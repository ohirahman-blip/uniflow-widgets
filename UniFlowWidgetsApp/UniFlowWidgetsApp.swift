import SwiftUI

@main
struct UniFlowWidgetsApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("UniFlow Widgets") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 430, minHeight: 340)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var launchAtLogin = false
    private let accent = Color(red: 0.94, green: 0.58, blue: 0.47)

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.05, green: 0.14, blue: 0.19), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("uniflow").font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-1)
                    Text("WIDGETS").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(accent)
                    Spacer()
                    Image(systemName: "calendar.badge.clock").font(.system(size: 21))
                }
                Text("Dein Studium. Ein Blick genügt.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                if !model.isConfigured {
                    Text("Bitte Supabase-URL und Publishable Key beim Build angeben.")
                        .font(.caption).foregroundStyle(.orange)
                } else if model.stage == .email {
                    Text("Mit deinem UniFlow-Konto verbinden").font(.headline)
                    TextField("E-Mail-Adresse", text: $model.email)
                        .textFieldStyle(.roundedBorder)
                    Button("Anmeldecode senden") { Task { await model.requestCode() } }
                        .buttonStyle(.borderedProminent).disabled(model.busy || !model.email.contains("@"))
                } else if model.stage == .code {
                    Text("Code aus deiner E-Mail").font(.headline)
                    TextField("Einmalcode", text: $model.code).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Bestätigen") { Task { await model.confirmCode() } }
                            .buttonStyle(.borderedProminent).disabled(model.busy || model.code.count < 6)
                        Button("Zurück") { model.stage = .email }.buttonStyle(.plain)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("UniFlow verbunden", systemImage: "checkmark.circle.fill").foregroundStyle(.mint)
                        Text(model.nextText).font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                    }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                     .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    HStack(spacing: 12) {
                        Button("Jetzt synchronisieren") { Task { await model.sync() } }
                            .disabled(model.busy)
                        Button("30-Minuten-Erinnerungen") { Task { await model.enableReminders() } }
                            .disabled(model.busy)
                    }
                    Toggle("Beim Anmelden am Mac starten", isOn: $launchAtLogin)
                        .font(.system(size: 12))
                        .onChange(of: launchAtLogin) { _, value in model.setLaunchAtLogin(value) }
                    Button("Abmelden") { Task { await model.signOut() } }.buttonStyle(.plain)
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Text(model.status).font(.caption).foregroundStyle(.white.opacity(0.72))
            }
            .padding(28)
            .foregroundStyle(.white)
        }
        .onAppear { launchAtLogin = model.loginAtStartup }
    }
}
