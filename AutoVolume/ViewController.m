//
//  ViewController.m
//  AutoVolume
//
//  Created by Derek Chen on 11/20/14.
//  Copyright (c) 2014 Derek Chen. All rights reserved.
//

#import "ViewController.h"
#import "AVSystemController.h"
#import "MKMapView+ZoomLevel.h"
#import "sqlite3.h"

@interface ViewController ()

/**
 *  contentView.superView = transitionView;
 *  subContentView.superView = transitionView;
 *  transitionView.superView = self.view;
 *  用来调整frame，适配ios7
 */
@property (nonatomic, strong) UIView *transitionView;

@end

@implementation ViewController

#define IOS_VERSION [[[UIDevice currentDevice] systemVersion] floatValue]
#define isPad (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)

- (UIView *)transitionView
{
    if (!_transitionView) {
        //创建 transitionView
        _transitionView = [[UIView alloc] initWithFrame:self.view.bounds];
        _transitionView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        
        /**
         *  iOS7 适配
         */
        if (IOS_VERSION >= 7.0) {
            CGRect frame = _transitionView.frame;
            frame.origin.y += 20;
            frame.size.height -= 20;
            _transitionView.frame = frame;
            
            //statusBar用黑色背景
            UIView *statusBarBackground = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 20)];
            statusBarBackground.backgroundColor = [UIColor colorWithRed:(247/255.0) green:(247/255.0) blue:(247/255.0) alpha:1];
            statusBarBackground.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [self.view addSubview:statusBarBackground];
            
            [self setNeedsStatusBarAppearanceUpdate];
        }
        
        [self.view addSubview:_transitionView];
    }
    return _transitionView;
}

/**
 Inform CLLocationManager to start sending us updates to our location.
 */
- (void)askLocationPermission
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_7_1
    // As of iOS 8, apps must explicitly request location services permissions. INTULocationManager supports both levels, "Always" and "When In Use".
    // INTULocationManager determines which level of permissions to request based on which description key is present in your app's Info.plist
    // If you provide values for both description keys, the more permissive "Always" level is requested.
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_7_1 && [CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined) {
        BOOL hasAlwaysKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSLocationAlwaysUsageDescription"] != nil;
        BOOL hasWhenInUseKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSLocationWhenInUseUsageDescription"] != nil;
        if (hasAlwaysKey) {
            [locationManager requestAlwaysAuthorization];
        } else if (hasWhenInUseKey) {
            [locationManager requestWhenInUseAuthorization];
        } else {
            // At least one of the keys NSLocationAlwaysUsageDescription or NSLocationWhenInUseUsageDescription MUST be present in the Info.plist file to use location services on iOS 8+.
            NSAssert(hasAlwaysKey || hasWhenInUseKey, @"To use location services in iOS 8+, your Info.plist must provide a value for either NSLocationWhenInUseUsageDescription or NSLocationAlwaysUsageDescription.");
        }
    }
#endif /* __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_7_1 */
}

