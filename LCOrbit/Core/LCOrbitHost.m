#import "LCOrbitHost.h"
#import <objc/message.h>

@implementation LCOrbitHost
+ (id)callHostSelector:(NSString *)name {
    SEL sel=NSSelectorFromString(name);
    if(![NSUserDefaults respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,sel);
}
+ (NSUserDefaults *)hostDefaults {
    id defaults=[self callHostSelector:@"lcUserDefaults"];
    return [defaults isKindOfClass:NSUserDefaults.class]?defaults:NSUserDefaults.standardUserDefaults;
}
+ (NSString *)appGroupPath { return [self callHostSelector:@"lcAppGroupPath"]; }
+ (NSDictionary *)guestInfo {
    id value=[self callHostSelector:@"guestAppInfo"];
    return [value isKindOfClass:NSDictionary.class]?value:nil;
}
+ (NSString *)guestIdentifier {
    return [self callHostSelector:@"lcGuestAppId"] ?: NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
}
+ (UIWindowScene *)activeScene {
    if(@available(iOS 13.0,*)) {
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if([scene isKindOfClass:UIWindowScene.class] &&
               scene.activationState==UISceneActivationStateForegroundActive)
                return (UIWindowScene *)scene;
    }
    return nil;
}
+ (BOOL)isLiveProcess {
    SEL selector=NSSelectorFromString(@"isLiveProcess");
    if([NSUserDefaults respondsToSelector:selector] &&
       ((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,selector)) return YES;
    NSString *process=NSProcessInfo.processInfo.processName ?: @"";
    NSString *bundlePath=NSBundle.mainBundle.bundlePath ?: @"";
    return [process containsString:@"LiveProcess"] ||
           [process containsString:@"Multitask"] ||
           [bundlePath hasSuffix:@".appex"] ||
           [bundlePath containsString:@"/LiveProcess/"];
}
+ (BOOL)isSideStore {
    SEL selector=NSSelectorFromString(@"isSideStore");
    return [NSUserDefaults respondsToSelector:selector] &&
           ((BOOL(*)(id,SEL))objc_msgSend)(NSUserDefaults.class,selector);
}
+ (BOOL)isHostUI {
    // A Guest has guestAppInfo even when its bundle lives in the shared App
    // Group, so its presence takes precedence over all host-class heuristics.
    if([self guestInfo] || [self isLiveProcess]) return NO;

    // Match LCSwitcher's own LiveContainer host-process detection. Some LC
    // builds expose the host classes but omit one or more NSUserDefaults
    // convenience selectors; those missing selectors must not disable the UI.
    NSString *bundlePath=NSBundle.mainBundle.bundlePath ?: @"";
    if([bundlePath containsString:@"/Documents/Applications/"]) return NO;
    NSArray<NSString *> *hostClasses=@[
        @"DecoratedAppSceneViewController",
        @"LiveContainer.DecoratedAppSceneViewController",
        @"LiveContainerSwiftUI.DecoratedAppSceneViewController",
        @"PiPManager",
        @"LiveContainer.PiPManager",
        @"LiveContainerSwiftUI.PiPManager",
        @"LCMultitaskSceneViewController",
        @"LiveContainer.LCMultitaskSceneViewController",
        @"LiveContainerSwiftUI.LCMultitaskSceneViewController",
        @"GnoixMultitaskBridge",
        @"GnoixHostUI.GnoixMultitaskBridge",
        @"Gnoix.GnoixMultitaskBridge"
    ];
    for(NSString *name in hostClasses) if(NSClassFromString(name)) return YES;

    NSBundle *hostBundle=[self callHostSelector:@"lcMainBundle"];
    if([hostBundle isKindOfClass:NSBundle.class] &&
       [hostBundle.bundlePath isEqualToString:NSBundle.mainBundle.bundlePath]) return YES;
    return NO;
}
+ (BOOL)isSupportedGuest {
    if(![self activeScene] || ![self guestInfo] || [self isSideStore] || [self isLiveProcess]) return NO;
    return YES;
}
@end
