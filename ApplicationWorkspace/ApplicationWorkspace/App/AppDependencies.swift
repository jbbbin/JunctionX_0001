import Foundation

@MainActor
struct AppDependencies {
    let store: AppStore
    let applicationAnalyzer: any ApplicationAnalyzing
    let localAnalysisCredentialStore: (any UpstageAPIKeyStoring)?
    let externalURLOpener: any ExternalURLOpening
    let calendarExporter: any CalendarExporting

    static func localDevelopment() -> AppDependencies {
        let credentialStore = LocalUpstageAPIKeyStore()
        let client = UpstageAPIClient(apiKeyStore: credentialStore)

        return AppDependencies(
            store: AppStore(),
            applicationAnalyzer: LocalUpstageApplicationAnalysisService(client: client),
            localAnalysisCredentialStore: credentialStore,
            externalURLOpener: SystemExternalURLOpener(),
            calendarExporter: ICSCalendarExportService()
        )
    }

    static func prototype() -> AppDependencies {
        AppDependencies(
            store: AppStore(),
            applicationAnalyzer: MockApplicationAnalysisService(),
            localAnalysisCredentialStore: nil,
            externalURLOpener: SystemExternalURLOpener(),
            calendarExporter: ICSCalendarExportService()
        )
    }
}
