extends Node
## Autoload for persistent story/progress flags. Everything here is saved, so values must be
## JSON-friendly (bool, number, String).

signal flag_changed(flag: StringName, value: Variant)

const STARTER_SELECTED := &"starter_selected"
const STARTER_SPECIES := &"starter_species"

## The state of every flag at the start of a new game. Add new story flags here.
const INITIAL_FLAGS := {
	STARTER_SELECTED: false,
	STARTER_SPECIES: "",
}

var starter_selected: bool:
	get:
		return get_flag(STARTER_SELECTED, false) == true
	set(value):
		set_flag(STARTER_SELECTED, value)

var _flags: Dictionary = INITIAL_FLAGS.duplicate()


func get_flag(flag: StringName, default: Variant = null) -> Variant:
	return _flags.get(flag, default)


func set_flag(flag: StringName, value: Variant) -> void:
	if _flags.get(flag) == value:
		return
	_flags[flag] = value
	flag_changed.emit(flag, value)


## Back to a brand-new game. Doesn't emit flag_changed: callers reload the map afterwards.
func reset() -> void:
	_flags = INITIAL_FLAGS.duplicate()


func to_save_data() -> Dictionary:
	var data := {}
	for flag in _flags:
		data[String(flag)] = _flags[flag]
	return data


## Flags missing from older saves keep their initial values.
func load_save_data(data: Variant) -> void:
	reset()
	if data is Dictionary:
		for key in data:
			_flags[StringName(str(key))] = data[key]
