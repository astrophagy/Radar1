import SwiftUI
import MWDATCore
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

            switch glassesManager.registrationState {
            case .unavailable:
                Text("Registration unavailable")
                    .foregroundColor(.secondary)

            case .available:
                Button("Register with Meta AI") {
                    glassesManager.register()
                }
                .buttonStyle(.borderedProminent)

            case .registering:
                ProgressView()
                    .progressViewStyle(.circular)

            case .registered:
                Button(glassesManager.isConnected ? "Disconnect" : "Connect to Glasses") {
                    if glassesManager.isConnected {
                        glassesManager.disconnect()
                    } else {
                        glassesManager.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .task {
            await glassesManager.observeRegistration()
        }
    }
}

@MainActor
class GlassesManager: ObservableObject {
    @Published var statusMessage = "Not registered"
    @Published var isConnected = false
    @Published var registrationState: RegistrationState = Wearables.shared.registrationState

    private var deviceSession: DeviceSession?
    private var monitorTask: Task<Void, Never>?
    private var registrationTask: Task<Void, Never>?

    func observeRegistration() async {
        for await state in Wearables.shared.registrationStateStream() {
            self.registrationState = state
            switch state {
            case .unavailable:
                self.statusMessage = "Registration unavailable on this device."
            case .available:
                self.statusMessage = "Not registered. Tap below to link with Meta AI."
            case .registering:
                self.statusMessage = "Opening Meta AI to authorize…"
            case .registered:
                if !isConnected {
                    self.statusMessage = "Registered. Tap Connect when glasses are on."
                }
            }
        }
    }

    func register() {
        registrationTask = Task {
            do {
                try await Wearables.shared.startRegistration()
            } catch RegistrationError.alreadyRegistered {
                self.registrationState = .registered
                self.statusMessage = "Already registered."
            } catch {
                self.statusMessage = "Registration failed: \(error.localizedDescription)"
            }
        }
    }

    func connect() {
        guard !Wearables.shared.devices.isEmpty else {
            statusMessage = "No glasses found. Make sure your Ray-Ban Meta glasses are powered on and in range."
            return
        }

        statusMessage = "Connecting…"

        monitorTask = Task {
            do {
                let selector = AutoDeviceSelector(wearables: Wearables.shared)
                let session = try Wearables.shared.createSession(deviceSelector: selector)
                try session.start()
                self.deviceSession = session

                for await state in session.stateStream() {
                    switch state {
                    case .started:
                        self.isConnected = true
                        self.statusMessage = "Glasses connected"
                    case .stopped:
                        self.isConnected = false
                        self.statusMessage = "Disconnected"
                        return
                    default:
                        self.statusMessage = state.description
                    }
                }
            } catch DeviceSessionError.noEligibleDevice {
                self.statusMessage = "No eligible glasses found. Make sure they're powered on and in range."
            } catch DeviceSessionError.sessionAlreadyExists {
                self.statusMessage = "A session is already active. Disconnect first."
            } catch {
                self.statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        monitorTask?.cancel()
        monitorTask = nil
        deviceSession?.stop()
        deviceSession = nil
        isConnected = false
        statusMessage = "Tap Connect when glasses are on."
    }
}
