import Foundation

// What a listing already says about a post's collections, before it is opened.
// Pool size and a child's siblings are not in listings, so neither is counted.
extension PostContent {
    var isInPool: Bool { !pools.isEmpty }

    var hasFamily: Bool {
        relationships.parent_id != nil
            || !relationships.children.isEmpty
            || relationships.has_active_children
    }

    // Unused since the grid cell dropped its family-count badge for a single
    // collection icon. Kept for reference.
    // Parent + listed children. `children` includes inactive posts, so this can
    // overstate what the viewer will show.
    // var familyCount: Int {
    //     relationships.children.count + (relationships.parent_id == nil ? 0 : 1)
    // }
}
