import Foundation
import Security

enum UpstageAPIKeySource {
    case environment
    case keychain
}

@MainActor
protocol UpstageAPIKeyStoring: AnyObject {
    var hasAPIKey: Bool { get }
    var activeSource: UpstageAPIKeySource? { get }

    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

extension UpstageAPIKeyStoring {
    var activeSource: UpstageAPIKeySource? {
        hasAPIKey ? .keychain : nil
    }
}

enum UpstageAPIKeyStoreError: LocalizedError {
    case invalidAPIKey
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            "Upstage API 키를 확인해 주세요."
        case .keychainFailure:
            "API 키를 macOS Keychain에서 처리하지 못했어요."
        }
    }
}

/// Local-development credential store.
///
/// `UPSTAGE_API_KEY` always takes precedence so Xcode schemes and CI can inject a
/// key without touching Keychain. A key saved through the app is stored as a
/// generic-password item and is never written to UserDefaults, the app bundle,
/// logs, or the repository.
@MainActor
final class LocalUpstageAPIKeyStore: UpstageAPIKeyStoring {
    static let environmentVariable = "UPSTAGE_API_KEY"

    private let service: String
    private let account: String
    private let environment: () -> [String: String]

    init(
        service: String = "com.junctionx.ApplicationWorkspace.upstage",
        account: String = "local-api-key",
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.service = service
        self.account = account
        self.environment = environment
    }

    var hasAPIKey: Bool {
        activeSource != nil
    }

    var activeSource: UpstageAPIKeySource? {
        if normalized(environment()[Self.environmentVariable]) != nil {
            return .environment
        }
        guard (try? loadKeychainAPIKey()) != nil else { return nil }
        return .keychain
    }

    func loadAPIKey() throws -> String? {
        if let environmentKey = normalized(environment()[Self.environmentVariable]) {
            return environmentKey
        }

        return try loadKeychainAPIKey()
    }

    private func loadKeychainAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8),
                  let key = normalized(value)
            else {
                throw UpstageAPIKeyStoreError.invalidAPIKey
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw UpstageAPIKeyStoreError.keychainFailure(status)
        }
    }

    func saveAPIKey(_ apiKey: String) throws {
        guard let key = normalized(apiKey), let data = key.data(using: .utf8) else {
            throw UpstageAPIKeyStoreError.invalidAPIKey
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw UpstageAPIKeyStoreError.keychainFailure(addStatus)
            }
        default:
            throw UpstageAPIKeyStoreError.keychainFailure(updateStatus)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UpstageAPIKeyStoreError.keychainFailure(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}
