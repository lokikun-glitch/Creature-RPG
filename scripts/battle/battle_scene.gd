class_name BattleScene
extends CanvasLayer
## Presents battles: shows both creatures, collects the player's choices and plays back the
## BattleEvents that BattleManager returns, with messages and simple animations. It never decides
## outcomes (every action is resolved by BattleManager); the world map stays loaded underneath.

enum UiState { HIDDEN, INTRO, ACTION_MENU, MOVE_MENU, CREATURE_MENU, ITEM_MENU, PLAYING, ENDING }
## Battle menu actions, in grid order: [FIGHT, CREATURE] / [ITEM, RUN].
enum Action { FIGHT, CREATURE, ITEM, RUN }

const TEXT := Color("f2ebd9")
const TEXT_SELECTED := Color("f6cc6b")
const TEXT_DISABLED := Color(0.55, 0.53, 0.62)
## Actions shown but not usable yet. Empty now that items and switching exist; kept for future actions.
const UNAVAILABLE_ACTIONS: Array[Action] = []

## Seconds each message stays up; E / Enter / Space skips ahead. Tests shorten it.
@export var message_delay := 1.1
## Speeds up every animation (tests raise it).
@export var animation_speed := 1.0
@export var option_style: StyleBox
@export var option_selected_style: StyleBox

var ui_state := UiState.HIDDEN
## Every message shown in the current battle, oldest first. Handy for debugging and tests.
var message_log := PackedStringArray()

var _battle: BattleContext
var _action_index: int = Action.FIGHT
var _moves: Array[MoveData] = []
var _move_options: Array[PanelContainer] = []
var _move_index := 0
## Selectable rows of the creature/item list and what choosing each one does.
var _rows: Array[PanelContainer] = []
var _row_actions: Array[Callable] = []
var _row_index := 0
## False while a fainted creature must be replaced: the list can't be closed without choosing.
var _overlay_can_cancel := true
var _skip := false
var _enemy_home := Vector2.ZERO
var _player_home := Vector2.ZERO

@onready var _enemy_sprite: TextureRect = %EnemySprite
@onready var _player_sprite: TextureRect = %PlayerSprite
@onready var _enemy_panel: BattleStatusPanel = %EnemyPanel
@onready var _player_panel: BattleStatusPanel = %PlayerPanel
@onready var _message: Label = %Message
@onready var _move_grid: GridContainer = %MoveGrid
@onready var _action_menu: GridContainer = %ActionMenu
@onready var _action_options: Array[PanelContainer] = [%FightOption, %CreatureOption, %ItemOption, %RunOption]
@onready var _move_info: Control = %MoveInfo
@onready var _move_element: PanelContainer = %MoveElement
@onready var _move_element_label: Label = %MoveElementLabel
@onready var _move_power: Label = %MovePower
@onready var _move_effect: Label = %MoveEffect
@onready var _overlay: Control = %Overlay
@onready var _overlay_title: Label = %OverlayTitle
@onready var _overlay_list: VBoxContainer = %OverlayList
@onready var _overlay_footer: Label = %OverlayFooter
@onready var _overlay_back: PanelContainer = %OverlayBack
@onready var _orb: TextureRect = %Orb
## Trainer battles only: who you're battling and how many of their creatures can still fight.
@onready var _opponent_label: Label = %OpponentLabel


func _ready() -> void:
	hide()
	_enemy_home = _enemy_sprite.position
	_player_home = _player_sprite.position
	for i in _action_options.size():
		_action_options[i].mouse_entered.connect(_on_action_hovered.bind(i))
		_action_options[i].gui_input.connect(_on_action_input.bind(i))
	_overlay_back.add_theme_stylebox_override(&"panel", option_selected_style)
	_overlay_back.gui_input.connect(_on_overlay_back_input)
	BattleManager.battle_started.connect(_on_battle_started)


func get_move_names() -> PackedStringArray:
	var names := PackedStringArray()
	for move in _moves:
		names.append(move.display_name)
	return names


func get_selected_move() -> MoveData:
	return _moves[_move_index] if _move_index < _moves.size() else null


func get_selected_action() -> int:
	return _action_index


