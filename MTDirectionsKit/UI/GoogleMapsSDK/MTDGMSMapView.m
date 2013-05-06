#import "MTDGMSMapView.h"
#import "MTDAddress.h"
#import "MTDWaypoint.h"
#import "MTDWaypoint+MTDirectionsPrivateAPI.h"
#import "MTDManeuver.h"
#import "MTDDistance.h"
#import "MTDDirectionsDelegate.h"
#import "MTDDirectionsRequest.h"
#import "MTDDirectionsRequestOption.h"
#import "MTDDirectionsOverlay.h"
#import "MTDDirectionsOverlay+MTDirectionsPrivateAPI.h"
#import "MTDRoute.h"
#import "MTDRoute+MTDGoogleMapsSDK.h"
#import "MTDGMSDirectionsOverlayView.h"
#import "MTDDirectionsOverlayView+MTDirectionsPrivateAPI.h"
#import "MTDMapViewProxy.h"
#import "MTDFunctions.h"
#import "MTDCustomization.h"
#import "MTDInterApp.h"
#import "MTDAssert.h"


static char myLocationContext;


@interface GMSMapView (MTDGoogleMapsSDK)

// the designated initializer of GMSMapView is not exposed. we declare it here to keep the compiler silent
- (id)initWithFrame:(CGRect)frame camera:(GMSCameraPosition *)camera;

@end


@interface MTDGMSMapView () <GMSMapViewDelegate>

@property (nonatomic, strong) NSMutableDictionary *directionsOverlayViews;

/** The delegate that was set by the user, we forward all delegate calls */
@property (nonatomic, mtd_weak, setter = mtd_setTrueDelegate:) id<GMSMapViewDelegate> mtd_trueDelegate;

/** the delegate proxy for CLLocationManagerDelegate and UIGestureRecognizerDelegate */
@property (nonatomic, strong) MTDMapViewProxy *mtd_proxy;

@end


@implementation MTDGMSMapView

@synthesize directionsOverlay = _directionsOverlay;
@synthesize directionsDisplayType = _directionsDisplayType;

////////////////////////////////////////////////////////////////////////
#pragma mark - Lifecycle
////////////////////////////////////////////////////////////////////////

- (id)initWithFrame:(CGRect)frame camera:(GMSCameraPosition *)camera {
    if ((self = [super initWithFrame:frame camera:camera])) {
        [self mtd_setup];
    }

    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [super initWithCoder:aDecoder])) {
        [self mtd_setup];
    }

    return self;
}

