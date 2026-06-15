// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 21:58 UTC-5 (Lima)][desc: Servicio nativo iOS para flush de ubicaciones pendientes desde SQLite directo al API, sin depender del engine Flutter. Espejo de PendingLocationApiClient.kt][obj: PendingFlushService]
import Foundation
// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-09 22:21 UTC-5 (Lima)][desc: Importa Security y SQLite3 para soportar lectura explícita de Keychain y flush directo sobre DB local en iOS][obj: PendingFlushService imports]
import Security
import SQLite3

enum PendingFlushService {
    struct FlushContext {
        let uid: String
        let apiBaseUrl: String
        let token: String
        let dbPath: String
    }

    struct PendingRow {
        let id: Int64
        let saaSubject: String
        let latitude: Double
        let longitude: Double
        let timestamp: String
        let accuracy: Double
        let altitude: Double
        let speed: Double
        let heading: Double
        let batteryLevel: Double
        let activityType: String
    }

    private struct PendingLocationStore {
        let dbPath: String

        func load(uid: String, limit: Int) -> [PendingRow]? {
            // WAL permite un escritor + múltiples lectores simultáneos sin bloquear.
            // Necesario porque el BGTask puede correr mientras Flutter también accede a la DB.
            var db: OpaquePointer?
            guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
                  let db = db else {
                NSLog("[PendingFlushService] No se pudo abrir SQLite (readonly)")
                return nil
            }
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            defer { sqlite3_close(db) }

            return readPendingLocations(db: db, uid: uid, limit: limit)
        }

