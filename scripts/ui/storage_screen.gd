class_name StorageScreen
extends WorldMenu
## Creature Storage, opened at the storage terminal. Two tabs, PARTY and STORAGE (Left/Right or
## click to switch), each listing creatures with the same details as the party screen. Lets the
## player view a summary (and rename), deposit a party creature and withdraw a stored one. All
## changes go through CreatureManagement, which also saves; this screen only displays.

enum Tab { PARTY, STORAGE }
enum Mode { LIST, ACTIONS }

const TITLE := "CREATURE STORAGE"
const EMPTY_STORAGE := "No creatures in storage."
const HINT := "Left/Right: party / storage    Enter: options    Esc: leave"
const VISIBLE_ROWS := 6

var _tab := Tab.PARTY
var _mode := Mode.LIST
var _tab_labels: Array[PanelContainer] = []
var _list: MenuList
var _actions: MenuList
var _actions_panel: PanelContainer
var _range: Label
var _message: Label
var _details: CreatureDetailPanel


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var background := ColorRect.new()
	background.color = Color(0.08, 0.08, 0.13, 1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	root.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", UiStyle.panel(6, 4))
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	panel.add_child(box)
	box.add_child(UiStyle.label(TITLE, 10, UiStyle.ACCENT))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 6)
	box.add_child(tabs)
	for tab in [Tab.PARTY, Tab.STORAGE]:
		var tab_panel := PanelContainer.new()
		tab_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		tab_panel.add_child(UiStyle.label("", 7))
		tab_panel.gui_input.connect(_on_tab_input.bind(tab))
		tabs.add_child(tab_panel)
		_tab_labels.append(tab_panel)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	_range = UiStyle.label("", 6, UiStyle.TEXT_DIM)
	_range.name = "Range"
	tabs.add_child(_range)
	_list = MenuList.new()
	_list.name = "CreatureList"
	_list.visible_rows = VISIBLE_ROWS
	_list.cell_separation = 4
	_list.activated.connect(_on_row_activated)
	_list.selection_changed.connect(func(_index: int) -> void: _update_range())
	box.add_child(_list)
	_message = UiStyle.label("", 7, UiStyle.GOOD)
	_message.name = "Message"
	_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	box.add_child(_message)
	box.add_child(UiStyle.label(HINT, 6, UiStyle.TEXT_DIM))

	_actions_panel = PanelContainer.new()
	_actions_panel.add_theme_stylebox_override(&"panel", UiStyle.panel(4, 3))
	_actions_panel.position = Vector2(236, 60)
	root.add_child(_actions_panel)
	_actions = MenuList.new()
	_actions.name = "Actions"
	_actions.activated.connect(_on_action)
	_actions_panel.add_child(_actions)
	_actions_panel.hide()

	_details = CreatureDetailPanel.new()
	_details.name = "Details"
	root.add_child(_details)
	_details.closed.connect(_refresh)


func open() -> void:
	_message.text = ""
	_tab = Tab.PARTY
	_set_mode(Mode.LIST)
	_list.select(0)
	_open_menu()


func close() -> void:
	_details.close()
	_close_menu()


func get_tab() -> Tab:
	return _tab


func get_mode() -> Mode:
	return _mode


## "1-6 of 10" when the list scrolls, otherwise "".
func get_range_text() -> String:
	return _range.text


func get_list() -> MenuList:
	return _list


func get_actions() -> MenuList:
	return _actions


func get_details() -> CreatureDetailPanel:
	return _details


func get_message() -> String:
	return _message.text


func get_tab_control(tab: Tab) -> Control:
	return _tab_labels[tab]


## The creature on the selected row of the current tab, or null.
func get_selected_creature() -> CreatureInstance:
	return _creature_at(_list.get_selected())


