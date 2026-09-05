import SwiftUI

// The API returns posts in the v2 format (`v2=true&mode=extended`): no
// `posts` / `post` envelope, related fields grouped into `files` / `stats` /
// `flags` / `has` / `relationships`. The wire shape is decoded by the private
// `PostWire` structs below and mapped onto the flatter model the views use.
// See https://e621.net/forum_topics/63849

// Equatable/Hashable are auto-synthesized from every stored property below —
// do NOT add a custom id-only `==`/`hash(into:)`. @State (and @State arrays)
// skip publishing a change when the new value is `==` the old one; an
// id-only `==` makes a vote or favorite that only changes score/fav_count
// look like "no change" and the view silently never redraws. ForEach/lookup
// code that wants identity-only comparison already uses an explicit `.id`
// predicate or `id:` keypath — nothing relies on `==` being id-only.
struct PostContent: Decodable, Hashable {
    let id: Int;
    let created_at: String;
    let updated_at: String?;
    let file: File;
    let preview: Preview;
    let sample: Sample;
    var score: Score;
    let tags: Tags;
    let locked_tags: [String];
    let change_seq: Int;
    let flags: Flags;
    let rating: String;
    var fav_count: Int;
    let sources: [String];
    let pools: [Int];
    let relationships: Relationships;
    let approver_id: Int?;
    let uploader_id: Int;
    let description: String;
    let comment_count: Int;
    var is_favorited: Bool;
    var vote: Int;
    let has_notes: Bool;
    let duration: Float?;

    init(from decoder: any Decoder) throws {
        let wire = try PostWire(from: decoder);

        id = wire.id;
        created_at = wire.created_at;
        updated_at = wire.updated_at;
        change_seq = wire.change_seq;

        file = File(
            width: wire.files.original.width,
            height: wire.files.original.height,
            ext: wire.files.meta.ext,
            size: wire.files.meta.size,
            md5: wire.files.meta.md5,
            url: wire.files.original.url
        );
        preview = Preview(
            width: wire.files.preview.width,
            height: wire.files.preview.height,
            url: wire.files.preview.jpg
        );
        // `files.sample` falls back to the original file when no sample was
        // generated, so `has.sample` is the only reliable "real sample" signal.
        sample = Sample(
            has: wire.has.sample,
            height: wire.files.sample.height,
            width: wire.files.sample.width,
            url: wire.files.sample.jpg,
            alternates: wire.files.videoSamples.map {
                Alternates(original: $0.original, variants: $0.variants)
            }
        );
        duration = wire.files.meta.duration;

        score = wire.stats.score;
        fav_count = wire.stats.fav_count;
        is_favorited = wire.stats.is_favorited;
        vote = wire.stats.vote;
        comment_count = wire.stats.comment_count;

        flags = wire.flags;
        has_notes = wire.has.notes;
        relationships = Relationships(
            parent_id: wire.relationships.parent_id,
            has_children: wire.has.children,
            has_active_children: wire.has.active_children,
            children: wire.relationships.children
        );

        uploader_id = wire.uploader_id;
        approver_id = wire.approver_id;
        pools = wire.pools;
        rating = wire.rating;
        locked_tags = wire.locked_tags;
        sources = wire.sources;
        description = wire.description;
        tags = wire.tags;
    }
}

// MARK: - v2 wire format

private struct PostWire: Decodable {
    let id: Int;
    let created_at: String;
    let updated_at: String?;
    let change_seq: Int;
    let files: Files;
    let uploader_id: Int;
    let approver_id: Int?;
    let stats: Stats;
    let flags: Flags;
    let has: Has;
    let relationships: RelationshipsWire;
    let pools: [Int];
    let rating: String;
    let locked_tags: [String];
    let sources: [String];
    let description: String;
    let tags: Tags;

    struct Files: Decodable {
        let meta: Meta;
        let original: Original;
        let preview: Scaled;
        let sample: Scaled;
        let videoSamples: VideoSamples?;

