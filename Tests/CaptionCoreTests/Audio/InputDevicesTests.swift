import Testing
@testable import CaptionCore

@Suite("Input devices")
struct InputDevicesTests {
    private let devices = [
        InputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone"),
        InputDevice(uid: "usb-1234", name: "Jabra Speak 510"),
    ]

    @Test func keepsASavedDeviceThatIsConnected() {
        #expect(InputDevices.resolve(preferredUID: "usb-1234", available: devices) == "usb-1234")
    }

    @Test func fallsBackToTheSystemDefaultWhenTheDeviceIsGone() {
        #expect(InputDevices.resolve(preferredUID: "usb-9999", available: devices) == nil)
    }

    @Test func noChoiceMeansTheSystemDefault() {
        #expect(InputDevices.resolve(preferredUID: nil, available: devices) == nil)
    }

    @Test func listsAtLeastTheDevicesCoreAudioReports() {
        let found = InputDevices.available()
        #expect(Set(found.map(\.uid)).count == found.count)
    }
}
