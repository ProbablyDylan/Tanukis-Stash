//
//  TagModel.swift
//  Tanuki
//
//  Created by Jemma Poffinbarger on 7/15/22.
//

import SwiftUI

struct TagSuggestion: Hashable {
    let name: String;
    let category: Int;
}

struct TagContent: Decodable {
    let id: Int;
    let name: String;
    let post_count: Int;
    let category: Int;
    let antecedent_name: String?;
}

struct WikiPage: Decodable {
    let id: Int;
    let title: String;
    let body: String;
    let other_names: [String]?;
    let is_deleted: Bool?;
}

struct TagDetail: Decodable {
    let id: Int;
    let name: String;
    let post_count: Int;
    let related_tags: String?;
    let category: Int;
}

struct TagAlias: Decodable {
    let id: Int;
    let antecedent_name: String;
    let consequent_name: String;
    let status: String;
}
