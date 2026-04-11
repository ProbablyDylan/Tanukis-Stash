import SwiftUI

struct PostMetadataBar: View {
    let post: PostContent;
    @Binding var selectedArtist: String?;

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
            NavigationLink(destination: TagView(tagName: post.tags.artist[0])) {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                    Text(post.tags.artist[0])
                }
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        } else if post.tags.artist.count > 1 {
            Menu {
                ForEach(post.tags.artist, id: \.self) { artist in
                    Button(artist) {
                        selectedArtist = artist;
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                    Text(post.tags.artist.joined(separator: ", "))
                }
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
    }
}
