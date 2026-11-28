#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Namespaced compatibility model for the public LCSwitcher app record.
/// The LCSwitcher runtime classes are deliberately not linked: both tweaks may
/// be present in one process, so defining their original Objective-C class
/// names would create runtime collisions.
@interface LCOrbitSwitcherAppInfo : NSObject
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *folderName;
@property(nonatomic,copy) NSString *bundleId;
@property(nonatomic,copy) NSString *version;
@property(nonatomic,copy) NSString *dataUUID;
@property(nonatomic,copy) NSString *appPath;
@property(nonatomic,strong,nullable) UIImage *icon;
@property(nonatomic,assign) BOOL isJITEnabled;
@property(nonatomic,copy) NSString *identity;
@property(nonatomic,copy) NSString *status;
@property(nonatomic,assign) BOOL isLaunchable;
@property(nonatomic,assign) BOOL isShared;
@property(nonatomic,assign) BOOL isHidden;
@property(nonatomic,assign) BOOL isLocked;
@property(nonatomic,assign) BOOL isBuiltIn;
@end

/// LCSwitcher-compatible API backed by LCFloatingMenu's existing guarded
/// inventory and launch services. It never installs a second floating UI.
@interface LCOrbitSwitcherAdapter : NSObject
+ (void)setupIfNeeded;
+ (NSArray<LCOrbitSwitcherAppInfo *> *)scanInstalledApps;
+ (void)presentTransitionAndSwitchToApp:(LCOrbitSwitcherAppInfo *)app
                            completion:(nullable void (^)(BOOL finished))completion;
+ (void)presentTransitionAndReturnHomeWithCompletion:(nullable void (^)(BOOL finished))completion;
+ (NSString *)realHostDocumentsDirectory;
+ (NSString *)currentGuestFolderName;
+ (NSString *)hostBundleIdentifier;
+ (BOOL)isContainerGuestRunning;

/// Internal dictionary bridge used by the existing LCFloatingMenu drawer.
+ (BOOL)launchGuestDictionary:(NSDictionary *)app error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)launchGuestPath:(NSString *)path
                   uuid:(nullable NSString *)uuid
                  error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
