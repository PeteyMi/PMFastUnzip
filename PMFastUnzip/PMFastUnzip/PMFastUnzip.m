//
//  PMFastUnzip.m
//  PMFastUnzip
//
//  Created by Petey Mi on 2023/1/13.
//

#include <sys/stat.h>
#import <sys/sysctl.h>
#import <Foundation/Foundation.h>
#include "minizip/zip.h"
#include "minizip/unzip.h"
#import "zlib.h"

#import "PMFastUnzip.h"

static NSErrorDomain const PMFastUnzipErrorDomain = @"PMFastUnzipErrorDomain";
static NSUInteger const PMFastUnzipCountOfThread = 3; //


@interface PMFastUnzip () {
    unzFile _unzip;
    dispatch_queue_t    _queue;
}

@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *destination;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, assign) BOOL overwrite;

@property (nonatomic, readonly) BOOL isUsed;

+ (instancetype)createWithPath:(NSString *)path toDestination:(NSString *)destination overwrite:(BOOL)overwrite password:(NSString *)password error:(NSError **)error;

@end



@implementation PMFastUnzip

+ (BOOL)fastUnzipFileAtPath:(NSString *)path toDestination:(NSString *)destination {
    return [self fastUnzipFileAtPath:path toDestination:destination delegate:nil];
}
+ (BOOL)fastUnzipFileAtPath:(NSString *)path toDestination:(NSString *)destination overwrite:(BOOL)overwrite password:(NSString *)password error:(NSError **)error{
    return [self fastUnzipFileAtPath:path toDestination:destination overwrite:overwrite password:password error:error delegate:nil];
}

+ (BOOL)fastUnzipFileAtPath:(NSString *)path toDestination:(NSString *)destination delegate:(id<PMFastUnzipDelegate>)delegate {
    return [self fastUnzipFileAtPath:path toDestination:destination overwrite:YES password:nil error:nil delegate:delegate];
}
+ (BOOL)fastUnzipFileAtPath:(NSString *)path toDestination:(NSString *)destination overwrite:(BOOL)overwrite password:(NSString *)password error:(NSError **)error delegate:(id<PMFastUnzipDelegate>)delegate {

#ifdef DEBUG
    CFTimeInterval start = CFAbsoluteTimeGetCurrent();
#endif

    unzFile unzip = unzOpen((const char*)[path UTF8String]);
    if (unzip == NULL) {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"failed to open zip file"};
        if (error) {
            *error = [NSError errorWithDomain:PMFastUnzipErrorDomain code:-1 userInfo:userInfo];
        }
        return NO;
    }

    unz_global_info globalInfo = {0, 0};
    unzGetGlobalInfo(unzip, &globalInfo);

    if (unzGoToFirstFile(unzip) != UNZ_OK) {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"failed to open first file in zip file"};
        if (error) {
            *error = [NSError errorWithDomain:PMFastUnzipErrorDomain code:-2 userInfo:userInfo];
        }
        return NO;
    }

    NSUInteger countOfThread = PMFastUnzipCountOfThread;
    if (globalInfo.number_entry < countOfThread) {
        countOfThread = globalInfo.number_entry;
    }

    NSMutableArray *fastUnzipArray = [[NSMutableArray alloc] initWithCapacity:countOfThread];
    for (NSInteger index = 0; index < countOfThread; index++) {
        PMFastUnzip *fastUnzip = [self createWithPath:path toDestination:destination overwrite:overwrite password:password error:error];
        if (fastUnzip == nil) {
            return NO;
        }
        [fastUnzipArray addObject:fastUnzip];
    }

    if (delegate && [delegate respondsToSelector:@selector(fastUnzipWillUnzipArchiveAtPath:zipInfo:)]) {
        [delegate fastUnzipWillUnzipArchiveAtPath:path zipInfo:globalInfo];
    }

    BOOL success = YES;
    int ret = 0;
    __block BOOL isUnzipError = NO;
    NSMutableSet *directoriesModificationDates = [[NSMutableSet alloc] init];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(countOfThread - 1);
    dispatch_group_t group = dispatch_group_create();

    do {
        unz_file_pos filePos = {0, 0};
        ret = unzGetFilePos(unzip, &filePos);
        if (ret != UNZ_OK) {
            success = NO;
            break;
        }

        PMFastUnzip *fastUnzip = [self findCanUseUnzipFromArray:fastUnzipArray];
        dispatch_group_enter(group);
        [fastUnzip fastUnzipAtPos:filePos delegate:delegate completion:^(BOOL success, NSArray *directoryModificationDates) {
            if (success) {
                if (directoryModificationDates) {
                    @synchronized (directoriesModificationDates) {
                        [directoriesModificationDates addObjectsFromArray:directoryModificationDates];
                    }
                }
            } else {
                isUnzipError = YES;
            }
            dispatch_group_leave(group);
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        if (isUnzipError) {
            break;
        }

        ret = unzGoToNextFile(unzip);
    } while (ret == UNZ_OK && UNZ_OK != UNZ_END_OF_LIST_OF_FILE);

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // Close
    unzClose(unzip);

    // The process of decompressing the .zip archive causes the modification times on the folders
    // to be set to the present time. So, when we are done, they need to be explicitly set.
    // set the modification date on all of the directories.
    NSError * err = nil;
    for (NSDictionary * d in directoriesModificationDates) {
        if (![NSFileManager.defaultManager setAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[d objectForKey:@"modDate"], NSFileModificationDate, nil] ofItemAtPath:[d objectForKey:@"path"] error:&err]) {
            NSLog(@"[PMFastUnzip] Set attributes failed for directory: %@.", [d objectForKey:@"path"]);
        }
        if (err) {
            NSLog(@"[PMFastUnzip] Error setting directory file modification date attribute: %@",err.localizedDescription);
        }
    }

    // Message delegate
    if (success && [delegate respondsToSelector:@selector(fastUnzipDidUnzipArchiveAtPath:zipInfo:unzippedPath:)]) {
        [delegate fastUnzipDidUnzipArchiveAtPath:path zipInfo:globalInfo unzippedPath:destination];
    }

#ifdef DEBUG
    CFTimeInterval interval = CFAbsoluteTimeGetCurrent() - start;
    NSLog(@"Unzip time: %f", interval);
#endif

    return success;
}

