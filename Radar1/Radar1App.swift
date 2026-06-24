import SwiftUI
import MWDATCore
import MWDATMockDevice

@main
struct Radar1App: App {
    init() {
        MockDeviceKit.shared.enable(config: MockDeviceKitConfig(initiallyRegistered: true))
        do {
            try Wearables.configure()
        } catch WearablesError.alreadyConfigured {
            // MockDeviceKit.enable() already configured the SDK internally
        } catch {
            assertionFailure("Wearables SDK configuration failed: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        _ = try? await Wearables.shared.handleUrl(url)
                    }
                }
        }
    }
}
