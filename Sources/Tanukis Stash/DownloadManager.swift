import Foundation
import Kingfisher
import LinkPresentation
import Photos
import os.log
import SwiftUI
import UIKit

private enum DownloadError: Error {
    case albumCreationFailed
    case assetCreationFailed
    case noVideoURL
}

private actor AlbumManager {
    private var cachedAlbum: PHAssetCollection?;

    func getStashAlbum() async throws -> PHAssetCollection {
        if let album = cachedAlbum { return album; }

        let fetchOptions = PHFetchOptions();
        fetchOptions.predicate = NSPredicate(format: "title = %@", "Stash");
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: fetchOptions);
        if let album = existing.firstObject {
            cachedAlbum = album;
            return album;
        }

        var placeholderID: String?;
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Stash");
            placeholderID = request.placeholderForCreatedAssetCollection.localIdentifier;
        }

        guard let localID = placeholderID else {
            throw DownloadError.albumCreationFailed;
        }

        let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localID], options: nil);
        guard let album = created.firstObject else {
            throw DownloadError.albumCreationFailed;
        }
        cachedAlbum = album;
        return album;
    }
}

private let albumManager = AlbumManager();

func determineAuthorizationStatus() -> PHAuthorizationStatus {
    return PHPhotoLibrary.authorizationStatus(for: .readWrite);
}

func requestAuthorization() async -> PHAuthorizationStatus {
    return await withCheckedContinuation { continuation in
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            continuation.resume(returning: status);
        }
    }
}

func ensureAuthorized() async -> Bool {
    let status = determineAuthorizationStatus();
    switch status {
    case .authorized, .limited:
        return true;
    case .notDetermined:
        let requested = await requestAuthorization();
        return requested == .authorized || requested == .limited;
    default:
        return false;
    }
}

func findOrCreateStashAlbum() async throws -> PHAssetCollection {
    return try await albumManager.getStashAlbum();
}

func saveImageDataToStashAlbum(data: Data, uniformTypeIdentifier: String) async throws {
    let album = try await findOrCreateStashAlbum();
    var placeholderID: String?;
    try await PHPhotoLibrary.shared().performChanges {
        let options = PHAssetResourceCreationOptions();
        options.uniformTypeIdentifier = uniformTypeIdentifier;
        let request = PHAssetCreationRequest.forAsset();
        request.addResource(with: .photo, data: data, options: options);
        guard let placeholder = request.placeholderForCreatedAsset else { return; }
        placeholderID = placeholder.localIdentifier;
        PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray);
    }
    guard placeholderID != nil else {
        throw DownloadError.assetCreationFailed;
    }
}

// The temp copy from `downloadToTemp` already carries a `.mp4` extension, which
// Photos needs to recognise the asset, and it doubles as the share-sheet cache.
func saveVideoToStashAlbum(post: PostContent) async throws {
    let album = try await findOrCreateStashAlbum();
    let fileURL = try await downloadToTemp(post: post);

    var placeholderID: String?;
    try await PHPhotoLibrary.shared().performChanges {
        let options = PHAssetResourceCreationOptions();
        let request = PHAssetCreationRequest.forAsset();
        request.addResource(with: .video, fileURL: fileURL, options: options);
        guard let placeholder = request.placeholderForCreatedAsset else {
            os_log("%{public}s", log: .default, "saveVideoToStashAlbum: placeholderForCreatedAsset was nil");
            return;
        }
        placeholderID = placeholder.localIdentifier;
        PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray);
    }
    guard placeholderID != nil else {
        throw DownloadError.assetCreationFailed;
    }
}

func getVideoLink(post: PostContent) -> URL? {
    let fileType = String(post.file.ext);
    let isWebm = fileType == "webm";
    let isMp4 = fileType == "mp4";

    if isWebm {
        if let alternates = post.sample.alternates, let variants = alternates.variants {
            if let mp4 = variants.mp4, let urlString = mp4.url {
                return URL(string: urlString);
            }
        }
    } else if isMp4 {
        if let urlString = post.file.url {
            return URL(string: urlString);
        }
    }
    return nil;
}

// `downloadToTemp` keeps `<postId>.<ext>` around so a save followed by a share
// (or repeated shares) doesn't re-download. Nothing else prunes tmp, so the
// app sweeps stale media at launch instead of relying on iOS storage pressure.
func sweepStaleMediaTemp(olderThan maxAge: TimeInterval = 24 * 60 * 60) {
    let fm = FileManager.default;
    guard let items = try? fm.contentsOfDirectory(
        at: fm.temporaryDirectory,
        includingPropertiesForKeys: [.contentModificationDateKey]
    ) else { return; }
    let cutoff = Date(timeIntervalSinceNow: -maxAge);
    for url in items {
        let stem = url.deletingPathExtension().lastPathComponent;
        guard !stem.isEmpty, stem.allSatisfy(\.isNumber) else { continue; }
        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              modified < cutoff else { continue; }
        try? fm.removeItem(at: url);
    }
}

