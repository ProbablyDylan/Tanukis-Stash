//
//  Model_Comment.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 2/18/26.
//

import SwiftUI;

struct CommentContent: Decodable, Identifiable {
    let id: Int;
    let post_id: Int;
    let creator_id: Int;
    let updater_id: Int;
    let creator_name: String;
    let updater_name: String;
    let body: String;
    let score: Int;
    let created_at: String;
    let updated_at: String;
    let is_hidden: Bool;
    let is_sticky: Bool;
    let do_not_bump_post: Bool;
    let warning_type: String?;
    let warning_user_id: Int?;
}
