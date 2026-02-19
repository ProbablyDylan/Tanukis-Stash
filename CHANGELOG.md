# Changelog

## Unreleased

### 2026-02-18 (later)

- Fixed MP4 posts always failing to save (were falling into unsupported else-branch)
- Fixed GIFs saving as a static single frame — now saved as animated GIF using raw data + `com.compuserve.gif` UTI
- All media saves now go to a dedicated "Stash" album in Photos, created automatically if absent
- Upgraded Photos authorization to read/write (required for album creation)

### 2026-02-18

- Reorganized PostView info card: artist name moved to right side with palette icon, stats (votes, favorites, comments) on the left
- Artist name in info card is now tappable — opens a search for that artist (menu for multiple artists)
- Added comment count to the PostView info card and SearchView grid overlay
- Reordered PostView sections to: Description → Comments → Tags
- Description is now a collapsible section (expanded by default)
- Removed redundant Artist section from the tags list
- SearchView grid overlay stats are now center-aligned and slightly smaller to prevent wrapping
