import SwiftUI

@main
@MainActor
struct ControleQ80AiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = TVRemoteModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .background: model.disconnect()
                    case .active: model.connectIfNeeded()
                    default: break
                    }
                }
        }
    }
}
