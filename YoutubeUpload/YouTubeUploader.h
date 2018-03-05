//
//  YouTubeUploader.h
//  YoutubeUpload
//
//  Created by larryhou on 2018/3/5.
//  Copyright © 2018 larryhou. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <AppAuth/AppAuth.h>

#define YOUTUBE_UPLOAD_API @"https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status"

typedef NS_ENUM(NSInteger, UploadStatus)
{
    UploadStatusNone = 0,
    UploadStatusAuthorize,
    UploadStatusConfig,
    UploadStatusUpload,
    UploadStatusFinish,
    UploadStatusError
};

@interface YouTubeUploader : NSObject<NSURLSessionDataDelegate>

@property(nonatomic, readonly) BOOL uploading;
@property(nonatomic, readonly) UploadStatus status;

+ (instancetype _Nonnull)sharedUploader;

- (void)requestAuthorization:(void (^_Nonnull)(OIDAuthState* _Nullable authState))completion;

- (void)sendUploadRequest:(NSString * _Nonnull)filepath
                    title:(NSString * _Nonnull)title
              description:(NSString * _Nonnull)description;

- (void)sendVideoContent:(NSString * _Nonnull)filepath
                filesize:(NSNumber * _Nonnull)filesize
                      to:(NSString * _Nonnull)server;

- (void)resumeVideoContent:(NSString * _Nonnull)filepath
                        to:(NSString * _Nonnull)server
                    offset:(NSInteger)offset;
@end
