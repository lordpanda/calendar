import Foundation

extension EventEditView {
struct EventContext: Identifiable {
        enum Mode {
            case create(seedDate: Date)
            case edit(CalendarEvent)
        }

        let mode: Mode
        let id: String

        static func create(seedDate: Date) -> EventContext {
            EventContext(mode: .create(seedDate: seedDate), id: "create-\(seedDate.timeIntervalSinceReferenceDate)")
        }

        static func edit(_ event: CalendarEvent) -> EventContext {
            EventContext(mode: .edit(event), id: "edit-\(event.id)")
        }
    }

    struct Draft {
        var title = ""
        var location = ""
        var notes = ""
        var startDate: Date
        var endDate: Date
        var isAllDay = false
        var calendarID: String
        var repeatOption: EventRepeatOption = .never
        var invitees: [String] = []
        var attachmentURL = ""
        var videoCallURL = ""
        var alertOption: EventAlertOption = .none
        var visibility: EventVisibilityOption = .default
        var availability: EventAvailabilityOption = .busy
        var isCompleted = false
        var kind: CalendarItemKind = .event

        private static let videoCallPrefix = "Video call: "

        var notesForStorage: String {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedVideoCallURL = videoCallURL.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedVideoCallURL.isEmpty else {
                return trimmedNotes
            }

            guard !trimmedNotes.isEmpty else {
                return Self.videoCallPrefix + trimmedVideoCallURL
            }

            return trimmedNotes + "\n" + Self.videoCallPrefix + trimmedVideoCallURL
        }

        static func userNotes(from storedNotes: String?) -> String {
            (storedNotes ?? "")
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(videoCallPrefix) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        static func videoCallURL(from storedNotes: String?) -> String {
            (storedNotes ?? "")
                .components(separatedBy: .newlines)
                .first { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(videoCallPrefix) }
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(videoCallPrefix.count)) } ?? ""
        }
    }

    enum Mode {
        case create
        case edit(eventID: String)
    }

    enum PendingRecurringAction {
        case save
        case delete
    }

    enum PickerFocus: Equatable {
        case startDate, startTime, endDate, endTime
    }

    enum FocusField: Hashable {
        case title
    }
}
