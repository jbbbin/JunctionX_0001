import AppKit
import Foundation

@MainActor
protocol ExternalURLOpening {
    @discardableResult
    func open(_ url: URL) -> Bool
}

struct SystemExternalURLOpener: ExternalURLOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
protocol CalendarExporting {
    func openCalendarEvent(for application: ApplicationItem) throws
}

enum CalendarExportError: LocalizedError {
    case missingDeadline
    case couldNotOpen

    var errorDescription: String? {
        switch self {
        case .missingDeadline:
            "마감일을 확인한 뒤 캘린더에 추가해 주세요."
        case .couldNotOpen:
            "캘린더 파일을 열지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}

struct ICSCalendarExportService: CalendarExporting {
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    func openCalendarEvent(for application: ApplicationItem) throws {
        guard let deadline = application.deadline else {
            throw CalendarExportError.missingDeadline
        }
        let escapedTitle = application.title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
        let contents = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//PassReady//Application Deadline//KO
        BEGIN:VEVENT
        UID:\(application.id.uuidString)@passready.local
        DTSTAMP:\(formatter.string(from: Date()))
        DTSTART:\(formatter.string(from: deadline))
        DTEND:\(formatter.string(from: deadline.addingTimeInterval(1800)))
        SUMMARY:\(escapedTitle) 마감
        DESCRIPTION:PassReady에서 관리 중인 지원 마감입니다.
        END:VEVENT
        END:VCALENDAR
        """

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PassReady-\(application.id.uuidString).ics")
        try contents.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        guard NSWorkspace.shared.open(fileURL) else {
            throw CalendarExportError.couldNotOpen
        }
    }
}
