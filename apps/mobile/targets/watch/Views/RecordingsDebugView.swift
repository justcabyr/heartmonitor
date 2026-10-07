import SwiftUI

#if DEBUG
struct RecordingsDebugView: View {
    @State private var listings: [RecordingListing] = []
    @State private var errorMessage: String?
    @State private var transferNote: String?

    private let store = RecordingStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }
                if let transferNote {
                    Text(transferNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                if listings.isEmpty && errorMessage == nil {
                    Text("No recordings")
                        .foregroundStyle(.secondary)
                }
                ForEach(listings) { listing in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listing.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        Text("Duration \(SessionClock.string(from: listing.activeSeconds))")
                        Text("\(listing.sampleCount) samples")
                        Text(listing.id.uuidString.lowercased().prefix(8))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(listing.isFinalized ? "Saved" : "Open")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Recordings")
        .task {
            RecordingTransfer.sendFinishedRecordings()
            reload()
        }
    }

    private func reload() {
        transferNote = RecordingTransfer.statusText()
        do {
            listings = try store.listings()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
