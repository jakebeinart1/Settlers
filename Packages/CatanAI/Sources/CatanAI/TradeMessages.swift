import Foundation
import CatanEngine

/// Flavor text a bot attaches to a trade action - the pitch when it
/// initiates an offer, and the line it fires back when it accepts or
/// rejects one of the human's. Purely cosmetic (never affects
/// `TradeHeuristics.evaluate`'s actual accept/reject math) and entirely
/// deterministic per offer: the same `TradeOffer.id` always yields the same
/// line, so a message doesn't change across re-renders of a still-pending
/// offer, but a fresh offer samples a different line from the pool.
///
/// Keyed by `Empire` rather than `BotPersonality` - the ask was for bots to
/// sound like the culture they represent (a Roman legion vs. a Norse raiding
/// party), not like a trait slider. `Empire`'s raw values deliberately mirror
/// `Civilization`'s cases 1:1 (the app-layer enum this package can't import,
/// being UI-agnostic) so the call site is a trivial `Empire(rawValue:
/// civilization.rawValue)!`.
///
/// Every line in every pool is capped at 38 characters (see
/// `TradeMessagesTests.everyLineFitsTheIncomingCardsCharacterBudget`) - the
/// views render these at full, readable size rather than shrinking text to
/// fit, so the length budget lives in the content instead of a
/// `minimumScaleFactor` bailout.
public enum TradeMessages {
    public enum Empire: String, CaseIterable, Sendable {
        case medieval
        case greece
        case egypt
        case aztec
        case columbia
        case rome
        case japan
        case norse
    }

    /// The line a bot sends along with an offer it's initiating.
    public static func pitch(offer: TradeOffer, empire: Empire) -> String {
        let pool = pitchPool(for: empire)
        return pool[stableIndex(for: offer.id, count: pool.count)]
    }

    /// The line a bot sends back accepting or rejecting a human-proposed
    /// offer.
    public static func response(offer: TradeOffer, empire: Empire, accepted: Bool) -> String {
        let pool = responsePool(for: empire, accepted: accepted)
        return pool[stableIndex(for: offer.id, count: pool.count)]
    }

    /// A hash over the UUID's own bytes rather than `UUID.hashValue` -
    /// `Hashable`'s hash seed is randomized per process launch, so the same
    /// offer could sample a different line on every app run even though
    /// nothing about the offer changed. Summing the raw bytes is stable
    /// across launches, not just within one.
    private static func stableIndex(for id: UUID, count: Int) -> Int {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let sum = bytes.reduce(0) { $0 + Int($1) }
        return sum % count
    }

    // MARK: - Pools

    static func pitchPool(for empire: Empire) -> [String] {
        switch empire {
        case .medieval: return medievalPitch
        case .greece: return greecePitch
        case .egypt: return egyptPitch
        case .aztec: return aztecPitch
        case .columbia: return columbiaPitch
        case .rome: return romePitch
        case .japan: return japanPitch
        case .norse: return norsePitch
        }
    }

    static func responsePool(for empire: Empire, accepted: Bool) -> [String] {
        switch (empire, accepted) {
        case (.medieval, true): return medievalAccept
        case (.medieval, false): return medievalReject
        case (.greece, true): return greeceAccept
        case (.greece, false): return greeceReject
        case (.egypt, true): return egyptAccept
        case (.egypt, false): return egyptReject
        case (.aztec, true): return aztecAccept
        case (.aztec, false): return aztecReject
        case (.columbia, true): return columbiaAccept
        case (.columbia, false): return columbiaReject
        case (.rome, true): return romeAccept
        case (.rome, false): return romeReject
        case (.japan, true): return japanAccept
        case (.japan, false): return japanReject
        case (.norse, true): return norseAccept
        case (.norse, false): return norseReject
        }
    }

    // MARK: - Britannia (Charlemagne)

    private static let medievalPitch = [
        "Trade fair, or lose your henhouse.",
        "A knight proposes, not begs.",
        "Take it before I knight myself.",
        "Sworn on my sword. Deal?",
        "My blacksmith approves this trade.",
        "Chivalry's dead. This deal isn't.",
        "Sign here, peasant.",
        "This deal has a real edge to it.",
        "Grant this boon, keep your keep.",
        "A round table trade, sharp and fair.",
    ]
    private static let medievalAccept = [
        "Done. My liege will be pleased.",
        "Deal - don't make me regret it.",
        "Fine, the round table approves.",
        "Accepted, before my knights riot.",
        "You've earned my seal.",
        "Aye, even kings need bargains.",
        "Take the deal, quick.",
        "Sworn and sealed. Don't ruin it.",
    ]
    private static let medievalReject = [
        "No. My jester offers better terms.",
        "Denied. Try the tavern instead.",
        "That wouldn't buy a rusty helm.",
        "Not while I guard my castle.",
        "My knights would laugh at that.",
        "Refused. Go win a war first.",
        "My horse turned its nose up.",
        "Even peasants trade better.",
    ]

