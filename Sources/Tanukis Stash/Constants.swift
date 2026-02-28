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
}

let postGridColumns = [
    GridItem(.flexible(minimum: 75)),
    GridItem(.flexible()),
    GridItem(.flexible())
];
