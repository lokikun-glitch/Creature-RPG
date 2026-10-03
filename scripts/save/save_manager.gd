extends Node
## Autoload that writes and reads the save file as plain JSON. Each system provides its own
## save data; nothing here knows about creature stats or map contents.

signal game_saved
signal game_loaded

## Version written into new saves. Bump it whenever the save format changes, and teach
## _migrate() how to upgrade the previous version.
##   1: world, game_state, party
##   2: + inventory (item id -> quantity), storage (creatures), active_index (active party slot)
##   3: + currency (Coins, a whole number)
const CURRENT_SAVE_VERSION := 3
## Oldest save version this build can still read (via _migrate()).
const MIN_SUPPORTED_SAVE_VERSION := 1
## Top-level fields every save must have, with their JSON types.
const REQUIRED_FIELDS := {
	"version": TYPE_FLOAT,
	"world": TYPE_DICTIONARY,
	"game_state": TYPE_DICTIONARY,
	"party": TYPE_ARRAY,
	"inventory": TYPE_DICTIONARY,
	"storage": TYPE_ARRAY,
	"active_index": TYPE_FLOAT,
	"currency": TYPE_FLOAT,
}

const ERROR_MISSING := "No save file was found."
const ERROR_DAMAGED := "The save file is damaged."
const ERROR_TOO_NEW := "The save file was made by a newer version of the game."
const ERROR_TOO_OLD := "The save file is from an old version that can no longer be loaded."

## Overridable so tests never touch the player's real save.
var save_path := "user://savegame.json"

var _world: World


func register_world(world: World) -> void:
	_world = world


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## Collects world, story, party, item, storage and money state, checks it, and writes it safely.
## Callers should go through GameSession (save_now / request_save), which knows when saving is safe.
func save_game() -> bool:
	var data := {
		"version": CURRENT_SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"world": _world.get_save_data() if _world else {},
		"game_state": GameState.to_save_data(),
		"party": PartyManager.to_save_data(),
		"active_index": PartyManager.get_active_index(),
		"inventory": GameSession.inventory.to_save_data(),
		"storage": GameSession.storage.to_save_data(),
		"currency": GameSession.wallet.to_save_data(),
	}
	# Round-trip through JSON and validate exactly what a later load will see.
	var text := JSON.stringify(data, "	")
	var problem := validate_save_data(JSON.parse_string(text))
	if not problem.is_empty():
		push_error("SaveManager: refusing to write invalid save data (%s)." % problem)
		return false
	# Write to a temporary file first so a crash mid-write can't corrupt the existing save.
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write '%s' (%s)." % [temp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	file.close()
	if has_save():
		DirAccess.remove_absolute(save_path)
	var error := DirAccess.rename_absolute(temp_path, save_path)
	if error != OK:
		push_error("SaveManager: cannot replace save file (%s)." % error_string(error))
		return false
	game_saved.emit()
	return true


## Reads and validates the save without changing any game state. Never modifies the file.
## Returns {"data": Dictionary, "error": String}; `error` is empty when the save is usable.
func read_save() -> Dictionary:
	if not has_save():
		return _read_failure(ERROR_MISSING)
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not json.data is Dictionary:
		return _read_failure(ERROR_DAMAGED)
	var data: Dictionary = json.data
	var problem := _check_version(data)
	if not problem.is_empty():
		return _read_failure(problem)
	data = _migrate(data, int(data["version"]))
	problem = _check_fields(data)
	if not problem.is_empty():
		return _read_failure(problem)
	return {"data": data, "error": ""}


## "" if `data` is a well-formed save of a supported version, otherwise the reason it isn't.
func validate_save_data(data: Variant) -> String:
	if not data is Dictionary:
		return ERROR_DAMAGED
	var problem := _check_version(data)
	return problem if not problem.is_empty() else _check_fields(data)


func is_save_valid() -> bool:
	return read_save()["error"].is_empty()


## Restores progress before the world, because maps read flags (e.g. starter_selected)
## as soon as they load. `data` must come from read_save().
func apply_save_data(data: Dictionary) -> void:
	GameState.load_save_data(data.get("game_state", {}))
	PartyManager.load_save_data(data.get("party", []), data.get("active_index", 0))
	GameSession.inventory.load_save_data(data.get("inventory", {}))
	GameSession.storage.load_save_data(data.get("storage", []))
	GameSession.wallet.load_save_data(data.get("currency", Wallet.STARTING_COINS))
	if _world:
		_world.apply_save_data(data.get("world", {}))
	game_loaded.emit()


func load_game() -> bool:
	var result := read_save()
	if not result["error"].is_empty():
		return false
	apply_save_data(result["data"])
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(save_path)


## Upgrades older save data to CURRENT_SAVE_VERSION, one version at a time.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version < 2:
		data = _migrate_1_to_2(data)
	if from_version < 3:
		data = _migrate_2_to_3(data)
	data["version"] = CURRENT_SAVE_VERSION
	return data


## Version 1 had no items, storage or active creature. Players get the New Game starting items
## (so catching is possible), an empty storage, and their first party creature as the active one.
## Everything else is left exactly as it was.
func _migrate_1_to_2(data: Dictionary) -> Dictionary:
	data["inventory"] = Inventory.starting_save_data()
	data["storage"] = []
	data["active_index"] = 0
	return data


## Version 2 had no money. Players get the New Game starting Coins; everything else (including
## inventory, storage and the active creature) is left exactly as it was.
func _migrate_2_to_3(data: Dictionary) -> Dictionary:
	data["currency"] = Wallet.STARTING_COINS
	return data


func _check_version(data: Dictionary) -> String:
	var version: Variant = data.get("version")
	if not (version is float or version is int) or version != floorf(version):
		return ERROR_DAMAGED
	if version > CURRENT_SAVE_VERSION:
		return ERROR_TOO_NEW
	if version < MIN_SUPPORTED_SAVE_VERSION:
		return ERROR_TOO_OLD
	return ""


func _check_fields(data: Dictionary) -> String:
	for field in REQUIRED_FIELDS:
		var expected: int = REQUIRED_FIELDS[field]
		var actual := typeof(data.get(field))
		var number_ok := expected == TYPE_FLOAT and actual == TYPE_INT
		if actual != expected and not number_ok:
			return ERROR_DAMAGED
	var index: Variant = data["active_index"]
	if index != floorf(index) or index < 0:
		return ERROR_DAMAGED
	if not Inventory.validate_save_data(data["inventory"]).is_empty():
		return ERROR_DAMAGED
	if not Wallet.validate_save_data(data["currency"]).is_empty():
		return ERROR_DAMAGED
	if data["party"].size() > PartyManager.MAX_PARTY_SIZE:
		return ERROR_DAMAGED
	for creature: Variant in data["party"] + data["storage"]:
		if not CreatureInstance.validate_save_data(creature).is_empty():
			return ERROR_DAMAGED
	return ""


func _read_failure(message: String) -> Dictionary:
	return {"data": {}, "error": message}
