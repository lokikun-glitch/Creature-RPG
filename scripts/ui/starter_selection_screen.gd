class_name StarterSelectionScreen
extends CanvasLayer
## Lets the player browse the offered starters and pick one. Display and input only: it reports
## which species was chosen and never creates creatures or calculates stats.

signal species_chosen(species: CreatureSpecies)
signal cancelled

const CARD_SCENE := preload("res://scenes/ui/starter_card.tscn")
## Base stat that fills a bar completely.
const STAT_BAR_MAX := 100.0
const OPTION_TEXT := Color("f2ebd9")
const OPTION_TEXT_SELECTED := Color("222034")

@export var option_style: StyleBox
@export var option_selected_style: StyleBox

var _options: Array[CreatureSpecies] = []
var _cards: Array[StarterCard] = []
var _index := 0
var _confirming := false
var _confirm_yes := true
var _bars: Dictionary = {}
var _bar_fill := StyleBoxFlat.new()

@onready var _card_row: HBoxContainer = %Cards
@onready var _detail_name: Label = %DetailName
@onready var _detail_subtitle: Label = %DetailSubtitle
@onready var _description: Label = %Description
@onready var _stats_grid: GridContainer = %StatsGrid
@onready var _confirm: Control = %Confirm
@onready var _question: Label = %Question
@onready var _yes_option: PanelContainer = %YesOption
@onready var _no_option: PanelContainer = %NoOption


func _ready() -> void:
	_build_stat_rows()
	_yes_option.gui_input.connect(_on_option_input.bind(true))
	_no_option.gui_input.connect(_on_option_input.bind(false))


func open(options: Array[CreatureSpecies]) -> void:
	_options = options
	for card in _cards:
		card.queue_free()
	_cards.clear()
	for species in options:
		var card := CARD_SCENE.instantiate() as StarterCard
		_card_row.add_child(card)
		card.setup(species)
		card.clicked.connect(_on_card_clicked)
		_cards.append(card)
	_hide_confirm()
	_select(0)
	show()


func get_selected_species() -> CreatureSpecies:
	return _options[_index] if _index < _options.size() else null


func is_confirming() -> bool:
	return _confirming


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _options.is_empty():
		return
	var left := _pressed(event, [&"ui_left", &"move_left"])
	var right := _pressed(event, [&"ui_right", &"move_right"])
	var accept := _pressed(event, [&"ui_accept", &"interact"])
	var cancel := _pressed(event, [&"ui_cancel"])
	if not (left or right or accept or cancel):
		return
	get_viewport().set_input_as_handled()

	if _confirming:
		if left or right:
			_set_confirm_choice(not _confirm_yes)
		elif accept:
			_resolve_confirm(_confirm_yes)
		else:
			_resolve_confirm(false)
	elif left or right:
		_select(_index + (-1 if left else 1))
	elif accept:
		_show_confirm()
	else:
		cancelled.emit()


func _pressed(event: InputEvent, actions: Array[StringName]) -> bool:
	for action in actions:
		if event.is_action_pressed(action):
			return true
	return false


func _select(index: int) -> void:
	_index = wrapi(index, 0, _options.size())
	for i in _cards.size():
		_cards[i].set_selected(i == _index)

	var species := _options[_index]
	_detail_name.text = species.display_name
	var element_name := species.element.display_name if species.element else ""
	_detail_subtitle.text = "%s  ·  %s" % [element_name, species.role]
	_description.text = species.description
	_bar_fill.bg_color = species.element.color if species.element else Color.WHITE
	for stat in _bars:
		var bar := _bars[stat] as ProgressBar
		var target := species.get_base_stat(stat) / STAT_BAR_MAX * bar.max_value
		create_tween().tween_property(bar, "value", target, 0.15)


func _show_confirm() -> void:
	_confirming = true
	_question.text = "Choose %s as your first companion?" % _options[_index].display_name
	_set_confirm_choice(true)
	_confirm.show()


func _hide_confirm() -> void:
	_confirming = false
	_confirm.hide()


func _set_confirm_choice(yes: bool) -> void:
	_confirm_yes = yes
	for option in [_yes_option, _no_option]:
		var selected: bool = (option == _yes_option) == yes
		option.add_theme_stylebox_override(&"panel", option_selected_style if selected else option_style)
		(option.get_child(0) as Label).add_theme_color_override(
				&"font_color", OPTION_TEXT_SELECTED if selected else OPTION_TEXT)


func _resolve_confirm(yes: bool) -> void:
	_hide_confirm()
	if yes:
		species_chosen.emit(_options[_index])


func _on_card_clicked(card: StarterCard) -> void:
	if _confirming:
		return
	var index := _cards.find(card)
	if index == _index:
		_show_confirm()
	else:
		_select(index)


func _on_option_input(event: InputEvent, yes: bool) -> void:
	if _confirming and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_resolve_confirm(yes)


func _build_stat_rows() -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.08, 0.13)
	for stat in CreatureStats.Stat.values():
		var label := Label.new()
		label.text = CreatureStats.DISPLAY_NAMES[stat]
		label.custom_minimum_size.x = 34
		label.add_theme_font_size_override(&"font_size", 7)
		label.add_theme_color_override(&"font_color", Color("b8b2a4"))
		_stats_grid.add_child(label)

		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.custom_minimum_size = Vector2(0, 5)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override(&"background", track)
		bar.add_theme_stylebox_override(&"fill", _bar_fill)
		_stats_grid.add_child(bar)
		_bars[stat] = bar
