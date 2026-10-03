class_name MenuList
extends VBoxContainer
## A vertical list of selectable rows, used by the party, storage and shop screens. Keyboard
## (Up/Down or W/S, Enter/Space/E) and mouse (hover selects, click activates) both work.
##
## The owning screen decides which list receives keys by calling handle_input(); a list never
## reads input on its own, so several lists can share a screen. Rows are arrays of cells; a cell
## is a String or a Dictionary {text, color, width, align, expand, clip}.

signal activated(index: int)
signal selection_changed(index: int)

## How many rows are shown at once; the rest scroll. 0 shows every row.
@export var visible_rows := 0
@export var font_size := 7
@export var cell_separation := 6

## Lists that aren't focused still show their rows, but ignore the mouse and dim their highlight.
var focused := true:
	set(value):
		focused = value
		_refresh_highlight()

var _panels: Array[PanelContainer] = []
var _index := 0
var _scroll := 0
var _placeholder: Label


func _ready() -> void:
	add_theme_constant_override(&"separation", 1)


## Shows `rows`. Existing row controls are updated in place (so a refresh never frees the row
## under the mouse); rows are only created or removed when the count changes.
func set_rows(rows: Array, placeholder := "") -> void:
	while _panels.size() > rows.size():
		var extra: PanelContainer = _panels.pop_back()
		remove_child(extra)
		extra.queue_free()
	for i in rows.size():
		if i < _panels.size():
			_fill_row(_panels[i], rows[i])
		else:
			_panels.append(_make_row(rows[i], i))
	if _placeholder:
		remove_child(_placeholder)
		_placeholder.queue_free()
		_placeholder = null
	if rows.is_empty() and not placeholder.is_empty():
		_placeholder = UiStyle.label(placeholder, font_size, UiStyle.TEXT_DIM)
		add_child(_placeholder)
	_index = clampi(_index, 0, maxi(rows.size() - 1, 0))
	_update_window()
	_refresh_highlight()


func get_row_count() -> int:
	return _panels.size()


func get_selected() -> int:
	return _index if not _panels.is_empty() else -1


## The row's control (e.g. to click it in tests), or null.
func get_row(index: int) -> Control:
	return _panels[index] if index >= 0 and index < _panels.size() else null


## The text of every cell in a row, joined with single spaces.
func get_row_text(index: int) -> String:
	var row := get_row(index)
	if row == null:
		return ""
	var parts := PackedStringArray()
	for cell in row.get_child(0).get_children():
		if (cell as Label).text != "":
			parts.append((cell as Label).text)
	return " ".join(parts)


func get_placeholder_text() -> String:
	return _placeholder.text if _placeholder else ""


func select(index: int) -> void:
	if _panels.is_empty():
		return
	var new_index := clampi(index, 0, _panels.size() - 1)
	var changed := new_index != _index
	_index = new_index
	_update_window()
	_refresh_highlight()
	if changed:
		selection_changed.emit(_index)


func can_scroll_up() -> bool:
	return _scroll > 0


func can_scroll_down() -> bool:
	return visible_rows > 0 and _scroll + visible_rows < _panels.size()


## Handles Up/Down/accept for this list. Returns true if the event was used.
func handle_input(event: InputEvent) -> bool:
	if _panels.is_empty():
		return false
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up"):
		select(wrapi(_index - 1, 0, _panels.size()))
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down"):
		select(wrapi(_index + 1, 0, _panels.size()))
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
		activated.emit(_index)
	else:
		return false
	return true


func _make_row(cells: Array, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override(&"separation", cell_separation)
	panel.add_child(hbox)
	_fill_row(panel, cells)
	panel.mouse_entered.connect(_on_row_hovered.bind(index))
	panel.gui_input.connect(_on_row_input.bind(index))
	add_child(panel)
	return panel


func _fill_row(panel: PanelContainer, cells: Array) -> void:
	var hbox := panel.get_child(0) as HBoxContainer
	while hbox.get_child_count() > cells.size():
		var extra := hbox.get_child(hbox.get_child_count() - 1)
		hbox.remove_child(extra)
		extra.queue_free()
	while hbox.get_child_count() < cells.size():
		hbox.add_child(UiStyle.label("", font_size))
	for i in cells.size():
		var cell: Variant = cells[i]
		var spec: Dictionary = cell if cell is Dictionary else {"text": str(cell)}
		var label := hbox.get_child(i) as Label
		label.text = str(spec.get("text", ""))
		label.add_theme_color_override(&"font_color", spec.get("color", UiStyle.TEXT))
		label.custom_minimum_size.x = float(spec.get("width", 0))
		label.horizontal_alignment = spec.get("align", HORIZONTAL_ALIGNMENT_LEFT)
		label.clip_text = spec.get("clip", false)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if spec.get("expand", false) else Control.SIZE_FILL


func _update_window() -> void:
	if visible_rows <= 0:
		_scroll = 0
	else:
		_scroll = clampi(_scroll, maxi(_index - visible_rows + 1, 0), _index)
		_scroll = clampi(_scroll, 0, maxi(_panels.size() - visible_rows, 0))
	for i in _panels.size():
		_panels[i].visible = visible_rows <= 0 or (i >= _scroll and i < _scroll + visible_rows)


func _refresh_highlight() -> void:
	for i in _panels.size():
		var style := UiStyle.row(i == _index)
		if i == _index and not focused:
			style.bg_color.a = 0.06
			style.border_color.a = 0.35
		_panels[i].add_theme_stylebox_override(&"panel", style)


func _on_row_hovered(index: int) -> void:
	if focused and is_visible_in_tree():
		select(index)


func _on_row_input(event: InputEvent, index: int) -> void:
	if focused and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select(index)
		_panels[index].accept_event()
		activated.emit(index)
