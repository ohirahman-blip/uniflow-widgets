import Foundation

// Mirrors only the relevant fields in UniFlow's existing private_workspaces.payload.
// Unknown fields remain compatible because Codable ignores them.
struct UniFlowWorkspace: Codable {
    var activeSemesterId: String
    var offerings: [UniOffering]
    var assessments: [UniAssessment]
    var modules: [UniModule]

    init(activeSemesterId: String = "", offerings: [UniOffering] = [], assessments: [UniAssessment] = [], modules: [UniModule] = []) {
        self.activeSemesterId = activeSemesterId
        self.offerings = offerings
        self.assessments = assessments
        self.modules = modules
    }
}
struct UniModule: Codable {
    let id: String
    let name: String
}
struct UniAssessment: Codable {
    let id: String
    let semesterId: String
    let moduleId: String
    let type: String
    let title: String
    let date: String
}
struct UniOverride: Codable {
    let date: String?
    let from: String?
    let to: String?
    let cancelled: Bool?
    let selected: Bool?
}
struct UniScheduleChange: Codable {
    let fromOrigin: String
    let shiftDays: Int
    let from: String
    let to: String
}
struct UniOffering: Codable {
    let id: String
    let semesterId: String
    let moduleId: String
    let name: String
    let category: String
    let date: String
    let endDate: String
    let from: String
    let to: String
    let recurrence: String
    let room: String?
    let onlineLink: String?
    let organizer: String?
    let selected: Bool
    let overrides: [String: UniOverride]?
    let scheduleChanges: [UniScheduleChange]?
}
struct UniOccurrence: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let organizer: String
    let location: String
    let start: Date
    let end: Date
    let moduleId: String

    static func == (lhs: UniOccurrence, rhs: UniOccurrence) -> Bool { lhs.id == rhs.id && lhs.start == rhs.start }
}
struct UniExam: Identifiable {
    let id: String
    let title: String
    let module: String
    let date: Date
    func daysRemaining(from now: Date, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0)
    }
}

enum Spotlight {
    case active(UniOccurrence)
    case upcoming(UniOccurrence, minutes: Int)
    case tomorrow([UniOccurrence])
    case none
}

enum CalendarEngine {
    static let isoDay: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    static func dayKey(_ date: Date) -> String { isoDay.string(from: date) }
    static func dateFor(_ day: String, time: String, calendar: Calendar = .current) -> Date? {
        guard let base = isoDay.date(from: day) else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base)
    }
    static func dayOffset(from first: Date, to second: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: second)).day ?? 0
    }
    static func occurrences(_ workspace: UniFlowWorkspace, between start: Date, and end: Date, calendar: Calendar = .current) -> [UniOccurrence] {
        guard end >= start else { return [] }
        return workspace.offerings
            .filter { $0.semesterId == workspace.activeSemesterId }
            .flatMap { offering -> [UniOccurrence] in
                guard let first = isoDay.date(from: offering.date), let final = isoDay.date(from: offering.endDate) else { return [] }
                var result: [UniOccurrence] = []
                var origin = first
                let step: Int = offering.recurrence == "biweekly" ? 14 : offering.recurrence == "weekly" ? 7 : 0
                for _ in 0..<400 {
                    if origin > final { break }
                    if origin > calendar.date(byAdding: .day, value: 7, to: end)! { break }
                    let key = dayKey(origin)
                    let override = offering.overrides?[key]
                    let chosen = override?.selected ?? offering.selected
                    if chosen && override?.cancelled != true {
                        let schedule = (offering.scheduleChanges ?? []).filter { $0.fromOrigin <= key }.sorted { $0.fromOrigin < $1.fromOrigin }.last
                        let shifted = calendar.date(byAdding: .day, value: schedule?.shiftDays ?? 0, to: origin) ?? origin
                        let actualDay = override?.date ?? dayKey(shifted)
                        let from = override?.from ?? schedule?.from ?? offering.from
                        let to = override?.to ?? schedule?.to ?? offering.to
                        if let fromDate = dateFor(actualDay, time: from, calendar: calendar),
                           let toDate = dateFor(actualDay, time: to, calendar: calendar),
                           toDate > fromDate, toDate >= start, fromDate <= end {
                            let room = offering.room?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            let hasLink = !(offering.onlineLink?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                            result.append(UniOccurrence(id: "\(offering.id):\(key)", title: offering.name,
                                category: offering.category, organizer: offering.organizer ?? "",
                                location: [room, hasLink ? "Online" : ""].filter { !$0.isEmpty }.joined(separator: " + "),
                                start: fromDate, end: toDate, moduleId: offering.moduleId))
                        }
                    }
                    if step == 0 { break }
                    guard let next = calendar.date(byAdding: .day, value: step, to: origin) else { break }
                    origin = next
                }
                return result
            }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    static func exams(_ workspace: UniFlowWorkspace, from now: Date, calendar: Calendar = .current) -> [UniExam] {
        let start = calendar.startOfDay(for: now)
        let names = Dictionary(workspace.modules.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return workspace.assessments.filter { $0.semesterId == workspace.activeSemesterId && $0.type == "exam" }
            .compactMap { assessment -> UniExam? in
                guard let day = isoDay.date(from: assessment.date), day >= start else { return nil }
                return UniExam(id: assessment.id, title: assessment.title,
                               module: names[assessment.moduleId] ?? "Klausur", date: day)
            }
            .sorted { $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date }
    }

    // Priority: upcoming in <=30min wins over an ongoing class; otherwise keep showing
    // the class until it ends. When nothing is left today, show tomorrow's titles.
    static func spotlight(_ workspace: UniFlowWorkspace, at now: Date, calendar: Calendar = .current) -> Spotlight {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: tomorrow)!
        let items = occurrences(workspace, between: calendar.startOfDay(for: now), and: dayAfter, calendar: calendar)
        let today = items.filter { $0.start < tomorrow && $0.end > now }
        let upcoming = today.first { $0.start > now }
        let current = today.first { $0.start <= now && $0.end > now }
        if let upcoming = upcoming, upcoming.start.timeIntervalSince(now) <= 30 * 60 {
            return .upcoming(upcoming, minutes: max(0, Int(ceil(upcoming.start.timeIntervalSince(now) / 60))))
        }
        if let current = current { return .active(current) }
        if let upcoming = upcoming { return .upcoming(upcoming, minutes: Int(ceil(upcoming.start.timeIntervalSince(now) / 60))) }
        return .tomorrow(items.filter { $0.start >= tomorrow && $0.start < dayAfter })
    }

    static func transitionDates(_ workspace: UniFlowWorkspace, at now: Date, calendar: Calendar = .current) -> [Date] {
        let end = calendar.date(byAdding: .day, value: 7, to: now)!
        let items = occurrences(workspace, between: now, and: end, calendar: calendar)
        var dates = items.flatMap { event in
            [event.start.addingTimeInterval(-7200), event.start.addingTimeInterval(-1800), event.start, event.end]
        }
        for n in 1...7 {
            if let day = calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: now)) { dates.append(day) }
        }
        return Array(Set(dates.filter { $0 > now })).sorted().prefix(64).map { $0 }
    }
}
