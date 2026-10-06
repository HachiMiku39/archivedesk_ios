import SwiftUI

/// Preserve full values at accessibility text sizes, without shrinking text.
struct AdaptiveValueRow: View {
    let title: LocalizedStringKey
    let value: String
    @Environment(\.dynamicTypeSize) private var textSize
    init(_ title: LocalizedStringKey, value: String) { self.title = title; self.value = value }
    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                    Text(verbatim: value).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else { LabeledContent(title, value: value) }
        }
        .accessibilityElement(children: .combine)
    }
}
