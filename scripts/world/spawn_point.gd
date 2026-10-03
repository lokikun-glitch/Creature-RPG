class_name SpawnPoint
extends Marker2D
## Named arrival point on a map. Doors and exits send the player to a spawn id, never to raw coordinates.

const GROUP := &"spawn_points"

@export var spawn_id: StringName
## Direction the player faces on arrival.
@export var facing := Vector2.DOWN


func _enter_tree() -> void:
	add_to_group(GROUP)
