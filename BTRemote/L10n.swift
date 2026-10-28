import Foundation
import SwiftUI

enum L10n {
    enum App {
        static var title: LocalizedStringKey {
            "app.title"
        }
    }

    enum Tab {
        static var setup: LocalizedStringKey {
            "tab.setup"
        }

        static var input: LocalizedStringKey {
            "tab.input"
        }

        static var settings: LocalizedStringKey {
            "tab.settings"
        }
    }

    enum Input {
        static var keyboard: LocalizedStringKey {
            "input.keyboard"
        }

        static var trackpad: LocalizedStringKey {
            "input.trackpad"
        }

        static var notConnectedTitle: LocalizedStringKey {
            "remote.not_connected_title"
        }

        static var notConnectedMessage: LocalizedStringKey {
            "remote.not_connected_message"
        }

        static var openSetup: LocalizedStringKey {
            "remote.open_setup"
        }
    }

    enum Section {
        static var lastError: LocalizedStringKey {
            "section.last_error"
        }

        static var status: LocalizedStringKey {
            "section.status"
        }

        static var connection: LocalizedStringKey {
            "section.connection"
        }

        static var devices: LocalizedStringKey {
            "section.devices"
        }

        static var battery: LocalizedStringKey {
            "section.battery"
        }
    }

    enum Status {
        static var bluetooth: LocalizedStringKey {
            "status.bluetooth"
        }

        static var advertising: LocalizedStringKey {
            "status.advertising"
        }

        static var hidService: LocalizedStringKey {
            "status.hid_service"
        }

        static var hidServiceAdded: LocalizedStringKey {
            "status.hid_service.added"
        }

        static var subscribedCentrals: LocalizedStringKey {
            "status.subscribed_centrals"
        }

        static var connectedPeripherals: LocalizedStringKey {
            "status.connected_peripherals"
        }

        static var hostLEDs: LocalizedStringKey {
            "status.host_leds"
        }
    }

    enum Value {
        static var yes: LocalizedStringKey {
            "value.yes"
        }

        static var no: LocalizedStringKey {
            "value.no"
        }

        static var none: LocalizedStringKey {
            "value.none"
        }

        static var noneString: String {
            String(localized: "value.none")
        }
    }

    enum Action {
        static var startAdvertising: LocalizedStringKey {
            "action.start_advertising"
        }

        static var stopAdvertising: LocalizedStringKey {
            "action.stop_advertising"
        }

        static var scanNearbyDevices: LocalizedStringKey {
            "action.scan_nearby_devices"
        }

        static var stopScanning: LocalizedStringKey {
            "action.stop_scanning"
        }

        static var notNow: LocalizedStringKey {
            "action.not_now"
        }

        static var done: LocalizedStringKey {
            "action.done"
        }
    }

    enum Welcome {
        static var title: LocalizedStringKey {
            "welcome.title"
        }

        static var message: LocalizedStringKey {
            "welcome.message"
        }

        static var viewGuide: LocalizedStringKey {
            "welcome.view_guide"
        }
    }

    enum Sort {
        static var title: LocalizedStringKey {
            "sort.title"
        }

        static var direction: LocalizedStringKey {
            "sort.direction"
        }

        static var ascending: LocalizedStringKey {
            "sort.ascending"
        }

        static var descending: LocalizedStringKey {
            "sort.descending"
        }
    }

    enum Device {
        static var emptyState: LocalizedStringKey {
            "device.empty_state"
        }

        static var unknownName: String {
            String(localized: "device.unknown_name")
        }

        static var unknownManufacturer: String {
            String(localized: "device.unknown_manufacturer")
        }

        static var inactive: LocalizedStringKey {
            "device.inactive"
        }

        static var notSubscribed: LocalizedStringKey {
            "device.not_subscribed"
        }

        static var connectedLegend: LocalizedStringKey {
            "device.connected_legend"
        }

        static var remove: LocalizedStringKey {
            "device.remove"
        }

        static var removeConfirmTitle: LocalizedStringKey {
            "device.remove_confirm_title"
        }

        static var removeConfirmMessage: LocalizedStringKey {
            "device.remove_confirm_message"
        }

        static var inUse: LocalizedStringKey {
            "device.in_use"
        }

        static var standby: LocalizedStringKey {
            "device.standby"
        }

        static var removed: LocalizedStringKey {
            "device.removed"
        }

        static var use: LocalizedStringKey {
            "device.use"
        }

        static var restore: LocalizedStringKey {
            "device.restore"
        }

        static func rssi(_ value: Int) -> String {
            String.localizedStringWithFormat(
                String(localized: "device.rssi_format"),
                value
            )
        }

        static func connectAccessibilityLabel(_ name: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "device.connect_accessibility_label"),
                name
            )
        }

        static func disconnectAccessibilityLabel(_ name: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "device.disconnect_accessibility_label"),
                name
            )
        }
    }
}

extension L10n {
    enum Keyboard {
        static var esc: LocalizedStringKey {
            "keyboard.esc"
        }

        static var tab: LocalizedStringKey {
            "keyboard.tab"
        }

        static var up: LocalizedStringKey {
            "keyboard.up"
        }

        static var down: LocalizedStringKey {
            "keyboard.down"
        }

        static var left: LocalizedStringKey {
            "keyboard.left"
        }

        static var right: LocalizedStringKey {
            "keyboard.right"
        }

        static var shift: LocalizedStringKey {
            "keyboard.shift"
        }

        static var ctrl: LocalizedStringKey {
            "keyboard.ctrl"
        }

