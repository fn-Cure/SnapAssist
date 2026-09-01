import AppKit
import SwiftUI

@MainActor
final class AppWindowController: NSWindowController, NSWindowDelegate {
    enum Kind {
        case onboarding
        case settings
    }

    private let kind: Kind

    init(kind: Kind, model: AppPreferencesModel, onOnboardingFinished: (() -> Void)? = nil) {
        self.kind = kind
        let rootView: AnyView
        let title: String
        let size: NSSize
        switch kind {
        case .onboarding:
            rootView = AnyView(OnboardingView(model: model, onFinished: onOnboardingFinished ?? {}))
            title = "Willkommen bei SnapAssist"
            size = NSSize(width: 640, height: 500)
        case .settings:
            rootView = AnyView(SettingsRootView(model: model))
            title = "SnapAssist Einstellungen"
            size = NSSize(width: 620, height: 470)
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private struct SettingsRootView: View {
    @ObservedObject var model: AppPreferencesModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("Allgemein", systemImage: "switch.2") }
            PermissionSettingsView(model: model)
                .tabItem { Label("Berechtigungen", systemImage: "checkmark.shield") }
            AboutSettingsView(model: model)
                .tabItem { Label("Über SnapAssist", systemImage: "info.circle") }
            PrivacySettingsView()
                .tabItem { Label("Datenschutz", systemImage: "hand.raised") }
        }
        .padding(20)
        .frame(minWidth: 580, minHeight: 420)
    }
}

@MainActor
private struct GeneralSettingsView: View {
    @ObservedObject var model: AppPreferencesModel

