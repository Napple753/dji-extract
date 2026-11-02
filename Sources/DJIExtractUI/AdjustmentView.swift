import DJIExtractCore
import SwiftUI

/// Per-video date correction: offset Δ in seconds and the shooting location's time zone.
struct AdjustmentView: View {
    @Binding var settings: VideoSettings
    let hasCreationTime: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var zoneQuery = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $settings.adjustment.offset, step: 1) {
                        LabeledContent("Offset", value: Formatting.offset(settings.adjustment.offset))
                    }
                    Stepper("Fine (0.1 s)", value: $settings.adjustment.offset, step: 0.1)
                    Button("Reset Offset") { settings.adjustment.offset = 0 }
                } footer: {
                    Text("Added to every capture time of this video. Use it when the camera clock was off.")
                }

                if !hasCreationTime && settings.manualRecordingStart != nil {
                    Section {
                        Button("Clear Manually Entered Time", role: .destructive) { settings.manualRecordingStart = nil }
                    }
                }

                Section {
                    TextField("Search time zones", text: $zoneQuery)
                    ForEach(matchingZones, id: \.self) { identifier in
                        Button {
                            settings.adjustment.timeZoneIdentifier = identifier
                        } label: {
                            HStack {
                                Text(identifier)
                                Spacer()
                                Text(offsetLabel(identifier)).foregroundStyle(.secondary)
                                if identifier == settings.adjustment.timeZoneIdentifier {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Shooting Location Time Zone")
                } footer: {
                    Text("Defaults to this iPhone's current time zone. Change it for videos shot while traveling.")
                }
            }
            .navigationTitle("Capture Date")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var matchingZones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !zoneQuery.isEmpty else {
            return [settings.adjustment.timeZoneIdentifier, TimeZone.current.identifier]
                .reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
        return all.filter { $0.localizedCaseInsensitiveContains(zoneQuery) }
    }

    private func offsetLabel(_ identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return "" }
        return CaptureTimestamp(date: Date(), timeZone: zone).exifOffset
    }
}
