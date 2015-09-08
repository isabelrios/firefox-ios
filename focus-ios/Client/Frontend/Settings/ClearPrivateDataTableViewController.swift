/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

private let SectionToggles = 0
private let SectionButton = 1
private let NumberOfSections = 2
private let SectionHeaderIdentifier = "SectionHeaderIdentifier"
private let HeaderHeight: CGFloat = 44

class ClearPrivateDataTableViewController: UITableViewController {
    private var clearButton: UITableViewCell?

    var profile: Profile!
    var tabManager: TabManager!

    private lazy var clearables: [Clearable] = {
        return [
            HistoryClearable(profile: self.profile),
            CacheClearable(tabManager: self.tabManager),
            CookiesClearable(tabManager: self.tabManager),
            SiteDataClearable(tabManager: self.tabManager),
            PasswordsClearable(profile: self.profile),
        ]
    }()

    private lazy var toggles: [Bool] = {
        return [Bool](count: self.clearables.count, repeatedValue: true)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Clear Private Data", comment: "Navigation title for clearing private data.")

        tableView.registerClass(SettingsTableSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderIdentifier)

        tableView.separatorColor = UIConstants.TableViewSeparatorColor
        tableView.backgroundColor = UIConstants.TableViewHeaderBackgroundColor

        tableView.tableFooterView = UIView()
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: UITableViewCellStyle.Default, reuseIdentifier: nil)

        if indexPath.section == SectionToggles {
            cell.textLabel?.text = clearables[indexPath.item].label
            let control = UISwitch()
            control.onTintColor = UIConstants.ControlTintColor
            control.addTarget(self, action: "switchValueChanged:", forControlEvents: UIControlEvents.ValueChanged)
            control.on = true
            cell.accessoryView = control
            cell.selectionStyle = .None
            control.tag = indexPath.item
        } else {
            assert(indexPath.section == SectionButton)
            cell.textLabel?.text = NSLocalizedString("Clear Private Data", comment: "Button in settings that clears private data for the selected items.")
            cell.textLabel?.textAlignment = NSTextAlignment.Center
            cell.textLabel?.textColor = UIConstants.DestructiveRed
            clearButton = cell
        }

        // Make the separator line fill the entire table width.
        cell.separatorInset = UIEdgeInsetsZero

        return cell
    }

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return NumberOfSections
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == SectionToggles {
            return clearables.count
        }

        assert(section == SectionButton)
        return 1
    }

    override func tableView(tableView: UITableView, shouldHighlightRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        guard indexPath.section == SectionButton else { return false }

        // Highlight the button only if at least one clearable is enabled.
        return toggles.contains(true)
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        guard indexPath.section == SectionButton else { return }

        clearables
            .enumerate()
            .filter { (i, _) in toggles[i] }
            .map { (_, clearable) in clearable.clear() }
            .allSucceed()
            .upon { result in
                // TODO: Need some kind of success/failure UI. Bug 1202093.
                if result.isSuccess {
                    print("Private data cleared")
                } else {
                    print("Error clearing private data")
                    assertionFailure("\(result.failureValue)")
                }

                dispatch_async(dispatch_get_main_queue()) {
                    self.navigationController?.popViewControllerAnimated(true)
                }
        }
    }

    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return tableView.dequeueReusableHeaderFooterViewWithIdentifier(SectionHeaderIdentifier) as! SettingsTableSectionHeaderView
    }

    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return HeaderHeight
    }

    @objc func switchValueChanged(toggle: UISwitch) {
        toggles[toggle.tag] = toggle.on

        // Dim the clear button if no clearables are selected.
        clearButton?.textLabel?.textColor = toggles.contains(true) ? UIConstants.DestructiveRed : UIColor.lightGrayColor()
    }
}