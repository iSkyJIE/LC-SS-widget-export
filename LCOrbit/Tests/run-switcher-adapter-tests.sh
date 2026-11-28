#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HEADER="$ROOT/LCFloatingMenu/LCOrbitSwitcherAdapter.h"
SOURCE="$ROOT/LCFloatingMenu/LCOrbitSwitcherAdapter.m"
MENU="$ROOT/LCFloatingMenu/LCFloatingMenu.m"
BUILD="$ROOT/LCOrbit/Build/build.sh"

test -s "$HEADER"
test -s "$SOURCE"
grep -q 'NSClassFromString(@"LCSwitcher")' "$SOURCE"
grep -q 'NSClassFromString(@"LCSwitcherAppInfo")' "$SOURCE"
grep -q 'scanInstalledApps' "$SOURCE"
grep -q 'presentTransitionAndSwitchToApp:completion:' "$SOURCE"
grep -q 'presentTransitionAndReturnHomeWithCompletion:' "$SOURCE"
grep -q 'initWithName:folderName:bundleId:version:dataUUID:appPath:icon:isJITEnabled:' "$SOURCE"
grep -q 'LCOrbitSwitcherAdapter launchGuestDictionary:target error:' "$MENU"
grep -q 'LCOrbitSwitcherAdapter launchGuestPath:path uuid:uuid error:' "$MENU"
grep -q 'LCOrbitSwitcherAdapter.m' "$BUILD"

# Do not define upstream runtime classes or install its constructor/hooks ourselves.
if grep -Eq '@(interface|implementation) LCSwitcher([[:space:]:<]|$)|LCSwitcherInit|LCInstallMultitaskSidebarReplacementHooks' "$SOURCE" "$HEADER"; then
    echo "LCSwitcher runtime collision/overlay hook detected" >&2
    exit 1
fi

# Public handoff is asynchronous; never block the main thread on its completion.
if grep -Eq 'dispatch_semaphore_(wait|create)' "$SOURCE"; then
    echo "blocking wait found in LCSwitcher adapter" >&2
    exit 1
fi

echo "LCSwitcher public API bridge tests passed"
