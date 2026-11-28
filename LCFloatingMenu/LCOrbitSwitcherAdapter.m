#import "LCOrbitSwitcherAdapter.h"
#import "../LCOrbit/Core/LCOrbitGuestService.h"
#import "../LCOrbit/Core/LCOrbitHost.h"
#import "../LCOrbit/Core/LCOrbitMultitask.h"
#import <objc/message.h>
#import <stdlib.h>

@implementation LCOrbitSwitcherAppInfo
@end

static NSString *FMAdapterString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}
static BOOL FMAdapterFlag(id value) {
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}
static NSString *FMAdapterCanonicalPath(NSString *path) {
    return path.length ? [[path stringByStandardizingPath] stringByResolvingSymlinksInPath] : @"";
}
static void FMAdapterComplete(void (^completion)(BOOL), BOOL result) {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
}
static Class FMLCSwitcherClass(void) {
    return NSClassFromString(@"LCSwitcher");
}
static Class FMLCSwitcherAppInfoClass(void) {
    return NSClassFromString(@"LCSwitcherAppInfo");
}
static NSError *FMAdapterError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"LCOrbit.SwitcherAdapter" code:code
        userInfo:@{NSLocalizedDescriptionKey:message ?: @"LCSwitcher 接口调用失败。"}];
}
static BOOL FMAdapterFail(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = FMAdapterError(code, message);
    return NO;
}
static id FMReadProperty(id object, NSString *key) {
    if (!object || !key.length) return nil;
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}
static NSString *FMModelString(id object, NSString *key) {
    return FMAdapterString(FMReadProperty(object, key));
}
static BOOL FMModelFlag(id object, NSString *key) {
    return FMAdapterFlag(FMReadProperty(object, key));
}

@implementation LCOrbitSwitcherAdapter

+ (BOOL)isAvailable {
    Class cls = FMLCSwitcherClass();
    Class model = FMLCSwitcherAppInfoClass();
    return cls && model &&
        [cls respondsToSelector:NSSelectorFromString(@"scanInstalledApps")] &&
        [cls respondsToSelector:NSSelectorFromString(@"presentTransitionAndSwitchToApp:completion:")] &&
        [cls respondsToSelector:NSSelectorFromString(@"presentTransitionAndReturnHomeWithCompletion:")];
}

+ (void)setupIfNeeded {
    // LCSwitcher's setupIfNeeded installs its own bead, drawer and hooks.
    // FloatingMenu owns the visible UI, so it must not install a second overlay.
    // The public scan/switch/return APIs below are called directly instead.
}

+ (NSArray<LCOrbitSwitcherAppInfo *> *)scanInstalledApps {
    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"scanInstalledApps");
    if (!cls || ![cls respondsToSelector:selector]) {
        NSLog(@"[LCFloatingMenu][LCSwitcher] API unavailable: scanInstalledApps");
        return @[];
    }
    NSArray *upstream = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
    if (![upstream isKindOfClass:NSArray.class]) return @[];

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:upstream.count];
    for (id item in upstream) {
        if (![item isKindOfClass:FMLCSwitcherAppInfoClass()]) continue;
        LCOrbitSwitcherAppInfo *app = [LCOrbitSwitcherAppInfo new];
        app.name = FMModelString(item, @"name");
        app.folderName = FMModelString(item, @"folderName");
        app.bundleId = FMModelString(item, @"bundleId");
        app.version = FMModelString(item, @"version");
        app.dataUUID = FMModelString(item, @"dataUUID");
        app.appPath = FMModelString(item, @"appPath");
        id icon = FMReadProperty(item, @"icon");
        app.icon = [icon isKindOfClass:UIImage.class] ? icon : nil;
        app.isJITEnabled = FMModelFlag(item, @"isJITEnabled");
        [result addObject:app];
    }
    return [result copy];
}

