class_name SaveNotice
extends CanvasLayer
## Small "Game saved." notice shown after every save. Purely visual: it never takes input.
##
## Placement: it sits in the first screen corner (top-right, bottom-right, top-left, bottom-left)
## where it covers nothing important. UI that must never be covered (Coins labels, the dialogue
## box...) joins the AVOID_GROUP; nothing else needs to know where the notice goes.

const TEXT := "Game saved."
const AVOID_GROUP := &"save_notice_avoid"
const MARGIN := 6.0

## Corners, in the order they're tried. Plain constants rather than an enum: this script is part
## of a class_name dependency cycle, which confuses GDScript's enum typing.
const TOP_RIGHT := 0
const BOTTOM_RIGHT := 1
const TOP_LEFT := 2
const BOTTOM_LEFT := 3

@export var hold_time := 1.4

var _tween: Tween
var _corner := TOP_RIGHT

@onready var _panel: Control = %Panel


func _ready() -> void:
	_panel.modulate.a = 0.0
	GameSession.game_saved.connect(func(_reason: StringName) -> void: show_notice())
	# Battles take over the screen; an autosave notice from just before mustn't sit on top of them.
	BattleManager.battle_started.connect(func(_battle: BattleContext) -> void: dismiss())


func is_showing() -> bool:
	return _panel.modulate.a > 0.0


func dismiss() -> void:
	if _tween:
		_tween.kill()
	_panel.modulate.a = 0.0


## Where the notice is (or was last) shown.
func get_corner() -> int:
	return _corner


func get_rect() -> Rect2:
	return _panel.get_global_rect()


func show_notice() -> void:
	_place()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.15)
	_tween.tween_interval(hold_time)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.35)


func _place() -> void:
	var screen := get_viewport().get_visible_rect().size
	var size := _panel.get_combined_minimum_size().max(_panel.size)
	for corner: int in [TOP_RIGHT, BOTTOM_RIGHT, TOP_LEFT, BOTTOM_LEFT]:
		var rect := Rect2(Vector2(
				MARGIN if corner in [TOP_LEFT, BOTTOM_LEFT] else screen.x - MARGIN - size.x,
				MARGIN if corner in [TOP_RIGHT, TOP_LEFT] else screen.y - MARGIN - size.y), size)
		if not _covers_anything(rect):
			_set_corner(corner, rect)
			return
	_set_corner(TOP_RIGHT, Rect2(Vector2(screen.x - MARGIN - size.x, MARGIN), size))


func _set_corner(corner: int, rect: Rect2) -> void:
	_corner = corner
	_panel.position = rect.position
	_panel.size = rect.size


func _covers_anything(rect: Rect2) -> bool:
	for node in get_tree().get_nodes_in_group(AVOID_GROUP):
		var control := node as Control
		if control and control.is_visible_in_tree() and control.get_global_rect().intersects(rect.grow(1.0)):
			return true
	return false
