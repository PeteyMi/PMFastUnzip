//
//  PMFastUnzip.h
//  PMFastUnzip
//
//  Created by Petey Mi on 2023/1/13.
//

#import <Foundation/Foundation.h>
#include <PMFastUnzip/unzip.h>

NS_ASSUME_NONNULL_BEGIN


@protocol PMFastUnzipDelegate <NSObject>

@optional
- (void)fastUnzipWillUnzipArchiveAtPath:(NSString *)path zipInfo:(unz_global_info)zipInfo;
- (void)fastUnzipDidUnzipArchiveAtPath:(NSString *)path zipInfo:(unz_global_info)zipInfo unzippedPath:(NSString *)unzippedPath;

- (void)fastUnzipWillUnzipFileAtIndex:(NSInteger)fileIndex filePath:(NSString *)filePath fileInfo:(unz_file_info)fileInfo;
- (void)fastUnzipDidUnzipFileAtIndex:(NSInteger)fileIndex filePath:(NSString *)filePath fileInfo:(unz_file_info)fileInfo;

@end

@interface PMFastUnzip : NSObject

+ (BOOL)fastUnzipFileAtPath:(NSString *)path toDestination:(NSString *)destination;
+ (BOOL)fastUnzipFileAtPath:(NSString *)path toDestination:(NSString *)destination overwrite:(BOOL)overwrite password:(nullable NSString *)password error:( NSError * _Nullable *)error;

+ (BOOL)fastUnzipFileAtPath:(NSString *)path toDestination:(NSString *)destination delegate:(nullable id<PMFastUnzipDelegate>)delegate;
+ (BOOL)fastUnzipFileAtPath:(NSString *)path toDestination:(NSString *)destination overwrite:(BOOL)overwrite password:(nullable NSString *)password error:( NSError * _Nullable *)error delegate:(nullable id<PMFastUnzipDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
