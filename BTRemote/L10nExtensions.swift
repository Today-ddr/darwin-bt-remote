import CoreBluetooth
import Foundation
import SwiftUI

extension CBManagerState {
    /// Shared by the Setup status row and the device list's scan footer, which both have to
    /// name a radio that cannot be used.
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .unknown: return L10n.BluetoothState.unknown
        case .resetting: return L10n.BluetoothState.resetting
        case .unsupported: return L10n.BluetoothState.unsupported
        case .unauthorized: return L10n.BluetoothState.unauthorized
        case .poweredOff: return L10n.BluetoothState.poweredOff
        case .poweredOn: return L10n.BluetoothState.poweredOn
        @unknown default: return L10n.BluetoothState.unavailable
        }
    }
}

extension L10n {
    enum DeviceInfo {
        static var title: LocalizedStringKey {
            "device_info.title"
        }

        static var info: LocalizedStringKey {
            "device_info.info"
        }

        static var device: LocalizedStringKey {
            "device_info.device"
        }

        static var name: LocalizedStringKey {
            "device_info.name"
        }

        static var identifier: LocalizedStringKey {
            "device_info.identifier"
        }

        static var done: LocalizedStringKey {
            "device_info.done"
        }
    }

    enum Setup {
        static var help: LocalizedStringKey {
            "setup.help"
        }

        static var videoInstructions: LocalizedStringKey {
            "setup.video_instructions"
        }

        static var activeLegend: LocalizedStringKey {
            "setup.active_legend"
        }

        static var lowEnergyGuide: LocalizedStringKey {
            "setup.le_guide"
        }

        static var connectFromTargetDevice: LocalizedStringKey {
            "setup.connect_from_target_device"
        }

        static var fromDevice: LocalizedStringKey {
            "setup.from_device"
        }

        static var fromDeviceStep1: LocalizedStringKey {
            "setup.from_device_step1"
        }

        static func fromDeviceStep2(_ name: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "setup.from_device_step2"),
                name
            )
        }

        static var fromDeviceStep3: LocalizedStringKey {
            "setup.from_device_step3"
        }

        static var troubleshooting: LocalizedStringKey {
            "setup.troubleshooting"
        }

        static var findGuideHint: LocalizedStringKey {
            "setup.find_guide_hint"
        }

        static var deviceNameLimitation: LocalizedStringKey {
            "setup.device_name_limitation"
        }

        static var advertisedName: LocalizedStringKey {
            "setup.advertised_name"
        }

        static var advertisedNameHint: LocalizedStringKey {
            "setup.advertised_name_hint"
        }
    }

    enum Settings {
        static var appearance: LocalizedStringKey {
            "settings.appearance"
        }

        static var themeSystem: LocalizedStringKey {
            "settings.theme.system"
        }

        static var themeLight: LocalizedStringKey {
            "settings.theme.light"
        }

        static var themeDark: LocalizedStringKey {
            "settings.theme.dark"
        }

        static var themeOLED: LocalizedStringKey {
            "settings.theme.oled"
        }

        static var oledHint: LocalizedStringKey {
            "settings.theme.oled_hint"
        }

        static var trackpad: LocalizedStringKey {
            "settings.trackpad"
        }

        static var trackingSpeed: LocalizedStringKey {
            "settings.tracking_speed"
        }

        static var scrollSpeed: LocalizedStringKey {
            "settings.scroll_speed"
        }

        static var connection: LocalizedStringKey {
            "settings.connection"
        }

        static var haptics: LocalizedStringKey {
            "settings.haptics"
        }

        static var hapticsEnabled: LocalizedStringKey {
            "settings.haptics.enabled"
        }

        static var hapticsTrackpad: LocalizedStringKey {
            "settings.haptics.trackpad"
        }

        static var hapticsScroll: LocalizedStringKey {
            "settings.haptics.scroll"
        }

        static var hapticsKeyboard: LocalizedStringKey {
            "settings.haptics.keyboard"
        }

        static var hapticsHint: LocalizedStringKey {
            "settings.haptics.hint"
        }

        static var hapticsIntensity: LocalizedStringKey {
            "settings.haptics.intensity"
        }

        static var hapticsIntensityLight: LocalizedStringKey {
            "settings.haptics.intensity.light"
        }

        static var hapticsIntensityMedium: LocalizedStringKey {
            "settings.haptics.intensity.medium"
        }

        static var hapticsIntensityStrong: LocalizedStringKey {
            "settings.haptics.intensity.strong"
        }

        static var autoAdvertise: LocalizedStringKey {
            "settings.auto_advertise"
        }

        static var autoAdvertiseHint: LocalizedStringKey {
            "settings.auto_advertise_hint"
        }

        static var advanced: LocalizedStringKey {
            "settings.advanced"
        }

        static var developerMode: LocalizedStringKey {
            "settings.developer_mode"
        }

        static var forceServiceChanged: LocalizedStringKey {
            "settings.force_service_changed"
        }

        static var forceServiceChangedHint: LocalizedStringKey {
            "settings.force_service_changed_hint"
        }

        static var sourceCode: LocalizedStringKey {
            "settings.source_code"
        }

        static var reset: LocalizedStringKey {
            "settings.reset"
        }

        static var resetConfirm: LocalizedStringKey {
            "settings.reset_confirm"
        }
    }
}
