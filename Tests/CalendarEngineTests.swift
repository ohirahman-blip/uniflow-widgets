import Foundation

@main struct CalendarEngineTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("Failed: " + message) }
    }
    static func make(_ id: String, _ date: String, _ from: String, _ to: String) -> UniOffering {
        UniOffering(id: id, semesterId: "s", moduleId: "m", name: id, category: "Vorlesung", date: date,
          endDate: date, from: from, to: to, recurrence: "once", room: "MA 041", onlineLink: nil,
          organizer: "Dozent", selected: true, overrides: nil, scheduleChanges: nil)
    }
    static func main() {
        let now = CalendarEngine.dateFor("2026-10-12", time: "10:00")!
        let data = UniFlowWorkspace(activeSemesterId: "s", offerings: [
            make("laufend", "2026-10-12", "09:00", "11:00"),
            make("folgend", "2026-10-12", "10:30", "12:00")],
            assessments: [UniAssessment(id: "a", semesterId: "s", moduleId: "m", type: "exam", title: "Bio", date: "2026-10-18")],
            modules: [UniModule(id: "m", name: "Biologie")])
        if case .upcoming(let event, let minutes) = CalendarEngine.spotlight(data, at: now) {
            check(event.id.hasPrefix("folgend:"), "next should be prioritized 30 min before")
            check(minutes == 30, "30 minutes remaining")
        } else { fatalError("Expected upcoming event") }
        let earlier = CalendarEngine.dateFor("2026-10-12", time: "09:20")!
        if case .active(let event) = CalendarEngine.spotlight(data, at: earlier) {
            check(event.id.hasPrefix("laufend:"), "current class stays visible before 30 minute warning")
        } else { fatalError("Expected active event") }
        let tomorrow = UniFlowWorkspace(activeSemesterId:"s", offerings:[make("morgen", "2026-10-13", "12:00", "13:00")])
        if case .tomorrow(let rows) = CalendarEngine.spotlight(tomorrow, at: now) {
            check(rows.count == 1, "tomorrow events displayed")
        } else { fatalError("Expected tomorrow agenda") }
        let exam = CalendarEngine.exams(data, from: now).first!
        check(exam.daysRemaining(from: now) == 6, "calendar date countdown")
        let paused = UniOffering(id:"paused",semesterId:"s",moduleId:"m",name:"Paused",category:"Übung",
            date:"2026-10-12",endDate:"2026-10-12",from:"14:00",to:"15:00",recurrence:"once",
            room:nil,onlineLink:nil,organizer:nil,selected:true,
            overrides:["2026-10-12":UniOverride(date:nil,from:nil,to:nil,cancelled:nil,selected:false)],scheduleChanges:nil)
        let testWorkspace = UniFlowWorkspace(activeSemesterId:"s",offerings:[paused])
        let existing = CalendarEngine.occurrences(testWorkspace, between: now, and: now.addingTimeInterval(86400))
        check(existing.isEmpty, "suppressed attendance not in widget")
        print("CalendarEngineTests OK")
    }
}
