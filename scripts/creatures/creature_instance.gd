class_name CreatureInstance
extends RefCounted
## One individual, player-owned creature: mutable state only. Shared facts (name, element,
## base stats, sprite) are looked up from its CreatureSpecies through CreatureDatabase.

const MAX_LEVEL := 100
const MAX_MOVES := 4
## Longest allowed nickname, in characters (after trimming surrounding whitespace).
const MAX_NICKNAME_LENGTH := 16
const NICKNAME_EMPTY := "Nicknames can't be empty."
const NICKNAME_TOO_LONG := "Nicknames can be at most 16 characters."
const NICKNAME_INVALID := "Nicknames can't contain control characters."

## Unique per creature, so later systems (storage, trading) can tell two of the same species apart.
var uid := ""
var species_id: StringName
var nickname := ""
var level := 1
var experience := 0
var current_hp := 0
var move_ids: Array[StringName] = []
## Empty means healthy. Statuses arrive with the battle system.
var status: StringName = &""


func get_species() -> CreatureSpecies:
	return CreatureDatabase.get_species(species_id)


func get_display_name() -> String:
	if not nickname.is_empty():
		return nickname
	var species := get_species()
	return species.display_name if species else String(species_id)


func get_stat(stat: CreatureStats.Stat) -> int:
	var species := get_species()
	return CreatureStats.calculate(stat, species.get_base_stat(stat), level) if species else 0


func get_max_hp() -> int:
	return get_stat(CreatureStats.Stat.HP)


## Nicknames are trimmed of surrounding whitespace; anything else (including Unicode) is kept.
static func clean_nickname(raw: String) -> String:
	return raw.strip_edges()


## "" if `raw` is an acceptable nickname once cleaned, otherwise the message to show.
static func get_nickname_problem(raw: String) -> String:
	var cleaned := clean_nickname(raw)
	if cleaned.is_empty():
		return NICKNAME_EMPTY
	if cleaned.length() > MAX_NICKNAME_LENGTH:
		return NICKNAME_TOO_LONG
	for i in cleaned.length():
		if cleaned.unicode_at(i) < 32 or cleaned.unicode_at(i) == 127:
			return NICKNAME_INVALID
	return ""


## Plain, JSON-friendly data; the save file never contains Resource objects.
func to_save_data() -> Dictionary:
	var moves: Array[String] = []
	for move_id in move_ids:
		moves.append(String(move_id))
	return {
		"uid": uid,
		"species_id": String(species_id),
		"nickname": nickname,
		"level": level,
		"experience": experience,
		"current_hp": current_hp,
		"moves": moves,
		"status": String(status),
	}


## Rebuilds a creature from save data. Returns null if its species no longer exists.
static func from_save_data(data: Dictionary) -> CreatureInstance:
	var saved_species := StringName(str(data.get("species_id", "")))
	if CreatureDatabase.get_species(saved_species) == null:
		push_warning("CreatureInstance: unknown species '%s' in save data; skipped." % saved_species)
		return null
	var creature := CreatureInstance.new()
	creature.uid = str(data.get("uid", ""))
	if creature.uid.is_empty():
		creature.uid = CreatureFactory.generate_uid()
	creature.species_id = saved_species
	creature.nickname = str(data.get("nickname", ""))
	creature.level = clampi(int(data.get("level", 1)), 1, MAX_LEVEL)
	creature.experience = maxi(int(data.get("experience", 0)), 0)
	creature.current_hp = clampi(int(data.get("current_hp", 0)), 0, creature.get_max_hp())
	for saved_move in data.get("moves", []):
		var move_id := StringName(str(saved_move))
		if CreatureDatabase.get_move(move_id) and creature.move_ids.size() < MAX_MOVES:
			creature.move_ids.append(move_id)
	creature.status = StringName(str(data.get("status", "")))
	return creature


## "" if `data` has the shape of a saved creature, otherwise the reason. Used by save validation so
## a damaged creature rejects the whole save instead of loading half of it. An unknown species is
## still valid here: like before, such creatures are skipped when the save is applied.
static func validate_save_data(data: Variant) -> String:
	if not data is Dictionary:
		return "creature is not a dictionary"
	var species: Variant = data.get("species_id")
	if not species is String or species.is_empty():
		return "creature has no species"
	for field in ["level", "current_hp", "experience"]:
		var value: Variant = data.get(field, 0)
		if not (value is int or value is float) or value != floorf(value) or value < 0:
			return "creature %s is not a whole number >= 0" % field
	if not (data.get("level") is int or data.get("level") is float) or data["level"] < 1:
		return "creature level is missing or below 1"
	if not (data.get("current_hp") is int or data.get("current_hp") is float):
		return "creature current_hp is missing"
	for field in ["uid", "nickname", "status"]:
		if data.has(field) and not data[field] is String:
			return "creature %s is not text" % field
	var moves: Variant = data.get("moves", [])
	if not moves is Array or (moves as Array).any(func(move: Variant) -> bool: return not move is String):
		return "creature moves are not a list of move ids"
	return ""