+ (PMFastUnzip*)findCanUseUnzipFromArray:(NSArray<PMFastUnzip*>*) array {
    for (PMFastUnzip *fastUnzip in array) {
        if (fastUnzip.isUsed == NO) {
            return fastUnzip;
        }
    }
    return nil;
}

+ (instancetype)createWithPath:(NSString *)path toDestination:(NSString *)destination overwrite:(BOOL)overwrite password:(NSString *)password error:(NSError **)error {

    unzFile unzip = unzOpen((const char*)[path UTF8String]);
    if (unzip == NULL) {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"failed to open zip file"};
        if (error) {
            *error = [NSError errorWithDomain:PMFastUnzipErrorDomain code:-1 userInfo:userInfo];
        }
        return nil;
    }
    return [[self alloc] initWithUnzip:unzip toDestination:destination overwrite:overwrite password:password];
}

- (id)initWithUnzip:(unzFile)unzip toDestination:(NSString *)destination overwrite:(BOOL)overwrite password:(NSString *)password {
    if (self = [super init]) {
        _unzip = unzip;
        _destination = destination;
        _overwrite = overwrite;
        _password = password;
        _isUsed = NO;
        _queue = dispatch_queue_create("PMFastUnzip.queue.com", NULL);
    }
    return self;
}

- (void)dealloc {
    if (_unzip) {
        unzClose(_unzip);
        _unzip = NULL;
    }
}

- (void)fastUnzipAtPos:(unz_file_pos)filePos delegate:(nullable id<PMFastUnzipDelegate>)delegate  completion:(void(^)(BOOL success, NSArray *directoryModificationDates))completion {
    _isUsed = YES;
    dispatch_async(_queue, ^{
        [self _fastUnzipAtPos:filePos delegate:delegate completion:completion];
    });
}

