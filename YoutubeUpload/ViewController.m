//
//  ViewController.m
//  GoogleOAuth
//
//  Created by larryhou on 2018/3/1.
//  Copyright © 2018 larryhou. All rights reserved.
//

#import "ViewController.h"


@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [YouTubeUploader.sharedUploader requestAuthorization:^(OIDAuthState * _Nullable authState)
     {
         [self uploadSampleVideo];
     }];
}

- (void)uploadSampleVideo
{
    NSString* filename = @"Sample.mp4";
    NSString* filepath = [[NSBundle.mainBundle pathForResource:@"Youtube" ofType:@"bundle"] stringByAppendingPathComponent:filename];
    [YouTubeUploader.sharedUploader sendUploadRequest:filepath title:@"标题" description:@"描述"];
}

-(void)YouTubeUploader:(YouTubeUploader *)uploader progress:(float)progress
{
    NSLog(@"++ %5.2f%%", progress);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

