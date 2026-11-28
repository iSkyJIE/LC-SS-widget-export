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
    SEL initializer = NSSelectorFromString(@"initWithName:folderName:bundleId:version:dataUUID:appPath:icon:isJITEnabled:");
    if (!modelClass || ![modelClass instancesRespondToSelector:initializer]) return nil;

    NSString *folder = FMAdapterString(target[@"path"]);
    NSString *uuid = FMAdapterString(target[@"uuid"]);
    NSString *path = FMAdapterString(target[@"folder"]);
    if (!folder.length || !uuid.length || !path.length) return nil;

    // Build the exact public LCSwitcher model from the already revalidated
    // FloatingMenu inventory record. This also supports shared-container apps,
    // which the upstream scanInstalledApps currently does not enumerate.
    NSString *name = FMAdapterString(target[@"title"]);
    NSString *bundle = FMAdapterString(target[@"bundle"]);
    NSString *version = @"";
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [path stringByAppendingPathComponent:@"Info.plist"]];
    if ([info isKindOfClass:NSDictionary.class])
        version = FMAdapterString(info[@"CFBundleShortVersionString"]);
    BOOL jit = NO;
    NSDictionary *lcInfo = [NSDictionary dictionaryWithContentsOfFile:
        [path stringByAppendingPathComponent:@"LCAppInfo.plist"]];
    if ([lcInfo isKindOfClass:NSDictionary.class])
        jit = FMAdapterFlag(lcInfo[@"isJITNeeded"]) || FMAdapterFlag(lcInfo[@"isJITEnabled"]);

    id allocated = ((id (*)(id, SEL))objc_msgSend)(modelClass, @selector(alloc));
    id (*initCall)(id, SEL, id, id, id, id, id, id, id, BOOL) =
        (id (*)(id, SEL, id, id, id, id, id, id, id, BOOL))objc_msgSend;
    return initCall(allocated, initializer, name, folder, bundle, version, uuid, path, nil, jit);
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
    if (FMAdapterFlag(app[@"shared"])) {
        // LCSwitcher's current public launcher resolves private Documents/Applications
        // paths only. Keep shared-app launches on FloatingMenu's scope-aware service.
        return [LCOrbitGuestService launchGuest:app error:error];
    }
    id upstream = [self freshUpstreamAppForDictionary:app];
    if (!upstream)
        return FMAdapterFail(error, 2, @"无法构造 LCSwitcher 应用记录，请刷新应用列表。");

    // The upstream method invokes setupIfNeeded internally and performs the
    // handoff asynchronously. Do not block the main thread waiting for completion.
    ((void (*)(id, SEL, id, id))objc_msgSend)(cls, selector, upstream, ^(BOOL finished) {
        if (!finished) NSLog(@"[LCFloatingMenu][LCSwitcher] app handoff did not finish: %@",
            FMAdapterString(app[@"identity"]));
    });
    return YES;
}

+ (BOOL)launchGuestPath:(NSString *)path uuid:(NSString *)uuid error:(NSError **)error {
    if (![path isEqualToString:@"ui"])
        return [LCOrbitGuestService launchGuestPath:path uuid:uuid error:error];

    Class cls = FMLCSwitcherClass();
    SEL selector = NSSelectorFromString(@"presentTransitionAndReturnHomeWithCompletion:");
    if (![self isAvailable] || ![cls respondsToSelector:selector])
        return FMAdapterFail(error, 1, @"没有检测到 LCSwitcher，无法调用返回主页接口。");
    ((void (*)(id, SEL, id))objc_msgSend)(cls, selector, ^(BOOL finished) {
        if (!finished) NSLog(@"[LCFloatingMenu][LCSwitcher] return-home handoff did not finish");
    });
    return YES;
}

@end