func is_action_available(action: int) -> bool:
	return not UNAVAILABLE_ACTIONS.has(action)


func get_overlay_footer() -> String:
	return _overlay_footer.text


func is_overlay_cancellable() -> bool:
	return _overlay_can_cancel


## Text of each row in the creature or item list ("Empty" for free party slots).
## "Young Trainer Rory  1/1" in trainer battles; empty (and hidden) in wild ones.
func get_opponent_text() -> String:
	return _opponent_label.text if _opponent_label.visible else ""


func get_enemy_name() -> String:
	return (_enemy_panel.get_node("%Name") as Label).text


func get_creature_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for row in _overlay_list.get_children():
		if row.is_queued_for_deletion():
			continue
		var texts := PackedStringArray()
		for label in row.find_children("*", "Label", true, false):
			texts.append((label as Label).text)
		rows.append(" ".join(texts))
	return rows


# --- Flow -----------------------------------------------------------------------------------

func _on_battle_started(battle: BattleContext) -> void:
	_battle = battle
	message_log.clear()
	_set_ui(UiState.INTRO)
	await SceneRouter.transition(_open)
	await _play_intro()


func _open() -> void:
	_enemy_sprite.texture = _battle.wild.get_species().sprite
	_player_sprite.texture = _battle.player.get_species().sprite
	for sprite in [_enemy_sprite, _player_sprite]:
		sprite.modulate = Color.WHITE
		sprite.scale = Vector2.ONE
	_orb.hide()
	_enemy_sprite.position = _enemy_home + Vector2(140, 0)
	_player_sprite.position = _player_home - Vector2(140, 0)
	_enemy_panel.show_creature(_battle.display_name(BattleSide.Side.WILD), _battle.wild)
	_player_panel.show_creature(_battle.display_name(BattleSide.Side.PLAYER), _battle.player)
	_update_opponent_label()
	_enemy_panel.modulate.a = 0.0
	_player_panel.modulate.a = 0.0
	_message.text = ""
	_overlay.hide()
	_show_menus(false, false)
	show()


func _play_intro() -> void:
	if _battle.is_trainer_battle():
		var trainer := _battle.trainer.get_title()
		await _say(BattleMessages.TRAINER_CHALLENGE.format({"trainer": trainer}))
		await _slide(_enemy_sprite, _enemy_home, _enemy_panel)
		await _say(BattleMessages.TRAINER_SENT_OUT.format({"trainer": trainer, "name": _battle.wild.get_display_name()}))
	else:
		await _slide(_enemy_sprite, _enemy_home, _enemy_panel)
		await _say(BattleMessages.WILD_APPEARED.format({"name": _battle.wild.get_display_name()}))
	await _slide(_player_sprite, _player_home, _player_panel)
	await _say(BattleMessages.SEND_OUT.format({"name": _battle.player.get_display_name()}))
	BattleManager.begin_player_turn()
	_show_action_menu(Action.FIGHT)


func _show_action_menu(select := -1) -> void:
	_set_ui(UiState.ACTION_MENU)
	_overlay.hide()
	_message.text = BattleMessages.PROMPT.format({"name": _battle.player.get_display_name()})
	_show_menus(true, false)
	_select_action(_action_index if select < 0 else select)


func _select_action(action: int) -> void:
	_action_index = action
	for i in _action_options.size():
		var selected := i == _action_index
		_action_options[i].add_theme_stylebox_override(&"panel", option_selected_style if selected else option_style)
		var color := TEXT_SELECTED if selected else TEXT
		(_action_options[i].get_child(0) as Label).add_theme_color_override(
				&"font_color", color if is_action_available(i) else TEXT_DISABLED)


func _activate_action(action: int) -> void:
	_select_action(action)
	match action:
		Action.FIGHT:
			_show_move_menu()
		Action.CREATURE:
			_show_creature_menu()
		Action.ITEM:
			_show_item_menu()
		Action.RUN:
			var problem := BattleManager.get_run_problem()
			if problem.is_empty():
				_resolve(BattleManager.submit_run())
			else:
				_notice(problem)


