import SwiftUI
import AURADesign

/// Two screens' worth of app: pair, then press a button.
///
/// Deliberately plain. The companion has no dashboard because it holds no data
/// worth showing — and an iOS app that displayed figures would need its own
/// copy of the analytics, which is the one thing this design exists to avoid.
struct CompanionView: View {
    @Environment(\.theme) private var theme
    /// `@Bindable`, not `@State`: the app owns this object's lifetime, and a
    /// second `@State` here would capture a snapshot and quietly stop tracking.
    /// The binding is what `$model.pairingCode` needs.
    @Bindable var model: CompanionModel

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 22) {
                header
                if model.isPaired { synced } else { pairing }
                Spacer()
                footer
            }
            .padding(26)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 5) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.primary)
            Text("AURA Companion")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text("Sends new Health data to your Mac. Nothing leaves your network.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
    }

    private var pairing: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                PanelLabel("Pair with your Mac")
                Text("Open AURA on your Mac, go to Settings, and start sync. Type the six digits it shows.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("000000", text: $model.pairingCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 26, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)

                Button("Pair") { model.pair() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(theme.primary))
            }
        }
    }

    private var synced: some View {
        GlassPanel {
            VStack(spacing: 14) {
                status

                Button {
                    Task { await model.sync() }
                } label: {
                    Text("Sync now")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(theme.primary))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .opacity(isWorking ? 0.5 : 1)
            }
        }
    }

    private var isWorking: Bool {
        if case .working = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .needsPairing, .ready:
            Text("Ready.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textSecondary)

        case .working(let step):
            HStack(spacing: 9) {
                ProgressView().controlSize(.small).tint(theme.primary)
                Text(step)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textPrimary)
            }

        case .done(let stored, let duplicates, let at):
            VStack(spacing: 4) {
                Text(stored == 0 ? "Nothing new" : "\(stored.formatted()) new readings")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                if duplicates > 0 {
                    // Same honesty as the Mac's import screen: your Mac already
                    // having most of this is the pipeline working, not a fault.
                    Text("\(duplicates.formatted()) already on your Mac")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
                Text(at.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
            }

        case .failed(let message):
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.accent)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isPaired {
            VStack(spacing: 10) {
                Button("Send everything again") {
                    Task { await model.resendEverything() }
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .disabled(isWorking)

                Button("Unpair") { model.unpair() }
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }
}
