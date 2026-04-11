//
//  FullscreenImageViewer.swift
//  Tanuki
//
//  Created by Max on 12/19/24.
//

import SwiftUI

public struct FullscreenImageViewer: View {
    @Environment(\.dismiss) private var dismiss;
    let post: PostContent;

    public var body: some View {
        NavigationStack {
            ZoomableContainer {
                MediaView(post: post)
                    .frame(minWidth: 0, maxWidth: .greatestFiniteMagnitude, minHeight: 0, maxHeight: .greatestFiniteMagnitude)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}
