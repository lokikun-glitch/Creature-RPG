class_name PartyScreen
extends Control
## The overworld party screen (pause menu -> Creatures). Shows all six slots straight from
## PartyManager and lets the player view a creature's summary (and rename it), choose the lead
## and reorder the party. Every change goes through CreatureManagement; this screen holds no
## creature state of its own. Separate from the battle CREATURE menu on purpose.

signal closed

enum Mode { LIST, ACTIONS, MOVING }
enum Action { SUMMARY, LEAD, MOVE, CANCEL }

const TITLE := "CREATURES"
const HINT := "Enter: options    Esc: back"
const MOVE_HINT := "Choose a slot, then Enter.    Esc: cancel"
const MOVE_PROMPT := "Move {name} to which slot?"
const ACTION_NAMES := ["SUMMARY", "SET AS LEAD", "MOVE", "CANCEL"]
const NOTHING_TO_MOVE := "There's no other creature to swap with yet."

var _mode := Mode.LIST
var _move_from := -1
var _list: MenuList
var _actions: MenuList
var _actions_panel: PanelContainer
var _coins: Label
var _message: Label
var _hint: Label
var _details: CreatureDetailPanel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.08, 0.08, 0.13, 1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", UiStyle.panel(6, 4))
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UiStyle.label(TITLE, 10, UiStyle.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_coins = UiStyle.label("", 7, UiStyle.TEXT_DIM)
	_coins.name = "Coins"
	_coins.add_to_group(SaveNotice.AVOID_GROUP)
	header.add_child(_coins)
	_list = MenuList.new()
	_list.name = "PartyList"
	_list.cell_separation = 4
	_list.activated.connect(_on_slot_activated)
	box.add_child(_list)
	_message = UiStyle.label("", 7, UiStyle.GOOD)
	_message.name = "Message"
	_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	box.add_child(_message)
	_hint = UiStyle.label(HINT, 6, UiStyle.TEXT_DIM)
	box.add_child(_hint)

	_actions_panel = PanelContainer.new()
	_actions_panel.add_theme_stylebox_override(&"panel", UiStyle.panel(4, 3))
	_actions_panel.position = Vector2(232, 60)
	add_child(_actions_panel)
	_actions = MenuList.new()
	_actions.name = "Actions"
	_actions.activated.connect(_on_action)
	_actions_panel.add_child(_actions)
	_actions_panel.hide()

	_details = CreatureDetailPanel.new()
	_details.name = "Details"
	add_child(_details)
	_details.closed.connect(_refresh)
	PartyManager.party_changed.connect(func() -> void:
		if visible:
			_refresh())
	hide()


func open() -> void:
	_message.text = ""
	_set_mode(Mode.LIST)
	_list.select(PartyManager.get_active_index())
	_refresh()
	show()


func close() -> void:
	if not visible:
		return
	_details.close()
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func get_list() -> MenuList:
	return _list


func get_actions() -> MenuList:
	return _actions


func get_details() -> CreatureDetailPanel:
	return _details


func get_message() -> String:
	return _message.text


func get_mode() -> Mode:
	return _mode


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _details.is_open():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		match _mode:
			Mode.LIST:
				close()
			Mode.ACTIONS, Mode.MOVING:
				_set_mode(Mode.LIST)
				_message.text = ""
		return
	var target := _actions if _mode == Mode.ACTIONS else _list
	if target.handle_input(event):
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var rows := []
	for slot in PartyManager.MAX_PARTY_SIZE:
		var creature := PartyManager.get_creature(slot)
		if creature:
			rows.append(CreatureRow.cells(creature, slot == PartyManager.get_active_index(),
					_mode == Mode.MOVING and slot == _move_from))
		else:
			rows.append(CreatureRow.empty_cells())
	_list.set_rows(rows)
	_coins.text = Wallet.format(GameSession.wallet.get_coins())


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_actions_panel.visible = mode == Mode.ACTIONS
	_list.focused = mode != Mode.ACTIONS
	_actions.focused = mode == Mode.ACTIONS
	_hint.text = MOVE_HINT if mode == Mode.MOVING else HINT
	if mode != Mode.MOVING:
		_move_from = -1
	_refresh()


func _on_slot_activated(slot: int) -> void:
	if _mode == Mode.MOVING:
		var from := _move_from
		var problem := CreatureManagement.move(from, slot)
		var moved := PartyManager.get_creature(slot)
		_set_mode(Mode.LIST)
		_message.text = problem if not problem.is_empty() else CreatureManagement.message(CreatureManagement.MOVED, moved)
		_list.select(slot)
		return
	if PartyManager.get_creature(slot) == null:
		_message.text = CreatureManagement.SLOT_EMPTY
		return
	_actions.set_rows(ACTION_NAMES.map(func(name: String) -> Array: return [name]))
	_actions.select(Action.SUMMARY)
	_actions_panel.position.y = clampf(_list.get_row(slot).global_position.y - 4, 20, 100)
	_set_mode(Mode.ACTIONS)


func _on_action(action: int) -> void:
	var slot := _list.get_selected()
	var creature := PartyManager.get_creature(slot)
	_set_mode(Mode.LIST)
	match action:
		Action.SUMMARY:
			_details.open(creature)
		Action.LEAD:
			var problem := CreatureManagement.set_lead(slot)
			_message.text = problem if not problem.is_empty() \
					else CreatureManagement.message(CreatureManagement.LEAD_CHANGED, creature)
		Action.MOVE:
			if PartyManager.get_size() < 2:
				_message.text = NOTHING_TO_MOVE
				return
			_move_from = slot
			_set_mode(Mode.MOVING)
			_message.text = MOVE_PROMPT.format({"name": creature.get_display_name()})
