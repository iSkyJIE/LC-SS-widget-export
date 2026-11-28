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
    return [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
}
static void FMAdapterComplete(void (^completion)(BOOL), BOOL result) {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
}

@implementation LCOrbitSwitcherAdapter

+ (void)setupIfNeeded {
    // LCFloatingMenu owns the sole overlay and lifecycle. This compatibility
    // entry point intentionally does not install LCSwitcher's bead or hooks.
}

+ (NSArray<LCOrbitSwitcherAppInfo *> *)scanInstalledApps {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *item in [LCOrbitGuestService installedApps]) {
        LCOrbitSwitcherAppInfo *app = [LCOrbitSwitcherAppInfo new];
        app.name = FMAdapterString(item[@"title"]);
        app.folderName = FMAdapterString(item[@"path"]);
        app.bundleId = FMAdapterString(item[@"bundle"]);
        app.dataUUID = FMAdapterString(item[@"uuid"]);
        app.appPath = FMAdapterString(item[@"folder"]);
        app.identity = FMAdapterString(item[@"identity"]);
        app.status = FMAdapterString(item[@"status"]);
        app.isLaunchable = FMAdapterFlag(item[@"launchable"]);
        app.isShared = FMAdapterFlag(item[@"shared"]);
        app.isHidden = FMAdapterFlag(item[@"hidden"]);
        app.isLocked = FMAdapterFlag(item[@"locked"]);
        app.isBuiltIn = FMAdapterFlag(item[@"builtin"]);

        NSDictionary *info = app.appPath.length
            ? [NSDictionary dictionaryWithContentsOfFile:[app.appPath stringByAppendingPathComponent:@"Info.plist"]]
            : nil;
        app.version = FMAdapterString(info[@"CFBundleShortVersionString"]);
        NSDictionary *lcInfo = app.appPath.length
            ? [NSDictionary dictionaryWithContentsOfFile:[app.appPath stringByAppendingPathComponent:@"LCAppInfo.plist"]]
            : nil;
        app.isJITEnabled = FMAdapterFlag(lcInfo[@"isJITNeeded"]) || FMAdapterFlag(lcInfo[@"isJITEnabled"]);
        [result addObject:app];
    }
    return [result copy];
}

+ (NSDictionary *)freshDictionaryForSwitcherApp:(LCOrbitSwitcherAppInfo *)app {
    if (![app isKindOfClass:LCOrbitSwitcherAppInfo.class] || app.isBuiltIn) return nil;
    NSString *wantedPath = FMAdapterCanonicalPath(app.appPath);
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    for (NSDictionary *candidate in [LCOrbitGuestService installedApps]) {
        BOOL sameIdentity = app.identity.length && [candidate[@"identity"] isEqualToString:app.identity];
        BOOL samePath = wantedPath.length &&
            [FMAdapterCanonicalPath(FMAdapterString(candidate[@"folder"])) isEqualToString:wantedPath];
        BOOL sameLegacyKey = !app.identity.length && !wantedPath.length &&
            [candidate[@"path"] isEqualToString:app.folderName] &&
            [candidate[@"uuid"] isEqualToString:app.dataUUID];
        if (sameIdentity || samePath || sameLegacyKey) [matches addObject:candidate];
    }
    return matches.count == 1 ? matches.firstObject : nil;
}

+ (void)presentTransitionAndSwitchToApp:(LCOrbitSwitcherAppInfo *)app
                            completion:(void (^)(BOOL))completion {
    [self setupIfNeeded];
    NSDictionary *fresh = [self freshDictionaryForSwitcherApp:app];
    NSError *error = nil;
    BOOL accepted = fresh && [LCOrbitGuestService launchGuest:fresh error:&error];
    FMAdapterComplete(completion, accepted);
}

+ (void)presentTransitionAndReturnHomeWithCompletion:(void (^)(BOOL))completion {
    [self setupIfNeeded];
    if ([LCOrbitMultitask isEnabled]) {
        [LCOrbitMultitask showHome];
        FMAdapterComplete(completion, YES);
        return;
    }
    NSError *error = nil;
    BOOL accepted = [LCOrbitGuestService launchGuestPath:@"ui" uuid:nil error:&error];
    FMAdapterComplete(completion, accepted);
}

+ (NSString *)realHostDocumentsDirectory {
    const char *realDocs = getenv("GNOIX_REAL_DOCUMENTS");
    if (realDocs && realDocs[0]) return [NSString stringWithUTF8String:realDocs];
    const char *home = getenv("LC_HOME_PATH");
    if (home && home[0]) return [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@"Documents"];
    NSString *homePath = NSHomeDirectory();
    NSString *docs = [homePath stringByAppendingPathComponent:@"Documents"];
    BOOL isDirectory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:docs isDirectory:&isDirectory] && isDirectory) return docs;
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: @"";
}

+ (NSString *)currentGuestFolderName {
    const char *appID = getenv("LC_APP_ID");
    if (appID && appID[0]) return [NSString stringWithUTF8String:appID];
    NSDictionary *guest = [LCOrbitHost guestInfo];
    NSString *bundlePath = FMAdapterString(guest[@"bundlePath"]);
    if (bundlePath.length) return bundlePath.lastPathComponent;
    return @"";
}

+ (NSString *)hostBundleIdentifier {
    SEL selector = NSSelectorFromString(@"lcMainBundle");
    if ([NSUserDefaults respondsToSelector:selector]) {
        NSBundle *(*call)(id, SEL) = (NSBundle *(*)(id, SEL))objc_msgSend;
        NSBundle *host = call(NSUserDefaults.class, selector);
        if (host.bundleIdentifier.length) return host.bundleIdentifier;
    }
    return NSBundle.mainBundle.bundleIdentifier ?: @"";
}

+ (BOOL)isContainerGuestRunning {
    if (![LCOrbitHost guestInfo]) return NO;
    for (NSString *name in @[@"isSideStore", @"isLiveProcess"]) {
        SEL selector = NSSelectorFromString(name);
        if ([NSUserDefaults respondsToSelector:selector]) {
            BOOL (*call)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
            if (call(NSUserDefaults.class, selector)) return NO;
        }
    }
    return YES;
}

+ (BOOL)launchGuestDictionary:(NSDictionary *)app error:(NSError **)error {
    return [LCOrbitGuestService launchGuest:app error:error];
}

+ (BOOL)launchGuestPath:(NSString *)path uuid:(NSString *)uuid error:(NSError **)error {
    return [LCOrbitGuestService launchGuestPath:path uuid:uuid error:error];
}

@end
