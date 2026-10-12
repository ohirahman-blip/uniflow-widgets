import AppIntents
import SwiftUI
import WidgetKit

struct UniFlowEntry: TimelineEntry {
    let date: Date
    let workspace: UniFlowWorkspace?
    let page: Int
}

struct UniFlowProvider: TimelineProvider {
    func placeholder(in context: Context) -> UniFlowEntry { UniFlowEntry(date: Date(), workspace: Self.preview, page: 0) }
    func getSnapshot(in context: Context, completion: @escaping (UniFlowEntry) -> Void) {
        completion(UniFlowEntry(date: Date(), workspace: WidgetStorage.read() ?? (context.isPreview ? Self.preview : nil), page: WidgetStorage.page))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UniFlowEntry>) -> Void) {
        let now = Date()
        let workspace = WidgetStorage.read()
        let refreshes = workspace.map { CalendarEngine.transitionDates($0, at: now) } ?? []
        let allDates = [now] + refreshes
        let entries = allDates.map { UniFlowEntry(date: $0, workspace: workspace, page: WidgetStorage.page) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }

    static let preview: UniFlowWorkspace = {
        let today = CalendarEngine.dayKey(Date())
        return UniFlowWorkspace(activeSemesterId: "sample", offerings: [
            UniOffering(id: "demo", semesterId: "sample", moduleId: "m", name: "Data Management",
                category: "Vorlesung", date: today, endDate: today,
                from: "17:00", to: "19:00", recurrence: "once", room: "MA 041",
                onlineLink: nil, organizer: "Prof. Müller", selected: true,
                overrides: nil, scheduleChanges: nil)],
            assessments: [UniAssessment(id: "exam", semesterId: "sample", moduleId: "m",
                                       type: "exam", title: "Datenbanksysteme", date: today)],
            modules: [UniModule(id: "m", name: "Data Management")])
    }()
}

struct ShiftTimelineIntent: AppIntent {
    static var title: LocalizedStringResource = "Zeitleiste wechseln"
    static var description = IntentDescription("Blättert durch die kommenden Veranstaltungen.")
    @Parameter(title: "Richtung") var delta: Int
    init() { delta = 0 }
    init(delta: Int) { self.delta = delta }
    func perform() async throws -> some IntentResult {
        WidgetStorage.page = WidgetStorage.page + max(-1, min(1, delta))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private enum WidgetText {
    static func time(_ d: Date) -> String { d.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))) }
    static func date(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE"))) }
}

private struct GlassBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        Group {
            if renderingMode == .accented {
                Color.clear
            } else {
                LinearGradient(colors: [Color(red: 0.11, green: 0.22, blue: 0.26).opacity(0.54),
                                        Color(red: 0.05, green: 0.07, blue: 0.10).opacity(0.42),
                                        Color(red: 0.06, green: 0.19, blue: 0.24).opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

private struct UniFlowBrand: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("uniflow").font(.system(size: 14, weight: .bold, design: .rounded)).tracking(-0.5)
            Text(".").foregroundStyle(.orange).fontWeight(.black)
            Spacer()
            Image(systemName: "calendar.badge.clock").font(.system(size: 11, weight: .medium)).opacity(0.7)
        }
        .foregroundStyle(.primary)
        .widgetAccentable()
    }
}

private struct TimelineRow: View {
    let event: UniOccurrence
    let isHighlighted: Bool
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(WidgetText.time(event.start))
                .font(.system(size: 10, weight: isHighlighted ? .bold : .medium, design: .rounded))
                .monospacedDigit().frame(width: 42, alignment: .leading)
                .foregroundStyle(isHighlighted ? .primary : .secondary)
            Rectangle().fill(isHighlighted ? Color.orange : Color.primary.opacity(0.2))
                .frame(width: 2, height: 13)
            Text(event.title).lineLimit(1).minimumScaleFactor(0.78)
                .font(.system(size: 11, weight: isHighlighted ? .semibold : .medium))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpotlightView: View {
    let workspace: UniFlowWorkspace
    let now: Date
    let compact: Bool
    var body: some View {
        let state = CalendarEngine.spotlight(workspace, at: now)
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            switch state {
            case .active(let event):
                caption("LÄUFT GERADE", symbol: "circle.fill")
                Text(event.title).font(.system(size: compact ? 22 : 20, weight: .bold, design: .rounded))
                    .lineLimit(2).minimumScaleFactor(0.72)
                details(event)
                Label("Bis \(WidgetText.time(event.end))", systemImage: "clock")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            case .upcoming(let event, let minutes):
                caption(minutes <= 30 ? "GLEICH GEHT’S LOS" : "NÄCHSTE VERANSTALTUNG", symbol: "clock.fill")
                Text(event.title).font(.system(size: compact ? 22 : 20, weight: .bold, design: .rounded))
                    .lineLimit(2).minimumScaleFactor(0.72)
                details(event)
                Text(minutes <= 120 ? "In \(minutes) Minuten" : "Heute · \(WidgetText.time(event.start))")
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.primary)
            case .tomorrow(let events):
                caption("MORGEN", symbol: "sunrise.fill")
                if events.isEmpty {
                    Text("Morgen frei").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("Keine Veranstaltungen geplant").font(.caption).foregroundStyle(.secondary)
                } else {
                    // Only times on the left and titles on the right, as requested.
                    ForEach(Array(events.prefix(compact ? 4 : 3))) { event in
                        TimelineRow(event: event, isHighlighted: false)
                    }
                    if events.count > (compact ? 4 : 3) {
                        Text("+ \(events.count - (compact ? 4 : 3)) weitere").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            case .none:
                caption("STUNDENPLAN", symbol: "calendar")
                Text("Noch keine Termine").font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Verbinde dein UniFlow-Konto.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
    private func caption(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1)
            .foregroundStyle(.secondary)
    }
    private func details(_ event: UniOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text([event.category, event.organizer].filter { !$0.isEmpty }.joined(separator: " · "))
                .lineLimit(1)
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin") .lineLimit(1) }
            Text("\(WidgetText.time(event.start)) – \(WidgetText.time(event.end))")
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }
}

private struct Pager: View {
    var body: some View {
        HStack(spacing: 7) {
            Button(intent: ShiftTimelineIntent(delta: -1)) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 18)
            }.buttonStyle(.plain).accessibilityLabel("Frühere Termine")
            Button(intent: ShiftTimelineIntent(delta: 1)) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 18)
            }.buttonStyle(.plain).accessibilityLabel("Weitere Termine")
        }
        .background(.thinMaterial, in: Capsule())
    }
}

