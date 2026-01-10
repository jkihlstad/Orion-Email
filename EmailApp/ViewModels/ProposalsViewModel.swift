import Foundation
import SwiftUI

@MainActor
final class ProposalsViewModel: ObservableObject {
    @Published var proposals: [RescheduleProposalDTO] = []
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    private let api: ConvexCalendarAPI

    init(api: ConvexCalendarAPI) {
        self.api = api
    }

    func refresh() {
        Task {
            do {
                proposals = try await api.listProposals(status: "sent")
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    func apply(proposalId: String) {
        Task {
            do {
                try await api.applyProposal(proposalId: proposalId)
                refresh()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
