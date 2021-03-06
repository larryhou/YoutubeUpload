//
//  YouTubeUploader.m
//  YoutubeUpload
//
//  Created by larryhou on 2018/3/5.
//  Copyright © 2018 larryhou. All rights reserved.
//

#import "YouTubeUploader.h"
#import "Reachability.h"

@interface YouTubeUploader()
{
    NSString * _filepath;
    NSString * _server;
    
    NSURLSession * _videoSession;
    id<OIDAuthorizationFlowSession> _flowSession;
    OIDAuthState * _auth;
    NSString * _token;
    
    int _retryCount;
};

@property(nonatomic, readwrite) BOOL uploading;
@property(nonatomic, readwrite) UploadStatus status;
@end

@implementation YouTubeUploader

- (void)setStatus:(UploadStatus)status
{
    _status = status;
    if ([_delegate respondsToSelector:@selector(YouTubeUploader:status:)])
    {
        [_delegate YouTubeUploader:self status:_status];
    }
}

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
        _videoSession = [self createVideoSession];
        [self setStatus:UploadStatusNone];
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
    [self setStatus:UploadStatusDiscover];
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
    [self setStatus:UploadStatusAuthorize];
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
             header:(NSDictionary<NSString*, id> * _Nullable)header
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
- (void)checkUploadStatus:(NSString *)filepath
                   server:(NSString *)server
               completion:(void (^)(NSInteger position, BOOL complete))completion
{
    NSNumber* filesize = [self sizeOf:filepath];
    NSDictionary *header = @{@"Authorization":[NSString stringWithFormat:@"Bearer %@", _token],
                             @"Content-Length":@"0",
                             @"Content-Range":[NSString stringWithFormat:@"bytes */%@", filesize]
                             };
    [self sendRequest:server method:@"PUT" header:header payload:nil completion:^(NSHTTPURLResponse * _Nullable response)
    {
        NSInteger position = -1;
        if (response && response.statusCode == 308)
        {
            NSString *field = response.allHeaderFields[@"Range"];
            if (field)
            {
                NSString *range = [[field componentsSeparatedByString:@"="] lastObject];
                if (range)
                {
                    NSInteger offset = [[[range componentsSeparatedByString:@"-"] lastObject] integerValue];
                    if (offset > 0) { position = offset + 1; }
                }
            }
            
            completion(position, position == filesize.integerValue);
        }
        else
        {
            if (response)
            {
                completion(position, NO);
            }
            else
            {
                if (_status == UploadStatusCompletionCheck)
                {
                    [self checkInternetAndContinue];
                }
            }
        }
    }];
}

- (NSNumber *)sizeOf:(NSString *)filepath
{
    NSDictionary<NSFileAttributeKey, id>* attributes = [NSFileManager.defaultManager attributesOfItemAtPath:filepath error:nil];
    return (NSNumber *)attributes[NSFileSize];
}

//MARK: upload video
- (void)cancelCurrentUpload
{
    _status = UploadStatusCanceled;
    [_videoSession invalidateAndCancel];
    _videoSession = [self createVideoSession];
}

- (NSURLSession *)createVideoSession
{
    return [NSURLSession
            sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
            delegate:self
            delegateQueue:NSOperationQueue.mainQueue];
}

- (void)sendUploadRequest:(NSString *)filepath
                    title:(NSString *)title
              description:(NSString *)description
{
    _filepath = filepath;
    _server = nil;
    [self setStatus:UploadStatusConfigurate];
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
    
    NSNumber* filesize = [self sizeOf:filepath];
    NSDictionary *header = @{@"Authorization":[NSString stringWithFormat:@"Bearer %@", _token],
                             @"Content-Type":@"application/json; charset=UTF-8",
                             @"X-Upload-Content-Length":[NSString stringWithFormat:@"%@", filesize],
                             @"X-Upload-Content-Type":@"video/*"
                             };
    
    NSData* payload = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:nil];
    
    [self sendRequest:YOUTUBE_UPLOAD_API method:@"POST" header:header payload:payload completion:^(NSHTTPURLResponse * _Nullable response)
    {
        if (_status == UploadStatusCanceled) {return;}
        
        if (response && response.statusCode == 200)
        {
            [self sendVideoContent:filepath to:response.allHeaderFields[@"Location"]];
        }
    }];
}

- (void)resumeVideoContent:(NSString *)filepath
                        to:(NSString *)server
                    position:(NSInteger)position
{
    [self setStatus:UploadStatusUpload];
    NSData *bytes = [NSData dataWithContentsOfFile:filepath];
    NSData *payload = [bytes subdataWithRange:NSMakeRange(position, bytes.length - position)];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:server]];
    request.HTTPMethod = @"PUT";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", _token] forHTTPHeaderField:@"Authorization"];
    [request setValue:[NSString stringWithFormat:@"%ld", payload.length] forHTTPHeaderField:@"Content-Length"];
    [request setValue:[NSString stringWithFormat:@"bytes %ld-%ld/%ld", position, bytes.length - 1, bytes.length] forHTTPHeaderField:@"Content-Range"];
    request.HTTPBody = payload;
    
    _uploading = YES;
    [[_videoSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
      {
          _uploading = NO;
          [self processUploadCompletion:data response:response error:error];
      }] resume];
}

