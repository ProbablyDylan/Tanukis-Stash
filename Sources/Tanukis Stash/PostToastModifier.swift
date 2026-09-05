import SwiftUI
import AlertToast

enum MediaActionState: Equatable {
    case idle
    case inProgress
    case success
    case errorSaveFailed
    case errorPhotosPermissionDenied
    case errorNoVideoAvailable

    var isError: Bool {
        switch self {
        case .errorSaveFailed, .errorPhotosPermissionDenied, .errorNoVideoAvailable:
            return true;
        default:
            return false;
        }
    }

    // Terminal states clear themselves after a moment; `.inProgress` must
    // persist until the operation actually finishes.
    var isTransient: Bool {
        return self == .success || isError;
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
                clearTask?.cancel();
                if newValue.isTransient { scheduleClear(); }
            }
    }

    private func scheduleClear() {
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

// Label for the save/share toolbar menu. Both the icon and the spinner stay in
// the hierarchy so the button never changes size and the symbol can animate
// share → checkmark → share with a single `.replace` content transition; the
// spinner just fades over the top while work is in flight.
struct MediaActionMenuLabel: View {
    let state: MediaActionState;
    let preparingShare: Bool;

    private var busy: Bool { state == .inProgress || preparingShare; }
    private var succeeded: Bool { state == .success; }

    var body: some View {
        ZStack {
            Image(systemName: succeeded ? "checkmark.circle.fill" : "square.and.arrow.up")
                .imageScale(.large)
                .foregroundStyle(succeeded ? Color.green : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .opacity(busy ? 0 : 1)
            ProgressView()
                .opacity(busy ? 1 : 0)
        }
        .animation(.smooth, value: busy)
        .animation(.smooth, value: succeeded)
    }
}