        static var alt: LocalizedStringKey {
            "keyboard.alt"
        }

        static var meta: LocalizedStringKey {
            "keyboard.meta"
        }

        static var backspace: LocalizedStringKey {
            "keyboard.backspace"
        }

        static var enter: LocalizedStringKey {
            "keyboard.enter"
        }

        static var space: LocalizedStringKey {
            "keyboard.space"
        }

        static var capsLock: LocalizedStringKey {
            "keyboard.caps_lock"
        }
    }

    enum Gesture {
        static var sectionTitle: LocalizedStringKey {
            "gesture.section_title"
        }

        static var doubleTapDrag: LocalizedStringKey {
            "gesture.double_tap_drag"
        }

        static var longPressDrag: LocalizedStringKey {
            "gesture.long_press_drag"
        }

        static var longPressDragHint: LocalizedStringKey {
            "gesture.long_press_drag_hint"
        }

        static var invertScroll: LocalizedStringKey {
            "gesture.invert_scroll"
        }

        static var invertScrollHint: LocalizedStringKey {
            "gesture.invert_scroll_hint"
        }

        static var mappingTitle: LocalizedStringKey {
            "gesture.mapping_title"
        }

        static var pinchToZoom: LocalizedStringKey {
            "gesture.pinch_to_zoom"
        }

        static var rotationGesture: LocalizedStringKey {
            "gesture.rotation"
        }

        static var fourFingerSectionTitle: LocalizedStringKey {
            "gesture.four_finger_section_title"
        }

        static var fourFingerSwipeUp: LocalizedStringKey {
            "gesture.four_finger_swipe_up"
        }

        static var fourFingerSwipeDown: LocalizedStringKey {
            "gesture.four_finger_swipe_down"
        }

        static var fourFingerSwipeLeft: LocalizedStringKey {
            "gesture.four_finger_swipe_left"
        }

        static var fourFingerSwipeRight: LocalizedStringKey {
            "gesture.four_finger_swipe_right"
        }

        static var fourFingerTap: LocalizedStringKey {
            "gesture.four_finger_tap"
        }

        static var threeFingerSwipeUp: LocalizedStringKey {
            "gesture.three_finger_swipe_up"
        }

        static var threeFingerSwipeDown: LocalizedStringKey {
            "gesture.three_finger_swipe_down"
        }

        static var threeFingerSwipeLeft: LocalizedStringKey {
            "gesture.three_finger_swipe_left"
        }

        static var threeFingerSwipeRight: LocalizedStringKey {
            "gesture.three_finger_swipe_right"
        }

        static var threeFingerTap: LocalizedStringKey {
            "gesture.three_finger_tap"
        }

        static var actionNone: LocalizedStringKey {
            "gesture.action_none"
        }

        static var actionAppSwitcher: LocalizedStringKey {
            "gesture.action_app_switcher"
        }

        static var actionHome: LocalizedStringKey {
            "gesture.action_home"
        }

        static var actionDock: LocalizedStringKey {
            "gesture.action_dock"
        }

        static var actionPreviousApp: LocalizedStringKey {
            "gesture.action_previous_app"
        }

        static var actionNextApp: LocalizedStringKey {
            "gesture.action_next_app"
        }

        static var actionSpotlight: LocalizedStringKey {
            "gesture.action_spotlight"
        }

        static var actionControlCenter: LocalizedStringKey {
            "gesture.action_control_center"
        }

        static var actionNotificationCenter: LocalizedStringKey {
            "gesture.action_notification_center"
        }

        static var actionScreenshot: LocalizedStringKey {
            "gesture.action_screenshot"
        }

        static var actionMiddleClick: LocalizedStringKey {
            "gesture.action_middle_click"
        }

        static var actionZoom: LocalizedStringKey {
            "gesture.action_zoom"
        }

        static var actionRotateLeft: LocalizedStringKey {
            "gesture.action_rotate_left"
        }

        static var actionRotateRight: LocalizedStringKey {
            "gesture.action_rotate_right"
        }
    }

    enum Mouse {
        static var middleButton: LocalizedStringKey {
            "mouse.button.middle"
        }

        static var wheelUp: LocalizedStringKey {
            "mouse.wheel.up"
        }

        static var wheelDown: LocalizedStringKey {
            "mouse.wheel.down"
        }
    }

    enum Battery {
        static var level: LocalizedStringKey {
            "battery.level"
        }
    }

    enum BluetoothState {
        static var unknown: LocalizedStringKey {
            "bluetooth_state.unknown"
        }

        static var resetting: LocalizedStringKey {
            "bluetooth_state.resetting"
        }

        static var unsupported: LocalizedStringKey {
            "bluetooth_state.unsupported"
        }

        static var unauthorized: LocalizedStringKey {
            "bluetooth_state.unauthorized"
        }

        static var poweredOff: LocalizedStringKey {
            "bluetooth_state.powered_off"
        }

        static var poweredOn: LocalizedStringKey {
            "bluetooth_state.powered_on"
        }

        static var unavailable: LocalizedStringKey {
            "bluetooth_state.unavailable"
        }
    }

    enum KeyboardLED {
        static var numLock: String {
            String(localized: "keyboard_led.num_lock")
        }

        static var capsLock: String {
            String(localized: "keyboard_led.caps_lock")
        }

        static var scrollLock: String {
            String(localized: "keyboard_led.scroll_lock")
        }
    }

    enum Bluetooth {
        static var advertisedName: String {
            String(localized: "bluetooth.advertised_name")
        }
    }
}
