class_name BusinessEvent
extends RefCounted
## Typed helpers for the rolling event journal. Events are stored as plain
## Dictionaries (cheap to trim and to serialize, exactly like CompanyState's
## recent_moves / StaffManager's absence_log) — this class only centralizes
## their schema, the type constants, and how they present in the UI. Clicking
## a report anomaly opens the events that explain it.

const PRICE_CHANGE: StringName = &"price_change"
const SHORTAGE: StringName = &"shortage"
const CAMPAIGN_STARTED: StringName = &"campaign_started"
const CAMPAIGN_ENDED: StringName = &"campaign_ended"
const STAFF_LOST: StringName = &"staff_lost"
const INCIDENT: StringName = &"incident"
const PURCHASE: StringName = &"purchase"
const EXPANSION: StringName = &"expansion"
const LOAN: StringName = &"loan"
const RANK_CHANGE: StringName = &"rank_change"
const DAY_CLOSE: StringName = &"day_close"
const COMMAND: StringName = &"command"
const AWARD_WON: StringName = &"award_won"
const STAR_GAINED: StringName = &"star_gained"
const STAR_LOST: StringName = &"star_lost"
const INSPECTION: StringName = &"inspection"
const COMPETITION_ANNOUNCED: StringName = &"competition_announced"
const COMPETITION_RESULT: StringName = &"competition_result"


## Build a journal entry. `fields` may carry restaurant_id, amount, title, tags.
static func make(type: StringName, company_id: StringName, day: int, minute: int, fields: Dictionary = {}) -> Dictionary:
	return {
		"type": type,
		"company_id": String(company_id),
		"day": day,
		"minute": minute,
		"restaurant_id": int(fields.get("restaurant_id", -1)),
		"amount": float(fields.get("amount", 0.0)),
		"title": String(fields.get("title", "")),
		"tags": fields.get("tags", []),
	}


static func icon_for(type: StringName) -> StringName:
	match type:
		PRICE_CHANGE: return &"receipt"
		SHORTAGE: return &"basket"
		CAMPAIGN_STARTED, CAMPAIGN_ENDED: return &"megaphone"
		STAFF_LOST: return &"people"
		INCIDENT: return &"hammer"
		PURCHASE, EXPANSION: return &"store"
		LOAN: return &"bank"
		RANK_CHANGE: return &"trophy"
		DAY_CLOSE: return &"calendar"
		AWARD_WON, COMPETITION_ANNOUNCED: return &"trophy"
		COMPETITION_RESULT: return &"medal"
		STAR_GAINED, STAR_LOST: return &"star"
		INSPECTION: return &"magnifier"
		_: return &"receipt"


## Feed tone: &"good" / &"bad" / &"warning" / &"info" / &"neutral".
static func tone_for(type: StringName, amount: float) -> StringName:
	match type:
		SHORTAGE, STAFF_LOST, INCIDENT: return &"bad"
		CAMPAIGN_STARTED, EXPANSION, PURCHASE: return &"info"
		RANK_CHANGE: return &"good" if amount >= 0.0 else &"bad"
		DAY_CLOSE: return &"good" if amount >= 0.0 else &"bad"
		AWARD_WON, STAR_GAINED: return &"good"
		STAR_LOST: return &"bad"
		INSPECTION: return &"good" if amount >= 0.0 else &"warning"
		COMPETITION_ANNOUNCED: return &"info"
		COMPETITION_RESULT: return &"good" if amount > 0.0 else &"info"
		_: return &"neutral"


## One-line human summary for a popover row.
static func describe(event: Dictionary) -> String:
	var title: String = String(event.get("title", ""))
	if not title.is_empty():
		return title
	return String(event.get("type", "event")).capitalize()
