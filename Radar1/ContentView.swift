import SwiftUI
import MWDATCore
import MWDATMockDevice
import Combine

struct ContentView: View {
    @StateObject private var glassesManager = GlassesManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("Radar")
                .font(.largeTitle)
                .bold()

            Circle()
                .fill(glassesManager.isConnected ? Color.green : Color.red)
                .frame(width: 20, height: 20)

            Text(glassesManager.statusMessage)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(glassesManager.isConnected ? "Disconnect" : "Connect to Mock Glasses") {
                if glassesManager.isConnected {
                    glassesManager.disconnect()
                } else {
                    glassesManager.connect()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

@MainActor
class GlassesManager: ObservableObject {
    @Published var statusMessage = "Ready"
    @Published var isConnected = false

    private var deviceSession: DeviceSession?
    private var mockDevice: (any MockRaybanMeta)?
    private var monitorTask: Task<Void, Never>?

func connect() {
        statusMessage = "Setting up mock glasses…"

        monitorTask = Task {
            let device = MockDeviceKit.shared.pairRaybanMeta()
            self.mockDevice = device

            device.powerOn()
            device.don()

            // Wait for mock device to appear in Wearables.shared.devices
            self.statusMessage = "Waiting for mock device to register…"
            var targetId: DeviceIdentifier? = nil
            for await devices in Wearables.shared.devicesStream() {
                print("🔵 devicesStream update: \(devices)")
                if let id = devices.first {
                    targetId = id
                    break
                }
            }

            guard let deviceId = targetId else {
                self.statusMessage = "Mock device never appeared in SDK device list"
                return
            }

            print("🔵 Found device: \(deviceId)")
            do {
                let selector = SpecificDeviceSelector(device: deviceId)
                let session = try Wearables.shared.createSession(deviceSelector: selector)
                try session.start()
                self.deviceSession = session

                for await state in session.stateStream() {
                    switch state {
                    case .started:
                        self.isConnected = true
                        self.statusMessage = "Mock glasses connected"
                    case .stopped:
                        self.isConnected = false
                        self.statusMessage = "Disconnected"
                        return
                    default:
                        self.statusMessage = state.description
                    }
                }
            } catch DeviceSessionError.noEligibleDevice {
                self.statusMessage = "No eligible device. SDK devices: \(Wearables.shared.devices). State: \(Wearables.shared.registrationState)"
            } catch {
                self.statusMessage = "Error: \(error)"
            }
        }
    }

    func disconnect() {
        monitorTask?.cancel()
        monitorTask = nil
        deviceSession?.stop()
        deviceSession = nil
        if let device = mockDevice {
            MockDeviceKit.shared.unpairDevice(device)
        }
        mockDevice = nil
        isConnected = false
        statusMessage = "Disconnected"
    }
}
