import SwiftUI
import AlertToast

struct PostToastModifier: ViewModifier {
    @Binding var displayToastType: Int;

    func body(content: Content) -> some View {
        content
            .toast(isPresenting: Binding<Bool>(
                get: { [1, 3, 4, 5].contains(displayToastType) },
                set: { _ in }
            )) {
                toastForType()
            }
            .onChange(of: displayToastType) { _, newValue in
                if newValue == 2 { clearToast(); }
            }
    }

    private func clearToast() {
        let current = displayToastType;
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if current == displayToastType {
                displayToastType = 0;
            }
        }
    }

    private func toastForType() -> AlertToast {
        clearToast();
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
