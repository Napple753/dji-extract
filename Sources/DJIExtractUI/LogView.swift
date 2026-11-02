import SwiftUI

/// In-app log for debugging while the camera is plugged in.
struct LogView: View {
    @Environment(\.dismiss) private var dismiss
    private let log = AppLog.shared

    var body: some View {
        NavigationStack {
            List(log.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.message)
                        .font(.caption.monospaced())
                        .foregroundStyle(entry.level == .error ? .red : .primary)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem { Button("Clear") { log.clear() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
