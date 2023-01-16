//
//  ViewController.m
//  PMFastUnzipDemo
//
//  Created by Petey Mi on 2023/1/13.
//

#import <PMFastUnzip/PMFastUnzip.h>
#import "ViewController.h"

@interface ViewController ()<PMFastUnzipDelegate>

@end

@implementation ViewController

- (NSString *)docPath {
    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths objectAtIndex:0];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    NSString *path = [NSBundle.mainBundle pathForResource:@"loan" ofType:@".zip"];

    NSString *destination = [self docPath];
    destination = [destination stringByAppendingFormat:@"/home"];

    NSLog(@"destination: %@", destination);
    [PMFastUnzip fastUnzipFileAtPath:path toDestination:destination delegate:self];
}

- (void)fastUnzipWillUnzipArchiveAtPath:(NSString *)path zipInfo:(unz_global_info)zipInfo {
    NSLog(@"开始解压文件:%@ 总文件个数:%lu", path, zipInfo.number_entry);
}

- (void)fastUnzipDidUnzipArchiveAtPath:(NSString *)path zipInfo:(unz_global_info)zipInfo unzippedPath:(NSString *)unzippedPath {
    NSLog(@"完成解压文件:%@ 总文件个数:%lu 解压文件路径:%@", path, zipInfo.number_entry, unzippedPath);
}

//- (void)fastUnzipWillUnzipFileAtIndex:(NSInteger)fileIndex filePath:(NSString *)filePath fileInfo:(unz_file_info)fileInfo {
//    NSLog(@"将要解压第%lu文件: %@", fileIndex, filePath);
//}
//- (void)fastUnzipDidUnzipFileAtIndex:(NSInteger)fileIndex filePath:(NSString *)filePath fileInfo:(unz_file_info)fileInfo {
//    NSLog(@"完成解压第%lu文件: %@", fileIndex, filePath);
//}

@end
