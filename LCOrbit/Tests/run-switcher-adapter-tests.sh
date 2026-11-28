#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HEADER="$ROOT/LCFloatingMenu/LCOrbitSwitcherAdapter.h"
SOURCE="$ROOT/LCFloatingMenu/LCOrbitSwitcherAdapter.m"
MENU="$ROOT/LCFloatingMenu/LCFloatingMenu.m"
BUILD="$ROOT/LCOrbit/Build/build.sh"

test -s "$HEADER"
test -s "$SOURCE"
grep -q 'LCOrbitGuestService installedApps' "$SOURCE"
grep -q 'LCOrbitGuestService launchGuest:fresh error:' "$SOURCE"
grep -q 'launchGuestPath:@"ui"' "$SOURCE"
grep -q 'LCOrbitMultitask showHome' "$SOURCE"
grep -q 'LCOrbitSwitcherAdapter launchGuestDictionary:target error:' "$MENU"
grep -q 'LCOrbitSwitcherAdapter launchGuestPath:path uuid:uuid error:' "$MENU"
grep -q 'LCOrbitSwitcherAdapter.m' "$BUILD"

# Never link LCSwitcher's original Objective-C class names or its constructor
# hooks into FloatingMenu: that would install a second bead and Dock replacement.
if grep -Eq '@(interface|implementation) LCSwitcher([[:space:]:<]|$)|LCSwitcherInit|LCInstallMultitaskSidebarReplacementHooks' "$SOURCE" "$HEADER"; then
    echo "LCSwitcher runtime collision/overlay hook detected" >&2
    exit 1
fi

echo "LCSwitcher compatibility adapter tests passed"
