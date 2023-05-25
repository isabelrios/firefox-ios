// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Shared
import MozillaAppServices

class NimbusOnboardingFeatureLayer: NimbusOnboardingFeatureLayerProtocol {
    private var helperUtility: NimbusMessagingHelperUtilityProtocol

    init(with helperUtility: NimbusMessagingHelperUtilityProtocol = NimbusMessagingHelperUtility()) {
        self.helperUtility = helperUtility
    }

    /// Fetches an ``OnboardingViewModel`` from ``FxNimbus`` configuration.
    ///
    /// - Parameter nimbus: The ``FxNimbus/shared`` instance.
    /// - Returns: An ``OnboardingViewModel`` to be used in the onboarding.
    func getOnboardingModel(
        for onboardingType: OnboardingType,
        from nimbus: FxNimbus = FxNimbus.shared
    ) -> OnboardingViewModel {
        let framework = nimbus.features.onboardingFrameworkFeature.value()

        return OnboardingViewModel(
            cards: getOrderedOnboardingCards(
                for: onboardingType,
                from: framework.cards,
                using: framework.cardOrdering,
                withConditions: framework.conditions),
            isDismissable: framework.dismissable)
    }

    /// Will sort onboarding cards according to specified order in the
    /// Nimbus configuration. If the names of cards and the names in the card
    /// order array don't match, these cards will simply not be shown in onboarding.
    ///
    /// - Parameters:
    ///   - cardData: Card data from ``FxNimbus/shared``
    ///   - cardOrder: Card order from ``FxNimbus/shared``
    ///   - conditionTable: Condition table from ``FxNimbus/shared``
    /// - Returns: Card data converted to ``OnboardingCardInfoModel`` and ordered.
    private func getOrderedOnboardingCards(
        for onboardingType: OnboardingType,
        from cardData: [NimbusOnboardingCardData],
        using cardOrder: [String],
        withConditions conditionTable: [String: String]
    ) -> [OnboardingCardInfoModel] {
        let cards = getOnboardingCards(from: cardData, withConditions: conditionTable)

        // Sorting the cards this way, instead of a simple sort, to account for human
        // error in the order naming. If a card name is misspelled, it will be ignored
        // and not included in the list of cards.
        return cardOrder
            .compactMap { cardName in
                if let card = cards.first(where: { $0.name == cardName }) {
                    return card
                }

                return nil
            }
            .filter { $0.type == onboardingType }
            .enumerated()
            .map { index, card in
                // We have to update the a11yIdRoot using the correct order of the cards
                return OnboardingCardInfoModel(
                    name: card.name,
                    title: card.title,
                    body: card.body,
                    link: card.link,
                    buttons: card.buttons,
                    type: card.type,
                    a11yIdRoot: "\(card.a11yIdRoot)\(index)",
                    imageID: card.imageID)
            }
    }

    /// Converts ``NimbusOnboardingCardData`` to ``OnboardingCardInfoModel``
    /// to be used in the onboarding process.
    ///
    /// All cards must have valid formats and data. For example, a card with no
    /// buttons, will be omitted from the returned cards.
    ///
    /// For designer's flexibility, the `title` and `body` property are formatted
    /// with the app's name, in case we need to use localized strings that include
    /// the app name. Testing accounts for this, ensuring that the string, when
    /// there is no placeholder, is as expected.
    ///
    /// - Parameters
    ///   - cardData: Card data from ``FxNimbus/shared``
    ///   - conditionTable: Condition table from ``FxNimbus/shared``
    /// - Returns: An array of viable ``OnboardingCardInfoModel``
    private func getOnboardingCards(
        from cardData: [NimbusOnboardingCardData],
        withConditions conditionTable: [String: String]
    ) -> [OnboardingCardInfoModel] {
        let a11yOnboarding = AccessibilityIdentifiers.Onboarding.onboarding
        let a11yUpgrade = AccessibilityIdentifiers.Upgrade.upgrade
        var jexlCache = [String: Bool]()

        // If `NimbusMessagingHelper` creation fails, we cannot continue with
        // evaluating card triggers based on their JEXL prerequisites.
        // Therefore, we return an empty array.
        guard let helper = helperUtility.createNimbusMessagingHelper() else { return [] }

        return cardData.compactMap { card in
            if cardIsValid(with: card, using: conditionTable, jexlCache: &jexlCache, and: helper) {
                return OnboardingCardInfoModel(
                    name: card.name,
                    title: String(format: card.title, AppName.shortName.rawValue),
                    body: String(format: card.body, AppName.shortName.rawValue),
                    link: getOnboardingLink(from: card.link),
                    buttons: getOnboardingCardButtons(from: card.buttons),
                    type: card.type,
                    a11yIdRoot: card.type == .freshInstall ? a11yOnboarding : a11yUpgrade,
                    imageID: getOnboardingImageID(from: card.image))
            }

            return nil
        }
    }

