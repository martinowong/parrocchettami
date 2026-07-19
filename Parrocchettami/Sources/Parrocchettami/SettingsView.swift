import SwiftUI

struct SettingsView: View {
    @AppStorage("historyRetentionLimit") private var historyRetentionLimit = 100

    var body: some View {
        Form {
            Section("History") {
                Picker("Keep recent transcripts", selection: $historyRetentionLimit) {
                    Text("50 transcripts").tag(50)
                    Text("100 transcripts").tag(100)
                    Text("250 transcripts").tag(250)
                    Text("500 transcripts").tag(500)
                    Text("Unlimited").tag(0)
                }

                Text("Archived transcripts are always kept. When a limit is reached, only the oldest unarchived transcripts are removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 210)
        .scenePadding()
    }
}
