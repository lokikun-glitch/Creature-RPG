@tool
class_name MapTransition
extends Area2D
## Sends the player to a spawn point on another map when they walk into this area.
## An empty target_map disables it (e.g. a house door that is locked for now).

@export_file("*.tscn") var target_map := ""
@export var target_spawn: StringName
@export var size := Vector2(16, 12):
	set(value):
		size = value
		_apply_size()


func _ready() -> void:
	_apply_size()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _apply_size() -> void:
	var shape_node := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		(shape_node.shape as RectangleShape2D).size = size


func _on_body_entered(body: Node2D) -> void:
	if body is Player and not target_map.is_empty():
		SceneRouter.go_to(target_map, target_spawn)
