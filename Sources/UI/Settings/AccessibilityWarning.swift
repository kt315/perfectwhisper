import AppKit
import Observation
import SwiftUI

struct AccessibilityWarning: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L10n.t("Open System Settings")) {
                Permissions.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
    }
}
