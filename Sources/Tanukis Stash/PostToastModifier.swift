import SwiftUI
import AlertToast

enum MediaActionState: Equatable {
    case idle
    case inProgress
    case success
    case errorSaveFailed
    case errorPhotosPermissionDenied
    case errorMoveFailed
    case errorNoVideoAvailable

    var isError: Bool {
        switch self {
        case .errorSaveFailed, .errorPhotosPermissionDenied,
             .errorMoveFailed, .errorNoVideoAvailable:
            return true;
        default:
            return false;
        }
    }
}

struct PostToastModifier: ViewModifier {
    @Binding var displayToastType: MediaActionState;
    @State private var clearTask: Task<Void, Never>?;

    func body(content: Content) -> some View {
        content
            .toast(isPresenting: Binding<Bool>(
                get: { displayToastType.isError },
                set: { _ in }
            )) {
                toastForType()
            }
            .onChange(of: displayToastType) { _, newValue in
                if newValue != .idle { clearToast(); }
            }
    }

    private func clearToast() {
        clearTask?.cancel();
        let current = displayToastType;
        clearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2));
            if !Task.isCancelled && current == displayToastType {
                displayToastType = .idle;
            }
        };
    }

    private func toastForType() -> AlertToast {
        switch displayToastType {
        case .errorSaveFailed:
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Failed to save");
        case .errorPhotosPermissionDenied:
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Photos permission required");
        case .errorMoveFailed:
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Failed to move file");
        case .errorNoVideoAvailable:
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "No video available");
        case .idle, .inProgress, .success:
            // Never shown — isPresenting is false for these states.
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Unknown error");
        }
    }
}

extension View {
    func postToast(displayToastType: Binding<MediaActionState>) -> some View {
        modifier(PostToastModifier(displayToastType: displayToastType));
    }
}
