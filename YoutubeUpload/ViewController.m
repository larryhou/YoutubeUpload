//
//  ViewController.m
//  GoogleOAuth
//
//  Created by larryhou on 2018/3/1.
//  Copyright © 2018 larryhou. All rights reserved.
//

#import "ViewController.h"
#import "AppDelegate.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    //    [self discorverServiceConfiguration];
    // Do any additional setup after loading the view, typically from a nib.
    [self requestAuthorization:^(OIDAuthState *authState)
     {
         [self uploadSampleVideo];
     }];
}

- (void)requestAuthorization:(void (^)(OIDAuthState* authState))completionHandler
{
    if (_accountAuth)
    {
        completionHandler(_accountAuth);
        return;
    }
    
    NSURL *issuer = [NSURL URLWithString:@"https://accounts.google.com"];
    [OIDAuthorizationService discoverServiceConfigurationForIssuer:issuer
                                                        completion:^(OIDServiceConfiguration *_Nullable configuration, NSError *_Nullable error)
     {
         if (!configuration)
         {
             NSLog(@"Error retrieving discovery document: %@",
                   [error localizedDescription]);
             return;
         }
         NSLog(@"%@", configuration);
         [self requestAuthorization:configuration completionHandler:completionHandler];
     }];
}

- (void)requestAuthorization:(OIDServiceConfiguration *)configuration completionHandler:(void (^)(OIDAuthState* authState))completionHandler
{
    NSString* plist = [[NSBundle.mainBundle pathForResource:@"Youtube" ofType:@"bundle"] stringByAppendingPathComponent:@"client-id-iOS.plist"];
    NSDictionary* data = [[NSDictionary alloc] initWithContentsOfFile:plist];
    NSLog(@"CLIENT_ID_INFO:%@", data);
    
    NSString* kClientID = data[@"CLIENT_ID"];
    NSURL* kRedirectURI = [NSURL URLWithString:[NSString stringWithFormat:@"%@:/oauth2redirect", data[@"REVERSED_CLIENT_ID"]]];
    
    // builds authentication request
    OIDAuthorizationRequest *request =
    [[OIDAuthorizationRequest alloc] initWithConfiguration:configuration
                                                  clientId:kClientID
                                                    scopes:@[OIDScopeOpenID,
                                                             OIDScopeProfile,
                                                             @"https://www.googleapis.com/auth/youtube.upload"]
                                               redirectURL:kRedirectURI
                                              responseType:OIDResponseTypeCode
                                      additionalParameters:nil];
    // performs authentication request
    self.authorizationSession =
    [OIDAuthState authStateByPresentingAuthorizationRequest:request
                                   presentingViewController:self
                                                   callback:^(OIDAuthState *_Nullable authState,
                                                              NSError *_Nullable error)
     {
         if (authState)
         {
             NSLog(@"Got authorization tokens. Access token: %@ \n%@",authState.lastTokenResponse.accessToken, authState);
             [self setAccountAuth:authState];
             completionHandler(authState);
         }
         else
         {
             NSLog(@"Authorization error: %@", [error localizedDescription]);
             [self setAccountAuth:nil];
         }
     }];
}

- (void)uploadSampleVideo
{
    NSString* filename = @"Sample.mp4";
    NSString* filepath = [[NSBundle.mainBundle pathForResource:@"Youtube" ofType:@"bundle"] stringByAppendingPathComponent:filename];
    [self sendUploadRequest:filepath token:_accountAuth.lastTokenResponse.accessToken];
}

- (void)sendUploadRequest:(NSString *)path token:(NSString *)token
{
    NSDictionary* metadata = @{@"snippet":@{
                                       @"categoryId":@20,
                                       @"description":@"Warsong游戏太好玩啦，根本停不下来！",
                                       @"title":@"大杀特杀",
                                       @"tags":@[@"warsong", @"moba", @"action"]
                                       },
                               @"status":@{
                                       @"privacyStatus":@"public",
                                       @"embeddable":@YES,
                                       @"license":@"youtube"
                                       }
                               };
    NSURL* server = [NSURL URLWithString:@"https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status"];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:server];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    
    NSDictionary<NSFileAttributeKey, id>* attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    NSNumber* size = (NSNumber *)attributes[NSFileSize];
    [request setValue:[NSString stringWithFormat:@"%@", size] forHTTPHeaderField:@"X-Upload-Content-Length"];
    [request setValue:@"video/*" forHTTPHeaderField:@"X-Upload-Content-Type"];
    
    NSData* payload = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:nil];
    NSLog(@"%@", [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding]);
    request.HTTPBody = payload;
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
      {
          if (error == nil)
          {
              NSLog(@"response %@", response);
              NSHTTPURLResponse* http = (NSHTTPURLResponse *)response;
              [self sendVideoContent:path to:http.allHeaderFields[@"Location"] token:token size:size];
          }
          else
          {
              NSLog(@"error %@", error);
          }
      }] resume];
}

- (void)sendVideoContent:(NSString *)path to:(NSString *)server token:(NSString *)token size:(NSNumber *)size
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:server]];
    request.HTTPMethod = @"PUT";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:[NSString stringWithFormat:@"%@", size] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"video/*" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSData dataWithContentsOfFile:path];
    
    NSURLSession* session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration delegate:self delegateQueue:NSOperationQueue.mainQueue];
    
    [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
      {
          if (error == nil)
          {
              NSLog(@"response %@", response);
          }
          else
          {
              NSLog(@"error %@", error);
          }
      }] resume];
}

-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    NSLog(@"++ %5.2f%% %lld %lld", 100*(double)totalBytesSent / (double)totalBytesExpectedToSend, totalBytesSent, totalBytesExpectedToSend);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

