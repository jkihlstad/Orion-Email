import SwiftUI

// MARK: - Glass Search Bar

/// A search bar with glass material background and Apple-style design
/// Features search icon, clear button, and focus state animations
struct GlassSearchBar: View {
    @Binding var text: String
    var placeholder: String
    var showsCancelButton: Bool
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var isEditing = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        text: Binding<String>,
        placeholder: String = "Search",
        showsCancelButton: Bool = true,
        onSubmit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.showsCancelButton = showsCancelButton
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Search field
            HStack(spacing: Theme.Spacing.xs) {
                // Search icon
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(iconColor)
                    .animation(Theme.Animation.easeFast, value: isFocused)

                // Text field
                TextField(placeholder, text: $text)
                    .font(Theme.Typography.body)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        Haptics.light()
                        onSubmit?()
                    }
                    .onChange(of: isFocused) { _, newValue in
                        withAnimation(Theme.Animation.defaultSpring) {
                            isEditing = newValue
                        }
                    }

                // Clear button
                if !text.isEmpty {
                    Button(action: clearText) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .frame(height: Theme.Spacing.searchBarHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.searchBar)
                    .fill(backgroundMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.searchBar)
                            .stroke(borderColor, lineWidth: isFocused ? 1.5 : 1)
                    )
            )
            .shadow(Theme.Shadows.xs)
            .animation(Theme.Animation.defaultSpring, value: isFocused)

            // Cancel button
            if showsCancelButton && isEditing {
                Button("Cancel") {
                    cancelSearch()
                }
                .font(Theme.Typography.body)
                .foregroundStyle(.primary)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Theme.Animation.defaultSpring, value: isEditing)
    }

    // MARK: - Computed Properties

    private var backgroundMaterial: some ShapeStyle {
        if isFocused {
            return AnyShapeStyle(.regularMaterial)
        } else {
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var iconColor: Color {
        isFocused ? .primary : .secondary
    }

    private var borderColor: Color {
        if isFocused {
            return Theme.Colors.primary.opacity(0.5)
        }
        return colorScheme == .dark
            ? Color.white.opacity(Theme.Opacity.glassBorder)
            : Color.black.opacity(0.1)
    }

    // MARK: - Actions

    private func clearText() {
        Haptics.light()
        withAnimation(Theme.Animation.easeFast) {
            text = ""
        }
    }

    private func cancelSearch() {
        Haptics.light()
        withAnimation(Theme.Animation.defaultSpring) {
            text = ""
            isFocused = false
            isEditing = false
        }
        onCancel?()
    }
}

// MARK: - Glass Search Bar with Filters

/// An enhanced search bar with filter chips
struct GlassSearchBarWithFilters: View {
    @Binding var text: String
    @Binding var activeFilters: Set<SearchFilter>
    var placeholder: String
    var availableFilters: [SearchFilter]
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(
        text: Binding<String>,
        activeFilters: Binding<Set<SearchFilter>>,
        placeholder: String = "Search emails",
        availableFilters: [SearchFilter] = SearchFilter.allCases,
        onSubmit: (() -> Void)? = nil
    ) {
        self._text = text
        self._activeFilters = activeFilters
        self.placeholder = placeholder
        self.availableFilters = availableFilters
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Main search bar
            GlassSearchBar(
                text: $text,
                placeholder: placeholder,
                showsCancelButton: true,
                onSubmit: onSubmit
            )

            // Filter chips
            if !availableFilters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(availableFilters) { filter in
                            FilterChip(
                                filter: filter,
                                isActive: activeFilters.contains(filter),
                                action: { toggleFilter(filter) }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xxs)
                }
            }
        }
    }

    private func toggleFilter(_ filter: SearchFilter) {
        Haptics.selection()
        withAnimation(Theme.Animation.defaultSpring) {
            if activeFilters.contains(filter) {
                activeFilters.remove(filter)
            } else {
                activeFilters.insert(filter)
            }
        }
    }
}

// MARK: - Search Filter

enum SearchFilter: String, CaseIterable, Identifiable, Hashable {
    case hasAttachment = "has:attachment"
    case isUnread = "is:unread"
    case isStarred = "is:starred"
    case fromMe = "from:me"
    case toMe = "to:me"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hasAttachment: return "Attachments"
        case .isUnread: return "Unread"
        case .isStarred: return "Starred"
        case .fromMe: return "From me"
        case .toMe: return "To me"
        }
    }

    var iconName: String {
        switch self {
        case .hasAttachment: return "paperclip"
        case .isUnread: return "envelope.badge.fill"
        case .isStarred: return "star.fill"
        case .fromMe: return "arrow.up.right"
        case .toMe: return "arrow.down.left"
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let filter: SearchFilter
    let isActive: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: filter.iconName)
                    .font(.system(size: 12, weight: .medium))
                Text(filter.displayName)
                    .font(Theme.Typography.labelChip)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                Capsule()
                    .fill(isActive ? activeBackground : inactiveBackground)
                    .overlay(
                        Capsule()
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var activeBackground: some ShapeStyle {
        AnyShapeStyle(Theme.Colors.primary)
    }

    private var inactiveBackground: some ShapeStyle {
        AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderColor: Color {
        if isActive {
            return .clear
        }
        return colorScheme == .dark
            ? Color.white.opacity(Theme.Opacity.glassBorder)
            : Color.black.opacity(0.1)
    }
}

// MARK: - Compact Search Button

/// A compact search button that expands into a full search bar
struct CompactSearchButton: View {
    @Binding var isExpanded: Bool
    @Binding var searchText: String
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            if isExpanded {
                GlassSearchBar(
                    text: $searchText,
                    placeholder: "Search",
                    showsCancelButton: true,
                    onSubmit: onSubmit,
                    onCancel: {
                        withAnimation(Theme.Animation.defaultSpring) {
                            isExpanded = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
            } else {
                Button(action: expand) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(Theme.Opacity.glassBorder), lineWidth: 1)
                                )
                        )
                        .shadow(Theme.Shadows.sm)
                }
                .buttonStyle(GlassButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func expand() {
        Haptics.light()
        withAnimation(Theme.Animation.defaultSpring) {
            isExpanded = true
        }
    }
}

// MARK: - Preview

#Preview("Glass Search Bar") {
    ZStack {
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: Theme.Spacing.xl) {
            // Basic search bar
            GlassSearchBar(
                text: .constant(""),
                placeholder: "Search emails..."
            )

            // Search bar with text
            GlassSearchBar(
                text: .constant("Project update"),
                placeholder: "Search emails..."
            )

            // Search bar with filters
            GlassSearchBarWithFilters(
                text: .constant(""),
                activeFilters: .constant([.isUnread, .hasAttachment]),
                placeholder: "Search emails"
            )

            Spacer()
        }
        .padding()
    }
}

#Preview("Compact Search") {
    ZStack {
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack {
            HStack {
                Text("Inbox")
                    .font(Theme.Typography.title)
                Spacer()
                CompactSearchButton(
                    isExpanded: .constant(false),
                    searchText: .constant("")
                )
            }
            .padding()

            Spacer()

            HStack {
                CompactSearchButton(
                    isExpanded: .constant(true),
                    searchText: .constant("Search query")
                )
            }
            .padding()

            Spacer()
        }
    }
}
