//
//  ViewController.h
//  AutoVolume
//
//  Created by Derek Chen on 11/20/14.
//  Copyright (c) 2014 Derek Chen. All rights reserved.
//

@import MapKit;
#import <UIKit/UIKit.h>
#import "JPSThumbnailAnnotation.h"

@interface ViewController : UIViewController<MKMapViewDelegate, CLLocationManagerDelegate, UIActionSheetDelegate>
{
    MKMapView *myMapView;
    MKPointAnnotation *myLocation;
    CLLocationManager* locationManager;
    BOOL regionMonitored;
    UIBarButtonItem *pinButton;
    
    float officeVolume, homeVolume;
    
    JPSThumbnail *office;
    JPSThumbnail *home;
    JPSThumbnail *theLastThumbnail;
    id officeAnnotation;
    id homeAnnotation;
    JPSThumbnailAnnotationView *officeView;
    JPSThumbnailAnnotationView *homeView;
    JPSThumbnailAnnotationView *theLastAnnotationView;
    CLCircularRegion *officeRegion;
    CLCircularRegion *homeRegion;
    NSTimer *timer;
    
    BOOL insideHome, insideOffice;
}

@property (nonatomic, strong) UISlider *volumeSlider;

@end

