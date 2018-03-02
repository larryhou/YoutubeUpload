//
//  ViewController.h
//  GoogleOAuth
//
//  Created by larryhou on 2018/3/1.
//  Copyright © 2018 larryhou. All rights reserved.
//

#import <UIKit/UIKit.h>
@import AppAuth;

@interface ViewController : UIViewController<NSURLSessionDataDelegate>

@property(nonatomic, strong, nullable) OIDAuthState *accountAuth;
@property (nonatomic, strong, nullable) id<OIDAuthorizationFlowSession> authorizationSession;
@end
