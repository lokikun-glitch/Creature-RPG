@tool
class_name EncounterZone
extends Area2D
## Tall grass (or any area) where wild creatures can appear. It draws itself, so the visible
## grass and the encounter area always match. The origin is the top-left corner.
##
## Steps are measured by distance actually walked inside the zone: standing still, walking into
## a wall, being frozen by dialogue/menus or being teleported never count.

const TILE := 16
## A position jump larger than this in one physics frame is a teleport, not walking.
const MAX_STEP_PER_FRAME := 8.0
## A darker outline so the edge of the encounter area reads clearly against plain grass.
const EDGE_COLOR := Color(0.1, 0.26, 0.12, 0.9)

@export var size_tiles := Vector2i(4, 3):
	set(value):
		size_tiles = value.max(Vector2i.ONE)
		_refresh()
@export var encounter_enabled := true
## Chance of an encounter per step (0..1).
@export_range(0.0, 1.0, 0.01) var encounter_rate := 0.1
@export var encounter_table: EncounterTable
## Distance walked inside the zone that counts as one step.
@export var step_length := 16.0
@export var grass_texture: Texture2D:
	set(value):
		grass_texture = value
		queue_redraw()
## Drawn in front of the player's feet while they stand in the zone.
@export var tuft_texture: Texture2D

var _player: Player
var _last_position := Vector2.ZERO
var _walked := 0.0
var _tuft: Sprite2D


func _ready() -> void:
	_refresh()
	set_physics_process(false)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func get_map() -> GameMap:
	var node := get_parent()
	while node and not node is GameMap:
		node = node.get_parent()
	return node as GameMap


func contains_player() -> bool:
	return _player != null


func get_rect() -> Rect2:
	return Rect2(global_position, Vector2(size_tiles * TILE))


func _refresh() -> void:
	queue_redraw()
	var shape_node := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		var size := Vector2(size_tiles * TILE)
		(shape_node.shape as RectangleShape2D).size = size
		shape_node.position = size / 2.0


func _draw() -> void:
	if grass_texture == null:
		return
	for y in size_tiles.y:
		for x in size_tiles.x:
			draw_texture(grass_texture, Vector2(x, y) * TILE)
	draw_rect(Rect2(Vector2(0.5, 0.5), Vector2(size_tiles * TILE) - Vector2.ONE), EDGE_COLOR, false, 1.0)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_stop_tracking()
		return
	var position_now := _player.global_position
	var moved := position_now.distance_to(_last_position)
	_last_position = position_now
	if moved > MAX_STEP_PER_FRAME or not _player.controls_enabled:
		return
	_walked += moved
	while _walked >= step_length:
		_walked -= step_length
		EncounterManager.register_step(self)


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	_player = body
	_last_position = body.global_position
	_walked = 0.0
	set_physics_process(true)
	EncounterManager.zone_entered(self)
	if tuft_texture:
		# Parented to the player so it moves exactly with the (interpolated) sprite.
		_tuft = Sprite2D.new()
		_tuft.texture = tuft_texture
		_tuft.position = Vector2(0, -3)
		_tuft.z_index = 1
		body.add_child(_tuft)


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_stop_tracking()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_stop_tracking()


func _stop_tracking() -> void:
	if _player == null and _tuft == null:
		return
	_player = null
	set_physics_process(false)
	EncounterManager.zone_exited(self)
	if is_instance_valid(_tuft):
		_tuft.queue_free()
	_tuft = null
