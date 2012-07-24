#import "MTDDirectionsParserMapQuestTest.h"
#import "MTDDirectionsOverlay.h"
#import "MTDDistance.h"
#import "MTDWaypoint.h"
#import "MTDAddress.h"


@implementation MTDDirectionsParserMapQuestTest

- (void)testDirectRoute {
    NSString *path = [[[NSBundle bundleForClass:[self class]] bundlePath] stringByAppendingPathComponent:@"mapquest_guessing_vienna.xml"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    
    STAssertNotNil(data, @"Couldn't read mapquest_guessing_vienna.xml");
    
    __block BOOL testFinished = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        MTDDirectionsParserMapQuest *parser = [[MTDDirectionsParserMapQuest alloc] initWithFrom:[MTDWaypoint waypointWithCoordinate:CLLocationCoordinate2DMake(47.0616,16.3236)]
                                                                                             to:[MTDWaypoint waypointWithCoordinate:CLLocationCoordinate2DMake(48.209,16.354)]
                                                                              intermediateGoals:nil
                                                                                      routeType:MTDDirectionsRouteTypeShortestDriving
                                                                                           data:data];
        
        
        [parser parseWithCompletion:^(MTDDirectionsOverlay *overlay, NSError *error) {
            STAssertNil(error,@"There was an error parsing mapquest_guessing_vienna.xml");
            
            MTDAddress *fromAddress = overlay.fromAddress;
            MTDAddress *toAddress = overlay.toAddress;
            
            STAssertEqualObjects(fromAddress.state, @"Burgenland", @"fromAddress: error parsing state");
            STAssertEqualObjects(fromAddress.country, @"Austria", @"fromAddress: error parsing country");
            STAssertEqualObjects(toAddress.state, @"Vienna", @"toAddress: error parsing state");
            STAssertEqualObjects(toAddress.country, @"Austria", @"toAddress: error parsing country");
            
            STAssertEquals(overlay.timeInSeconds, 7915., @"Error parsing time");
            STAssertEqualObjects(overlay.formattedTime, @"2:11:55", @"Error formatting time");
            STAssertTrue(overlay.waypoints.count == 248, @"Error parsing waypoints");
            STAssertEqualsWithAccuracy([overlay.distance distanceInMeasurementSystem:MTDMeasurementSystemMetric], 150.8663, 0.001, @"Error parsing distance");
            
            testFinished = YES;
        }];
    });
    
    while (!testFinished) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
}

- (void)testIntermediateGoals {
    NSString *path = [[[NSBundle bundleForClass:[self class]] bundlePath] stringByAppendingPathComponent:@"mapquest_intermediate_optimized.xml"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    
    STAssertNotNil(data, @"Couldn't read mapquest_intermediate_optimized.xml");
    
    __block BOOL testFinished = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CLLocationCoordinate2D from = CLLocationCoordinate2DMake(51.4554, -0.9742);              // Reading
        CLLocationCoordinate2D to = CLLocationCoordinate2DMake(51.38713, -1.0316);               // NSConference
        CLLocationCoordinate2D intermediateGoal1 = CLLocationCoordinate2DMake(51.3765, -1.003);  // Beech Hill
        CLLocationCoordinate2D intermediateGoal2 = CLLocationCoordinate2DMake(51.4388, -0.9409); // University
        MTDDirectionsParserMapQuest *parser = [[MTDDirectionsParserMapQuest alloc] initWithFrom:[MTDWaypoint waypointWithCoordinate:from]
                                                                                             to:[MTDWaypoint waypointWithCoordinate:to]
                                                                              intermediateGoals:[NSArray arrayWithObjects:
                                                                                                 [MTDWaypoint waypointWithCoordinate:intermediateGoal1],
                                                                                                 [MTDWaypoint waypointWithCoordinate:intermediateGoal2],
                                                                                                 nil]
                                                                                      routeType:MTDDirectionsRouteTypeShortestDriving
                                                                                           data:data];
        
        
        [parser parseWithCompletion:^(MTDDirectionsOverlay *overlay, NSError *error) {
            STAssertNil(error,@"There was an error parsing mapquest_guessing_vienna.xml");
            
            MTDAddress *fromAddress = overlay.fromAddress;
            MTDAddress *toAddress = overlay.toAddress;

            STAssertEqualObjects(fromAddress.city, @"Reading", @"fromAddress: error parsing city");
            STAssertEqualObjects(fromAddress.state, @"England", @"fromAddress: error parsing state");
            STAssertEqualObjects(fromAddress.county, @"Reading", @"fromAddress: error parsing county");
            STAssertEqualObjects(fromAddress.postalCode, @"RG1 1TT", @"fromAddress: error parsing postalCode");
            STAssertEqualObjects(fromAddress.country, @"United Kingdom", @"fromAddress: error parsing country");
            STAssertEqualObjects(toAddress.street, @"New Road", @"toAddress: error parsing street");
            STAssertEqualObjects(toAddress.city, @"Burghfield", @"toAddress: error parsing city");
            STAssertEqualObjects(toAddress.state, @"England", @"toAddress: error parsing state");
            STAssertEqualObjects(toAddress.county, @"Berkshire", @"toAddress: error parsing county");
            STAssertEqualObjects(toAddress.country, @"United Kingdom", @"toAddress: error parsing country");
            
            STAssertEquals(overlay.timeInSeconds, 2263., @"Error parsing time");
            STAssertEqualObjects(overlay.formattedTime, @"37:43", @"Error formatting time");
            STAssertTrue(overlay.waypoints.count == 388, @"Error parsing waypoints");
            STAssertEqualsWithAccuracy([overlay.distance distanceInMeasurementSystem:MTDMeasurementSystemMetric], 21.8195, 0.001, @"Error parsing distance");

            NSArray *intermediateGoals = overlay.intermediateGoals;

            STAssertTrue(intermediateGoals.count == 2, @"Error parsing number of intermediate goals");

            MTDWaypoint *ig1 = [intermediateGoals objectAtIndex:0];
            MTDWaypoint *ig2 = [intermediateGoals objectAtIndex:1];

            STAssertEqualObjects(ig1.address.city, @"Shinfield", @"Wrong address of intermediate goal");
            STAssertEqualsWithAccuracy(ig1.coordinate.latitude, 51.4388, 0.000001, @"Wrong coordinate of intermediate goal");
            STAssertEqualsWithAccuracy(ig1.coordinate.longitude, -0.9409, 0.000001, @"Wrong coordinate of intermediate goal");

            STAssertEqualObjects(ig2.address.city, @"Beech Hill", @"Wrong address of intermediate goal");
            STAssertEqualsWithAccuracy(ig2.coordinate.latitude, 51.3765, 0.000001, @"Wrong coordinate of intermediate goal");
            STAssertEqualsWithAccuracy(ig2.coordinate.longitude, -1.003, 0.000001, @"Wrong coordinate of intermediate goal");

            testFinished = YES;
        }];
    });
    
    while (!testFinished) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
}

@end
