/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

protocol TabManagerDelegate {
    func didSelectedTabChange(selected: Browser?, previous: Browser?)
    func didCreateTab(tab: Browser)
    func didAddTab(tab: Browser)
    func didRemoveTab(tab: Browser)
}

class TabManager {
    var delegate: TabManagerDelegate? = nil

    private var tabs: [Browser] = []
    private var selectedIndex = -1

    var count: Int {
        return tabs.count
    }

    var selectedTab: Browser? {
        if !(0..<count ~= selectedIndex) {
            return nil
        }

        return tabs[selectedIndex]
    }

    func getTab(index: Int) -> Browser {
        return tabs[index]
    }

    func selectTab(tab: Browser?) {
        if selectedTab === tab {
            return
        }

        let previous = selectedTab

        selectedIndex = -1
        for i in 0..<count {
            if tabs[i] === tab {
                selectedIndex = i
                break
            }
        }

        assert(tab === selectedTab, "Expected tab is selected")

        delegate?.didSelectedTabChange(tab, previous: previous)
    }

    func addTab() -> Browser {
        let tab = Browser()
        delegate?.didCreateTab(tab)
        tabs.append(tab)
        delegate?.didAddTab(tab)
        selectTab(tab)
        return tab
    }

    func removeTab(tab: Browser) {
        // If the removed tab was selected, find the new tab to select.
        if tab === selectedTab {
            let index = getIndex(tab)
            if index + 1 < count {
                selectTab(tabs[index + 1])
            } else if index - 1 >= 0 {
                selectTab(tabs[index - 1])
            } else {
                assert(count == 1, "Removing last tab")
                selectTab(nil)
            }
        }

        let prevCount = count
        for i in 0..<count {
            if tabs[i] === tab {
                tabs.removeAtIndex(i)
                break
            }
        }
        assert(count == prevCount - 1, "Tab removed")

        delegate?.didRemoveTab(tab)
    }

    private func getIndex(tab: Browser) -> Int {
        for i in 0..<count {
            if tabs[i] === tab {
                return i
            }
        }
        
        assertionFailure("Tab not in tabs list")
    }
}