## v0.5 — "The Fork" (2025-02-25)

The first release under ProbablyDylan's fork. Picks up from the original CaramelKat/Tanukis-Stash codebase (last upstream feature: collapsible tag categories and vote persistence) and applies a ground-up modernization.

### Build System & Platform

- Migrated from Xcode project to **xtool** — no more `.xcodeproj`; builds via Swift Package Manager + `xtool.yml`
- Jumped to **Swift 6** with strict concurrency (`async/await` throughout, `@MainActor` where needed)
- Bumped deployment target to **iOS 26 / macOS 26** with Swift tools version 6.2
- Modernized navigation: replaced deprecated `NavigationView` / `presentationMode` with `NavigationStack` and `dismiss` environment action
- Cleared iOS-incompatible macOS sandbox entitlements that caused device signature verification failures (macOS builds temporarily disabled)

### Rebranding

- Renamed app from **Tanuki's Stash** to **Tanuki** across package manifest, source files, and UI
- Replaced GitHub link in settings with development Telegram channel

### New Features

- **Comments** — Read-only comments section on PostView; lazily fetched, collapsible, with quote block formatting (left accent bar, italic attribution) and oldest-first sort order
- **Pool browsing** — Dedicated PoolView with pool name as title, oldest-first post ordering, infinite scroll, and pull-to-refresh; pool cards show real thumbnails fetched in parallel
- **In-app blacklist management** — Interactive blacklist editor with swipe-to-delete, tag autocomplete, and direct save to e621 API via `PATCH /users/{id}.json`; replaces the old read-only text field
- **Kingfisher image caching** — Replaced `AsyncImage` with `KFImage` for in-memory + disk thumbnail caching; `ImagePrefetcher` pre-warms the cache on each page load, eliminating thumbnail pop-in
- **Share menu** — Consolidated save and share into a single menu button offering Save to Photos, Share Link, and Share Content (downloads full media with webm-to-mp4 fallback, presents native share sheet with temp file caching)
- **Search dismiss behavior** — Cancel/X on the search bar clears results and reloads recent posts; navigation title dynamically shows "Recent" or "Results"

### UI Overhaul

- **iOS 26 liquid glass bottom bar** — Moved settings, search, and favorites from the navigation bar into a bottom bar with `DefaultToolbarItem` and `ToolbarSpacer`
- **Native bottom toolbar for PostView** — Replaced custom `ActionBar` with SwiftUI toolbar using `bottomBar` placement
- **SF Symbols** — Replaced emoji (arrows, hearts) with SF Symbols throughout post stats and UI controls
- **PostView info card** — Artist name moved to right side with palette icon; tappable (direct `NavigationLink` for single artist, `Menu` for multiple); stats (votes, favorites, comments) on the left; bumped text from `.caption` to `.footnote`
- **Related posts as thumbnail cards** — Parent/child posts render as 80x80 thumbnail cards in a horizontal scroll row instead of plain text links
- **Button animations** — Download button pulses while saving, transitions to green checkmark on success; favorite and vote buttons bounce on state change; toasts now only appear for errors
- **Settings polish** — Replaced "Dismiss" text button with xmark icon; cleaned up settings layout
- **PostView section reorder** — Description (now collapsible) → Comments → Tags; removed redundant Artist tag group
- **Comment count** added to both PostView info card and SearchView grid overlay

### Downloads & Media

- **Rewrote DownloadManager** — Fixed MP4 files falling into unsupported else-branch; fixed GIFs saving as static single frame (now saved as animated data with `com.compuserve.gif` UTI)
- **Stash album** — All media saves go to a dedicated "Stash" album in Photos, created automatically if absent
- **Video save reliability** — Switched to `PHAssetCreationRequest.forAsset()` + `addResource(with:fileURL:)` pattern; ensures `.mp4` extension for Photos recognition; distinct error toasts for move errors vs. missing video URL
- Upgraded Photos authorization to `.readWrite` for album creation

### Performance

- **Scroll performance** — `ForEach` now diffs by post ID (Int) instead of hashing full `PostContent` structs; prefetches only newly fetched URLs instead of re-queuing entire array on each page append
- **Blacklist parsing** — Parse blacklist string once before the filter loop instead of once per post; build tag `Set` once per post instead of once per blacklist line
- **View properties** — Changed `@State` to `let` across all passed-in view properties that are never locally mutated (PostView, RelatedPostsView, InfoView, CommentsView, TagGroup, Tag, CommentRow)
- **Comment parsing** — Moved `CommentBody.segments` from a recomputed property to a stored `let` initialized in `init`
- Removed redundant `Task.init` wrapping in `onChange(of: search)`; removed unnecessary `async` from inlined `processTags`

### Bug Fixes

- Fixed blocklist not being saved correctly
- Fixed iOS 17 build warnings
- Made `UserData` fields optional to prevent JSON decode failure when e621 returns null for fields like `avatar_id` or `last_forum_read_at`
- Filter out deleted posts (nil preview URLs) from search grid to prevent empty squares
- Fixed broken parent post navigation in RelatedPostsView
- Fixed vote icons (replaced `arrowtriangle` with `arrowshape` variants)

### Under the Hood

- Refactored `ApiManager` — centralized request handling, auth, and logging
- Updated post models to prevent searches from failing to load
- Added `Model_UserData.swift` for user profile data
- User icon displayed in settings when authenticated
- Authentication flow: login with API key, blacklist fetch on init