func set_tab(tab: Tab) -> void:
	_tab = tab
	_set_mode(Mode.LIST)
	_list.select(0)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _details.is_open() or _is_opening_input():
		return
	var handled := true
	if event.is_action_pressed(&"ui_cancel"):
		if _mode == Mode.ACTIONS:
			_set_mode(Mode.LIST)
		else:
			close()
	elif _mode == Mode.ACTIONS:
		handled = _actions.handle_input(event)
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left") \
			or event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		set_tab(Tab.STORAGE if _tab == Tab.PARTY else Tab.PARTY)
	else:
		handled = _list.handle_input(event)
	if handled:
		get_viewport().set_input_as_handled()


func _creatures() -> Array[CreatureInstance]:
	return PartyManager.get_party() if _tab == Tab.PARTY else GameSession.storage.get_all()


func _creature_at(index: int) -> CreatureInstance:
	var creatures := _creatures()
	return creatures[index] if index >= 0 and index < creatures.size() else null


func _refresh() -> void:
	var rows := []
	if _tab == Tab.PARTY:
		for slot in PartyManager.MAX_PARTY_SIZE:
			var creature := PartyManager.get_creature(slot)
			rows.append(CreatureRow.cells(creature, slot == PartyManager.get_active_index()) if creature \
					else CreatureRow.empty_cells())
	else:
		for creature in GameSession.storage.get_all():
			rows.append(CreatureRow.cells(creature))
	_list.set_rows(rows, EMPTY_STORAGE)
	var names := ["PARTY %d/%d" % [PartyManager.get_size(), PartyManager.MAX_PARTY_SIZE],
			"STORAGE %d" % GameSession.storage.get_count()]
	for tab in _tab_labels.size():
		var selected := tab == _tab
		_tab_labels[tab].add_theme_stylebox_override(&"panel", UiStyle.row(selected))
		var label := _tab_labels[tab].get_child(0) as Label
		label.text = names[tab]
		label.add_theme_color_override(&"font_color", UiStyle.ACCENT if selected else UiStyle.TEXT_DIM)
	_update_range()


func _update_range() -> void:
	var count := _list.get_row_count()
	if _tab == Tab.PARTY or count <= VISIBLE_ROWS:
		_range.text = ""
		return
	var first := 0
	for i in count:
		if _list.get_row(i).visible:
			first = i
			break
	_range.text = "%d-%d of %d" % [first + 1, mini(first + VISIBLE_ROWS, count), count]


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_actions_panel.visible = mode == Mode.ACTIONS
	_list.focused = mode == Mode.LIST
	_actions.focused = mode == Mode.ACTIONS
	_refresh()


func _on_row_activated(index: int) -> void:
	var creature := _creature_at(index)
	if creature == null:
		_message.text = CreatureManagement.SLOT_EMPTY if _tab == Tab.PARTY else EMPTY_STORAGE
		return
	var move_text := "DEPOSIT" if _tab == Tab.PARTY else "WITHDRAW"
	_actions.set_rows([["SUMMARY"], [move_text], ["CANCEL"]])
	_actions.select(0)
	_actions_panel.position.y = clampf(_list.get_row(index).global_position.y - 4, 30, 110)
	_set_mode(Mode.ACTIONS)


func _on_action(action: int) -> void:
	var creature := get_selected_creature()
	_set_mode(Mode.LIST)
	if creature == null:
		return
	match action:
		0:
			_details.open(creature)
		1:
			_transfer(creature)


func _transfer(creature: CreatureInstance) -> void:
	var problem := CreatureManagement.deposit(creature) if _tab == Tab.PARTY else CreatureManagement.withdraw(creature)
	if not problem.is_empty():
		_message.text = problem
		return
	_message.text = CreatureManagement.message(
			CreatureManagement.DEPOSITED if _tab == Tab.PARTY else CreatureManagement.WITHDRAWN, creature)
	_refresh()


func _on_tab_input(event: InputEvent, tab: Tab) -> void:
	if _mode == Mode.LIST and not _details.is_open() and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_tab_labels[tab].accept_event()
		set_tab(tab)
