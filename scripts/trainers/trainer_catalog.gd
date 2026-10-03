class_name TrainerCatalog
## Registry of every TrainerData in data/trainers/, loaded on first use and keyed by id. Static,
## like ItemCatalog: nothing about it changes at runtime. Invalid trainers are reported and
## skipped, so a broken definition can never start (or crash) a battle.

const TRAINERS_DIR := "res://data/trainers/"

static var load_problems := PackedStringArray()
static var _trainers: Dictionary = {}
static var _loaded := false


static func get_trainer(id: StringName) -> TrainerData:
	_ensure_loaded()
	return _trainers.get(id)


static func get_all_trainers() -> Array[TrainerData]:
	_ensure_loaded()
	var result: Array[TrainerData] = []
	result.assign(_trainers.values())
	return result


## Every reason `trainer` can't be used; empty when it's valid.
static func validate_trainer(trainer: TrainerData) -> PackedStringArray:
	var problems := PackedStringArray()
	var label := trainer.resource_path if not trainer.resource_path.is_empty() else "trainer '%s'" % trainer.id
	if trainer.id.is_empty():
		problems.append("%s has no id." % label)
	if trainer.display_name.strip_edges().is_empty():
		problems.append("%s has no name." % label)
	if trainer.trainer_class.strip_edges().is_empty():
		problems.append("%s has no trainer class." % label)
	if trainer.reward_coins < 0:
		problems.append("%s has a negative reward." % label)
	for dialogue: DialogueData in [trainer.dialogue_before, trainer.dialogue_after]:
		if dialogue == null or dialogue.lines.is_empty():
			problems.append("%s is missing its before or after dialogue." % label)
	if trainer.team.is_empty():
		problems.append("%s has an empty team." % label)
	for i in trainer.team.size():
		var entry := trainer.team[i]
		var where := "%s team slot %d" % [label, i + 1]
		if entry == null:
			problems.append("%s is empty." % where)
			continue
		if CreatureDatabase.get_species(entry.species_id) == null:
			problems.append("%s: unknown species '%s'." % [where, entry.species_id])
		if entry.level < 1 or entry.level > CreatureInstance.MAX_LEVEL:
			problems.append("%s: level %d is out of range." % [where, entry.level])
		if entry.move_ids.size() > CreatureInstance.MAX_MOVES:
			problems.append("%s: more than %d moves." % [where, CreatureInstance.MAX_MOVES])
		for move_id in entry.move_ids:
			if CreatureDatabase.get_move(move_id) == null:
				problems.append("%s: unknown move '%s'." % [where, move_id])
	return problems


## Registers `trainer` if it's valid and its id is new. Returns the problems (empty on success);
## a rejected trainer changes nothing. Used for every file in data/trainers/.
static func try_register(trainer: TrainerData) -> PackedStringArray:
	_ensure_loaded()
	return _register(trainer)


static func _register(trainer: TrainerData) -> PackedStringArray:
	if trainer == null:
		return PackedStringArray(["not a TrainerData."])
	var problems := validate_trainer(trainer)
	if _trainers.has(trainer.id):
		problems.append("duplicate trainer id '%s'." % trainer.id)
	if problems.is_empty():
		_trainers[trainer.id] = trainer
	return problems


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for file in ResourceLoader.list_directory(TRAINERS_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		for problem in _register(load(TRAINERS_DIR.path_join(file)) as TrainerData):
			load_problems.append("%s: %s" % [file, problem])
			push_error("TrainerCatalog: %s: %s" % [file, problem])
