class_name ShopScreen
extends WorldMenu
## A simple shop: lists what's for sale with prices and how many you own, then asks how many to
## buy. Prices and funds are checked by Shop, and GameSession.buy_item() makes the purchase and
## saves; this screen never changes Coins or items itself.

enum Mode { LIST, QUANTITY }

const LEAVE := "LEAVE"
const HINT := "Enter: buy    Esc: leave"
const QUANTITY_HINT := "Left/Right: -1/+1   Up/Down: +10/-10   Enter: buy   Esc: back"
const BOUGHT := "You bought {count} {item}."

var _mode := Mode.LIST
var _stock: Array[ItemData] = []
var _quantity := 1
var _title: Label
var _coins: Label
var _list: MenuList
var _description: Label
var _message: Label
var _hint: Label
var _quantity_overlay: Control
var _quantity_panel: PanelContainer
var _quantity_label: Label
var _total_label: Label
var _buy_button: PanelContainer


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UiStyle.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 120)
	panel.add_theme_stylebox_override(&"panel", UiStyle.panel(8, 5))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = UiStyle.label("", 9, UiStyle.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_coins = UiStyle.label("", 7)
	_coins.name = "Coins"
	_coins.add_to_group(SaveNotice.AVOID_GROUP)
	header.add_child(_coins)
	_list = MenuList.new()
	_list.name = "ItemList"
	_list.activated.connect(_on_row_activated)
	_list.selection_changed.connect(func(_index: int) -> void: _update_description())
	box.add_child(_list)
	_description = UiStyle.label("", 6, UiStyle.TEXT_DIM)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(224, 16)
	box.add_child(_description)
	_message = UiStyle.label("", 7, UiStyle.GOOD)
	_message.name = "Message"
	box.add_child(_message)
	_hint = UiStyle.label(HINT, 6, UiStyle.TEXT_DIM)
	box.add_child(_hint)

	_quantity_overlay = Control.new()
	_quantity_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quantity_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_quantity_overlay)
	_quantity_overlay.add_child(UiStyle.backdrop())
	var quantity_center := CenterContainer.new()
	quantity_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quantity_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quantity_overlay.add_child(quantity_center)
	_quantity_panel = PanelContainer.new()
	_quantity_panel.custom_minimum_size = Vector2(150, 0)
	_quantity_panel.add_theme_stylebox_override(&"panel", UiStyle.panel(10, 6))
	quantity_center.add_child(_quantity_panel)
	var quantity_box := VBoxContainer.new()
	quantity_box.add_theme_constant_override(&"separation", 4)
	_quantity_panel.add_child(quantity_box)
	quantity_box.add_child(UiStyle.label("How many?", 8, UiStyle.ACCENT))
	var stepper := HBoxContainer.new()
	stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	stepper.add_theme_constant_override(&"separation", 8)
	quantity_box.add_child(stepper)
	stepper.add_child(_button("-", func() -> void: _change_quantity(-1)))
	_quantity_label = UiStyle.label("", 8)
	_quantity_label.name = "Quantity"
	_quantity_label.custom_minimum_size.x = 30
	_quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stepper.add_child(_quantity_label)
	stepper.add_child(_button("+", func() -> void: _change_quantity(1)))
	_total_label = UiStyle.label("", 7)
	_total_label.name = "Total"
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_box.add_child(_total_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 12)
	quantity_box.add_child(buttons)
	_buy_button = _button("BUY", _buy_selected)
	buttons.add_child(_buy_button)
	buttons.add_child(_button("BACK", func() -> void: _set_mode(Mode.LIST)))
	_quantity_overlay.hide()


func open(shop_name: String, stock: Array[ItemData], greeting := "") -> void:
	_title.text = shop_name
	_stock = stock
	_message.text = greeting
	_set_mode(Mode.LIST)
	_list.select(0)
	_update_description()
	_open_menu()


func close() -> void:
	_close_menu()


func get_list() -> MenuList:
	return _list


func get_mode() -> Mode:
	return _mode


func get_quantity() -> int:
	return _quantity


func get_message() -> String:
	return _message.text


func get_coins_text() -> String:
	return _coins.text


func get_buy_button() -> Control:
	return _buy_button


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _is_opening_input():
		return
	var handled := true
	if _mode == Mode.QUANTITY:
		if event.is_action_pressed(&"ui_cancel"):
			_set_mode(Mode.LIST)
		elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
			_change_quantity(-1)
		elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
			_change_quantity(1)
		elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up"):
			_change_quantity(10)
		elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down"):
			_change_quantity(-10)
		elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
			_buy_selected()
		else:
			handled = false
	elif event.is_action_pressed(&"ui_cancel"):
		close()
	else:
		handled = _list.handle_input(event)
	if handled:
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var rows := []
	for item in _stock:
		rows.append([
			{"text": item.display_name, "expand": true},
			{"text": "%d" % item.price, "width": 34, "align": HORIZONTAL_ALIGNMENT_RIGHT, "color": UiStyle.ACCENT},
			{"text": "Own %d" % GameSession.inventory.get_quantity(item.id), "width": 40,
					"align": HORIZONTAL_ALIGNMENT_RIGHT, "color": UiStyle.TEXT_DIM},
		])
	rows.append([{"text": LEAVE, "expand": true}])
	_list.set_rows(rows)
	_coins.text = Wallet.format(GameSession.wallet.get_coins())


func _update_description() -> void:
	var item := _selected_item()
	_description.text = item.description if item else ""


func _selected_item() -> ItemData:
	var index := _list.get_selected()
	return _stock[index] if index >= 0 and index < _stock.size() else null


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_quantity_overlay.visible = mode == Mode.QUANTITY
	_list.focused = mode == Mode.LIST
	_hint.text = QUANTITY_HINT if mode == Mode.QUANTITY else HINT
	_refresh()


func _on_row_activated(index: int) -> void:
	if index >= _stock.size():
		close()
		return
	var item := _stock[index]
	if Shop.max_affordable(item.id, GameSession.wallet) < 1:
		_message.text = Shop.NOT_ENOUGH_COINS
		return
	_message.text = ""
	_quantity = 1
	_set_mode(Mode.QUANTITY)
	_update_quantity()


func _change_quantity(delta: int) -> void:
	var item := _selected_item()
	if item == null:
		return
	_quantity = clampi(_quantity + delta, 1, maxi(Shop.max_affordable(item.id, GameSession.wallet), 1))
	_update_quantity()


func _update_quantity() -> void:
	var item := _selected_item()
	_quantity_label.text = "x%d" % _quantity
	_total_label.text = "%s  -  %s" % [item.display_name, Wallet.format(Shop.get_total(item.id, _quantity))]


func _buy_selected() -> void:
	var item := _selected_item()
	if item == null:
		return
	var problem := GameSession.buy_item(item.id, _quantity)
	_set_mode(Mode.LIST)
	if not problem.is_empty():
		_message.text = problem
		return
	var item_name := item.display_name + ("s" if _quantity != 1 else "")
	_message.text = BOUGHT.format({"count": _quantity, "item": item_name})


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