    // MARK: - Greece (Alexander)

    private static let greecePitch = [
        "Even Zeus approves this trade.",
        "Accept, or face my phalanx.",
        "This deal's sharper than my abs.",
        "Sparta had no comeback either.",
        "My philosophers approve. Trust them.",
        "A gift from Olympus, practically.",
        "Trade, or meet my 300 friends.",
        "Golden ratio of trades. Accept.",
        "I conquered worlds for less.",
        "The oracle foresaw your yes.",
    ]
    private static let greeceAccept = [
        "Accepted - the gods smile.",
        "Deal. Even Achilles agrees.",
        "Fine, by my laurel, this works.",
        "Yes - my phalanx approves.",
        "Take it, I've conquered worse.",
        "Agreed, before Sparta hears.",
        "Done. The Parthenon approves.",
        "Accepted - go be legendary.",
    ]
    private static let greeceReject = [
        "No. My horse has better taste.",
        "Denied - the oracle warned me.",
        "Insults my abs and ancestors.",
        "Rejected. Try the agora.",
        "My phalanx won't break for that.",
        "Not while Olympus watches.",
        "That's a tragedy, and I'd know.",
        "Read some philosophy first.",
    ]

    // MARK: - Egypt (Ramesses)

    private static let egyptPitch = [
        "Pyramids weren't built on bad deals.",
        "This deal's eternal. Take it.",
        "My scarabs approve. Rare, that.",
        "The Nile floods on time. This too.",
        "A pharaoh doesn't ask twice.",
        "Carved in stone, unlike your excuses.",
        "Take it, or face the locusts.",
        "My priests read the stars. It's yes.",
        "Worth more than my second obelisk.",
        "Refuse and meet my curse.",
    ]
    private static let egyptAccept = [
        "Accepted - the Nile is pleased.",
        "Deal. Even my mummy approves.",
        "Fine, by the sun god's light.",
        "Yes - onto the scrolls it goes.",
        "Done. My pyramid crew celebrates.",
        "Accepted before the flood.",
        "The sphinx cracked a smile.",
        "Take it. Feeling generous today.",
    ]
    private static let egyptReject = [
        "No. The sphinx has better riddles.",
        "My scarabs recoiled in horror.",
        "Wouldn't buy a canopic jar.",
        "Rejected. Bother the tax men.",
        "Not while my pyramid's short a brick.",
        "My priests cursed that offer.",
        "Insults my ancestors and sandals.",
        "Come back when the stars align.",
    ]

    // MARK: - Aztec (Moctezuma)

    private static let aztecPitch = [
        "The sun god demands this trade.",
        "Accept, or my jaguars get restless.",
        "Sharper than obsidian. Take it.",
        "My priests blessed this offer.",
        "Trade now, before the eclipse.",
        "This is a gift. Gifts expire.",
        "My empire wasn't built on bad deals.",
        "The stars favor this trade.",
        "Explain your refusal to the sun.",
        "The calendar stone says yes.",
    ]
    private static let aztecAccept = [
        "Accepted - the sun god is pleased.",
        "Deal. My warriors stand down.",
        "Fine, by obsidian and ash.",
        "Yes - the temple approves.",
        "Done. The eclipse looked kind.",
        "Agreed, before my warriors riot.",
        "Today's a good day. Take it.",
        "Accepted - earn the sun's gaze.",
    ]
    private static let aztecReject = [
        "No. My warriors would eat that.",
        "The sun god turned his back.",
        "Wouldn't please a single priest.",
        "Rejected. Make offerings elsewhere.",
        "Not while the eclipse favors me.",
        "My blades are sharper than that.",
        "Insults the calendar stone.",
        "Come back when stars align.",
    ]

    // MARK: - Columbia (Washington)