+ (id)freshUpstreamAppForDictionary:(NSDictionary *)target {
    if (![target isKindOfClass:NSDictionary.class] || FMAdapterFlag(target[@"builtin"])) return nil;
    Class modelClass = FMLCSwitcherAppInfoClass();
    if (!modelClass) return nil;
    NSString *wantedPath = FMAdapterCanonicalPath(FMAdapterString(target[@"folder"]));
    NSString *wantedFolder = FMAdapterString(target[@"path"]);
    NSString *wantedUUID = FMAdapterString(target[@"uuid"]);
    NSString *wantedBundle = FMAdapterString(target[@"bundle"]);
    NSMutableArray *matches = [NSMutableArray array];
    for (id candidate in [self scanInstalledApps]) {
        BOOL samePath = wantedPath.length &&
            [FMAdapterCanonicalPath(candidate.appPath) isEqualToString:wantedPath];
        BOOL sameFolderAndUUID = wantedFolder.length && wantedUUID.length &&
            [candidate.folderName isEqualToString:wantedFolder] &&
            [candidate.dataUUID isEqualToString:wantedUUID];
        BOOL sameBundle = wantedBundle.length && candidate.bundleId.length &&
            [candidate.bundleId isEqualToString:wantedBundle];
        if ((samePath || sameFolderAndUUID) && (!wantedBundle.length || sameBundle))
            [matches addObject:candidate];
    }
    if (matches.count != 1) return nil;

    // Reacquire the actual LCSwitcherAppInfo instance. The namespaced model above
    // is only a safe read-only projection for FloatingMenu; it is never passed
    // across the upstream Objective-C API boundary.
    NSArray *raw = ((id (*)(id, SEL))objc_msgSend)(FMLCSwitcherClass(),
        NSSelectorFromString(@"scanInstalledApps"));
    LCOrbitSwitcherAppInfo *match = matches.firstObject;
    for (id item in raw) {
        NSString *path = FMAdapterCanonicalPath(FMModelString(item, @"appPath"));
        NSString *folder = FMModelString(item, @"folderName");
        NSString *uuid = FMModelString(item, @"dataUUID");
        NSString *bundle = FMModelString(item, @"bundleId");
        BOOL same = (path.length && [path isEqualToString:FMAdapterCanonicalPath(match.appPath)]) ||
            ([folder isEqualToString:match.folderName] && [uuid isEqualToString:match.dataUUID] &&
             [bundle isEqualToString:match.bundleId]);
        if (same) return item;
    }
    return nil;
}

+ (void)presentTransitionAndSwitchToApp:(LCOrbitSwitcherAppInfo *)app
                            completion:(void (^)(BOOL))completion {
    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"presentTransitionAndSwitchToApp:completion:");
    if (![self isAvailable] || ![cls respondsToSelector:selector] ||
        ![app isKindOfClass:LCOrbitSwitcherAppInfo.class]) {
        FMAdapterComplete(completion, NO);
        return;
    }
    // This public convenience API accepts the real upstream model, not our projection.
    NSDictionary *target = @{@"folder":app.appPath ?: @"", @"path":app.folderName ?: @"",
        @"uuid":app.dataUUID ?: @"", @"bundle":app.bundleId ?: @""};
    id upstream = [self freshUpstreamAppForDictionary:target];
    if (!upstream) { FMAdapterComplete(completion, NO); return; }
    ((void (*)(id, SEL, id, id))objc_msgSend)(cls, selector, upstream, completion);
}

+ (void)presentTransitionAndReturnHomeWithCompletion:(void (^)(BOOL))completion {
    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"presentTransitionAndReturnHomeWithCompletion:");
    if (![self isAvailable] || ![cls respondsToSelector:selector]) {
        FMAdapterComplete(completion, NO);
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(cls, selector, completion);
}

