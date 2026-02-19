import Foundation
import Photos
import os.log
import SwiftUI

private enum DownloadError: Error {
    case albumCreationFailed
    case assetCreationFailed
}

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
    let fetchOptions = PHFetchOptions();
    fetchOptions.predicate = NSPredicate(format: "title = %@", "Stash");
    let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: fetchOptions);
    if let album = existing.firstObject {
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
    return album;
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

func saveVideoToStashAlbum(url: URL) async throws {
    let album = try await findOrCreateStashAlbum();

    let (tempURL, _) = try await URLSession.shared.download(from: url);

    guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        throw DownloadError.assetCreationFailed;
    }
    let destinationURL = documentsDir.appendingPathComponent(url.lastPathComponent);

    if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL);
    }
    try FileManager.default.moveItem(at: tempURL, to: destinationURL);
    defer { try? FileManager.default.removeItem(at: destinationURL); }

    var placeholderID: String?;
    try await PHPhotoLibrary.shared().performChanges {
        guard let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: destinationURL) else { return; }
        guard let placeholder = request.placeholderForCreatedAsset else { return; }
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

func saveFile(post: PostContent, showToast: Binding<Int>) {
    Task {
        do {
            guard await ensureAuthorized() else {
                await MainActor.run { showToast.wrappedValue = 3; }
                return;
            }

            await MainActor.run { showToast.wrappedValue = -1; }

            let ext = String(post.file.ext);

            switch ext {
            case "gif":
                guard let urlString = post.file.url, let url = URL(string: urlString) else {
                    throw DownloadError.assetCreationFailed;
                }
                let (data, _) = try await URLSession.shared.data(from: url);
                try await saveImageDataToStashAlbum(data: data, uniformTypeIdentifier: "com.compuserve.gif");

            case "webm", "mp4":
                guard let videoURL = getVideoLink(post: post) else {
                    throw DownloadError.assetCreationFailed;
                }
                try await saveVideoToStashAlbum(url: videoURL);

            default:
                guard let urlString = post.file.url, let url = URL(string: urlString) else {
                    throw DownloadError.assetCreationFailed;
                }
                let (data, _) = try await URLSession.shared.data(from: url);
                try await saveImageDataToStashAlbum(data: data, uniformTypeIdentifier: "public.image");
            }

            await MainActor.run { showToast.wrappedValue = 2; }

        } catch {
            os_log("%{public}s", log: .default, "saveFile error: \(String(describing: error))");
            await MainActor.run { showToast.wrappedValue = 1; }
        }
    }
}
