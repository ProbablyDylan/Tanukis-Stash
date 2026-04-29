import Foundation
import Kingfisher

enum ImageCacheConfig {
    static var sizeLimit: ImageCacheSizeLimit {
        let raw = UserDefaults.standard.object(forKey: UDKey.imageCacheSizeLimit) as? Int;
        return ImageCacheSizeLimit(rawValue: raw ?? ImageCacheSizeLimit.unlimited.rawValue) ?? .unlimited;
    }

    static var expiration: ImageCacheExpiration {
        let raw = UserDefaults.standard.object(forKey: UDKey.imageCacheExpirationDays) as? Int;
        return ImageCacheExpiration(rawValue: raw ?? ImageCacheExpiration.sevenDays.rawValue) ?? .sevenDays;
    }

    static func apply() {
        let cache = KingfisherManager.shared.cache;
        cache.diskStorage.config.sizeLimit = sizeLimit.bytes;
        switch expiration {
        case .never:
            cache.diskStorage.config.expiration = .never;
        default:
            cache.diskStorage.config.expiration = .seconds(TimeInterval(expiration.rawValue) * 86400);
        }
    }

    static func cleanExpired() {
        KingfisherManager.shared.cache.cleanExpiredDiskCache();
    }

    static func currentDiskSize() async -> UInt {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                switch result {
                case .success(let size): continuation.resume(returning: size);
                case .failure: continuation.resume(returning: 0);
                }
            }
        }
    }

    static func formatBytes(_ bytes: UInt) -> String {
        let formatter = ByteCountFormatter();
        formatter.countStyle = .file;
        return formatter.string(fromByteCount: Int64(bytes));
    }
}
