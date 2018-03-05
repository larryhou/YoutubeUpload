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
    UploadStatusDiscover,
    UploadStatusAuthorize,
    UploadStatusConfigurate,
    UploadStatusUpload,
    UploadStatusIntegrityCheck,
    UploadStatusComplete,
    UploadStatusError
};

@class YouTubeUploader;
@protocol YouTubeUploaderDelegate<NSObject>

@optional
- (void)YouTubeUploader:(YouTubeUploader * _Nonnull)uploader status:(UploadStatus)status;

@optional
- (void)YouTubeUploader:(YouTubeUploader * _Nonnull)uploader progress: (float)progress;
@end

@interface YouTubeUploader : NSObject<NSURLSessionDataDelegate>

@property(nonatomic, readonly) BOOL uploading;
@property(nonatomic, readonly) UploadStatus status;
@property(nonatomic, strong, nullable) id<YouTubeUploaderDelegate> delegate;

+ (instancetype _Nonnull)sharedUploader;

- (void)requestAuthorization:(void (^_Nonnull)(OIDAuthState* _Nullable authState))completion;

- (void)sendUploadRequest:(NSString * _Nonnull)filepath
                    title:(NSString * _Nonnull)title
              description:(NSString * _Nonnull)description;

- (void)sendVideoContent:(NSString * _Nonnull)filepath
                      to:(NSString * _Nonnull)server;

- (void)checkUploadStatus:(NSString * _Nonnull)server
                 filepath:(NSString * _Nonnull)filepath
               completion:(void (^_Nonnull)(NSInteger offset, BOOL complete))completion;

- (void)resumeVideoContent:(NSString * _Nonnull)filepath
                        to:(NSString * _Nonnull)server
                    offset:(NSInteger)offset;
@end
