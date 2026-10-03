class_name PauseMenu
extends CanvasLayer
## In-game pause menu, opened with Esc during free exploration. It only asks GameSession to pause,
## save or return to the title, and opens the party screen (Creatures); it never touches the
## player, saves, creatures or maps itself.

enum Option { CONTINUE, CREATURES, SAVE, SETTINGS, TITLE }

const TEXT := Color("f2ebd9")
const TEXT_SELECTED := Color("f6cc6b")
const SAVED := "Game saved."
const SAVE_FAILED := "The game can't be saved right now."

@export var option_style: StyleBox
@export var option_selected_style: StyleBox

var _index := Option.CONTINUE

@onready var _options: Array[PanelContainer] = [
	%ContinueOption, %CreaturesOption, %SaveOption, %SettingsOption, %TitleOption]
@onready var _status: Label = %Status
@onready var _settings: SettingsPanel = %Settings
@onready var _dialog: ChoiceDialog = %Dialog
@onready var _party: PartyScreen = %Party


func _ready() -> void:
	hide()
	_dialog.chosen.connect(_on_dialog_chosen)
	GameSession.state_changed.connect(func(_state: GameSession.State) -> void: _close_without_resume())
	for i in _options.size():
		_options[i].mouse_entered.connect(_on_option_hovered.bind(i))
		_options[i].gui_input.connect(_on_option_input.bind(i))


func is_open() -> bool:
	return visible


func open() -> void:
	if visible or not GameSession.can_pause():
		return
	GameSession.set_paused(true)
	_status.text = ""
	_select(Option.CONTINUE)
	show()


func close() -> void:
	if not visible:
		return
	_close_without_resume()
	GameSession.set_paused(false)


func get_selected_option() -> Option:
	return _index


func is_settings_open() -> bool:
	return _settings.is_open()


func is_party_open() -> bool:
	return _party.is_open()


func get_party_screen() -> PartyScreen:
	return _party


func _close_without_resume() -> void:
	_settings.close()
	_party.close()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed(&"ui_cancel") and GameSession.can_pause():
			get_viewport().set_input_as_handled()
			open()
		return
	# The settings panel, party screen and dialog handle their own input while open.
	if _submenu_open():
		return
	var up := event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up")
	var down := event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down")
	var accept := event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact")
	var cancel := event.is_action_pressed(&"ui_cancel")
	if not (up or down or accept or cancel):
		return
	get_viewport().set_input_as_handled()
	if up or down:
		_select(wrapi(_index + (-1 if up else 1), 0, _options.size()))
	elif accept:
		_activate(_index)
	else:
		close()


func _select(option: int) -> void:
	_index = option
	for i in _options.size():
		var selected := i == _index
		_options[i].add_theme_stylebox_override(&"panel", option_selected_style if selected else option_style)
		(_options[i].get_node("HBox/Label") as Label).add_theme_color_override(
				&"font_color", TEXT_SELECTED if selected else TEXT)
		(_options[i].get_node("HBox/Cursor") as CanvasItem).modulate.a = 1.0 if selected else 0.0


func _activate(option: Option) -> void:
	match option:
		Option.CONTINUE:
			close()
		Option.CREATURES:
			_status.text = ""
			_party.open()
		Option.SAVE:
			_status.text = SAVED if GameSession.save_now(&"manual") else SAVE_FAILED
		Option.SETTINGS:
			_settings.open()
		Option.TITLE:
			_dialog.open("Return to title?", "Your game will be saved first.",
					PackedStringArray(["YES", "NO"]), 1, 1)


func _on_dialog_chosen(index: int) -> void:
	if index != 0:
		return
	close()
	GameSession.save_now(&"return_to_title")
	GameSession.return_to_title()


func _submenu_open() -> bool:
	return _dialog.is_open() or _settings.is_open() or _party.is_open()


func _on_option_hovered(option: int) -> void:
	if visible and not _submenu_open():
		_select(option)


func _on_option_input(event: InputEvent, option: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and not _submenu_open():
		_select(option)
		_activate(option)
