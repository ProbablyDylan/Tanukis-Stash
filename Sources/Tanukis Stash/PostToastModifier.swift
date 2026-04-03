import SwiftUI
import AlertToast

struct PostToastModifier: ViewModifier {
    @Binding var displayToastType: Int;
    @State private var clearTask: Task<Void, Never>?;

    func body(content: Content) -> some View {
        content
            .toast(isPresenting: Binding<Bool>(
                get: { [1, 3, 4, 5].contains(displayToastType) },
                set: { _ in }
            )) {
                toastForType()
            }
            .onChange(of: displayToastType) { _, newValue in
                if newValue != 0 { clearToast(); }
            }
    }

    private func clearToast() {
        clearTask?.cancel();
        let current = displayToastType;
        clearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2));
            if !Task.isCancelled && current == displayToastType {
                displayToastType = 0;
            }
        };
    }

    private func toastForType() -> AlertToast {
        switch displayToastType {
        case 1:
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Failed to save");
        case 3:
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Photos permission required");
        case 4:
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Failed to move file");
        case 5:
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "No video available");
        default:
            return AlertToast(displayMode: .hud, type: .error(Color.red), title: "Unknown error");
        }
    }
}

extension View {
    func postToast(displayToastType: Binding<Int>) -> some View {
        modifier(PostToastModifier(displayToastType: displayToastType));
    }
}