- (void)sendVideoContent:(NSString *)filepath
                      to:(NSString *)server
{
    _retryCount = 0;
    _server = server;
    
    [self setStatus:UploadStatusUpload];
    NSNumber *filesize = [self sizeOf:filepath];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:server]];
    request.HTTPMethod = @"PUT";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", _token] forHTTPHeaderField:@"Authorization"];
    [request setValue:[NSString stringWithFormat:@"%@", filesize] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"video/*" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSData dataWithContentsOfFile:filepath];
    
    _uploading = YES;
    [[_videoSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
      {
          _uploading = NO;
          [self processUploadCompletion:data response:response error:error];
      }] resume];
}

- (void)processUploadCompletion:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error
{
    if (_status == UploadStatusCanceled) {return;}
    
    if (error == nil)
    {
        NSLog(@"UPLOAD %@", response);
        NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode == 200)
        {
            NSLog(@"%@", message);
            [self setStatus:UploadStatusComplete];
            [self alertWithTitle:@"upload success" message:nil];
            if ([_delegate respondsToSelector:@selector(YouTubeUploader:complete:)])
            {
                [_delegate YouTubeUploader:self complete:message];
            }
        }
        else
        {
            [self setStatus:UploadStatusError];
            [self alertWithTitle:[NSString stringWithFormat:@"%ld", http.statusCode]
                         message:message];
            
            if ([_delegate respondsToSelector:@selector(YouTubeUploader:failWithCode:)])
            {
                [_delegate YouTubeUploader:self failWithCode:http.statusCode];
            }
        }
    }
    else
    {
        NSLog(@"error %@", error);
        [self alertWithTitle:@"error" message:nil];
        [self setStatus:UploadStatusCompletionCheck];
        [self processInternetError:error];
    }
}

- (void)processInternetError:(NSError *)error
{
    if ([_delegate respondsToSelector:@selector(YouTubeUploader:error:)])
    {
        [_delegate YouTubeUploader:self error:error];
    }
    
    if (++_retryCount >= 3)
    {
        [self alertWithTitle:@"upload error" message:error.localizedDescription];
    }
    else
    {
        if (_status == UploadStatusCompletionCheck)
        {
            [self checkInternetAndContinue];
        }
    }
}

//MARK: alert
- (void)alertWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [[self frontViewController] presentViewController:alert animated:true completion:nil];
}

//MARK: upload delegate
-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    float progress = (float)(100*(double)totalBytesSent / (double)totalBytesExpectedToSend);
    if ([_delegate respondsToSelector:@selector(YouTubeUploader:progress:)])
    {
        [_delegate YouTubeUploader:self progress:progress];
    }
    
    NSLog(@"++ %5.2f%% %lld %lld", 100*(double)totalBytesSent / (double)totalBytesExpectedToSend, totalBytesSent, totalBytesExpectedToSend);
}

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error
{
    [self setStatus:UploadStatusError];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (_status == UploadStatusCanceled) {return;}
    
    [self setStatus:UploadStatusError];
    
    if (_server && _filepath)
    {
        [self setStatus:UploadStatusCompletionCheck];
        [self processInternetError:error];
    }
}

- (void)checkCompletionAndContinue
{
    [self checkUploadStatus:_filepath server:_server completion:^(NSInteger position, BOOL complete)
     {
         if (complete)
         {
             [self setStatus:UploadStatusComplete];
         }
         else
         {
             
             [self resumeVideoContent:_filepath to:_server position:MAX(0, position)];
         }
     }];
}

//MARK: network monitor
- (void)checkInternetAndContinue
{
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(networkReachabilityChange:) name:kReachabilityChangedNotification object:nil];
    
    Reachability *reachability = [Reachability reachabilityForInternetConnection];
    [reachability startNotifier];
    
    [self tryContinue:reachability];
}

- (void)networkReachabilityChange:(NSNotification *)note
{
    Reachability *reachability = note.object;
    NSLog(@"NETWORK_CHANGE:%ld", (long)reachability.currentReachabilityStatus);
    [self tryContinue:reachability];
}

- (void)tryContinue:(Reachability *)reachability
{
    if (reachability.currentReachabilityStatus != NotReachable)
    {
        [reachability stopNotifier];
        [NSNotificationCenter.defaultCenter removeObserver:self name:kReachabilityChangedNotification object:nil];
        if (_status == UploadStatusCompletionCheck)
        {
            [self checkCompletionAndContinue];
        }
    }
}

@end