func downloadToTemp(post: PostContent) async throws -> URL {
    let ext = post.file.ext;
    let downloadURL: URL;

    if ext == "webm" || ext == "mp4" {
        guard let url = getVideoLink(post: post) else { throw URLError(.fileDoesNotExist); }
        downloadURL = url;
    } else {
        guard let urlString = post.file.url, let url = URL(string: urlString) else {
            throw URLError(.badURL);
        }
        downloadURL = url;
    }

    let destExt = ext == "webm" ? "mp4" : ext;
    let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(post.id).\(destExt)");

    if !FileManager.default.fileExists(atPath: destURL.path) {
        let (downloadedURL, _) = try await URLSession.shared.download(from: downloadURL);
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL);
        }
        try FileManager.default.moveItem(at: downloadedURL, to: destURL);
    }
    return destURL;
}

// Thumbnail for the link preview card. The sample is a still even for video
// posts, and it's usually already in Kingfisher's cache from the grid.
private func fetchLinkPreviewImage(post: PostContent) async -> UIImage? {
    guard let urlString = post.sample.url ?? post.preview.url, let url = URL(string: urlString) else { return nil; }
    do {
        return try await KingfisherManager.shared.retrieveImage(with: url).image;
    } catch {
        os_log("%{public}s", log: .default, "Link preview image unavailable for post \(post.id): \(String(describing: error))");
        return nil;
    }
}

@MainActor
func prepareAndShareContent(
    post: PostContent,
    preparingShare: Binding<Bool>,
    shareItems: Binding<[Any]>,
    showShareSheet: Binding<Bool>,
    displayToastType: Binding<MediaActionState>,
    includeLink: Bool = false
) {
    preparingShare.wrappedValue = true;
    Task {
        defer { preparingShare.wrappedValue = false; }
        do {
            if includeLink {
                let domain = UserDefaults.standard.string(forKey: UDKey.apiSource) ?? "e926.net";
                guard let postURL = URL(string: "https://\(domain)/posts/\(post.id)") else {
                    throw URLError(.badURL);
                }
                let image = await fetchLinkPreviewImage(post: post);
                shareItems.wrappedValue = [PostRichLinkShareItem(postURL: postURL, previewImage: image, postId: post.id)];
            } else {
                let tempURL = try await downloadToTemp(post: post);
                shareItems.wrappedValue = [tempURL];
            }
            showShareSheet.wrappedValue = true;
        } catch {
            os_log("%{public}s", log: .default, "prepareAndShareContent error: \(String(describing: error))");
            displayToastType.wrappedValue = .errorSaveFailed;
        }
    }
}

final class PostRichLinkShareItem: NSObject, UIActivityItemSource {
    let postURL: URL;
    let previewImage: UIImage?;
    let postId: Int;

    init(postURL: URL, previewImage: UIImage?, postId: Int) {
        self.postURL = postURL;
        self.previewImage = previewImage;
        self.postId = postId;
        super.init();
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return postURL;
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return postURL;
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "Post #\(postId)";
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata();
        metadata.originalURL = postURL;
        metadata.url = postURL;
        metadata.title = "Post #\(postId)";
        if let image = previewImage {
            metadata.imageProvider = NSItemProvider(object: image);
            metadata.iconProvider = NSItemProvider(object: image);
        }
        return metadata;
    }
}

@MainActor
func saveFile(post: PostContent, showToast: Binding<MediaActionState>) {
    // Flip to in-progress synchronously so the button reflects the tap at once.
    showToast.wrappedValue = .inProgress;
    Task {
        do {
            guard await ensureAuthorized() else {
                showToast.wrappedValue = .errorPhotosPermissionDenied;
                return;
            }

            let ext = String(post.file.ext);

            switch ext {
            case "gif":
                guard let urlString = post.file.url, let url = URL(string: urlString) else {
                    throw DownloadError.assetCreationFailed;
                }
                let (data, _) = try await URLSession.shared.data(from: url);
                try await saveImageDataToStashAlbum(data: data, uniformTypeIdentifier: "com.compuserve.gif");

            case "webm", "mp4":
                guard getVideoLink(post: post) != nil else {
                    throw DownloadError.noVideoURL;
                }
                try await saveVideoToStashAlbum(post: post);

            default:
                guard let urlString = post.file.url, let url = URL(string: urlString) else {
                    throw DownloadError.assetCreationFailed;
                }
                let (data, _) = try await URLSession.shared.data(from: url);
                try await saveImageDataToStashAlbum(data: data, uniformTypeIdentifier: "public.image");
            }

            showToast.wrappedValue = .success;

        } catch DownloadError.noVideoURL {
            showToast.wrappedValue = .errorNoVideoAvailable;
        } catch {
            os_log("%{public}s", log: .default, "saveFile error: \(String(describing: error))");
            showToast.wrappedValue = .errorSaveFailed;
        }
    }
}
