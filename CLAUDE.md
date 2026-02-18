# Tanuki's Stash — CLAUDE.md

This file provides context for AI assistants working in this repository.

## Project Overview

Tanuki's Stash is a native iOS/iPadOS/macOS client for the e621 and e926 imageboards, built entirely with SwiftUI. It is the world's first e621 client for Apple platforms.

- **Bundle ID**: `dev.jemsoftware.tanukistash`
- **Current Version**: 0.2.0 (build 2)
- **Platforms**: iOS 17+, macOS 14+
- **Swift Tools Version**: 6.0
- **Build Tool**: `xtool` (not Xcode)

## Repository Layout

```
Tanukis-Stash/
├── Package.swift                    # Swift Package Manager manifest
├── xtool.yml                        # xtool build config (bundleID, icon, entitlements, Info.xml)
├── Resources/
│   ├── AppIcon.png                  # Dev app icon
│   ├── AppIconProd.png              # Production app icon
│   ├── App.entitlements             # App sandbox + network + photos entitlements
│   └── Info.xml                     # Info.plist equivalent (XML format for xtool)
└── Sources/Tanukis Stash/
    ├── TanukisStashApp.swift        # @main entry point
    ├── ContentView.swift            # Root view; triggers login and blacklist fetch on init
    ├── SearchView.swift             # Main grid of posts with infinite scroll and search
    ├── PostView.swift               # Post detail view (media + metadata + actions)
    ├── MediaView.swift              # Media dispatcher: routes to ImageView, GIFView, or VideoView
    ├── FullscreenImageViewer.swift  # Fullscreen media viewer sheet (supports zoom)
    ├── ZoomableContainer.swift      # Pinch-to-zoom + double-tap zoom via UIScrollView bridge
    ├── AnimatedGifView.swift        # UIViewRepresentable wrapping SwiftyGif UIImageView
    ├── VideoPlayerController.swift  # UIViewControllerRepresentable wrapping AVPlayerViewController
    ├── SettingsView.swift           # Settings sheet: login, API source, blacklist, AirPlay
    ├── ApiManager.swift             # All API calls, authentication, blacklist logic
    ├── DownloadManager.swift        # Saving media to the Photos library
    ├── Model_Post.swift             # Post-related Decodable structs
    ├── Model_Tag.swift              # TagContent Decodable struct
    └── Model_UserData.swift         # UserData Decodable struct
```

## Build System

This project uses **xtool** instead of Xcode. There is no `.xcodeproj` or `.xcworkspace`.

### xtool.yml

```yaml
version: 1
bundleID: dev.jemsoftware.tanukistash
iconPath: Resources/AppIconProd.png
entitlementsPath: Resources/App.entitlements
infoPath: Resources/Info.xml
```

To build/run, use the `xtool` CLI. The `.gitignore` excludes the `/xtool` binary and build artifacts (`.build/`, `DerivedData/`, `*.ipa`, `/Payload`).

## Dependencies (Package.swift)

| Package | Source | Version | Usage |
|---|---|---|---|
| AlertToast | elai950/AlertToast | ≥ 1.3.9 | Toast notifications in PostView |
| AttributedText | Iaenhaall/AttributedText | ≥ 1.2.0 | Rendering BBCode-parsed post descriptions |
| SwiftyGif | kirualex/SwiftyGif | ≥ 5.4.4 | Animated GIF playback |
| swiftui-image-viewer | Jake-Short/swiftui-image-viewer | ≥ 2.3.1 | ImageViewerRemote (imported but see FullscreenImageViewer) |

`Package.resolved` is gitignored — SPM resolves dependencies fresh on each build.

## Architecture

There is no formal MVVM or similar pattern. The app uses:

- **SwiftUI views** that call global `async` functions directly.
- **Global functions** in `ApiManager.swift` handle all network requests and business logic.
- **`UserDefaults`** for persistent user state (no CoreData or other persistence layer).
- **Swift 6 strict concurrency** — `async/await` is used throughout; `@MainActor` is applied where UI updates cross thread boundaries.

### Data Flow