func _show_move_menu() -> void:
	_set_ui(UiState.MOVE_MENU)
	_moves = BattleManager.get_player_moves()
	for option in _move_options:
		option.queue_free()
	_move_options.clear()
	for i in _moves.size():
		var move := _moves[i]
		var option := PanelContainer.new()
		option.mouse_filter = Control.MOUSE_FILTER_STOP
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.gui_input.connect(_on_move_input.bind(i))
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := Label.new()
		name_label.text = move.display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override(&"font_size", 8)
		var detail := Label.new()
		detail.text = "%s %d" % [move.element.display_name if move.element else "", move.power]
		detail.add_theme_font_size_override(&"font_size", 6)
		detail.add_theme_color_override(&"font_color", move.element.color if move.element else TEXT)
		row.add_child(name_label)
		row.add_child(detail)
		option.add_child(row)
		_move_grid.add_child(option)
		_move_options.append(option)
	_show_menus(false, true)
	_select_move(0)


func _select_move(index: int) -> void:
	if _moves.is_empty():
		return
	_move_index = clampi(index, 0, _moves.size() - 1)
	for i in _move_options.size():
		var selected := i == _move_index
		_move_options[i].add_theme_stylebox_override(&"panel", option_selected_style if selected else option_style)
		(_move_options[i].get_child(0).get_child(0) as Label).add_theme_color_override(
				&"font_color", TEXT_SELECTED if selected else TEXT)
	var move := _moves[_move_index]
	_move_power.text = "Power %d" % move.power
	_move_effect.text = BattleMessages.effectiveness_label(BattleManager.preview_effectiveness(move.id))
	_move_element.visible = move.element != null
	if move.element:
		_move_element_label.text = move.element.display_name.to_upper()
		var tag := StyleBoxFlat.new()
		tag.bg_color = move.element.color
		tag.set_corner_radius_all(2)
		tag.content_margin_left = 4
		tag.content_margin_right = 4
		_move_element.add_theme_stylebox_override(&"panel", tag)


func _choose_move(index: int) -> void:
	_resolve(BattleManager.submit_move(_moves[index].id))


## Shows why an action was refused without using the turn; the action menu stays open.
func _notice(text: String) -> void:
	message_log.append(text)
	_message.text = text


func _update_opponent_label() -> void:
	_opponent_label.visible = _battle.is_trainer_battle()
	if _opponent_label.visible:
		_opponent_label.text = "%s  %d/%d" % [_battle.trainer.get_title(), _battle.trainer_creatures_left(),
				_battle.trainer_team.size()]


## Plays back whatever BattleManager resolved (a move or a run attempt), then continues or ends.
func _resolve(events: Array[BattleEvent]) -> void:
	if events.is_empty():
		return
	_set_ui(UiState.PLAYING)
	_show_menus(false, false)
	await _play_events(events)
	match BattleManager.state:
		BattleManager.State.PLAYER_ACTION:
			_show_action_menu()
		BattleManager.State.SWITCH_REQUIRED:
			_show_creature_menu(true)
		BattleManager.State.VICTORY, BattleManager.State.DEFEAT, BattleManager.State.ESCAPED, \
				BattleManager.State.CAUGHT:
			_set_ui(UiState.ENDING)
			await SceneRouter.transition(_close)


func _close() -> void:
	hide()
	_set_ui(UiState.HIDDEN)
	_battle = null
	BattleManager.end_battle()


# --- Creature / item menus ------------------------------------------------------------------

## Lists the party straight from PartyManager. Every occupied slot can be highlighted; choosing
## one that can't be sent out (active, fainted) just explains why. `must_choose` is used after the
## active creature fainted: the list can't be closed until a replacement is chosen.
func _show_creature_menu(must_choose := false) -> void:
	_open_overlay(UiState.CREATURE_MENU, "CHOOSE A CREATURE" if must_choose else "YOUR CREATURES", not must_choose)
	var party := PartyManager.get_party()
	for slot in PartyManager.MAX_PARTY_SIZE:
		if slot >= party.size():
			_add_placeholder_row("Empty")
			continue
		var creature := party[slot]
		var texts := [creature.get_display_name(), "Lv. %d" % creature.level,
				"%d/%d" % [creature.current_hp, creature.get_max_hp()]]
		if not String(creature.status).is_empty():
			texts.append(String(creature.status).to_upper())
		if slot == PartyManager.get_active_index():
			texts.append(BattleMessages.ACTIVE_TAG)
		elif creature.current_hp <= 0:
			texts.append(BattleMessages.FAINTED_TAG)
		_add_row(texts, PartyManager.can_switch_to(slot), _choose_creature.bind(slot))
	if must_choose:
		_overlay_footer.text = BattleMessages.SWITCH_REQUIRED
	elif party.size() == 1:
		_overlay_footer.text = BattleMessages.ONLY_ONE_CREATURE
	else:
		_overlay_footer.text = "Choose a creature."
	_select_row(PartyManager.get_active_index() if not must_choose else _first_switchable_row())


