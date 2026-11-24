//
//  LCDuoGeometry.swift
//  LiveContainer
//
//  iPhone Duo adaptation: geometry helpers shared by the multitask dock,
//  virtual windows and decorated guest windows.
//
//  Design notes (do not hardcode the device):
//  - There is no public fold-state API to sniff. Everything here is driven
//    by the live scene size / size class, so it also stays correct on iPad
//    and on future foldables.
//  - iPhone Duo (2026): outer display 5.4" 1398x2034, inner display 7.6"
//    1878x2670, both the same ~1.4 aspect ratio. At the usual @3x scale
//    that is ~466x678pt folded and ~626x890pt unfolded. Those point sizes
//    are derived, not measured on device: verify them on a real Duo and
//    adjust only the threshold below if they are off. No behaviour in this
//    file depends on the exact numbers, only on the 600pt expanded
//    threshold, which sits between the two displays either way.
//  - Deployment target is iOS 15, so only APIs available there are used.
//

import UIKit

/// The two live geometries an iPhone Duo scene can be in.
@objc public enum LCDuoFormFactor: Int {
    case outer = 0
    case inner = 1
}

@objc public final class LCDuoGeometry: NSObject {

    /// Width (in points) at and above which a scene counts as expanded.
    /// Duo outer is ~466pt wide, Duo inner ~626pt wide; iPad widths are
    /// above this too, which is the intended behaviour.
    @objc public static let expandedWidthThreshold: CGFloat = 600

    /// Classify a live scene size. A regular horizontal size class is also
    /// treated as expanded, so iPad-style layouts keep working.
    @objc public static func formFactor(
        for size: CGSize,
        horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> LCDuoFormFactor {
        if horizontalSizeClass == .regular || size.width >= expandedWidthThreshold {
            return .inner
        }
        return .outer
    }

    @objc public static func isExpanded(
        size: CGSize,
        horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> Bool {
        return formFactor(for: size, horizontalSizeClass: horizontalSizeClass) == .inner
    }

    /// The scene that is actually on screen. `connectedScenes.first` is
    /// wrong as soon as there is more than one scene (multitask, and the
    /// Duo's outer/inner transition): prefer the foreground-active scene.
    @objc public static func keyWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
        for scene in scenes {
            if let windowScene = scene as? UIWindowScene,
               scene.activationState == .foregroundActive {
                return windowScene
            }
        }
        return scenes.first as? UIWindowScene
    }

    /// The key window of the foreground scene, falling back to any window.
    @objc public static func keyWindow() -> UIWindow? {
        if let scene = keyWindowScene() {
            if let key = scene.windows.first(where: { $0.isKeyWindow }) {
                return key
            }
            if let first = scene.windows.first {
                return first
            }
        }
        return nil
    }

    /// Initial size for a decorated (floating) guest window, proportional
    /// to the container instead of the old fixed 320x480 / 480x320.
    /// On a phone / Duo outer display this reproduces the old size almost
    /// exactly (outer portrait: ~317x475); on the unfolded inner display
    /// it grows to ~426x639 so the window is not a small island.
    /// `containerSize` is the host window size; the navigation bar height
    /// is added by the caller, as before.
    @objc public static func initialDecoratedWindowSize(
        for containerSize: CGSize,
        landscape: Bool
    ) -> CGSize {
        if landscape {
            let width = min(560, max(360, containerSize.width * 0.62))
            return CGSize(width: width, height: width * 0.66)
        } else {
            let width = min(480, max(280, containerSize.width * 0.68))
            return CGSize(width: width, height: width * 1.5)
        }
    }
}
