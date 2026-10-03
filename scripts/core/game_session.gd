extends Node
## Autoload for high-level game flow: title screen, new game, continue, pause, saving and back to
## title. Menus and world objects ask for these actions; this node coordinates GameState,
## PartyManager, SaveManager and the World, so nothing else touches saves, creatures or maps.
##
## Saving: every save goes through save_now() / request_save(). request_save() saves at once when
## it's safe, otherwise remembers the request and saves as soon as the current transition or
## battle has finished, so a save never captures a half-finished state.

signal state_changed(state: State)
## Emitted after every successful save, with why it happened (e.g. &"manual", &"battle_victory").
signal game_saved(reason: StringName)

enum State { BOOT, TITLE, PLAYING }

## Command-line user argument (`godot --path . -- --new-game`) that skips the title screen and
## starts a fresh game. For development: the existing save is left alone until the game next saves.
const NEW_GAME_ARG := "--new-game"
const PAUSE_LOCK := &"pause"

var state := State.BOOT
## The player's items, stored creatures and Coins. Owned here (not autoloads) and saved by
## SaveManager.
var inventory := Inventory.new()
var storage := CreatureStorage.new()
var wallet := Wallet.new()

var _world: World
var _pending_save := &""
var _paused := false


func register_world(world: World) -> void:
	_world = world
	# Autosave checkpoints. Battle results and map changes are saved once their transition ends.
	world.map_loaded.connect(_on_map_loaded)
	BattleManager.battle_finished.connect(_on_battle_finished)
	SceneRouter.transition_finished.connect(_flush_pending_save)
	_boot.call_deferred()


func has_save() -> bool:
	return SaveManager.has_save()


func can_continue() -> bool:
	return SaveManager.is_save_valid()


## Why Continue can't be used, or "" if it can. Shown to the player as-is.
func get_save_problem() -> String:
	return SaveManager.read_save()["error"] if has_save() else ""


## Starts a game from the very beginning. `discard_existing_save` deletes the current save; the
## title screen only passes true after the player has confirmed overwriting it.
func start_new_game(discard_existing_save: bool) -> void:
	if not _can_start():
		return
	SceneRouter.transition(func() -> void:
		if discard_existing_save:
			SaveManager.delete_save()
		_reset_runtime_state()
		_world.start_from_beginning()
		_set_playing())


## Loads the save and enters the game. Returns "" when loading has started, otherwise a message
## for the player; in that case nothing has changed and the save file is untouched.
func continue_game() -> String:
	if not _can_start():
		return ""
	var result := SaveManager.read_save()
	if not result["error"].is_empty():
		return result["error"]
	SceneRouter.transition(func() -> void:
		_reset_runtime_state()
		SaveManager.apply_save_data(result["data"])
		_set_playing())
	return ""


## Leaves the current game for the title screen (callers save first if they want to). Refused
## mid-dialogue, mid-encounter/battle or mid-transition.
func return_to_title() -> bool:
	if state != State.PLAYING or SceneRouter.is_busy() or DialogueManager.is_active() \
			or EncounterManager.has_active_encounter():
		return false
	set_paused(false)
	_pending_save = &""
	SceneRouter.transition(func() -> void:
		_world.unload()
		_world.set_active(false)
		_set_state(State.TITLE))
	return true


# --- Saving ---------------------------------------------------------------------------------

## True when the game is in a settled state that can be written to disk.
func can_save() -> bool:
	return state == State.PLAYING and _world != null and _world.current_map != null \
			and not SceneRouter.is_busy() and not BattleManager.is_active() \
			and not EncounterManager.has_active_encounter()


## Saves immediately if possible. Returns whether the game was saved.
func save_now(reason: StringName = &"manual") -> bool:
	if not can_save() or not SaveManager.save_game():
		return false
	_pending_save = &""
	game_saved.emit(reason)
	return true


## Autosave checkpoint: saves now if it's safe, otherwise as soon as it becomes safe.
func request_save(reason: StringName) -> void:
	if not save_now(reason):
		_pending_save = reason


# --- Shopping -------------------------------------------------------------------------------

## Buys `quantity` of an item (Shop rules: price, funds) and saves. Returns "" on success,
## otherwise the message to show; nothing changes then.
func buy_item(item_id: StringName, quantity: int) -> String:
	var problem := Shop.purchase(item_id, quantity, wallet, inventory)
	if problem.is_empty():
		request_save(&"purchase")
	return problem


func has_pending_save() -> bool:
	return not _pending_save.is_empty()


func _flush_pending_save() -> void:
	if has_pending_save():
		save_now(_pending_save)


func _on_map_loaded(_map: GameMap) -> void:
	# Only real map changes during play; starting or continuing a game isn't a checkpoint.
	if state == State.PLAYING:
		request_save(&"map_entered")


func _on_battle_finished(battle: BattleContext) -> void:
	request_save(StringName("battle_" + String(battle.outcome)))


# --- Pause ----------------------------------------------------------------------------------

## The pause menu may only open during free exploration: no dialogue, menu, transition or battle.
func can_pause() -> bool:
	return state == State.PLAYING and _world != null and _world.player.controls_enabled \
			and not SceneRouter.is_busy() and not BattleManager.is_active()


func set_paused(paused: bool) -> void:
	if _world == null or paused == _paused:
		return
	_paused = paused
	if paused:
		_world.player.add_control_lock(PAUSE_LOCK)
	else:
		_world.player.remove_control_lock(PAUSE_LOCK)


func is_paused() -> bool:
	return _paused


# --- Internals ------------------------------------------------------------------------------

func _boot() -> void:
	if OS.get_cmdline_user_args().has(NEW_GAME_ARG):
		state = State.TITLE
		start_new_game(false)
	else:
		_set_state(State.TITLE)


func _can_start() -> bool:
	return _world != null and state == State.TITLE and not SceneRouter.is_busy()


## The one place that puts runtime state back to a brand-new game, so nothing from a previous
## session (party, flags, encounters, map) can leak into the next one.
func _reset_runtime_state() -> void:
	GameState.reset()
	PartyManager.clear()
	inventory.reset_to_starting_items()
	storage.clear()
	wallet.reset_to_starting_amount()
	BattleManager.reset()
	EncounterManager.reset()
	set_paused(false)
	_pending_save = &""
	_world.unload()


func _set_playing() -> void:
	_world.set_active(true)
	_set_state(State.PLAYING)


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(new_state)
