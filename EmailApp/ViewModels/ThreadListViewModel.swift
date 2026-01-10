import Foundation
import SwiftUI
import Combine

// MARK: - Thread List View Model

/// ViewModel for the thread list (inbox) view
/// Handles loading, refreshing, and applying actions to email threads
@MainActor
class ThreadListViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var threads: [EmailThread] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var error: EmailError?
    @Published var hasMoreThreads = true
    @Published var currentLabelId: String?

    // MARK: - Private Properties

    private let emailAPI: EmailAPIProtocol
    private var cancellables = Set<AnyCancellable>()
    private var currentPage = 0
    private let pageSize = 20
    private var isLoadingMore = false

    // MARK: - Initialization

    init(emailAPI: EmailAPIProtocol = ConvexEmailAPI()) {
        self.emailAPI = emailAPI
    }

    // MARK: - Public Methods

    /// Loads threads for a given label
    func loadThreads(labelId: String) {
        guard !isLoading else { return }

        currentLabelId = labelId
        currentPage = 0
        isLoading = true
        error = nil

        Task {
            do {
                let loadedThreads = try await emailAPI.listThreads(
                    labelId: labelId,
                    page: currentPage,
                    pageSize: pageSize
                )

                threads = loadedThreads
                hasMoreThreads = loadedThreads.count == pageSize
                isLoading = false
            } catch let apiError as EmailError {
                error = apiError
                isLoading = false

                // Use mock data in debug mode
                #if DEBUG
                useMockData()
                #endif
            } catch {
                self.error = .networkError(error.localizedDescription)
                isLoading = false

                #if DEBUG
                useMockData()
                #endif
            }
        }
    }

    /// Refreshes the current thread list
    func refresh() async {
        guard let labelId = currentLabelId else { return }

        isRefreshing = true
        currentPage = 0

        do {
            let refreshedThreads = try await emailAPI.listThreads(
                labelId: labelId,
                page: currentPage,
                pageSize: pageSize
            )

            threads = refreshedThreads
            hasMoreThreads = refreshedThreads.count == pageSize
            isRefreshing = false
            Haptics.success()
        } catch {
            isRefreshing = false
            Haptics.error()
        }
    }

    /// Loads more threads for pagination
    func loadMoreThreadsIfNeeded(currentThread: EmailThread) {
        guard let lastThread = threads.last,
              lastThread.id == currentThread.id,
              hasMoreThreads,
              !isLoadingMore,
              let labelId = currentLabelId else {
            return
        }

        loadMoreThreads(labelId: labelId)
    }

    /// Applies an action to a thread
    func applyAction(threadId: String, action: MessageAction) {
        // Optimistic update
        optimisticallyUpdateThread(threadId: threadId, action: action)

        Task {
            do {
                try await emailAPI.applyAction(
                    threadIds: [threadId],
                    action: action
                )

                // Remove from list if archived or trashed
                if action == .archive || action == .trash || action == .spam {
                    withAnimation(Theme.Animation.defaultSpring) {
                        threads.removeAll { $0.id == threadId }
                    }
                }
            } catch {
                // Revert optimistic update on failure
                revertOptimisticUpdate(threadId: threadId, action: action)
                Haptics.error()
            }
        }
    }

    /// Applies an action to multiple threads
    func applyBatchAction(threadIds: Set<String>, action: MessageAction) {
        // Optimistic update
        for threadId in threadIds {
            optimisticallyUpdateThread(threadId: threadId, action: action)
        }

        Task {
            do {
                try await emailAPI.applyAction(
                    threadIds: Array(threadIds),
                    action: action
                )

                // Remove from list if needed
                if action == .archive || action == .trash || action == .spam {
                    withAnimation(Theme.Animation.defaultSpring) {
                        threads.removeAll { threadIds.contains($0.id) }
                    }
                }

                Haptics.success()
            } catch {
                // Revert optimistic updates on failure
                for threadId in threadIds {
                    revertOptimisticUpdate(threadId: threadId, action: action)
                }
                Haptics.error()
            }
        }
    }

    // MARK: - Private Methods

    private func loadMoreThreads(labelId: String) {
        isLoadingMore = true
        currentPage += 1

        Task {
            do {
                let moreThreads = try await emailAPI.listThreads(
                    labelId: labelId,
                    page: currentPage,
                    pageSize: pageSize
                )

                threads.append(contentsOf: moreThreads)
                hasMoreThreads = moreThreads.count == pageSize
                isLoadingMore = false
            } catch {
                currentPage -= 1
                isLoadingMore = false
            }
        }
    }

    private func optimisticallyUpdateThread(threadId: String, action: MessageAction) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }

        withAnimation(Theme.Animation.easeFast) {
            switch action {
            case .markRead:
                threads[index].isRead = true
            case .markUnread:
                threads[index].isRead = false
            case .star:
                threads[index].isStarred = true
            case .unstar:
                threads[index].isStarred = false
            case .archive:
                threads[index].isArchived = true
            case .unarchive:
                threads[index].isArchived = false
            case .trash:
                threads[index].isTrashed = true
            case .restore:
                threads[index].isTrashed = false
            case .spam:
                threads[index].isSpam = true
            case .notSpam:
                threads[index].isSpam = false
            default:
                break
            }
        }
    }

    private func revertOptimisticUpdate(threadId: String, action: MessageAction) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }

        withAnimation(Theme.Animation.easeFast) {
            switch action {
            case .markRead:
                threads[index].isRead = false
            case .markUnread:
                threads[index].isRead = true
            case .star:
                threads[index].isStarred = false
            case .unstar:
                threads[index].isStarred = true
            case .archive:
                threads[index].isArchived = false
            case .unarchive:
                threads[index].isArchived = true
            case .trash:
                threads[index].isTrashed = false
            case .restore:
                threads[index].isTrashed = true
            case .spam:
                threads[index].isSpam = false
            case .notSpam:
                threads[index].isSpam = true
            default:
                break
            }
        }
    }

    private func useMockData() {
        threads = EmailThread.mockThreads
        hasMoreThreads = false
    }
}

// MARK: - Email Error

enum EmailError: LocalizedError, Equatable {
    case networkError(String)
    case authenticationError
    case notFound
    case serverError(Int)
    case invalidData
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationError:
            return "Please sign in again"
        case .notFound:
            return "Email not found"
        case .serverError(let code):
            return "Server error (code: \(code))"
        case .invalidData:
            return "Invalid data received"
        case .quotaExceeded:
            return "Storage quota exceeded"
        }
    }
}
