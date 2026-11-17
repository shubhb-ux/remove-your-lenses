import SwiftUI

private typealias LensCareTheme = LensTheme

struct WatchHomeView: View {
    @Environment(LensStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLogging = false
    @State private var showsSettings = false

    // Debug-only launch states let each design be checked without changing saved lens status.
    private var previewState: String? {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--watch-preview=") })?
            .replacingOccurrences(of: "--watch-preview=", with: "")
        #else
        return nil
        #endif
    }

    private var isComplete: Bool {
        if let previewState { return previewState == "rest" }
        return !store.lensesAreIn
    }
    private var displaysLogging: Bool { isLogging || previewState == "pinch" }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    screen(width: geometry.size.width, height: max(geometry.size.height, geometry.size.width * 296 / 240))
                    Button("Reminders & bedtime") { showsSettings = true }
                        .font(.caption2)
                        .foregroundStyle(LensCareTheme.lavender)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .padding(.bottom, 10)
                }
                .scrollIndicators(.hidden)
            }
            .ignoresSafeArea()
            .background(LensCareTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsSettings) {
                if previewState == "trial" { NavigationStack { DriftTrialView() } }
                else { settings }
            }
            .onAppear { if previewState == "trial" { showsSettings = true } }
        }
        .tint(LensCareTheme.lavender)
    }

    private func screen(width: CGFloat, height: CGFloat) -> some View {
        let scale = width / 240
        return VStack(spacing: 0) {
            HStack {
                Text("Lenses")
                    .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(LensCareTheme.lavender)
                Spacer()
            }
            .padding(.horizontal, 22 * scale)
            .padding(.top, 18 * scale)

            if displaysLogging {
                loggingContent(scale: scale)
            } else if isComplete {
                completeContent(scale: scale)
            } else {
                readyContent(scale: scale)
            }
        }
        .foregroundStyle(.white)
        .frame(width: width, height: height, alignment: .top)
        .background(LensCareTheme.background)
        .task(id: isLogging) {
            guard isLogging else { return }
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 1100)) }
            catch { return }
            store.markLensesOut()
            isLogging = false
        }
    }

    private func readyContent(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            title("Time to take\nthem out", scale: scale)
                .padding(.top, 12 * scale)
            Spacer(minLength: 6 * scale)
            artwork("LensReady")
                .frame(height: 105 * scale)
                .padding(.horizontal, 18 * scale)
                .accessibilityHidden(true)
            Spacer(minLength: 5 * scale)
            Text("Pinch to log removal")
                .font(.system(size: 11 * scale, weight: .bold, design: .rounded))
                .padding(.bottom, 9 * scale)
            capsuleButton("Or tap to confirm", scale: scale, prominent: false) {
                isLogging = true
            }
            .handGestureShortcut(.primaryAction)
            .accessibilityLabel("Confirm contact lenses removed")
        }
        .padding(.bottom, 18 * scale)
    }

    private func loggingContent(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            title("Pinch & release", scale: scale)
                .padding(.top, 19 * scale)
            Spacer(minLength: 8 * scale)
            artwork("LensPinch")
                .frame(height: 147.5 * scale)
                .padding(.horizontal, 18 * scale)
                .accessibilityHidden(true)
            Spacer(minLength: 8 * scale)
            Text("Logging removal...")
                .font(.system(size: 12 * scale, design: .rounded))
                .foregroundStyle(LensCareTheme.secondary)
        }
        .padding(.bottom, 35 * scale)
        .accessibilityElement(children: .combine)
    }

    private func completeContent(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            title("All done!", scale: scale)
                .padding(.top, 15 * scale)
                .overlay(alignment: .bottomLeading) {
                    artwork("LensRays")
                        .frame(width: 22.5 * scale, height: 18.75 * scale)
                        .offset(x: -37 * scale, y: 3 * scale)
                        .accessibilityHidden(true)
                }
            Spacer(minLength: 4 * scale)
            artwork("LensRest")
                .frame(height: 83.75 * scale)
                .padding(.horizontal, 37.5 * scale)
                .overlay(alignment: .topTrailing) {
                    artwork("LensSparkle")
                        .frame(width: 37.5 * scale, height: 31.25 * scale)
                        .offset(x: -25 * scale, y: -35 * scale)
                }
                .accessibilityHidden(true)
            Text("Removal logged")
                .font(.system(size: 10 * scale, design: .rounded))
                .foregroundStyle(LensCareTheme.secondary)
                .padding(.top, 5 * scale)
            Spacer(minLength: 6 * scale)
            capsuleButton("Done", scale: scale, prominent: true) { showsSettings = true }
                .handGestureShortcut(.primaryAction)
            Button("Undo") { store.markLensesIn() }
                .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(LensCareTheme.secondary)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 36 * scale)
                .accessibilityLabel("Undo removal, mark lenses in")
        }
        .padding(.bottom, 10 * scale)
    }

    private func title(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 21 * scale, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func artwork(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
    }

    private func capsuleButton(_ title: String, scale: CGFloat, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16 * scale, design: .rounded))
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 39 * scale)
                .foregroundStyle(prominent ? LensCareTheme.background : Color(red: 235 / 255, green: 214 / 255, blue: 253 / 255))
                .background(prominent ? LensCareTheme.lavender : LensCareTheme.muted, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24 * scale)
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Nightly reminder time") { ReminderSettingsView(store: store, compact: true) }
                Section("Quick reminder") {
                    RemindInPicker(store: store)
                    Button("Remind me in \(store.remindInText)") {
                        store.remindInSelectedDelay()
                    }
                    if let message = store.quickReminderMessage { Text(message).foregroundStyle(LensCareTheme.lavender) }
                }
                Section("Experimental") {
                    NavigationLink("Drift-off trial") { DriftTrialView() }
                }
                Section("Your schedule") {
                    NavigationLink("My reminders") { CustomRemindersView() }
                }
                if !store.lensesAreIn {
                    Button("Put lenses in") { store.markLensesIn(); showsSettings = false }
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSettings = false }
                }
            }
        }
        .tint(LensCareTheme.lavender)
    }
}

#Preview {
    WatchHomeView().environment(LensStore.shared)
}
