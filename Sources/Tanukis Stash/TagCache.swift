//
//  TagCache.swift
//  Tanuki
//

import Foundation
import GRDB
import os.log
import Compression

struct CachedTag: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tags";
    let id: Int;
    let name: String;
    let postCount: Int;
    let category: Int;
}

private let _tagDBLock = NSLock();
private nonisolated(unsafe) var _tagDB: DatabaseQueue?;

func openTagDatabase() throws -> DatabaseQueue {
    _tagDBLock.lock();
    defer { _tagDBLock.unlock(); }
    if let db = _tagDB { return db; }
    guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        throw CocoaError(.fileNoSuchFile);
    }
    try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true);
    let dbPath = appSupport.appendingPathComponent("tags.sqlite").path;
    let db = try DatabaseQueue(path: dbPath);
    try db.write { db in
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS tags (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                postCount INTEGER NOT NULL,
                category INTEGER NOT NULL
            )
        """);
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name)");
    }
    _tagDB = db;
    return db;
}

func isTagCachePopulated() -> Bool {
    guard let db = try? openTagDatabase() else { return false; }
    let count = try? db.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags")
    }
    return (count ?? 0) > 0;
}

func searchLocalTags(_ prefix: String, limit: Int = 10) -> [CachedTag] {
    guard let db = try? openTagDatabase() else { return []; }
    let pattern = prefix.lowercased() + "%";
    do {
        return try db.read { db in
            try CachedTag.fetchAll(db, sql: """
                SELECT * FROM tags WHERE name LIKE ? ORDER BY postCount DESC LIMIT ?
            """, arguments: [pattern, limit]);
        }
    } catch {
        os_log("Tag cache search error: %{public}s", log: .default, error.localizedDescription);
        return [];
    }
}

func tagCacheSyncIfNeeded() async {
    let lastSync = UserDefaults.standard.double(forKey: UDKey.tagCacheLastSync);
    let now = Date().timeIntervalSince1970;
    if now - lastSync < 86400 && isTagCachePopulated() { return; }

    let formatter = DateFormatter();
    formatter.dateFormat = "yyyy-MM-dd";
    formatter.timeZone = TimeZone(identifier: "America/New_York");
    let today = formatter.string(from: Date());
    let yesterday = formatter.string(from: Date(timeIntervalSinceNow: -86400));

    var csvData: Data?;
    for dateStr in [today, yesterday] {
        let domain = UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net";
        let urlStr = "https://\(domain)/db_export/tags-\(dateStr).csv.gz";
        guard let url = URL(string: urlStr) else { continue; }
        var request = URLRequest(url: url);
        request.addValue(userAgent.removingPercentEncoding ?? userAgent, forHTTPHeaderField: "User-Agent");
        do {
            let (data, response) = try await URLSession.shared.data(for: request);
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                csvData = decompressGzip(data);
                if csvData != nil {
                    os_log("Downloaded tag export for %{public}s (%{public}d bytes compressed)", log: .default, dateStr, data.count);
                    break;
                }
            }
        } catch {
            os_log("Tag export download failed for %{public}s: %{public}s", log: .default, dateStr, error.localizedDescription);
        }
    }

    guard let csv = csvData, let csvString = String(data: csv, encoding: .utf8) else {
        os_log("Failed to download or decompress tag export", log: .default);
        return;
    }

    do {
        let db = try openTagDatabase();
        let lines = csvString.split(separator: "\n", omittingEmptySubsequences: true);

        try await db.write { db in
            try db.execute(sql: "DELETE FROM tags");
            // Skip header line
            for line in lines.dropFirst() {
                let cols = line.split(separator: ",", maxSplits: 4, omittingEmptySubsequences: false);
                guard cols.count >= 4 else { continue; }
                let id = Int(cols[0]) ?? 0;
                let name = String(cols[1]);
                let category = Int(cols[2]) ?? 0;
                let postCount = Int(cols[3]) ?? 0;
                try db.execute(
                    sql: "INSERT OR REPLACE INTO tags (id, name, postCount, category) VALUES (?, ?, ?, ?)",
                    arguments: [id, name, postCount, category]
                );
            }
        }

        UserDefaults.standard.set(now, forKey: UDKey.tagCacheLastSync);
        os_log("Tag cache synced with %{public}d tags", log: .default, lines.count - 1);
    } catch {
        os_log("Tag cache sync failed: %{public}s", log: .default, error.localizedDescription);
    }
}

func decompressGzip(_ data: Data) -> Data? {
    guard data.count > 18 else { return nil; }
    guard data[0] == 0x1f && data[1] == 0x8b else { return nil; }

    // Parse gzip header to find the start of the raw deflate stream
    var offset = 10;
    let flags = data[3];
    if flags & 0x04 != 0 {
        guard offset + 2 <= data.count else { return nil; }
        let extraLen = Int(data[offset]) | (Int(data[offset + 1]) << 8);
        offset += 2 + extraLen;
    }
    if flags & 0x08 != 0 {
        while offset < data.count && data[offset] != 0 { offset += 1; }
        offset += 1;
    }
    if flags & 0x10 != 0 {
        while offset < data.count && data[offset] != 0 { offset += 1; }
        offset += 1;
    }
    if flags & 0x02 != 0 { offset += 2; }
    guard offset < data.count - 8 else { return nil; }

    let deflateData = data[offset ..< (data.count - 8)];

    // Use streaming decompression to handle arbitrarily large output
    let initBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1);
    defer { initBuf.deallocate(); }
    var stream = compression_stream(dst_ptr: initBuf, dst_size: 0, src_ptr: initBuf, src_size: 0, state: nil);
    guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
        return nil;
    }
    defer { compression_stream_destroy(&stream); }

    let bufferSize = 65536;
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize);
    defer { buffer.deallocate(); }

    var result = Data();
    deflateData.withUnsafeBytes { rawBuffer in
        let sourcePointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress!;
        stream.src_ptr = sourcePointer;
        stream.src_size = deflateData.count;

        while true {
            stream.dst_ptr = buffer;
            stream.dst_size = bufferSize;
            let status = compression_stream_process(&stream, 0);
            let written = bufferSize - stream.dst_size;
            if written > 0 { result.append(buffer, count: written); }
            if status == COMPRESSION_STATUS_END { break; }
            if status == COMPRESSION_STATUS_ERROR { result = Data(); break; }
        }
    }

    return result.isEmpty ? nil : result;
}
