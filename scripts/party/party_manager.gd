extends Node
## Autoload holding the player's party: up to MAX_PARTY_SIZE creatures, filled from slot 0
## with no gaps. Slots past get_size() are empty.
##
## One party creature is the active one (the lead: it fights first in battle). It's tracked by
## index, defaults to slot 0, and is saved. Reordering and removing keep it pointing at the same
## creature.

signal party_changed

const MAX_PARTY_SIZE := 6

var _creatures: Array[CreatureInstance] = []
var _active_index := 0


func get_party() -> Array[CreatureInstance]:
	return _creatures.duplicate()


## Returns null for an empty or out-of-range slot.
func get_creature(slot: int) -> CreatureInstance:
	return _creatures[slot] if slot >= 0 and slot < _creatures.size() else null


func get_size() -> int:
	return _creatures.size()


func has_space() -> bool:
	return _creatures.size() < MAX_PARTY_SIZE


## Returns the slot the creature went into, or -1 if the party is full or it's already in it.
func add_creature(creature: CreatureInstance) -> int:
	if creature == null or not has_space() or _creatures.has(creature):
		return -1
	_creatures.append(creature)
	party_changed.emit()
	return _creatures.size() - 1


func remove_creature(creature: CreatureInstance) -> bool:
	var index := _creatures.find(creature)
	if index < 0:
		return false
	_creatures.remove_at(index)
	# Keep pointing at the same creature. If the active one left, the first creature that can
	# fight takes over (or slot 0 if none can).
	if index < _active_index:
		_active_index -= 1
	elif index == _active_index:
		_active_index = maxi(_first_usable_index(), 0)
	party_changed.emit()
	return true


## Moves the creature in slot `from` to slot `to`; the ones in between shift by one. The active
## creature stays the same creature: its index follows it to wherever it ends up.
func move_creature(from: int, to: int) -> bool:
	if from == to or get_creature(from) == null or get_creature(to) == null:
		return false
	var active := get_active_creature()
	var creature := _creatures[from]
	_creatures.remove_at(from)
	_creatures.insert(to, creature)
	_active_index = _creatures.find(active)
	party_changed.emit()
	return true


## Number of party creatures that can still fight.
func get_usable_count() -> int:
	return _creatures.filter(func(creature: CreatureInstance) -> bool: return creature.current_hp > 0).size()


func clear() -> void:
	_creatures.clear()
	_active_index = 0
	party_changed.emit()


# --- Active creature ------------------------------------------------------------------------

func get_active_index() -> int:
	return _active_index


func get_active_creature() -> CreatureInstance:
	return get_creature(_active_index)


## A creature can be switched in if its slot is filled, it isn't already active, and it can fight.
func can_switch_to(index: int) -> bool:
	var creature := get_creature(index)
	return creature != null and index != _active_index and creature.current_hp > 0


func switch_active(index: int) -> bool:
	if not can_switch_to(index):
		return false
	_active_index = index
	party_changed.emit()
	return true


## If the active creature can't fight, makes the first creature that can active. Returns the active
## creature, or null if nobody can fight.
func ensure_usable_active() -> CreatureInstance:
	var active := get_active_creature()
	if active and active.current_hp > 0:
		return active
	var index := _first_usable_index()
	if index < 0:
		return null
	_active_index = index
	party_changed.emit()
	return _creatures[index]


func _first_usable_index() -> int:
	for i in _creatures.size():
		if _creatures[i].current_hp > 0:
			return i
	return -1


# --- Saving ---------------------------------------------------------------------------------

func to_save_data() -> Array:
	return _creatures.map(func(creature: CreatureInstance) -> Dictionary: return creature.to_save_data())


func load_save_data(data: Variant, active_index: Variant = 0) -> void:
	_creatures.clear()
	if data is Array:
		for entry in data:
			var creature := CreatureInstance.from_save_data(entry) if entry is Dictionary else null
			if creature and has_space():
				_creatures.append(creature)
	var index := int(active_index) if (active_index is int or active_index is float) else 0
	_active_index = index if index >= 0 and index < _creatures.size() else 0
	party_changed.emit()
