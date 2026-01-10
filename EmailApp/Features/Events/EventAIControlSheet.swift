import SwiftUI

struct EventAIControlSheet: View {
    @Binding var policy: EventPolicy
    var onSave: (EventPolicy) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Control") {
                    Picker("Lock State", selection: $policy.lockState) {
                        ForEach(LockState.allCases, id: \.self) { state in
                            Text(state.rawValue.capitalized).tag(state)
                        }
                    }

                    Toggle("Confirm before contacting others", isOn: $policy.requiresUserConfirmationBeforeSendingRequests)

                    Picker("Content sharing", selection: $policy.contentSharing) {
                        Text("None").tag("none")
                        Text("Minimal").tag("minimal")
                        Text("Full").tag("full")
                    }
                }

                if policy.lockState == .negotiable {
                    Section("Approver") {
                        TextField("Name", text: Binding(get: { policy.approver?.name ?? "" }, set: {
                            if policy.approver == nil { policy.approver = .init() }
                            policy.approver?.name = $0
                        }))
                        TextField("Email", text: Binding(get: { policy.approver?.email ?? "" }, set: {
                            if policy.approver == nil { policy.approver = .init() }
                            policy.approver?.email = $0
                        }))
                        TextField("Phone", text: Binding(get: { policy.approver?.phone ?? "" }, set: {
                            if policy.approver == nil { policy.approver = .init() }
                            policy.approver?.phone = $0
                        }))
                    }
                }

                if policy.lockState == .sensitive {
                    Section {
                        Text("Sensitive events will not include details in approval requests or messages.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("AI Control")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(policy) }
                }
            }
        }
    }
}
