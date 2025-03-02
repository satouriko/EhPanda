//
//  FiltersStore.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/09.
//

import ComposableArchitecture

struct FiltersState: Equatable {
    enum Route {
        case resetFilters
    }
    enum FocusedBound {
        case lower
        case upper
    }

    @BindableState var route: Route?
    @BindableState var filterRange: FilterRange = .search
    @BindableState var focusedBound: FocusedBound?

    @BindableState var searchFilter = Filter()
    @BindableState var globalFilter = Filter()
    @BindableState var watchedFilter = Filter()
}

enum FiltersAction: BindableAction {
    case binding(BindingAction<FiltersState>)
    case setNavigation(FiltersState.Route?)
    case onTextFieldSubmitted

    case syncFilter(FilterRange)
    case resetFilters
    case fetchFilters
    case fetchFiltersDone(AppEnv)
}

struct FiltersEnvironment {
    let databaseClient: DatabaseClient
}

let filtersReducer = Reducer<FiltersState, FiltersAction, FiltersEnvironment> { state, action, environment in
    switch action {
    case .binding(\.$searchFilter):
        state.searchFilter.fixInvalidData()
        return .init(value: .syncFilter(.search))

    case .binding(\.$globalFilter):
        state.globalFilter.fixInvalidData()
        return .init(value: .syncFilter(.global))

    case .binding(\.$watchedFilter):
        state.watchedFilter.fixInvalidData()
        return .init(value: .syncFilter(.watched))

    case .binding:
        return .none

    case .setNavigation(let route):
        state.route = route
        return .none

    case .onTextFieldSubmitted:
        switch state.focusedBound {
        case .lower:
            state.focusedBound = .upper
        case .upper:
            state.focusedBound = nil
        default:
            break
        }
        return .none

    case .syncFilter(let range):
        let filter: Filter
        switch range {
        case .search:
            filter = state.searchFilter
        case .global:
            filter = state.globalFilter
        case .watched:
            filter = state.watchedFilter
        }
        return environment.databaseClient.updateFilter(filter, range: range).fireAndForget()

    case .resetFilters:
        switch state.filterRange {
        case .search:
            state.searchFilter = .init()
            return .init(value: .syncFilter(.search))
        case .global:
            state.globalFilter = .init()
            return .init(value: .syncFilter(.global))
        case .watched:
            state.watchedFilter = .init()
            return .init(value: .syncFilter(.watched))
        }

    case .fetchFilters:
        return environment.databaseClient.fetchAppEnv().map(FiltersAction.fetchFiltersDone)

    case .fetchFiltersDone(let appEnv):
        state.searchFilter = appEnv.searchFilter
        state.globalFilter = appEnv.globalFilter
        state.watchedFilter = appEnv.watchedFilter
        return .none
    }
}
.binding()
