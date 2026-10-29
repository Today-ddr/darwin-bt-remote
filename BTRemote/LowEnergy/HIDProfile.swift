import CoreBluetooth
import Foundation

/// HID profile constants used by the low energy (HOGP) peripheral
enum HIDProfile {
    // use full UUID strings: CBPeripheralManager rejects short-form service UUIDs

    // services
    nonisolated(unsafe) static let batteryService = CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let deviceInformationService = CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let hidService = CBUUID(string: "00001812-0000-1000-8000-00805F9B34FB")

    /// Report Reference descriptor: names a report characteristic by report ID and type.
    nonisolated(unsafe) static let reportReference = CBUUID(string: "00002908-0000-1000-8000-00805F9B34FB")

    // characteristics
    nonisolated(unsafe) static let batteryLevel = CBUUID(string: "00002A19-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let bootKeyboardInputReport = CBUUID(string: "00002A22-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let bootKeyboardOutputReport = CBUUID(string: "00002A32-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let bootMouseInputReport = CBUUID(string: "00002A33-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let hidInformation = CBUUID(string: "00002A4A-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let reportMap = CBUUID(string: "00002A4B-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let hidControlPoint = CBUUID(string: "00002A4C-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let report = CBUUID(string: "00002A4D-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let protocolMode = CBUUID(string: "00002A4E-0000-1000-8000-00805F9B34FB")

    // device information service characteristics
    nonisolated(unsafe) static let manufacturerName = CBUUID(string: "00002A29-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let modelNumber = CBUUID(string: "00002A24-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let pnpID = CBUUID(string: "00002A50-0000-1000-8000-00805F9B34FB")

    /// bcdHID 0x0111, country 0, RemoteWake | NormallyConnectable
    static let hidInformationValue = Data([0x11, 0x01, 0x00, 0x03])

    static let manufacturerNameValue = Data("BTRemote".utf8)
    static let modelNumberValue = Data("BTRemote-1.0".utf8)

    /// PnP ID: VendorIDSource(BTSIG=1), VendorID 0xFFFF (test), ProductID 0x0001, Version 0x0100
    static let pnpIDValue = Data([0x01, 0xFF, 0xFF, 0x01, 0x00, 0x00, 0x01])
}

enum ReportID: UInt8 {
    case mouse = 1
    case keyboard = 2
    case keyboardLEDs = 3
}

enum ReportType: UInt8 {
    case input = 1
    case output = 2
    case feature = 3
}

extension ReportID {
    func descriptor(_ type: ReportType) -> Data {
        Data([rawValue, type.rawValue])
    }
}

/// 113-byte HID report map: keyboard input + LED output (61 bytes) and mouse (52 bytes).
///
/// Only reports that are actually produced live here. Battery is exposed through the
/// standard Battery Service, not a HID report, so the map carries no battery collection.
extension HIDProfile {
    static let reportMapData = Data([
        // keyboard input + LED output, Report IDs 2 and 3 (61 bytes)
        0x05, 0x01, // Usage Page (Generic Desktop)
        0x09, 0x06, // Usage (Keyboard)
        0xA1, 0x01, // Collection (Application)
        0x85, 0x02, //   Report ID (2)
        0x05, 0x07, //   Usage Page (Keyboard/Keypad)
        0x19, 0xE0, //   Usage Min (LeftControl)
        0x29, 0xE7, //   Usage Max (RightGUI)
        0x75, 0x01, //   Report Size (1)
        0x95, 0x08, //   Report Count (8)
        0x15, 0x00, //   Logical Min (0)
        0x25, 0x01, //   Logical Max (1)
        0x81, 0x02, //   Input (Data,Var,Abs): 8 modifier bits
        0x95, 0x01, //   Report Count (1)
        0x75, 0x08, //   Report Size (8)
        0x81, 0x01, //   Input (Const,Array,Abs): reserved byte
        0x19, 0x00, //   Usage Min (0)
        0x29, 0xDD, //   Usage Max (221)
        0x95, 0x06, //   Report Count (6)
        0x25, 0xDD, //   Logical Max (221)
        0x81, 0x00, //   Input (Data,Array,Abs): 6 keys
        0x85, 0x03, //   Report ID (3)
        0x05, 0x08, //   Usage Page (LEDs)
        0x19, 0x01, //   Usage Min (NumLock)
        0x29, 0x05, //   Usage Max (Kana)
        0x95, 0x05, //   Report Count (5)
        0x75, 0x01, //   Report Size (1)
        0x25, 0x01, //   Logical Max (1)
        0x91, 0x02, //   Output (Data,Var,Abs): 5 LED bits
        0x95, 0x03, //   Report Count (3)
        0x91, 0x03, //   Output (Const,Var,Abs): LED padding
        0xC0, // End Collection

        // mouse, Report ID 1 (52 bytes)
        0x05, 0x01, // Usage Page (Generic Desktop)
        0x09, 0x02, // Usage (Mouse)
        0xA1, 0x01, // Collection (Application)
        0x85, 0x01, //   Report ID (1)
        0x09, 0x01, //   Usage (Pointer)
        0xA1, 0x00, //   Collection (Physical)
        0x05, 0x09, //     Usage Page (Button)
        0x19, 0x01, //     Usage Min (1)
        0x29, 0x03, //     Usage Max (3)
        0x75, 0x01, //     Report Size (1)
        0x95, 0x03, //     Report Count (3)
        0x15, 0x00, //     Logical Min (0)
        0x25, 0x01, //     Logical Max (1)
        0x81, 0x02, //     Input (Data,Var,Abs)
        0x95, 0x05, //     Report Count (5)
        0x81, 0x03, //     Input (Const,Var,Abs) padding
        0x05, 0x01, //     Usage Page (Generic Desktop)
        0x09, 0x30, //     Usage (X)
        0x09, 0x31, //     Usage (Y)
        0x09, 0x38, //     Usage (Wheel)
        0x75, 0x08, //     Report Size (8)
        0x95, 0x03, //     Report Count (3)
        0x15, 0x81, //     Logical Min (-127)
        0x25, 0x7F, //     Logical Max (127)
        0x81, 0x06, //     Input (Data,Var,Rel)
        0xC0, //   End Collection
        0xC0 // End Collection
    ])
}
