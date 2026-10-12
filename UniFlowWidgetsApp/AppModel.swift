import Combine
import Foundation
import ServiceManagement
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var email = ""
    @Published var code = ""
    @Published var stage: Stage = .email
    @Published var status = ""
    @Published var busy = false
    @Published var lastSync: Date?
    @Published var notifications = false
    @Published var workspace: UniFlowWorkspace?

    enum Stage { case email, code, signedIn }
    private let client = SupabaseClient.configured
    private var syncLoop: Task<Void, Never>?

    init() {
        stage = SecureSession.load() == nil ? .email : .signedIn
        workspace = WidgetStorage.read()
        Task { await sync() }
        syncLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self else { return }
                if self.stage == .signedIn { await self.sync() }
            }
        }
    }

    var isConfigured: Bool { client != nil }
    var nextText: String {
        guard let workspace else { return "Noch keine Daten geladen" }
        switch CalendarEngine.spotlight(workspace, at: Date()) {
        case .active(let event): return "Jetzt: \(event.title)"
        case .upcoming(let event, let minutes): return "Nächster Termin in \(minutes) Min.: \(event.title)"
        case .tomorrow(let events): return events.isEmpty ? "Morgen ist frei" : "Morgen: \(events.count) Termin(e)"
        case .none: return "Noch keine Termine"
        }
    }
    var loginAtStartup: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
        } catch { status = "Autostart konnte nicht geändert werden: \(error.localizedDescription)" }
    }

    func requestCode() async {
        guard let client else { status = "Supabase-Konfiguration fehlt (siehe README)."; return }
        busy = true; defer { busy = false }
        do {
            try await client.sendCode(to: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            stage = .code
            status = "Einmalcode versendet. Schau in dein E-Mail-Postfach."
        } catch { status = error.localizedDescription }
    }
    func confirmCode() async {
        guard let client else { return }
        busy = true; defer { busy = false }
        do {
            let auth = try await client.verify(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            try SecureSession.save(auth)
            stage = .signedIn
            status = "Verbunden – lade UniFlow-Daten …"
            busy = false
            await sync()
        } catch { status = error.localizedDescription }
    }
    func sync() async {
        guard let client, let session = SecureSession.load(), !busy else { return }
        busy = true; defer { busy = false }
        do {
            let valid = try await client.validSession(session)
            let fetched = try await client.workspace(for: valid)
            try WidgetStorage.save(fetched)
            workspace = fetched
            lastSync = Date()
            WidgetCenter.shared.reloadAllTimelines()
            await ReminderScheduler.refresh(workspace: fetched)
            status = "Aktuell synchronisiert"
        } catch {
            status = "Synchronisierung fehlgeschlagen: \(error.localizedDescription)"
        }
    }
    func enableReminders() async {
        do {
            notifications = try await ReminderScheduler.requestPermission()
            if let workspace, notifications { await ReminderScheduler.refresh(workspace: workspace) }
            status = notifications ? "Erinnerungen aktiviert" : "Benachrichtigungen nicht erlaubt"
        } catch { status = error.localizedDescription }
    }
    func signOut() async {
        SecureSession.delete()
        WidgetStorage.reset()
        await ReminderScheduler.removeAll()
        WidgetCenter.shared.reloadAllTimelines()
        stage = .email
        workspace = nil
        email = ""
        code = ""
        lastSync = nil
        status = "Abgemeldet"
    }
}