-(BOOL)CanDeviceSupportAppBackgroundRefresh
{
    // Override point for customization after application launch.
    if ([[UIApplication sharedApplication] backgroundRefreshStatus] == UIBackgroundRefreshStatusAvailable) {
        NSLog(@"Background updates are available for the app.");
        return YES;
    }else if([[UIApplication sharedApplication] backgroundRefreshStatus] == UIBackgroundRefreshStatusDenied)
    {
        NSLog(@"The user explicitly disabled background behavior for this app or for the whole system.");
        return NO;
    }else if([[UIApplication sharedApplication] backgroundRefreshStatus] == UIBackgroundRefreshStatusRestricted)
    {
        NSLog(@"Background updates are unavailable and the user cannot enable them again. For example, this status can occur when parental controls are in effect for the current user.");
        return NO;
    }
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    locationManager = [[CLLocationManager alloc] init];
    locationManager.delegate = self;
    [self askLocationPermission];
    if (![self CanDeviceSupportAppBackgroundRefresh]) {
        [self sendLocalNotification:@"Background refresh disabled"];
    }
    /*locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    locationManager.distanceFilter= 1;
    locationManager.pausesLocationUpdatesAutomatically = NO;
    locationManager.activityType = CLActivityTypeAutomotiveNavigation;
    [locationManager startUpdatingLocation];*/
    [locationManager startMonitoringSignificantLocationChanges];//后台基站更换时更新
    //[locationManager startUpdatingLocation];//前台准确定位频繁更新
    
    // Map View
    myMapView = [[MKMapView alloc] initWithFrame:self.transitionView.bounds];
    myMapView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    myMapView.rotateEnabled = NO;
    myMapView.delegate = self;
    [self.transitionView addSubview:myMapView];
    myMapView.showsUserLocation = YES;
    //[myMapView setUserTrackingMode:MKUserTrackingModeFollow animated:YES];
    
    //读取存在UserDefaults里面的数据
    NSDictionary *officeLocation = [[NSUserDefaults standardUserDefaults] objectForKey:@"officeLocation"];
    if (officeLocation != nil) {
        officeVolume = [[[NSUserDefaults standardUserDefaults] objectForKey:@"officeVolume"] floatValue];
        office = [[JPSThumbnail alloc] init];
        office.image = [UIImage imageNamed:@"Office.png"];
        office.title = @"办公室";
        office.subtitle = [NSString stringWithFormat:@"铃声音量：%.2f", officeVolume];
        CLLocationCoordinate2D location = CLLocationCoordinate2DMake([[officeLocation objectForKey:@"latitude"]floatValue], [[officeLocation objectForKey:@"longitude"]floatValue]);
        office.coordinate = location;
        office.disclosureBlock = ^{ NSLog(@"selected office"); };
        officeAnnotation = [JPSThumbnailAnnotation annotationWithThumbnail:office];
        [myMapView addAnnotation:officeAnnotation];
        
        [self addOffset:&location.longitude latitude:&location.latitude];
        officeRegion = [[CLCircularRegion alloc] initWithCenter:location radius:30 identifier:@"OFFICE"];
        officeRegion.notifyOnEntry = YES;
        officeRegion.notifyOnExit = YES;
        [locationManager startMonitoringForRegion:officeRegion];
        [locationManager requestStateForRegion:officeRegion];
        NSLog(@"Start monitor for region : OFFICE");
    }
    NSDictionary *homeLocation = [[NSUserDefaults standardUserDefaults] objectForKey:@"homeLocation"];
    if (homeLocation != nil) {
        homeVolume = [[[NSUserDefaults standardUserDefaults] objectForKey:@"homeVolume"] floatValue];
        home = [[JPSThumbnail alloc] init];
        home.image = [UIImage imageNamed:@"Home.png"];
        home.title = @"家";
        home.subtitle = [NSString stringWithFormat:@"铃声音量：%.2f", homeVolume];
        CLLocationCoordinate2D location = CLLocationCoordinate2DMake([[homeLocation objectForKey:@"latitude"]floatValue], [[homeLocation objectForKey:@"longitude"]floatValue]);
        home.coordinate = location;
        home.disclosureBlock = ^{ NSLog(@"selected home"); };
        homeAnnotation = [JPSThumbnailAnnotation annotationWithThumbnail:home];
        [myMapView addAnnotation:homeAnnotation];
        
        [self addOffset:&location.longitude latitude:&location.latitude];
        homeRegion = [[CLCircularRegion alloc] initWithCenter:location radius:30 identifier:@"HOME"];
        homeRegion.notifyOnEntry = YES;
        homeRegion.notifyOnExit = YES;
        [locationManager startMonitoringForRegion:homeRegion];
        [locationManager requestStateForRegion:homeRegion];
        NSLog(@"Start monitor for region : HOME");
        
        //MKCoordinateRegion r = MKCoordinateRegionMakeWithDistance(location, 100, 100);
        //[myMapView setRegion:r];
    }
    NSLog(@"%@", [locationManager monitoredRegions]);
    
    UIToolbar *toolBar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, self.transitionView.bounds.size.height - 44, self.transitionView.bounds.size.width, 44)];
    [toolBar setBackgroundColor:[UIColor colorWithRed:(247/255.0) green:(247/255.0) blue:(247/255.0) alpha:1]];
    [self.transitionView addSubview:toolBar];
    
    UIBarButtonItem *locateMeButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"LocateMe"] style:UIBarButtonItemStylePlain target:self action:@selector(LocateMe:)];
    pinButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Pin"] style:UIBarButtonItemStylePlain target:self action:@selector(showAddressType:)];
    UIBarButtonItem *flexibleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    [toolBar setItems:[NSArray arrayWithObjects:locateMeButton, flexibleItem, pinButton, nil] animated:YES];
    
    //监控铃声音量变化
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(volumeChanged:) name:@"AVSystemController_SystemVolumeDidChangeNotification" object:nil];
    [self changeVolume:1.0f];
    /*
    regionMonitored = NO;
    locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    locationManager.distanceFilter= 1;
    locationManager.pausesLocationUpdatesAutomatically = NO;
    locationManager.activityType = CLActivityTypeAutomotiveNavigation;
    [locationManager startUpdatingLocation];//前台准确定位频繁更新
     */
    
    timer = [NSTimer scheduledTimerWithTimeInterval:5
                                             target:self
                                           selector:@selector(requestRegionState)
                                           userInfo:nil
                                            repeats:YES];
}

