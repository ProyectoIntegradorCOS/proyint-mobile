import Flutter
import Foundation
import Security

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Expone canal nativo iOS para persistir y limpiar auth_token en Keychain desde Flutter][obj: SecureStoreChannel]
enum SecureStoreChannel {
    private static let account = "auth_token"
    static var writeTokenHandler: (String) throws -> Void = writeToken
    static var clearTokenHandler: () -> Void = clearToken

    static func resetHandlers() {
        writeTokenHandler = writeToken
        clearTokenHandler = clearToken
    }

    static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setToken":
            guard let token = validatedToken(from: call.arguments) else {
                result(
                    FlutterError(
                        code: "invalid_args",
                        message: "token vacío",
                        details: nil
                    )
                )
                return
            }

            do {
                try writeTokenHandler(token)
                NSLog("[SecureStoreChannel] Token escrito en Keychain OK")
                result(nil)
            } catch {
                NSLog("[SecureStoreChannel] ERROR al escribir token en Keychain: \(error.localizedDescription)")
                result(
                    FlutterError(
                        code: "secure_store_error",
                        message: "No se pudo guardar token",
                        details: error.localizedDescription
                    )
                )
            }

        case "clearToken":
            clearTokenHandler()
            NSLog("[SecureStoreChannel] Token eliminado de Keychain")
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    static func validatedToken(from arguments: Any?) -> String? {
        let args = arguments as? [String: Any]
        let token = args?["token"] as? String ?? ""
        return token.isEmpty ? nil : token
    }

    private static func writeToken(_ token: String) throws {
        clearToken()

        guard let data = token.data(using: .utf8) else {
            throw NSError(domain: "SecureStoreChannel", code: -1)
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "pe.gob.onp.thaqhiri",
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func clearToken() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "pe.gob.onp.thaqhiri",
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
