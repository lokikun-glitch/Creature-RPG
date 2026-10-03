class_name ItemCatalog
## Registry of every ItemData in data/items/, loaded on first use and keyed by id. Static rather
## than an autoload because nothing about it changes at runtime. Invalid items are reported and
## skipped, like CreatureDatabase does for creatures.

const ITEMS_DIR := "res://data/items/"

static var load_problems := PackedStringArray()
static var _items: Dictionary = {}
static var _loaded := false


static func get_item(id: StringName) -> ItemData:
	_ensure_loaded()
	return _items.get(id)


static func get_all_items() -> Array[ItemData]:
	_ensure_loaded()
	var result: Array[ItemData] = []
	result.assign(_items.values())
	return result


static func validate_item(item: ItemData) -> PackedStringArray:
	var problems := PackedStringArray()
	var label := item.resource_path if not item.resource_path.is_empty() else "item '%s'" % item.id
	if item.id.is_empty():
		problems.append("%s has no id." % label)
	if item.display_name.is_empty():
		problems.append("%s has no display name." % label)
	if item.category.is_empty():
		problems.append("%s has no category." % label)
	if item.price < 0:
		problems.append("%s has a negative price." % label)
	return problems


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for file in ResourceLoader.list_directory(ITEMS_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var item := load(ITEMS_DIR.path_join(file)) as ItemData
		var problems := validate_item(item) if item else PackedStringArray(["%s is not an ItemData." % file])
		if item and _items.has(item.id):
			problems.append("duplicate item id '%s'." % item.id)
		if problems.is_empty():
			_items[item.id] = item
		for problem in problems:
			load_problems.append(problem)
			push_error("ItemCatalog: " + problem)
