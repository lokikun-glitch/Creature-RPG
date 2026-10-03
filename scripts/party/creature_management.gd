class_name CreatureManagement
extends RefCounted
## Rules for looking after owned creatures outside battle: ordering the party, choosing the lead,
## moving creatures between the party and storage, renaming and resting.
##
## Screens and world objects call these and show the returned message; they never change
## PartyManager or storage themselves. Each function returns "" on success, otherwise a message
## for the player (with {name} already filled in) and nothing changes. Every successful change is
## saved through GameSession.request_save().

const SLOT_EMPTY := "That slot is empty."
const ALREADY_LEAD := "{name} is already leading your team."
const LEAD_FAINTED := "{name} has fainted and can't lead."
const LEAD_CHANGED := "{name} will now lead your team."
const MOVED := "{name} was moved."
const LAST_CREATURE := "Your party can't be empty."
const LAST_USABLE := "{name} is the only creature in your party that can fight."
const PARTY_FULL := "Your party is full."
const NOT_OWNED := "That creature isn't yours."
const DEPOSITED := "{name} was sent to storage."
const WITHDRAWN := "{name} joined your party."
const NICKNAME_CHANGED := "Nickname changed to \"{name}\"."
const RESTED := "Your creatures are fully rested."
const ALREADY_RESTED := "Your creatures are already fully rested."


## Formats a message constant for a creature.
static func message(text: String, creature: CreatureInstance) -> String:
	return text.format({"name": creature.get_display_name() if creature else ""})


# --- Party order and lead -------------------------------------------------------------------

static func get_lead_problem(slot: int) -> String:
	var creature := PartyManager.get_creature(slot)
	if creature == null:
		return SLOT_EMPTY
	if slot == PartyManager.get_active_index():
		return message(ALREADY_LEAD, creature)
	if creature.current_hp <= 0:
		return message(LEAD_FAINTED, creature)
	return ""


## Makes the creature in `slot` the active (lead) creature, which fights first in battle.
static func set_lead(slot: int) -> String:
	var problem := get_lead_problem(slot)
	if not problem.is_empty():
		return problem
	PartyManager.switch_active(slot)
	GameSession.request_save(&"lead_changed")
	return ""


## Moves the creature in slot `from` to slot `to`. The lead stays the same creature.
static func move(from: int, to: int) -> String:
	if PartyManager.get_creature(from) == null or PartyManager.get_creature(to) == null:
		return SLOT_EMPTY
	if from == to:
		return ""
	PartyManager.move_creature(from, to)
	GameSession.request_save(&"party_reordered")
	return ""


# --- Party <-> storage ----------------------------------------------------------------------

static func get_deposit_problem(creature: CreatureInstance) -> String:
	if creature == null or not PartyManager.get_party().has(creature):
		return NOT_OWNED
	if PartyManager.get_size() <= 1:
		return LAST_CREATURE
	if creature.current_hp > 0 and PartyManager.get_usable_count() <= 1:
		return message(LAST_USABLE, creature)
	return ""


## Moves a party creature into storage, unchanged. If it was the lead, the first remaining
## creature that can fight becomes the lead.
static func deposit(creature: CreatureInstance) -> String:
	var problem := get_deposit_problem(creature)
	if not problem.is_empty():
		return problem
	PartyManager.remove_creature(creature)
	GameSession.storage.add_creature(creature)
	GameSession.request_save(&"creature_deposited")
	return ""


static func get_withdraw_problem(creature: CreatureInstance) -> String:
	if creature == null or not GameSession.storage.get_all().has(creature):
		return NOT_OWNED
	if not PartyManager.has_space():
		return PARTY_FULL
	return ""


## Moves a stored creature into the last party slot, unchanged.
static func withdraw(creature: CreatureInstance) -> String:
	var problem := get_withdraw_problem(creature)
	if not problem.is_empty():
		return problem
	GameSession.storage.remove_creature(creature)
	PartyManager.add_creature(creature)
	GameSession.request_save(&"creature_withdrawn")
	return ""


# --- Nicknames ------------------------------------------------------------------------------

static func is_owned(creature: CreatureInstance) -> bool:
	return creature != null and (PartyManager.get_party().has(creature) or GameSession.storage.get_all().has(creature))


## Renames an owned creature. Only the nickname changes (never the species).
static func rename(creature: CreatureInstance, raw_name: String) -> String:
	if not is_owned(creature):
		return NOT_OWNED
	var problem := CreatureInstance.get_nickname_problem(raw_name)
	if not problem.is_empty():
		return problem
	var cleaned := CreatureInstance.clean_nickname(raw_name)
	if cleaned != creature.nickname:
		creature.nickname = cleaned
		GameSession.request_save(&"nickname_changed")
	return ""


# --- Resting --------------------------------------------------------------------------------

## True if any owned creature (party or storage) is below full HP or has a status.
static func needs_rest() -> bool:
	for creature in _all_owned():
		if creature.current_hp < creature.get_max_hp() or not creature.status.is_empty():
			return true
	return false


## Restores every owned creature, party and storage, to full HP with no status. Nothing else
## changes (level, EXP, moves, names, order, membership). Saves only if something was healed.
## Returns whether anything changed.
static func rest_all() -> bool:
	if not needs_rest():
		return false
	for creature in _all_owned():
		creature.current_hp = creature.get_max_hp()
		creature.status = &""
	PartyManager.party_changed.emit()
	GameSession.request_save(&"rested")
	return true


static func _all_owned() -> Array[CreatureInstance]:
	var owned := PartyManager.get_party()
	owned.append_array(GameSession.storage.get_all())
	return owned
