// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux

struct AppState: StateType {
    let activeScreens: ActiveScreensState

    static let reducer: Reducer<Self> = { state, action in
        AppState(activeScreens: ActiveScreensState.reducer(state.activeScreens, action))
    }

    func screenState<State>(for screen: AppScreen) -> State? {
        return activeScreens.screens
            .compactMap {
                switch ($0, screen) {
                case (.themeSettings(let state), .themeSettings): return state as? State
                }
            }
            .first
    }
}

extension AppState {
    init() {
        activeScreens = ActiveScreensState()
    }
}
