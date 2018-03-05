//
//  YouTubeUploader.m
//  YoutubeUpload
//
//  Created by larryhou on 2018/3/5.
//  Copyright © 2018 larryhou. All rights reserved.
//

#import "YouTubeUploader.h"

@interface YouTubeUploader()
{
    NSString * _filepath;
    NSString * _server;
    
    NSURLSession * _videoSession;
    id<OIDAuthorizationFlowSession> _flowSession;
    OIDAuthState * _auth;
    NSString * _token;
};

@property(nonatomic, readwrite) BOOL uploading;
@property(nonatomic, readwrite) UploadStatus status;
@end

@implementation YouTubeUploader

+ (instancetype)sharedUploader
{
    static YouTubeUploader *instance;
    static dispatch_once_t token;
    dispatch_once(&token,^{
        instance = [[YouTubeUploader alloc] init];
    });
    
    return instance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        _videoSession = [NSURLSession
                         sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                         delegate:self
                         delegateQueue:NSOperationQueue.mainQueue];
    }
    
    return self;
}

//MARK: auth
- (void)requestAuthorization:(void (^)(OIDAuthState* authState))completion
{
    if (_auth)
    {
        completion(_auth);
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
         [self requestAuthorization:configuration completion:completion];
     }];
}

- (UIViewController *)frontViewController
{
    UIViewController *topViewController = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (topViewController.presentedViewController)
    {
        topViewController = topViewController.presentedViewController;
    }
    return topViewController;
}

- (void)requestAuthorization:(OIDServiceConfiguration *)configuration
                  completion:(void (^)(OIDAuthState* authState))completion
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
    _flowSession =
    [OIDAuthState authStateByPresentingAuthorizationRequest:request
                                   presentingViewController:[self frontViewController]
                                                   callback:^(OIDAuthState *_Nullable authState,
                                                              NSError *_Nullable error)
     {
         if (authState)
         {
             NSLog(@"Got authorization tokens. Access token: %@ \n%@",authState.lastTokenResponse.accessToken, authState);
             _token = authState.lastTokenResponse.accessToken;
             _auth = authState;
             completion(authState);
         }
         else
         {
             NSLog(@"Authorization error: %@", [error localizedDescription]);
             _auth = nil;
         }
     }];
}


//MARK: API request
- (void)sendRequest:(NSString *)server
             method:(NSString *)method
             header:(NSDictionary<NSString*, NSString*> * _Nullable)header
            payload:(NSData * _Nullable)payload
         completion:(void (^)(NSHTTPURLResponse * _Nullable))completion
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:server]];
    request.HTTPMethod = method;
    
    if (header)
    {
        for (NSString* field in header)
        {
            [request addValue:header[field] forHTTPHeaderField:field];
        }
    }
    
    if (payload)
    {
        request.HTTPBody = payload;
    }
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
      {
          if (error == nil)
          {
              NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
              NSLog(@"%@", http);
              if (http.statusCode == 200)
              {
                  NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
              }
              completion(http);
          }
          else
          {
              NSLog(@"%@", error);
              completion(nil);
          }
      }] resume];
}

//MARK: check status
- (void)checkUploadStatus:(NSString *)server filepath:(NSString *)filepath completion:(void (^)(NSInteger))completion
{
    NSDictionary<NSFileAttributeKey, id>* attributes = [NSFileManager.defaultManager attributesOfItemAtPath:filepath error:nil];
    
    NSNumber* filesize = (NSNumber *)attributes[NSFileSize];
    NSDictionary *header = @{@"Authorization":[NSString stringWithFormat:@"Bearer %@", _token],
                             @"Content-Length":@0,
                             @"Content-Range":[NSString stringWithFormat:@"bytes */%@", filesize]
                             };
    [self sendRequest:server method:@"PUT" header:header payload:nil completion:^(NSHTTPURLResponse * _Nullable response)
    {
        if (response && response.statusCode == 308)
        {
            NSInteger offset = 0;
            NSString *field = response.allHeaderFields[@"Range"];
            if (field)
            {
                NSString *range = [[field componentsSeparatedByString:@"="] lastObject];
                if (range)
                {
                    offset = [[[range componentsSeparatedByString:@"-"] firstObject] integerValue];
                }
            }
            
            completion(offset);
        }
        else
        {
            completion(-1);
        }
    }];
}

