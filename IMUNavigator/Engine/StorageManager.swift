import Foundation
import SQLite3

class StorageManager {
    static let shared = StorageManager()
    
    func saveSession(_ session: TrackingSession, format: StorageFormat) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(session.metadata.startTime.timeIntervalSince1970)
        
        if format == .json {
            let url = docs.appendingPathComponent("INS_\(timestamp).json")
            if let data = try? JSONEncoder().encode(session) { try? data.write(to: url) }
        } else {
            let url = docs.appendingPathComponent("INS_\(timestamp).sqlite")
            var db: OpaquePointer?
            if sqlite3_open(url.path, &db) == SQLITE_OK {
                let createTableStr = "CREATE TABLE IF NOT EXISTS session (id TEXT PRIMARY KEY, metadata TEXT, points BLOB, distance REAL);"
                if sqlite3_exec(db, createTableStr, nil, nil, nil) == SQLITE_OK {
                    let insertQuery = "INSERT INTO session (id, metadata, points, distance) VALUES (?, ?, ?, ?);"
                    var stmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, insertQuery, -1, &stmt, nil) == SQLITE_OK {
                        let metaData = (try? JSONEncoder().encode(session.metadata)) ?? Data()
                        let metaStr = String(data: metaData, encoding: .utf8) ?? ""
                        let ptsData = (try? JSONEncoder().encode(session.points)) ?? Data()
                        
                        sqlite3_bind_text(stmt, 1, (session.id.uuidString as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 2, (metaStr as NSString).utf8String, -1, nil)
                        sqlite3_bind_blob(stmt, 3, (ptsData as NSData).bytes, Int32(ptsData.count), nil)
                        sqlite3_bind_double(stmt, 4, session.totalDistance)
                        sqlite3_step(stmt)
                    }
                    sqlite3_finalize(stmt)
                }
                sqlite3_close(db)
            }
        }
    }
}