- (void)requestRegionState {
    if (officeRegion != nil) {
        [locationManager requestStateForRegion:officeRegion];
    }
    if (homeRegion != nil) {
        [locationManager requestStateForRegion:homeRegion];
    }
}

- (void)addAddress:(int)index{
    JPSThumbnail *theThumbnail;
    id theAnnotation;
    if (index == 1) {
        theThumbnail = office;
        theAnnotation = officeAnnotation;
    }
    else if (index == 2){
        theThumbnail = home;
        theAnnotation = homeAnnotation;
    }
    else
        return;
    AVSystemController* avc = SharedAVSystemController;
    float nowVolume;
    [avc getActiveCategoryVolume:&nowVolume andName:nil];
    if (theThumbnail != nil) {
        [theAnnotation setCoordinate:myMapView.userLocation.location.coordinate];
        NSNumber *latitude = [NSNumber numberWithDouble:myMapView.userLocation.location.coordinate.latitude];
        NSNumber *longitude = [NSNumber numberWithDouble:myMapView.userLocation.location.coordinate.longitude];
        NSDictionary *theLocation=@{@"latitude":latitude,@"longitude":longitude};
        if (theThumbnail == office) {
            [[NSUserDefaults standardUserDefaults] setObject:theLocation forKey:@"officeLocation"];
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:nowVolume] forKey:@"officeVolume"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        if (theThumbnail == home) {
            [[NSUserDefaults standardUserDefaults] setObject:theLocation forKey:@"homeLocation"];
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:nowVolume] forKey:@"homeVolume"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        return;
    }
    else{
        if (index == 1) {
            theThumbnail = [[JPSThumbnail alloc] init];
            theThumbnail.image = [UIImage imageNamed:@"Office.png"];
            theThumbnail.title = @"办公室";
            theThumbnail.subtitle = [NSString stringWithFormat:@"铃声音量：%.2f", nowVolume];
            theThumbnail.coordinate = myMapView.userLocation.location.coordinate;
            theThumbnail.disclosureBlock = ^{ NSLog(@"selected office"); };
        }
        else if (index == 2){
            theThumbnail = [[JPSThumbnail alloc] init];
            theThumbnail.image = [UIImage imageNamed:@"Home.png"];
            theThumbnail.title = @"家";
            theThumbnail.subtitle = [NSString stringWithFormat:@"铃声音量：%.2f", nowVolume];
            theThumbnail.coordinate = myMapView.userLocation.location.coordinate;
            theThumbnail.disclosureBlock = ^{ NSLog(@"selected home"); };
        }
    }
    theAnnotation = [JPSThumbnailAnnotation annotationWithThumbnail:theThumbnail];
    [myMapView addAnnotation:theAnnotation];
    if (index == 1) {
        office = theThumbnail;
        officeAnnotation = theAnnotation;
        officeVolume = nowVolume;
        NSNumber *latitude = [NSNumber numberWithDouble:theThumbnail.coordinate.latitude];
        NSNumber *longitude = [NSNumber numberWithDouble:theThumbnail.coordinate.longitude];
        NSDictionary *officeLocation=@{@"latitude":latitude,@"longitude":longitude};
        
        [[NSUserDefaults standardUserDefaults] setObject:officeLocation forKey:@"officeLocation"];
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:officeVolume] forKey:@"officeVolume"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        CLLocationCoordinate2D location = myMapView.userLocation.location.coordinate;
        [self addOffset:&location.longitude latitude:&location.latitude];
        officeRegion = [[CLCircularRegion alloc] initWithCenter:location radius:30 identifier:@"OFFICE"];
        officeRegion.notifyOnEntry = YES;
        officeRegion.notifyOnExit = YES;
        [locationManager startMonitoringForRegion:officeRegion];
        NSLog(@"Start monitor for region : OFFICE");
    }
    else if (index == 2){
       home = theThumbnail;
        homeAnnotation = theAnnotation;
        homeVolume = nowVolume;
        NSNumber *latitude = [NSNumber numberWithDouble:theThumbnail.coordinate.latitude];
        NSNumber *longitude = [NSNumber numberWithDouble:theThumbnail.coordinate.longitude];
        NSDictionary *homeLocation=@{@"latitude":latitude,@"longitude":longitude};
        
        [[NSUserDefaults standardUserDefaults] setObject:homeLocation forKey:@"homeLocation"];
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:homeVolume] forKey:@"homeVolume"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        CLLocationCoordinate2D location = myMapView.userLocation.location.coordinate;
        [self addOffset:&location.longitude latitude:&location.latitude];
        homeRegion = [[CLCircularRegion alloc] initWithCenter:location radius:30 identifier:@"HOME"];
        homeRegion.notifyOnEntry = YES;
        homeRegion.notifyOnExit = YES;
        [locationManager startMonitoringForRegion:homeRegion];
        NSLog(@"Start monitor for region : HOME");
    }
}

