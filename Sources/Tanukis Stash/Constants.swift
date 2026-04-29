//
//  Constants.swift
//  Tanuki
//

import SwiftUI

enum UDKey {
    static let username = "username";
    static let apiKey = "API_KEY";
    static let apiSource = "api_source";
    static let authenticated = "AUTHENTICATED";
    static let userBlacklist = "USER_BLACKLIST";
    static let enableBlacklist = "ENABLE_BLACKLIST";
    static let enableAirplay = "ENABLE_AIRPLAY";
    static let userIcon = "USER_ICON";
    static let tagCacheLastSync = "TAG_CACHE_LAST_SYNC";
    static let imageCacheSizeLimit = "IMAGE_CACHE_SIZE_LIMIT";
    static let imageCacheExpirationDays = "IMAGE_CACHE_EXPIRATION_DAYS";
}

enum ImageCacheSizeLimit: Int, CaseIterable, Identifiable {
    case unlimited = 0
    case mb500 = 500
    case gb1 = 1000
    case gb2 = 2000
    case gb5 = 5000

    var id: Int { rawValue; }

    var label: String {
        switch self {
        case .unlimited: return "Unlimited";
        case .mb500: return "500 MB";
        case .gb1: return "1 GB";
        case .gb2: return "2 GB";
        case .gb5: return "5 GB";
        }
    }

    /// Bytes for Kingfisher (UInt). 0 means no limit.
    var bytes: UInt {
        UInt(rawValue) * 1024 * 1024;
    }
}

enum ImageCacheExpiration: Int, CaseIterable, Identifiable {
    case oneDay = 1
    case threeDays = 3
    case sevenDays = 7
    case thirtyDays = 30
    case never = -1

    var id: Int { rawValue; }

    var label: String {
        switch self {
        case .oneDay: return "1 Day";
        case .threeDays: return "3 Days";
        case .sevenDays: return "7 Days";
        case .thirtyDays: return "30 Days";
        case .never: return "Never";
        }
    }
}

let postGridColumns = [
    GridItem(.flexible(minimum: 75)),
    GridItem(.flexible()),
    GridItem(.flexible())
];
