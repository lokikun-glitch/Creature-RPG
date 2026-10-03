class_name NicknameDialog
extends Control
## "Enter nickname:" box using the platform's normal text field. Enter or OK submits, Esc or
## CANCEL backs out; the mouse works too. It only reports the text: the owner applies it through
## CreatureManagement.rename() and calls show_error() if it was refused.

signal submitted(text: String)
signal cancelled

const PROMPT := "Enter nickname:"

var _field: LineEdit
var _error: Label
var _ok: PanelContainer
var _cancel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiStyle.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(170, 0)
	panel.add_theme_stylebox_override(&"panel", UiStyle.panel(10, 7))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	panel.add_child(box)
	box.add_child(UiStyle.label(PROMPT, 8, UiStyle.ACCENT))
	_field = LineEdit.new()
	_field.name = "Field"
	_field.add_theme_font_size_override(&"font_size", 8)
	_field.custom_minimum_size = Vector2(150, 14)
	_field.context_menu_enabled = false
	# Stay in edit mode after Enter, so the player can fix a refused name straight away.
	_field.keep_editing_on_text_submit = true
	_field.text_submitted.connect(func(text: String) -> void: submitted.emit(text))
	box.add_child(_field)
	_error = UiStyle.label("", 6, UiStyle.BAD)
	_error.name = "Error"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(150, 0)
	box.add_child(_error)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 12)
	box.add_child(buttons)
	_ok = _button("OK", func() -> void: submitted.emit(_field.text))
	_cancel = _button("CANCEL", _cancel_now)
	buttons.add_child(_ok)
	buttons.add_child(_cancel)
	hide()


func open(current_name: String) -> void:
	_field.text = current_name
	_error.text = ""
	show()
	_start_editing()
	_field.select_all()


func close() -> void:
	_field.release_focus()
	hide()


func is_open() -> bool:
	return visible


func show_error(message: String) -> void:
	_error.text = message
	_start_editing()


func get_field() -> LineEdit:
	return _field


func get_error() -> String:
	return _error.text


func get_ok_button() -> Control:
	return _ok


func get_cancel_button() -> Control:
	return _cancel


func _input(event: InputEvent) -> void:
	# Esc must win over the text field (which would otherwise just stop editing).
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel_now()


func _cancel_now() -> void:
	close()
	cancelled.emit()


func _start_editing() -> void:
	_field.grab_focus()
	_field.edit()
	_field.caret_column = _field.text.length()


func _button(text: String, action: Callable) -> PanelContainer:
	var button := PanelContainer.new()
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_stylebox_override(&"panel", UiStyle.row(true))
	button.add_child(UiStyle.label(text, 7))
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			button.accept_event()
			action.call())
	return button
