//
//  SearchStore.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/12.
//

import ComposableArchitecture

struct SearchState: Equatable {
    enum Route: Equatable {
        case filters
        case quickSearch
        case detail(String)
    }
    struct CancelID: Hashable {
        let id = String(describing: SearchState.self)
    }

    init() {
        _detailState = .init(.init())
    }

    @BindableState var route: Route?
    @BindableState var keyword = ""
    var lastKeyword = ""
    @BindableState var jumpPageIndex = ""
    @BindableState var jumpPageAlertFocused = false
    @BindableState var jumpPageAlertPresented = false

    var galleries = [Gallery]()
    var pageNumber = PageNumber()
    var loadingState: LoadingState = .idle
    var footerLoadingState: LoadingState = .idle

    var filtersState = FiltersState()
    @Heap var detailState: DetailState!
    var quickSearchState = QuickSearchState()

    mutating func insertGalleries(_ galleries: [Gallery]) {
        galleries.forEach { gallery in
            if !self.galleries.contains(gallery) {
                self.galleries.append(gallery)
            }
        }
    }
}

enum SearchAction: BindableAction {
    case binding(BindingAction<SearchState>)
    case setNavigation(SearchState.Route?)
    case clearSubStates

    case performJumpPage
    case presentJumpPageAlert
    case setJumpPageAlertFocused(Bool)

    case teardown
    case fetchGalleries(Int? = nil, String? = nil)
    case fetchGalleriesDone(Result<(PageNumber, [Gallery]), AppError>)
    case fetchMoreGalleries
    case fetchMoreGalleriesDone(Result<(PageNumber, [Gallery]), AppError>)

    case detail(DetailAction)
    case filters(FiltersAction)
    case quickSearch(QuickSearchAction)
}

struct SearchEnvironment {
    let urlClient: URLClient
    let fileClient: FileClient
    let imageClient: ImageClient
    let deviceClient: DeviceClient
    let hapticClient: HapticClient
    let cookiesClient: CookiesClient
    let databaseClient: DatabaseClient
    let clipboardClient: ClipboardClient
    let appDelegateClient: AppDelegateClient
    let uiApplicationClient: UIApplicationClient
}

let searchReducer = Reducer<SearchState, SearchAction, SearchEnvironment>.combine(
    .init { state, action, environment in
        switch action {
        case .binding(\.$route):
            return state.route == nil ? .init(value: .clearSubStates) : .none

        case .binding(\.$jumpPageAlertPresented):
            if !state.jumpPageAlertPresented {
                state.jumpPageAlertFocused = false
            }
            return .none

        case .binding(\.$keyword):
            if !state.keyword.isEmpty {
                state.lastKeyword = state.keyword
            }
            return .none

        case .binding:
            return .none

        case .setNavigation(let route):
            state.route = route
            return route == nil ? .init(value: .clearSubStates) : .none

        case .clearSubStates:
            state.detailState = .init()
            state.filtersState = .init()
            state.quickSearchState = .init()
            return .merge(
                .init(value: .detail(.teardown)),
                .init(value: .quickSearch(.teardown))
            )

        case .performJumpPage:
            guard let index = Int(state.jumpPageIndex), index > 0, index <= state.pageNumber.maximum + 1 else {
                return environment.hapticClient.generateNotificationFeedback(.error).fireAndForget()
            }
            return .init(value: .fetchGalleries(index - 1))

        case .presentJumpPageAlert:
            state.jumpPageAlertPresented = true
            return environment.hapticClient.generateFeedback(.light).fireAndForget()

        case .setJumpPageAlertFocused(let isFocused):
            state.jumpPageAlertFocused = isFocused
            return .none

        case .teardown:
            return .cancel(id: SearchState.CancelID())

        case .fetchGalleries(let pageNum, let keyword):
            guard state.loadingState != .loading else { return .none }
            if let keyword = keyword {
                state.keyword = keyword
                state.lastKeyword = keyword
            }
            state.loadingState = .loading
            state.pageNumber.current = 0
            let filter = environment.databaseClient.fetchFilterSynchronously(range: .search)
            return SearchGalleriesRequest(keyword: state.lastKeyword, filter: filter, pageNum: pageNum)
                .effect.map(SearchAction.fetchGalleriesDone).cancellable(id: SearchState.CancelID())

        case .fetchGalleriesDone(let result):
            state.loadingState = .idle
            switch result {
            case .success(let (pageNumber, galleries)):
                guard !galleries.isEmpty else {
                    state.loadingState = .failed(.notFound)
                    guard pageNumber.current < pageNumber.maximum else { return .none }
                    return .init(value: .fetchMoreGalleries)
                }
                state.pageNumber = pageNumber
                state.galleries = galleries
                return environment.databaseClient.cacheGalleries(galleries).fireAndForget()
            case .failure(let error):
                state.loadingState = .failed(error)
            }
            return .none

        case .fetchMoreGalleries:
            let pageNumber = state.pageNumber
            guard pageNumber.current + 1 <= pageNumber.maximum,
                  state.footerLoadingState != .loading,
                  let lastID = state.galleries.last?.id
            else { return .none }
            state.footerLoadingState = .loading
            let pageNum = pageNumber.current + 1
            let filter = environment.databaseClient.fetchFilterSynchronously(range: .search)
            return MoreSearchGalleriesRequest(
                keyword: state.lastKeyword, filter: filter, lastID: lastID, pageNum: pageNum
            )
            .effect.map(SearchAction.fetchMoreGalleriesDone).cancellable(id: SearchState.CancelID())

        case .fetchMoreGalleriesDone(let result):
            state.footerLoadingState = .idle
            switch result {
            case .success(let (pageNumber, galleries)):
                state.pageNumber = pageNumber
                state.insertGalleries(galleries)

                var effects: [Effect<SearchAction, Never>] = [
                    environment.databaseClient.cacheGalleries(galleries).fireAndForget()
                ]
                if galleries.isEmpty, pageNumber.current < pageNumber.maximum {
                    effects.append(.init(value: .fetchMoreGalleries))
                } else if !galleries.isEmpty {
                    state.loadingState = .idle
                }
                return .merge(effects)

            case .failure(let error):
                state.footerLoadingState = .failed(error)
            }
            return .none

        case .detail:
            return .none

        case .filters:
            return .none

        case .quickSearch:
            return .none
        }
    }
    .haptics(
        unwrapping: \.route,
        case: /SearchState.Route.quickSearch,
        hapticClient: \.hapticClient
    )
    .haptics(
        unwrapping: \.route,
        case: /SearchState.Route.filters,
        hapticClient: \.hapticClient
    )
    .binding(),
    filtersReducer.pullback(
        state: \.filtersState,
        action: /SearchAction.filters,
        environment: {
            .init(
                databaseClient: $0.databaseClient
            )
        }
    ),
    quickSearchReducer.pullback(
        state: \.quickSearchState,
        action: /SearchAction.quickSearch,
        environment: {
            .init(
                databaseClient: $0.databaseClient
            )
        }
    ),
    detailReducer.pullback(
        state: \.detailState,
        action: /SearchAction.detail,
        environment: {
            .init(
                urlClient: $0.urlClient,
                fileClient: $0.fileClient,
                imageClient: $0.imageClient,
                deviceClient: $0.deviceClient,
                hapticClient: $0.hapticClient,
                cookiesClient: $0.cookiesClient,
                databaseClient: $0.databaseClient,
                clipboardClient: $0.clipboardClient,
                appDelegateClient: $0.appDelegateClient,
                uiApplicationClient: $0.uiApplicationClient
            )
        }
    )
)
