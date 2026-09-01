import AppKit
import ServiceManagement

@MainActor
final class AppPreferencesModel: ObservableObject {
    private enum Keys {
        static let onboardingCompleted = "onboardingCompleted"
    }

    private let coordinator: AppCoordinator
    private var refreshTimer: Timer?

    @Published private(set) var isEnabled: Bool
    @Published private(set) var linkedResizingEnabled: Bool
    @Published private(set) var accessibilityTrusted: Bool
    @Published private(set) var screenRecordingGranted: Bool
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var observerFailureCount: Int
    @Published private(set) var degradedObserverCount: Int
    @Published private(set) var lastMutationFailure: String?
    @Published private(set) var settingsError: String?
    @Published private(set) var diagnosticsCopied = false

    var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.onboardingCompleted) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.onboardingCompleted) }
    }

    var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "Version \(version) (\(build))"
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.isEnabled = coordinator.isEnabled
        self.linkedResizingEnabled = coordinator.linkedResizingEnabled
        self.accessibilityTrusted = coordinator.windowSystem.isAccessibilityTrusted
        self.screenRecordingGranted = coordinator.windowSystem.hasScreenRecordingPermission
        self.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        self.observerFailureCount = coordinator.windowSystem.observerFailureCount
        self.degradedObserverCount = coordinator.windowSystem.degradedObserverCount
        self.lastMutationFailure = coordinator.windowSystem.lastMutationFailureDescription
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    isolated deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        coordinator.windowSystem.refreshAccessibilityState()
        accessibilityTrusted = coordinator.windowSystem.isAccessibilityTrusted
        screenRecordingGranted = coordinator.windowSystem.hasScreenRecordingPermission
        observerFailureCount = coordinator.windowSystem.observerFailureCount
        degradedObserverCount = coordinator.windowSystem.degradedObserverCount
        lastMutationFailure = coordinator.windowSystem.lastMutationFailureDescription
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        coordinator.isEnabled = enabled
    }

    func setLinkedResizingEnabled(_ enabled: Bool) {
        linkedResizingEnabled = enabled
        coordinator.linkedResizingEnabled = enabled
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        settingsError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            settingsError = "Anmeldung beim Login konnte nicht geändert werden: \(error.localizedDescription)"
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    func openAccessibilitySettings() {
        coordinator.windowSystem.openAccessibilitySettings()
    }

    func requestAccessibilityPermission() {
        _ = coordinator.windowSystem.requestAccessibilityPermission(prompt: true)
        refresh()
    }

    func requestScreenRecording() {
        coordinator.windowSystem.requestScreenRecordingPermission()
        refresh()
    }

    func copyDiagnostics() {
        let report = DiagnosticsStore.shared.report(header: [
            "SnapAssist \(versionDescription)",
            "Accessibility: \(accessibilityTrusted ? "granted" : "denied")",
            "Screen Recording: \(screenRecordingGranted ? "granted" : "denied")",
            "Observer failures: \(observerFailureCount)",
            "Observer fallbacks: \(degradedObserverCount)",
            "Last mutation failure: \(lastMutationFailure ?? "none")",
        ])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        diagnosticsCopied = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.diagnosticsCopied = false
        }
    }
}
