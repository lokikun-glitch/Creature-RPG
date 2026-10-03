class_name CreatureDetailPanel
extends Control
## Full-screen summary of one owned creature: nickname, species, level, element, role, HP, EXP,
## moves and status. Species facts come from CreatureSpecies, individual state from the
## CreatureInstance; internal ids and UIDs are never shown. Offers RENAME (through
## CreatureManagement) and BACK. Used by the party and storage screens.

signal closed
## Emitted after a successful rename, with the message that was shown.
signal nickname_changed(message: String)

enum Option { RENAME, BACK }

var _creature: CreatureInstance
var _sprite: TextureRect
var _name: Label
var _subtitle: Label
var _stats: Label
var _moves: Label
var _message: Label
var _options: MenuList
var _nickname: NicknameDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiStyle.backdrop())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", UiStyle.panel(10, 6))
	margin.add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 10)
	panel.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 64
	columns.add_child(left)
	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = Vector2(64, 64)
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	left.add_child(_sprite)
	_options = MenuList.new()
	_options.font_size = 7
	_options.activated.connect(_on_option)
	left.add_child(_options)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 3)
	columns.add_child(right)
	_name = UiStyle.label("", 10, UiStyle.ACCENT)
	_name.name = "Nickname"
	right.add_child(_name)
	_subtitle = UiStyle.label("", 7, UiStyle.TEXT_DIM)
	_subtitle.name = "Subtitle"
	right.add_child(_subtitle)
	_stats = UiStyle.label("", 7)
	_stats.name = "Stats"
	right.add_child(_stats)
	right.add_child(UiStyle.label("MOVES", 7, UiStyle.ACCENT))
	_moves = UiStyle.label("", 7)
	_moves.name = "Moves"
	right.add_child(_moves)
	_message = UiStyle.label("", 7, UiStyle.GOOD)
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	right.add_child(_message)

	_nickname = NicknameDialog.new()
	_nickname.name = "NicknameDialog"
	add_child(_nickname)
	_nickname.submitted.connect(_on_nickname_submitted)
	_nickname.cancelled.connect(func() -> void: _options.focused = true)
	hide()


func open(creature: CreatureInstance) -> void:
	_creature = creature
	_message.text = ""
	_options.set_rows([["RENAME"], ["BACK"]])
	_options.select(Option.RENAME)
	_options.focused = true
	refresh()
	show()


func close() -> void:
	if not visible:
		return
	_nickname.close()
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func get_creature() -> CreatureInstance:
	return _creature


func get_options() -> MenuList:
	return _options


func get_nickname_dialog() -> NicknameDialog:
	return _nickname


func get_message() -> String:
	return _message.text


## Every line of text on the panel, for tests and debugging.
func get_text() -> String:
	return "\n".join([_name.text, _subtitle.text, _stats.text, _moves.text])


func refresh() -> void:
	var creature := _creature
	var species := creature.get_species()
	var element := species.element if species else null
	_sprite.texture = species.sprite if species else null
	_name.text = creature.get_display_name()
	var subtitle := PackedStringArray([species.display_name if species else String(creature.species_id)])
	if element:
		subtitle.append(element.display_name)
	if species and not species.role.is_empty():
		subtitle.append(species.role)
	_subtitle.text = "  |  ".join(subtitle)
	var status := "Healthy" if creature.current_hp > 0 and creature.status.is_empty() else CreatureRow.status_text(creature)
	_stats.text = "Level %d\nHP %d / %d\nEXP %d / %d\nStatus: %s" % [
		creature.level, creature.current_hp, creature.get_max_hp(),
		creature.experience, CreatureProgression.exp_to_next_level(creature.level), status]
	var moves := PackedStringArray()
	for move_id in creature.move_ids:
		var move := CreatureDatabase.get_move(move_id)
		if move:
			moves.append("%s  (%s, power %d)" % [move.display_name,
					move.element.display_name if move.element else "-", move.power])
	_moves.text = "\n".join(moves) if not moves.is_empty() else "-"


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _nickname.is_open():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif _options.handle_input(event):
		get_viewport().set_input_as_handled()


func _on_option(index: int) -> void:
	if index == Option.RENAME:
		_options.focused = false
		_message.text = ""
		_nickname.open(_creature.get_display_name())
	else:
		close()


func _on_nickname_submitted(text: String) -> void:
	var problem := CreatureManagement.rename(_creature, text)
	if not problem.is_empty():
		_nickname.show_error(problem)
		return
	_nickname.close()
	_options.focused = true
	refresh()
	_message.text = CreatureManagement.message(CreatureManagement.NICKNAME_CHANGED, _creature)
	nickname_changed.emit(_message.text)