    private func cardIsValid(
        with card: NimbusOnboardingCardData,
        using conditionTable: [String: String],
        jexlCache: inout [String: Bool],
        and helper: NimbusMessagingHelperProtocol
    ) -> Bool {
        // Basically, check if prerequisites are met and if no disqualifers are met
        return verifyConditionEligibility(from: card.prerequisites,
                                          checkingAgainst: conditionTable,
                                          using: &jexlCache,
                                          and: helper)
            && !verifyConditionEligibility(from: card.disqualifiers,
                                           checkingAgainst: conditionTable,
                                           using: &jexlCache,
                                           and: helper)
    }

    private func verifyConditionEligibility(
        from cardConditions: [String],
        checkingAgainst conditionLookupTable: [String: String],
        using jexlCache: inout [String: Bool],
        and helper: NimbusMessagingHelperProtocol
    ) -> Bool {
        // Make sure conditions exist and have a value, and that the number
        // of valid conditions matches the number of conditions on the card's
        // respective prerequisite or disqualifier table. If these mismatch,
        // that means a card contains a condition that's not in the feature
        // conditions lookup table. JEXLS can only be evaluated on
        // supported conditions. Otherwise, consider the card invalid.
        let conditions = cardConditions.compactMap({ conditionLookupTable[$0] })
        guard conditions.count == cardConditions.count else { return false }

        do {
            return try NimbusMessagingEvaluationUtility().doesObjectMeet(
                verificationRequirements: conditions,
                using: helper,
                and: &jexlCache)
        } catch {
            return false
        }
    }

    /// Returns an optional array of ``OnboardingButtonInfoModel`` given the data.
    /// A card is not viable without buttons.
    private func getOnboardingCardButtons(from cardButtons: NimbusOnboardingButtons) -> OnboardingButtons {
        var secondButton: OnboardingButtonInfoModel?
        if let secondary = cardButtons.secondary {
            secondButton = OnboardingButtonInfoModel(title: secondary.title,
                                                     action: secondary.action)
        }

        return OnboardingButtons(
            primary: OnboardingButtonInfoModel(
                title: cardButtons.primary.title,
                action: cardButtons.primary.action),
            secondary: secondButton)
    }

    /// Returns an optional ``OnboardingLinkInfoModel``, if one is provided. This will be
    /// used by the application in the privacy policy link.
    private func getOnboardingLink(from cardLink: NimbusOnboardingLink?) -> OnboardingLinkInfoModel? {
        guard let cardLink = cardLink,
              let url = URL(string: cardLink.url)
        else { return nil }

        return OnboardingLinkInfoModel(title: cardLink.title, url: url)
    }

    /// Translates a nimbus image ID for onboarding to an ``ImageIdentifiers`` based id
    /// that corresponds to an app resource.
    ///
    /// In the case that an unknown image identifier is entered into experimenter, the
    /// Nimbus will return the default image identifier, in this case,
    /// ``NimbusOnboardingImages/welcomeGlobe``
    ///
    /// - Parameter identifier: The given identifier for an image from ``FxNimbus/shared``
    /// - Returns: A string to be used as a proper identifier in the onboarding
    private func getOnboardingImageID(from identifier: NimbusOnboardingImages) -> String {
        switch identifier {
        case .welcomeGlobe: return ImageIdentifiers.onboardingWelcomev106
        case .syncDevices: return ImageIdentifiers.onboardingSyncv106
        case .notifications: return ImageIdentifiers.onboardingNotification
        }
    }
}
