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
    /// The input page is the keyboard and the trackpad, which need the long edge.
    /// Setup and Settings are portrait pages: the dock that is the only navigation
    /// on those tabs is portrait-only, and keeping them portrait means opening either
    /// one from the input page asks the system to turn the device back, instead of
    /// leaving a landscape page with no dock and no way out.
    static func mask(for tab: AppTab) -> UIInterfaceOrientationMask {
        switch tab {
        case .input:
            .landscape
        case .setup, .settings:
            .portrait
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
            //
            // Only the two masks the policy actually returns get a request:
            // there is no single orientation that stands for `.all`, and
            // pretending there is would turn the device for a page that allows
            // every orientation.
            if mask == .landscape {
                UIDevice.current.setValue(
                    UIInterfaceOrientation.landscapeRight.rawValue,
                    forKey: "orientation"
                )
            } else if mask == .portrait {
                UIDevice.current.setValue(
                    UIInterfaceOrientation.portrait.rawValue,
                    forKey: "orientation"
                )
            }
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
