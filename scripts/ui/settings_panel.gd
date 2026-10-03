class_name SettingsPanel
extends Control
## Settings screen shared by the title screen and the pause menu. Audio options are placeholders
## until the game has sound. Handles its own input while open: E/Enter/Space/Esc or clicking
## BACK closes it.

signal closed

@export var back_selected_style: StyleBox

@onready var _back: PanelContainer = %Back


func _ready() -> void:
	hide()
	_back.add_theme_stylebox_override(&"panel", back_selected_style)
	_back.gui_input.connect(_on_back_input)


func open() -> void:
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact") \
			or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_back_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close()