    private static let columbiaPitch = [
        "Take it, or I cross your river next.",
        "Cleaner than a cherry tree story.",
        "Liberty and a fair trade. Deal?",
        "My muskets are clean. So's this.",
        "Take it before the frontier riots.",
        "More stars in this than my flag.",
        "I didn't cross a river for junk.",
        "Give me liberty, or a better offer.",
        "The eagle's watching. Make it proud.",
        "Fair's fair - frontier spirit.",
    ]
    private static let columbiaAccept = [
        "Accepted - liberty and good trade.",
        "Deal. The eagle approves.",
        "Fine, by the flag, this is fair.",
        "Yes - the frontier rewards this.",
        "Done. My wooden teeth smile.",
        "Agreed, before the redcoats hear.",
        "Take it. Spirit of '76 right here.",
        "Accepted - go earn the stars.",
    ]
    private static let columbiaReject = [
        "No. My wooden teeth won't bite.",
        "Crookeder than a redcoat's deal.",
        "Wouldn't buy a musket ball.",
        "Rejected. Peddle to the Tories.",
        "Not while the frontier needs me.",
        "My eagle flew off in disgust.",
        "Insults the flag and frontier.",
        "Come back after crossing a river.",
    ]

    // MARK: - Rome (Augustus)

    private static let romePitch = [
        "Worthy of the Senate. Barely.",
        "Accept, or feed the lions this.",
        "My legions marched for worse deals.",
        "Rome wasn't built refusing trades.",
        "Straighter than my aqueducts.",
        "Even Caesar would nod at this.",
        "Trade, or face my gladiators.",
        "Tribute-worthy. Don't repeat me.",
        "My toga's pressed. Accept.",
        "The Colosseum roars for less.",
    ]
    private static let romeAccept = [
        "Accepted - the Senate approves.",
        "Deal. Even the lions are pleased.",
        "Fine, by the eagle standard.",
        "Yes - into the annals it goes.",
        "Done. My legions march on full.",
        "Agreed, before the gladiators wait.",
        "Take it. Rome rewards fair trade.",
        "Accepted - build an empire now.",
    ]
    private static let romeReject = [
        "No. My gladiators offer better.",
        "The Senate would laugh you out.",
        "Not worth a single sesterce.",
        "Rejected. Haggle with barbarians.",
        "Not while my aqueducts need funds.",
        "My legions marched for less insult.",
        "Beneath the Colosseum's standards.",
        "Come back once you've conquered.",
    ]

    // MARK: - Japan (Tokugawa)

    private static let japanPitch = [
        "This trade honors the code.",
        "My katana is sharp. So's my offer.",
        "The shogunate won't repeat itself.",
        "A samurai trades with honor.",
        "Does your answer respect bushido?",
        "Accept, before my archers tire.",
        "The shogun's seal is on this.",
        "Trade well - your ancestors watch.",
        "Balanced as my blade. Take it.",
        "Refuse and face my castle guard.",
    ]
    private static let japanAccept = [
        "Accepted - honor is satisfied.",
        "Deal. Even the shogun nods.",
        "Fine, by bushido, this is fair.",
        "Yes - my katana stays sheathed.",
        "Done. The castle guard stands down.",
        "Agreed, before my archers tire.",
        "Take it. This is the way of honor.",
        "Accepted - build a worthy legacy.",
    ]
    private static let japanReject = [
        "No. Not worth a single arrow.",
        "That offer dishonors us both.",
        "Wouldn't satisfy a single ronin.",
        "Rejected. Seek fortune elsewhere.",
        "Not while my castle needs defense.",
        "My katana stays sheathed for that.",
        "Insults bushido and my ancestors.",
        "Come back once you understand honor.",
    ]

    // MARK: - Norse (Ragnar)

    private static let norsePitch = [
        "Odin raises a horn to this deal.",
        "Take it, or my longship sails.",
        "More mead than fairness. Take it.",
        "Valhalla awaits the brave. Trade.",
        "My axe is sharp. My offer's sharper.",
        "Accept, before my raiders tire.",
        "Forged stronger than my shield.",
        "Trade now, or face my ship at dawn.",
        "The Norns wove this in your favor.",
        "A true Viking never haggles twice.",
    ]
    private static let norseAccept = [
        "Accepted - Odin raises a horn.",
        "Deal. My raiders stand down.",
        "Fine, by Thor's hammer, it works.",
        "Yes - Valhalla approves this.",
        "Done. My crew is celebrating.",
        "Agreed, before the raiders riot.",
        "Take it. The Norns wove it well.",
        "Accepted - go raid something good.",
    ]
    private static let norseReject = [
        "No. My crew laughed at that.",
        "Odin turned his back on that.",
        "Wouldn't buy a horn of mead.",
        "Rejected. Haggle with seagulls.",
        "Not while my axe needs sharpening.",
        "My raiders won't sail for that.",
        "Insults Valhalla itself.",
        "Come back once you've raided well.",
    ]
}
