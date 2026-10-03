class_name World
extends Node2D
## Owns the currently loaded map and the persistent player.
## Maps are swapped underneath the player, so the player never belongs to a map scene.

signal map_loaded(map: GameMap)

const INACTIVE_LOCK := &"world_inactive"

@export_file("*.tscn") var starting_map: String
@export var starting_spawn: StringName
@export var player: Player

var current_map: GameMap
var current_map_path: String


func _ready() -> void:
	SceneRouter.register_world(self)
	SceneRouter.transition_started.connect(player.add_control_lock.bind(&"transition"))
	SceneRouter.transition_finished.connect(player.remove_control_lock.bind(&"transition"))
	DialogueManager.dialogue_started.connect(player.add_control_lock.bind(&"dialogue").unbind(1))
	DialogueManager.dialogue_finished.connect(player.remove_control_lock.bind(&"dialogue").unbind(1))
	EncounterManager.encounter_started.connect(player.add_control_lock.bind(&"encounter").unbind(1))
	EncounterManager.encounter_ended.connect(player.remove_control_lock.bind(&"encounter").unbind(1))
	# Any battle, wild or trainer, freezes the player until it has fully finished.
	BattleManager.battle_started.connect(player.add_control_lock.bind(&"battle").unbind(1))
	BattleManager.battle_finished.connect(player.remove_control_lock.bind(&"battle").unbind(1))
	SaveManager.register_world(self)
	# The world waits, hidden and frozen, until GameSession starts or continues a game.
	set_active(false)
	GameSession.register_world(self)


## Inactive while the title screen is up: hidden, and the player can't act.
func set_active(active: bool) -> void:
	visible = active
	if active:
		player.remove_control_lock(INACTIVE_LOCK)
	else:
		player.add_control_lock(INACTIVE_LOCK)


func start_from_beginning() -> void:
	load_map(starting_map, starting_spawn)


## Drops the current map, e.g. when returning to the title screen.
func unload() -> void:
	if current_map:
		remove_child(current_map)
		current_map.queue_free()
	current_map = null
	current_map_path = ""


func load_map(map_path: String, spawn_id: StringName) -> void:
	if not _swap_map(map_path):
		return
	_place_player(spawn_id)
	map_loaded.emit(current_map)


func get_save_data() -> Dictionary:
	return {
		"map": current_map_path,
		"position": {"x": player.global_position.x, "y": player.global_position.y},
		"facing": {"x": player.facing.x, "y": player.facing.y},
	}


func apply_save_data(data: Variant) -> void:
	var saved: Dictionary = data if data is Dictionary else {}
	var map_path := str(saved.get("map", ""))
	if not ResourceLoader.exists(map_path) or not _swap_map(map_path):
		load_map(starting_map, starting_spawn)
		return
	var position_data: Dictionary = saved.get("position", {})
	var facing_data: Dictionary = saved.get("facing", {})
	player.teleport(
			Vector2(float(position_data.get("x", 0.0)), float(position_data.get("y", 0.0))),
			Vector2(float(facing_data.get("x", 0.0)), float(facing_data.get("y", 1.0))))
	player.camera.set_bounds(current_map.get_bounds())
	player.camera.reset_smoothing()
	map_loaded.emit(current_map)


func _swap_map(map_path: String) -> bool:
	var scene := load(map_path) as PackedScene
	var map := scene.instantiate() as GameMap if scene else null
	if map == null:
		push_error("World: '%s' is not a GameMap scene." % map_path)
		return false

	if current_map:
		remove_child(current_map)
		current_map.queue_free()
	current_map = map
	current_map_path = map_path
	add_child(map)
	move_child(map, 0)
	return true


func _place_player(spawn_id: StringName) -> void:
	var bounds := current_map.get_bounds()
	var spawn := current_map.get_spawn_point(spawn_id)
	if spawn:
		player.teleport(spawn.global_position, spawn.facing)
	else:
		push_warning("World: map '%s' has no spawn point '%s'." % [current_map.map_id, spawn_id])
		player.teleport(bounds.get_center(), Vector2.DOWN)
	player.camera.set_bounds(bounds)
	player.camera.reset_smoothing()
