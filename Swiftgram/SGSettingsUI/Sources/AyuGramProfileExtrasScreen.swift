import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import PromptUI
import UndoUI
import SGItemListUI
import GiftViewScreen
import SGSimpleSettings
import SGStrings
import AyuGramProfileExtras

private let ayuNftStarCost: Int64 = 100

private enum AyuProfileExtrasSection: Int32 {
    case intro, nfts, stars, level, number, usernames, bubbles, danger
}

private enum AyuProfileExtrasToggle: Equatable {
    case bubbles
    case showBubbles
    case hideReal
}

private enum AyuProfileExtrasAction: Equatable {
    case addNft
    case reorder
    case addStars(Int64)
    case setStars
    case resetStars
    case number
    case addUsername
    case deleteAll
}

private enum AyuProfileExtrasEntry: ItemListNodeEntry {
    case intro(id: Int, text: String)
    case toggle(id: Int, section: AyuProfileExtrasSection, key: AyuProfileExtrasToggle, symbol: String, title: String, value: Bool, enabled: Bool)
    case levelSlider(id: Int, value: Int32)
    case header(id: Int, section: AyuProfileExtrasSection, text: String)
    case footer(id: Int, section: AyuProfileExtrasSection, text: String)
    case status(id: Int, section: AyuProfileExtrasSection, symbol: String, title: String, label: String)
    case action(id: Int, section: AyuProfileExtrasSection, key: AyuProfileExtrasAction, symbol: String, title: String, enabled: Bool)
    case destructive(id: Int, section: AyuProfileExtrasSection, key: AyuProfileExtrasAction, title: String, enabled: Bool)
    case nft(id: Int, sortIndex: Int, index: Int, title: String, label: String, color: UInt32, isReordering: Bool, enabled: Bool)
    case username(id: Int, index: Int, title: String, enabled: Bool)

    var section: ItemListSectionId {
        switch self {
        case .intro:
            return AyuProfileExtrasSection.intro.rawValue
        case let .toggle(_, section, _, _, _, _, _):
            return section.rawValue
        case .levelSlider:
            return AyuProfileExtrasSection.level.rawValue
        case let .header(_, section, _), let .footer(_, section, _):
            return section.rawValue
        case let .status(_, section, _, _, _):
            return section.rawValue
        case let .action(_, section, _, _, _, _):
            return section.rawValue
        case let .destructive(_, section, _, _, _):
            return section.rawValue
        case .nft:
            return AyuProfileExtrasSection.nfts.rawValue
        case .username:
            return AyuProfileExtrasSection.usernames.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .intro(id, _):
            return id
        case let .toggle(id, _, _, _, _, _, _):
            return id
        case let .levelSlider(id, _):
            return id
        case let .header(id, _, _), let .footer(id, _, _):
            return id
        case let .status(id, _, _, _, _):
            return id
        case let .action(id, _, _, _, _, _):
            return id
        case let .destructive(id, _, _, _, _):
            return id
        case let .nft(id, _, _, _, _, _, _, _):
            return id
        case let .username(id, _, _, _):
            return id
        }
    }

    var sortIndex: Int {
        if case let .nft(_, sortIndex, _, _, _, _, _, _) = self {
            return sortIndex
        }
        return self.stableId
    }

    static func <(lhs: AyuProfileExtrasEntry, rhs: AyuProfileExtrasEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuProfileExtrasArguments
        switch self {
        case let .intro(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .toggle(_, _, key, symbol, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: AyuGramRowColor.blue), title: title, value: value, enabled: enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(key, value)
            })
        case let .levelSlider(_, value):
            return SliderPercentageItem(theme: presentationData.theme, strings: presentationData.strings, value: value, sectionId: self.section, updated: { value in
                arguments.updateLevel(value)
            })
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .status(_, _, symbol, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: AyuGramRowColor.gray), title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .action(_, _, key, symbol, title, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: enabled ? AyuGramRowColor.blue : AyuGramRowColor.gray), title: title, enabled: enabled, label: "", sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.perform(key)
                }
            })
        case let .destructive(_, _, key, title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.perform(key)
                }
            })
        case let .nft(_, _, index, title, label, color, isReordering, enabled):
            return AyuGramFakeNftRowItem(presentationData: presentationData, title: title, subtitle: label, color: color == 0 ? AyuGramRowColor.purple : UIColor(rgb: color), symbol: "gift.fill", isReordering: isReordering, enabled: enabled, sectionId: self.section, action: {
                arguments.openNft(index)
            })
        case let .username(_, index, title, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon("at", color: AyuGramRowColor.teal), title: title, enabled: enabled, label: "", sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.openUsername(index)
                }
            })
        }
    }
}

