class_name InteractionPrompt
extends Node2D
## Small "E" bubble drawn above the current interaction target.

const OUTLINE := Color("222034")
const PAPER := Color("f4ecd8")

var _target: Interactable
var _time := 0.0


func _ready() -> void:
	top_level = true
	z_index = 20
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false


func show_for(target: Interactable) -> void:
	_target = target
	_time = 0.0
	visible = target != null
	_follow()


func _process(delta: float) -> void:
	if visible:
		_time += delta
		_follow()


func _follow() -> void:
	if not is_instance_valid(_target):
		visible = false
		return
	var bob := Vector2(0, roundf(sin(_time * 5.0) * 0.6))
	global_position = (_target.global_position + _target.prompt_offset).round() + bob


func _draw() -> void:
	draw_rect(Rect2(-4, -9, 9, 9), OUTLINE)
	draw_rect(Rect2(-3, -8, 7, 7), PAPER)
	draw_rect(Rect2(-1, 0, 3, 1), OUTLINE)
	draw_rect(Rect2(0, 1, 1, 1), OUTLINE)
	# Pixel "E".
	draw_rect(Rect2(-1, -7, 1, 5), OUTLINE)
	draw_rect(Rect2(-1, -7, 3, 1), OUTLINE)
	draw_rect(Rect2(-1, -5, 2, 1), OUTLINE)
	draw_rect(Rect2(-1, -3, 3, 1), OUTLINE)
