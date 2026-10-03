class_name CreatureStorage
extends RefCounted
## Owned creatures that aren't in the party (e.g. caught while the party was full). Owned by
## GameSession; no capacity limit yet. Uses the same CreatureInstance save format as the party.

signal changed

var _creatures: Array[CreatureInstance] = []


func add_creature(creature: CreatureInstance) -> bool:
	if creature == null or _creatures.has(creature):
		return false
	_creatures.append(creature)
	changed.emit()
	return true


func remove_creature(creature: CreatureInstance) -> bool:
	if not _creatures.has(creature):
		return false
	_creatures.erase(creature)
	changed.emit()
	return true


func get_creature(index: int) -> CreatureInstance:
	return _creatures[index] if index >= 0 and index < _creatures.size() else null


func get_all() -> Array[CreatureInstance]:
	return _creatures.duplicate()


func get_count() -> int:
	return _creatures.size()


func clear() -> void:
	_creatures.clear()
	changed.emit()


func to_save_data() -> Array:
	return _creatures.map(func(creature: CreatureInstance) -> Dictionary: return creature.to_save_data())


func load_save_data(data: Variant) -> void:
	_creatures.clear()
	if data is Array:
		for entry in data:
			var creature := CreatureInstance.from_save_data(entry) if entry is Dictionary else null
			if creature:
				_creatures.append(creature)
	changed.emit()
