import SwiftUI

// MARK: - Search View

/// Search interface with glass search bar, filters, recent searches, and results
struct SearchView: View {
    var onThreadSelected: ((EmailThread) -> Void)?

    @StateObject private var viewModel = SearchViewModel()
    @State private var activeFilters: Set<SearchFilter> = []
    @State private var showAdvancedFilters = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar with filters
                    searchBarSection

                    // Content
                    if viewModel.searchText.isEmpty {
                        recentSearchesSection
                    } else if viewModel.isSearching {
                        searchLoadingState
                    } else if viewModel.results.isEmpty {
                        emptyResultsState
                    } else {
                        searchResultsList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Search Bar Section

    private var searchBarSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Main search bar
            GlassSearchBar(
                text: $viewModel.searchText,
                placeholder: "Search emails",
                showsCancelButton: false,
                onSubmit: {
                    viewModel.performSearch()
                }
            )
            .padding(.horizontal)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    // Quick filters
                    ForEach(SearchFilter.allCases) { filter in
                        FilterChip(
                            filter: filter,
                            isActive: activeFilters.contains(filter),
                            action: { toggleFilter(filter) }
                        )
                    }

                    // Advanced filters button
                    Button(action: { showAdvancedFilters = true }) {
                        HStack(spacing: Theme.Spacing.xxs) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .medium))
                            Text("More")
                                .font(Theme.Typography.labelChip)
                        }
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .stroke(borderColor, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }

            // Active filters summary
            if !activeFilters.isEmpty {
                activeFiltersSummary
            }

            Divider()
        }
        .sheet(isPresented: $showAdvancedFilters) {
            AdvancedFiltersView(
                filters: $viewModel.filters,
                onApply: {
                    showAdvancedFilters = false
                    viewModel.performSearch()
                }
            )
            .presentationDetents([.medium])
        }
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(Theme.Opacity.glassBorder)
            : Color.black.opacity(0.1)
    }

    private var activeFiltersSummary: some View {
        HStack {
            Text("\(activeFilters.count) filter(s) active")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)

            Button("Clear all") {
                clearAllFilters()
            }
            .font(Theme.Typography.captionBold)
            .foregroundStyle(Theme.Colors.primary)
        }
        .padding(.horizontal)
    }

    // MARK: - Recent Searches

    private var recentSearchesSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Recent searches
                if !viewModel.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Text("Recent Searches")
                                .font(Theme.Typography.headline)

                            Spacer()

                            Button("Clear") {
                                viewModel.clearRecentSearches()
                            }
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.primary)
                        }

                        ForEach(viewModel.recentSearches) { search in
                            RecentSearchRow(
                                search: search,
                                onTap: {
                                    viewModel.searchText = search.query
                                    viewModel.performSearch()
                                },
                                onRemove: {
                                    viewModel.removeRecentSearch(search)
                                }
                            )
                        }
                    }
                }

                // Search suggestions
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Try searching for")
                        .font(Theme.Typography.headline)

                    FlowingChipLayout {
                        SearchSuggestionChip(text: "is:unread") {
                            viewModel.searchText = "is:unread"
                            viewModel.performSearch()
                        }
                        SearchSuggestionChip(text: "has:attachment") {
                            viewModel.searchText = "has:attachment"
                            viewModel.performSearch()
                        }
                        SearchSuggestionChip(text: "is:starred") {
                            viewModel.searchText = "is:starred"
                            viewModel.performSearch()
                        }
                        SearchSuggestionChip(text: "from:me") {
                            viewModel.searchText = "from:me"
                            viewModel.performSearch()
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Search Loading State

    private var searchLoadingState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching...")
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty Results State

    private var emptyResultsState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No results found")
                .font(Theme.Typography.title2)

            Text("Try a different search term or adjust your filters")
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            // Suggestions
            VStack(spacing: Theme.Spacing.sm) {
                Text("Suggestions:")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    SuggestionRow(text: "Check your spelling")
                    SuggestionRow(text: "Try more general keywords")
                    SuggestionRow(text: "Remove some filters")
                }
            }
            .padding(.top, Theme.Spacing.md)

            Spacer()
        }
        .padding()
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Results count
                HStack {
                    Text("\(viewModel.results.count) result(s)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, Theme.Spacing.sm)

                ForEach(viewModel.results) { thread in
                    VStack(spacing: 0) {
                        SearchResultRow(
                            thread: thread,
                            searchQuery: viewModel.searchText,
                            onTap: {
                                Haptics.light()
                                viewModel.addToRecentSearches()
                                onThreadSelected?(thread)
                            }
                        )

                        Divider()
                            .padding(.leading, Theme.Spacing.listRowPadding + Theme.Spacing.avatarSizeMedium + Theme.Spacing.sm)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleFilter(_ filter: SearchFilter) {
        Haptics.selection()
        withAnimation(Theme.Animation.easeFast) {
            if activeFilters.contains(filter) {
                activeFilters.remove(filter)
            } else {
                activeFilters.insert(filter)
            }
        }
        updateFiltersAndSearch()
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation(Theme.Animation.easeFast) {
            activeFilters.removeAll()
        }
        viewModel.filters = EmailSearchFilters()
        viewModel.performSearch()
    }

    private func updateFiltersAndSearch() {
        viewModel.filters.hasAttachment = activeFilters.contains(.hasAttachment) ? true : nil
        viewModel.filters.isUnread = activeFilters.contains(.isUnread) ? true : nil
        viewModel.filters.isStarred = activeFilters.contains(.isStarred) ? true : nil

        if activeFilters.contains(.fromMe) {
            viewModel.filters.from = "me"
        } else {
            viewModel.filters.from = nil
        }

        if activeFilters.contains(.toMe) {
            viewModel.filters.to = "me"
        } else {
            viewModel.filters.to = nil
        }

        viewModel.performSearch()
    }
}

// MARK: - Recent Search Row

struct RecentSearchRow: View {
    let search: RecentSearch
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Button(action: onTap) {
                Text(search.query)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: {
                Haptics.light()
                onRemove()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Search Suggestion Chip

struct SearchSuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Text(text)
                .font(Theme.Typography.labelChip)
                .foregroundStyle(Theme.Colors.primary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(
                    Capsule()
                        .fill(Theme.Colors.primary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(Theme.Colors.secondary)
                .frame(width: 4, height: 4)
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let thread: EmailThread
    let searchQuery: String
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                // Avatar
                ZStack {
                    if let sender = thread.primarySender {
                        SenderAvatar(sender: sender, size: Theme.Spacing.avatarSizeMedium)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    // Sender and timestamp
                    HStack {
                        Text(thread.primarySender?.displayName ?? "Unknown")
                            .font(thread.isRead ? Theme.Typography.body : Theme.Typography.bodyBold)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(thread.formattedDate)
                            .font(Theme.Typography.emailTimestamp)
                            .foregroundStyle(.secondary)
                    }

                    // Subject with highlighted query
                    HighlightedText(
                        text: thread.subject,
                        highlight: searchQuery,
                        font: Theme.Typography.emailSubject,
                        highlightColor: Theme.Colors.primary
                    )
                    .lineLimit(1)

                    // Snippet with highlighted query
                    HighlightedText(
                        text: thread.snippet,
                        highlight: searchQuery,
                        font: Theme.Typography.emailSnippet,
                        textColor: .secondary,
                        highlightColor: Theme.Colors.primary
                    )
                    .lineLimit(2)
                }
            }
            .padding(.vertical, Theme.Spacing.listRowVerticalPadding)
            .padding(.horizontal, Theme.Spacing.listRowPadding)
            .background(thread.isRead ? Color.clear : Theme.Colors.primary.opacity(0.03))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.99 : 1.0)
        .animation(Theme.Animation.buttonPress, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Highlighted Text

struct HighlightedText: View {
    let text: String
    let highlight: String
    var font: Font = Theme.Typography.body
    var textColor: Color = .primary
    var highlightColor: Color = Theme.Colors.primary

    var body: some View {
        let attributedString = createHighlightedString()
        Text(attributedString)
            .font(font)
    }

    private func createHighlightedString() -> AttributedString {
        var attributedString = AttributedString(text)
        attributedString.foregroundColor = textColor

        guard !highlight.isEmpty else { return attributedString }

        let lowercaseText = text.lowercased()
        let lowercaseHighlight = highlight.lowercased()

        var searchStartIndex = lowercaseText.startIndex

        while let range = lowercaseText.range(of: lowercaseHighlight, range: searchStartIndex..<lowercaseText.endIndex) {
            let startOffset = lowercaseText.distance(from: lowercaseText.startIndex, to: range.lowerBound)
            let endOffset = lowercaseText.distance(from: lowercaseText.startIndex, to: range.upperBound)

            let attrStartIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: startOffset)
            let attrEndIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: endOffset)

            attributedString[attrStartIndex..<attrEndIndex].foregroundColor = highlightColor
            attributedString[attrStartIndex..<attrEndIndex].backgroundColor = highlightColor.opacity(0.2)

            searchStartIndex = range.upperBound
        }

        return attributedString
    }
}

// MARK: - Advanced Filters View

struct AdvancedFiltersView: View {
    @Binding var filters: EmailSearchFilters
    let onApply: () -> Void

    @State private var fromText = ""
    @State private var toText = ""
    @State private var subjectText = ""
    @State private var afterDate: Date?
    @State private var beforeDate: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("People") {
                    TextField("From", text: $fromText)
                    TextField("To", text: $toText)
                }

                Section("Content") {
                    TextField("Subject contains", text: $subjectText)
                    Toggle("Has attachment", isOn: Binding(
                        get: { filters.hasAttachment ?? false },
                        set: { filters.hasAttachment = $0 ? true : nil }
                    ))
                }

                Section("Status") {
                    Toggle("Unread only", isOn: Binding(
                        get: { filters.isUnread ?? false },
                        set: { filters.isUnread = $0 ? true : nil }
                    ))
                    Toggle("Starred only", isOn: Binding(
                        get: { filters.isStarred ?? false },
                        set: { filters.isStarred = $0 ? true : nil }
                    ))
                }

                Section("Date Range") {
                    DatePicker(
                        "After",
                        selection: Binding(
                            get: { afterDate ?? Date() },
                            set: { afterDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    DatePicker(
                        "Before",
                        selection: Binding(
                            get: { beforeDate ?? Date() },
                            set: { beforeDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }

                Section {
                    Button("Reset Filters", role: .destructive) {
                        resetFilters()
                    }
                }
            }
            .navigationTitle("Advanced Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        applyFilters()
                    }
                    .font(Theme.Typography.bodyBold)
                }
            }
            .onAppear {
                loadCurrentFilters()
            }
        }
    }

    private func loadCurrentFilters() {
        fromText = filters.from ?? ""
        toText = filters.to ?? ""
        subjectText = filters.subject ?? ""
        afterDate = filters.after
        beforeDate = filters.before
    }

    private func applyFilters() {
        filters.from = fromText.isEmpty ? nil : fromText
        filters.to = toText.isEmpty ? nil : toText
        filters.subject = subjectText.isEmpty ? nil : subjectText
        filters.after = afterDate
        filters.before = beforeDate
        onApply()
    }

    private func resetFilters() {
        filters = EmailSearchFilters()
        fromText = ""
        toText = ""
        subjectText = ""
        afterDate = nil
        beforeDate = nil
    }
}

// MARK: - Search View Model

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var filters = EmailSearchFilters()
    @Published var results: [EmailThread] = []
    @Published var recentSearches: [RecentSearch] = []
    @Published var isSearching = false

    private let emailAPI: EmailAPIProtocol

    init(emailAPI: EmailAPIProtocol = ConvexEmailAPI()) {
        self.emailAPI = emailAPI
        loadRecentSearches()
    }

    func performSearch() {
        guard !searchText.isEmpty else {
            results = []
            return
        }

        isSearching = true
        filters.query = searchText

        Task {
            do {
                let searchResults = try await emailAPI.search(filters: filters)
                results = searchResults
                isSearching = false
            } catch {
                print("Search error: \(error)")
                isSearching = false
            }
        }
    }

    func addToRecentSearches() {
        guard !searchText.isEmpty else { return }

        let search = RecentSearch(
            id: UUID().uuidString,
            query: searchText,
            searchedAt: Date()
        )

        // Remove existing duplicate
        recentSearches.removeAll { $0.query.lowercased() == searchText.lowercased() }

        // Add to front
        recentSearches.insert(search, at: 0)

        // Limit to 10 recent searches
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }

        saveRecentSearches()
    }

    func removeRecentSearch(_ search: RecentSearch) {
        recentSearches.removeAll { $0.id == search.id }
        saveRecentSearches()
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        saveRecentSearches()
    }

    private func loadRecentSearches() {
        if let data = UserDefaults.standard.data(forKey: "recentSearches"),
           let searches = try? JSONDecoder().decode([RecentSearch].self, from: data) {
            recentSearches = searches
        }
    }

    private func saveRecentSearches() {
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(data, forKey: "recentSearches")
        }
    }
}

// MARK: - Preview

#Preview("Search View") {
    SearchView()
}

#Preview("With Results") {
    struct PreviewWrapper: View {
        var body: some View {
            SearchView()
        }
    }

    return PreviewWrapper()
}
