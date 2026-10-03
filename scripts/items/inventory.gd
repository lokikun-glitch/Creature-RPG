class_name Inventory
extends RefCounted
## The player's items: item id -> quantity. Owned by GameSession; saved by SaveManager as plain
## ids and counts. Only items registered in ItemCatalog can be held.

signal changed

## What a new game (and a migrated version 1 save) starts with.
const STARTING_ITEMS := {&"capture_orb": 5}

var _quantities: Dictionary = {}


## Adds `amount` of a known item. Returns false (and changes nothing) for unknown items or amount < 1.
func add_item(id: StringName, amount := 1) -> bool:
	if amount < 1 or ItemCatalog.get_item(id) == null:
		return false
	_quantities[id] = get_quantity(id) + amount
	changed.emit()
	return true


## Removes `amount` if that many are held. Returns false (and changes nothing) otherwise.
func remove_item(id: StringName, amount := 1) -> bool:
	if amount < 1 or get_quantity(id) < amount:
		return false
	_quantities[id] = get_quantity(id) - amount
	if _quantities[id] == 0:
		_quantities.erase(id)
	changed.emit()
	return true


func get_quantity(id: StringName) -> int:
	return _quantities.get(id, 0)


func has_item(id: StringName, amount := 1) -> bool:
	return get_quantity(id) >= amount


## Held item ids and quantities (only items with quantity > 0).
func get_items() -> Dictionary:
	return _quantities.duplicate()


func clear() -> void:
	_quantities.clear()
	changed.emit()


func reset_to_starting_items() -> void:
	_quantities.clear()
	for id: StringName in STARTING_ITEMS:
		_quantities[id] = STARTING_ITEMS[id]
	changed.emit()


func to_save_data() -> Dictionary:
	var data := {}
	for id: StringName in _quantities:
		data[String(id)] = _quantities[id]
	return data


## Unknown item ids are skipped (same policy as unknown species in the party).
func load_save_data(data: Variant) -> void:
	_quantities.clear()
	if data is Dictionary and validate_save_data(data).is_empty():
		for key in data:
			var id := StringName(str(key))
			var amount := int(data[key])
			if amount > 0 and ItemCatalog.get_item(id):
				_quantities[id] = amount
	changed.emit()


static func starting_save_data() -> Dictionary:
	var data := {}
	for id: StringName in STARTING_ITEMS:
		data[String(id)] = STARTING_ITEMS[id]
	return data


## "" if `data` is a well-formed inventory (string ids, whole quantities >= 0), else the reason.
static func validate_save_data(data: Variant) -> String:
	if not data is Dictionary:
		return "inventory is not a dictionary"
	for key in data:
		if not key is String:
			return "inventory item id is not a string"
		var amount: Variant = data[key]
		if not (amount is int or amount is float) or amount != floorf(amount) or amount < 0:
			return "inventory quantity for '%s' is not a whole number >= 0" % key
	return ""
