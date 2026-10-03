@tool
class_name CharacterSprite
extends Sprite2D
## Drives a 3x4 character sheet shared by the player and NPCs.
## Rows: down, up, left, right. Columns: idle, step A, step B.

enum Row { DOWN, UP, LEFT, RIGHT }

const WALK_CYCLE: Array[int] = [1, 0, 2, 0]
const ROW_FOR_DIRECTION := {
	Vector2.DOWN: Row.DOWN, Vector2.UP: Row.UP, Vector2.LEFT: Row.LEFT, Vector2.RIGHT: Row.RIGHT,
}

@export var walk_fps := 8.0

var _row := Row.DOWN
var _walking := false
var _time := 0.0


func _ready() -> void:
	set_process(not Engine.is_editor_hint())


func face(direction: Vector2) -> void:
	var cardinal := Direction.to_cardinal(direction)
	if cardinal == Vector2.ZERO:
		return
	_row = ROW_FOR_DIRECTION[cardinal]
	_update_frame()


func set_walking(walking: bool) -> void:
	if walking == _walking:
		return
	_walking = walking
	_time = 0.0
	_update_frame()


func _process(delta: float) -> void:
	if _walking:
		_time += delta
		_update_frame()


func _update_frame() -> void:
	var column := 0
	if _walking:
		column = WALK_CYCLE[int(_time * walk_fps) % WALK_CYCLE.size()]
	frame = _row * hframes + column
