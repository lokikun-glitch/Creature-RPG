extends Node
## Autoload that moves the game between maps behind a screen fade.
## Doors, exits and (later) cutscenes call go_to(); none of them touch the scene tree directly.

signal transition_started
signal transition_finished

const FADE_DURATION := 0.2

var _world: World
var _busy := false
var _fade: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


func register_world(world: World) -> void:
	_world = world


func is_busy() -> bool:
	return _busy


func go_to(map_path: String, spawn_id: StringName) -> void:
	if _world == null:
		return
	transition(_world.load_map.bind(map_path, spawn_id))


## Fades to black, runs `action` while the screen is hidden, then fades back in.
## Used for map changes and for moving between the title screen and the game.
func transition(action: Callable) -> void:
	if _busy:
		return
	_busy = true
	transition_started.emit()
	await _fade_to(1.0)
	action.call()
	await _fade_to(0.0)
	_busy = false
	transition_finished.emit()


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", alpha, FADE_DURATION)
	await tween.finished