- (void)dealloc {
    _mtd_proxy.mapView = nil;
    _mtd_proxy = nil;
    self.delegate = nil;
    [self cancelLoadOfDirections];
    [self removeObserver:self forKeyPath:MTDKey(myLocation)];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject
////////////////////////////////////////////////////////////////////////

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &myLocationContext) {
        CLLocation *location = change[NSKeyValueChangeNewKey];
        
        [MTDWaypoint mtd_updateCurrentLocationCoordinate:location.coordinate];
        [self.mtd_proxy notifyDelegateDidUpdateUserLocation:location];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - UIView
////////////////////////////////////////////////////////////////////////

- (void)willMoveToSuperview:(UIView *)newSuperview {
    if (newSuperview == nil) {
        [self cancelLoadOfDirections];
    }

    [super willMoveToSuperview:newSuperview];
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    if (newWindow == nil) {
        [self cancelLoadOfDirections];
    }

    [super willMoveToWindow:newWindow];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Directions
////////////////////////////////////////////////////////////////////////

- (void)loadDirectionsFrom:(CLLocationCoordinate2D)fromCoordinate
                        to:(CLLocationCoordinate2D)toCoordinate
                 routeType:(MTDDirectionsRouteType)routeType
      zoomToShowDirections:(BOOL)zoomToShowDirections {
    [self loadDirectionsFrom:[MTDWaypoint waypointWithCoordinate:fromCoordinate]
                          to:[MTDWaypoint waypointWithCoordinate:toCoordinate]
           intermediateGoals:nil
                   routeType:routeType
                     options:MTDDirectionsRequestOptionNone
        zoomToShowDirections:zoomToShowDirections];
}

- (void)loadDirectionsFromAddress:(NSString *)fromAddress
                        toAddress:(NSString *)toAddress
                        routeType:(MTDDirectionsRouteType)routeType
             zoomToShowDirections:(BOOL)zoomToShowDirections {
    [self loadDirectionsFrom:[MTDWaypoint waypointWithAddress:[MTDAddress addressWithAddressString:fromAddress]]
                          to:[MTDWaypoint waypointWithAddress:[MTDAddress addressWithAddressString:toAddress]]
           intermediateGoals:nil
                   routeType:routeType
                     options:MTDDirectionsRequestOptionNone
        zoomToShowDirections:zoomToShowDirections];
}

- (void)loadAlternativeDirectionsFrom:(MTDWaypoint *)from
                                   to:(MTDWaypoint *)to
                            routeType:(MTDDirectionsRouteType)routeType
                 zoomToShowDirections:(BOOL)zoomToShowDirections {

    [self loadDirectionsFrom:from
                          to:to
           intermediateGoals:nil
                   routeType:routeType
                     options:_MTDDirectionsRequestOptionAlternativeRoutes
        zoomToShowDirections:zoomToShowDirections];
}

- (void)loadDirectionsFrom:(MTDWaypoint *)from
                        to:(MTDWaypoint *)to
         intermediateGoals:(NSArray *)intermediateGoals
                 routeType:(MTDDirectionsRouteType)routeType
                   options:(MTDDirectionsRequestOptions)options
      zoomToShowDirections:(BOOL)zoomToShowDirections {

    [self.mtd_proxy loadDirectionsFrom:from
                                    to:to
                     intermediateGoals:intermediateGoals
                             routeType:routeType
                               options:options
                  zoomToShowDirections:zoomToShowDirections];
}

- (void)cancelLoadOfDirections {
    [self.mtd_proxy cancelLoadOfDirections];
}

- (void)removeDirectionsOverlay {
    for (MTDGMSDirectionsOverlayView *overlayView in [_directionsOverlayViews allValues]) {
        overlayView.map = nil;
    }

    _directionsOverlay = nil;
    _directionsOverlayViews = nil;
}

- (MTDGMSDirectionsOverlayView *)directionsOverlayViewForRoute:(MTDRoute *)route {
    return self.directionsOverlayViews[route];
}

- (void)activateRoute:(MTDRoute *)route {
    MTDRoute *activeRouteBefore = self.directionsOverlay.activeRoute;

    if (route != nil && route != activeRouteBefore) {
        [self.directionsOverlay mtd_activateRoute:route];
        MTDRoute *activeRouteAfter = self.directionsOverlay.activeRoute;

        if (activeRouteBefore != activeRouteAfter) {
            [self.mtd_proxy notifyDelegateDidActivateRoute:activeRouteAfter ofOverlay:self.directionsOverlay];

            // Update colors depending on active state
            for (MTDRoute *r in self.directionsOverlay.routes) {
                UIColor *color = [self.mtd_proxy askDelegateForColorOfRoute:r ofOverlay:self.directionsOverlay];
                MTDGMSDirectionsOverlayView *overlayView = [self directionsOverlayViewForRoute:r];

                overlayView.strokeColor = color;
            }
        }
    }
}

- (CGFloat)distanceBetweenActiveRouteAndCoordinate:(CLLocationCoordinate2D)coordinate {
    // TODO: GoogleMapsSDK
    //    MTDAssert(CLLocationCoordinate2DIsValid(coordinate), @"We can't measure distance to invalid coordinates");
    //
    //    MTDRoute *activeRoute = self.directionsOverlay.activeRoute;
    //
    //    if (activeRoute == nil || !CLLocationCoordinate2DIsValid(coordinate)) {
    //        return FLT_MAX;
    //    }
    //
    //    CGPoint point = [self convertCoordinate:coordinate toPointToView:self.directionsOverlayView];
    //    CGFloat distance = [self.directionsOverlayView distanceBetweenPoint:point route:self.directionsOverlay.activeRoute];
    //
    //    return distance;
    return FLT_MAX;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Region
////////////////////////////////////////////////////////////////////////

- (void)setRegionToShowDirectionsAnimated:(BOOL)animated {
    GMSPath *path = self.directionsOverlay.activeRoute.path;
    GMSCoordinateBounds *bounds = [[GMSCoordinateBounds alloc] initWithPath:path];
    GMSCameraUpdate *update = [GMSCameraUpdate fitBounds:bounds withPadding:self.directionsEdgePadding];

    if (animated) {
        [self animateWithCameraUpdate:update];
    } else {
        [self moveCamera:update];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Properties
////////////////////////////////////////////////////////////////////////

- (void)setDirectionsOverlay:(MTDDirectionsOverlay *)directionsOverlay {
    if (directionsOverlay != _directionsOverlay) {
        // remove old overlay and annotations
        if (_directionsOverlay != nil) {
            [self removeDirectionsOverlay];
        }

        _directionsOverlay = directionsOverlay;

        // add new overlay
        if (directionsOverlay != nil) {
            [self mtd_addOverlay:directionsOverlay];
        }
    }
}

- (void)setDirectionsDisplayType:(MTDDirectionsDisplayType)directionsDisplayType {
    if (directionsDisplayType != _directionsDisplayType) {
        _directionsDisplayType = directionsDisplayType;
        [self mtd_updateUIForDirectionsDisplayType:directionsDisplayType];
    }
}

- (void)setDirectionsDelegate:(id<MTDDirectionsDelegate>)directionsDelegate {
    self.mtd_proxy.directionsDelegate = directionsDelegate;
}

- (id<MTDDirectionsDelegate>)directionsDelegate {
    return self.mtd_proxy.directionsDelegate;
}

- (void)setDelegate:(id<GMSMapViewDelegate>)delegate {
    if (delegate != _mtd_trueDelegate) {
        _mtd_trueDelegate = delegate;

        // if we haven't set a directionsDelegate and our delegate conforms to the protocol
        // MTDDirectionsDelegate, then we automatically set our directionsDelegate
        if (self.directionsDelegate == nil && [delegate conformsToProtocol:@protocol(MTDDirectionsDelegate)]) {
            self.directionsDelegate = (id<MTDDirectionsDelegate>)delegate;
        }
    }
}

- (id<GMSMapViewDelegate>)delegate {
    return _mtd_trueDelegate;
}

- (CLLocationCoordinate2D)fromCoordinate {
    if (self.directionsOverlay != nil) {
        return self.directionsOverlay.from.coordinate;
    }

    return kCLLocationCoordinate2DInvalid;
}

- (CLLocationCoordinate2D)toCoordinate {
    if (self.directionsOverlay != nil) {
        return self.directionsOverlay.to.coordinate;
    }

    return kCLLocationCoordinate2DInvalid;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Inter-App
////////////////////////////////////////////////////////////////////////

- (BOOL)openDirectionsInMapsApp {
    if (self.directionsOverlay != nil) {
        return [MTDNavigationAppBuiltInMaps openDirectionsFrom:self.directionsOverlay.activeRoute.from
                                                            to:self.directionsOverlay.activeRoute.to
                                                     routeType:self.directionsOverlay.routeType];
    }

    return NO;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - GMSMapViewDelegate Proxies
////////////////////////////////////////////////////////////////////////


/**
 * Called after the camera position has changed. During an animation, this
 * delegate might not be notified of intermediate camera positions. However, it
 * will always be called eventually with the final position of an the animation.
 */
- (void)mapView:(GMSMapView *)mapView didChangeCameraPosition:(GMSCameraPosition *)position {
    id<GMSMapViewDelegate> trueDelegate = self.mtd_trueDelegate;

    if ([trueDelegate respondsToSelector:@selector(mapView:didChangeCameraPosition:)]) {
        [trueDelegate mapView:mapView didChangeCameraPosition:position];
    }
}

/**
 * Called after a tap gesture at a particular coordinate, but only if a marker
 * was not tapped.  This is called before deselecting any currently selected
 * marker (the implicit action for tapping on the map).
 */
- (void)mapView:(GMSMapView *)mapView didTapAtCoordinate:(CLLocationCoordinate2D)coordinate {
    id<GMSMapViewDelegate> trueDelegate = self.mtd_trueDelegate;

    if ([trueDelegate respondsToSelector:@selector(mapView:didTapAtCoordinate:)]) {
        [trueDelegate mapView:mapView didTapAtCoordinate:coordinate];
    }
}

/**
 * Called after a long-press gesture at a particular coordinate.
 *
 * @param mapView The map view that was pressed.
 * @param coordinate The location that was pressed.
 */
- (void)mapView:(GMSMapView *)mapView didLongPressAtCoordinate:(CLLocationCoordinate2D)coordinate {
    id<GMSMapViewDelegate> trueDelegate = self.mtd_trueDelegate;

    if ([trueDelegate respondsToSelector:@selector(mapView:didLongPressAtCoordinate:)]) {
        [trueDelegate mapView:mapView didLongPressAtCoordinate:coordinate];
    }
}

/**
 * Called after a marker has been tapped.
 *
 * @param mapView The map view that was pressed.
 * @param marker The marker that was pressed.
 * @return YES if this delegate handled the tap event, which prevents the map
 *         from performing its default selection behavior, and NO if the map
 *         should continue with its default selection behavior.
 */
- (BOOL)mapView:(GMSMapView *)mapView didTapMarker:(GMSMarker *)marker {
    id<GMSMapViewDelegate> trueDelegate = self.mtd_trueDelegate;

    if ([trueDelegate respondsToSelector:@selector(mapView:didTapMarker:)]) {
        return [trueDelegate mapView:mapView didTapMarker:marker];
    }

    return NO;
}

/**
 * Called after a marker's info window has been tapped.
 */
- (void)mapView:(GMSMapView *)mapView didTapInfoWindowOfMarker:(GMSMarker *)marker {
    id<GMSMapViewDelegate> trueDelegate = self.mtd_trueDelegate;

    if ([trueDelegate respondsToSelector:@selector(mapView:didTapInfoWindowOfMarker:)]) {
        [trueDelegate mapView:mapView didTapInfoWindowOfMarker:marker];
    }
}

/**
 * Called after an overlay has been tapped.
 * This method is not called for taps on markers.
 *
 * @param mapView The map view that was pressed.
 * @param overlay The overlay that was pressed.
 */
- (void)mapView:(GMSMapView *)mapView didTapOverlay:(GMSOverlay *)overlay {
    id<GMSMapViewDelegate> trueDelegate = self.mtd_trueDelegate;
    __block MTDRoute *routeToActivate = nil;

    [self.directionsOverlayViews enumerateKeysAndObjectsUsingBlock:^(MTDRoute *route, MTDGMSDirectionsOverlayView *overlayView, BOOL *stop) {
        if (overlay == overlayView) {
            routeToActivate = route;
            *stop = YES;
        }
    }];

    [self activateRoute:routeToActivate];

    if ([trueDelegate respondsToSelector:@selector(mapView:didTapOverlay:)]) {
        [trueDelegate mapView:mapView didTapOverlay:overlay];
    }
}

/**
 * Called when a marker is about to become selected, and provides an optional
 * custom info window to use for that marker if this method returns a UIView.
 * If you change this view after this method is called, those changes will not
 * necessarily be reflected in the rendered version.
 *
 * The returned UIView must not have bounds greater than 500 points on either
 * dimension.  As there is only one info window shown at any time, the returned
 * view may be reused between other info windows.
 *
 * @return The custom info window for the specified marker, or nil for default
 */
- (UIView *)mapView:(GMSMapView *)mapView markerInfoWindow:(GMSMarker *)marker {
    id<GMSMapViewDelegate> trueDelegate = self.mtd_trueDelegate;

    if ([trueDelegate respondsToSelector:@selector(mapView:markerInfoWindow:)]) {
        [trueDelegate mapView:mapView markerInfoWindow:marker];
    }

    return nil;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Private
////////////////////////////////////////////////////////////////////////

- (void)mtd_setup {
    // we set ourself as the delegate
    [super setDelegate:self];

    _directionsDisplayType = MTDDirectionsDisplayTypeNone;
    _directionsEdgePadding = 125.f;
    _mtd_proxy = [[MTDMapViewProxy alloc] initWithMapView:self];

    [self addObserver:self forKeyPath:MTDKey(myLocation) options:NSKeyValueObservingOptionNew context:&myLocationContext];
}

- (void)mtd_addOverlay:(MTDDirectionsOverlay *)overlay {
    self.directionsOverlayViews = [NSMutableDictionary dictionaryWithCapacity:overlay.routes.count];

    for (MTDRoute *route in overlay.routes) {
        MTDGMSDirectionsOverlayView *overlayView = [self mtd_viewForRoute:route];

        self.directionsOverlayViews[route] = overlayView;
        overlayView.map = self;
    }
}

- (void)mtd_updateUIForDirectionsDisplayType:(MTDDirectionsDisplayType)displayType {
    for (MTDGMSDirectionsOverlayView *overlayView in [self.directionsOverlayViews allValues]) {
        overlayView.map = nil;

        if (displayType != MTDDirectionsDisplayTypeNone) {
            overlayView.map = self;
        }
    }
}

- (MTDGMSDirectionsOverlayView *)mtd_viewForRoute:(MTDRoute *)route {
    // don't display anything if display type is set to none
    if (self.directionsDisplayType == MTDDirectionsDisplayTypeNone) {
        return nil;
    }

    if (![route isKindOfClass:[MTDRoute class]] || self.directionsOverlay == nil) {
        return nil;
    }

    MTDGMSDirectionsOverlayView *overlayView = nil;
    CGFloat overlayLineWidthFactor = [self.mtd_proxy askDelegateForLineWidthFactorOfOverlay:self.directionsOverlay];
    Class directionsOverlayClass = MTDOverriddenClass([MTDGMSDirectionsOverlayView class]);

    if (directionsOverlayClass != Nil) {
        overlayView = [[directionsOverlayClass alloc] initWithDirectionsOverlay:self.directionsOverlay route:route];
        UIColor *overlayColor = [self.mtd_proxy askDelegateForColorOfRoute:route ofOverlay:self.directionsOverlay];

        // If we always set the color it breaks UIAppearance because it deactivates the proxy color if we
        // call the setter, even if we don't accept nil there.
        if (overlayColor != nil) {
            overlayView.strokeColor = overlayColor;
        }
        // same goes for the line width factor
        if (overlayLineWidthFactor > 0.f) {
            overlayView.overlayLineWidthFactor = overlayLineWidthFactor;
        }
    }

    return overlayView;
}

@end
