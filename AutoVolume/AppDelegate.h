//
//  AppDelegate.h
//  AutoVolume
//
//  Created by Derek Chen on 11/20/14.
//  Copyright (c) 2014 Derek Chen. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>{
    UIBackgroundTaskIdentifier bgTask;
    //NSTimer *timer;
}

@property (strong, nonatomic) UIWindow *window;

@end

