import SwiftUI
import UIKit

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
        tab == .input ? .landscape : .all
    }
}

@MainActor
enum OrientationController {
    static func apply(for tab: AppTab) {
        let mask = AppOrientationPolicy.mask(for: tab)
        guard AppDelegate.supportedOrientations != mask else { return }
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
                print("Orientation request failed: \(error)")
            }
        } else {
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
