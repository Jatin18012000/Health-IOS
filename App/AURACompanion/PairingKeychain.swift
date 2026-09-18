import Foundation
import Security

/// The pairing code, in the keychain.
///
/// Small on purpose. It holds one string, and the reason it is not a line of
/// `UserDefaults` is that a preferences plist travels in an unencrypted device
/// backup — and this code is the only thing standing between a health database
/// and anyone on the same Wi-Fi.
struct PairingKeychain {

    private let service = "com.aura.companion.pairing"
    private let account = "mac"

    var code: String? {
        get {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data
            else { return nil }
            return String(data: data, encoding: .utf8)
        }
        nonmutating set {
            // Delete first rather than branching on add-vs-update: the two
            // paths differ subtly and the difference has no upside here.
            SecItemDelete(baseQuery as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }

            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            // Never leaves this device, and unreadable until the phone has been
            // unlocked once since boot.
            attributes[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