```
ContentView (init)
  └── login() + fetchBlacklist()  →  UserDefaults
        ↓
SearchView
  ├── fetchRecentPosts()  →  [PostContent]  (API)
  ├── createTagList()     →  [String]       (autocomplete API)
  └── PostPreviewFrame
        └── PostView
              ├── MediaView  →  ImageView / GIFView / VideoView
              ├── RelatedPostsView
              ├── InfoView  →  TagGroup → Tag
              └── ActionBar  →  favoritePost / votePost / saveFile / ShareLink
```

## API Layer (ApiManager.swift)

All requests go through `makeRequest(destination:method:body:contentType:)`.

- **Base URL**: `https://{api_source}{destination}` where `api_source` defaults to `e926.net`
- **User-Agent**: `Tanukis%20Stash/0.0.5%20(by%20JemTanuki%20on%20e621)`
- **Auth**: HTTP Basic (`username:API_KEY` base64-encoded) — only sent when both values are non-empty
- **Logging**: `os_log` via the `dev.jemsoftware.tanukistash` subsystem, `main` category

### Key API Functions

| Function | Method | Endpoint | Purpose |
|---|---|---|---|
| `fetchRecentPosts(_:_:_:)` | GET | `/posts.json` or `/favorites.json` | Paginated post listing |
| `getPost(postId:)` | GET | `/posts/{id}.json` | Single post fetch |
| `fetchTags(_:)` | GET | `/tags/autocomplete.json` | Tag autocomplete |
| `fetchUserData()` | GET | `/users/{username}.json` | User profile + blacklist |
| `fetchBlacklist()` | — | (calls fetchUserData) | Returns `blacklisted_tags` string |
| `favoritePost(postId:)` | POST | `/favorites.json` | Add to favorites |
| `unFavoritePost(postId:)` | DELETE | `/favorites/{id}.json` | Remove from favorites |
| `votePost(postId:value:no_unvote:)` | POST | `/posts/{id}/votes.json` | Upvote/downvote |
| `getVote(postId:)` | GET | `/posts/{id}` | Fetch current vote (HTML scrape) |
| `login()` | — | (calls fetchRecentPosts) | Validates credentials |

### API Source Selection

Users can switch between:
- `e926.net` — SFW (default)
- `e621.net` — NSFW

This is stored in `UserDefaults` under key `api_source`.

## UserDefaults Keys

| Key | Type | Description |
|---|---|---|
| `username` | String | e621/e926 username |
| `API_KEY` | String | e621/e926 API key |
| `AUTHENTICATED` | Bool | Whether login succeeded |
| `USER_BLACKLIST` | String | Newline-separated tag blacklist from user profile |
| `ENABLE_BLACKLIST` | Bool | Whether client-side blacklist filtering is active |
| `ENABLE_AIRPLAY` | Bool | Allow AirPlay for video playback |
| `api_source` | String | Active API domain (`e926.net` or `e621.net`) |
| `USER_ICON` | String | URL string for the user's avatar image |

## Data Models (Decodable Structs)

### Model_Post.swift

- `Posts` — wraps `[PostContent]` (used for list responses)
- `Post` — wraps a single `PostContent` (used for single-post responses)
- `PostContent` — full post object; `is_favorited` is `var` (mutable)
- `File` — url, ext, width, height, size, md5
- `Preview` — url, width, height
- `Sample` — url, has, width, height, alternates
- `Alternates` / `Variants` / `Alternate` — video format variants (used for webm→mp4 fallback)
- `Score` — up, down, total
- `Tags` — general, species, character, copyright, artist, invalid, lore, meta
- `Flags` — pending, flagged, note_locked, status_locked, rating_locked, deleted
- `Relationships` — parent_id, has_children, has_active_children, children
- `VoteResponse` — score, up, down, our_score, success, message, code

### Model_Tag.swift

- `TagContent` — id, name, post_count, category, antecedent_name

### Model_UserData.swift

- `UserData` — full user profile including `blacklisted_tags` (String, newline-separated)

## Blacklist Logic

Blacklist entries are fetched from the authenticated user's e621 profile (`blacklisted_tags`). Each line may contain multiple space-separated tags — a post is blacklisted if **all tags on any single line** are present on the post.

The post's rating is appended as a synthetic tag (`rating:safe`, `rating:questionable`, `rating:explicit`) so rating-based blacklist entries work correctly.

Filtering runs in `fetchRecentPosts` when `ENABLE_BLACKLIST` is true.

## Media Handling

`MediaView` dispatches based on `post.file.ext`:

| Extension | Handler | Notes |
|---|---|---|
| `gif` | `GIFView` → `AnimatedGifView` (SwiftyGif) | Animated, aspect-fit |
| `webm` | `VideoView` → `VideoPlayerController` (AVKit) | Falls back to mp4 variant if available |
| `mp4` | `VideoView` → `VideoPlayerController` (AVKit) | Direct file URL |
| Everything else | `ImageView` (AsyncImage) | Shows blurred preview while loading |

### Video WebM Fallback

`getVideoLink(post:)` in `DownloadManager.swift` checks for an MP4 variant in `post.sample.alternates.variants.mp4` when the file is WebM, since AVKit cannot play WebM natively.

## Download/Save Logic (DownloadManager.swift)

`saveFile(post:showToast:)` saves media to the Photos library:

- **Static images** (non-gif, non-video): downloads `Data`, creates `UIImage`, saves via `UIImageWriteToSavedPhotosAlbum`
- **GIFs**: same as static images (saves first frame as UIImage — loses animation)
- **WebM**: resolves MP4 variant, downloads via `URLSession.downloadTask`, saves as video asset via `PHPhotoLibrary`
- **MP4**: not explicitly handled — falls through to "unsupported" path (known gap)

### Toast State Codes (displayToastType in PostView)

| Value | Meaning |
|---|---|
| `0` | No toast |
| `-1` | Loading / saving in progress |
| `1` | Error / failed to save |
| `2` | Success |
| `3` | Photo library permission not granted |
| `4` | File move error |

## Code Conventions

- **Semicolons**: Used at the end of most statements (non-standard for Swift, but consistent in this codebase — maintain this style when editing existing files).
- **Async/Await**: All network calls use `async/await`. UI-triggering work uses `Task.init { }` inside view modifiers.
- **Logging**: Use `os_log` with `log: .default`. Avoid `print()` (some remain from debugging — do not add more).
- **No state management framework**: State flows via `@State`, `@Binding`, and `@Environment`. No Combine publishers or ObservableObject beyond the stub `SearchableViewModel`.
- **View decomposition**: Sub-views are defined as separate `struct`s within the same file as their parent (e.g., `PostPreviewFrame` in `SearchView.swift`; `ActionBar`, `RelatedPostsView`, `InfoView`, `TagGroup`, `Tag` in `PostView.swift`).
- **Entitlements**: App sandbox is enabled. Required entitlements: network client, network server, photos library read/write, pictures read/write.

## Infinite Scroll

`SearchView` loads 75 posts per page (`var limit = 75`). When the user scrolls to 9 posts before the end of the list (`i == posts.count - 9`), the next page is fetched and appended.

Pull-to-refresh resets to page 1.

## Settings

Settings are presented as a modal sheet from the leading toolbar button in `SearchView` (top-level view only). Closing the settings sheet triggers `updateSettings()`, which re-reads `AUTHENTICATED` from `UserDefaults` and refreshes posts if needed.

The settings picker offers `e926.net` and `e621.net` as API sources. Changing sources persists immediately to `UserDefaults`.

## Known Patterns / Quirks

- `ContentView.init` fires `login()` and `fetchBlacklist()` via `Task.init` — this runs asynchronously before the view is fully rendered.
- `SearchView.updateSettings()` has inverted logic: it toggles `showSettings` rather than reading the new value, which means it effectively runs on the previous state.
- `getVote` scrapes HTML rather than using a JSON endpoint — this is intentional as the vote state is not returned in standard post JSON.
- `FullscreenImageViewer` wraps `MediaView` in `ZoomableContainer`, which uses a `UIScrollView` bridge for pinch-to-zoom (SwiftUI's native zoom gestures were insufficient).
- The `swiftui-image-viewer` dependency is declared in `Package.swift` but `FullscreenImageViewer` uses the custom `ZoomableContainer` instead.
- `descParser` converts a limited subset of BBCode (`[b]`, `[u]`, `[quote]`) to HTML for rendering via `AttributedText`.

## App Entitlements

- `com.apple.security.app-sandbox` — sandboxed
- `com.apple.security.network.client` — outbound network
- `com.apple.security.network.server` — inbound network
- `com.apple.security.assets.pictures.read-write` — picture assets
- `com.apple.security.personal-information.photos-library` — Photos library access