private final class AyuProfileExtrasArguments {
    let toggle: (AyuProfileExtrasToggle, Bool) -> Void
    let updateLevel: (Int32) -> Void
    let perform: (AyuProfileExtrasAction) -> Void
    let openNft: (Int) -> Void
    let openUsername: (Int) -> Void

    init(toggle: @escaping (AyuProfileExtrasToggle, Bool) -> Void, updateLevel: @escaping (Int32) -> Void, perform: @escaping (AyuProfileExtrasAction) -> Void, openNft: @escaping (Int) -> Void, openUsername: @escaping (Int) -> Void) {
        self.toggle = toggle
        self.updateLevel = updateLevel
        self.perform = perform
        self.openNft = openNft
        self.openUsername = openUsername
    }
}

private final class AyuProfileExtrasModel {
    var entry: AyuGramProfileEntry
    var gifts: [String: StarGift.UniqueGift] = [:]
    var resolving = Set<String>()
    var reordering = false
    private var nftIds: [String: Int] = [:]
    private var nextNftId = 0

    init(entry: AyuGramProfileEntry) {
        self.entry = entry
    }

    func nftStableId(_ nft: AyuGramProfileNft) -> Int {
        if let id = self.nftIds[nft.key] {
            return id
        }
        self.nextNftId += 1
        self.nftIds[nft.key] = self.nextNftId
        return self.nextNftId
    }

    func dropStatusIfMissing() {
        guard let statusSlug = self.entry.statusSlug?.lowercased() else {
            return
        }
        if !self.entry.nfts.contains(where: { $0.slug?.lowercased() == statusSlug }) {
            self.entry.statusSlug = nil
        }
    }
}

private final class AyuProfileExtrasHolder {
    let disposables: DisposableSet
    let model: AyuProfileExtrasModel

    init(model: AyuProfileExtrasModel, disposables: DisposableSet) {
        self.model = model
        self.disposables = disposables
    }

    deinit {
        self.disposables.dispose()
    }
}

private func ayuProfileNftColor(_ gift: StarGift.UniqueGift?) -> UInt32 {
    guard let gift else {
        return 0
    }
    for attribute in gift.attributes {
        if case let .backdrop(_, _, innerColor, _, _, _, _) = attribute {
            return UInt32(bitPattern: innerColor)
        }
    }
    return 0
}