func _choose_creature(slot: int) -> void:
	var creature := PartyManager.get_creature(slot)
	if creature == null:
		return
	var args := {"name": creature.get_display_name()}
	if slot == PartyManager.get_active_index():
		_overlay_footer.text = BattleMessages.ALREADY_IN_BATTLE.format(args)
	elif creature.current_hp <= 0:
		_overlay_footer.text = BattleMessages.NO_ENERGY.format(args)
	else:
		_close_overlay()
		_resolve(BattleManager.submit_switch(slot))


## Lists every known item with how many the player holds.
func _show_item_menu() -> void:
	_open_overlay(UiState.ITEM_MENU, "ITEMS", true)
	var items := ItemCatalog.get_all_items()
	items.sort_custom(func(a: ItemData, b: ItemData) -> bool: return a.display_name < b.display_name)
	for item in items:
		var count := GameSession.inventory.get_quantity(item.id)
		_add_row([item.display_name, "x%d" % count], count > 0, _choose_item.bind(item.id))
	_overlay_footer.text = "" if not items.is_empty() else BattleMessages.NO_ITEMS
	_select_row(0)


func _choose_item(item_id: StringName) -> void:
	var problem := BattleManager.get_item_problem(item_id)
	if not problem.is_empty():
		_overlay_footer.text = problem
		return
	_close_overlay()
	_resolve(BattleManager.submit_item(item_id))


func _open_overlay(state: UiState, title: String, can_cancel: bool) -> void:
	_set_ui(state)
	for child in _overlay_list.get_children():
		_overlay_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_row_actions.clear()
	_overlay_title.text = title
	_overlay_can_cancel = can_cancel
	_overlay_back.visible = can_cancel
	_overlay.show()


func _close_overlay() -> void:
	_overlay.hide()


## A selectable row. `usable` only changes how it looks; choosing it always runs `action`, which
## explains the problem when the row can't be used.
func _add_row(texts: Array, usable: bool, action: Callable) -> void:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override(&"separation", 6)
	row.add_child(hbox)
	for i in texts.size():
		var label := _add_row_label(hbox, texts[i], i == 0)
		if not usable:
			label.add_theme_color_override(&"font_color", TEXT_DISABLED)
	row.gui_input.connect(_on_row_input.bind(_rows.size()))
	_overlay_list.add_child(row)
	_rows.append(row)
	_row_actions.append(action)


func _add_placeholder_row(text: String) -> void:
	var row := PanelContainer.new()
	var hbox := HBoxContainer.new()
	row.add_child(hbox)
	_add_row_label(hbox, text, true).add_theme_color_override(&"font_color", TEXT_DISABLED)
	_overlay_list.add_child(row)


func _select_row(index: int) -> void:
	if _rows.is_empty():
		return
	_row_index = clampi(index, 0, _rows.size() - 1)
	for i in _rows.size():
		_rows[i].add_theme_stylebox_override(&"panel", option_selected_style if i == _row_index else option_style)


func _first_switchable_row() -> int:
	for slot in PartyManager.get_size():
		if PartyManager.can_switch_to(slot):
			return slot
	return 0


func _add_row_label(row: HBoxContainer, text: String, expand: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 7)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return label


# --- Event playback -------------------------------------------------------------------------