        func insert(uid: String, point: [String: Any]) {
            var db: OpaquePointer?
            guard sqlite3_open_v2(
                dbPath,
                &db,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
                nil
            ) == SQLITE_OK,
            let db = db else {
                NSLog("[PendingFlushService] insertLocation: no se pudo abrir SQLite")
                return
            }
            defer { sqlite3_close(db) }

            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            ensureSchema(db: db)

            let latitude = point["latitude"] as? Double ?? 0.0
            let longitude = point["longitude"] as? Double ?? 0.0
            let timestamp = point["timestamp"] as? String ?? ""
            let accuracy = point["accuracy"] as? Double ?? 0.0
            let altitude = point["altitude"] as? Double ?? 0.0
            let speed = point["speed"] as? Double ?? 0.0
            let heading = point["heading"] as? Double ?? 0.0
            let epochMs = Int64(Date().timeIntervalSince1970 * 1000)

            let sql = """
                INSERT INTO pending_locations
                (saaSubject, latitude, longitude, timestamp, timestamp_epoch_ms,
                 accuracy, altitude, speed, heading, batteryLevel, activityType)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 'unknown')
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt = stmt else {
                NSLog("[PendingFlushService] insertLocation: prepare falló")
                return
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (uid as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, latitude)
            sqlite3_bind_double(stmt, 3, longitude)
            sqlite3_bind_text(stmt, 4, (timestamp as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 5, epochMs)
            sqlite3_bind_double(stmt, 6, accuracy)
            sqlite3_bind_double(stmt, 7, altitude)
            sqlite3_bind_double(stmt, 8, speed)
            sqlite3_bind_double(stmt, 9, heading)

            if sqlite3_step(stmt) == SQLITE_DONE {
                NSLog("[PendingFlushService] ENQUEUE_IOS_SQLITE uid=\(uid) lat=\(latitude) lng=\(longitude)")
            } else {
                NSLog("[PendingFlushService] insertLocation: insert falló")
            }
        }

        func remove(ids: [Int64], uid: String) {
            guard !ids.isEmpty else { return }

            var db: OpaquePointer?
            guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
                  let db = db else {
                NSLog("[PendingFlushService] No se pudo abrir SQLite (readwrite)")
                return
            }
            defer { sqlite3_close(db) }

            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            deleteLocations(db: db, ids: ids)
            NSLog("[PendingFlushService] FLUSH_OK \(ids.count) ubicaciones eliminadas uid=\(uid)")
        }
    }

    private struct PendingLocationApiClient {
        let apiBaseUrl: String
        let token: String

        func send(locations: [PendingRow]) -> Bool {
            guard let request = makeBatchRequest(
                apiBaseUrl: apiBaseUrl,
                token: token,
                locations: locations
            ) else { return false }

            let semaphore = DispatchSemaphore(value: 0)
            var success = false
            URLSession.shared.dataTask(with: request) { _, response, error in
                if let http = response as? HTTPURLResponse {
                    success = (200...299).contains(http.statusCode)
                    NSLog("[PendingFlushService] HTTP \(http.statusCode)")
                } else if let error = error {
                    NSLog("[PendingFlushService] Error de red: \(error.localizedDescription)")
                }
                semaphore.signal()
            }.resume()
            semaphore.wait()
            return success
        }
    }

    // MARK: - Entry point

    /// Punto de entrada llamado desde el BGAppRefreshTask.
    /// Lee ubicaciones pendientes de SQLite y las envía al API.
    static func flush() {
        guard let context = makeFlushContext() else {
            return
        }
        let store = PendingLocationStore(dbPath: context.dbPath)
        let apiClient = PendingLocationApiClient(
            apiBaseUrl: context.apiBaseUrl,
            token: context.token
        )

        guard let locations = store.load(uid: context.uid, limit: 100) else {
            return
        }

        guard !locations.isEmpty else {
            NSLog("[PendingFlushService] Sin ubicaciones pendientes para uid=\(context.uid)")
            return
        }

        NSLog("[PendingFlushService] Enviando \(locations.count) ubicaciones para uid=\(context.uid)")

        let success = apiClient.send(locations: locations)

        if success {
            store.remove(ids: locations.map(\.id), uid: context.uid)
        } else {
            NSLog("[PendingFlushService] FLUSH_FAIL envío fallido, se reintentará")
        }
    }

    static func loadPendingLocations(
        dbPath: String,
        uid: String,
        limit: Int
    ) -> [PendingRow]? {
        PendingLocationStore(dbPath: dbPath).load(uid: uid, limit: limit)
    }

    static func removePendingLocations(
        dbPath: String,
        ids: [Int64],
        uid: String
    ) {
        PendingLocationStore(dbPath: dbPath).remove(ids: ids, uid: uid)
    }

    static func makeFlushContext(
        defaults: UserDefaults = .standard,
        tokenReader: () -> String? = readTokenFromKeychain,
        dbPathProvider: () -> String? = getDatabasePath
    ) -> FlushContext? {
        guard let uid = defaults.string(forKey: "flutter.auth_uid"),
              !uid.isEmpty else {
            NSLog("[PendingFlushService] Sin auth_uid, abortando")
            return nil
        }

        guard let apiBaseUrl = normalizedApiBaseUrl(
            defaults.string(forKey: "flutter.api_base_url")
        ) else {
            NSLog("[PendingFlushService] Sin api_base_url, abortando")
            return nil
        }

        guard let token = tokenReader(), !token.isEmpty else {
            NSLog("[PendingFlushService] Sin auth_token en Keychain, abortando")
            return nil
        }

        guard let dbPath = dbPathProvider() else {
            NSLog("[PendingFlushService] DB tracking_store.db no encontrada")
            return nil
        }

        return FlushContext(
            uid: uid,
            apiBaseUrl: apiBaseUrl,
            token: token,
            dbPath: dbPath
        )
    }

    static func normalizedApiBaseUrl(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Database path

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-13 UTC-5 (Lima)][desc: sqflite en iOS usa NSDocumentDirectory (no NSLibraryDirectory). Corrección de path para que nativo y Flutter lean/escriban el mismo archivo.][obj: PendingFlushService.getDatabasePath documentDirectory]
    /// sqflite en iOS almacena la DB en {Documents}/tracking_store.db
    private static func getDatabasePath() -> String? {
        guard let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }

        let path = documentsDir
            .appendingPathComponent("tracking_store.db")
            .path

        guard FileManager.default.fileExists(atPath: path) else {
            NSLog("[PendingFlushService] DB no encontrada en \(path)")
            return nil
        }
        return path
    }

    // MARK: - Keychain

    /// flutter_secure_storage v9+ usa el bundle ID como kSecAttrService.
    /// Se intentan variantes por si la versión difiere.
    private static func readTokenFromKeychain() -> String? {
        let serviceNames = [
            Bundle.main.bundleIdentifier ?? "",
            "pe.gob.onp.thaqhiri",
            "FlutterSecureStorage",
        ]
        for service in serviceNames {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: "auth_token",
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let token = String(data: data, encoding: .utf8),
               !token.isEmpty {
                return token
            }
        }
        return nil
    }

    // MARK: - SQLite read

    private static func readPendingLocations(
        db: OpaquePointer,
        uid: String,
        limit: Int
    ) -> [PendingRow] {
        let sql = """
            SELECT id, saaSubject, latitude, longitude, timestamp,
                   accuracy, altitude, speed, heading, batteryLevel, activityType
            FROM pending_locations
            WHERE saaSubject = ?
            ORDER BY timestamp_epoch_ms ASC, id ASC
            LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt = stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (uid as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var rows: [PendingRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let saaSubject = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? uid
            let latitude = sqlite3_column_double(stmt, 2)
            let longitude = sqlite3_column_double(stmt, 3)
            let timestamp = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let accuracy = sqlite3_column_double(stmt, 5)
            let altitude = sqlite3_column_double(stmt, 6)
            let speed = sqlite3_column_double(stmt, 7)
            let heading = sqlite3_column_double(stmt, 8)
            let batteryLevel = sqlite3_column_double(stmt, 9)
            let activityType = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? "unknown"

            rows.append(PendingRow(
                id: id,
                saaSubject: saaSubject,
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp,
                accuracy: accuracy,
                altitude: altitude,
                speed: speed,
                heading: heading,
                batteryLevel: batteryLevel,
                activityType: activityType
            ))
        }
        return rows
    }

    // MARK: - HTTP send

    private static func sendBatch(
        apiBaseUrl: String,
        token: String,
        locations: [PendingRow]
    ) -> Bool {
        PendingLocationApiClient(apiBaseUrl: apiBaseUrl, token: token)
            .send(locations: locations)
    }

    static func makeBatchRequest(
        apiBaseUrl: String,
        token: String,
        locations: [PendingRow],
        timeoutInterval: TimeInterval = 15
    ) -> URLRequest? {
        guard let url = makeBatchUrl(apiBaseUrl: apiBaseUrl) else { return nil }
        guard let body = try? JSONSerialization.data(
            withJSONObject: ["locations": requestPayload(for: locations)]
        ) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    static func makeBatchUrl(apiBaseUrl: String) -> URL? {
        let base = normalizedApiBaseUrl(apiBaseUrl) ?? apiBaseUrl
        return URL(string: "\(base)/locations/batch")
    }

    static func requestPayload(for locations: [PendingRow]) -> [[String: Any]] {
        locations.map {
            [
                "saaSubject": $0.saaSubject,
                "latitude": $0.latitude,
                "longitude": $0.longitude,
                "timestamp": $0.timestamp,
                "accuracy": $0.accuracy,
                "altitude": $0.altitude,
                "speed": $0.speed,
                "heading": $0.heading,
                "batteryLevel": Int($0.batteryLevel),
                "activityType": $0.activityType,
            ]
        }
    }

    // MARK: - Insert (llamado desde LocationTracker para captura en background)

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-12 UTC-5 (Lima)][desc: Inserta punto capturado en background directo al SQLite de Flutter, sin pasar por el engine. Permite que BGAppRefreshTask lo encuentre y lo envíe al backend.][obj: PendingFlushService.insertLocation]
    static func insertLocation(uid: String, point: [String: Any]) {
        guard let dbPath = getOrCreateDatabasePath() else {
            NSLog("[PendingFlushService] insertLocation: no se pudo obtener ruta de DB")
            return
        }
        PendingLocationStore(dbPath: dbPath).insert(uid: uid, point: point)
    }

    static func countPending(uid: String) -> Int {
        guard let dbPath = getDatabasePath() else { return 0 }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = db else { return 0 }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM pending_locations WHERE saaSubject = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt = stmt else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (uid as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: - Database path (con creación si no existe)

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-13 UTC-5 (Lima)][desc: Usa NSDocumentDirectory igual que getDatabasePath() y sqflite. Documents existe siempre; no requiere crear subdirectorio.][obj: PendingFlushService.getOrCreateDatabasePath documentDirectory]
    private static func getOrCreateDatabasePath() -> String? {
        guard let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }

        return documentsDir.appendingPathComponent("tracking_store.db").path
    }

    // MARK: - Schema

    private static func ensureSchema(db: OpaquePointer) {
        let sql = """
            CREATE TABLE IF NOT EXISTS pending_locations (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                saaSubject        TEXT,
                latitude          REAL,
                longitude         REAL,
                timestamp         TEXT,
                timestamp_epoch_ms INTEGER,
                accuracy          REAL,
                altitude          REAL,
                speed             REAL,
                heading           REAL,
                batteryLevel      REAL,
                activityType      TEXT
            )
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - SQLite delete

    private static func deleteLocations(db: OpaquePointer, ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "DELETE FROM pending_locations WHERE id IN (\(placeholders))"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt = stmt else { return }
        defer { sqlite3_finalize(stmt) }
        for (i, id) in ids.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), id)
        }
        sqlite3_step(stmt)
    }
}
