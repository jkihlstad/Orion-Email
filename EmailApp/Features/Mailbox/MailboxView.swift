import SwiftUI

// MARK: - Mailbox View

/// Sidebar/sheet for selecting mailboxes with account picker and label list
struct MailboxView: View {
    @Binding var selectedLabel: EmailLabel
    let account: EmailAccount
    let onDismiss: () -> Void

    @State private var labels: [EmailLabel] = EmailLabel.allSystemLabels
    @State private var customLabels: [EmailLabel] = []
    @State private var showAccountPicker = false
    @State private var isRefreshing = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Account Section
                        accountSection

                        // System Labels
                        labelsSection

                        // Custom Labels
                        if !customLabels.isEmpty {
                            customLabelsSection
                        }

                        // Actions
                        actionsSection
                    }
                    .padding()
                }
                .refreshable {
                    await refreshLabels()
                }
            }
            .navigationTitle("Mailboxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.light()
                        onDismiss()
                    }
                    .font(Theme.Typography.bodyBold)
                }
            }
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                Color(uiColor: .secondarySystemBackground).opacity(0.5)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var accountSection: some View {
        GlassCard(padding: Theme.Spacing.sm) {
            Button(action: { showAccountPicker = true }) {
                HStack(spacing: Theme.Spacing.md) {
                    // Avatar
                    AccountAvatar(account: account, size: 48)

                    // Account Info
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(account.displayName)
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(.primary)

                        Text(account.email)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showAccountPicker) {
            AccountPickerView(currentAccount: account)
        }
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("MAILBOXES")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.sm)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(labels) { label in
                        LabelRow(
                            label: label,
                            isSelected: selectedLabel.id == label.id,
                            onSelect: {
                                selectLabel(label)
                            }
                        )

                        if label.id != labels.last?.id {
                            Divider()
                                .padding(.leading, Theme.Spacing.xxl + Theme.Spacing.md)
                        }
                    }
                }
            }
        }
    }

    private var customLabelsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("LABELS")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: createNewLabel) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(customLabels) { label in
                        LabelRow(
                            label: label,
                            isSelected: selectedLabel.id == label.id,
                            onSelect: {
                                selectLabel(label)
                            }
                        )

                        if label.id != customLabels.last?.id {
                            Divider()
                                .padding(.leading, Theme.Spacing.xxl + Theme.Spacing.md)
                        }
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ActionButton(
                icon: "gear",
                title: "Settings",
                action: openSettings
            )

            ActionButton(
                icon: "questionmark.circle",
                title: "Help & Feedback",
                action: openHelp
            )
        }
    }

    // MARK: - Actions

    private func selectLabel(_ label: EmailLabel) {
        Haptics.selection()
        withAnimation(Theme.Animation.defaultSpring) {
            selectedLabel = label
        }
        onDismiss()
    }

    private func refreshLabels() async {
        isRefreshing = true
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isRefreshing = false
    }

    private func createNewLabel() {
        Haptics.light()
        // Would open label creation flow
    }

    private func openSettings() {
        Haptics.light()
        // Would navigate to settings
    }

    private func openHelp() {
        Haptics.light()
        // Would open help
    }
}

// MARK: - Account Avatar

struct AccountAvatar: View {
    let account: EmailAccount
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            if let avatarURL = account.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.avatarColor(for: account.id))

            Text(account.displayName.prefix(1).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Label Row

struct LabelRow: View {
    let label: EmailLabel
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.md) {
                // Icon
                Image(systemName: label.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? label.displayColor : .secondary)
                    .frame(width: 24)

                // Name
                Text(label.name)
                    .font(isSelected ? Theme.Typography.bodyBold : Theme.Typography.body)
                    .foregroundStyle(.primary)

                Spacer()

                // Unread count
                if label.unreadCount > 0 {
                    Text("\(label.unreadCount)")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(
                            Capsule()
                                .fill(label.displayColor)
                        )
                }

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                isSelected
                    ? label.displayColor.opacity(0.1)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(Theme.Animation.buttonPress, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(.plain)
        .glassMorphism(cornerRadius: Theme.CornerRadius.md)
    }
}

// MARK: - Account Picker View

struct AccountPickerView: View {
    let currentAccount: EmailAccount
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Current account
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("CURRENT ACCOUNT")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Theme.Spacing.sm)

                            AccountRow(account: currentAccount, isSelected: true) {}
                        }

                        // Other accounts
                        if authManager.accounts.count > 1 {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("OTHER ACCOUNTS")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, Theme.Spacing.sm)

                                VStack(spacing: Theme.Spacing.xs) {
                                    ForEach(authManager.accounts.filter { $0.id != currentAccount.id }) { account in
                                        AccountRow(account: account, isSelected: false) {
                                            // Switch account
                                            dismiss()
                                        }
                                    }
                                }
                            }
                        }

                        // Add account
                        AddAccountButton {
                            // Would open add account flow
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct AccountRow: View {
    let account: EmailAccount
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.md) {
                AccountAvatar(account: account, size: 44)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(account.displayName)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(.primary)

                    HStack(spacing: Theme.Spacing.xs) {
                        Text(account.email)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)

                        if account.isActive {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct AddAccountButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.primary.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)
                }

                Text("Add another account")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Mailbox View") {
    struct PreviewWrapper: View {
        @State private var selectedLabel = EmailLabel.inbox

        var body: some View {
            MailboxView(
                selectedLabel: $selectedLabel,
                account: .mock,
                onDismiss: {}
            )
        }
    }

    return PreviewWrapper()
        .environmentObject(AuthManager())
}

#Preview("Account Picker") {
    AccountPickerView(currentAccount: .mock)
        .environmentObject(AuthManager())
}
