import Foundation
import EventKit
import UIKit

/// Adds a shift to the user's calendar (native replacement for the web app's
/// `downloadICS`). Uses EventKit with a 1-hour alarm; falls back to sharing an
/// `.ics` file if calendar access is denied.
enum CalendarService {
    enum Result {
        case added
        case sharedFile(URL)
        case failed(String)
    }

    static func addShift(_ shift: Shift, companyName: String) async -> Result {
        let store = EKEventStore()
        let granted: Bool
        do {
            if #available(iOS 17.0, *) {
                granted = try await store.requestWriteOnlyAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
        } catch {
            granted = false
        }

        guard granted else {
            if let url = writeICS(shift, companyName: companyName) {
                return .sharedFile(url)
            }
            return .failed("Calendar access was denied.")
        }

        let event = EKEvent(eventStore: store)
        event.title = shiftTitle(shift, companyName: companyName)
        event.startDate = shift.startDateTime
        event.endDate = shift.endDateTime
        event.location = shift.location
        event.notes = shift.notes
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -3600))

        do {
            try store.save(event, span: .thisEvent)
            return .added
        } catch {
            return .failed("Could not save the event.")
        }
    }

    private static func shiftTitle(_ shift: Shift, companyName: String) -> String {
        if let location = shift.location, !location.isEmpty {
            return "\(companyName) — \(location)"
        }
        return "\(companyName) Shift"
    }

    // MARK: - ICS fallback

    private static func writeICS(_ shift: Shift, companyName: String) -> URL? {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        func stamp(_ date: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return f.string(from: date)
        }
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Rosterra//Staff//EN
        BEGIN:VEVENT
        UID:\(shift.id)@sura-roster
        DTSTAMP:\(stamp(Date()))
        DTSTART:\(stamp(shift.startDateTime))
        DTEND:\(stamp(shift.endDateTime))
        SUMMARY:\(shiftTitle(shift, companyName: companyName))
        LOCATION:\(shift.location ?? "")
        BEGIN:VALARM
        TRIGGER:-PT1H
        ACTION:DISPLAY
        DESCRIPTION:Upcoming shift
        END:VALARM
        END:VEVENT
        END:VCALENDAR
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shift-\(shift.id).ics")
        do {
            try ics.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
