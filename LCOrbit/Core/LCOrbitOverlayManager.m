#import "LCOrbitOverlayManager.h"
#import <math.h>

// Transparent regions must not steal interaction from the active Guest.
@interface LCOrbitPassThroughView : UIView @end
@implementation LCOrbitPassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *target=[super hitTest:point withEvent:event];
    return target==self?nil:target;
}
@end
@interface LCOrbitPassThroughWindow : UIWindow @end
@implementation LCOrbitPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if(!event || event.type==UIEventTypeTouches) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOrbitScreenTouchedNotification" object:nil];
    }
    UIView *target=[super hitTest:point withEvent:event];
    return target==self || target==self.rootViewController.view?nil:target;
}
@end

@interface LCOrbitOverlayViewController : UIViewController
@property(nonatomic,weak) LCOrbitOverlayManager *manager;
@end
@implementation LCOrbitOverlayViewController
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    __weak typeof(self) weakSelf=self;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
        [weakSelf.manager updateFrame];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
        [weakSelf.manager updateFrame];
    }];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.manager updateFrame];
}
@end

@implementation LCOrbitOverlayManager {
    UIWindow *_window;
    NSMutableDictionary<NSString *,UIView *> *_modules;
    CGRect _lastReportedSceneBounds;
    BOOL _hasReportedSceneBounds;
}
- (instancetype)init {
    if((self=[super init])) _modules=[NSMutableDictionary dictionary];
    return self;
}
- (UIWindow *)window { return _window; }
- (void)clearScene {
    for(UIView *layer in _modules.allValues) [layer removeFromSuperview];
    [_modules removeAllObjects];
    _window.hidden=YES;
    _window.rootViewController=nil;
    _window=nil;
}
- (UIView *)mountModule:(NSString *)identifier inScene:(UIWindowScene *)scene {
    NSAssert(NSThread.isMainThread,@"Overlay UI must be used on the main thread");
    if(!identifier.length || !scene) return nil;
    if(_window && _window.windowScene!=scene) [self clearScene];
    BOOL created=NO;
    if(!_window) {
        CGRect frame=scene.coordinateSpace.bounds;
        if(!isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
           !isfinite(frame.size.width) || !isfinite(frame.size.height) ||
           frame.size.width<=0 || frame.size.height<=0) return nil;
        LCOrbitPassThroughWindow *window=[[LCOrbitPassThroughWindow alloc] initWithWindowScene:scene];
        window.frame=frame;
        window.backgroundColor=UIColor.clearColor;
        window.windowLevel=UIWindowLevelNormal+75;
        LCOrbitOverlayViewController *vc=[LCOrbitOverlayViewController new];
        vc.manager=self;
        vc.view.backgroundColor=UIColor.clearColor;
        window.rootViewController=vc;
        // Publish the reference before the visibility notification can fire.
        _window=window;
        created=YES;
    }
    [self updateFrame];
    UIView *layer=_modules[identifier];
    if(!layer) {
        layer=[[LCOrbitPassThroughView alloc] initWithFrame:_window.rootViewController.view.bounds];
        layer.backgroundColor=UIColor.clearColor;
        layer.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [_window.rootViewController.view addSubview:layer];
        _modules[identifier]=layer;
    }
    // Mount the module before displaying. Never make the overlay the key window.
    if(created) _window.hidden=NO;
    return layer;
}
- (void)updateFrame {
    UIWindow *window=_window;
    if(!window) return;
    CGRect frame=window.windowScene.coordinateSpace.bounds;
    if(!isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
       !isfinite(frame.size.width) || !isfinite(frame.size.height) ||
       frame.size.width<=0 || frame.size.height<=0) return;

    BOOL geometryChanged=!_hasReportedSceneBounds ||
        !CGRectEqualToRect(_lastReportedSceneBounds,frame);
    _lastReportedSceneBounds=frame;
    _hasReportedSceneBounds=YES;
    if(!CGRectEqualToRect(window.frame,frame)) {
        window.frame=frame;
        geometryChanged=YES;
    }
    CGRect bounds=window.rootViewController.view.bounds;
    if(isfinite(bounds.size.width) && isfinite(bounds.size.height) &&
       bounds.size.width>0 && bounds.size.height>0) {
        for(UIView *layer in _modules.allValues) {
            if(!CGRectEqualToRect(layer.frame,bounds)) {
                layer.frame=bounds;
                geometryChanged=YES;
            }
        }
    }
    // A scene can resize without changing device orientation (fold/unfold,
    // Stage Manager, or a window resize). Notify the owning module only after
    // the overlay and its content layer have adopted the new scene geometry.
    if(geometryChanged) {
        __weak typeof(self) weakSelf=self;
        dispatch_async(dispatch_get_main_queue(), ^{
            if(!weakSelf || weakSelf.window!=window) return;
            [NSNotificationCenter.defaultCenter postNotificationName:@"LCOrbitOverlayLayoutDidChangeNotification"
                object:window];
        });
    }
}
- (void)unmountModule:(NSString *)identifier {
    UIView *layer=_modules[identifier];
    [layer removeFromSuperview];
    [_modules removeObjectForKey:identifier];
    if(_modules.count==0) [self clearScene];
}
- (void)setModule:(NSString *)identifier visible:(BOOL)visible {
    _modules[identifier].hidden=!visible;
}
@end
