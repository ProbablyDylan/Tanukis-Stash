import SwiftUI

struct PostMetadataBar: View {
    let post: PostContent;
    @Environment(\.navigateToTag) private var navigateToTag;
    @Environment(\.pushDestination) private var pushDestination;

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(post.rating.uppercased()) · #\(post.id)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("\(post.score.total)")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                        Text("\(post.fav_count)")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.fill")
                        Text("\(post.comment_count)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            artistSection
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var artistSection: some View {
        if post.tags.artist.count == 1 {
            let artist = post.tags.artist[0];
            if let navigateToTag {
                Button {
                    navigateToTag(artist);
                } label: {
                    artistLabel(text: artist)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: TagDestination(name: artist)) {
                    artistLabel(text: artist)
                }
            }
        } else if post.tags.artist.count > 1 {
            Menu {
                ForEach(post.tags.artist, id: \.self) { artist in
                    Button(artist) {
                        if let navigateToTag {
                            navigateToTag(artist);
                        } else {
                            pushDestination?(TagDestination(name: artist));
                        }
                    }
                }
            } label: {
                artistLabel(text: post.tags.artist.joined(separator: ", "))
            }
        }
    }

    private func artistLabel(text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "paintpalette.fill")
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(.orange)
    }
}
