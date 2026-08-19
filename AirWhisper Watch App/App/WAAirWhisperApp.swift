import SwiftUI

@main // start point of the watch app
struct WAAirWhisper_Watch_AppApp: App {
    @StateObject private var connectivity = WatchConnectivityClient.shared // shared instance of the watch connectivity client to manage communication with the iPhone app.
    @StateObject private var modelState = MLModelState.shared // model loading state to track if the ML model is ready for use.

    init() {
        DispatchQueue.global(qos: .userInitiated).async { // using a background thread with userInitiated quality of service to perform the ML model warmup, ensuring that it doesn't block the main thread and provides a responsive user experience.
            Log.info(Log.ml, "Starting ML model warmup...")
            AirWriteMLRunner.warmUp()
            Log.info(Log.ml, "ML model warmup complete")
            Task { @MainActor in
                MLModelState.shared.markReady() // mark model as ready
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity) // inject the connectivity client into the environment so that it can be accessed throughout the app for communication with the iPhone app.
                .environmentObject(modelState) // inject the model state into the environment so that it can be accessed throughout the app to check if the ML model is ready before allowing certain features that depend on it.
        }
    }
}