//MARK: upload video
- (void)sendUploadRequest:(NSString *)filepath
                    title:(NSString *)title
              description:(NSString *)description
{
    _filepath = filepath;
    _server = nil;
    
    NSDictionary* metadata = @{@"snippet":@{
                                       @"categoryId":@20,
                                       @"description":description,
                                       @"title":title,
                                       @"tags":@[@"warsong", @"moba", @"action"]
                                       },
                               @"status":@{
                                       @"privacyStatus":@"public",
                                       @"embeddable":@YES,
                                       @"license":@"youtube"
                                       }
                               };
    NSDictionary<NSFileAttributeKey, id>* attributes = [NSFileManager.defaultManager attributesOfItemAtPath:filepath error:nil];
    
    NSNumber* filesize = (NSNumber *)attributes[NSFileSize];
    
    NSDictionary *header = @{@"Authorization":[NSString stringWithFormat:@"Bearer %@", _token],
                             @"Content-Type":@"application/json; charset=UTF-8",
                             @"X-Upload-Content-Length":[NSString stringWithFormat:@"%@", filesize],
                             @"X-Upload-Content-Type":@"video/*"
                             };
    
    NSData* payload = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:nil];
    
    [self sendRequest:YOUTUBE_UPLOAD_API method:@"POST" header:header payload:payload completion:^(NSHTTPURLResponse * _Nullable response)
    {
        if (response && response.statusCode == 200)
        {
            [self sendVideoContent:filepath filesize:filesize to:response.allHeaderFields[@"Location"]];
        }
    }];
}

- (void)resumeVideoContent:(NSString *)filepath
                        to:(NSString *)server
                    offset:(NSInteger)offset
{
    NSInteger position = offset + 1;
    NSData *bytes = [NSData dataWithContentsOfFile:filepath];
    NSData *payload = [bytes subdataWithRange:NSMakeRange(position, bytes.length - position)];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:server]];
    request.HTTPMethod = @"PUT";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", _token] forHTTPHeaderField:@"Authorization"];
    [request setValue:[NSString stringWithFormat:@"%lu", payload.length] forHTTPHeaderField:@"Content-Length"];
    [request setValue:[NSString stringWithFormat:@"bytes %lu-%lu/%lu", position, bytes.length - 1, bytes.length] forHTTPHeaderField:@"Content-Range"];
    request.HTTPBody = payload;
    
    [[_videoSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
      {
          if (error == nil)
          {
              NSLog(@"UPLOAD_RESUME %@", response);
              NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
              if (http.statusCode == 200)
              {
                  NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
              }
          }
          else
          {
              NSLog(@"error %@", error);
          }
      }] resume];
}

- (void)sendVideoContent:(NSString *)filepath
                filesize:(NSNumber *)filesize
                      to:(NSString *)server
{
    _server = server;
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:server]];
    request.HTTPMethod = @"PUT";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", _token] forHTTPHeaderField:@"Authorization"];
    [request setValue:[NSString stringWithFormat:@"%@", filesize] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"video/*" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSData dataWithContentsOfFile:filepath];
    
    [[_videoSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
      {
          if (error == nil)
          {
              NSLog(@"UPLOAD %@", response);
              NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
              if (http.statusCode == 200)
              {
                  NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
              }
          }
          else
          {
              NSLog(@"error %@", error);
          }
      }] resume];
}

//MARK: upload delegate
-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    NSLog(@"++ %5.2f%% %lld %lld", 100*(double)totalBytesSent / (double)totalBytesExpectedToSend, totalBytesSent, totalBytesExpectedToSend);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (_server && _filepath)
    {
        [self checkUploadStatus:_server filepath:_filepath completion:^(NSInteger offset)
        {
            if (offset >= 0)
            {
                [self resumeVideoContent:_filepath to:_server offset:offset];
            }
        }];
    }
}

@end