private func ayuFormatStars(_ value: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func ayuProfileExtrasEntries(data: PresentationData, model: AyuProfileExtrasModel) -> [AyuProfileExtrasEntry] {
    let locale = data.strings.baseLanguageCode
    func s(_ key: String) -> String {
        return i18n(key, locale)
    }
    var entries: [AyuProfileExtrasEntry] = []
    entries.append(.intro(id: 0, text: s("Ayu.ProfileExtras.Intro")))

    // NFTs
    let reordering = model.reordering && model.entry.nfts.count > 1
    entries.append(.header(id: 100, section: .nfts, text: s("Ayu.ProfileExtras.NftsSection") + " · \(model.entry.nfts.count)"))
    if !reordering {
        entries.append(.action(id: 101, section: .nfts, key: .addNft, symbol: "plus.circle.fill", title: s("Ayu.ProfileExtras.AddNft"), enabled: true))
    }
    for (index, nft) in model.entry.nfts.enumerated() {
        var title = nft.title
        var gift: StarGift.UniqueGift?
        if let slug = nft.slug, let resolved = model.gifts[slug.lowercased()] {
            title = "\(resolved.title) #\(resolved.number)"
            gift = resolved
        }
        var marks: [String] = []
        if let slug = nft.slug, slug.lowercased() == model.entry.statusSlug?.lowercased() {
            marks.append(s("Ayu.ProfileExtras.Status"))
        }
        if nft.pinned {
            marks.append(s("Ayu.ProfileExtras.Pinned"))
        }
        entries.append(.nft(id: 100000 + model.nftStableId(nft), sortIndex: 200 + index, index: index, title: title, label: marks.joined(separator: " · "), color: ayuProfileNftColor(gift), isReordering: reordering, enabled: true))
    }
    if model.entry.nfts.count > 1 {
        entries.append(.action(id: 280, section: .nfts, key: .reorder, symbol: reordering ? "checkmark.circle.fill" : "arrow.up.arrow.down", title: s(reordering ? "Ayu.ProfileExtras.ReorderDone" : "Ayu.ProfileExtras.Reorder"), enabled: true))
    }
    entries.append(.toggle(id: 290, section: .nfts, key: .hideReal, symbol: "eye.slash.fill", title: s("Ayu.ProfileExtras.HideReal"), value: model.entry.hideReal, enabled: true))
    entries.append(.footer(id: 300, section: .nfts, text: reordering ? s("Ayu.ProfileExtras.ReorderInfo") : s("Ayu.ProfileExtras.NftsInfo") + "\n" + s("Ayu.ProfileExtras.HideRealInfo")))

    // Stars
    entries.append(.header(id: 320, section: .stars, text: s("Ayu.ProfileExtras.StarsSection")))
    entries.append(.status(id: 321, section: .stars, symbol: "star.fill", title: s("Ayu.ProfileExtras.StarsBalance"), label: "⭐️ " + ayuFormatStars(model.entry.stars)))
    entries.append(.action(id: 322, section: .stars, key: .addStars(100), symbol: "plus.circle.fill", title: i18n("Ayu.ProfileExtras.StarsAdd", locale, "100"), enabled: true))
    entries.append(.action(id: 323, section: .stars, key: .addStars(1000), symbol: "plus.circle.fill", title: i18n("Ayu.ProfileExtras.StarsAdd", locale, "1 000"), enabled: true))
    entries.append(.action(id: 324, section: .stars, key: .addStars(10000), symbol: "plus.circle.fill", title: i18n("Ayu.ProfileExtras.StarsAdd", locale, "10 000"), enabled: true))
    entries.append(.action(id: 325, section: .stars, key: .setStars, symbol: "pencil", title: s("Ayu.ProfileExtras.StarsSet"), enabled: true))
    if model.entry.stars > 0 {
        entries.append(.destructive(id: 326, section: .stars, key: .resetStars, title: s("Ayu.ProfileExtras.StarsReset"), enabled: true))
    }
    entries.append(.footer(id: 327, section: .stars, text: s("Ayu.ProfileExtras.StarsInfo")))

    // Level
    entries.append(.header(id: 350, section: .level, text: s("Ayu.ProfileExtras.LevelSection") + " · \(model.entry.level)/100"))
    entries.append(.levelSlider(id: 351, value: model.entry.level))
    entries.append(.footer(id: 352, section: .level, text: s("Ayu.ProfileExtras.LevelInfo")))

    // Number
    entries.append(.header(id: 400, section: .number, text: s("Ayu.ProfileExtras.NumberSection")))
    if let number = model.entry.number {
        entries.append(.action(id: 401, section: .number, key: .number, symbol: "phone.fill", title: AyuGramProfileEntry.formatNumber(number), enabled: true))
    } else {
        entries.append(.action(id: 401, section: .number, key: .number, symbol: "plus.circle.fill", title: s("Ayu.ProfileExtras.ClaimNumber"), enabled: true))
    }
    entries.append(.footer(id: 402, section: .number, text: s("Ayu.ProfileExtras.NumberInfo")))

    // Usernames
    entries.append(.header(id: 450, section: .usernames, text: s("Ayu.ProfileExtras.UsernamesSection") + " · \(model.entry.usernames.count)"))
    entries.append(.action(id: 451, section: .usernames, key: .addUsername, symbol: "plus.circle.fill", title: s("Ayu.ProfileExtras.AddUsername"), enabled: true))
    for (index, name) in model.entry.usernames.enumerated() {
        entries.append(.username(id: 500 + index, index: index, title: "@" + name, enabled: true))
    }
    entries.append(.footer(id: 600, section: .usernames, text: s("Ayu.ProfileExtras.UsernamesInfo")))

    // Bubbles
    entries.append(.header(id: 610, section: .bubbles, text: s("Ayu.ProfileExtras.BubblesSection")))
    entries.append(.toggle(id: 611, section: .bubbles, key: .bubbles, symbol: "bubbles.and.sparkles.fill", title: s("Ayu.ProfileExtras.Bubbles"), value: model.entry.bubbles, enabled: true))
    entries.append(.toggle(id: 612, section: .bubbles, key: .showBubbles, symbol: "eye.fill", title: s("Ayu.ProfileExtras.ShowBubbles"), value: AyuGramProfileRelay.bubblesEnabled, enabled: true))
    entries.append(.footer(id: 613, section: .bubbles, text: s("Ayu.ProfileExtras.BubblesInfo")))

    // Danger
    entries.append(.destructive(id: 700, section: .danger, key: .deleteAll, title: s("Ayu.ProfileExtras.DeleteAll"), enabled: !model.entry.isEmpty))
    entries.append(.footer(id: 701, section: .danger, text: s("Ayu.ProfileExtras.Footer")))
    return entries
}

public func ayuGramProfileExtrasController(context: AccountContext) -> ViewController {
    let accountId = context.account.peerId.id._internalGetInt64Value()
    let initialEntry = AyuGramProfileRelay.shared.localOrEmptyEntry(rawId: accountId)
    let model = AyuProfileExtrasModel(entry: initialEntry)
    let disposables = DisposableSet()
    let holder = AyuProfileExtrasHolder(model: model, disposables: disposables)
    let updates = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    let changed: () -> Void = {
        revision += 1
        updates.set(revision)
    }
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var popToSelfImpl: (() -> Void)?

    func locale() -> String {
        return context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    }

    func apply() {
        model.entry.id = accountId
        AyuGramProfileRelay.shared.setLocalEntry(model.entry)
        changed()
    }

    func showText(_ text: String) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]))
    }

    func toast(_ text: String) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: data, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
    }

    func confirm(text: String, action: String, perform: @escaping () -> Void) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [
            TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: action, action: perform)
        ]))
    }

    func resolveGifts() {
        for nft in model.entry.nfts {
            guard let slug = nft.slug else {
                continue
            }
            let key = slug.lowercased()
            if model.gifts[key] != nil || model.resolving.contains(key) {
                continue
            }
            model.resolving.insert(key)
            disposables.add((AyuGramFakeNftResolver.shared.resolve(engine: context.engine, slug: slug)
            |> deliverOnMainQueue).start(next: { gift in
                model.resolving.remove(key)
                if let gift {
                    model.gifts[key] = gift
                    changed()
                }
            }))
        }
    }

    func moveItem<T>(_ items: inout [T], from index: Int, by offset: Int) {
        let target = index + offset
        guard index >= 0, index < items.count, target >= 0, target < items.count else {
            return
        }
        let item = items.remove(at: index)
        items.insert(item, at: target)
    }

    func addUsername(_ value: String) {
        guard let name = AyuGramProfileEntry.normalizeUsername(value) else {
            showText(i18n("Ayu.ProfileExtras.Error.BadUsername", locale()))
            return
        }
        if model.entry.usernames.contains(name) {
            return
        }
        model.entry.usernames.append(name)
        apply()
    }

    func setNumber(_ value: String) {
        guard let number = AyuGramProfileEntry.normalizeNumber(value) else {
            showText(i18n("Ayu.ProfileExtras.Error.BadNumber", locale()))
            return
        }
        model.entry.number = number
        apply()
    }

    func askNumber() {
        presentControllerImpl?(promptController(context: context, text: i18n("Ayu.ProfileExtras.NumberPrompt", locale()), value: model.entry.number.map(AyuGramProfileEntry.formatNumber) ?? "+", placeholder: "+1 234 567 8900", characterLimit: 24, apply: { value in
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                setNumber(value)
            }
        }))
    }

    func askStars() {
        presentControllerImpl?(promptController(context: context, text: i18n("Ayu.ProfileExtras.StarsPrompt", locale()), value: "\(model.entry.stars)", placeholder: "0", characterLimit: 12, apply: { value in
            guard let value else {
                return
            }
            let digits = String(value.unicodeScalars.filter { $0 >= "0" && $0 <= "9" })
            let amount = Int64(digits) ?? 0
            model.entry.stars = AyuGramProfileEntry.clampStars(amount)
            apply()
        }))
    }

    func buyGift(_ gift: StarGift.UniqueGift) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        if !AyuGramProfileNft.isValidSlug(gift.slug) {
            showText(i18n("Ayu.ProfileExtras.Error.NftNotFound", locale))
            return
        }
        if model.entry.nfts.contains(where: { $0.slug?.lowercased() == gift.slug.lowercased() }) {
            showText(i18n("Ayu.ProfileExtras.Error.NftExists", locale))
            return
        }
        let title = "\(gift.title) #\(gift.number)"
        presentControllerImpl?(textAlertController(context: context, title: nil, text: i18n("Ayu.ProfileExtras.BuyConfirm", locale, title, ayuFormatStars(ayuNftStarCost)), actions: [
            TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: i18n("Ayu.ProfileExtras.BuyAction", locale), action: {
                if model.entry.stars < ayuNftStarCost {
                    showText(i18n("Ayu.ProfileExtras.NotEnoughStars", locale))
                    return
                }
                model.entry.stars = AyuGramProfileEntry.clampStars(model.entry.stars - ayuNftStarCost)
                model.gifts[gift.slug.lowercased()] = gift
                let pinned = model.entry.nfts.filter { $0.pinned }.count < 6
                model.entry.nfts.append(AyuGramProfileNft(slug: gift.slug, pinned: pinned))
                apply()
                toast(i18n("Ayu.ProfileExtras.Bought", locale, title))
                popToSelfImpl?()
            })
        ]))
    }

    let arguments = AyuProfileExtrasArguments(toggle: { key, value in
        switch key {
        case .bubbles:
            model.entry.bubbles = value
            apply()
        case .showBubbles:
            AyuGramProfileRelay.bubblesEnabled = value
            changed()
        case .hideReal:
            model.entry.hideReal = value
            apply()
        }
    }, updateLevel: { value in
        model.entry.level = AyuGramProfileEntry.clampLevel(value)
        apply()
    }, perform: { action in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        switch action {
        case .addNft:
            pushControllerImpl?(ayuGramNftSearchController(context: context, onPick: { gift in
                buyGift(gift)
            }))
        case .reorder:
            model.reordering = !model.reordering
            changed()
        case let .addStars(amount):
            model.entry.stars = AyuGramProfileEntry.clampStars(model.entry.stars + amount)
            apply()
        case .setStars:
            askStars()
        case .resetStars:
            confirm(text: i18n("Ayu.ProfileExtras.StarsResetConfirm", locale), action: i18n("Ayu.ProfileExtras.StarsReset", locale), perform: {
                model.entry.stars = 0
                apply()
            })
        case .number:
            let sheet = ActionSheetController(presentationData: data)
            var numberItems: [ActionSheetItem] = []
            if let number = model.entry.number {
                numberItems.append(ActionSheetTextItem(title: AyuGramProfileEntry.formatNumber(number), parseMarkdown: false))
                numberItems.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.ChangeNumber", locale), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    askNumber()
                }))
                numberItems.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.ClearNumber", locale), color: .destructive, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    model.entry.number = nil
                    apply()
                }))
            } else {
                numberItems.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.EnterNumber", locale), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    askNumber()
                }))
                numberItems.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.RandomNumber", locale), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    setNumber(ayuGramRandomAnonymousNumber())
                }))
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: numberItems),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })])
            ])
            presentControllerImpl?(sheet)
        case .addUsername:
            presentControllerImpl?(promptController(context: context, text: i18n("Ayu.ProfileExtras.AddUsernamePrompt", locale), value: "", placeholder: "@username", characterLimit: 40, apply: { value in
                if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    addUsername(value)
                }
            }))
        case .deleteAll:
            confirm(text: i18n("Ayu.ProfileExtras.DeleteAllConfirm", locale), action: i18n("Ayu.ProfileExtras.DeleteAll", locale), perform: {
                model.entry = AyuGramProfileEntry(id: accountId, nfts: [], usernames: [], background: nil, bubbles: false, updatedAt: Date().timeIntervalSince1970)
                AyuGramProfileRelay.shared.clearLocalEntry(rawId: accountId)
                changed()
            })
        }
    }, openNft: { index in
        guard index >= 0, index < model.entry.nfts.count else {
            return
        }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        let nft = model.entry.nfts[index]
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = []
        var title = nft.title
        var previewGift: StarGift.UniqueGift?
        if let slug = nft.slug, let gift = model.gifts[slug.lowercased()] {
            title = "\(gift.title) #\(gift.number)"
            previewGift = gift
        }
        items.append(ActionSheetTextItem(title: title, parseMarkdown: false))
        if let previewGift {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.Preview", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                pushControllerImpl?(ayuGramFakeNftViewScreen(context: context, gift: previewGift))
            }))
        }
        items.append(ActionSheetButtonItem(title: i18n(nft.pinned ? "Ayu.ProfileExtras.Unpin" : "Ayu.ProfileExtras.Pin", locale), color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            guard index < model.entry.nfts.count else {
                return
            }
            model.entry.nfts[index] = model.entry.nfts[index].withPinned(!model.entry.nfts[index].pinned)
            apply()
        }))
        if let slug = nft.slug {
            let isStatus = slug.lowercased() == model.entry.statusSlug?.lowercased()
            items.append(ActionSheetButtonItem(title: i18n(isStatus ? "Ayu.ProfileExtras.RemoveStatus" : "Ayu.ProfileExtras.SetStatus", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                model.entry.statusSlug = isStatus ? nil : slug
                apply()
            }))
        }
        if index > 0 {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.MoveUp", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                moveItem(&model.entry.nfts, from: index, by: -1)
                apply()
            }))
        }
        if index < model.entry.nfts.count - 1 {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.MoveDown", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                moveItem(&model.entry.nfts, from: index, by: 1)
                apply()
            }))
        }
        items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.Delete", locale), color: .destructive, action: { [weak sheet] in
            sheet?.dismissAnimated()
            guard index < model.entry.nfts.count else {
                return
            }
            model.entry.nfts.remove(at: index)
            model.dropStatusIfMissing()
            apply()
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(sheet)
    }, openUsername: { index in
        guard index >= 0, index < model.entry.usernames.count else {
            return
        }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = []
        items.append(ActionSheetTextItem(title: "@" + model.entry.usernames[index], parseMarkdown: false))
        if index > 0 {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.MoveUp", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                moveItem(&model.entry.usernames, from: index, by: -1)
                apply()
            }))
        }
        if index < model.entry.usernames.count - 1 {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.MoveDown", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                moveItem(&model.entry.usernames, from: index, by: 1)
                apply()
            }))
        }
        items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.Delete", locale), color: .destructive, action: { [weak sheet] in
            sheet?.dismissAnimated()
            guard index < model.entry.usernames.count else {
                return
            }
            model.entry.usernames.remove(at: index)
            apply()
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(sheet)
    })

    let signal = combineLatest(context.sharedContext.presentationData, updates.get())
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, AyuProfileExtrasArguments)) in
        let locale = data.strings.baseLanguageCode
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(i18n("Ayu.ProfileExtras.Title", locale)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(data), entries: ayuProfileExtrasEntries(data: data, model: model), style: .blocks, animateChanges: true)
        return (state, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.didDisappear = { _ in
        let _ = holder
    }
    presentControllerImpl = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    popToSelfImpl = { [weak controller] in
        guard let controller, let navigationController = controller.navigationController as? NavigationController else {
            return
        }
        let _ = navigationController.popToViewController(controller, animated: true)
    }
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [AyuProfileExtrasEntry]) -> Signal<Bool, NoError> in
        guard fromIndex >= 0, fromIndex < entries.count, case let .nft(_, _, fromNft, _, _, _, _, _) = entries[fromIndex] else {
            return .single(false)
        }
        let target: Int
        if toIndex >= 0, toIndex < entries.count, case let .nft(_, _, index, _, _, _, _, _) = entries[toIndex] {
            target = index
        } else if toIndex >= 0, toIndex < entries.count, entries[toIndex] < entries[fromIndex] {
            target = 0
        } else {
            target = model.entry.nfts.count - 1
        }
        guard fromNft >= 0, fromNft < model.entry.nfts.count, target >= 0, target < model.entry.nfts.count, target != fromNft else {
            return .single(false)
        }
        let item = model.entry.nfts.remove(at: fromNft)
        model.entry.nfts.insert(item, at: target)
        apply()
        return .single(true)
    })
    resolveGifts()
    return controller
}