func _play_events(events: Array[BattleEvent]) -> void:
	for i in events.size():
		var event := events[i]
		var lines := BattleMessages.describe(event, _battle)
		var next_is_level_up := i + 1 < events.size() and events[i + 1].type == BattleEvent.Type.LEVEL_UP
		match event.type:
			BattleEvent.Type.MOVE_USED:
				await _say(lines[0])
				await _lunge(event.side)
			BattleEvent.Type.DAMAGE:
				await _flash(_sprite_for(event.side))
				await _panel_for(event.side).animate_hp(event.hp_before, event.hp_after, _time(0.5))
				for line in lines:
					await _say(line)
			BattleEvent.Type.FAINTED:
				await _faint(_sprite_for(event.side))
				if event.side == BattleSide.Side.WILD and _battle.is_trainer_battle():
					_update_opponent_label()
				await _say(lines[0])
			BattleEvent.Type.TRAINER_SENT_OUT:
				_enemy_sprite.texture = event.creature.get_species().sprite
				_enemy_sprite.modulate = Color.WHITE
				_enemy_sprite.scale = Vector2.ONE
				_enemy_sprite.position = _enemy_home + Vector2(140, 0)
				_enemy_panel.modulate.a = 0.0
				_enemy_panel.show_creature(_battle.name_of(event.creature, BattleSide.Side.WILD), event.creature)
				await _slide(_enemy_sprite, _enemy_home, _enemy_panel)
				await _say(lines[0])
			BattleEvent.Type.EXP_GAINED:
				await _say(lines[0])
				var target := 1.0 if next_is_level_up else BattleStatusPanel.exp_ratio(_battle.player)
				await _player_panel.animate_exp_ratio(target, _time(0.5))
			BattleEvent.Type.LEVEL_UP:
				_player_panel.set_level(event.level, _battle.player.get_max_hp(), _battle.player.current_hp)
				_player_panel.set_exp_ratio(0.0)
				await _say(lines[0])
				if not next_is_level_up:
					await _player_panel.animate_exp_ratio(BattleStatusPanel.exp_ratio(_battle.player), _time(0.4))
			BattleEvent.Type.ESCAPED:
				await _say(lines[0])
				await _retreat()
			BattleEvent.Type.RECALLED:
				await _say(lines[0])
				await _retreat()
			BattleEvent.Type.SENT_OUT:
				_player_sprite.texture = event.creature.get_species().sprite
				_player_sprite.modulate = Color.WHITE
				_player_sprite.position = _player_home - Vector2(140, 0)
				_player_panel.modulate.a = 0.0
				_player_panel.show_creature(_battle.display_name(BattleSide.Side.PLAYER), event.creature)
				await _slide(_player_sprite, _player_home, _player_panel)
				await _say(lines[0])
			BattleEvent.Type.CAPTURE_THROWN:
				await _say(lines[0])
				await _throw_orb()
			BattleEvent.Type.CAPTURE_SUCCEEDED:
				await _say(lines[0])
			BattleEvent.Type.CAPTURE_FAILED:
				await _break_free()
				await _say(lines[0])
			BattleEvent.Type.SWITCH_REQUIRED:
				pass
			_:
				for line in lines:
					await _say(line)


func _say(text: String) -> void:
	message_log.append(text)
	_message.text = text
	_skip = false
	var waited := 0.0
	while waited < message_delay and not _skip:
		await get_tree().process_frame
		waited += get_process_delta_time()


# --- Animation helpers ----------------------------------------------------------------------

func _time(seconds: float) -> float:
	return seconds / maxf(animation_speed, 0.01)


func _slide(sprite: TextureRect, home: Vector2, panel: Control) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "position", home, _time(0.45)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, _time(0.3))
	await tween.finished


## The orb flies at the wild creature, which shrinks into it.
func _throw_orb() -> void:
	_orb.position = _player_home + Vector2(40, 0)
	_orb.show()
	var tween := create_tween()
	tween.tween_property(_orb, "position", _enemy_home + Vector2(26, 40), _time(0.35))
	tween.tween_property(_enemy_sprite, "scale", Vector2(0.1, 0.1), _time(0.2))
	tween.parallel().tween_property(_enemy_sprite, "modulate:a", 0.0, _time(0.2))
	await tween.finished


