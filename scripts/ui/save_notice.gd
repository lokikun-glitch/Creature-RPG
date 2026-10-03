class_name SaveNotice
extends CanvasLayer
## Small "Game saved." notice shown after every save. Purely visual: it never takes input.

const TEXT := "Game saved."

@export var hold_time := 1.4

var _tween: Tween

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


func show_notice() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.15)
	_tween.tween_interval(hold_time)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.35)
