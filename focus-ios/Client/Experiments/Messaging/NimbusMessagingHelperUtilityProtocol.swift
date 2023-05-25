// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Common
import Shared
import MozillaAppServices

protocol NimbusMessagingHelperUtilityProtocol {
    func createNimbusMessagingHelper() -> NimbusMessagingHelperProtocol?
    init(logger: Logger)
}

/// Responsible for creating a ``NimbusMessagingHelper`` with appropriate context.
class NimbusMessagingHelperUtility: NimbusMessagingHelperUtilityProtocol {
    private var logger: Logger

    required init(logger: Logger = DefaultLogger.shared) {
        self.logger = logger
    }

    func createNimbusMessagingHelper() -> NimbusMessagingHelperProtocol? {
        let contextProvider = GleanPlumbContextProvider()

        do {
            // Attempt to create our message helper
            return try Experiments.shared.createMessageHelper(
                additionalContext: contextProvider.createAdditionalDeviceContext())
        } catch {
            // If we're here, then all of Messaging is in limbo!
            // Report the error and let the caller handle the error.
            logger.log("NimbusMessagingHelper could not be created! With error \(error)",
                       level: .warning,
                       category: .experiments)
            return nil
        }
    }
}
