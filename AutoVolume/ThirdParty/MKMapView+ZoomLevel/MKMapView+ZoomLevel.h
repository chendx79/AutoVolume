//
//  MKMapView+ZoomLevel.h
//  AutoVolume
//
//  Created by Derek Chen on 14/11/23.
//  Copyright (c) 2014年 Derek Chen. All rights reserved.
//

#import <MapKit/MapKit.h>

@interface MKMapView (ZoomLevel)

- (void)setCenterCoordinate:(CLLocationCoordinate2D)centerCoordinate
                  zoomLevel:(NSUInteger)zoomLevel
                   animated:(BOOL)animated;

@end