        // Staff floated renaming `video` to `video_samples`; accept either.
        enum CodingKeys: String, CodingKey {
            case meta, original, preview, sample, video, video_samples;
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self);
            meta = try container.decode(Meta.self, forKey: .meta);
            original = try container.decode(Original.self, forKey: .original);
            preview = try container.decode(Scaled.self, forKey: .preview);
            sample = try container.decode(Scaled.self, forKey: .sample);
            videoSamples = try container.decodeIfPresent(VideoSamples.self, forKey: .video)
                ?? container.decodeIfPresent(VideoSamples.self, forKey: .video_samples);
        }
    }

    struct Meta: Decodable {
        let md5: String;
        let ext: String;
        let size: Int;
        let duration: Float?;
        let has_sample: Bool;
    }

    struct Original: Decodable {
        let width: Int;
        let height: Int;
        let url: String?;
    }

    struct Scaled: Decodable {
        let width: Int;
        let height: Int;
        let jpg: String?;
        let webp: String?;
    }

    struct VideoSamples: Decodable {
        let original: Alternate?;
        let variants: Variants?;
    }

    struct Stats: Decodable {
        let score: Score;
        let fav_count: Int;
        let is_favorited: Bool;
        let vote: Int;
        let comment_count: Int;
    }

    struct Has: Decodable {
        let parent: Bool;
        let children: Bool;
        let active_children: Bool;
        let notes: Bool;
        let sample: Bool;
    }

    struct RelationshipsWire: Decodable {
        let parent_id: Int?;
        let children: [Int];
    }
}

struct File: Decodable, Hashable {
    let width: Int;
    let height: Int;
    let ext: String;
    let size: Int;
    let md5: String;
    let url: String?;
}

struct Preview: Decodable, Hashable {
    let width: Int;
    let height: Int;
    let url: String?;
}

struct Sample: Decodable, Hashable {
    let has: Bool;
    let height: Int;
    let width: Int;
    let url: String?;
    let alternates: Alternates?;
}

struct Alternates: Decodable, Hashable {
    let original: Alternate?
    let variants: Variants?
}

struct Variants: Decodable, Hashable {
    let webm: Alternate?;
    let mp4: Alternate?;
}

struct Alternate: Decodable, Hashable {
    let height: Int?;
    let width: Int?;
    let url: String?;
}

struct Score: Decodable, Hashable {
    let up: Int;
    let down: Int;
    let total: Int;
}

// The server builds these keys from its own category table, so the categories
// are kept as a dictionary rather than fixed fields — a new category upstream
// still reaches `all` (and therefore the blacklist) without a client change.
struct Tags: Decodable, Hashable {
    let byCategory: [String: [String]];

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer();
        byCategory = try container.decode([String: [String]].self);
    }

    private func tags(_ category: String) -> [String] {
        return byCategory[category] ?? [];
    }

    var general: [String] { tags("general") };
    var species: [String] { tags("species") };
    var character: [String] { tags("character") };
    var copyright: [String] { tags("copyright") };
    var artist: [String] { tags("artist") };
    var contributor: [String] { tags("contributor") };
    var invalid: [String] { tags("invalid") };
    var lore: [String] { tags("lore") };
    var meta: [String] { tags("meta") };

    var all: [String] { byCategory.values.flatMap { $0 } };
}

struct Flags: Decodable, Hashable {
   let pending: Bool;
   let flagged: Bool;
   let note_locked: Bool;
   let status_locked: Bool;
   let rating_locked: Bool;
   let deleted: Bool;
}

struct Relationships: Decodable, Hashable {
    let parent_id: Int?;
    let has_children: Bool;
    let has_active_children: Bool;
    let children: [Int];
}

struct VoteResponse: Decodable, Hashable {
    let score: Int?;
    let up: Int?;
    let down: Int?;
    let our_score: Int?;
    let success: Bool?;
    let message: String?;
    let code: String?;
}

struct PoolContent: Decodable {
    let id: Int;
    let name: String;
    let description: String;
    let category: String;
    let post_ids: [Int];
    let post_count: Int;
    let creator_name: String;
    let created_at: String;
    let updated_at: String?;
    let is_active: Bool;
    let is_deleted: Bool;
}
