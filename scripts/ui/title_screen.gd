class_name TitleScreen
extends CanvasLayer
## Startup menu. Shows itself whenever GameSession is on the title and only asks GameSession
## for high-level actions; it never touches saves, creatures, maps or the player.

enum Option { CONTINUE, NEW_GAME, SETTINGS }

const TEXT := Color("f2ebd9")
const TEXT_SELECTED := Color("f6cc6b")
const TEXT_DISABLED := Color(0.55, 0.53, 0.62)

@export var option_style: StyleBox
@export var option_selected_style: StyleBox

var _index := Option.NEW_GAME
var _continue_enabled := false
## Which question the dialog is currently asking.
var _pending_dialog := &""

@onready var _options: Array[PanelContainer] = [%ContinueOption, %NewGameOption, %SettingsOption]
@onready var _settings: SettingsPanel = %Settings
@onready var _dialog: ChoiceDialog = %Dialog


func _ready() -> void:
	hide()
	GameSession.state_changed.connect(_on_state_changed)
	_dialog.chosen.connect(_on_dialog_chosen)
	for i in _options.size():
		_options[i].mouse_entered.connect(_on_option_hovered.bind(i))
		_options[i].gui_input.connect(_on_option_input.bind(i))


func open() -> void:
	show()
	_settings.close()
	_continue_enabled = GameSession.can_continue()
	_select(Option.CONTINUE if _continue_enabled else Option.NEW_GAME)
	var problem := GameSession.get_save_problem()
	if not problem.is_empty():
		_show_load_error(problem)


func is_option_enabled(option: Option) -> bool:
	return option != Option.CONTINUE or _continue_enabled


func get_selected_option() -> Option:
	return _index


func is_settings_open() -> bool:
	return _settings.is_open()


func _on_state_changed(state: GameSession.State) -> void:
	if state == GameSession.State.TITLE:
		open()
	else:
		hide()


func _unhandled_input(event: InputEvent) -> void:
	# The settings panel and dialog handle their own input while open.
	if not visible or _dialog.is_open() or _settings.is_open() or SceneRouter.is_busy():
		return
	var up := event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up")
	var down := event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down")
	var accept := event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact")
	var cancel := event.is_action_pressed(&"ui_cancel")
	if not (up or down or accept or cancel):
		return
	get_viewport().set_input_as_handled()
	if up or down:
		_select(_next_enabled(_index, -1 if up else 1))
	elif accept:
		_activate(_index)


func _next_enabled(from: int, step: int) -> int:
	var index := from
	for i in _options.size():
		index = wrapi(index + step, 0, _options.size())
		if is_option_enabled(index):
			return index
	return from


func _select(option: Option) -> void:
	_index = option
	for i in _options.size():
		var selected := i == _index
		var panel := _options[i]
		panel.add_theme_stylebox_override(&"panel", option_selected_style if selected else option_style)
		var label := panel.get_node("HBox/Label") as Label
		var color := TEXT_SELECTED if selected else TEXT
		label.add_theme_color_override(&"font_color", color if is_option_enabled(i) else TEXT_DISABLED)
		(panel.get_node("HBox/Cursor") as CanvasItem).modulate.a = 1.0 if selected else 0.0


func _activate(option: Option) -> void:
	if not is_option_enabled(option):
		return
	match option:
		Option.CONTINUE:
			var problem := GameSession.continue_game()
			if not problem.is_empty():
				_show_load_error(problem)
		Option.NEW_GAME:
			if GameSession.has_save():
				_pending_dialog = &"overwrite"
				_dialog.open("Start a new game?", "This will overwrite your existing save.",
						PackedStringArray(["YES", "NO"]), 1, 1)
			else:
				GameSession.start_new_game(false)
		Option.SETTINGS:
			_settings.open()


func _show_load_error(problem: String) -> void:
	_continue_enabled = false
	_select(Option.NEW_GAME)
	_pending_dialog = &"load_error"
	_dialog.open("Save data could not be loaded.", problem, PackedStringArray(["OK"]), 0, 0)


func _on_dialog_chosen(index: int) -> void:
	var question := _pending_dialog
	_pending_dialog = &""
	if question == &"overwrite" and index == 0:
		GameSession.start_new_game(true)


func _on_option_hovered(option: int) -> void:
	if not _dialog.is_open() and not _settings.is_open() and is_option_enabled(option):
		_select(option)


func _on_option_input(event: InputEvent, option: int) -> void:
	if _clicked(event) and not _dialog.is_open() and not _settings.is_open() and not SceneRouter.is_busy() \
			and is_option_enabled(option):
		_select(option)
		_activate(option)


func _clicked(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