- (void)_fastUnzipAtPos:(unz_file_pos)filePos delegate:(nullable id<PMFastUnzipDelegate>)delegate completion:(void(^)(BOOL success, NSArray *directoryModificationDates))completion {

    unzGoToFilePos(_unzip, &filePos);

    int ret = 0;
    unsigned char buffer[4096] = {0};
    NSMutableSet *directoryModificationDates = [[NSMutableSet alloc] init];

    if (_password.length == 0) {
        ret = unzOpenCurrentFile(_unzip);
    } else {
        ret = unzOpenCurrentFilePassword(_unzip, [_password cStringUsingEncoding:NSASCIIStringEncoding]);
    }

    if (ret != UNZ_OK) {
        _isUsed = NO;
        completion ? completion(NO, nil) : nil;
        return;
    }

    unz_file_info fileInfo;
    memset(&fileInfo, 0, sizeof(unz_file_info));

    ret = unzGetCurrentFileInfo(_unzip, &fileInfo, NULL, 0, NULL, 0, NULL, 0);
    if (ret != UNZ_OK) {
        unzCloseCurrentFile(_unzip);
        _isUsed = NO;
        completion ? completion(NO, nil) : nil;
        return;
    }

    char *fileName = (char*)malloc(fileInfo.size_filename + 1);
    unzGetCurrentFileInfo(_unzip, &fileInfo, fileName, fileInfo.size_filename + 1, NULL, 0, NULL, 0);
    fileName[fileInfo.size_filename] = '\0';

    const uLong ZipCompressionMethodStore = 0;

    BOOL fileIsSymbolicLink = NO;

    if((fileInfo.compression_method == ZipCompressionMethodStore) && // Is it compressed?
       (S_ISDIR(fileInfo.external_fa)) && // Is it marked as a directory
       (fileInfo.compressed_size > 0)) // Is there any data?
    {
        fileIsSymbolicLink = YES;
    }

    // Check if it contains directory
    NSString *strPath = [NSString stringWithCString:fileName encoding:NSUTF8StringEncoding];
    BOOL isDirectory = NO;
    if (fileName[fileInfo.size_filename - 1] == '/' || fileName[fileInfo.size_filename - 1] == '\\') {
        isDirectory = YES;
    }
    free(fileName);

    // Message delegate
    if ([delegate respondsToSelector:@selector(fastUnzipWillUnzipFileAtIndex:filePath:fileInfo:)]) {
        [delegate fastUnzipWillUnzipFileAtIndex:filePos.num_of_file filePath:strPath fileInfo:fileInfo];
    }

    // Contains a path
    if ([strPath rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"]].location != NSNotFound) {
        strPath = [strPath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    }

    NSString *fullPath = [_destination stringByAppendingPathComponent:strPath];
    NSError *err = nil;
    NSDate *modDate = [self _dateWithMSDOSFormat:(UInt32)fileInfo.dosDate];
    NSDictionary *directoryAttr = [NSDictionary dictionaryWithObjectsAndKeys:modDate, NSFileCreationDate, modDate, NSFileModificationDate, nil];

    if (isDirectory) {
        [NSFileManager.defaultManager createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:directoryAttr  error:&err];
    } else {
        [NSFileManager.defaultManager createDirectoryAtPath:[fullPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:directoryAttr error:&err];
    }
    if (nil != err) {
        NSLog(@"[PMFastUnzip] Error: %@", err.localizedDescription);
    }

    if(!fileIsSymbolicLink)
        [directoryModificationDates addObject: [NSDictionary dictionaryWithObjectsAndKeys:fullPath, @"path", modDate, @"modDate", nil]];

    if ([NSFileManager.defaultManager fileExistsAtPath:fullPath] && !isDirectory && !_overwrite) {
        unzCloseCurrentFile(_unzip);
        _isUsed = NO;
        completion ? completion(YES, directoryModificationDates.allObjects) : nil;
        return;
    }

    if(!fileIsSymbolicLink) {
        FILE *fp = fopen((const char*)[fullPath UTF8String], "wb");
        while (fp) {
            int readBytes = unzReadCurrentFile(_unzip, buffer, 4096);

            if (readBytes > 0) {
                fwrite(buffer, readBytes, 1, fp );
            } else {
                break;
            }
        }

        if (fp) {
            fclose(fp);

            // Set the original datetime property
            if (fileInfo.dosDate != 0) {
                NSDate *orgDate = [self _dateWithMSDOSFormat:(UInt32)fileInfo.dosDate];
                NSDictionary *attr = [NSDictionary dictionaryWithObject:orgDate forKey:NSFileModificationDate];

                if (attr) {
                    if ([NSFileManager.defaultManager setAttributes:attr ofItemAtPath:fullPath error:nil] == NO) {
                        // Can't set attributes
                        NSLog(@"[PMFastUnzip] Failed to set attributes");
                    }
                }
            }
        }
    } else {
        // Get the path for the symbolic link
        NSURL* symlinkURL = [NSURL fileURLWithPath:fullPath];
        NSMutableString* destinationPath = [NSMutableString string];

        int bytesRead = 0;
        while((bytesRead = unzReadCurrentFile(_unzip, buffer, 4096)) > 0) {
            buffer[bytesRead] = 0;
            [destinationPath appendString:[NSString stringWithUTF8String:(const char*)buffer]];
        }

        NSURL* destinationURL = [NSURL fileURLWithPath:destinationPath];

        // Create the symbolic link
        NSError* symlinkError = nil;
        [NSFileManager.defaultManager createSymbolicLinkAtURL:symlinkURL withDestinationURL:destinationURL error:&symlinkError];

        if(symlinkError != nil) {
            NSLog(@"Failed to create symbolic link at \"%@\" to \"%@\". Error: %@", symlinkURL.absoluteString, destinationURL.absoluteString, symlinkError.localizedDescription);
        }
    }

    unzCloseCurrentFile(_unzip);

    // Message delegate
    if ([delegate respondsToSelector:@selector(fastUnzipDidUnzipFileAtIndex:filePath:fileInfo:)]) {
        [delegate fastUnzipDidUnzipFileAtIndex:filePos.num_of_file filePath:strPath fileInfo:fileInfo];
    }
    _isUsed = NO;
    completion ? completion(YES, directoryModificationDates.allObjects) : nil;
}

// Format from http://newsgroups.derkeiler.com/Archive/Comp/comp.os.msdos.programmer/2009-04/msg00060.html
// Two consecutive words, or a longword, YYYYYYYMMMMDDDDD hhhhhmmmmmmsssss
// YYYYYYY is years from 1980 = 0
// sssss is (seconds/2).
//
// 3658 = 0011 0110 0101 1000 = 0011011 0010 11000 = 27 2 24 = 2007-02-24
// 7423 = 0111 0100 0010 0011 - 01110 100001 00011 = 14 33 2 = 14:33:06
- (NSDate *)_dateWithMSDOSFormat:(UInt32)msdosDateTime {
    static const UInt32 kYearMask = 0xFE000000;
    static const UInt32 kMonthMask = 0x1E00000;
    static const UInt32 kDayMask = 0x1F0000;
    static const UInt32 kHourMask = 0xF800;
    static const UInt32 kMinuteMask = 0x7E0;
    static const UInt32 kSecondMask = 0x1F;

    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [[NSDateComponents alloc] init];

    NSAssert(0xFFFFFFFF == (kYearMask | kMonthMask | kDayMask | kHourMask | kMinuteMask | kSecondMask), @"[PMFastUnzip] MSDOS date masks don't add up");

    [components setYear:1980 + ((msdosDateTime & kYearMask) >> 25)];
    [components setMonth:(msdosDateTime & kMonthMask) >> 21];
    [components setDay:(msdosDateTime & kDayMask) >> 16];
    [components setHour:(msdosDateTime & kHourMask) >> 11];
    [components setMinute:(msdosDateTime & kMinuteMask) >> 5];
    [components setSecond:(msdosDateTime & kSecondMask) * 2];

    NSDate *date = [NSDate dateWithTimeInterval:0 sinceDate:[gregorian dateFromComponents:components]];

    return date;
}

@end


