class_name ChoiceDialog
extends Control
## Small modal box with a title, a message and a row of options (YES / NO, OK, ...).
## Left/Right (or A/D) to pick, E/Enter/Space to choose, Esc for the cancel option; mouse too.

signal chosen(index: int)

const TEXT := Color("f2ebd9")
const TEXT_SELECTED := Color("222034")

@export var option_style: StyleBox
@export var option_selected_style: StyleBox

var _options: Array[PanelContainer] = []
var _index := 0
var _cancel_index := -1

@onready var _title: Label = %DialogTitle
@onready var _message: Label = %DialogMessage
@onready var _row: HBoxContainer = %OptionRow


func _ready() -> void:
	hide()


## `cancel_index` is chosen by Esc; -1 means Esc does nothing.
func open(title: String, message: String, options: PackedStringArray,
		default_index := 0, cancel_index := -1) -> void:
	_title.text = title
	_message.text = message
	_message.visible = not message.is_empty()
	for option in _options:
		_row.remove_child(option)
		option.queue_free()
	_options.clear()
	for i in options.size():
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_entered.connect(_highlight.bind(i))
		panel.gui_input.connect(_on_option_input.bind(i))
		var label := Label.new()
		label.text = options[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 8)
		panel.add_child(label)
		_row.add_child(panel)
		_options.append(panel)
	_cancel_index = cancel_index
	_highlight(default_index)
	show()


func is_open() -> bool:
	return visible


func get_selected_index() -> int:
	return _index


func get_option(index: int) -> Control:
	return _options[index]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		_highlight(_index - 1)
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		_highlight(_index + 1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
		_choose(_index)
	elif event.is_action_pressed(&"ui_cancel") and _cancel_index >= 0:
		_choose(_cancel_index)
	else:
		return
	get_viewport().set_input_as_handled()


func _highlight(index: int) -> void:
	_index = wrapi(index, 0, _options.size())
	for i in _options.size():
		var selected := i == _index
		_options[i].add_theme_stylebox_override(&"panel", option_selected_style if selected else option_style)
		(_options[i].get_child(0) as Label).add_theme_color_override(
				&"font_color", TEXT_SELECTED if selected else TEXT)


func _on_option_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_choose(index)


func _choose(index: int) -> void:
	hide()
	chosen.emit(index)
