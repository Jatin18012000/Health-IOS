import SwiftUI
import AURACore
import AURAStore
import AURADesign

/// The app shell. Deliberately thin — views and wiring only.
///
/// Anything with logic worth testing lives in a package under `Sources/`, so it
/// can be built and tested from the command line and, later, linked by an iOS
/// companion without moving.
@main
struct AURAApp: App {

    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            Group {
                switch container.status {
                case .opening:
                    ProgressView().controlSize(.large)

                case .ready(let store):
                    DashboardView(model: DashboardViewModel(store: store))

                case .failed(let message):
                    // A store that will not open is not something to paper over
                    // with an empty dashboard — four years of health data either
                    // loaded or it did not.
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                        Text("Could not open your health store")
                            .font(.headline)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(AppContainer.storeURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    .padding(40)
                }
            }
            .environment(\.theme, .cyberNeon)
            .preferredColorScheme(.dark)
            .frame(minWidth: 1180, minHeight: 760)
            .task { await container.open() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// Owns the store's lifetime.
@Observable
@MainActor
final class AppContainer {

    enum Status {
        case opening
        case ready(SQLiteHealthStore)
        case failed(String)
    }

    private(set) var status: Status = .opening

    /// One folder, under Application Support. Everything AURA knows lives here
    /// and nowhere else, so backing it up or deleting it is a single decision.
    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appending(path: "AURA/aura.sqlite")
    }

    func open() async {
        guard case .opening = status else { return }
        do {
            status = .ready(try SQLiteHealthStore(url: Self.storeURL))
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
