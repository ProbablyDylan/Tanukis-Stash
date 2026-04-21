//
//  Keychain.swift
//  Tanuki
//
//  Thin wrapper around Security.framework for storing the API key.
//  Intentionally minimal — if we ever need biometric-gated reads or
//  shared access groups, extend here rather than sprinkling SecItem*
//  calls across the codebase.
//

import Foundation
import Security
import os.log

enum Keychain {
    private static let service = "dev.jemsoftware.tanukistash";

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8);
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ];

        // Try to update an existing item first.
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        );
        if updateStatus == errSecSuccess { return true; }

        if updateStatus != errSecItemNotFound {
            os_log("Keychain update failed for %{public}s: OSStatus %{public}d", log: .default, account, Int(updateStatus));
            return false;
        }

        // No existing item — add a new one.
        var addQuery = query;
        addQuery[kSecValueData] = data;
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly;

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil);
        if addStatus != errSecSuccess {
            os_log("Keychain add failed for %{public}s: OSStatus %{public}d", log: .default, account, Int(addStatus));
            return false;
        }
        return true;
    }

    static func load(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ];

        var result: AnyObject?;
        let status = SecItemCopyMatching(query as CFDictionary, &result);
        if status == errSecItemNotFound { return nil; }
        if status != errSecSuccess {
            os_log("Keychain load failed for %{public}s: OSStatus %{public}d", log: .default, account, Int(status));
            return nil;
        }
        guard let data = result as? Data else { return nil; }
        return String(data: data, encoding: .utf8);
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ];
        let status = SecItemDelete(query as CFDictionary);
        if status == errSecSuccess || status == errSecItemNotFound { return true; }
        os_log("Keychain delete failed for %{public}s: OSStatus %{public}d", log: .default, account, Int(status));
        return false;
    }
}