struct UniFlowSmallView: View {
    let entry: UniFlowEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            UniFlowBrand()
            if let workspace = entry.workspace {
                if entry.page > 0,
                   let event = futureEvents(workspace).dropFirst(entry.page).first {
                    Text("ZEITLEISTE · \(WidgetText.date(event.start))")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    Text(event.title).font(.system(size: 21, weight: .bold, design: .rounded)).lineLimit(2)
                    Text("\(WidgetText.time(event.start)) · \(event.location)")
                        .font(.system(size: 10)).lineLimit(2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    SpotlightView(workspace: workspace, now: entry.date, compact: true)
                }
                HStack { Spacer(); Pager() }
            } else {
                Spacer(minLength: 5)
                Text("Dein nächster Termin").font(.system(size: 22, weight: .bold, design: .rounded)).lineLimit(2)
                Text("UniFlow Widgets öffnen und anmelden")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(4)
        .containerBackground(for: .widget) { GlassBackground() }
    }
}

private func futureEvents(_ workspace: UniFlowWorkspace, from date: Date = Date()) -> [UniOccurrence] {
    let until = Calendar.current.date(byAdding: .day, value: 45, to: date)!
    return CalendarEngine.occurrences(workspace, between: date, and: until).filter { $0.end > date }
}

struct UniFlowWideView: View {
    let entry: UniFlowEntry
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                UniFlowBrand()
                if let workspace = entry.workspace {
                    let events = futureEvents(workspace, from: entry.date)
                    let pageEvents = Array(events.dropFirst(entry.page).prefix(3))
                    if entry.page == 0 {
                        SpotlightView(workspace: workspace, now: entry.date, compact: false)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        Text("ZEITLEISTE").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                        ForEach(pageEvents) { TimelineRow(event: $0, isHighlighted: false) }
                        Spacer(minLength: 0)
                    }
                    HStack { Text("TERMINE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary); Spacer(); Pager() }
                } else {
                    Text("Mit UniFlow anmelden").font(.headline)
                    Text("Begleit-App öffnen").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 11) {
                Label("NÄCHSTE KLAUSUR", systemImage: "graduationcap.fill")
                    .font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
                if let exam = entry.workspace.flatMap({ CalendarEngine.exams($0, from: entry.date).first }) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(exam.daysRemaining(from: entry.date))")
                            .font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                        Text("TAGE").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    }.minimumScaleFactor(0.7)
                    Text(exam.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(exam.module).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(WidgetText.date(exam.date)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                } else {
                    Spacer(minLength: 7)
                    Text("Keine Klausur geplant").font(.system(size: 15, weight: .medium)).lineLimit(3)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(4)
        .containerBackground(for: .widget) { GlassBackground() }
    }
}

struct UniFlowSmallWidget: Widget {
    let kind = "UniFlow.Next.small"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UniFlowProvider()) { entry in
            UniFlowSmallView(entry: entry)
        }
        .configurationDisplayName("UniFlow · Nächster Termin")
        .description("Laufende Veranstaltung, nächste Vorlesung und die Termine von morgen.")
        .supportedFamilies([.systemSmall])
    }
}
struct UniFlowWideWidget: Widget {
    let kind = "UniFlow.NextAndExam.medium"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UniFlowProvider()) { entry in
            UniFlowWideView(entry: entry)
        }
        .configurationDisplayName("UniFlow · Zeitplan & Klausur")
        .description("Zeitleiste und nächste Klausur mit Countdown auf einem breiten Widget.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct UniFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        UniFlowSmallWidget()
        UniFlowWideWidget()
    }
}