+ (NSString *)realHostDocumentsDirectory {
    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"realHostDocumentsDirectory");
    if (cls && [cls respondsToSelector:selector]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    const char *realDocs = getenv("GNOIX_REAL_DOCUMENTS");
    if (realDocs && realDocs[0]) return [NSString stringWithUTF8String:realDocs];
    const char *home = getenv("LC_HOME_PATH");
    if (home && home[0]) return [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"Documents"];
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: @"";
}

+ (NSString *)currentGuestFolderName {
    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"currentGuestFolderName");
    if (cls && [cls respondsToSelector:selector]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
        if ([value isKindOfClass:NSString.class]) return value;
    }
    const char *appID = getenv("LC_APP_ID");
    return (appID && appID[0]) ? [NSString stringWithUTF8String:appID] : @"";
}

+ (NSString *)hostBundleIdentifier {
    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"hostBundleIdentifier");
    if (cls && [cls respondsToSelector:selector]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    SEL hostSelector = NSSelectorFromString(@"lcMainBundle");
    if ([NSUserDefaults respondsToSelector:hostSelector]) {
        NSBundle *(*call)(id, SEL) = (NSBundle *(*)(id, SEL))objc_msgSend;
        NSBundle *host = call(NSUserDefaults.class, hostSelector);
        if (host.bundleIdentifier.length) return host.bundleIdentifier;
    }
    return NSBundle.mainBundle.bundleIdentifier ?: @"";
}

+ (BOOL)isContainerGuestRunning {
    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"isContainerGuestRunning");
    if (cls && [cls respondsToSelector:selector])
        return ((BOOL (*)(id, SEL))objc_msgSend)(cls, selector);
    return [LCOrbitHost guestInfo] != nil;
}

+ (BOOL)launchGuestDictionary:(NSDictionary *)app error:(NSError **)error {
    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"presentTransitionAndSwitchToApp:completion:");
    if (![self isAvailable] || ![cls respondsToSelector:selector])
        return FMAdapterFail(error, 1, @"没有检测到 LCSwitcher。请确认 LCSwitcher 已安装并注入当前进程。");
    id upstream = [self freshUpstreamAppForDictionary:app];
    if (!upstream)
        return FMAdapterFail(error, 2, @"LCSwitcher 应用记录无法唯一匹配，请刷新应用列表。");

    // Upstream API is asynchronous and owns the handoff animation. Its completion
    // reports acceptance; do not invoke LCOrbitGuestService's parallel launcher.
    __block BOOL accepted = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    void (^completion)(BOOL) = ^(BOOL finished) {
        accepted = finished;
        dispatch_semaphore_signal(semaphore);
    };
    ((void (*)(id, SEL, id, id))objc_msgSend)(cls, selector, upstream, completion);
    // The public API schedules handoff work itself. A short bounded wait lets the
    // existing synchronous menu contract receive the result without blocking UI.
    long wait = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)));
    if (wait != 0) {
        if (error) *error = FMAdapterError(3, @"LCSwitcher 已接收切换请求，正在执行交接。");
        return YES;
    }
    return accepted ? YES : FMAdapterFail(error, 4, @"LCSwitcher 未能完成应用交接。");
}

+ (BOOL)launchGuestPath:(NSString *)path uuid:(NSString *)uuid error:(NSError **)error {
    if (![path isEqualToString:@"ui"])
        return [LCOrbitGuestService launchGuestPath:path uuid:uuid error:error];

    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"presentTransitionAndReturnHomeWithCompletion:");
    if (![self isAvailable] || ![cls respondsToSelector:selector])
        return FMAdapterFail(error, 1, @"没有检测到 LCSwitcher，无法调用返回主页接口。");
    __block BOOL accepted = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    void (^completion)(BOOL) = ^(BOOL finished) {
        accepted = finished;
        dispatch_semaphore_signal(semaphore);
    };
    ((void (*)(id, SEL, id))objc_msgSend)(cls, selector, completion);
    long wait = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)));
    if (wait != 0) return YES;
    return accepted ? YES : FMAdapterFail(error, 4, @"LCSwitcher 未能返回宿主主页。");
}

@end