- (void)showAddressType:(id)sender{
    UIAlertController *optionsController;
    UIAlertAction *chooseHomeAction;
    UIAlertAction *chooseOfficeAction;
    UIAlertAction *cancelAction;
    
    optionsController = [UIAlertController alertControllerWithTitle:@"请选择你的地址类型"
                                                          message:@"不同的地址类型会显示不同的图标"
                                                   preferredStyle:UIAlertControllerStyleActionSheet];
    chooseHomeAction = [UIAlertAction actionWithTitle:@"家"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
                                               [self addAddress:2];
                                           }];
    chooseOfficeAction = [UIAlertAction actionWithTitle:@"办公室"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
                                             [self addAddress:1];
                                         }];
    cancelAction = [UIAlertAction actionWithTitle:@"我只是试试这个按钮是干嘛用的"
                                                style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction *action) {
                                                  // do something here
                                              }];
    // note: you can control the order buttons are shown, unlike UIActionSheet
    [optionsController addAction:chooseHomeAction];
    [optionsController addAction:chooseOfficeAction];
    [optionsController addAction:cancelAction];
    [optionsController setModalPresentationStyle:UIModalPresentationPopover];
    
    if (isPad) {
        UIPopoverController *popover = [[UIPopoverController alloc] initWithContentViewController:optionsController];
        [popover presentPopoverFromBarButtonItem:sender
                        permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    }
    else
        [self presentViewController:optionsController animated:YES completion:nil];
}

- (void)sendLocalNotification:(NSString *)message
{
    UILocalNotification* localNotification = [[UILocalNotification alloc] init];
    //localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:5];
    localNotification.alertBody = message;
    localNotification.timeZone = [NSTimeZone defaultTimeZone];
    localNotification.soundName = UILocalNotificationDefaultSoundName; // den den den
    //localNotification.soundName = @"sound.caf";
    //[[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
    [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
}

- (void)addOffset:(double*)longitude latitude:(double*)latitude
{
    sqlite3 *db;
    NSString *database_path = [[NSBundle mainBundle] pathForResource:@"offsets" ofType:@"db"];
    //NSArray *path = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    //NSString *documents = [path objectAtIndex:0];
    //NSString *database_path = [documents stringByAppendingPathComponent:@"offsets.db"];
    
    if (sqlite3_open([database_path UTF8String], &db) != SQLITE_OK) {
        sqlite3_close(db);
        NSLog(@"数据库打开失败");
    }
    
    NSString *sqlQuery = [NSString stringWithFormat:@"select offset_longitude, offset_latitude from offsets where longitude=%.1f and latitude=%.1f", *longitude, *latitude];
    sqlite3_stmt * statement;
    
    double offsetLongitude;
    double offsetLatitude;
    if (sqlite3_prepare_v2(db, [sqlQuery UTF8String], -1, &statement, nil) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            offsetLongitude = sqlite3_column_double(statement, 0);
            offsetLatitude = sqlite3_column_double(statement, 1);
            NSLog(@"offset_longitude:%f  offset_latitude:%f", offsetLongitude, offsetLatitude);
        }
    }
    sqlite3_close(db);
    
    *longitude = *longitude - offsetLongitude;
    *latitude = *latitude - offsetLatitude;
}

