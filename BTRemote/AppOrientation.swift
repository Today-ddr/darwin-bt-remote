import os
import UIKit

private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "AppOrientation")

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask = .all

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}

enum AppOrientationPolicy {
    static func mask(for tab: AppTab) -> UIInterfaceOrientationMask {
        switch tab {
        case .input:
            .landscape
        case .setup, .settings:
            .all
        }
    }
}

@MainActor
enum OrientationController {
    static func apply(for tab: AppTab) {
        let mask = AppOrientationPolicy.mask(for: tab)
        // Always refresh the delegate mask, even when it already matches: a
        // previous call may have run before any scene was connected, and the
        // mask alone cannot drive rotation. Caching here would make every
        // later tab change or onAppear a silent no-op.
        AppDelegate.supportedOrientations = mask

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else {
            return
        }

        let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController

        if #available(iOS 16.0, *) {
            root?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                log.error("Orientation request failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            // iOS 15 has no public API to force an interface rotation, so this
            // sideloaded app sets the undocumented UIDevice orientation key and
            // asks UIKit to re-evaluate. Best-effort and iOS 15 only; the
            // delegate mask above stays authoritative for what is allowed.
            if mask == .landscape {
                UIDevice.current.setValue(
                    UIInterfaceOrientation.landscapeRight.rawValue,
                    forKey: "orientation"
                )
            }
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
