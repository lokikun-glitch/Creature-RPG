extends Node
## Autoload registry of every element, move and species, loaded from their data folders and keyed
## by id. Adding a creature means adding a .tres file; no code changes.
##
## Every definition is validated before it is registered. A broken one (missing id, duplicate id,
## unknown element, missing move, bad stats, no sprite...) is reported and skipped, so bad data
## fails loudly at startup instead of crashing a battle later.

const ELEMENTS_DIR := "res://data/elements/"
const SPECIES_DIR := "res://data/creatures/"
const MOVES_DIR := "res://data/moves/"
const MAX_STARTING_MOVES := 4

## Problems found while loading the data folders. Empty when all data is valid.
var load_problems := PackedStringArray()

var _elements: Dictionary = {}
var _species: Dictionary = {}
var _moves: Dictionary = {}


func _ready() -> void:
	# Order matters: moves reference elements, species reference both.
	for resource in _load_resources(ELEMENTS_DIR):
		_report(try_register_element(resource))
	for resource in _load_resources(MOVES_DIR):
		_report(try_register_move(resource))
	for resource in _load_resources(SPECIES_DIR):
		_report(try_register_species(resource))


func get_species(id: StringName) -> CreatureSpecies:
	return _species.get(id)


func get_move(id: StringName) -> MoveData:
	return _moves.get(id)


func get_element(id: StringName) -> ElementData:
	return _elements.get(id)


func get_all_species() -> Array[CreatureSpecies]:
	var result: Array[CreatureSpecies] = []
	result.assign(_species.values())
	return result


func get_all_moves() -> Array[MoveData]:
	var result: Array[MoveData] = []
	result.assign(_moves.values())
	return result


## Each try_register_* validates, then registers only if there were no problems.
## Returns the problems (empty on success); it never registers anything invalid.
func try_register_element(resource: Resource) -> PackedStringArray:
	var element := resource as ElementData
	if element == null:
		return PackedStringArray(["%s is not an ElementData." % _describe(resource)])
	var problems := PackedStringArray()
	if element.id.is_empty():
		problems.append("%s has no id." % _describe(element))
	elif _elements.has(element.id):
		problems.append("duplicate element id '%s' (%s)." % [element.id, _describe(element)])
	if problems.is_empty():
		_elements[element.id] = element
	return problems


func try_register_move(resource: Resource) -> PackedStringArray:
	var move := resource as MoveData
	if move == null:
		return PackedStringArray(["%s is not a MoveData." % _describe(resource)])
	var problems := validate_move(move)
	if not move.id.is_empty() and _moves.has(move.id):
		problems.append("duplicate move id '%s' (%s)." % [move.id, _describe(move)])
	if problems.is_empty():
		_moves[move.id] = move
	return problems


func try_register_species(resource: Resource) -> PackedStringArray:
	var species := resource as CreatureSpecies
	if species == null:
		return PackedStringArray(["%s is not a CreatureSpecies." % _describe(resource)])
	var problems := validate_species(species)
	if not species.id.is_empty() and _species.has(species.id):
		problems.append("duplicate species id '%s' (%s)." % [species.id, _describe(species)])
	if problems.is_empty():
		_species[species.id] = species
	return problems


func validate_move(move: MoveData) -> PackedStringArray:
	var problems := PackedStringArray()
	var label := _describe(move)
	if move.id.is_empty():
		problems.append("%s has no id." % label)
	if move.display_name.is_empty():
		problems.append("%s has no display name." % label)
	if not _is_registered_element(move.element):
		problems.append("%s has a missing or unregistered element." % label)
	if move.power < 0:
		problems.append("%s has negative power." % label)
	if move.accuracy < 1 or move.accuracy > 100:
		problems.append("%s has accuracy outside 1-100." % label)
	return problems


func validate_species(species: CreatureSpecies) -> PackedStringArray:
	var problems := PackedStringArray()
	var label := _describe(species)
	if species.id.is_empty():
		problems.append("%s has no id." % label)
	if species.display_name.is_empty():
		problems.append("%s has no display name." % label)
	if not _is_registered_element(species.element):
		problems.append("%s has a missing or unregistered element." % label)
	if species.sprite == null:
		problems.append("%s has no sprite." % label)
	for stat in CreatureStats.Stat.values():
		if species.get_base_stat(stat) <= 0:
			problems.append("%s has a non-positive base %s." % [label, CreatureStats.DISPLAY_NAMES[stat]])
	if species.starting_moves.is_empty() or species.starting_moves.size() > MAX_STARTING_MOVES:
		problems.append("%s must have 1-%d starting moves." % [label, MAX_STARTING_MOVES])
	for move in species.starting_moves:
		if move == null or move.id.is_empty() or get_move(move.id) != move:
			problems.append("%s references a move that isn't registered (%s)." % [label, _describe(move)])
	return problems


func _is_registered_element(element: ElementData) -> bool:
	return element != null and not element.id.is_empty() and get_element(element.id) == element


func _report(problems: PackedStringArray) -> void:
	for problem in problems:
		load_problems.append(problem)
		push_error("CreatureDatabase: " + problem)


func _describe(resource: Resource) -> String:
	if resource == null:
		return "<null>"
	if not resource.resource_path.is_empty():
		return resource.resource_path
	var id: Variant = resource.get("id")
	return "'%s'" % id if id else "<unnamed %s>" % resource.get_class()


func _load_resources(directory: String) -> Array[Resource]:
	var result: Array[Resource] = []
	# list_directory() also resolves the remapped file names used in exported builds.
	for file in ResourceLoader.list_directory(directory):
		if file.ends_with(".tres") or file.ends_with(".res"):
			result.append(load(directory.path_join(file)))
	return result