- (void)changeLocation:(CLLocationCoordinate2D)location
{
    [myMapView removeAnnotation:myLocation];
    //[self addOffset:&location.longitude latitude:&location.latitude];
    myLocation.coordinate = location;
    [myMapView addAnnotation:myLocation];
    
    MKCoordinateRegion startingRegion = MKCoordinateRegionMakeWithDistance(location, 0.01, 0.01);
    [myMapView setRegion:startingRegion animated:YES];
    [myMapView setCenterCoordinate:location zoomLevel:50 animated:YES];
    
    CLCircularRegion *testRegion = [[CLCircularRegion alloc] initWithCenter:location radius:1 identifier:@"TEST"];
    [locationManager startMonitoringForRegion:testRegion];
}

- (IBAction)LocateMe:(id)sender
{
    CLLocationCoordinate2D location;
    location = myMapView.userLocation.coordinate;
    [myMapView setCenterCoordinate:location zoomLevel:50 animated:YES];
}

- (void)changeVolume:(float)volume
{
     AVSystemController *avsc = SharedAVSystemController;
     [avsc setActiveCategoryVolumeTo:volume];
}

- (void)volumeChanged:(NSNotification *)notification
{
    AVSystemController* avc = SharedAVSystemController;
    float nowVolume;
    if ([avc getActiveCategoryVolume:&nowVolume andName:nil]) {
        NSLog(@"%f", nowVolume);
    }
    if (theLastThumbnail != nil) {
        theLastThumbnail.subtitle = [NSString stringWithFormat:@"铃声音量：%.2f", nowVolume];
        [theLastAnnotationView updateWithThumbnail:theLastThumbnail];
        
        if (theLastThumbnail == office) {
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:nowVolume] forKey:@"officeVolume"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        if (theLastThumbnail == home) {
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:nowVolume] forKey:@"homeVolume"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
}


#pragma mark - MKMapViewDelegate

- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view {
    if ([view conformsToProtocol:@protocol(JPSThumbnailAnnotationViewProtocol)]) {
        [((NSObject<JPSThumbnailAnnotationViewProtocol> *)view) didSelectAnnotationViewInMap:mapView];
        NSLog(@"didSelectAnnotationView %@", view);
        theLastAnnotationView = (JPSThumbnailAnnotationView *)view;
        theLastThumbnail = theLastAnnotationView.thumbnail;
    }
}

- (void)mapView:(MKMapView *)mapView didDeselectAnnotationView:(MKAnnotationView *)view {
    if ([view conformsToProtocol:@protocol(JPSThumbnailAnnotationViewProtocol)]) {
        [((NSObject<JPSThumbnailAnnotationViewProtocol> *)view) didDeselectAnnotationViewInMap:mapView];
        NSLog(@"didDeselectAnnotationView %@", view);
    }
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation conformsToProtocol:@protocol(JPSThumbnailAnnotationProtocol)]) {
        JPSThumbnailAnnotationView *theAnnotationView = (JPSThumbnailAnnotationView *)[((NSObject<JPSThumbnailAnnotationProtocol> *)annotation) annotationViewInMap:mapView];
        return theAnnotationView;
    }
    return nil;
}

