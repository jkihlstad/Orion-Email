import SwiftUI

struct ProposalDetailView: View {
    let proposal: RescheduleProposalDTO
    var onApply: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(proposal.rationale)
                    .font(.body)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                Text("Options")
                    .font(.headline)

                ForEach(Array(proposal.options.enumerated()), id: \.offset) { idx, option in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Option \(idx + 1)")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("Score: \(Int(option.score))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(formatDate(option.startAt) + " - " + formatDate(option.endAt))
                            .font(.caption)
                        Text(option.explain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                if proposal.status == "approved" {
                    Button("Apply Reschedule") {
                        onApply()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle("Proposal")
    }

    private func formatDate(_ ts: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