func _break_free() -> void:
	_orb.hide()
	var tween := create_tween().set_parallel()
	tween.tween_property(_enemy_sprite, "scale", Vector2.ONE, _time(0.2))
	tween.tween_property(_enemy_sprite, "modulate:a", 1.0, _time(0.2))
	await tween.finished


func _retreat() -> void:
	var tween := create_tween()
	tween.tween_property(_player_sprite, "position", _player_home - Vector2(140, 0), _time(0.35))
	await tween.finished


func _lunge(side: BattleSide.Side) -> void:
	var sprite := _sprite_for(side)
	var home := _enemy_home if side == BattleSide.Side.WILD else _player_home
	var toward := Vector2(-10, 6) if side == BattleSide.Side.WILD else Vector2(10, -6)
	var tween := create_tween()
	tween.tween_property(sprite, "position", home + toward, _time(0.1))
	tween.tween_property(sprite, "position", home, _time(0.12))
	await tween.finished


func _flash(sprite: TextureRect) -> void:
	var tween := create_tween()
	for i in 3:
		tween.tween_property(sprite, "modulate:a", 0.2, _time(0.05))
		tween.tween_property(sprite, "modulate:a", 1.0, _time(0.05))
	await tween.finished


func _faint(sprite: TextureRect) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "position:y", sprite.position.y + 24, _time(0.4))
	tween.tween_property(sprite, "modulate:a", 0.0, _time(0.4))
	await tween.finished


func _sprite_for(side: BattleSide.Side) -> TextureRect:
	return _player_sprite if side == BattleSide.Side.PLAYER else _enemy_sprite


func _panel_for(side: BattleSide.Side) -> BattleStatusPanel:
	return _player_panel if side == BattleSide.Side.PLAYER else _enemy_panel


func _show_menus(action: bool, moves: bool) -> void:
	_action_menu.visible = action
	_move_info.visible = moves
	_move_grid.visible = moves
	_message.visible = not moves


func _set_ui(state: UiState) -> void:
	ui_state = state


# --- Input ----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var accept := event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact")
	var cancel := event.is_action_pressed(&"ui_cancel")
	var left := event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left")
	var right := event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right")
	var up := event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up")
	var down := event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down")
	if not (accept or cancel or left or right or up or down):
		return
	get_viewport().set_input_as_handled()
	match ui_state:
		UiState.ACTION_MENU:
			if accept:
				_activate_action(_action_index)
			elif left or right:
				_select_action(_action_index ^ 1)
			elif up or down:
				_select_action(_action_index ^ 2)
		UiState.MOVE_MENU:
			var columns := _move_grid.columns
			if accept:
				_choose_move(_move_index)
			elif cancel:
				_show_action_menu()
			elif left or right:
				_select_move(_move_index + (-1 if left else 1))
			elif up or down:
				_select_move(_move_index + (-columns if up else columns))
		UiState.CREATURE_MENU, UiState.ITEM_MENU:
			if accept and not _rows.is_empty():
				_row_actions[_row_index].call()
			elif cancel and _overlay_can_cancel:
				_show_action_menu()
			elif up or down:
				_select_row(_row_index + (-1 if up else 1))
		UiState.INTRO, UiState.PLAYING, UiState.ENDING:
			if accept:
				_skip = true


func _on_action_hovered(action: int) -> void:
	if ui_state == UiState.ACTION_MENU:
		_select_action(action)


func _on_action_input(event: InputEvent, action: int) -> void:
	if ui_state == UiState.ACTION_MENU and _clicked(event):
		_activate_action(action)


func _on_move_input(event: InputEvent, index: int) -> void:
	if ui_state != UiState.MOVE_MENU:
		return
	if event is InputEventMouseMotion:
		_select_move(index)
	elif _clicked(event):
		_select_move(index)
		_choose_move(index)


func _on_row_input(event: InputEvent, index: int) -> void:
	if (ui_state == UiState.CREATURE_MENU or ui_state == UiState.ITEM_MENU) and _clicked(event):
		_select_row(index)
		_row_actions[index].call()


func _on_overlay_back_input(event: InputEvent) -> void:
	if (ui_state == UiState.CREATURE_MENU or ui_state == UiState.ITEM_MENU) and _overlay_can_cancel and _clicked(event):
		_show_action_menu()


func _clicked(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