- (void)mapView:(MKMapView *) mapView didUpdateUserLocation:(MKUserLocation *)userLocation
{
    //NSLog(@"Location returned: %f, %f Accuracy: %f", userLocation.location.coordinate.latitude, userLocation.location.coordinate.longitude, userLocation.location.horizontalAccuracy);
    if (!regionMonitored) {
        //CLCircularRegion *monitoredRegion = [[CLCircularRegion alloc] initWithCenter:userLocation.location.coordinate radius:10 identifier:@"Office"];
        //[locationManager startMonitoringForRegion:monitoredRegion];
        //[self sendLocalNotification:@"startMonitoringForRegion"];
        regionMonitored = YES;
        //[locationManager stopUpdatingLocation];
        //[locationManager startMonitoringSignificantLocationChanges];//后台基站更换时更新
    }
    else{
        //[self sendLocalNotification:@"didUpdateUserLocation"];
    }
    
    //[myMapView removeAnnotation:myLocation];
    //myLocation.coordinate = userLocation.coordinate;
    //[myMapView addAnnotation:myLocation];
}
#pragma mark - CLLocationManagerDelegate

-(void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region
{
    if ([region.identifier isEqualToString:@"OFFICE"]) {
        [self changeVolume:officeVolume];
        [self sendLocalNotification:[NSString stringWithFormat:@"主人，你到办公室了，音量已经设置成了%.2f", officeVolume]];
    }
    if ([region.identifier isEqualToString:@"HOME"]) {
        [self changeVolume:homeVolume];
        [self sendLocalNotification:[NSString stringWithFormat:@"主人，你到家了，音量已经设置成了%.2f", homeVolume]];
    }
}

-(void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region
{
    if ([region.identifier isEqualToString:@"OFFICE"]) {
        [self sendLocalNotification:[NSString stringWithFormat:@"主人，你下班了，音量已经设置成了最大"]];
    }
    if ([region.identifier isEqualToString:@"HOME"]) {
        [self sendLocalNotification:[NSString stringWithFormat:@"主人，你离开家了，音量已经设置成了最大"]];
    }
    [self changeVolume:1];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations{
    NSLog(@"didUpdateLocations %@", [locations lastObject]);
    //CLLocation *currentLocation = [locations lastObject];
    //myLocation.coordinate = currentLocation.coordinate;
    //[myMapView addAnnotation:myLocation];
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error
{
    NSLog(@"monitoringDidFailForRegion - error: %@", [error localizedDescription]);
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    if (![CLLocationManager locationServicesEnabled]) {
        NSLog(@"Couldn't turn on ranging: Location services are not enabled.");
    }
    
    if ([CLLocationManager authorizationStatus] != kCLAuthorizationStatusAuthorizedAlways) {
        NSLog(@"Couldn't turn on monitoring: Location services not authorised.");
    }
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region{
    switch (state) {
        case CLRegionStateInside:
            //NSLog(@"Inside region. %@", region.identifier);
            if ([region.identifier isEqualToString:@"OFFICE"] && !insideOffice) {
                [self sendLocalNotification:[NSString stringWithFormat:@"主人，你到办公室了，音量已经设置成了%.2f", officeVolume]];
                insideOffice = YES;
                [self changeVolume:officeVolume];
                NSLog(@"Entered %@", region.identifier);
            }else if ([region.identifier isEqualToString:@"HOME"] && !insideHome) {
                [self sendLocalNotification:[NSString stringWithFormat:@"主人，你到家了，音量已经设置成了%.2f", homeVolume]];
                insideHome = YES;
                [self changeVolume:homeVolume];
                NSLog(@"Entered %@", region.identifier);
            }
            //[self sendLocalNotification:@"didEnterRegion"];
            break;
        case CLRegionStateOutside:
            //NSLog(@"Outside region. %@", region.identifier);
            if ([region.identifier isEqualToString:@"OFFICE"] && insideOffice) {
                insideOffice = NO;
                NSLog(@"Exitted %@", region.identifier);
            }else if ([region.identifier isEqualToString:@"HOME"] && insideHome) {
                insideHome = NO;
                NSLog(@"Exitted %@", region.identifier);
            }
            //[self sendLocalNotification:@"didExitRegion"];
            break;
        case CLRegionStateUnknown:
            //[self sendLocalNotification:@"unknown state"];
            break;
        default:
            break;
    }
}

- (void)locationManager:(CLLocationManager *)manager rangingBeaconsDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error{
    NSLog(@"rangingBeaconsDidFailForRegion - error: %@", [error localizedDescription]);
}

- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region{
    NSLog(@"didStartMonitoringForRegion : %@", region.identifier);
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error{
    NSLog(@"didFailWithError - error: %@", [error localizedDescription]);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
