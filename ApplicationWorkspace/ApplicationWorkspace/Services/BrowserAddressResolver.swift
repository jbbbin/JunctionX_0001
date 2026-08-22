import Foundation

struct BrowserAddressResolver {
    func resolve(_ rawValue: String) -> URL? {
        if let address = resolveWebAddress(rawValue) {
            return address
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let blockedSchemes = ["javascript:", "file:", "data:"]
        guard !blockedSchemes.contains(where: { value.lowercased().hasPrefix($0) }) else {
            return nil
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: value)]
        return components?.url
    }

    func resolveWebAddress(_ rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let blockedSchemes = ["javascript:", "file:", "data:"]
        guard !blockedSchemes.contains(where: { value.lowercased().hasPrefix($0) }) else {
            return nil
        }

        if let directURL = URL(string: value),
           let scheme = directURL.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return directURL
        }

        let looksLikeAddress = !value.contains(" ")
            && (value.contains(".") || value.contains(":") || value.hasPrefix("localhost"))

        if looksLikeAddress {
            let scheme = value.hasPrefix("localhost") ? "http" : "https"
            if let url = URL(string: "\(scheme)://\(value)") {
                return url
            }
        }

        return nil
    }
}
