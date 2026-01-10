import SwiftUI

struct ProposalsListView: View {
    @StateObject private var vm: ProposalsViewModel

    init(api: ConvexCalendarAPI) {
        _vm = StateObject(wrappedValue: ProposalsViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.proposals) { p in
                    NavigationLink {
                        ProposalDetailView(proposal: p, onApply: { vm.apply(proposalId: p.id) })
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.requiresApprover ? "Approval Needed" : "Suggestion")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(p.rationale)
                                .lineLimit(2)
                            Text("Status: \(p.status)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Proposals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") { vm.refresh() }
                }
            }
            .task { vm.refresh() }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(vm.errorMessage) }
        }
    }
}
