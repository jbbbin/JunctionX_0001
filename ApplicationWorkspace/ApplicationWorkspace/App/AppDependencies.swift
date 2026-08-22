import Foundation

@MainActor
struct AppDependencies {
    let store: AppStore
    let applicationAnalyzer: any ApplicationAnalyzing
    let externalURLOpener: any ExternalURLOpening
    let calendarExporter: any CalendarExporting

    static func prototype() -> AppDependencies {
        AppDependencies(
            store: AppStore(),
            applicationAnalyzer: MockApplicationAnalysisService(),
            externalURLOpener: SystemExternalURLOpener(),
            calendarExporter: ICSCalendarExportService()
        )
    }
}