    var body: some View {
        Form {
            Section("Snap Assist") {
                Toggle(
                    "SnapAssist aktiv",
                    isOn: Binding(
                        get: { model.isEnabled },
                        set: { enabled in model.setEnabled(enabled) }
                    )
                )
                Text("Erkennt Fenster, die du mit macOS oder Raycast anordnest, und schlägt passende Fenster für die freie Fläche vor.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Startverhalten") {
                Toggle(
                    "Beim Anmelden öffnen",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { enabled in model.setLaunchAtLoginEnabled(enabled) }
                    )
                )
            }

            Section("Experimentell") {
                Toggle(
                    "Gekoppelte Größenänderung",
                    isOn: Binding(
                        get: { model.linkedResizingEnabled },
                        set: { enabled in model.setLinkedResizingEnabled(enabled) }
                    )
                )
                Text("Passt vollständig belegte Fenstergruppen nach dem Loslassen einer gemeinsamen Trennlinie an. Standardmäßig deaktiviert.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let settingsError = model.settingsError {
                Label(settingsError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct PermissionSettingsView: View {
    @ObservedObject var model: AppPreferencesModel

    var body: some View {
        Form {
            Section("Erforderlich") {
                PermissionRow(
                    title: "Bedienungshilfen",
                    explanation: "Erlaubt SnapAssist, Fenster zu erkennen, zu verschieben und zu fokussieren.",
                    granted: model.accessibilityTrusted,
                    buttonTitle: "Berechtigung anfordern",
                    action: model.requestAccessibilityPermission
                )
            }

            Section("Optional") {
                PermissionRow(
                    title: "Bildschirmaufnahme",
                    explanation: "Wird ausschließlich lokal für Fenstervorschauen verwendet. Ohne Freigabe zeigt SnapAssist App-Symbole und Fenstertitel.",
                    granted: model.screenRecordingGranted,
                    buttonTitle: "Vorschauen erlauben",
                    action: model.requestScreenRecording
                )
            }

            Section("Diagnose") {
                StatusLine(
                    title: "Fensterbeobachtung",
                    value: model.degradedObserverCount == 0
                        ? "Bereit"
                        : "Fallback für \(model.degradedObserverCount) App(s)",
                    healthy: model.observerFailureCount == 0
                )
                if let failure = model.lastMutationFailure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button {
                    model.copyDiagnostics()
                } label: {
                    Label(
                        model.diagnosticsCopied ? "Diagnose kopiert" : "Diagnose kopieren",
                        systemImage: model.diagnosticsCopied ? "checkmark" : "doc.on.doc"
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct PermissionRow: View {
    let title: String
    let explanation: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Spacer()
                Text(granted ? "Erlaubt" : "Nicht erlaubt")
                    .font(.callout.weight(.medium))
            }
            Text(explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !granted {
                Button(buttonTitle, action: action)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private struct StatusLine: View {
    let title: String
    let value: String
    let healthy: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: healthy ? "checkmark.circle" : "exclamationmark.triangle")
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct AboutSettingsView: View {
    @ObservedObject var model: AppPreferencesModel

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            }
            Text("SnapAssist")
                .font(.title.bold())
            Text(model.versionDescription)
                .foregroundStyle(.secondary)
            Text("Windows-artige Fensterauswahl für macOS – nativ, lokal und ohne Tracking.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Divider().frame(maxWidth: 420)
            Label("Keine Netzwerkverbindung oder Analysefunktionen", systemImage: "hand.raised.fill")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

@MainActor
private struct PrivacySettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Datenschutz")
                    .font(.title.bold())
                Label("Keine Datenerfassung", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("SnapAssist überträgt keine Daten und enthält weder Tracking noch Analyse- oder Werbe-SDKs.")

                GroupBox("Lokal verarbeitete Informationen") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• App- und Fensternamen zur Darstellung im Picker")
                        Text("• Fensterpositionen und -größen zur Layout-Erkennung")
                        Text("• Optionale Fenstervorschauen ausschließlich im Arbeitsspeicher")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                Text("Vorschaubilder und Fensterinformationen werden nicht gespeichert und beim Schließen des Pickers verworfen. Berechtigungen können jederzeit in den macOS-Systemeinstellungen entzogen werden.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 500, alignment: .leading)
            .padding(24)
        }
    }
}

@MainActor
private struct OnboardingView: View {
    @ObservedObject var model: AppPreferencesModel
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permissions
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)

            Divider()
            HStack {
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                }
                Spacer()
                if step > 0 {
                    Button("Zurück") { changeStep(to: step - 1) }
                }
                Button(step == 2 ? "Fertig" : "Weiter") {
                    if step == 2 {
                        model.onboardingCompleted = true
                        onFinished()
                    } else {
                        changeStep(to: step + 1)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 640, height: 500)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(systemName: "rectangle.split.2x1.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Die freie Fläche gehört dir")
                .font(.largeTitle.bold())
            Text("SnapAssist ergänzt das macOS-Fenstersnapping um die vertraute Windows-Auswahl: Fenster anordnen, freie Zone sehen, passendes Fenster auswählen.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            HStack(spacing: 22) {
                FeatureLabel(icon: "rectangle.leadinghalf.inset.filled", text: "Hälften")
                FeatureLabel(icon: "rectangle.split.3x1", text: "Drittel")
                FeatureLabel(icon: "square.grid.2x2", text: "Viertel")
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Zwei klare Berechtigungen")
                .font(.largeTitle.bold())
            Text("SnapAssist arbeitet vollständig lokal. Bedienungshilfen sind erforderlich; Fenstervorschauen sind optional.")
                .font(.title3)
                .foregroundStyle(.secondary)
            PermissionRow(
                title: "Bedienungshilfen",
                explanation: "Erforderlich zum Erkennen und Positionieren von Fenstern.",
                granted: model.accessibilityTrusted,
                buttonTitle: "Berechtigung anfordern",
                action: model.requestAccessibilityPermission
            )
            PermissionRow(
                title: "Bildschirmaufnahme",
                explanation: "Optional für lokale Vorschaubilder. App-Symbole funktionieren immer.",
                granted: model.screenRecordingGranted,
                buttonTitle: "Vorschauen erlauben",
                action: model.requestScreenRecording
            )
        }
    }

    private var ready: some View {
        VStack(spacing: 22) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 68))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Bereit für den ersten Snap")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                InstructionRow(number: 1, text: "Ordne ein Fenster mit macOS oder Raycast links, rechts, als Drittel oder in einer Ecke an.")
                InstructionRow(number: 2, text: "SnapAssist zeigt passende Fenster direkt in der freien Fläche.")
                InstructionRow(number: 3, text: "Klicke ein Fenster oder nutze Tab, Pfeiltasten und Return.")
            }
            .frame(maxWidth: 500)
            Text("SnapAssist bleibt anschließend unauffällig in der Menüleiste.")
                .foregroundStyle(.secondary)
        }
    }

    private func changeStep(to newStep: Int) {
        if reduceMotion {
            step = newStep
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { step = newStep }
        }
    }
}

@MainActor
private struct FeatureLabel: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.quaternary, in: Capsule())
    }
}

@MainActor
private struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schritt \(number): \(text)")
    }
}
