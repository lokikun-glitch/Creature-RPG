extends Node
## End-to-end smoke test: loads the real main scene and drives it with simulated input.
## Run:  godot --path . res://tests/smoke_test.tscn
## Optional screenshots (needs a window, not --headless):  ... -- --shots=C:/some/dir
## Exits with the number of failed checks.
##
## The main stage starts from no save: title screen, New Game, all gameplay checks (choosing
## Flamkit), corrupted saves. It also relaunches Godot for stages that need a real quit/launch:
##   continue_flamkit  — Continue restores Flamkit; then New Game (overwrite) and choose Aquaphin
##   continue_aquaphin — Continue restores Aquaphin, and Flamkit is gone
##   new_game_arg      — `--new-game` skips the title and leaves the save alone
## Every stage uses its own save file, never the player's.

const TEST_SAVE_PATH := "user://test_savegame.json"
## Game-time limit for each relaunched stage process.
const STAGE_TIMEOUT := 300
const LAB_MAP := "res://scenes/world/maps/research_lab.tscn"
## Phase 12: how far below (or above) an NPC the player stands when touching them: the NPC body
## keeps the two sprites from overlapping, so this replaces the old 16 px.
const TALK_GAP := 22.0
const TOWN_SPAWN := Vector2(144, 180)
## Route 01's intended encounter design (Phase 10). Percentages; must total 100.
const ROUTE_01_WEIGHTS := {
	&"flamkit": 15, &"aquaphin": 15, &"mossaur": 15, &"pebblit": 15, &"cindrake": 10,
	&"rivulet": 10, &"thornling": 10, &"brambleox": 5, &"tideclaw": 5,
}

var failures := 0
var checks := 0
var shots_dir := ""
## Last section header printed; the test runner reports it if the process times out.
var current_section := ""
var arrival_pos := Vector2.INF
## Every encounter_started emission, so tests can prove none happened (not just none is active).
var encounters_started := 0
var saves := 0
var last_save_reason := &""

var main: Node
var world: World
var player: Player
var interaction: InteractionManager
var prompt: InteractionPrompt
var dialogue_box: DialogueBox
var title: TitleScreen


func _ready() -> void:
	var stage := ""
	var scenario := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shots_dir)
		elif arg.begins_with("--stage="):
			stage = arg.trim_prefix("--stage=")
		elif arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
	SaveManager.save_path = TEST_SAVE_PATH
	if stage == "migrate_v1" or stage == "e2e_start":
		write_file(TEST_SAVE_PATH, JSON.stringify(V1_FIXTURE))
	elif stage == "migrate_v2":
		write_file(TEST_SAVE_PATH, JSON.stringify(v2_fixture()))
	# Encounters must be reproducible in tests.
	EncounterManager.rng.seed = 1234
	if stage.is_empty():
		SaveManager.delete_save()
	main = load("res://main/main.tscn").instantiate()
	add_child(main)
	world = main.get_node("World")
	player = world.player
	interaction = player.get_node("InteractionManager")
	prompt = player.get_node("InteractionManager/Prompt")
	dialogue_box = main.get_node("UI/DialogueBox")
	title = main.get_node("TitleScreen")
	# Battles play out quickly but still through every state and animation.
	var battle_view := main.get_node("BattleScene") as BattleScene
	battle_view.message_delay = 0.03
	battle_view.animation_speed = 12.0
	world.map_loaded.connect(func(_map: GameMap) -> void: arrival_pos = player.global_position)
	EncounterManager.encounter_started.connect(func(_e: WildEncounter) -> void: encounters_started += 1)
	GameSession.game_saved.connect(func(reason: StringName) -> void:
		saves += 1
		last_save_reason = reason)
	match stage:
		"":
			_run.call_deferred()
		"continue_flamkit":
			_run_stage.call_deferred(stage, test_continue_flamkit_then_new_game)
		"continue_aquaphin":
			_run_stage.call_deferred(stage, test_continue_aquaphin)
		"battle_fresh":
			_run_stage.call_deferred(stage, test_battle_fresh_process)
		"safety_start":
			_run_stage.call_deferred(stage, test_safety_start)
		"safety":
			_run_stage.call_deferred(stage + ":" + scenario, test_safety.bind(scenario))
		"capture_start":
			_run_stage.call_deferred(stage, test_capture_start)
		"capture_continue":
			_run_stage.call_deferred(stage, test_capture_continue)
		"capture_verify":
			_run_stage.call_deferred(stage, test_capture_verify)
		"migrate_v1":
			_run_stage.call_deferred(stage, test_migrate_v1)
		"migrate_verify":
			_run_stage.call_deferred(stage, test_migrate_verify)
		"migrate_v2":
			_run_stage.call_deferred(stage, test_migrate_v2)
		"migrate_v2_verify":
			_run_stage.call_deferred(stage, test_migrate_v2_verify)
		"e2e_start":
			_run_stage.call_deferred(stage, test_e2e_start)
		"e2e_verify":
			_run_stage.call_deferred(stage, test_e2e_verify)
		"new_game_arg":
			_run_stage.call_deferred(stage, test_new_game_arg)


func _run() -> void:
	await frames(20)
	await test_harness_self_check()
	await test_title_without_save()
	await test_new_game_without_save()
	await test_world_and_collision()
	await test_npc_interaction()
	await test_facing_rules()
	await test_signs()
	await test_line_of_sight()
	await test_doors()
	await test_creature_data()
	await test_party_manager()
	await test_starter_selection()
	await run_stage("continue_flamkit")
	await run_stage("continue_aquaphin")
	await test_leave_lab()
	await test_route_transitions()
	await test_encounter_generation()
	await test_route_01()
	await test_encounters_on_route()
	await test_battle_rules()
	await test_battle()
	await test_escape_in_gameplay()
	await test_battle_actions()
	await test_pause_menu()
	await test_map_autosave()
	await test_database_validation()
	await test_route_table()
	await test_encounter_gates()
	await test_roster_battles()
	await test_new_moves_and_levels()
	await test_inventory_unit()
	await test_save_v2_unit()
	await test_party_and_storage_unit()
	await test_capture_rules_unit()
	await test_capture_in_battle()
	await test_switching_in_battle()
	await test_party_full_capture()
	await test_wallet_and_shop_rules()
	await test_save_v3_unit()
	await test_party_rules_phase12()
	await test_nickname_rules()
	await test_party_screen()
	await test_storage_terminal()
	await test_shop()
	await test_bed_prompt()
	await test_npc_collision()
	await test_npc_dialogue_variants()
	await test_route_01_polish()
	await run_stage("battle_fresh")
	await run_stage("new_game_arg", ["--new-game"])
	await run_stage("safety_start")
	for scenario in ["run", "lose", "heal", "manual", "verify"]:
		await run_stage("safety", ["--scenario=" + scenario])
	for stage in ["capture_start", "capture_continue", "capture_verify", "migrate_v1", "migrate_verify"]:
		await run_stage(stage)
	for stage in ["migrate_v2", "migrate_v2_verify", "e2e_start", "e2e_verify"]:
		await run_stage(stage)
	await test_corrupted_saves()
	SaveManager.delete_save()
	DirAccess.remove_absolute(EXPECT_PATH)
	_finish("SMOKE TEST")


func _run_stage(stage: String, body: Callable) -> void:
	# The test runner's --test-timeout (set by run_stage) turns a hang into a failure.
	await frames(20)
	await body.call()
	_finish("STAGE " + stage)


func _finish(label: String) -> void:
	# A script error aborts a test function silently; never report success for a stage that checked nothing.
	if checks == 0:
		check(false, "stage ran no checks")
	print("%s DONE: %d/%d checks passed, %d failure(s)" % [label, checks - failures, checks, failures])
	get_tree().quit(failures)


# --- Phase 6: title screen ------------------------------------------------------------------

func test_title_without_save() -> void:
	section("Title screen (no save)")
	check(GameSession.state == GameSession.State.TITLE and title.visible, "launch shows the title screen")
	check(not world.visible and world.current_map == null, "no world/map running behind the title")
	check(not player.controls_enabled, "player is frozen on the title screen")
	check(not title.is_option_enabled(TitleScreen.Option.CONTINUE), "Continue disabled without a save")
	check(title.get_selected_option() == TitleScreen.Option.NEW_GAME, "New Game selected by default")
	var continue_label := title.get_node("%ContinueOption/HBox/Label") as Label
	# LabelSettings would silently override the menu's colours, hiding the disabled state.
	check(continue_label.label_settings == null
			and continue_label.get_theme_color(&"font_color") == TitleScreen.TEXT_DISABLED, "Continue drawn greyed out")
	await shot("00_title_no_save")
	await press(&"ui_down")
	check(title.get_selected_option() == TitleScreen.Option.SETTINGS, "Down selects Settings")
	await press(&"ui_down")
	check(title.get_selected_option() == TitleScreen.Option.NEW_GAME, "Down wraps and skips disabled Continue")
	await press(&"move_up")
	check(title.get_selected_option() == TitleScreen.Option.SETTINGS, "W moves up (skipping Continue)")
	await press(&"move_down")
	check(title.get_selected_option() == TitleScreen.Option.NEW_GAME, "S moves down")

	await press(&"ui_down")
	await press(&"ui_accept")
	check(title.is_settings_open(), "Enter on Settings opens the settings screen")
	await shot("00b_settings")
	await press(&"ui_cancel")
	check(not title.is_settings_open() and title.visible, "Esc closes settings")
	await press(&"ui_cancel")
	check(GameSession.state == GameSession.State.TITLE and title.visible, "Esc on the title menu does nothing")

	var options := title.get_node("Root/Menu/Options")
	await mouse_move(options.get_node("NewGameOption"))
	check(title.get_selected_option() == TitleScreen.Option.NEW_GAME, "mouse hover selects New Game")
	await mouse_move(options.get_node("ContinueOption"))
	check(title.get_selected_option() == TitleScreen.Option.NEW_GAME, "hovering disabled Continue changes nothing")
	await mouse_click(options.get_node("ContinueOption"))
	check(GameSession.state == GameSession.State.TITLE, "clicking disabled Continue does nothing")
	await mouse_click(options.get_node("SettingsOption"))
	check(title.is_settings_open() and title.get_selected_option() == TitleScreen.Option.SETTINGS,
			"mouse click opens Settings")
	await mouse_click(title.get_node("%Settings").get_node("%Back"))
	check(not title.is_settings_open(), "mouse click on Back closes Settings")
	await press(&"ui_up")


func test_new_game_without_save() -> void:
	section("New Game (no save)")
	check(title.get_selected_option() == TitleScreen.Option.NEW_GAME, "New Game selected")
	await press(&"interact")
	check(not title.get_node("%Dialog").is_open(), "no overwrite question without a save")
	check(await wait_for_state(GameSession.State.PLAYING), "game starts")
	await assert_fresh_game()


## Shared checks for "this is a brand-new game".
func assert_fresh_game() -> void:
	check(world.visible and not title.visible and player.controls_enabled, "world running, title gone, player free")
	check(world.current_map.map_id == &"fernhollow_town", "starts in Fernhollow Town")
	check(player.global_position.distance_to(TOWN_SPAWN) < 1 and player.facing == Vector2.DOWN,
			"at the starting spawn, facing down")
	check(PartyManager.get_size() == 0, "party is empty")
	check(not GameState.starter_selected and GameState.get_flag(GameState.STARTER_SPECIES) == "",
			"starter_selected = false, no starter species")


func test_escape_in_gameplay() -> void:
	section("Esc during gameplay")
	var pause := main.get_node("PauseMenu") as PauseMenu
	await press(&"ui_cancel")
	await frames(10)
	check(GameSession.state == GameSession.State.PLAYING and not title.visible and pause.is_open(),
			"Esc opens the pause menu, never the title screen")
	await press(&"ui_cancel")
	check(not pause.is_open() and player.controls_enabled, "Esc again resumes")


func test_continue_flamkit_then_new_game() -> void:
	section("Relaunch: Continue")
	check(title.visible and title.is_option_enabled(TitleScreen.Option.CONTINUE), "Continue enabled with a save")
	check(title.get_selected_option() == TitleScreen.Option.CONTINUE, "Continue selected by default")
	check(world.current_map == null and PartyManager.get_size() == 0, "nothing loaded before choosing")
	var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_PATH))
	await shot("12_title_with_save")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue enters the game")
	check(world.current_map_path == save["world"]["map"] and world.current_map.map_id == &"research_lab",
			"saved map restored (lab)")
	var saved_pos := Vector2(save["world"]["position"]["x"], save["world"]["position"]["y"])
	var saved_facing := Vector2(save["world"]["facing"]["x"], save["world"]["facing"]["y"])
	check(player.global_position.distance_to(saved_pos) < 1, "saved position restored")
	check(player.facing == saved_facing, "saved facing restored %s" % player.facing)
	var creature := PartyManager.get_creature(0)
	check(PartyManager.get_size() == 1 and creature and creature.species_id == &"flamkit" and creature.level == 5
			and creature.current_hp == 55 and creature.uid == save["party"][0]["uid"]
			and Array(creature.move_ids) == [&"tackle", &"ember"], "Flamkit restored with its stats and moves")
	check(GameState.starter_selected and GameState.get_flag(GameState.STARTER_SPECIES) == "flamkit",
			"starter flags restored")
	await frames(3)
	await press(&"interact")
	await expect_lines("Professor Elian", [
		"You've already chosen your companion.",
		"Take good care of each other.",
	], "Elian remembers the starter")
	check(not starter_event().is_selecting(), "no second starter offered")

	section("Return to title, New Game over an existing save")
	var save_text := FileAccess.get_file_as_string(TEST_SAVE_PATH)
	check(GameSession.return_to_title(), "return_to_title accepted")
	check(await wait_for_state(GameSession.State.TITLE), "back on the title screen")
	check(world.current_map == null and not world.visible, "world unloaded")
	check(title.is_option_enabled(TitleScreen.Option.CONTINUE), "Continue still available")
	await press(&"ui_down")
	check(title.get_selected_option() == TitleScreen.Option.NEW_GAME, "New Game selected")
	var dialog := title.get_node("%Dialog") as ChoiceDialog
	await press(&"ui_accept")
	check(dialog.is_open() and dialog.get_node("%DialogTitle").text == "Start a new game?"
			and dialog.get_node("%DialogMessage").text == "This will overwrite your existing save.",
			"overwrite confirmation shown")
	check(dialog.get_selected_index() == 1, "NO is the default answer")
	await shot("13_overwrite_confirm")
	await press(&"ui_accept")
	check(not dialog.is_open() and GameSession.state == GameSession.State.TITLE, "NO returns to the title")
	check(FileAccess.get_file_as_string(TEST_SAVE_PATH) == save_text, "NO leaves the save untouched")
	await press(&"ui_accept")
	await press(&"ui_cancel")
	check(not dialog.is_open() and FileAccess.get_file_as_string(TEST_SAVE_PATH) == save_text,
			"Esc in the confirmation also means NO")
	await press(&"ui_accept")
	await mouse_click(dialog.get_option(0))
	check(await wait_for_state(GameSession.State.PLAYING), "YES (mouse click) starts the new game")
	check(not SaveManager.has_save(), "old save removed after confirming")
	await assert_fresh_game()

	section("New game: choose a different starter")
	await place(Vector2(128, 420), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(await wait_for_map(&"research_lab"), "enter lab")
	await hold(&"move_up", 1.0)
	await press(&"interact")
	await close_dialogue()
	check(starter_event().is_selecting(), "Elian offers the starters again")
	await press(&"ui_right")
	check(starter_screen().get_selected_species().id == &"aquaphin", "Aquaphin highlighted")
	await press(&"ui_accept")
	await press(&"ui_accept")
	await close_dialogue()
	check(PartyManager.get_size() == 1 and PartyManager.get_creature(0).species_id == &"aquaphin",
			"party holds only Aquaphin")
	check(SaveManager.has_save(), "new game saved")


func test_continue_aquaphin() -> void:
	section("Relaunch: Continue the new game")
	check(title.is_option_enabled(TitleScreen.Option.CONTINUE), "Continue enabled")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue enters the game")
	var species := PartyManager.get_party().map(func(c: CreatureInstance) -> StringName: return c.species_id)
	check(species == [&"aquaphin"], "party is exactly [Aquaphin]; Flamkit is gone (%s)" % [species])
	check(PartyManager.get_creature(0).current_hp == 65, "Aquaphin HP 65")
	check(GameState.starter_selected and GameState.get_flag(GameState.STARTER_SPECIES) == "aquaphin",
			"starter flags describe the new game")


func test_new_game_arg() -> void:
	section("Command line --new-game")
	var save_text := FileAccess.get_file_as_string(TEST_SAVE_PATH)
	check(await wait_for_state(GameSession.State.PLAYING), "title skipped")
	await assert_fresh_game()
	check(FileAccess.get_file_as_string(TEST_SAVE_PATH) == save_text, "existing save left untouched")

	section("No wild encounters before choosing a starter")
	SceneRouter.go_to("res://scenes/world/maps/route_01.tscn", &"south_entrance")
	check(await wait_for_map(&"route_01"), "Route 01 reachable without a starter")
	await place(Vector2(470, 536), Vector2.RIGHT)
	check(EncounterManager.current_zone != null, "standing in tall grass")
	EncounterManager.force_next_encounter()
	var steps := EncounterManager.steps_in_zones
	var started := encounters_started
	await hold(&"move_right", 0.6)
	check(EncounterManager.steps_in_zones > steps, "walking through the grass still counts steps")
	check(encounters_started == started and not BattleManager.is_active(),
			"no encounter or battle without a starter, even when forced")


func test_battle_fresh_process() -> void:
	section("Fresh process: Continue, then a full battle")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	var save_text := FileAccess.get_file_as_string(TEST_SAVE_PATH)
	var partner := PartyManager.get_creature(0)
	var exp_before := partner.experience
	SceneRouter.go_to("res://scenes/world/maps/route_01.tscn", &"south_entrance")
	check(await wait_for_map(&"route_01"), "on Route 01")
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.rng.seed = 21
	BattleManager.rng.seed = 21
	EncounterManager.force_next_encounter()
	await hold(&"move_right", 0.25)
	var spot := player.global_position
	check(BattleManager.is_active() and BattleManager.battle.player == partner, "battle with party slot 1 (%s)" % partner.species_id)
	var wild := BattleManager.battle.wild
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle UI ready")
	BattleManager.forced_turn_order = 1
	BattleManager.force_hit = true
	BattleManager.forced_random_factor = 1.0
	BattleManager.forced_damage = 999
	await press(&"interact")
	await press(&"interact")
	check(await wait_battle_over(), "battle won and closed")
	check(partner.experience == exp_before + CreatureProgression.exp_reward(wild.level) or partner.level > 5,
			"EXP awarded in memory")
	await assert_back_in_world(spot)
	check(FileAccess.get_file_as_string(TEST_SAVE_PATH) != save_text and saved_party(0)["experience"] == partner.experience
			and saved_party(0)["level"] == partner.level, "battle result autosaved")


func test_corrupted_saves() -> void:
	section("Corrupted / unsupported saves")
	await place(Vector2(320, 300), Vector2.DOWN)
	check(GameSession.return_to_title(), "return to title")
	check(await wait_for_state(GameSession.State.TITLE), "on the title screen")
	var dialog := title.get_node("%Dialog") as ChoiceDialog
	var cases := {
		"not json": "{ this is not json",
		"unsupported version": JSON.stringify({"version": 999, "world": {}, "game_state": {}, "party": []}),
		"missing fields": JSON.stringify({"version": 1, "world": {}}),
		"bad field types": JSON.stringify({"version": 1, "world": [], "game_state": {}, "party": {}}),
		"bad version value": JSON.stringify({"version": "one", "world": {}, "game_state": {}, "party": []}),
	}
	var expected_messages := {
		"unsupported version": SaveManager.ERROR_TOO_NEW,
	}
	for label: String in cases:
		write_test_save(cases[label])
		title.open()
		await frames(2)
		check(dialog.is_open() and dialog.get_node("%DialogTitle").text == "Save data could not be loaded."
				and dialog.get_node("%DialogMessage").text == expected_messages.get(label, SaveManager.ERROR_DAMAGED),
				"%s: error message shown" % label)
		check(not title.is_option_enabled(TitleScreen.Option.CONTINUE), "%s: Continue disabled" % label)
		if label == "not json":
			await shot("14_corrupt_save")
		await press(&"ui_accept")
		check(not dialog.is_open() and GameSession.state == GameSession.State.TITLE and title.visible,
				"%s: OK returns to the title" % label)
		check(FileAccess.get_file_as_string(TEST_SAVE_PATH) == cases[label], "%s: save file not modified" % label)

	# Save goes bad between opening the title and pressing Continue.
	write_test_save(JSON.stringify({"version": 1, "world": {}, "game_state": {}, "party": []}))
	title.open()
	check(title.is_option_enabled(TitleScreen.Option.CONTINUE) and not dialog.is_open(), "minimal valid save: Continue enabled")
	write_test_save("garbage")
	await press(&"ui_accept")
	check(dialog.is_open() and GameSession.state == GameSession.State.TITLE and world.current_map == null,
			"Continue on a save that broke meanwhile: error, still on title")
	await press(&"ui_accept")
	check(not title.is_option_enabled(TitleScreen.Option.CONTINUE), "Continue now disabled")

	await press(&"ui_accept")
	check(dialog.is_open() and dialog.get_node("%DialogTitle").text == "Start a new game?",
			"New Game over a damaged save still asks first")
	await press(&"ui_left")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "YES starts a clean game")
	await assert_fresh_game()


# --- Phase 7: Route 01 + wild encounters ----------------------------------------------------

func test_encounter_generation() -> void:
	section("Encounter table + wild creature generation (seeded)")
	var table := load("res://data/encounters/route_01.tres") as EncounterTable
	check(table != null and table.id == &"route_01" and table.entries.size() == ROUTE_01_WEIGHTS.size(),
			"route_01 table loads with %d entries" % ROUTE_01_WEIGHTS.size())
	var weights := {}
	for entry in table.entries:
		weights[entry.species_id] = entry.weight
		check(CreatureDatabase.get_species(entry.species_id) != null and entry.min_level == 2 and entry.max_level == 5,
				"%s resolves; levels 2-5" % entry.species_id)
	check(weights == ROUTE_01_WEIGHTS, "weights match the Route 01 design %s" % weights)

	var rng := EncounterManager.rng
	rng.seed = 99
	var counts := {}
	for id: StringName in ROUTE_01_WEIGHTS:
		counts[id] = 0
	var levels := {}
	var all_valid := true
	var party_before := PartyManager.get_size()
	for i in 3000:
		var creature := EncounterManager.generate_wild_creature(table)
		counts[creature.species_id] += 1
		levels[creature.level] = true
		all_valid = all_valid and creature.level >= 2 and creature.level <= 5 \
				and creature.current_hp == creature.get_max_hp() \
				and creature.move_ids.size() == creature.get_species().starting_moves.size()
	check(all_valid, "3000 wild creatures: level 2-5, full HP, species moves")
	check(levels.keys().size() == 4, "every level 2-5 occurs (%s)" % [levels.keys()])
	var close := true
	for id: StringName in ROUTE_01_WEIGHTS:
		close = close and absf(counts[id] / 3000.0 - ROUTE_01_WEIGHTS[id] / 100.0) < 0.04
	check(close, "species frequencies follow weights %s" % counts)
	check(PartyManager.get_size() == party_before, "generated wild creatures never join the party")

	rng.seed = 7
	var hits := {0.0: 0, 0.1: 0, 1.0: 0}
	for rate: float in hits:
		for i in 1000:
			hits[rate] += 1 if EncounterManager.roll_encounter(rate) else 0
	check(hits[0.0] == 0 and hits[1.0] == 1000 and hits[0.1] > 70 and hits[0.1] < 130,
			"encounter chance per step: 0%% / 10%% / 100%% -> %s of 1000" % hits)

	var odd := EncounterTable.new()
	var unknown := EncounterEntry.new()
	unknown.species_id = &"no_such_creature"
	unknown.weight = 100
	var only := EncounterEntry.new()
	only.species_id = &"mossaur"
	only.min_level = 4
	only.max_level = 4
	odd.entries = [unknown, only]
	check(EncounterManager.generate_wild_creature(odd).species_id == &"mossaur", "entries with unknown species are skipped")
	check(EncounterManager.generate_wild_creature(EncounterTable.new()) == null, "empty table produces nothing")
	rng.seed = 1234


func test_route_01() -> void:
	section("Route 01")
	await place(Vector2(320, 60), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(await wait_for_map(&"route_01"), "town north exit leads to Route 01")
	check(arrival_pos.distance_to(Vector2(400, 600)) < 1 and player.facing == Vector2.UP, "arrives at the south entrance")
	var bounds := world.current_map.get_bounds()
	check(bounds.size == Vector2(800, 640), "route is 50 x 40 tiles")
	check(world.current_map.get_node("EncounterZones").get_child_count() == 4, "four tall-grass zones")

	await place(Vector2(616, 340), Vector2.UP)
	await hold(&"move_up", 1.0)
	check(player.global_position.y > 320, "cliff blocks (y=%.1f)" % player.global_position.y)
	await place(Vector2(656, 340), Vector2.UP)
	await hold(&"move_up", 1.0)
	check(player.global_position.y < 288, "stairs lead up onto the plateau (y=%.1f)" % player.global_position.y)
	await place(Vector2(496, 80), Vector2.UP)
	await hold(&"move_up", 1.0)
	check(player.global_position.y > 46 and world.current_map.map_id == &"route_01",
			"closed north gate blocks (y=%.1f)" % player.global_position.y)
	await place(Vector2(56, 100), Vector2.LEFT)
	await hold(&"move_left", 0.6)
	check(player.global_position.x >= 35.9, "west border blocks")

	var sign_post := world.current_map.get_node("Objects/Signs/RouteSign") as SignPost
	await place(sign_post.global_position + Vector2(14, 0), Vector2.LEFT)
	check(interaction.target == interactable_of(sign_post), "facing the route sign targets it")
	await press(&"interact")
	check(DialogueManager.is_active() and box_text() == "Route 01\nThe first path beyond Fernhollow.", "route sign text")
	await close_dialogue()
	var trainer := npc(&"YoungTrainer")
	await place(trainer.global_position + Vector2(16, 0), Vector2.LEFT)
	await press(&"interact")
	await expect_lines("Young Trainer", [
		"I've heard creatures are especially active in tall grass.",
		"Tip: wear a wild creature down before you throw a Capture Orb. Healthy ones break free much more often.",
	], "Young Trainer")


func test_encounters_on_route() -> void:
	section("Tall grass + encounters")
	var zone := world.current_map.get_node("EncounterZones/TallGrassSouth") as EncounterZone
	var save_before := FileAccess.get_file_as_string(TEST_SAVE_PATH)
	var party_before := PartyManager.get_size()
	check(zone.encounter_table == load("res://data/encounters/route_01.tres") and is_equal_approx(zone.encounter_rate, 0.1),
			"zone uses the route_01 table at 10% per step")

	await place(Vector2(392, 560), Vector2.UP)
	check(EncounterManager.current_zone == null and not zone.contains_player(), "on the path: not in grass")
	var steps := EncounterManager.steps_in_zones
	await hold(&"move_up", 0.6)
	check(EncounterManager.steps_in_zones == steps, "walking outside grass counts no steps")

	zone.encounter_rate = 0.0
	await place(Vector2(470, 536), Vector2.RIGHT)
	check(EncounterManager.current_zone == zone and zone.contains_player(), "tall grass detects the player")
	check(player.get_children().any(func(c: Node) -> bool: return c is Sprite2D and c.texture == zone.tuft_texture),
			"grass tuft drawn at the player's feet")
	steps = EncounterManager.steps_in_zones
	await hold(&"move_right", 1.0)
	var walked := EncounterManager.steps_in_zones - steps
	check(walked >= 4 and walked <= 6, "walking ~80px in grass counts ~5 steps (%d)" % walked)
	check(not EncounterManager.has_active_encounter(), "0% rate: no encounter")
	await shot("15_tall_grass")

	EncounterManager.force_next_encounter()
	steps = EncounterManager.steps_in_zones
	await frames(60)
	check(EncounterManager.steps_in_zones == steps and not EncounterManager.has_active_encounter(),
			"standing still in grass never triggers, even when forced")
	await hold(&"move_left", 0.25)
	var encounter := EncounterManager.active_encounter
	check(encounter != null, "forced encounter triggers on the next step")
	if encounter == null:
		return
	var stopped_at := player.global_position
	var creature := encounter.creature
	check(FileAccess.get_file_as_string(TEST_SAVE_PATH) == save_before, "starting an encounter doesn't save")
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "the encounter starts a battle")
	check(BattleManager.battle != null and BattleManager.battle.wild == creature and BattleManager.battle.encounter == encounter,
			"battle receives the encounter's wild creature")
	check(encounter.table == zone.encounter_table and encounter.source_map_id == &"route_01"
			and encounter.source_zone == zone, "encounter records table, map and zone")
	check(creature.level >= 2 and creature.level <= 5 and creature.current_hp == creature.get_max_hp(),
			"wild %s Lv.%d with full HP" % [creature.species_id, creature.level])
	check(PartyManager.get_size() == party_before and not PartyManager.get_party().has(creature),
			"wild creature is not in the party")
	await hold(&"move_down", 0.3)
	check(player.global_position == stopped_at and interaction.target == null, "player frozen during the encounter")
	check(not GameSession.return_to_title(), "can't quit to title mid-encounter")
	await win_battle_quickly()
	check(not EncounterManager.has_active_encounter() and world.current_map.map_id == &"route_01",
			"back on Route 01 with no active encounter")
	check(player.global_position == stopped_at and player.facing == Vector2.LEFT, "same position and facing")
	await hold(&"move_left", 0.2)
	check(player.global_position.x < stopped_at.x - 4, "player can move again")

	zone.encounter_rate = 1.0
	steps = EncounterManager.steps_in_zones
	await place(Vector2(460, 536), Vector2.RIGHT)
	Input.action_press(&"move_right")
	for i in 120:
		await get_tree().physics_frame
		if EncounterManager.has_active_encounter():
			break
	Input.action_release(&"move_right")
	check(EncounterManager.has_active_encounter()
			and EncounterManager.steps_in_zones - steps == EncounterManager.COOLDOWN_STEPS + 1,
			"after an encounter, %d grace steps before the next" % EncounterManager.COOLDOWN_STEPS)
	await win_battle_quickly()
	zone.encounter_rate = 0.0

	await press(&"debug_force_encounter")
	check(EncounterManager.has_active_encounter(), "F6 (debug) starts an encounter while in grass")
	await win_battle_quickly()
	check(not EncounterManager.has_active_encounter(), "F6 encounter's battle finished")

	await place(Vector2(392, 560), Vector2.UP)
	await press(&"debug_force_encounter")
	check(not EncounterManager.has_active_encounter(), "F6 outside grass doesn't start one immediately")
	await place(Vector2(470, 536), Vector2.RIGHT)
	await hold(&"move_right", 0.3)
	check(EncounterManager.has_active_encounter(), "...but arms the next grass step")
	await win_battle_quickly()
	zone.encounter_rate = 0.1

	check(FileAccess.get_file_as_string(TEST_SAVE_PATH) != save_before and last_save_reason == &"battle_victory"
			and saved_party(0)["experience"] == PartyManager.get_creature(0).experience,
			"finished battles autosaved the party")
	await place(Vector2(400, 600), Vector2.DOWN)
	await hold(&"move_down", 0.6)
	check(await wait_for_map(&"fernhollow_town"), "Route 01 south exit returns to town")
	check(EncounterManager.current_zone == null, "leaving the map clears the current zone")


# --- Phase 8: battles -----------------------------------------------------------------------

func make_creature(species_id: StringName, level: int) -> CreatureInstance:
	return CreatureFactory.create_from_species(CreatureDatabase.get_species(species_id), level)


func test_battle_rules() -> void:
	section("Battle rules (deterministic)")
	var element := func(id: StringName) -> ElementData: return load("res://data/elements/%s.tres" % id)
	var chart := [
		[&"ember", &"verdant", 2.0], [&"verdant", &"tide", 2.0], [&"tide", &"ember", 2.0],
		[&"ember", &"tide", 0.5], [&"verdant", &"ember", 0.5], [&"tide", &"verdant", 0.5],
		[&"ember", &"ember", 1.0], [&"tide", &"neutral", 1.0],
		[&"neutral", &"ember", 1.0], [&"neutral", &"tide", 1.0], [&"neutral", &"verdant", 1.0],
	]
	var chart_ok := true
	for row in chart:
		chart_ok = chart_ok and element.call(row[0]).effectiveness_against(element.call(row[1])) == row[2]
	check(chart_ok, "element chart: Ember>Verdant>Tide>Ember at 2x, reverse 0.5x, Neutral 1x")

	var flamkit := make_creature(&"flamkit", 5)
	var mossaur := make_creature(&"mossaur", 5)
	var aquaphin := make_creature(&"aquaphin", 5)
	var ember := CreatureDatabase.get_move(&"ember")
	var tackle := CreatureDatabase.get_move(&"tackle")
	# ((2*5/5 + 2) * 40 * 65 / 70) / 50 + 2 = 4.971 -> x2 super effective = 9.94 -> 9
	var hit := BattleCalculator.calculate_damage(flamkit, mossaur, ember, 1.0)
	check(hit["damage"] == 9 and hit["effectiveness"] == 2.0 and hit["critical"] == false,
			"Flamkit Ember vs Mossaur: 9 damage, super effective (%s)" % hit)
	hit = BattleCalculator.calculate_damage(flamkit, mossaur, tackle, 1.0)
	check(hit["damage"] == 4 and hit["effectiveness"] == 1.0, "Flamkit Tackle vs Mossaur: 4 damage, neutral (%s)" % hit)
	# ((4 * 40 * 65 / 55) / 50 + 2) = 5.78 -> x0.5 = 2.89 -> 2
	hit = BattleCalculator.calculate_damage(flamkit, aquaphin, ember, 1.0)
	check(hit["damage"] == 2 and hit["effectiveness"] == 0.5, "Flamkit Ember vs Aquaphin: 2 damage, not very effective")
	hit = BattleCalculator.calculate_damage(make_creature(&"aquaphin", 2), make_creature(&"mossaur", 100),
			CreatureDatabase.get_move(&"splash"), BattleCalculator.MIN_RANDOM_FACTOR)
	check(hit["damage"] == 1, "weak hit still deals the minimum of 1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var factors_ok := true
	for i in 500:
		var factor := BattleCalculator.roll_random_factor(rng)
		factors_ok = factors_ok and factor >= 0.85 and factor <= 1.0
	check(factors_ok, "random factor always within 0.85-1.0")

	check(BattleCalculator.player_moves_first(75, 40, rng) and not BattleCalculator.player_moves_first(40, 75, rng),
			"faster creature acts first, slower second")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 5
	b.seed = 5
	var same := true
	var outcomes := {}
	for i in 100:
		var first := BattleCalculator.player_moves_first(60, 60, a)
		same = same and first == BattleCalculator.player_moves_first(60, 60, b)
		outcomes[first] = true
	check(same and outcomes.size() == 2, "speed ties: deterministic for a given seed, both outcomes possible")

	rng.seed = 9
	var ai_ok := true
	var ai_seen := {}
	for i in 300:
		var choice := BattleAI.choose_move(flamkit, rng)
		ai_ok = ai_ok and flamkit.move_ids.has(choice)
		ai_seen[choice] = true
	check(ai_ok and ai_seen.size() == 2, "AI picks only the creature's own moves (both used)")
	var odd := make_creature(&"mossaur", 3)
	odd.move_ids = [&"no_such_move", &"tackle"]
	var only_valid := true
	for i in 50:
		only_valid = only_valid and BattleAI.choose_move(odd, rng) == &"tackle"
	check(only_valid, "AI never picks a move that doesn't exist")
	odd.move_ids = [&"no_such_move"]
	check(BattleAI.choose_move(odd, rng) == &"", "AI with no valid move picks nothing")

	check(CreatureProgression.exp_reward(3) == 30 and CreatureProgression.exp_reward(0) == 1, "EXP reward = max(1, level*10)")
	check(CreatureProgression.exp_to_next_level(5) == 250, "level 5 -> 6 needs 250 EXP")
	var grower := make_creature(&"flamkit", 5)
	grower.current_hp = 40
	check(CreatureProgression.award_experience(grower, 249).is_empty() and grower.experience == 249, "249 EXP: no level-up")
	var levels := CreatureProgression.award_experience(grower, 1)
	check(levels == [6] and grower.level == 6 and grower.experience == 0, "reaching the threshold levels up to 6")
	check(grower.get_max_hp() == 57 and grower.current_hp == 42, "max HP 55->57; current HP rises by the same 2")
	var fast := make_creature(&"aquaphin", 2)
	check(CreatureProgression.award_experience(fast, 500) == [3, 4, 5] and fast.experience == 210,
			"500 EXP at level 2: three level-ups, 210 left over")
	var capped := make_creature(&"mossaur", 100)
	check(CreatureProgression.award_experience(capped, 1000).is_empty() and capped.level == 100, "level 100 is the cap")

	check(is_equal_approx(BattleCalculator.escape_chance(50, 50, 0), 0.75)
			and is_equal_approx(BattleCalculator.escape_chance(40, 50, 0), 0.6)
			and is_equal_approx(BattleCalculator.escape_chance(40, 50, 1), 0.75),
			"escape chance: 75% at equal speed, lower when slower, +15% per failed attempt")
	check(is_equal_approx(BattleCalculator.escape_chance(100, 50, 0), 0.95)
			and is_equal_approx(BattleCalculator.escape_chance(10, 80, 0), 0.25), "escape chance capped to 25-95%")


func test_battle() -> void:
	section("Battle: start + display")
	await place(Vector2(320, 60), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(await wait_for_map(&"route_01"), "on Route 01")
	var scene := battle_scene()
	var zone := world.current_map.get_node("EncounterZones/TallGrassSouth") as EncounterZone
	var save_before := FileAccess.get_file_as_string(TEST_SAVE_PATH)
	var partner := PartyManager.get_creature(0)
	partner.current_hp = partner.get_max_hp()
	var party_before := PartyManager.get_size()
	EncounterManager.rng.seed = 3
	BattleManager.rng.seed = 11
	zone.encounter_rate = 0.0
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter()
	await hold(&"move_right", 0.25)
	var stopped_at := player.global_position
	var battle := BattleManager.battle
	check(battle != null and BattleManager.state == BattleManager.State.INTRO, "wild encounter starts a battle (INTRO)")
	if battle == null:
		return
	var wild := battle.wild
	var wild_name := "Wild " + wild.get_species().display_name
	check(battle.player == partner and battle.player == PartyManager.get_creature(0), "player's creature is party slot 1 (same object)")
	check(wild == EncounterManager.active_encounter.creature, "wild creature comes from the encounter")
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU) and BattleManager.state == BattleManager.State.PLAYER_ACTION,
			"intro plays, then PLAYER_ACTION")
	check(scene.message_log.has(BattleMessages.WILD_APPEARED.format({"name": wild.get_display_name()}))
			and scene.message_log.has("Go, %s!" % partner.get_display_name()), "intro messages shown")
	check(label_text(scene, "Message") == "What should %s do?" % partner.get_display_name(), "action prompt")
	var enemy_panel := scene.get_node("%EnemyPanel")
	var player_panel := scene.get_node("%PlayerPanel")
	check(label_text(enemy_panel, "Name") == wild_name and label_text(enemy_panel, "Level") == "Lv. %d" % wild.level,
			"enemy panel: %s Lv. %d" % [wild_name, wild.level])
	check(label_text(player_panel, "Name") == partner.get_display_name()
			and label_text(player_panel, "Level") == "Lv. %d" % partner.level, "player panel: name and level")
	check(label_text(player_panel, "HpLabel") == "%d/%d" % [partner.current_hp, partner.get_max_hp()]
			and (enemy_panel.get_node("%HpBar") as ProgressBar).value == wild.current_hp, "HP shown for both sides")
	check((scene.get_node("%EnemySprite") as TextureRect).texture == wild.get_species().sprite
			and (scene.get_node("%PlayerSprite") as TextureRect).texture == partner.get_species().sprite, "both sprites shown")
	await hold(&"move_down", 0.3)
	check(player.global_position == stopped_at and not player.controls_enabled, "player movement disabled")
	await shot("17_battle_action")

	section("Battle: move selection")
	await press(&"interact")
	var expected_names := PackedStringArray()
	for move_id in partner.move_ids:
		expected_names.append(CreatureDatabase.get_move(move_id).display_name)
	check(scene.ui_state == BattleScene.UiState.MOVE_MENU and scene.get_move_names() == expected_names,
			"FIGHT lists the creature's own moves %s" % expected_names)
	await press(&"ui_right")
	var second := CreatureDatabase.get_move(partner.move_ids[1])
	check(scene.get_selected_move() == second and label_text(scene, "MovePower") == "Power %d" % second.power
			and label_text(scene, "MoveElementLabel") == second.element.display_name.to_upper(),
			"selecting %s shows its element and power" % second.display_name)
	await shot("18_battle_moves")
	await press(&"ui_cancel")
	check(scene.ui_state == BattleScene.UiState.ACTION_MENU, "Esc goes back to the action menu")
	await press(&"ui_accept")

	section("Battle: turns")
	BattleManager.force_hit = true
	BattleManager.forced_random_factor = 1.0
	BattleManager.forced_ai_move = &"tackle"
	BattleManager.forced_turn_order = 1
	var tackle := CreatureDatabase.get_move(&"tackle")
	var deal: int = BattleCalculator.calculate_damage(partner, wild, tackle, 1.0)["damage"]
	var take: int = BattleCalculator.calculate_damage(wild, partner, tackle, 1.0)["damage"]
	var wild_hp := wild.current_hp
	var my_hp := partner.current_hp
	var log_start := scene.message_log.size()
	await press(&"interact")
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "turn resolves and returns to the action menu")
	check(wild.current_hp == wild_hp - deal and partner.current_hp == my_hp - take,
			"HP: wild -%d, partner -%d" % [deal, take])
	var turn_log := scene.message_log.slice(log_start)
	var mine := turn_log.find("%s used Tackle!" % partner.get_display_name())
	var theirs := turn_log.find("%s used Tackle!" % wild_name)
	check(mine >= 0 and theirs > mine, "player acted first when first")
	check(turn_log.has("%s took %d damage!" % [wild_name, deal]), "damage message")
	check((enemy_panel.get_node("%HpBar") as ProgressBar).value == wild.current_hp
			and label_text(player_panel, "HpLabel") == "%d/%d" % [partner.current_hp, partner.get_max_hp()],
			"HP bars updated")
	var speed_first := partner.get_stat(CreatureStats.Stat.SPEED) > wild.get_stat(CreatureStats.Stat.SPEED)
	BattleManager.forced_turn_order = 0
	if partner.get_stat(CreatureStats.Stat.SPEED) != wild.get_stat(CreatureStats.Stat.SPEED):
		check(BattleManager.determine_turn_order()[0] == (BattleSide.Side.PLAYER if speed_first else BattleSide.Side.WILD),
				"live battle orders turns by Speed")
	BattleManager.forced_turn_order = -1
	log_start = scene.message_log.size()
	await press(&"interact")
	await press(&"interact")
	await wait_for_ui(BattleScene.UiState.ACTION_MENU)
	turn_log = scene.message_log.slice(log_start)
	check(turn_log.find("%s used Tackle!" % wild_name) < turn_log.find("%s used Tackle!" % partner.get_display_name()),
			"wild acted first when it moves first")

	var ember := CreatureDatabase.get_move(partner.move_ids[1])
	var effectiveness := ember.element.effectiveness_against(wild.get_species().element)
	BattleManager.forced_turn_order = 1
	log_start = scene.message_log.size()
	await press(&"interact")
	await press(&"ui_right")
	await press(&"interact")
	await wait_for_ui(BattleScene.UiState.ACTION_MENU)
	turn_log = scene.message_log.slice(log_start)
	var expected_line: String = {2.0: BattleMessages.SUPER_EFFECTIVE, 0.5: BattleMessages.NOT_VERY_EFFECTIVE}.get(effectiveness, "")
	check(turn_log.has("%s used %s!" % [partner.get_display_name(), ember.display_name])
			and (expected_line.is_empty() or turn_log.has(expected_line))
			and (not expected_line.is_empty() or not (turn_log.has(BattleMessages.SUPER_EFFECTIVE) or turn_log.has(BattleMessages.NOT_VERY_EFFECTIVE))),
			"%s vs %s: effectiveness %.1fx reported" % [ember.display_name, wild.species_id, effectiveness])

	section("Battle: victory + EXP")
	var level_before := partner.level
	partner.experience = CreatureProgression.exp_to_next_level(partner.level) - 1
	BattleManager.forced_damage = 999
	log_start = scene.message_log.size()
	var won := [false]
	BattleManager.battle_won.connect(func(_b: BattleContext) -> void: won[0] = true, CONNECT_ONE_SHOT)
	await press(&"interact")
	await press(&"interact")
	check(await wait_battle_over(), "battle ends after the wild creature faints")
	turn_log = scene.message_log.slice(log_start)
	var gained := CreatureProgression.exp_reward(wild.level)
	check(won[0] and wild.current_hp == 0, "wild creature fainted at exactly 0 HP; battle_won emitted")
	check(turn_log.has("%s fainted!" % wild_name) and turn_log.has("%s won the battle!" % partner.get_display_name()),
			"faint + victory messages")
	check(turn_log.has("%s gained %d EXP!" % [partner.get_display_name(), gained]), "EXP message (%d)" % gained)
	check(partner.level == level_before + 1 and turn_log.has(BattleMessages.LEVEL_UP.format({"name": partner.get_display_name(), "level": partner.level})),
			"levelled up to %d with message" % partner.level)
	check(PartyManager.get_size() == party_before and not PartyManager.get_party().has(wild), "wild creature never joins the party")
	await assert_back_in_world(stopped_at)
	check(last_save_reason == &"battle_victory" and saved_party(0)["level"] == partner.level
			and saved_party(0)["experience"] == partner.experience and saved_party(0)["current_hp"] == partner.current_hp,
			"victory autosaved level, EXP and HP after returning to the world")

	section("Battle: defeat")
	partner.current_hp = 1
	EncounterManager.force_next_encounter()
	await hold(&"move_left", 0.25)
	var defeat_spot := player.global_position
	check(BattleManager.is_active(), "battle starts with 1 HP left")
	await wait_for_ui(BattleScene.UiState.ACTION_MENU)
	BattleManager.forced_turn_order = -1
	log_start = scene.message_log.size()
	var lost := [false]
	BattleManager.battle_lost.connect(func(_b: BattleContext) -> void: lost[0] = true, CONNECT_ONE_SHOT)
	await press(&"interact")
	await press(&"interact")
	check(await wait_battle_over(), "battle ends after the partner faints")
	turn_log = scene.message_log.slice(log_start)
	check(lost[0] and partner.current_hp == 0, "partner at exactly 0 HP; battle_lost emitted")
	check(turn_log.has("%s fainted!" % partner.get_display_name()) and turn_log.has(BattleMessages.NO_USABLE_CREATURES),
			"defeat messages")
	check(PartyManager.get_creature(0) == partner and PartyManager.get_size() == party_before, "partner stays in the party")
	await assert_back_in_world(defeat_spot)
	check(last_save_reason == &"battle_defeat" and saved_party(0)["current_hp"] == 0, "defeat autosaved (0 HP)")
	BattleManager.reset_test_overrides()
	EncounterManager.force_next_encounter()
	var started := encounters_started
	await hold(&"move_right", 0.4)
	check(encounters_started == started and not BattleManager.is_active(),
			"no encounters while the party can't fight")

	section("Resting heals the party")
	SceneRouter.go_to("res://scenes/world/maps/player_house.tscn", &"entrance")
	check(await wait_for_map(&"player_house"), "home")
	await place(Vector2(176, 92), Vector2.UP)
	var bed := world.current_map.get_node("Objects/Bed")
	check(interaction.target == bed.get_node("Interactable"), "facing the bed targets it")
	await rest_in_bed()
	check(partner.current_hp == partner.get_max_hp(), "bed restores full HP (%d)" % partner.current_hp)
	check(last_save_reason == &"rested" and saved_party(0)["current_hp"] == partner.get_max_hp(), "resting autosaved the healed party")
	await close_dialogue()

	section("Battle: persistence")
	check(not FileAccess.get_file_as_string(TEST_SAVE_PATH).contains(wild.uid), "wild creature never persisted")
	check(saved_party(0)["level"] == level_before + 1, "the level-up is in the save file")
	SceneRouter.go_to("res://scenes/world/maps/fernhollow_town.tscn", &"player_home_front")
	await wait_for_map(&"fernhollow_town")


func assert_back_in_world(spot: Vector2) -> void:
	check(not battle_scene().visible and BattleManager.state == BattleManager.State.NONE
			and BattleManager.battle == null, "battle scene closed, battle cleared")
	check(not EncounterManager.has_active_encounter(), "encounter state cleared")
	check(world.current_map.map_id == &"route_01" and player.global_position == spot, "same map and position")
	await frames(3)
	check(player.controls_enabled and interaction.active, "controls and interaction restored")


func battle_scene() -> BattleScene:
	return main.get_node("BattleScene") as BattleScene


func wait_for_ui(state: BattleScene.UiState, max_frames := 600) -> bool:
	for i in max_frames:
		if battle_scene().ui_state == state and not SceneRouter.is_busy():
			return true
		await get_tree().physics_frame
	return false


func wait_battle_over(max_frames := 900) -> bool:
	for i in max_frames:
		if not BattleManager.is_active() and not battle_scene().visible and not SceneRouter.is_busy():
			return true
		await get_tree().physics_frame
	return false


## Ends the current battle with a one-hit win, without asserting anything about it.
func win_battle_quickly() -> void:
	await wait_for_ui(BattleScene.UiState.ACTION_MENU)
	BattleManager.forced_turn_order = 1
	BattleManager.forced_damage = 999
	BattleManager.force_hit = true
	await fight_with_first_move()
	await wait_battle_over()
	BattleManager.reset_test_overrides()


## Picks FIGHT (whatever action the menu cursor was left on) and the first move.
func fight_with_first_move() -> void:
	await mouse_click(battle_scene().get_node("%FightOption"))
	await press(&"ui_accept")


func label_text(root: Node, unique_name: String) -> String:
	return (root.get_node("%" + unique_name) as Label).text


# --- Phase 9: battle actions, pause menu, checkpoints ---------------------------------------

func test_battle_actions() -> void:
	section("Battle actions: menu")
	await place(Vector2(320, 60), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(await wait_for_map(&"route_01"), "on Route 01")
	var scene := battle_scene()
	var pause := main.get_node("PauseMenu") as PauseMenu
	var zone := world.current_map.get_node("EncounterZones/TallGrassSouth") as EncounterZone
	zone.encounter_rate = 0.0
	var partner := PartyManager.get_creature(0)
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter()
	await hold(&"move_right", 0.25)
	var spot := player.global_position
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle ready")
	var wild := BattleManager.battle.wild
	var wild_name := "Wild " + wild.get_species().display_name
	var labels := PackedStringArray()
	for option in scene.get_node("%ActionMenu").get_children():
		labels.append((option.get_child(0) as Label).text)
	check(labels == PackedStringArray(["FIGHT", "CREATURE", "ITEM", "RUN"]), "action grid: FIGHT CREATURE / ITEM RUN")
	check(scene.get_selected_action() == BattleScene.Action.FIGHT, "FIGHT selected first")
	var item_label := scene.get_node("%ItemOption").get_child(0) as Label
	check(scene.is_action_available(BattleScene.Action.ITEM)
			and item_label.get_theme_color(&"font_color") != BattleScene.TEXT_DISABLED, "ITEM is available (Phase 11)")
	await press(&"ui_right")
	check(scene.get_selected_action() == BattleScene.Action.CREATURE, "Right -> CREATURE")
	await press(&"move_down")
	check(scene.get_selected_action() == BattleScene.Action.RUN, "S -> RUN")
	await press(&"ui_left")
	check(scene.get_selected_action() == BattleScene.Action.ITEM, "Left -> ITEM")
	await press(&"move_up")
	check(scene.get_selected_action() == BattleScene.Action.FIGHT, "W -> FIGHT")
	await shot("20_battle_actions")
	await press(&"ui_cancel")
	check(not pause.is_open() and BattleManager.is_active(), "Esc in battle doesn't open the pause menu")

	await press(&"ui_accept")
	var first_option := scene.get_node("%MoveGrid").get_child(0)
	var first_move := CreatureDatabase.get_move(partner.move_ids[0])
	check(scene.ui_state == BattleScene.UiState.MOVE_MENU
			and label_text_in(first_option, 0) == first_move.display_name
			and label_text_in(first_option, 1) == "%s %d" % [first_move.element.display_name, first_move.power],
			"FIGHT opens moves showing name, element and power")
	await shot("21_battle_moves")
	await press(&"ui_cancel")

	section("Battle actions: ITEM / CREATURE")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(scene.ui_state == BattleScene.UiState.ITEM_MENU
			and scene.get_creature_rows() == PackedStringArray(["Capture Orb x%d" % GameSession.inventory.get_quantity(&"capture_orb")]),
			"ITEM lists the inventory (%s)" % [scene.get_creature_rows()])
	await press(&"ui_cancel")
	check(scene.ui_state == BattleScene.UiState.ACTION_MENU and not scene.get_node("%Overlay").visible,
			"...and returns to the battle menu")
	await press(&"ui_up")
	await press(&"ui_right")
	await press(&"ui_accept")
	var rows := scene.get_creature_rows()
	check(scene.ui_state == BattleScene.UiState.CREATURE_MENU and rows.size() == 6
			and rows[0] == "%s Lv. %d %d/%d Active" % [partner.get_display_name(), partner.level, partner.current_hp, partner.get_max_hp()]
			and rows.slice(1) == PackedStringArray(["Empty", "Empty", "Empty", "Empty", "Empty"]),
			"CREATURE lists the party from PartyManager %s" % [rows])
	check(scene.get_overlay_footer() == BattleMessages.ONLY_ONE_CREATURE, "'Only one creature is available.'")
	await shot("22_battle_creatures")
	await press(&"ui_accept")
	check(scene.get_overlay_footer() == "%s is already in battle!" % partner.get_display_name()
			and BattleManager.battle.player == partner, "can't switch to the active creature")
	await press(&"ui_cancel")
	check(scene.ui_state == BattleScene.UiState.ACTION_MENU, "Esc returns to the battle menu")

	var extra := make_creature(&"mossaur", 3)
	extra.current_hp = 0
	PartyManager.add_creature(extra)
	await mouse_click(scene.get_node("%CreatureOption"))
	check(scene.ui_state == BattleScene.UiState.CREATURE_MENU and scene.get_creature_rows().size() == 6
			and scene.get_creature_rows()[1].begins_with("Mossaur Lv. 3") and scene.get_creature_rows()[1].ends_with("Fainted"),
			"mouse opens CREATURE; fainted reserve is marked")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(scene.get_overlay_footer() == "Mossaur has no energy left to battle!", "fainted creature can't be chosen")
	await mouse_click(scene.get_node("%OverlayBack"))
	check(scene.ui_state == BattleScene.UiState.ACTION_MENU, "mouse BACK returns to the battle menu")
	PartyManager.remove_creature(extra)

	section("Battle actions: RUN")
	await mouse_move(scene.get_node("%RunOption"))
	check(scene.get_selected_action() == BattleScene.Action.RUN, "mouse hover selects RUN")
	BattleManager.force_hit = true
	BattleManager.forced_random_factor = 1.0
	BattleManager.forced_ai_move = &"tackle"
	BattleManager.forced_escape = -1
	var expected_chance := BattleCalculator.escape_chance(partner.get_stat(CreatureStats.Stat.SPEED),
			wild.get_stat(CreatureStats.Stat.SPEED), 0)
	check(is_equal_approx(BattleManager.get_escape_chance(), expected_chance), "escape chance comes from BattleCalculator")
	var exp_before := partner.experience
	var level_before := partner.level
	var my_hp := partner.current_hp
	var log_start := scene.message_log.size()
	await press(&"ui_accept")
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "failed run: battle continues")
	var turn_log := scene.message_log.slice(log_start)
	check(turn_log.has(BattleMessages.ESCAPE_FAILED) and turn_log.find("%s used Tackle!" % wild_name) > turn_log.find(BattleMessages.ESCAPE_FAILED),
			"'You couldn't get away!' then the wild creature attacks")
	check(partner.current_hp < my_hp and BattleManager.battle.failed_escapes == 1, "wild got its free turn; attempt counted")
	var rules_events := BattleManager.submit_run()
	check(rules_events.size() >= 1 and rules_events[0].type == BattleEvent.Type.ESCAPE_FAILED
			and BattleManager.battle.failed_escapes == 2, "RUN is resolved by BattleManager (no UI involved)")
	BattleManager.forced_escape = 1
	var wild_hp := wild.current_hp
	var saves_before := saves
	log_start = scene.message_log.size()
	await press(&"ui_accept")
	check(await wait_battle_over(), "successful run ends the battle")
	check(scene.message_log.slice(log_start).has(BattleMessages.ESCAPED), "'Got away safely!'")
	check(partner.experience == exp_before and partner.level == level_before and wild.current_hp == wild_hp,
			"no EXP gained, wild creature untouched")
	await assert_back_in_world(spot)
	check(saves > saves_before and last_save_reason == &"battle_escaped" and saved_party(0)["current_hp"] == partner.current_hp,
			"escape autosaved after returning to the world")
	BattleManager.reset_test_overrides()


func test_pause_menu() -> void:
	section("Pause menu")
	var pause := main.get_node("PauseMenu") as PauseMenu
	await place(Vector2(400, 600), Vector2.DOWN)
	check(not pause.is_open() and GameSession.can_pause(), "can pause while exploring")
	await press(&"ui_cancel")
	check(pause.is_open() and GameSession.is_paused() and pause.get_selected_option() == PauseMenu.Option.CONTINUE,
			"Esc opens PAUSED with Continue selected")
	var spot := player.global_position
	await hold(&"move_up", 0.3)
	check(player.global_position == spot and interaction.target == null, "player frozen and can't interact while paused")
	await press(&"ui_down")
	check(pause.get_selected_option() == PauseMenu.Option.CREATURES, "Down -> Creatures")
	await press(&"move_down")
	check(pause.get_selected_option() == PauseMenu.Option.SAVE, "S -> Save Game")

	var partner := PartyManager.get_creature(0)
	partner.current_hp = maxi(partner.current_hp - 3, 1)
	var saves_before := saves
	await press(&"ui_accept")
	var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_PATH))
	check(saves == saves_before + 1 and last_save_reason == &"manual" and label_text(pause, "Status") == "Game saved.",
			"Save Game saves and says so")
	check(save["world"]["map"] == world.current_map_path and save["world"]["map"].ends_with("route_01.tscn"), "save has the map")
	check(Vector2(save["world"]["position"]["x"], save["world"]["position"]["y"]) == player.global_position, "save has the position")
	check(Vector2(save["world"]["facing"]["x"], save["world"]["facing"]["y"]) == player.facing, "save has the facing")
	check(saved_party(0)["current_hp"] == partner.current_hp and saved_party(0)["experience"] == partner.experience
			and saved_party(0)["level"] == partner.level, "save has party HP, EXP and level")
	check(saved_party(0)["uid"] == partner.uid and saved_party(0)["species_id"] == String(partner.species_id)
			and saved_party(0)["moves"] == Array(partner.move_ids).map(func(m: StringName) -> String: return String(m))
			and saved_party(0).has("nickname") and saved_party(0).has("status"), "save has uid, species, moves, nickname, status")
	check(save["game_state"]["starter_selected"] == true and save["game_state"]["starter_species"] == "flamkit",
			"save has the story flags")
	check(int(save["version"]) == SaveManager.CURRENT_SAVE_VERSION and SaveManager.is_save_valid(),
			"save version %d and it validates" % SaveManager.CURRENT_SAVE_VERSION)
	check((main.get_node("SaveNotice") as SaveNotice).is_showing(), "'Game saved.' notice shown")
	await shot("23_pause_saved")

	await mouse_move(pause.get_node("%SettingsOption"))
	check(pause.get_selected_option() == PauseMenu.Option.SETTINGS, "mouse hover selects Settings")
	await mouse_click(pause.get_node("%SettingsOption"))
	check(pause.is_settings_open(), "Settings opens")
	await press(&"ui_cancel")
	check(not pause.is_settings_open() and pause.is_open(), "Esc closes Settings, still paused")
	var dialog := pause.get_node("%Dialog") as ChoiceDialog
	await mouse_click(pause.get_node("%TitleOption"))
	check(dialog.is_open() and dialog.get_node("%DialogTitle").text == "Return to title?"
			and dialog.get_node("%DialogMessage").text == "Your game will be saved first." and dialog.get_selected_index() == 1,
			"Return to Title asks first (default NO)")
	await press(&"ui_accept")
	check(not dialog.is_open() and pause.is_open() and GameSession.state == GameSession.State.PLAYING, "NO stays paused")
	await mouse_click(pause.get_node("%ContinueOption"))
	check(not pause.is_open() and player.controls_enabled, "Continue (mouse) resumes")
	await hold(&"move_up", 0.2)
	check(player.global_position != spot, "player moves again after resuming")

	section("Pause menu: refused while busy")
	var mira_dialogue := load("res://data/dialogue/villager_mira.tres") as DialogueData
	DialogueManager.start(mira_dialogue)
	await press(&"ui_cancel")
	check(not pause.is_open(), "no pause during dialogue")
	await close_dialogue()
	SceneRouter.go_to("res://scenes/world/maps/fernhollow_town.tscn", &"north_exit_arrival")
	await frames(2)
	await press(&"ui_cancel")
	check(not pause.is_open(), "no pause during a map transition")
	await wait_for_map(&"fernhollow_town")

	section("Pause menu: return to title")
	await press(&"ui_cancel")
	await press(&"ui_up")
	check(pause.get_selected_option() == PauseMenu.Option.TITLE, "Up wraps to Return to Title")
	var quit_spot := player.global_position
	await press(&"ui_accept")
	await press(&"ui_left")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.TITLE), "YES returns to the title")
	check(last_save_reason == &"return_to_title" and not pause.is_open() and not GameSession.is_paused(),
			"saved first; pause closed")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	check(world.current_map.map_id == &"fernhollow_town" and player.global_position == quit_spot,
			"Continue resumes exactly where the game was left")


func test_map_autosave() -> void:
	section("Autosave on map change")
	var saves_before := saves
	await place(Vector2(128, 420), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(await wait_for_map(&"research_lab"), "entered the lab")
	check(saves == saves_before + 1 and last_save_reason == &"map_entered", "one autosave after the transition")
	var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_PATH))
	check(save["world"]["map"] == LAB_MAP and Vector2(save["world"]["position"]["x"], save["world"]["position"]["y"])
			== Vector2(192, 200), "save points at the lab entrance")
	var notice := main.get_node("SaveNotice") as SaveNotice
	var before := player.global_position
	await hold(&"move_up", 0.2)
	check(notice.is_showing() and player.global_position != before, "notice doesn't block movement")
	await place(Vector2(192, 200), Vector2.DOWN)
	await hold(&"move_down", 0.6)
	await wait_for_map(&"fernhollow_town")


func saved_party(slot: int) -> Dictionary:
	var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_PATH))
	return save["party"][slot]


func label_text_in(container: Node, index: int) -> String:
	return (container.find_children("*", "Label", true, false)[index] as Label).text


# --- Phase 10: roster, data validation, encounters, battle polish ---------------------------

const ALL_SPECIES: Array[StringName] = [
	&"flamkit", &"aquaphin", &"mossaur", &"pebblit", &"cindrake", &"rivulet", &"thornling", &"brambleox", &"tideclaw",
]
const NEW_MOVES := {
	&"quick_jab": [&"neutral", 30], &"flame_burst": [&"ember", 55],
	&"water_pulse": [&"tide", 50], &"leaf_cutter": [&"verdant", 50],
}
const OWNED_INSTANCE_FIELDS := ["uid", "species_id", "nickname", "level", "experience", "current_hp", "move_ids", "status"]


func test_database_validation() -> void:
	section("Phase 10 · Database: roster")
	check(CreatureDatabase.load_problems.is_empty(), "all data files load without problems %s" % [CreatureDatabase.load_problems])
	var ids: Array[StringName] = []
	for species in CreatureDatabase.get_all_species():
		ids.append(species.id)
	ids.sort()
	var expected := ALL_SPECIES.duplicate()
	expected.sort()
	check(ids == expected, "exactly the 9 species are registered, ids unique %s" % [ids])
	for id in ALL_SPECIES:
		var species := CreatureDatabase.get_species(id)
		if species == null:
			check(false, "%s registered" % id)
			continue
		var stats_ok := true
		for stat in CreatureStats.Stat.values():
			stats_ok = stats_ok and species.get_base_stat(stat) > 0
		var moves_ok := not species.starting_moves.is_empty()
		for move in species.starting_moves:
			moves_ok = moves_ok and move != null and CreatureDatabase.get_move(move.id) == move
		check(species.id == id and not species.display_name.is_empty() and not species.description.is_empty()
				and not species.role.is_empty() and species.sprite is Texture2D
				and CreatureDatabase.get_element(species.element.id) == species.element and stats_ok and moves_ok
				and CreatureDatabase.validate_species(species).is_empty(),
				"%s: name, description, role, sprite, element %s, stats, moves %s" % [
					species.display_name, species.element.id, species.starting_moves.map(func(m: MoveData) -> StringName: return m.id)])
		var creature := CreatureFactory.create_from_species(species, 4)
		check(creature.get_species() == species and creature.level == 4 and creature.current_hp == creature.get_max_hp()
				and creature.move_ids.size() == species.starting_moves.size(), "factory creates a level-4 %s" % species.display_name)

	var designed := {
		&"pebblit": [&"neutral", "Balanced", [50, 48, 52, 42]], &"cindrake": [&"ember", "Offensive", [48, 65, 38, 62]],
		&"rivulet": [&"tide", "Balanced", [52, 52, 48, 60]], &"thornling": [&"verdant", "Offensive", [50, 58, 45, 55]],
		&"brambleox": [&"verdant", "Defensive", [72, 50, 68, 28]], &"tideclaw": [&"tide", "Offensive", [54, 63, 42, 58]],
	}
	for id: StringName in designed:
		var species := CreatureDatabase.get_species(id)
		var d: Array = designed[id]
		check(species.element.id == d[0] and species.role == d[1]
				and [species.base_hp, species.base_attack, species.base_defense, species.base_speed] == d[2],
				"%s matches its design (%s, %s, %s)" % [species.display_name, d[0], d[1], d[2]])

	section("Phase 10 · Database: moves")
	var move_ids: Array[StringName] = []
	for move in CreatureDatabase.get_all_moves():
		move_ids.append(move.id)
		check(CreatureDatabase.validate_move(move).is_empty(), "move %s is valid" % move.id)
	check(move_ids.size() == 8, "8 moves registered, ids unique")
	for id: StringName in NEW_MOVES:
		var move := CreatureDatabase.get_move(id)
		check(move != null and move.element.id == NEW_MOVES[id][0] and move.power == NEW_MOVES[id][1],
				"new move %s: %s, power %d" % [id, NEW_MOVES[id][0], NEW_MOVES[id][1]])
	var used := {}
	for species in CreatureDatabase.get_all_species():
		for move in species.starting_moves:
			used[move.id] = true
	check(NEW_MOVES.keys().all(func(id: StringName) -> bool: return used.has(id)), "every new move is known by some species")

	section("Phase 10 · Database: shared species vs owned instances")
	var flamkit := CreatureDatabase.get_species(&"flamkit")
	var a := CreatureFactory.create_from_species(flamkit, 5)
	var b := CreatureFactory.create_from_species(flamkit, 9)
	var instance_fields := PackedStringArray()
	for property in a.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			instance_fields.append(property["name"])
	check(Array(instance_fields) == OWNED_INSTANCE_FIELDS, "instances hold only owned state %s" % instance_fields)
	a.level = 50
	a.current_hp = 1
	check(a.get_species() == b.get_species() and flamkit.base_hp == 45 and flamkit.base_attack == 60
			and b.get_max_hp() == 45 + 9 * 2, "species data is shared and unchanged by instance changes")
	var saved := JSON.stringify(a.to_save_data())
	check(not saved.contains("base_hp") and not saved.contains("description") and saved.contains("\"species_id\""),
			"save data stores ids and owned state, never species data")

	section("Phase 10 · Database: invalid data is rejected")
	var species_count := CreatureDatabase.get_all_species().size()
	var blank := CreatureSpecies.new()
	var problems := CreatureDatabase.validate_species(blank)
	check(problems.size() >= 5 and "\n".join(problems).contains("no id") and "\n".join(problems).contains("element")
			and "\n".join(problems).contains("sprite") and "\n".join(problems).contains("starting moves"),
			"empty species: %d problems reported" % problems.size())
	var ghost_move := MoveData.new()
	ghost_move.id = &"ghost_move"
	var broken := flamkit.duplicate() as CreatureSpecies
	broken.id = &"broken_kit"
	broken.starting_moves = [ghost_move, null]
	check("\n".join(CreatureDatabase.try_register_species(broken)).contains("isn't registered")
			and CreatureDatabase.get_species(&"broken_kit") == null, "species with a missing move is not registered")
	var stranger := ElementData.new()
	stranger.id = &"shadow"
	var odd := flamkit.duplicate() as CreatureSpecies
	odd.id = &"odd_kit"
	odd.element = stranger
	check(not CreatureDatabase.try_register_species(odd).is_empty() and CreatureDatabase.get_species(&"odd_kit") == null,
			"species with an unregistered element is not registered")
	var twin := flamkit.duplicate() as CreatureSpecies
	check("\n".join(CreatureDatabase.try_register_species(twin)).contains("duplicate species id")
			and CreatureDatabase.get_species(&"flamkit") == flamkit, "duplicate species id rejected; original kept")
	var nameless := MoveData.new()
	nameless.element = CreatureDatabase.get_element(&"neutral")
	check("\n".join(CreatureDatabase.try_register_move(nameless)).contains("no id"), "move without an id rejected")
	var copy := CreatureDatabase.get_move(&"tackle").duplicate() as MoveData
	check("\n".join(CreatureDatabase.try_register_move(copy)).contains("duplicate move id")
			and CreatureDatabase.get_move(&"tackle") != copy, "duplicate move id rejected")
	check(CreatureDatabase.get_all_species().size() == species_count and CreatureDatabase.get_all_moves().size() == 8,
			"failed registrations leave the database unchanged")
	var survivor := CreatureFactory.create_from_species(broken, 3)
	check(Array(survivor.move_ids) == [&"ghost_move"], "factory skips null moves instead of crashing")

	section("Phase 10 · New moves resolve in the damage formula")
	for id: StringName in NEW_MOVES:
		var move := CreatureDatabase.get_move(id)
		var all_match := true
		for defender_id: StringName in [&"pebblit", &"cindrake", &"rivulet", &"thornling"]:
			var attacker := make_creature(&"tideclaw", 5)
			var defender := make_creature(defender_id, 5)
			var multiplier := move.element.effectiveness_against(defender.get_species().element)
			var atk := attacker.get_stat(CreatureStats.Stat.ATTACK)
			var def := defender.get_stat(CreatureStats.Stat.DEFENSE)
			var formula := maxi(1, floori(((4.0 * move.power * atk / def) / 50.0 + 2.0) * multiplier))
			var result := BattleCalculator.calculate_damage(attacker, defender, move, 1.0)
			if result["damage"] != formula or result["effectiveness"] != multiplier:
				all_match = false
				print("    mismatch %s vs %s: expected %d x%.1f, got %s" % [id, defender_id, formula, multiplier, result])
		check(all_match, "%s matches the formula against 4 defenders (incl. 2x / 0.5x matchups)" % id)


func test_route_table() -> void:
	section("Phase 10 · Route 01 encounter table")
	var table := load("res://data/encounters/route_01.tres") as EncounterTable
	check(table.get_total_weight() == 100, "weights total 100%")
	check(table.get_usable_entries().size() == table.entries.size(), "no entry has an unknown species or zero weight")
	var owned := {}
	for roll in range(1, 101):
		var entry := table.entry_for_roll(roll)
		owned[entry.species_id] = owned.get(entry.species_id, 0) + 1
	check(owned == ROUTE_01_WEIGHTS, "every roll 1-100 maps to a species; each owns exactly its weight %s" % owned)
	check(ROUTE_01_WEIGHTS.keys().all(func(id: StringName) -> bool: return owned.get(id, 0) > 0),
			"all 9 species are reachable")
	check(table.entry_for_roll(0) == table.entries[0] and table.entry_for_roll(101) == null, "rolls outside 1-100 are not valid picks")
	check(table.entries.all(func(e: EncounterEntry) -> bool: return e.min_level == 2 and e.max_level == 5),
			"every entry keeps the Lv. 2-5 range")
	EncounterManager.rng.seed = 404
	var level_ok := true
	for i in 500:
		var creature := EncounterManager.generate_wild_creature(table)
		level_ok = level_ok and creature.level >= 2 and creature.level <= 5 and ALL_SPECIES.has(creature.species_id)
	check(level_ok, "500 seeded wild creatures: valid species, Lv. 2-5")
	EncounterManager.rng.seed = 1234


func test_encounter_gates() -> void:
	section("Phase 10 · Encounter gates")
	await place(Vector2(320, 60), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(await wait_for_map(&"route_01"), "on Route 01")
	await place(Vector2(392, 560), Vector2.UP)
	var zone := world.current_map.get_node("EncounterZones/TallGrassSouth") as EncounterZone
	var partner := PartyManager.get_creature(0)
	var gate := func(label: String) -> void:
		var before := encounters_started
		EncounterManager.force_next_encounter()
		EncounterManager.register_step(zone)
		check(encounters_started == before, "%s: no encounter even when forced" % label)
	GameState.starter_selected = false
	gate.call("no starter")
	GameState.starter_selected = true
	var hp := partner.current_hp
	partner.current_hp = 0
	gate.call("party at 0 HP")
	partner.current_hp = hp
	zone.encounter_enabled = false
	gate.call("zone disabled")
	zone.encounter_enabled = true
	DialogueManager.start(load("res://data/dialogue/sign_route01.tres"))
	gate.call("during dialogue")
	await close_dialogue()
	SceneRouter.transition(func() -> void: pass)
	gate.call("during a transition")
	await wait_for_state(GameSession.State.PLAYING)
	var steps := EncounterManager.steps_in_zones
	var started := encounters_started
	await hold(&"move_up", 0.4)
	check(EncounterManager.steps_in_zones == steps and encounters_started == started, "walking outside grass: no steps, no encounter")
	EncounterManager.force_next_encounter()
	EncounterManager.register_step(zone)
	check(encounters_started == started + 1, "with every gate open, the forced step starts an encounter")
	await wait_for_ui(BattleScene.UiState.ACTION_MENU)
	gate.call("during a battle")
	await win_battle_quickly()
	# Gated steps never consumed the forced flag; clear it so it can't leak into later tests.
	EncounterManager.reset()


func test_roster_battles() -> void:
	section("Phase 10 · Every species in battle")
	var scene := battle_scene()
	var notice := main.get_node("SaveNotice") as SaveNotice
	var zone := world.current_map.get_node("EncounterZones/TallGrassSouth") as EncounterZone
	zone.encounter_rate = 0.0
	var party_before := PartyManager.get_size()
	for id in ALL_SPECIES:
		var species := CreatureDatabase.get_species(id)
		await place(Vector2(470, 536), Vector2.RIGHT)
		var first := id == ALL_SPECIES[0]
		if first:
			check(GameSession.save_now(&"manual") and notice.is_showing(), "'Game saved.' notice is showing just before the encounter")
		EncounterManager.force_next_encounter_species(id, 3)
		await hold(&"move_right", 0.25)
		if first:
			# Checked the moment the battle starts, long before the notice would have faded on its own.
			check(BattleManager.is_active() and not notice.is_showing(), "the notice is dismissed as soon as the battle starts")
		if not await wait_for_ui(BattleScene.UiState.ACTION_MENU):
			check(false, "%s battle opened" % id)
			continue
		var wild := BattleManager.battle.wild
		var enemy_panel := scene.get_node("%EnemyPanel") as BattleStatusPanel
		check(wild.species_id == id and wild.level == 3 and label_text(enemy_panel, "Name") == "Wild " + species.display_name
				and label_text(enemy_panel, "Level") == "Lv. 3" and enemy_panel.get_element_text() == species.element.display_name.to_upper()
				and (scene.get_node("%EnemySprite") as TextureRect).texture == species.sprite
				and (enemy_panel.get_node("%HpBar") as ProgressBar).max_value == wild.get_max_hp(),
				"wild %s: name, level, element %s, sprite, HP bar from species data" % [species.display_name, species.element.id])
		if first:
			check(not notice.is_showing(), "...and stays hidden during the battle")
			await shot("24_battle_panels")
		if id == &"tideclaw":
			await shot("25_battle_tideclaw")
		await win_battle_quickly()
		check(BattleManager.state == BattleManager.State.NONE and PartyManager.get_size() == party_before
				and last_save_reason == &"battle_victory" and world.current_map.map_id == &"route_01",
				"beat wild %s; back on Route 01; autosaved" % species.display_name)
	check(PartyManager.get_size() == party_before and PartyManager.get_creature(0).species_id == &"flamkit",
			"no wild creature joined the party")
	var player_panel := scene.get_node("%PlayerPanel") as BattleStatusPanel
	check(player_panel.get_element_text() == "EMBER", "player panel shows the partner's element")


func test_new_moves_and_levels() -> void:
	section("Phase 10 · New moves, effectiveness feedback, multi-level-up")
	var scene := battle_scene()
	var original := PartyManager.get_party()
	PartyManager.clear()
	var sprout := make_creature(&"thornling", 1)
	PartyManager.add_creature(sprout)
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter_species(&"aquaphin", 5)
	await hold(&"move_right", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "Lv. 1 Thornling vs wild Lv. 5 Aquaphin")
	var wild := BattleManager.battle.wild
	await press(&"ui_accept")
	check(scene.get_move_names() == PackedStringArray(["Tackle", "Vine Whip", "Leaf Cutter"]), "three moves listed")
	await press(&"ui_down")
	var leaf := CreatureDatabase.get_move(&"leaf_cutter")
	var multiplier := BattleManager.preview_effectiveness(&"leaf_cutter")
	check(scene.get_selected_move() == leaf and multiplier == 2.0 and label_text(scene, "MoveEffect") == "Effective",
			"Leaf Cutter vs Aquaphin labelled 'Effective' (from BattleCalculator: x%.1f)" % multiplier)
	await press(&"ui_up")
	check(label_text(scene, "MoveEffect") == BattleMessages.effectiveness_label(BattleManager.preview_effectiveness(&"tackle"))
			and label_text(scene, "MoveEffect") == "Normal", "Tackle labelled 'Normal'")
	await shot("26_battle_effectiveness")
	await press(&"ui_down")
	BattleManager.force_hit = true
	BattleManager.forced_random_factor = 1.0
	BattleManager.forced_ai_move = &"tackle"
	BattleManager.forced_turn_order = 1
	var expected_damage: int = BattleCalculator.calculate_damage(sprout, wild, leaf, 1.0)["damage"]
	var log_start := scene.message_log.size()
	await press(&"ui_accept")
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "turn resolved")
	var turn_log := scene.message_log.slice(log_start)
	var damage_line := turn_log.find("Wild Aquaphin took %d damage!" % expected_damage)
	check(turn_log.find("Thornling used Leaf Cutter!") >= 0 and damage_line >= 0
			and turn_log.find(BattleMessages.SUPER_EFFECTIVE) == damage_line + 1,
			"'used Leaf Cutter!' -> 'took %d damage!' -> 'Super effective!'" % expected_damage)
	check((scene.get_node("%EnemyPanel").get_node("%HpBar") as ProgressBar).value == wild.current_hp, "enemy HP bar matches")

	var hp_before := sprout.current_hp
	var max_before := sprout.get_max_hp()
	BattleManager.forced_damage = 999
	log_start = scene.message_log.size()
	await press(&"ui_accept")
	await press(&"ui_accept")
	check(await wait_battle_over(), "won")
	turn_log = scene.message_log.slice(log_start)
	var gained := CreatureProgression.exp_reward(5)
	check(turn_log.has("Thornling gained %d EXP!" % gained) and turn_log.has("Thornling grew to level 2!")
			and turn_log.has("Thornling grew to level 3!"), "50 EXP at Lv. 1: two level-up messages")
	check(sprout.level == 3 and sprout.experience == 0, "lands exactly on the Lv. 3 threshold (10 + 40 EXP)")
	check(sprout.get_max_hp() == max_before + 4 and sprout.current_hp == hp_before + 4, "max HP and current HP both +4")
	check(last_save_reason == &"battle_victory" and saved_party(0)["species_id"] == "thornling"
			and saved_party(0)["level"] == 3 and saved_party(0)["experience"] == 0
			and saved_party(0)["current_hp"] == sprout.current_hp, "the post-level-up state is what got autosaved")
	BattleManager.reset_test_overrides()
	PartyManager.clear()
	for creature in original:
		PartyManager.add_creature(creature)
	check(GameSession.save_now(&"manual") and saved_party(0)["species_id"] == "flamkit", "original party restored and saved")


# --- Phase 11: harness, inventory, saves v2, capture, switching, storage --------------------

const FIXTURE_PATH := "user://test_fixture.json"
## A save written by version 1 of the game (Phases 5-10 format: no inventory, storage or active index).
const V1_FIXTURE := {
	"version": 1,
	"saved_at": "2026-10-03T12:00:00",
	"world": {"map": "res://scenes/world/maps/route_01.tscn", "position": {"x": 392.0, "y": 560.0},
			"facing": {"x": 1.0, "y": 0.0}},
	"game_state": {"starter_selected": true, "starter_species": "flamkit"},
	"party": [
		{"uid": "v1-fixture-flamkit", "species_id": "flamkit", "nickname": "", "level": 7, "experience": 120,
				"current_hp": 40, "moves": ["tackle", "ember"], "status": ""},
		{"uid": "v1-fixture-aquaphin", "species_id": "aquaphin", "nickname": "Bubbles", "level": 5, "experience": 3,
				"current_hp": 0, "moves": ["tackle", "splash"], "status": ""},
	],
}


func test_harness_self_check() -> void:
	section("Phase 11 · Test harness fails loudly")
	var broken := "user://harness_broken.gd"
	var hang := "user://harness_hang.gd"
	write_file(broken, "extends Node\nfunc _ready() -> void\n\tthis is not valid gdscript (\n")
	write_file(hang, "extends Node\n## Never finishes.\n")
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"res://tests/smoke_test.tscn", "--", "--test-script=" + broken], out, true)
	check(code == 100 and "".join(out).contains("HARNESS FAILED: test script did not load"),
			"a test script that doesn't parse fails with exit code 100 (got %d)" % code)
	out.clear()
	code = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"res://tests/smoke_test.tscn", "--", "--test-script=" + hang, "--test-timeout=2"], out, true)
	check(code == 99 and "".join(out).contains("HARNESS FAILED: timeout"),
			"a test that never finishes is killed as a failure with exit code 99 (got %d)" % code)
	DirAccess.remove_absolute(broken)
	DirAccess.remove_absolute(hang)


func test_inventory_unit() -> void:
	section("Phase 11 · Items and inventory")
	var orb := ItemCatalog.get_item(&"capture_orb")
	check(ItemCatalog.load_problems.is_empty() and orb != null and orb.display_name == "Capture Orb"
			and orb.category == &"capture" and orb.description == "A device used to attempt the capture of a wild creature."
			and orb.icon != null, "Capture Orb item data loads")
	check(ItemCatalog.get_item(&"no_such_item") == null, "unknown item id resolves to nothing")
	var nameless := ItemData.new()
	check(ItemCatalog.validate_item(nameless).size() == 3, "an item without id, name or category is invalid")
	var bag := Inventory.new()
	check(bag.get_quantity(&"capture_orb") == 0 and not bag.has_item(&"capture_orb"), "empty inventory")
	check(bag.add_item(&"capture_orb", 3) and bag.get_quantity(&"capture_orb") == 3, "add 3")
	check(not bag.add_item(&"no_such_item") and not bag.add_item(&"capture_orb", 0), "unknown item / zero amount refused")
	check(bag.remove_item(&"capture_orb", 2) and bag.get_quantity(&"capture_orb") == 1, "remove 2")
	check(not bag.remove_item(&"capture_orb", 2) and bag.get_quantity(&"capture_orb") == 1, "can't remove more than held")
	check(bag.remove_item(&"capture_orb") and bag.get_items().is_empty() and not bag.has_item(&"capture_orb"),
			"quantity 0 removes the entry")
	bag.reset_to_starting_items()
	check(bag.get_items() == {&"capture_orb": 5}, "starting items: 5 Capture Orbs")
	var copy := Inventory.new()
	copy.load_save_data(JSON.parse_string(JSON.stringify(bag.to_save_data())))
	check(copy.get_items() == bag.get_items(), "save data round trip")
	copy.load_save_data({"capture_orb": 2, "ghost_item": 9})
	check(copy.get_items() == {&"capture_orb": 2}, "unknown item ids in a save are ignored")
	check(Inventory.validate_save_data({"capture_orb": 2}).is_empty(), "valid inventory data passes")
	var bad := {"list": [], "negative": {"capture_orb": -1}, "fraction": {"capture_orb": 1.5}, "text": {"capture_orb": "5"}}
	for label: String in bad:
		check(not Inventory.validate_save_data(bad[label]).is_empty(), "malformed inventory rejected: %s" % label)
	bag.clear()
	check(bag.get_items().is_empty(), "clear")


func test_save_v2_unit() -> void:
	section("Phase 11 · Save version 2 + migration")
	check(SaveManager.CURRENT_SAVE_VERSION == 3 and SaveManager.MIN_SUPPORTED_SAVE_VERSION == 1, "writes v3, still reads v1")
	var real_path := SaveManager.save_path
	SaveManager.save_path = FIXTURE_PATH
	write_file(FIXTURE_PATH, JSON.stringify(V1_FIXTURE))
	var result := SaveManager.read_save()
	var data: Dictionary = result["data"]
	check(result["error"].is_empty() and int(data["version"]) == 3, "v1 fixture reads as a valid v3 save")
	check(json(data["inventory"]) == json({"capture_orb": 5}) and data["storage"].is_empty() and int(data["active_index"]) == 0,
			"migration adds starting items, empty storage, active slot 0")
	check(json(data["world"]) == json(V1_FIXTURE["world"]) and json(data["game_state"]) == json(V1_FIXTURE["game_state"])
			and json(data["party"]) == json(V1_FIXTURE["party"]), "migration leaves world, flags and party untouched")
	check(FileAccess.get_file_as_string(FIXTURE_PATH) == JSON.stringify(V1_FIXTURE), "reading never rewrites the file")
	var v2 := V1_FIXTURE.duplicate(true)
	v2["version"] = 2
	v2["inventory"] = {"capture_orb": 3}
	v2["storage"] = []
	v2["active_index"] = 1
	var bad := {
		"missing inventory": {}, "inventory not a dictionary": {"inventory": [1]},
		"negative quantity": {"inventory": {"capture_orb": -2}}, "fractional quantity": {"inventory": {"capture_orb": 0.5}},
		"storage not a list": {"storage": {}}, "bad active index": {"active_index": -1},
	}
	for label: String in bad:
		var broken := v2.duplicate(true)
		if label == "missing inventory":
			broken.erase("inventory")
		else:
			broken.merge(bad[label], true)
		write_file(FIXTURE_PATH, JSON.stringify(broken))
		check(SaveManager.read_save()["error"] == SaveManager.ERROR_DAMAGED and not SaveManager.validate_save_data(broken).is_empty(),
				"v2 save with %s is rejected (read and write validation)" % label)
	write_file(FIXTURE_PATH, JSON.stringify(v2))
	check(SaveManager.is_save_valid(), "well-formed v2 save is valid")
	var too_new := v2.duplicate(true)
	too_new["version"] = 4
	write_file(FIXTURE_PATH, JSON.stringify(too_new))
	check(SaveManager.read_save()["error"] == SaveManager.ERROR_TOO_NEW, "v4 save rejected as too new")
	DirAccess.remove_absolute(FIXTURE_PATH)
	SaveManager.save_path = real_path


func test_party_and_storage_unit() -> void:
	section("Phase 11 · Party switching rules + storage")
	var party: Node = load("res://scripts/party/party_manager.gd").new()
	var a := make_creature(&"flamkit", 5)
	var b := make_creature(&"pebblit", 4)
	var c := make_creature(&"thornling", 3)
	c.current_hp = 0
	for creature in [a, b, c]:
		party.add_creature(creature)
	check(party.get_active_index() == 0 and party.get_active_creature() == a, "active slot defaults to 0")
	check(party.can_switch_to(1), "healthy reserve: can switch")
	check(not party.can_switch_to(0), "active creature: can't switch to itself")
	check(not party.can_switch_to(2), "fainted creature: can't switch")
	check(not party.can_switch_to(3) and not party.can_switch_to(-1) and not party.can_switch_to(99), "empty / invalid slots refused")
	check(not party.switch_active(2) and party.get_active_index() == 0, "refused switch changes nothing")
	check(party.switch_active(1) and party.get_active_creature() == b, "switch to slot 1")
	party.remove_creature(a)
	check(party.get_active_creature() == b and party.get_active_index() == 0, "removing an earlier slot keeps the same active creature")
	b.current_hp = 0
	check(party.ensure_usable_active() == null, "nobody can fight: no usable active creature")
	c.current_hp = 5
	check(party.ensure_usable_active() == c and party.get_active_index() == 1, "a fainted lead hands over to the first usable creature")
	party.load_save_data(party.to_save_data(), 7)
	check(party.get_active_index() == 0, "an out-of-range saved active index falls back to 0")
	party.load_save_data(party.to_save_data(), 1)
	check(party.get_active_index() == 1, "saved active index restored")
	party.free()

	var box := CreatureStorage.new()
	var stored := make_creature(&"rivulet", 6)
	check(box.add_creature(stored) and not box.add_creature(stored) and box.get_count() == 1 and box.get_creature(0) == stored,
			"storage add / no duplicates / get")
	var restored := CreatureStorage.new()
	restored.load_save_data(JSON.parse_string(JSON.stringify(box.to_save_data())))
	check(restored.get_count() == 1 and restored.get_creature(0).uid == stored.uid
			and JSON.stringify(restored.to_save_data()) == JSON.stringify(box.to_save_data()),
			"storage uses the same creature save format and round-trips")
	check(box.remove_creature(stored) and box.get_count() == 0 and box.get_creature(0) == null, "storage remove")
	box.add_creature(stored)
	box.clear()
	check(box.get_all().is_empty(), "storage clear")


func test_capture_rules_unit() -> void:
	section("Phase 11 · Capture chance + creature from wild")
	check(is_equal_approx(BattleCalculator.capture_chance(50, 50), BattleCalculator.MIN_CAPTURE_CHANCE), "full HP: 2% (minimum)")
	check(is_equal_approx(BattleCalculator.capture_chance(25, 50), 0.325), "half HP: 32.5%")
	check(is_equal_approx(BattleCalculator.capture_chance(1, 50), 0.65 * 49.0 / 50.0), "1 HP left: 63.7%")
	check(is_equal_approx(BattleCalculator.capture_chance(1, 50, 2.0), BattleCalculator.MAX_CAPTURE_CHANCE), "clamped to 95%")
	check(BattleCalculator.capture_chance(0, 50) == 0.0 and BattleCalculator.capture_chance(-3, 50) == 0.0
			and BattleCalculator.capture_chance(10, 0) == 0.0, "0 / negative / invalid HP: can't be caught")
	check(is_equal_approx(BattleCalculator.capture_chance(80, 50), BattleCalculator.MIN_CAPTURE_CHANCE), "HP above max treated as full")
	var wild := make_creature(&"cindrake", 4)
	wild.current_hp = 11
	wild.experience = 7
	var owned := CreatureFactory.create_from_wild(wild)
	check(owned.species_id == &"cindrake" and owned.level == 4 and owned.current_hp == 11 and owned.experience == 7
			and owned.move_ids == wild.move_ids and owned.status == wild.status, "caught creature keeps species, level, HP, EXP, moves")
	check(owned.uid != wild.uid and not owned.uid.is_empty() and owned.nickname == "Cindrake", "new UID; nickname defaults to the species name")
	owned.move_ids.append(&"tackle")
	check(wild.move_ids.size() == 3, "moves are copied, not shared")
	var uids := {}
	for i in 2000:
		uids[CreatureFactory.create_from_wild(wild).uid] = true
	check(uids.size() == 2000, "2000 captures in a row: 2000 unique UIDs")


func test_capture_in_battle() -> void:
	section("Phase 11 · Capture in battle")
	var scene := battle_scene()
	var zone := world.current_map.get_node("EncounterZones/TallGrassSouth") as EncounterZone
	zone.encounter_rate = 0.0
	GameSession.inventory.reset_to_starting_items()
	var partner := PartyManager.get_creature(0)
	var exp_before := partner.experience
	var party_before := PartyManager.get_size()
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter_species(&"pebblit", 4)
	await hold(&"move_right", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle vs wild Pebblit Lv. 4")
	var spot := player.global_position
	var wild := BattleManager.battle.wild
	wild.current_hp = 5
	await mouse_click(scene.get_node("%ItemOption"))
	check(scene.ui_state == BattleScene.UiState.ITEM_MENU and scene.get_creature_rows() == PackedStringArray(["Capture Orb x5"]),
			"ITEM shows 'Capture Orb x5'")
	await shot("27_item_menu")
	BattleManager.forced_capture = -1
	BattleManager.forced_ai_move = &"tackle"
	BattleManager.force_hit = true
	BattleManager.forced_random_factor = 1.0
	var log_start := scene.message_log.size()
	await press(&"ui_accept")
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "failed capture: battle continues")
	var turn_log := scene.message_log.slice(log_start)
	check(turn_log.has("You threw a Capture Orb!") and turn_log.has("Oh no! Pebblit broke free!")
			and turn_log.find("Wild Pebblit used Tackle!") > turn_log.find("Oh no! Pebblit broke free!"),
			"'threw' -> 'broke free' -> the wild creature takes its turn")
	check(GameSession.inventory.get_quantity(&"capture_orb") == 4 and BattleManager.state == BattleManager.State.PLAYER_ACTION,
			"one orb used even though it failed")
	BattleManager.forced_capture = 1
	var saves_before := saves
	log_start = scene.message_log.size()
	await mouse_click(scene.get_node("%ItemOption"))
	await mouse_click(scene.get_node("%OverlayList").get_child(0))
	check(await wait_battle_over(), "successful capture ends the battle")
	turn_log = scene.message_log.slice(log_start)
	check(turn_log.has("Pebblit was caught!") and turn_log.has("Pebblit joined your team!") and turn_log.find("Wild Pebblit used") == -1,
			"'Pebblit was caught!' -> 'joined your team!'; no wild turn after a capture")
	var caught := PartyManager.get_creature(party_before)
	check(PartyManager.get_size() == party_before + 1 and caught != null and caught.species_id == &"pebblit"
			and caught.level == 4 and caught.current_hp == 5 and caught.move_ids == wild.move_ids and caught.nickname == "Pebblit"
			and caught.uid != wild.uid, "caught Pebblit is in the party: Lv. 4, 5 HP, same moves, own UID")
	check(partner.experience == exp_before and GameSession.inventory.get_quantity(&"capture_orb") == 3, "no EXP for a capture; 3 orbs left")
	await assert_back_in_world(spot)
	check(saves > saves_before and last_save_reason == &"battle_caught" and saved_party(party_before)["uid"] == caught.uid
			and saved_save()["inventory"] == json({"capture_orb": 3}), "autosaved after returning: party + orbs")

	section("Phase 11 · Out of Capture Orbs")
	GameSession.inventory.remove_item(&"capture_orb", 3)
	EncounterManager.force_next_encounter_species(&"rivulet", 2)
	await hold(&"move_left", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle")
	await mouse_click(scene.get_node("%ItemOption"))
	check(scene.get_creature_rows() == PackedStringArray(["Capture Orb x0"]), "ITEM shows 'Capture Orb x0'")
	await press(&"ui_accept")
	check(scene.get_overlay_footer() == "Out of Capture Orbs." and scene.ui_state == BattleScene.UiState.ITEM_MENU
			and BattleManager.state == BattleManager.State.PLAYER_ACTION and GameSession.inventory.get_quantity(&"capture_orb") == 0,
			"'Out of Capture Orbs.'; nothing consumed, turn not used")
	check(BattleManager.submit_item(&"capture_orb").is_empty(), "BattleManager refuses the capture too")
	await press(&"ui_cancel")
	await win_battle_quickly()
	GameSession.inventory.reset_to_starting_items()
	BattleManager.reset_test_overrides()


func test_switching_in_battle() -> void:
	section("Phase 11 · Switching")
	var scene := battle_scene()
	var lead := PartyManager.get_creature(0)
	var reserve := PartyManager.get_creature(1)
	var fainted := make_creature(&"thornling", 3)
	fainted.current_hp = 0
	PartyManager.add_creature(fainted)
	lead.current_hp = lead.get_max_hp()
	reserve.current_hp = reserve.get_max_hp()
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter_species(&"rivulet", 3)
	await hold(&"move_right", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU) and BattleManager.battle.player == lead, "battle; lead creature active")
	await mouse_click(scene.get_node("%CreatureOption"))
	var rows := scene.get_creature_rows()
	check(rows[0].ends_with("Active") and rows[1] == "Pebblit Lv. 4 %d/%d" % [reserve.current_hp, reserve.get_max_hp()]
			and rows[2] == "Thornling Lv. 3 0/%d Fainted" % fainted.get_max_hp() and rows[3] == "Empty",
			"menu marks active / healthy / fainted / empty %s" % [rows])
	await shot("28_switch_menu")
	await press(&"ui_accept")
	check(scene.get_overlay_footer().ends_with("is already in battle!"), "active creature can't be chosen")
	await mouse_click(scene.get_node("%OverlayList").get_child(2))
	check(scene.get_overlay_footer() == "Thornling has no energy left to battle!" and PartyManager.get_active_index() == 0,
			"fainted creature can't be chosen")
	BattleManager.forced_ai_move = &"tackle"
	BattleManager.force_hit = true
	BattleManager.forced_random_factor = 1.0
	var reserve_hp := reserve.current_hp
	var log_start := scene.message_log.size()
	await mouse_click(scene.get_node("%OverlayList").get_child(1))
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "switch resolved")
	var turn_log := scene.message_log.slice(log_start)
	var come_back := turn_log.find("%s, come back!" % lead.get_display_name())
	check(come_back >= 0 and turn_log.find("Go, Pebblit!") == come_back + 1
			and turn_log.find("Wild Rivulet used Tackle!") > come_back + 1, "'come back!' -> 'Go, Pebblit!' -> the wild creature attacks")
	check(PartyManager.get_active_index() == 1 and BattleManager.battle.player == reserve and reserve.current_hp < reserve_hp
			and label_text(scene.get_node("%PlayerPanel"), "Name") == "Pebblit", "Pebblit is active and took the hit")

	section("Phase 11 · Active creature faints, battle goes on")
	reserve.current_hp = 1
	BattleManager.forced_turn_order = -1
	BattleManager.forced_damage = 999
	log_start = scene.message_log.size()
	await fight_with_first_move()
	check(await wait_for_ui(BattleScene.UiState.CREATURE_MENU), "replacement menu opens")
	check(BattleManager.state == BattleManager.State.SWITCH_REQUIRED and BattleManager.battle.awaiting_switch
			and BattleManager.battle.outcome.is_empty() and scene.message_log.slice(log_start).has("Pebblit fainted!"),
			"'Pebblit fainted!' is not a defeat: a replacement is required")
	await press(&"ui_cancel")
	check(scene.ui_state == BattleScene.UiState.CREATURE_MENU and not scene.is_overlay_cancellable()
			and scene.get_overlay_footer() == BattleMessages.SWITCH_REQUIRED, "Esc can't skip choosing a replacement")
	BattleManager.forced_damage = -1
	log_start = scene.message_log.size()
	await mouse_click(scene.get_node("%OverlayList").get_child(0))
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "replacement sent out")
	turn_log = scene.message_log.slice(log_start)
	check(turn_log == PackedStringArray(["Go, %s!" % lead.get_display_name()]) and PartyManager.get_active_index() == 0,
			"replacing a fainted creature is free: no wild turn")
	await win_battle_quickly()
	check(last_save_reason == &"battle_victory" and int(saved_save()["active_index"]) == 0 and saved_party(1)["current_hp"] == 0,
			"autosave has the active slot and the fainted HP")

	section("Phase 11 · Last creature faints: defeat")
	lead.current_hp = 1
	EncounterManager.force_next_encounter_species(&"rivulet", 3)
	await hold(&"move_left", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle with only 1 HP left in the party")
	BattleManager.forced_turn_order = -1
	BattleManager.forced_damage = 999
	BattleManager.force_hit = true
	log_start = scene.message_log.size()
	await fight_with_first_move()
	check(await wait_battle_over(), "battle over")
	turn_log = scene.message_log.slice(log_start)
	check(turn_log.has(BattleMessages.NO_USABLE_CREATURES) and last_save_reason == &"battle_defeat"
			and PartyManager.get_party().all(func(c: CreatureInstance) -> bool: return c.current_hp == 0)
			and saved_save()["party"].all(func(c: Dictionary) -> bool: return int(c["current_hp"]) == 0),
			"no healthy creature left: defeat, all at 0 HP in the save")
	BattleManager.reset_test_overrides()
	PartyManager.remove_creature(fainted)


func test_party_full_capture() -> void:
	section("Phase 11 · Capture with a full party")
	var scene := battle_scene()
	for creature in PartyManager.get_party():
		creature.current_hp = creature.get_max_hp()
	var fillers: Array[CreatureInstance] = []
	while PartyManager.has_space():
		var filler := make_creature(&"brambleox", 2)
		fillers.append(filler)
		PartyManager.add_creature(filler)
	GameSession.storage.clear()
	check(PartyManager.get_size() == 6, "party of 6")
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter_species(&"tideclaw", 5)
	await hold(&"move_right", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle vs wild Tideclaw")
	var wild := BattleManager.battle.wild
	wild.current_hp = 9
	BattleManager.forced_capture = 1
	var log_start := scene.message_log.size()
	await mouse_click(scene.get_node("%ItemOption"))
	await press(&"ui_accept")
	check(await wait_battle_over(), "caught")
	var turn_log := scene.message_log.slice(log_start)
	check(turn_log.has("Tideclaw was caught!") and turn_log.has("Your party is full.") and turn_log.has("Tideclaw was sent to storage."),
			"'caught!' -> 'Your party is full.' -> 'sent to storage.'")
	var stored := GameSession.storage.get_creature(0)
	check(PartyManager.get_size() == 6 and GameSession.storage.get_count() == 1 and stored.species_id == &"tideclaw"
			and stored.current_hp == 9 and stored.uid != wild.uid, "party stays at 6; Tideclaw (9 HP) is in storage")
	check(saved_save()["storage"].size() == 1 and saved_save()["storage"][0]["uid"] == stored.uid, "storage is in the autosave")
	SceneRouter.go_to("res://scenes/world/maps/player_house.tscn", &"entrance")
	await wait_for_map(&"player_house")
	await place(Vector2(176, 92), Vector2.UP)
	await rest_in_bed()
	await close_dialogue()
	check(stored.current_hp == stored.get_max_hp() and saved_save()["storage"][0]["current_hp"] == stored.get_max_hp(),
			"the bed heals stored creatures too")
	for filler in fillers:
		PartyManager.remove_creature(filler)
	GameSession.storage.clear()
	BattleManager.reset_test_overrides()
	check(GameSession.save_now(&"manual"), "back to the normal party")
	SceneRouter.go_to("res://scenes/world/maps/route_01.tscn", &"south_entrance")
	await wait_for_map(&"route_01")


# --- Phase 11: relaunch stages --------------------------------------------------------------

func new_game_from_title() -> void:
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_left")
	await press(&"ui_accept")
	await wait_for_state(GameSession.State.PLAYING)


func choose_flamkit() -> void:
	SceneRouter.go_to(LAB_MAP, &"entrance")
	await wait_for_map(&"research_lab")
	await hold(&"move_up", 1.0)
	await press(&"interact")
	await close_dialogue()
	await press(&"ui_accept")
	await press(&"ui_accept")
	await close_dialogue()


func test_capture_start() -> void:
	section("Relaunch chain: New Game -> starter -> capture")
	await new_game_from_title()
	check(PartyManager.get_size() == 0 and GameSession.inventory.get_items() == {&"capture_orb": 5}
			and GameSession.storage.get_count() == 0 and PartyManager.get_active_index() == 0,
			"new game: no creatures, 5 Capture Orbs, empty storage, active slot 0")
	await choose_flamkit()
	check(PartyManager.get_size() == 1 and GameSession.inventory.get_quantity(&"capture_orb") == 5
			and last_save_reason == &"starter_selected", "starter chosen; still 5 orbs; autosaved")
	SceneRouter.go_to("res://scenes/world/maps/route_01.tscn", &"south_entrance")
	await wait_for_map(&"route_01")
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter_species(&"pebblit", 4)
	await hold(&"move_right", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "wild Pebblit")
	BattleManager.battle.wild.current_hp = 6
	BattleManager.forced_capture = 1
	await mouse_click(battle_scene().get_node("%ItemOption"))
	await press(&"ui_accept")
	check(await wait_battle_over() and PartyManager.get_size() == 2 and last_save_reason == &"battle_caught", "caught; autosaved")
	BattleManager.reset_test_overrides()
	write_expectation()


func test_capture_continue() -> void:
	section("Relaunch chain: Continue -> verify capture -> switch -> fill party -> capture to storage")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	await frames(3)
	verify_expectation()
	var caught := PartyManager.get_creature(1)
	check(caught.species_id == &"pebblit" and caught.nickname == "Pebblit" and caught.level == 4 and caught.current_hp == 6
			and caught.experience == 0 and caught.status == &"" and Array(caught.move_ids) == [&"tackle", &"quick_jab"],
			"caught Pebblit restored exactly (slot 2, Lv. 4, 6 HP, moves, no status)")
	var scene := battle_scene()
	EncounterManager.force_next_encounter_species(&"mossaur", 2)
	await hold(&"move_right", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle")
	BattleManager.force_hit = true
	BattleManager.forced_damage = 1
	await mouse_click(scene.get_node("%CreatureOption"))
	await mouse_click(scene.get_node("%OverlayList").get_child(1))
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU) and BattleManager.battle.player == caught
			and caught.current_hp == 5, "switched to Pebblit (the switch cost the turn: it took 1 damage)")
	await win_battle_quickly()
	check(PartyManager.get_active_index() == 1 and caught.experience > 0, "Pebblit won the battle and stays active")
	while PartyManager.has_space():
		PartyManager.add_creature(make_creature(&"rivulet", 2))
	GameSession.save_now(&"manual")
	EncounterManager.force_next_encounter_species(&"cindrake", 4)
	await hold(&"move_left", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle with a full party")
	BattleManager.battle.wild.current_hp = 11
	BattleManager.forced_capture = 1
	await mouse_click(scene.get_node("%ItemOption"))
	await press(&"ui_accept")
	check(await wait_battle_over() and GameSession.storage.get_count() == 1 and PartyManager.get_size() == 6, "Cindrake went to storage")
	BattleManager.reset_test_overrides()
	write_expectation()


func test_capture_verify() -> void:
	section("Relaunch chain: final reload")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	await frames(3)
	verify_expectation()
	var stored := GameSession.storage.get_creature(0)
	check(PartyManager.get_size() == 6 and stored.species_id == &"cindrake" and stored.current_hp == 11 and stored.level == 4
			and GameSession.inventory.get_quantity(&"capture_orb") == 3 and PartyManager.get_active_index() == 1,
			"6 in the party, Cindrake (11 HP) in storage, 3 orbs, Pebblit still active")


func test_migrate_v1() -> void:
	section("Migration: version 1 save -> Continue -> save as version 3")
	check(title.is_option_enabled(TitleScreen.Option.CONTINUE), "a version 1 save offers Continue")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	await frames(3)
	check(world.current_map_path == V1_FIXTURE["world"]["map"] and player.global_position == Vector2(392, 560)
			and player.facing == Vector2.RIGHT, "map, position and facing unchanged")
	check(json(GameState.to_save_data()) == json(V1_FIXTURE["game_state"]), "story flags unchanged")
	check(json(PartyManager.to_save_data()) == json(V1_FIXTURE["party"]),
			"party unchanged: UIDs, levels, EXP, HP, moves, nicknames")
	check(GameSession.inventory.get_items() == {&"capture_orb": 5} and GameSession.storage.get_count() == 0
			and PartyManager.get_active_index() == 0, "gets 5 Capture Orbs, empty storage, active slot 0")
	check(GameSession.wallet.get_coins() == Wallet.STARTING_COINS, "gets the starting 500 Coins")
	check(GameSession.save_now(&"manual") and int(saved_save()["version"]) == 3, "saved again as version 3")
	write_expectation()


func test_migrate_verify() -> void:
	section("Migration: reload the version 3 save")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	await frames(3)
	verify_expectation()


## JSON round trip, so in-memory values (ints) compare equal to parsed save data (floats).
func json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func saved_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_PATH))


func write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# --- Phase 9: save safety across real relaunches --------------------------------------------

const EXPECT_PATH := "user://test_expectation.json"


## Everything a Continue must restore, as plain JSON-able data.
func snapshot() -> Dictionary:
	return JSON.parse_string(JSON.stringify({
		"map": world.current_map_path,
		"position": [player.global_position.x, player.global_position.y],
		"facing": [player.facing.x, player.facing.y],
		"flags": GameState.to_save_data(),
		"party": PartyManager.to_save_data(),
		"active_index": PartyManager.get_active_index(),
		"inventory": GameSession.inventory.to_save_data(),
		"storage": GameSession.storage.to_save_data(),
		"currency": GameSession.wallet.get_coins(),
	}))


func write_expectation() -> void:
	check(not GameSession.has_pending_save() and SaveManager.is_save_valid(), "autosave written before quitting")
	var file := FileAccess.open(EXPECT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot()))
	file.close()


func verify_expectation() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPECT_PATH))
	var actual := snapshot()
	var partner: Dictionary = actual["party"][0]
	var was: Dictionary = expected["party"][0]
	check(partner["uid"] == was["uid"] and partner["species_id"] == was["species_id"], "same creature (%s)" % partner["species_id"])
	check(partner["level"] == was["level"] and partner["experience"] == was["experience"],
			"same level %d and EXP %d" % [partner["level"], partner["experience"]])
	check(partner["current_hp"] == was["current_hp"], "same HP %d" % partner["current_hp"])
	check(actual["map"] == expected["map"] and actual["position"] == expected["position"] and actual["facing"] == expected["facing"],
			"same map and position (%s)" % String(actual["map"]).get_file())
	check(actual["flags"] == expected["flags"] and actual["party"] == expected["party"], "same story state and full party data")
	check(actual["active_index"] == expected["active_index"] and actual["inventory"] == expected["inventory"]
			and actual["storage"] == expected["storage"] and actual["currency"] == expected["currency"],
			"same active creature, items %s, storage (%d) and Coins (%d)"
					% [actual["inventory"], actual["storage"].size(), actual["currency"]])


func test_safety_start() -> void:
	section("Save safety: New Game -> Flamkit -> save -> win -> level up")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_left")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "new game started over the old save")
	SceneRouter.go_to(LAB_MAP, &"entrance")
	await wait_for_map(&"research_lab")
	await hold(&"move_up", 1.0)
	await press(&"interact")
	await close_dialogue()
	await press(&"ui_accept")
	await press(&"ui_accept")
	await close_dialogue()
	var partner := PartyManager.get_creature(0)
	check(partner != null and partner.species_id == &"flamkit" and last_save_reason == &"starter_selected",
			"chose Flamkit (autosaved)")
	var pause := main.get_node("PauseMenu") as PauseMenu
	await pause_and_save()
	check(last_save_reason == &"manual", "saved from the pause menu")
	await press(&"ui_cancel")
	check(not pause.is_open(), "resumed")
	SceneRouter.go_to("res://scenes/world/maps/route_01.tscn", &"south_entrance")
	await wait_for_map(&"route_01")
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter_species(&"tideclaw", 4)
	await hold(&"move_right", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU) and BattleManager.battle.wild.species_id == &"tideclaw",
			"battle against a new species (Tideclaw)")
	partner.experience = CreatureProgression.exp_to_next_level(partner.level) - 1
	BattleManager.forced_turn_order = 1
	BattleManager.force_hit = true
	BattleManager.forced_damage = 999
	await press(&"interact")
	await press(&"interact")
	check(await wait_battle_over(), "won")
	check(partner.level == 6 and last_save_reason == &"battle_victory", "levelled up to 6; autosaved")
	BattleManager.reset_test_overrides()
	write_expectation()


func test_safety(scenario: String) -> void:
	section("Save safety: relaunch + Continue, then '%s'" % scenario)
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	await frames(3)
	verify_expectation()
	var partner := PartyManager.get_creature(0)
	match scenario:
		"run":
			EncounterManager.force_next_encounter()
			await hold(&"move_right", 0.25)
			check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle")
			var exp_before := partner.experience
			BattleManager.forced_escape = 1
			await press(&"ui_down")
			await press(&"ui_right")
			await press(&"ui_accept")
			check(await wait_battle_over() and last_save_reason == &"battle_escaped" and partner.experience == exp_before,
					"ran away (no EXP); autosaved")
		"lose":
			EncounterManager.force_next_encounter()
			await hold(&"move_right", 0.25)
			check(await wait_for_ui(BattleScene.UiState.ACTION_MENU), "battle")
			BattleManager.forced_turn_order = -1
			BattleManager.force_hit = true
			BattleManager.forced_damage = 999
			await press(&"interact")
			await press(&"interact")
			check(await wait_battle_over() and partner.current_hp == 0 and last_save_reason == &"battle_defeat",
					"lost (0 HP); autosaved")
		"manual":
			await hold(&"move_right", 0.3)
			await hold(&"move_down", 0.2)
			await pause_and_save()
			await press(&"ui_cancel")
			check(last_save_reason == &"manual", "walked, then saved from the pause menu")
		"heal":
			SceneRouter.go_to("res://scenes/world/maps/player_house.tscn", &"entrance")
			await wait_for_map(&"player_house")
			await place(Vector2(176, 92), Vector2.UP)
			await rest_in_bed()
			await close_dialogue()
			check(partner.current_hp == partner.get_max_hp() and last_save_reason == &"rested", "rested (full HP); autosaved")
	BattleManager.reset_test_overrides()
	if scenario != "verify":
		write_expectation()


# --- Phase 12: creature management, economy, Route 01 polish ---------------------------------

## Phase 12 version 2 fixture: Phase 11 format (inventory, storage, active index; no currency).
func v2_fixture() -> Dictionary:
	var data: Dictionary = V1_FIXTURE.duplicate(true)
	data["version"] = 2
	data["party"][1]["current_hp"] = 12
	data["inventory"] = {"capture_orb": 3}
	data["storage"] = [{"uid": "v2-fixture-pebblit", "species_id": "pebblit", "nickname": "Pebbles", "level": 4,
			"experience": 9, "current_hp": 6, "moves": ["tackle"], "status": ""}]
	data["active_index"] = 1
	return data


## Party, lead, storage, items and Coins as plain data, so a test can put them back afterwards.
func stash_roster() -> Dictionary:
	return {"party": PartyManager.to_save_data(), "active": PartyManager.get_active_index(),
			"storage": GameSession.storage.to_save_data(), "items": GameSession.inventory.to_save_data(),
			"coins": GameSession.wallet.get_coins()}


func restore_roster(stash: Dictionary) -> void:
	PartyManager.load_save_data(stash["party"], stash["active"])
	GameSession.storage.load_save_data(stash["storage"])
	GameSession.inventory.load_save_data(stash["items"])
	GameSession.wallet.load_save_data(stash["coins"])


## Replaces the party (and storage) with the given creatures; `lead` is the active slot.
func set_roster(party: Array, lead := 0, stored: Array = []) -> void:
	PartyManager.clear()
	for creature: CreatureInstance in party:
		PartyManager.add_creature(creature)
	if lead != 0:
		PartyManager.switch_active(lead)
	GameSession.storage.clear()
	for creature: CreatureInstance in stored:
		GameSession.storage.add_creature(creature)


func party_names() -> Array:
	return PartyManager.get_party().map(func(c: CreatureInstance) -> String: return c.get_display_name())


func storage_names() -> Array:
	return GameSession.storage.get_all().map(func(c: CreatureInstance) -> String: return c.get_display_name())


## Types into whatever has keyboard focus, as real key presses carrying text.
func type_text(text: String) -> void:
	for i in text.length():
		for pressed in [true, false]:
			var event := InputEventKey.new()
			event.unicode = text.unicode_at(i)
			event.pressed = pressed
			Input.parse_input_event(event)
			await delivered()


## The opaque part of a character sprite (player or NPC) standing with its feet at `feet`.
func sprite_box(feet: Vector2) -> Rect2:
	return Rect2(feet + Vector2(-5, -19), Vector2(10, 22))


func sprites_overlap(a: Vector2, b: Vector2) -> bool:
	var both := sprite_box(a).intersection(sprite_box(b))
	return both.size.x > 0.5 and both.size.y > 0.5


func expected_row(creature: CreatureInstance, lead: bool) -> String:
	var species := creature.get_species()
	return "%s %s Lv %d %d/%d %s %s%s" % [creature.get_display_name(), species.display_name, creature.level,
			creature.current_hp, creature.get_max_hp(), species.element.display_name, CreatureRow.status_text(creature),
			" LEAD" if lead else ""]


func test_wallet_and_shop_rules() -> void:
	section("Phase 12 · Coins + shop rules")
	var wallet := Wallet.new()
	wallet.reset_to_starting_amount()
	check(wallet.get_coins() == 500 and Wallet.STARTING_COINS == 500 and Wallet.format(500) == "500 Coins",
			"starting amount is 500 Coins")
	check(not wallet.spend(600) and wallet.get_coins() == 500, "can't spend more than you have")
	check(not wallet.add(-5) and not wallet.spend(-5) and wallet.get_coins() == 500, "negative amounts are refused")
	var bad_amounts := [-1, 12.5, "500", null, [], {}]
	check(Wallet.validate_save_data(0).is_empty() and Wallet.validate_save_data(500.0).is_empty()
			and bad_amounts.all(func(v: Variant) -> bool: return not Wallet.validate_save_data(v).is_empty()),
			"a saved amount must be a whole number >= 0")
	check(ItemCatalog.get_item(&"capture_orb").price == 100 and Shop.get_price(&"capture_orb") == 100,
			"a Capture Orb costs 100 Coins (ItemData.price)")
	var inventory := Inventory.new()
	inventory.reset_to_starting_items()
	check(Shop.purchase(&"capture_orb", 1, wallet, inventory).is_empty() and wallet.get_coins() == 400
			and inventory.get_quantity(&"capture_orb") == 6, "buy one: 500 -> 400 Coins, 5 -> 6 orbs")
	check(Shop.purchase(&"capture_orb", 3, wallet, inventory).is_empty() and wallet.get_coins() == 100
			and inventory.get_quantity(&"capture_orb") == 9, "buy three at once: 100 Coins, 9 orbs")
	check(Shop.max_affordable(&"capture_orb", wallet) == 1, "exactly one more is affordable")
	check(Shop.purchase(&"capture_orb", 2, wallet, inventory) == Shop.NOT_ENOUGH_COINS and wallet.get_coins() == 100
			and inventory.get_quantity(&"capture_orb") == 9, "two more: 'Not enough Coins.', nothing changes")
	check(Shop.purchase(&"capture_orb", 1, wallet, inventory).is_empty() and wallet.get_coins() == 0
			and inventory.get_quantity(&"capture_orb") == 10, "spend the last 100: 0 Coins, 10 orbs")
	check(Shop.purchase(&"capture_orb", 1, wallet, inventory) == Shop.NOT_ENOUGH_COINS and wallet.get_coins() == 0
			and inventory.get_quantity(&"capture_orb") == 10, "with 0 Coins: 'Not enough Coins.', nothing changes")
	wallet.add(1000)
	check(Shop.purchase(&"no_such_item", 1, wallet, inventory) == Shop.NOT_FOR_SALE
			and Shop.purchase(&"capture_orb", 0, wallet, inventory) == Shop.INVALID_QUANTITY
			and wallet.get_coins() == 1000 and inventory.get_quantity(&"capture_orb") == 10,
			"unknown items and a quantity of 0 are refused")


func test_save_v3_unit() -> void:
	section("Phase 12 · Save version 3 + migrations")
	var real_path := SaveManager.save_path
	SaveManager.save_path = FIXTURE_PATH
	write_file(FIXTURE_PATH, JSON.stringify(V1_FIXTURE))
	var result := SaveManager.read_save()
	var data: Dictionary = result["data"]
	check(result["error"].is_empty() and int(data["version"]) == 3 and int(data["currency"]) == 500
			and json(data["inventory"]) == json({"capture_orb": 5}) and data["storage"].is_empty()
			and int(data["active_index"]) == 0, "v1 -> v3: 5 orbs, empty storage, active slot 0, 500 Coins")
	check(json(data["party"]) == json(V1_FIXTURE["party"]) and json(data["world"]) == json(V1_FIXTURE["world"])
			and json(data["game_state"]) == json(V1_FIXTURE["game_state"]), "v1 -> v3: party, world and flags untouched")
	var v2 := v2_fixture()
	write_file(FIXTURE_PATH, JSON.stringify(v2))
	result = SaveManager.read_save()
	data = result["data"]
	check(result["error"].is_empty() and int(data["version"]) == 3 and int(data["currency"]) == 500, "v2 -> v3: 500 Coins added")
	check(json(data["inventory"]) == json(v2["inventory"]) and json(data["storage"]) == json(v2["storage"])
			and int(data["active_index"]) == 1, "v2 -> v3: inventory, storage and active index unchanged")
	check(json(data["party"]) == json(v2["party"]) and json(data["world"]) == json(v2["world"])
			and json(data["game_state"]) == json(v2["game_state"]), "v2 -> v3: party, world and flags unchanged")
	check(FileAccess.get_file_as_string(FIXTURE_PATH) == JSON.stringify(v2), "migrating in memory never rewrites the file")

	var stash := stash_roster()
	GameSession.wallet.load_save_data(321)
	GameSession.storage.add_creature(make_creature(&"thornling", 3))
	check(SaveManager.save_game(), "a version 3 save is written")
	var saved: Dictionary = SaveManager.read_save()["data"]
	check(int(saved["version"]) == 3 and int(saved["currency"]) == 321
			and json(saved["party"]) == json(PartyManager.to_save_data())
			and json(saved["storage"]) == json(GameSession.storage.to_save_data())
			and json(saved["inventory"]) == json(GameSession.inventory.to_save_data())
			and int(saved["active_index"]) == PartyManager.get_active_index(),
			"v3 round trip: party, storage, items, Coins and active slot read back exactly")
	restore_roster(stash)

	var good: Dictionary = json(saved)
	var creature: Dictionary = good["party"][0]
	var bad := {
		"no currency": {"currency": null}, "currency as text": {"currency": "500"},
		"negative currency": {"currency": -5}, "fractional currency": {"currency": 12.5},
		"a text item quantity": {"inventory": {"capture_orb": "lots"}},
		"a party that isn't a list": {"party": "Flamkit"}, "a party entry that isn't a creature": {"party": [5]},
		"a creature level that isn't a number": {"party": [creature.merged({"level": "five"}, true)]},
		"a creature with no species": {"party": [creature.merged({"species_id": ""}, true)]},
		"seven party creatures": {"party": [creature, creature, creature, creature, creature, creature, creature]},
		"a damaged stored creature": {"storage": [creature.merged({"moves": "tackle"}, true)]},
		"storage that isn't a list": {"storage": {"a": creature}},
	}
	for label: String in bad:
		var broken: Dictionary = good.duplicate(true)
		var change: Dictionary = bad[label]
		for key: String in change:
			if change[key] == null:
				broken.erase(key)
			else:
				broken[key] = change[key]
		write_file(FIXTURE_PATH, JSON.stringify(broken))
		check(SaveManager.read_save()["error"] == SaveManager.ERROR_DAMAGED and not SaveManager.validate_save_data(broken).is_empty(),
				"v3 save with %s is rejected" % label)

	var before: Variant = json(stash_roster())
	var flags_before := GameState.to_save_data()
	var map_before := world.current_map_path
	var position_before := player.global_position
	var mixed: Dictionary = good.duplicate(true)
	mixed["party"] = [creature.merged({"nickname": "Changed"}, true)]
	mixed["inventory"] = {"capture_orb": 99}
	mixed["currency"] = -1
	mixed["game_state"] = {"starter_selected": false}
	write_file(FIXTURE_PATH, JSON.stringify(mixed))
	check(not SaveManager.load_game() and json(stash_roster()) == before and GameState.to_save_data() == flags_before
			and world.current_map_path == map_before and player.global_position == position_before,
			"a rejected save is never partly applied: party, storage, items, Coins, flags and position unchanged")
	DirAccess.remove_absolute(FIXTURE_PATH)
	SaveManager.save_path = real_path


func test_party_rules_phase12() -> void:
	section("Phase 12 · Party order, lead and storage rules")
	var stash := stash_roster()
	var flam := make_creature(&"flamkit", 5)
	var peb := make_creature(&"pebblit", 4)
	var moss := make_creature(&"mossaur", 3)
	set_roster([flam, peb, moss])
	check(CreatureManagement.move(1, 0).is_empty() and party_names() == ["Pebblit", "Flamkit", "Mossaur"]
			and PartyManager.get_active_creature() == flam and PartyManager.get_active_index() == 1
			and last_save_reason == &"party_reordered", "Pebblit to slot 1: Flamkit is still the lead, now at index 1; saved")
	set_roster([flam, peb, moss])
	check(CreatureManagement.move(0, 1).is_empty() and party_names() == ["Pebblit", "Flamkit", "Mossaur"]
			and PartyManager.get_active_index() == 1, "the lead itself moved to slot 2: active index follows it (1)")
	check(CreatureManagement.move(2, 0).is_empty() and party_names() == ["Mossaur", "Pebblit", "Flamkit"]
			and PartyManager.get_active_creature() == flam and PartyManager.get_active_index() == 2,
			"moving another creature across the lead keeps the lead (index 2)")
	check(CreatureManagement.move(0, 5) == CreatureManagement.SLOT_EMPTY and not PartyManager.move_creature(0, 5)
			and party_names() == ["Mossaur", "Pebblit", "Flamkit"], "moving into an empty slot is refused")

	set_roster([flam, peb, moss])
	moss.current_hp = 0
	check(CreatureManagement.set_lead(2) == "Mossaur has fainted and can't lead." and PartyManager.get_active_index() == 0,
			"a fainted creature can't lead")
	check(CreatureManagement.set_lead(4) == CreatureManagement.SLOT_EMPTY, "an empty slot can't lead")
	check(CreatureManagement.set_lead(0) == "Flamkit is already leading your team.", "the lead is already the lead")
	check(CreatureManagement.set_lead(1).is_empty() and PartyManager.get_active_creature() == peb
			and last_save_reason == &"lead_changed" and int(saved_save()["active_index"]) == 1, "Pebblit leads now; saved")

	set_roster([flam, peb, moss])
	moss.current_hp = 0
	flam.nickname = "Sparky"
	flam.experience = 7
	flam.current_hp = 10
	var flam_data := flam.to_save_data()
	check(CreatureManagement.deposit(flam).is_empty() and party_names() == ["Pebblit", "Mossaur"]
			and storage_names() == ["Sparky"] and last_save_reason == &"creature_deposited",
			"the lead goes to storage; saved")
	check(PartyManager.get_active_creature() == peb, "the first creature that can fight (Pebblit) takes the lead")
	check(json(flam.to_save_data()) == json(flam_data), "stored unchanged: UID, HP, EXP, level, nickname, moves, status")
	check(CreatureManagement.deposit(peb) == "Pebblit is the only creature in your party that can fight."
			and party_names() == ["Pebblit", "Mossaur"], "the last creature that can fight stays")
	check(CreatureManagement.deposit(moss).is_empty() and party_names() == ["Pebblit"] and storage_names() == ["Sparky", "Mossaur"],
			"a fainted creature can be stored")
	check(CreatureManagement.deposit(peb) == CreatureManagement.LAST_CREATURE and PartyManager.get_size() == 1,
			"the party can't become empty")
	check(CreatureManagement.withdraw(flam).is_empty() and party_names() == ["Pebblit", "Sparky"]
			and storage_names() == ["Mossaur"] and last_save_reason == &"creature_withdrawn"
			and json(flam.to_save_data()) == json(flam_data), "withdrawn into the last slot, unchanged; saved")
	while PartyManager.has_space():
		PartyManager.add_creature(make_creature(&"brambleox", 2))
	check(CreatureManagement.withdraw(moss) == CreatureManagement.PARTY_FULL and storage_names() == ["Mossaur"],
			"withdrawing into a full party is refused")
	var stranger := make_creature(&"rivulet", 3)
	check(CreatureManagement.deposit(stranger) == CreatureManagement.NOT_OWNED
			and CreatureManagement.withdraw(stranger) == CreatureManagement.NOT_OWNED, "creatures you don't own are refused")
	check(PartyManager.get_active_index() >= 0 and PartyManager.get_active_index() < PartyManager.get_size(),
			"the active index is always a valid slot")
	restore_roster(stash)


func test_nickname_rules() -> void:
	section("Phase 12 · Nicknames")
	var stash := stash_roster()
	var problem := func(name: String) -> String: return CreatureInstance.get_nickname_problem(name)
	check(problem.call("") == CreatureInstance.NICKNAME_EMPTY and problem.call("   ") == CreatureInstance.NICKNAME_EMPTY,
			"empty or blank names are rejected")
	check(problem.call("A").is_empty(), "a 1-character name is fine")
	check(problem.call("ABCDEFGHIJKLMNOP").is_empty() and problem.call("ABCDEFGHIJKLMNOPQ") == CreatureInstance.NICKNAME_TOO_LONG,
			"16 characters are fine, 17 are rejected")
	check(CreatureInstance.clean_nickname("  Ember  ") == "Ember" and problem.call("   ABCDEFGHIJKLMNOP   ").is_empty(),
			"surrounding whitespace is trimmed and not counted")
	check(problem.call("Bad\nName") == CreatureInstance.NICKNAME_INVALID, "control characters are rejected")
	check(problem.call("Flämmchen").is_empty() and problem.call("火の子").is_empty()
			and problem.call("ねこねこねこねこねこねこねこねこ").is_empty()
			and problem.call("ねこねこねこねこねこねこねこねこね") == CreatureInstance.NICKNAME_TOO_LONG,
			"Unicode names are fine; length counts characters")
	var wild := make_creature(&"pebblit", 3)
	check(CreatureFactory.create_from_wild(wild).nickname == "Pebblit", "a caught creature's nickname starts as its species name")

	var flam := make_creature(&"flamkit", 5)
	var stored := make_creature(&"tideclaw", 4)
	set_roster([flam], 0, [stored])
	check(CreatureManagement.rename(flam, "  Ember ").is_empty() and flam.nickname == "Ember" and flam.species_id == &"flamkit"
			and last_save_reason == &"nickname_changed", "renamed to 'Ember' (trimmed); species unchanged; saved")
	check(CreatureManagement.rename(flam, "") == CreatureInstance.NICKNAME_EMPTY
			and CreatureManagement.rename(flam, "ABCDEFGHIJKLMNOPQ") == CreatureInstance.NICKNAME_TOO_LONG
			and flam.nickname == "Ember", "invalid names leave the old nickname")
	check(CreatureManagement.rename(stored, "Pinchy").is_empty() and stored.nickname == "Pinchy", "stored creatures can be renamed")
	check(CreatureManagement.rename(make_creature(&"rivulet", 2), "Nope") == CreatureManagement.NOT_OWNED,
			"only your own creatures can be renamed")
	CreatureManagement.rename(flam, "火の子✨")
	var reloaded := CreatureInstance.from_save_data(JSON.parse_string(JSON.stringify(flam.to_save_data())))
	check(reloaded.nickname == "火の子✨" and reloaded.species_id == &"flamkit" and saved_party(0)["nickname"] == "火の子✨",
			"a Unicode nickname survives save and load")
	restore_roster(stash)


func test_party_screen() -> void:
	section("Phase 12 · Party screen (pause -> Creatures)")
	var stash := stash_roster()
	var pause := main.get_node("PauseMenu") as PauseMenu
	var screen := pause.get_party_screen()
	var flam := make_creature(&"flamkit", 5)
	var peb := make_creature(&"pebblit", 4)
	var moss := make_creature(&"mossaur", 3)
	moss.current_hp = 0
	set_roster([flam, peb, moss])
	var spot := player.global_position
	await press(&"ui_cancel")
	await press(&"ui_down")
	check(pause.get_selected_option() == PauseMenu.Option.CREATURES, "CREATURES is the second pause option")
	await press(&"ui_accept")
	check(screen.is_open() and pause.is_open() and GameSession.is_paused(), "Creatures opens the party screen")
	var list := screen.get_list()
	check(list.get_row_count() == 6, "all six slots are shown")
	check(list.get_row_text(0) == expected_row(flam, true) and list.get_row_text(1) == expected_row(peb, false)
			and list.get_row_text(2) == expected_row(moss, false),
			"each row: nickname, species, level, HP, element, status, LEAD (%s)" % list.get_row_text(0))
	check(list.get_row_text(2).ends_with("Fainted") and list.get_row_text(3) == "Empty" and list.get_row_text(5) == "Empty",
			"fainted creatures and empty slots are marked")
	await shot("29_party_screen")
	await hold(&"move_down", 0.3)
	check(player.global_position == spot, "no movement under the party screen")

	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_mode() == PartyScreen.Mode.ACTIONS and screen.get_actions().get_row_text(1) == "SET AS LEAD",
			"a creature's options: SUMMARY, SET AS LEAD, MOVE, CANCEL")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_message() == "Pebblit will now lead your team." and PartyManager.get_active_creature() == peb
			and list.get_row_text(1).ends_with("LEAD") and last_save_reason == &"lead_changed", "SET AS LEAD changes the lead; saved")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_message() == "Mossaur has fainted and can't lead." and PartyManager.get_active_creature() == peb,
			"a fainted creature can't lead")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_message() == CreatureManagement.SLOT_EMPTY and screen.get_mode() == PartyScreen.Mode.LIST,
			"an empty slot has no options")

	await press(&"ui_up")
	await press(&"ui_up")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_mode() == PartyScreen.Mode.MOVING and screen.get_message() == "Move Pebblit to which slot?", "MOVE asks for a slot")
	await press(&"ui_up")
	await press(&"ui_accept")
	check(party_names() == ["Pebblit", "Flamkit", "Mossaur"] and PartyManager.get_active_creature() == peb
			and PartyManager.get_active_index() == 0 and screen.get_message() == "Pebblit was moved.", "Pebblit moved to slot 1, still the lead")
	check(last_save_reason == &"party_reordered" and saved_party(0)["uid"] == peb.uid and int(saved_save()["active_index"]) == 0,
			"the new order and lead are saved")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_cancel")
	check(screen.get_mode() == PartyScreen.Mode.LIST and party_names() == ["Pebblit", "Flamkit", "Mossaur"], "Esc cancels a move")

	await mouse_click(list.get_row(1))
	check(screen.get_mode() == PartyScreen.Mode.ACTIONS, "clicking a creature opens its options")
	await mouse_click(screen.get_actions().get_row(1))
	check(PartyManager.get_active_creature() == flam and PartyManager.get_active_index() == 1, "mouse: SET AS LEAD")

	# The pointer now rests over the list (hover selects), so pick Flamkit with it again.
	await mouse_click(list.get_row(1))
	await press(&"ui_accept")
	var details := screen.get_details()
	var text := details.get_text()
	check(details.is_open() and details.get_creature() == flam, "SUMMARY opens the creature's details")
	check(text.contains("Flamkit") and text.contains("Ember") and text.contains(flam.get_species().role)
			and text.contains("Level 5") and text.contains("HP %d / %d" % [flam.current_hp, flam.get_max_hp()])
			and text.contains("EXP %d / %d" % [flam.experience, CreatureProgression.exp_to_next_level(5)])
			and text.contains("Status: Healthy") and text.contains("Tackle") and text.contains("Ember  (Ember, power"),
			"details: nickname, species, element, role, level, HP, EXP, status, moves")
	check(not text.contains(flam.uid) and not text.contains("flamkit"), "no UID or internal ids shown")
	await shot("30_creature_details")

	await press(&"ui_accept")
	var dialog := details.get_nickname_dialog()
	check(dialog.is_open() and get_viewport().gui_get_focus_owner() == dialog.get_field() and dialog.get_field().text == "Flamkit",
			"RENAME opens 'Enter nickname:' with the text field focused")
	await type_text("Blaze")
	await shot("31_rename")
	await press_key(KEY_ENTER)
	check(not dialog.is_open() and flam.nickname == "Blaze" and flam.species_id == &"flamkit"
			and details.get_message() == "Nickname changed to \"Blaze\"." and last_save_reason == &"nickname_changed",
			"typed 'Blaze' + Enter: 'Nickname changed to \"Blaze\".'; saved")
	check(saved_party(1)["nickname"] == "Blaze" and saved_party(1)["species_id"] == "flamkit", "the save has the nickname, same species")
	await press(&"ui_accept")
	dialog.get_field().text = ""
	await press_key(KEY_ENTER)
	check(dialog.is_open() and dialog.get_error() == CreatureInstance.NICKNAME_EMPTY and flam.nickname == "Blaze",
			"an empty name shows a message and changes nothing")
	await type_text("ABCDEFGHIJKLMNOPQ")
	await press_key(KEY_ENTER)
	check(dialog.is_open() and dialog.get_error() == CreatureInstance.NICKNAME_TOO_LONG and flam.nickname == "Blaze",
			"a 17-character name shows a message and changes nothing ('%s': %s)" % [dialog.get_field().text, dialog.get_error()])
	await press(&"ui_cancel")
	check(not dialog.is_open() and details.is_open() and flam.nickname == "Blaze", "Esc cancels renaming")
	await mouse_click(details.get_options().get_row(0))
	dialog.get_field().text = "  Ëmber✨  "
	await mouse_click(dialog.get_ok_button())
	check(flam.nickname == "Ëmber✨", "mouse: OK renames (trimmed, Unicode kept)")
	await mouse_click(details.get_options().get_row(0))
	await mouse_click(dialog.get_cancel_button())
	check(not dialog.is_open() and flam.nickname == "Ëmber✨", "mouse: CANCEL closes without renaming")
	check(player.global_position == spot, "typing W/A/S/D into the name never moved the player")

	await press(&"ui_cancel")
	check(not details.is_open() and screen.is_open() and list.get_row_text(1).begins_with("Ëmber✨"), "Esc closes the details")
	await press(&"ui_cancel")
	check(not screen.is_open() and pause.is_open() and pause.get_selected_option() == PauseMenu.Option.CREATURES,
			"Esc closes the party screen, back to the pause menu")
	await press(&"ui_cancel")
	check(not pause.is_open() and player.controls_enabled, "Esc resumes")

	var mira_dialogue := load("res://data/dialogue/villager_mira.tres") as DialogueData
	DialogueManager.start(mira_dialogue)
	await press(&"ui_cancel")
	check(not pause.is_open() and not screen.is_open(), "no Creatures menu during dialogue")
	await close_dialogue()
	player.add_control_lock(StarterSelectionEvent.PLAYER_LOCK)
	await press(&"ui_cancel")
	check(not pause.is_open() and not screen.is_open(), "no Creatures menu during starter selection")
	player.remove_control_lock(StarterSelectionEvent.PLAYER_LOCK)

	section("Phase 12 · The lead fights; battles show nicknames")
	if world.current_map.map_id != &"route_01":
		SceneRouter.go_to("res://scenes/world/maps/route_01.tscn", &"south_entrance")
		await wait_for_map(&"route_01")
	var scene := battle_scene()
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter_species(&"rivulet", 3)
	await hold(&"move_right", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU) and BattleManager.battle.player == flam,
			"the lead (slot 2) fights, not slot 1")
	check((scene.get_node("%PlayerPanel").get_node("%Name") as Label).text == "Ëmber✨"
			and scene.message_log.has("Go, Ëmber✨!"), "the battle shows the nickname")
	BattleManager.forced_escape = 1
	await mouse_click(scene.get_node("%RunOption"))
	check(await wait_battle_over(), "ran away")
	flam.current_hp = 0
	EncounterManager.force_next_encounter_species(&"rivulet", 3)
	await hold(&"move_left", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU) and BattleManager.battle.player == peb,
			"a fainted lead: the first creature that can fight goes instead")
	await mouse_click(scene.get_node("%RunOption"))
	check(await wait_battle_over(), "ran away")
	peb.current_hp = 0
	var started := encounters_started
	EncounterManager.force_next_encounter()
	await hold(&"move_right", 0.3)
	check(encounters_started == started and not BattleManager.is_active(), "nobody can fight: no encounter")
	BattleManager.reset_test_overrides()
	restore_roster(stash)


func test_storage_terminal() -> void:
	section("Phase 12 · Storage terminal")
	var stash := stash_roster()
	SceneRouter.go_to(LAB_MAP, &"entrance")
	check(await wait_for_map(&"research_lab"), "in the lab")
	var terminal := world.current_map.get_node("Objects/StorageTerminal") as StorageTerminal
	var peb := make_creature(&"pebblit", 4)
	var flam := make_creature(&"flamkit", 5)
	var moss := make_creature(&"mossaur", 3)
	flam.nickname = "Blaze"
	moss.current_hp = 0
	set_roster([peb, flam, moss])
	await place(terminal.global_position + Vector2(0, 12), Vector2.UP)
	check(interaction.target == terminal.get_node("Interactable"), "facing the terminal targets it")
	await press(&"interact")
	var prompt := terminal.get_prompt()
	check(prompt != null and prompt.get_dialog().get_node("%DialogTitle").text == "Access Creature Storage?"
			and prompt.get_dialog().get_selected_index() == 0, "E asks 'Access Creature Storage?'")
	check(not player.controls_enabled and not GameSession.can_pause(), "player locked, no pause while it asks")
	await press(&"ui_cancel")
	check(terminal.get_prompt() == null and terminal.get_screen() == null and player.controls_enabled, "Esc = NO: nothing opens")
	await press(&"interact")
	await press(&"ui_accept")
	var screen := terminal.get_screen()
	var list := screen.get_list() if screen else null
	check(screen != null and screen.get_tab() == StorageScreen.Tab.PARTY and list.get_row_count() == 6
			and list.get_row_text(0) == expected_row(peb, true) and list.get_row_text(1) == expected_row(flam, false),
			"YES opens storage on the PARTY tab with full creature rows")
	await press(&"ui_right")
	check(screen.get_tab() == StorageScreen.Tab.STORAGE and list.get_row_count() == 0
			and list.get_placeholder_text() == "No creatures in storage.", "empty storage says 'No creatures in storage.'")
	await shot("32_storage_empty")
	var spot := player.global_position
	await hold(&"move_down", 0.3)
	await press(&"interact")
	check(player.global_position == spot and not DialogueManager.is_active() and not GameSession.can_pause(),
			"no movement, interaction or pause under the storage screen")
	await press(&"ui_left")

	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_actions().get_row_text(1) == "DEPOSIT", "a party creature: SUMMARY / DEPOSIT / CANCEL")
	var flam_data: Variant = json(flam.to_save_data())
	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_message() == "Blaze was sent to storage." and party_names() == ["Pebblit", "Mossaur"]
			and storage_names() == ["Blaze"], "DEPOSIT moves Blaze to storage")
	check(json(flam.to_save_data()) == flam_data, "unchanged in storage: UID, HP, EXP, level, nickname, moves, status")
	check(last_save_reason == &"creature_deposited" and saved_save()["storage"].size() == 1
			and saved_save()["storage"][0]["uid"] == flam.uid and saved_save()["party"].size() == 2, "saved")
	await press(&"ui_up")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_message() == "Pebblit is the only creature in your party that can fight." and PartyManager.get_size() == 2,
			"the last creature that can fight can't be stored")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(party_names() == ["Pebblit"] and storage_names() == ["Blaze", "Mossaur"], "fainted Mossaur stored")
	await press(&"ui_up")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_message() == CreatureManagement.LAST_CREATURE and party_names() == ["Pebblit"], "the party can't become empty")

	await mouse_click(screen.get_tab_control(StorageScreen.Tab.STORAGE))
	check(screen.get_tab() == StorageScreen.Tab.STORAGE and list.get_row_count() == 2
			and list.get_row_text(0) == expected_row(flam, false), "mouse: STORAGE tab lists stored creatures")
	await shot("33_storage_list")
	await press(&"ui_accept")
	check(screen.get_actions().get_row_text(1) == "WITHDRAW", "a stored creature: SUMMARY / WITHDRAW / CANCEL")
	await press(&"ui_accept")
	check(screen.get_details().is_open() and screen.get_details().get_creature() == flam, "SUMMARY of a stored creature")
	await press(&"ui_cancel")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_message() == "Blaze joined your party." and party_names() == ["Pebblit", "Blaze"]
			and storage_names() == ["Mossaur"] and json(flam.to_save_data()) == flam_data
			and last_save_reason == &"creature_withdrawn" and saved_save()["party"].size() == 2, "WITHDRAW: back in the party, unchanged; saved")

	await press(&"ui_left")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(party_names() == ["Blaze"] and PartyManager.get_active_creature() == flam and PartyManager.get_active_index() == 0,
			"storing the lead: the other healthy creature becomes the lead")
	var fillers: Array[CreatureInstance] = []
	while PartyManager.has_space():
		var filler := make_creature(&"brambleox", 2)
		fillers.append(filler)
		PartyManager.add_creature(filler)
	await press(&"ui_right")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(screen.get_message() == CreatureManagement.PARTY_FULL and GameSession.storage.get_count() == 2, "a full party can't take more")
	for filler in fillers:
		PartyManager.remove_creature(filler)
	for i in 8:
		GameSession.storage.add_creature(make_creature(&"thornling", 2))
	screen.set_tab(StorageScreen.Tab.STORAGE)
	check(list.get_row_count() == 10 and screen.get_range_text() == "1-6 of 10", "ten stored creatures: '1-6 of 10'")
	for i in 6:
		await press(&"ui_down")
	var visible_rows := range(list.get_row_count()).filter(func(i: int) -> bool: return list.get_row(i).visible)
	check(list.get_selected() == 6 and visible_rows == [1, 2, 3, 4, 5, 6] and screen.get_range_text() == "2-7 of 10",
			"long storage lists scroll, 6 rows at a time")
	await mouse_click(list.get_row(6))
	check(screen.get_mode() == StorageScreen.Mode.ACTIONS, "mouse: clicking a stored creature opens its options")
	await mouse_click(screen.get_actions().get_row(2))
	check(screen.get_mode() == StorageScreen.Mode.LIST and GameSession.storage.get_count() == 10, "mouse: CANCEL closes them")
	await press(&"ui_cancel")
	check(terminal.get_screen() == null and player.controls_enabled and not (main.get_node("PauseMenu") as PauseMenu).is_open(),
			"Esc leaves storage (and doesn't open the pause menu)")
	await hold(&"move_down", 0.2)
	check(player.global_position != spot, "the player can move again")
	restore_roster(stash)


func test_shop() -> void:
	section("Phase 12 · Fernhollow Market")
	var stash := stash_roster()
	SceneRouter.go_to("res://scenes/world/maps/fernhollow_town.tscn", &"player_home_front")
	check(await wait_for_map(&"fernhollow_town"), "in Fernhollow")
	var counter := world.current_map.get_node("Objects/Market") as ShopCounter
	GameSession.wallet.load_save_data(500)
	var orbs := GameSession.inventory.get_quantity(&"capture_orb")
	await place(counter.global_position + Vector2(0, 10), Vector2.UP)
	check(interaction.target == counter.get_node("Interactable"), "facing the counter targets the shop")
	await press(&"interact")
	var screen := counter.get_screen()
	var list := screen.get_list() if screen else null
	check(screen != null and list.get_row_text(0) == "Capture Orb 100 Own %d" % orbs and list.get_row_text(1) == "LEAVE"
			and screen.get_coins_text() == "500 Coins", "the shop lists Capture Orb (100), what you own, and your 500 Coins")
	var spot := player.global_position
	await hold(&"move_down", 0.3)
	check(player.global_position == spot and not GameSession.can_pause(), "no movement or pause in the shop")
	await shot("34_shop")
	var saves_before := saves
	await press(&"ui_accept")
	check(screen.get_mode() == ShopScreen.Mode.QUANTITY and screen.get_quantity() == 1, "choosing an item asks how many (1)")
	await shot("35_shop_quantity")
	await press(&"ui_accept")
	check(GameSession.wallet.get_coins() == 400 and GameSession.inventory.get_quantity(&"capture_orb") == orbs + 1
			and screen.get_message() == "You bought 1 Capture Orb." and screen.get_coins_text() == "400 Coins",
			"bought one: 400 Coins, one more orb")
	check(last_save_reason == &"purchase" and saves == saves_before + 1 and int(saved_save()["currency"]) == 400
			and int(saved_save()["inventory"]["capture_orb"]) == orbs + 1, "the purchase is saved")
	await press(&"ui_accept")
	await press(&"ui_right")
	await press(&"ui_right")
	check(screen.get_quantity() == 3, "Right raises the quantity")
	await press(&"ui_accept")
	check(GameSession.wallet.get_coins() == 100 and GameSession.inventory.get_quantity(&"capture_orb") == orbs + 4
			and screen.get_message() == "You bought 3 Capture Orbs.", "bought three at once: 100 Coins")
	await press(&"ui_accept")
	await press(&"ui_right")
	await press(&"ui_up")
	check(screen.get_quantity() == 1, "the quantity can't go past what you can afford")
	await press(&"ui_cancel")
	check(screen.get_mode() == ShopScreen.Mode.LIST and GameSession.wallet.get_coins() == 100, "Esc backs out without buying")
	await mouse_click(list.get_row(0))
	await mouse_click(screen.get_buy_button())
	check(GameSession.wallet.get_coins() == 0 and GameSession.inventory.get_quantity(&"capture_orb") == orbs + 5,
			"mouse: bought the last one, 0 Coins")
	saves_before = saves
	await press(&"ui_accept")
	check(screen.get_message() == "Not enough Coins." and screen.get_mode() == ShopScreen.Mode.LIST
			and GameSession.wallet.get_coins() == 0 and GameSession.inventory.get_quantity(&"capture_orb") == orbs + 5
			and saves == saves_before, "with 0 Coins: 'Not enough Coins.', nothing changes or saves")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(counter.get_screen() == null and player.controls_enabled, "LEAVE closes the shop")
	await frames(5)
	check(counter.get_screen() == null and not DialogueManager.is_active(), "leaving didn't reopen it")
	await press(&"interact")
	await press(&"ui_cancel")
	check(counter.get_screen() == null and not (main.get_node("PauseMenu") as PauseMenu).is_open(), "Esc leaves too (no pause menu)")
	restore_roster(stash)


func test_bed_prompt() -> void:
	section("Phase 12 · Resting")
	var stash := stash_roster()
	SceneRouter.go_to("res://scenes/world/maps/player_house.tscn", &"entrance")
	check(await wait_for_map(&"player_house"), "home")
	var bed := world.current_map.get_node("Objects/Bed") as HealPoint
	var flam := make_creature(&"flamkit", 6)
	var peb := make_creature(&"pebblit", 4)
	var moss := make_creature(&"mossaur", 5)
	var ox := make_creature(&"brambleox", 3)
	set_roster([flam, peb], 1, [moss, ox])
	flam.nickname = "Blaze"
	flam.experience = 11
	flam.current_hp = 3
	peb.current_hp = 0
	moss.current_hp = 2
	ox.current_hp = 0
	var before := {"party": json(PartyManager.to_save_data()), "storage": json(GameSession.storage.to_save_data())}
	var hp_before := [flam.current_hp, peb.current_hp, moss.current_hp, ox.current_hp]
	await place(Vector2(176, 92), Vector2.UP)
	var saves_before := saves
	await press(&"interact")
	var prompt := bed.get_prompt()
	check(prompt != null and prompt.get_dialog().get_node("%DialogTitle").text == "Rest and restore your creatures?"
			and prompt.get_dialog().get_selected_index() == 1, "the bed asks 'Rest and restore your creatures?' (default No)")
	check(not player.controls_enabled and not GameSession.can_pause(), "player locked while it asks")
	await shot("36_bed_prompt")
	await press(&"ui_accept")
	check(bed.get_prompt() == null and [flam.current_hp, peb.current_hp, moss.current_hp, ox.current_hp] == hp_before
			and saves == saves_before and not DialogueManager.is_active() and player.controls_enabled, "No: nothing healed, nothing saved")
	await press(&"interact")
	await press(&"ui_cancel")
	check(bed.get_prompt() == null and flam.current_hp == 3 and saves == saves_before, "Esc: same as No")
	await rest_in_bed()
	await expect_lines("", ["You lie down for a short rest.", "Your creatures are fully rested."], "Rested")
	check([flam, peb, moss, ox].all(func(c: CreatureInstance) -> bool: return c.current_hp == c.get_max_hp() and c.status.is_empty()),
			"party and storage, damaged or fainted, at exactly full HP")
	var after := {"party": json(PartyManager.to_save_data()), "storage": json(GameSession.storage.to_save_data())}
	var same := true
	for group: String in ["party", "storage"]:
		for i in before[group].size():
			for field: String in ["uid", "species_id", "nickname", "level", "experience", "moves"]:
				same = same and before[group][i][field] == after[group][i][field]
	check(same and party_names() == ["Blaze", "Pebblit"] and storage_names() == ["Mossaur", "Brambleox"]
			and PartyManager.get_active_index() == 1, "only HP changed: UIDs, species, names, levels, EXP, moves, order, storage")
	check(last_save_reason == &"rested" and saves == saves_before + 1 and saved_party(1)["current_hp"] == peb.get_max_hp()
			and saved_save()["storage"][1]["current_hp"] == ox.get_max_hp(), "saved once after healing")
	saves_before = saves
	await rest_in_bed()
	await expect_lines("", ["Your creatures are already fully rested."], "Already rested")
	check(saves == saves_before, "already rested: no extra save")
	await press(&"interact")
	await mouse_click(bed.get_prompt().get_dialog().get_option(0))
	check(DialogueManager.is_active() and box_text() == "Your creatures are already fully rested.", "mouse: YES works")
	await close_dialogue()
	restore_roster(stash)


func test_npc_collision() -> void:
	section("Phase 12 · NPC collision (player can't overlap an NPC)")
	SceneRouter.go_to("res://scenes/world/maps/fernhollow_town.tscn", &"player_home_front")
	await wait_for_map(&"fernhollow_town")
	var mira := npc(&"Mira")
	var home := mira.global_position
	var approaches := {
		"below": [Vector2(0, 48), &"move_up", Vector2.UP], "above": [Vector2(0, -48), &"move_down", Vector2.DOWN],
		"left": [Vector2(-40, 0), &"move_right", Vector2.RIGHT], "right": [Vector2(40, 0), &"move_left", Vector2.LEFT],
	}
	for side: String in approaches:
		var start: Vector2 = approaches[side][0]
		await place(home + start, approaches[side][2])
		await hold(approaches[side][1], 1.0)
		var gap := (player.global_position - home).abs()
		var touching := gap.y >= 21.5 and gap.y <= 23.0 if start.x == 0.0 else gap.x >= 9.5 and gap.x <= 11.0
		check(touching and not sprites_overlap(player.global_position, home),
				"from %s: stops touching Mira, sprites don't overlap (gap %s)" % [side, gap])
		check(interaction.target == interactable_of(mira), "from %s: Mira is in reach" % side)
		await press(&"interact")
		check(DialogueManager.is_active() and box_name() == "Mira"
				and mira.facing.is_equal_approx(-Vector2(approaches[side][2])), "from %s: E talks; Mira turns to face the player" % side)
		await close_dialogue()
	check(mira.global_position == home, "Mira never moved")
	await place(home + Vector2(-14, 40), Vector2.UP)
	await hold(&"move_up", 1.2)
	check(player.global_position.y < home.y - 25, "walking past beside her isn't blocked")
	var tobin := npc(&"Tobin")
	await place(tobin.global_position + Vector2(0, TALK_GAP), Vector2.UP)
	await press(&"interact")
	check(DialogueManager.is_active() and box_name() == "Old Tobin", "other NPCs: Tobin talks from the new distance")
	await close_dialogue()
	var sign_post := world.current_map.get_node("Objects/Signs/TownSign") as SignPost
	await place(sign_post.global_position + Vector2(0, 14), Vector2.UP)
	await press(&"interact")
	check(DialogueManager.is_active() and box_text() == "Fernhollow Town\nA peaceful beginning.", "signs still work")
	await close_dialogue()
	var locked := world.current_map.get_node("Objects/Buildings/HouseEast") as Building
	await place(locked.global_position + Vector2(0, 24), Vector2.UP)
	await hold(&"move_up", 0.6)
	await press(&"interact")
	check(DialogueManager.is_active() and box_text() == "The door is locked.", "doors still work")
	await close_dialogue()


func test_npc_dialogue_variants() -> void:
	section("Phase 12 · NPC dialogue")
	var tobin := npc(&"Tobin")
	await place(tobin.global_position + Vector2(0, TALK_GAP), Vector2.UP)
	await press(&"interact")
	await expect_lines("Old Tobin", ["So you've chosen your first companion. Take good care of it."], "Tobin (after the starter)")
	await frames(5)
	check(not DialogueManager.is_active(), "the E that closes a dialogue doesn't start it again")
	GameState.set_flag(GameState.STARTER_SELECTED, false)
	await press(&"interact")
	await expect_lines("Old Tobin", ["The professor has been preparing something special in the lab."], "Tobin (before the starter)")
	GameState.set_flag(GameState.STARTER_SELECTED, true)
	var mira := npc(&"Mira")
	await place(mira.global_position + Vector2(0, TALK_GAP), Vector2.UP)
	await press(&"interact")
	await expect_lines("Mira", ["Beautiful day, isn't it?",
		"Dara's market stall on the plaza sells Capture Orbs, if you're running low.",
		"And the lab has a storage terminal for creatures that don't fit in your party."], "Mira")
	var pell := npc(&"Pell")
	await place(pell.global_position + Vector2(0, TALK_GAP), Vector2.UP)
	await press(&"interact")
	await expect_lines("Pell", ["Route 01 is north of town. Be careful out there.",
		"If your team gets worn out, rest in your bed at home. You'll all wake up good as new."], "Pell")
	var dara := npc(&"Dara")
	check(not interactable_of(dara).can_interact(), "the shopkeeper is served through the counter, not by talking")


func test_route_01_polish() -> void:
	section("Phase 12 · Route 01 polish")
	SceneRouter.go_to("res://scenes/world/maps/route_01.tscn", &"south_entrance")
	check(await wait_for_map(&"route_01") and arrival_pos == Vector2(400, 600), "Route 01 loads at the same south entrance")
	var map := world.current_map
	check(map.get_bounds().size == Vector2(800, 640), "same size (50 x 40 tiles)")
	var zones := {"TallGrassSouth": Rect2(448, 496, 128, 80), "TallGrassWest": Rect2(48, 288, 128, 128),
			"TallGrassNorth": Rect2(272, 80, 160, 112), "TallGrassCrossing": Rect2(288, 208, 64, 64)}
	var zones_ok := map.get_node("EncounterZones").get_child_count() == 4
	for zone_name: String in zones:
		var zone := map.get_node("EncounterZones/" + zone_name) as EncounterZone
		zones_ok = zones_ok and zone.get_rect() == zones[zone_name] and zone.encounter_rate == 0.1 \
				and zone.encounter_table.resource_path == "res://data/encounters/route_01.tres"
	check(zones_ok, "the four grass zones, their rate (10%) and table are unchanged")
	var maps := Array(ResourceLoader.list_directory("res://scenes/world/maps/")).filter(
			func(f: String) -> bool: return f.ends_with(".tscn"))
	check(map.get_node("Transitions").get_child_count() == 1 and not ResourceLoader.exists("res://scenes/world/maps/route_02.tscn")
			and maps.size() == 4, "no Route 02 or other new maps; the only exit is south")
	var ground := map.get_node("Ground") as TileMapLayer
	var path_ok := true
	for y in range(9, 14):
		for x in [12, 13]:
			path_ok = path_ok and ground.get_cell_atlas_coords(Vector2i(x, y)) == Vector2i(4, 0)
	check(path_ok, "a new dirt path leads north from the junction")
	var started := encounters_started
	await place(Vector2(208, 250), Vector2.UP)
	await hold(&"move_up", 1.4)
	check(player.global_position.y < 165 and encounters_started == started, "walking the path north reaches the camp (no grass)")
	await hold(&"move_up", 0.6)
	check(player.global_position.y > 116, "the tent blocks (y=%.1f)" % player.global_position.y)
	await shot("37_field_camp")
	var camp := map.get_node("Objects/FieldCamp")
	check(camp.has_node("Tent") and camp.has_node("Campfire") and camp.has_node("LogSeat") and camp.has_node("SurveyMarker"),
			"field camp landmark: tent, campfire, log seat, survey marker")
	var fire := camp.get_node("Campfire") as SignPost
	await place(fire.global_position + Vector2(0, 10), Vector2.UP)
	await press(&"interact")
	check(DialogueManager.is_active() and box_text() == "The embers are still warm.\nSomeone camps here often.", "the campfire can be inspected")
	await close_dialogue()
	var marker := camp.get_node("SurveyMarker") as SignPost
	await place(marker.global_position + Vector2(12, -2), Vector2.LEFT)
	await press(&"interact")
	check(DialogueManager.is_active() and box_text().begins_with("FIELD STATION 01"), "the survey marker can be read")
	await close_dialogue()
	var researcher := npc(&"Researcher")
	await place(researcher.global_position + Vector2(11, 0), Vector2.LEFT)
	await press(&"interact")
	await expect_lines("Researcher Wren", ["Shh... the creatures come down to this pond to drink.",
		"I'm recording which elements live on Route 01. Ember, Tide, Verdant, and a few plain Neutral types.",
		"Ember beats Verdant, Verdant beats Tide, and Tide beats Ember. Remember that and you'll do fine."], "Researcher")
	var junction := map.get_node("Objects/Signs/JunctionSign") as SignPost
	await place(junction.global_position + Vector2(0, 14), Vector2.UP)
	await press(&"interact")
	check(DialogueManager.is_active() and box_text() == "North: Field Camp\nEast: Lookout and north gate\nSouth: Fernhollow Town",
			"a junction sign gives directions")
	await close_dialogue()
	var hiker := npc(&"Hiker")
	await place(hiker.global_position + Vector2(0, TALK_GAP), Vector2.UP)
	await press(&"interact")
	await expect_lines("Hiker", ["The view from up here is great!", "On a clear day you can see all the way back to Fernhollow.",
		"See the tent by the pond? Someone from the lab camps out there to study the wildlife."], "Hiker")
	await place(Vector2(400, 600), Vector2.DOWN)
	await hold(&"move_down", 0.8)
	check(await wait_for_map(&"fernhollow_town"), "south still leads back to Fernhollow")
	SceneRouter.go_to("res://scenes/world/maps/route_01.tscn", &"south_entrance")
	await wait_for_map(&"route_01")


# --- Phase 12: relaunch stages --------------------------------------------------------------

func test_e2e_start() -> void:
	section("Phase 12 end-to-end: New Game -> manage -> catch -> heal -> shop -> storage -> save")
	var pause := main.get_node("PauseMenu") as PauseMenu
	var party_screen := pause.get_party_screen()
	await new_game_from_title()
	check(GameSession.wallet.get_coins() == 500 and GameSession.inventory.get_quantity(&"capture_orb") == 5
			and PartyManager.get_size() == 0, "New Game: 500 Coins, 5 Capture Orbs")
	await choose_flamkit()
	var ember := PartyManager.get_creature(0)
	check(ember != null and ember.species_id == &"flamkit" and GameSession.wallet.get_coins() == 500
			and last_save_reason == &"starter_selected", "starter chosen (Coins unchanged); autosaved")
	await pause_and_save()
	check(last_save_reason == &"manual", "saved from the pause menu")
	await press(&"ui_up")
	await press(&"ui_accept")
	check(party_screen.is_open(), "party management opened")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(party_screen.get_message() == PartyScreen.NOTHING_TO_MOVE, "one creature: nothing to reorder yet")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(party_screen.get_message() == "Flamkit is already leading your team.", "and it's already the lead")
	await press(&"ui_accept")
	await press(&"ui_accept")
	await press(&"ui_accept")
	await type_text("Ember")
	await press_key(KEY_ENTER)
	check(ember.nickname == "Ember" and party_screen.get_details().get_message() == "Nickname changed to \"Ember\"."
			and last_save_reason == &"nickname_changed", "renamed to Ember; saved")
	for i in 3:
		await press(&"ui_cancel")
	check(not pause.is_open() and player.controls_enabled, "back to the game")

	SceneRouter.go_to("res://scenes/world/maps/route_01.tscn", &"south_entrance")
	await wait_for_map(&"route_01")
	await place(Vector2(470, 536), Vector2.RIGHT)
	EncounterManager.force_next_encounter_species(&"pebblit", 4)
	await hold(&"move_right", 0.25)
	check(await wait_for_ui(BattleScene.UiState.ACTION_MENU) and BattleManager.battle.player == ember
			and battle_scene().message_log.has("Go, Ember!"), "Route 01 encounter: Ember is sent out")
	BattleManager.battle.wild.current_hp = 6
	BattleManager.forced_capture = 1
	await mouse_click(battle_scene().get_node("%ItemOption"))
	await press(&"ui_accept")
	check(await wait_battle_over() and party_names() == ["Ember", "Pebblit"] and last_save_reason == &"battle_caught",
			"caught a Pebblit; autosaved")
	BattleManager.reset_test_overrides()
	var pebblit := PartyManager.get_creature(1)
	await place(Vector2(400, 610), Vector2.DOWN)
	await hold(&"move_down", 0.6)
	check(await wait_for_map(&"fernhollow_town"), "walked back to Fernhollow")

	await press(&"ui_cancel")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(PartyManager.get_active_creature() == pebblit and last_save_reason == &"lead_changed", "Pebblit made the lead")
	await press(&"ui_up")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(party_names() == ["Pebblit", "Ember"] and PartyManager.get_active_creature() == pebblit
			and PartyManager.get_active_index() == 0 and last_save_reason == &"party_reordered", "reordered: Pebblit, Ember (lead follows)")
	await press(&"ui_cancel")
	await press(&"ui_cancel")

	ember.current_hp = maxi(ember.current_hp - 5, 1)
	SceneRouter.go_to("res://scenes/world/maps/player_house.tscn", &"entrance")
	await wait_for_map(&"player_house")
	await place(Vector2(176, 92), Vector2.UP)
	await rest_in_bed()
	await close_dialogue()
	check(ember.current_hp == ember.get_max_hp() and pebblit.current_hp == pebblit.get_max_hp()
			and last_save_reason == &"rested", "rested: everyone at full HP; saved")

	SceneRouter.go_to("res://scenes/world/maps/fernhollow_town.tscn", &"player_home_front")
	await wait_for_map(&"fernhollow_town")
	var counter := world.current_map.get_node("Objects/Market") as ShopCounter
	await place(counter.global_position + Vector2(0, 10), Vector2.UP)
	await press(&"interact")
	await press(&"ui_accept")
	await press(&"ui_right")
	await press(&"ui_accept")
	check(GameSession.wallet.get_coins() == 300 and GameSession.inventory.get_quantity(&"capture_orb") == 6
			and last_save_reason == &"purchase", "bought 2 Capture Orbs: 300 Coins, 6 orbs; saved")
	await press(&"ui_cancel")

	SceneRouter.go_to(LAB_MAP, &"entrance")
	await wait_for_map(&"research_lab")
	var terminal := world.current_map.get_node("Objects/StorageTerminal") as StorageTerminal
	await place(terminal.global_position + Vector2(0, 12), Vector2.UP)
	await press(&"interact")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(party_names() == ["Pebblit"] and storage_names() == ["Ember"] and last_save_reason == &"creature_deposited",
			"Ember moved to storage; saved")
	await press(&"ui_right")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	check(party_names() == ["Pebblit", "Ember"] and GameSession.storage.get_count() == 0
			and last_save_reason == &"creature_withdrawn", "and moved back; saved")
	await press(&"ui_cancel")

	await press(&"ui_cancel")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_down")
	await press(&"ui_down")
	await press(&"ui_accept")
	await press(&"ui_up")
	await press(&"ui_accept")
	check(party_names() == ["Ember", "Pebblit"] and PartyManager.get_active_creature() == pebblit
			and PartyManager.get_active_index() == 1, "reordered again: Ember, Pebblit (Pebblit still leads, index 1)")
	await press(&"ui_cancel")
	await press(&"ui_cancel")
	await place(Vector2(250, 150), Vector2.LEFT)
	await pause_and_save()
	await press(&"ui_cancel")
	check(last_save_reason == &"manual" and not pause.is_open(), "saved")
	write_expectation()


func test_e2e_verify() -> void:
	section("Phase 12 end-to-end: relaunch -> Continue -> everything restored")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	await frames(3)
	verify_expectation()
	check(world.current_map.map_id == &"research_lab" and player.global_position == Vector2(250, 150)
			and player.facing == Vector2.LEFT, "map, position and facing exact")
	check(party_names() == ["Ember", "Pebblit"] and PartyManager.get_creature(0).species_id == &"flamkit"
			and PartyManager.get_active_index() == 1, "party order, nickname (Ember, still a Flamkit) and lead (slot 2)")
	check(PartyManager.get_party().all(func(c: CreatureInstance) -> bool: return c.current_hp == c.get_max_hp()),
			"HP restored exactly (full after resting)")
	check(GameSession.wallet.get_coins() == 300 and GameSession.inventory.get_items() == {&"capture_orb": 6}
			and GameSession.storage.get_count() == 0, "300 Coins, 6 Capture Orbs, empty storage")
	check(GameState.starter_selected and GameState.get_flag(GameState.STARTER_SPECIES) == "flamkit", "story flags")
	check(int(saved_save()["version"]) == 3, "the save file is version 3")


func test_migrate_v2() -> void:
	section("Migration: version 2 save -> Continue -> save as version 3")
	var v2 := v2_fixture()
	check(title.is_option_enabled(TitleScreen.Option.CONTINUE), "a version 2 save offers Continue")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	await frames(3)
	check(json(PartyManager.to_save_data()) == json(v2["party"]) and PartyManager.get_active_index() == 1,
			"party and active creature (slot 2) unchanged")
	check(json(GameSession.inventory.to_save_data()) == json(v2["inventory"])
			and json(GameSession.storage.to_save_data()) == json(v2["storage"]), "items (3 orbs) and storage (Pebbles) unchanged")
	check(GameSession.wallet.get_coins() == 500, "gets the starting 500 Coins")
	check(world.current_map_path == v2["world"]["map"] and player.global_position == Vector2(392, 560), "map and position unchanged")
	check(GameSession.save_now(&"manual") and int(saved_save()["version"]) == 3 and int(saved_save()["currency"]) == 500,
			"saved again as version 3 with currency")
	write_expectation()


func test_migrate_v2_verify() -> void:
	section("Migration: reload the version 3 save made from version 2")
	await press(&"ui_accept")
	check(await wait_for_state(GameSession.State.PLAYING), "Continue")
	await frames(3)
	verify_expectation()
	check(GameSession.storage.get_creature(0).nickname == "Pebbles" and GameSession.wallet.get_coins() == 500,
			"stored Pebbles and 500 Coins still there")


# --- Phase 1-3 regression -------------------------------------------------------------------

func test_world_and_collision() -> void:
	section("World + collision")
	check(world.current_map.map_id == &"fernhollow_town", "starts in town")
	check(player.global_position.distance_to(Vector2(144, 180)) < 1, "spawns at player_home_front")
	await shot("01_town_start")
	await hold(&"move_up", 1.0)
	check(player.global_position.y > 160 and world.current_map.map_id == &"fernhollow_town",
			"house wall blocks, walking into an E-only door does not enter (y=%.1f)" % player.global_position.y)
	var p0 := player.global_position
	Input.action_press(&"move_down"); Input.action_press(&"move_right")
	await frames(30)
	Input.action_release(&"move_down"); Input.action_release(&"move_right")
	await frames(10)
	var d := player.global_position - p0
	check(d.x > 10 and d.y > 10 and absf(d.x - d.y) < 2, "diagonal movement %s" % d)
	await place(Vector2(56, 200), Vector2.LEFT)
	await hold(&"move_left", 1.0)
	check(player.global_position.x >= 35.9, "west hedge blocks (x=%.1f)" % player.global_position.x)
	await place(Vector2(248, 185), Vector2.UP)
	await hold(&"move_up", 1.0)
	check(player.global_position.y > 156, "tree trunk blocks (y=%.1f)" % player.global_position.y)
	await place(Vector2(230, 252), Vector2.RIGHT)
	await hold(&"move_right", 1.0)
	check(player.global_position.x < 258, "NPC blocks (x=%.1f)" % player.global_position.x)
	await place(Vector2(320, 330), Vector2.UP)
	await hold(&"move_up", 1.0)
	check(player.global_position.y > 304, "fountain blocks (y=%.1f)" % player.global_position.y)


# --- Phase 4 --------------------------------------------------------------------------------

func test_npc_interaction() -> void:
	section("NPC interaction + dialogue")
	var mira := npc(&"Mira")
	await place(mira.global_position + Vector2(0, TALK_GAP), Vector2.UP)
	check(interaction.target == interactable_of(mira), "facing Mira targets Mira")
	check(prompt.visible, "prompt shown above Mira")
	await shot("02_prompt_mira")

	await press(&"interact")
	check(DialogueManager.is_active() and dialogue_box.visible, "E opens dialogue")
	check(box_name() == "Mira" and box_text() == "Beautiful day, isn't it?", "Mira's line and name shown")
	check(not prompt.visible, "prompt hidden during dialogue")
	check(mira.facing.y > 0.9, "Mira turned to face the player")
	var hint := dialogue_box.get_node("%HintLabel") as Label
	check(not hint.visible, "text is still typing out")
	await press(&"interact")
	check(DialogueManager.is_active() and hint.visible, "press while typing completes the text without advancing")
	await shot("03_dialogue_mira")

	var before := player.global_position
	await hold(&"move_down", 0.5)
	check(player.global_position == before, "movement disabled while dialogue open")
	await close_dialogue()
	check(not DialogueManager.is_active() and not dialogue_box.visible, "dialogue closes cleanly")
	await hold(&"move_down", 0.3)
	check(player.global_position.y > before.y + 5, "movement restored after dialogue")


func test_facing_rules() -> void:
	section("Facing rules")
	var mira := npc(&"Mira")
	var pell := npc(&"Pell")
	var pell_home := pell.global_position

	await place(mira.global_position + Vector2(0, TALK_GAP), Vector2.DOWN)
	check(interaction.target == null and not prompt.visible, "next to NPC but facing away: no target")
	await press(&"interact")
	check(not DialogueManager.is_active(), "next to NPC but facing away: E does nothing")

	await place(mira.global_position + Vector2(-14, 0), Vector2.UP)
	check(interaction.target == null, "NPC beside the player is never selected")
	await place(mira.global_position + Vector2(-14, 0), Vector2.RIGHT)
	check(interaction.target == interactable_of(mira), "turning toward the same NPC selects it")

	pell.global_position = mira.global_position + Vector2(16, 0)
	await frames(2)
	await place(mira.global_position + Vector2(0, TALK_GAP), Vector2.UP)
	check(interaction.target == interactable_of(mira), "two NPCs side by side: below Mira picks Mira")
	await place(pell.global_position + Vector2(0, TALK_GAP), Vector2.UP)
	check(interaction.target == interactable_of(pell), "two NPCs side by side: below Pell picks Pell")
	await place(mira.global_position + Vector2(6, TALK_GAP), Vector2.UP)
	check(interaction.target == interactable_of(mira), "slightly off-centre picks the nearer-aligned NPC")
	pell.global_position = pell_home
	await frames(2)


func test_signs() -> void:
	section("Signs")
	var sign_post := world.current_map.get_node("Objects/Signs/TownSign") as SignPost
	var tobin := npc(&"Tobin")
	var tobin_home := tobin.global_position
	# Tobin stands diagonally ahead, inside the facing cone; the sign is straight ahead.
	tobin.global_position = sign_post.global_position + Vector2(-11, -2)
	await frames(2)
	await place(sign_post.global_position + Vector2(0, 14), Vector2.UP)
	check(interaction.target == interactable_of(sign_post), "object straight ahead beats NPC off to the side")
	await press(&"interact")
	check(DialogueManager.is_active() and box_text() == "Fernhollow Town\nA peaceful beginning.", "sign text shown")
	check(not dialogue_box.get_node("%NameLabel").visible, "sign has no speaker name")
	await frames(40)
	await shot("04_sign")
	await press_key(KEY_SPACE)
	await press_key(KEY_SPACE)
	check(not DialogueManager.is_active(), "Space advances and closes dialogue")
	tobin.global_position = tobin_home
	await frames(2)


func test_line_of_sight() -> void:
	section("Line of sight")
	# Inside the fenced garden, facing an NPC on the other side of the fence.
	var tobin := npc(&"Tobin")
	var tobin_home := tobin.global_position
	await place(Vector2(240, 500), Vector2.UP)
	await hold(&"move_up", 0.6)
	tobin.global_position = Vector2(240, interaction.global_position.y - 23 + 3)
	await frames(3)
	var along := interaction.global_position.y - interactable_of(tobin).global_position.y
	check(along <= interactable_of(tobin).interaction_distance, "NPC is within reach (%.1f px)" % along)
	check(interaction.target == null and not prompt.visible, "fence between player and NPC blocks interaction")
	await press(&"interact")
	check(not DialogueManager.is_active(), "E through a fence does nothing")
	tobin.global_position = tobin_home
	await frames(2)


func test_doors() -> void:
	section("Doors")
	var buildings := world.current_map.get_node("Objects/Buildings")
	var lab_door := buildings.get_node("ResearchLab/DoorInteractable") as Interactable
	check(not lab_door.interaction_enabled, "walk-in lab door has no E interaction")

	var locked := buildings.get_node("HouseEast") as Building
	await place(locked.global_position + Vector2(0, 24), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(interaction.target == locked.get_node("DoorInteractable"), "facing a locked door targets it")
	await press(&"interact")
	check(DialogueManager.is_active() and box_text() == "The door is locked.", "locked door message")
	await close_dialogue()

	var home := buildings.get_node("PlayerHouse") as Building
	await place(home.global_position + Vector2(0, 24), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(world.current_map.map_id == &"fernhollow_town", "E-only door does not enter on walk-in")
	check(interaction.target == home.get_node("DoorInteractable") and prompt.visible, "prompt on home door")
	await shot("05_prompt_door")
	await press(&"interact")
	check(await wait_for_map(&"player_house"), "E on home door enters the house")
	check(arrival_pos.distance_to(Vector2(112, 116)) < 1, "arrives at house entrance %s" % arrival_pos)
	await frames(20)
	await shot("06_home_interior")
	await hold(&"move_down", 0.6)
	check(await wait_for_map(&"fernhollow_town"), "leaving the house returns to town")
	check(arrival_pos.distance_to(Vector2(144, 180)) < 1, "arrives at player_home_front %s" % arrival_pos)


# --- Phase 5 --------------------------------------------------------------------------------

func test_creature_data() -> void:
	section("Creature data + factory")
	var expected := {
		&"flamkit": [45, 60, 40, 70, &"ember", [&"tackle", &"ember"]],
		&"aquaphin": [55, 50, 50, 55, &"tide", [&"tackle", &"splash"]],
		&"mossaur": [65, 45, 65, 35, &"verdant", [&"tackle", &"vine_whip"]],
	}
	for id: StringName in expected:
		var e: Array = expected[id]
		var species := CreatureDatabase.get_species(id)
		check(species != null and species.sprite != null and species.element.id == e[4],
				"%s species loads with sprite and element" % id)
		var creature := CreatureFactory.create_from_species(species, 5)
		check(creature.species_id == id and creature.level == 5 and creature.experience == 0,
				"%s instance: species, level 5, 0 XP" % id)
		check(creature.get_max_hp() == e[0] + 10 and creature.current_hp == creature.get_max_hp(),
				"%s HP = base + level*2 = %d, starts full" % [id, creature.get_max_hp()])
		check(creature.get_stat(CreatureStats.Stat.ATTACK) == e[1] + 5
				and creature.get_stat(CreatureStats.Stat.DEFENSE) == e[2] + 5
				and creature.get_stat(CreatureStats.Stat.SPEED) == e[3] + 5, "%s other stats = base + level" % id)
		check(Array(creature.move_ids) == e[5], "%s starting moves %s" % [id, creature.move_ids])

	var moves := {
		&"tackle": [&"neutral", 40], &"ember": [&"ember", 40],
		&"splash": [&"tide", 20], &"vine_whip": [&"verdant", 45],
	}
	for id: StringName in moves:
		var move := CreatureDatabase.get_move(id)
		check(move != null and move.element.id == moves[id][0] and move.power == moves[id][1],
				"move %s: %s, power %d" % [id, moves[id][0], moves[id][1]])

	var original := CreatureFactory.create_from_species(CreatureDatabase.get_species(&"aquaphin"), 5)
	original.nickname = "Bubbles"
	original.current_hp = 20
	original.experience = 12
	var json: Dictionary = JSON.parse_string(JSON.stringify(original.to_save_data()))
	var restored := CreatureInstance.from_save_data(json)
	check(restored.uid == original.uid and restored.species_id == &"aquaphin" and restored.nickname == "Bubbles"
			and restored.level == 5 and restored.experience == 12 and restored.current_hp == 20
			and restored.move_ids == original.move_ids, "instance survives a JSON save/load round trip")
	check(restored.get_display_name() == "Bubbles", "nickname is used as the display name")
	var other := CreatureFactory.create_from_species(CreatureDatabase.get_species(&"aquaphin"), 5)
	check(other.uid != original.uid, "every instance gets a unique id")
	json["current_hp"] = 999
	check(CreatureInstance.from_save_data(json).current_hp == original.get_max_hp(), "corrupt HP is clamped on load")


func test_party_manager() -> void:
	section("PartyManager")
	var party: Node = load("res://scripts/party/party_manager.gd").new()
	var flamkit := CreatureDatabase.get_species(&"flamkit")
	var first := CreatureFactory.create_from_species(flamkit, 5)
	check(party.add_creature(first) == 0 and party.get_creature(0) == first, "first creature goes in slot 1")
	check(party.add_creature(first) == -1, "the same creature can't be added twice")
	for i in 5:
		party.add_creature(CreatureFactory.create_from_species(flamkit, 5))
	check(party.get_size() == 6 and not party.has_space(), "party holds 6")
	check(party.add_creature(CreatureFactory.create_from_species(flamkit, 5)) == -1, "a 7th creature is refused")
	check(party.get_creature(6) == null and party.get_creature(-1) == null, "empty / invalid slots return null")
	var saved: Array = party.to_save_data()
	check(party.remove_creature(first) and party.get_size() == 5 and party.get_creature(0) != first, "remove creature")
	party.load_save_data(JSON.parse_string(JSON.stringify(saved)))
	check(party.get_size() == 6 and party.get_creature(0).uid == first.uid, "party save data round trip")
	party.free()
	check(PartyManager.get_size() == 0, "real party is still empty before choosing a starter")


func test_starter_selection() -> void:
	section("Starter selection")
	await place(Vector2(128, 420), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(await wait_for_map(&"research_lab"), "walk-in lab door still works")
	check(arrival_pos.distance_to(Vector2(192, 200)) < 1, "arrives at lab entrance")
	check(not GameState.starter_selected and PartyManager.get_size() == 0, "no starter before talking to Elian")
	var event := world.current_map.get_node("Events/StarterSelectionEvent") as StarterSelectionEvent
	var elian := npc(&"ProfessorElian")
	await hold(&"move_up", 1.0)
	check(interaction.target == interactable_of(elian), "facing Professor Elian targets him")

	await press(&"interact")
	await frames(40)
	await shot("07_dialogue_elian")
	await expect_lines("Professor Elian", [
		"You're finally here!",
		"Every journey begins with a first companion.",
		"I have three creatures that are ready to form a bond with a new trainer.",
		"Which one will you choose?",
	], "Elian intro")
	check(event.is_selecting(), "intro finishing opens the starter screen")
	var screen := starter_screen()
	var ids := screen.get_node("%Cards").get_children().map(func(card: StarterCard) -> StringName: return card.species.id)
	check(ids == [&"flamkit", &"aquaphin", &"mossaur"], "three starters shown in order %s" % [ids])
	await frames(20)
	check(screen.get_selected_species().id == &"flamkit" and detail("DetailName") == "Flamkit",
			"Flamkit highlighted first")
	check(interaction.target == null and not prompt.visible, "world interaction disabled while open")
	var before := player.global_position
	await hold(&"move_down", 0.3)
	check(player.global_position == before, "player can't move while choosing")
	await shot("08_starter_flamkit")

	await press(&"ui_right")
	var aquaphin := CreatureDatabase.get_species(&"aquaphin")
	check(screen.get_selected_species() == aquaphin and detail("DetailName") == "Aquaphin"
			and detail("Description") == aquaphin.description and detail("DetailSubtitle").begins_with("Tide"),
			"Right selects Aquaphin and the details update")
	await frames(20)
	var hp_bar := screen.get_node("%StatsGrid").get_child(1) as ProgressBar
	check(is_equal_approx(hp_bar.value, 55.0), "HP bar reflects Aquaphin's base HP (%.0f)" % hp_bar.value)
	await shot("09_starter_aquaphin")
	await press(&"move_right")
	check(screen.get_selected_species().id == &"mossaur", "D also moves right (Mossaur)")
	await press(&"ui_right")
	check(screen.get_selected_species().id == &"flamkit", "selection wraps around")
	await press(&"ui_left")
	check(screen.get_selected_species().id == &"mossaur", "Left moves back")
	await press(&"ui_left")
	await press(&"ui_left")

	await press(&"ui_cancel")
	check(not event.is_selecting() and DialogueManager.is_active()
			and box_text() == "Take your time. It's an important choice.", "Esc closes the screen and Elian reacts")
	await close_dialogue()
	check(not GameState.starter_selected and PartyManager.get_size() == 0, "cancelling gives nothing")

	await press(&"interact")
	await close_dialogue()
	check(event.is_selecting(), "talking again reopens the starter screen")
	screen = starter_screen()
	await press(&"ui_accept")
	check(screen.is_confirming() and detail("Question") == "Choose Flamkit as your first companion?",
			"confirmation asks about Flamkit")
	await shot("10_starter_confirm")
	await press(&"ui_right")
	await press(&"ui_accept")
	check(event.is_selecting() and not screen.is_confirming() and PartyManager.get_size() == 0,
			"NO returns to the selection")
	await press(&"interact")
	check(screen.is_confirming(), "E also selects")
	await press(&"ui_cancel")
	check(event.is_selecting() and not screen.is_confirming(), "Esc in the confirmation means NO")
	await press(&"ui_accept")
	await press(&"ui_accept")
	check(not event.is_selecting(), "YES closes the starter screen")

	var creature := PartyManager.get_creature(0)
	check(PartyManager.get_size() == 1 and creature != null, "starter is in party slot 1")
	if creature:
		check(creature.species_id == &"flamkit" and creature.level == 5 and creature.experience == 0
				and creature.nickname == "", "Flamkit, level 5, 0 XP, no nickname")
		check(Array(creature.move_ids) == [&"tackle", &"ember"], "moves: Tackle, Ember")
		check(creature.current_hp == 55 and creature.get_max_hp() == 55, "HP 55/55 (45 + 5 * 2)")
	check(GameState.starter_selected and GameState.get_flag(GameState.STARTER_SPECIES) == "flamkit",
			"starter_selected = true, starter_species = flamkit")
	var save: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_PATH))
	check(save is Dictionary and save["game_state"]["starter_selected"] == true
			and save["party"].size() == 1 and save["party"][0]["species_id"] == "flamkit"
			and int(save["party"][0]["current_hp"]) == 55 and save["party"][0]["moves"] == ["tackle", "ember"]
			and save["world"]["map"] == LAB_MAP, "game saved with flag, party and position")

	await frames(30)
	await shot("11_starter_joined")
	await expect_lines("Professor Elian", [
		"Flamkit has joined your team!",
		"You and Flamkit have a long road ahead.",
	], "Elian reacts to the choice")
	var moved_from := player.global_position
	await hold(&"move_down", 0.2)
	check(player.global_position.y > moved_from.y, "control returns after the sequence")
	await hold(&"move_up", 0.5)

	await press(&"interact")
	await expect_lines("Professor Elian", [
		"You've already chosen your companion.",
		"Take good care of each other.",
	], "Elian's post-selection dialogue")
	check(not event.is_selecting() and PartyManager.get_size() == 1, "no second starter offered")
	# Even if the intro were somehow replayed, the event must not offer another starter.
	DialogueManager.start(event.intro_dialogue)
	await close_dialogue()
	check(not event.is_selecting() and PartyManager.get_size() == 1, "a replayed intro can't reopen selection")


func test_leave_lab() -> void:
	section("Leave lab")
	await place(Vector2(192, 200), Vector2.DOWN)
	await hold(&"move_down", 0.6)
	check(await wait_for_map(&"fernhollow_town"), "leaving lab returns to town")
	check(arrival_pos.distance_to(Vector2(128, 404)) < 1, "arrives at lab_front")


## Quits nothing in this process: launches a fresh Godot process running `stage`, which loads
## the same test save from disk, and reports its checks here.
func run_stage(stage: String, extra_args: Array = []) -> void:
	section("Relaunch: separate Godot process, stage '%s'" % stage)
	var output: Array = []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60",
			"res://tests/smoke_test.tscn", "--", "--stage=" + stage, "--test-timeout=" + str(STAGE_TIMEOUT)]
	args.append_array(extra_args)
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	for line in "".join(output).split("\n"):
		if line.begins_with("  ") or line.begins_with("##") or line.contains("DONE") \
				or line.contains("ERROR") or line.contains("WARNING"):
			print("    | " + line)
	check(code == 0, "stage '%s' passed (exit code %d)" % [stage, code])


func test_route_transitions() -> void:
	section("Route 01")
	await place(Vector2(320, 60), Vector2.UP)
	await hold(&"move_up", 0.6)
	check(await wait_for_map(&"route_01"), "north exit leads to Route 01")
	await hold(&"move_down", 0.8)
	check(await wait_for_map(&"fernhollow_town"), "Route 01 returns to town")
	check(arrival_pos.distance_to(Vector2(320, 40)) < 1, "arrives at north_exit_arrival")


# --- Helpers --------------------------------------------------------------------------------

func section(title: String) -> void:
	current_section = title
	print("\n## " + title)


func check(condition: bool, message: String) -> void:
	checks += 1
	print(("  PASS  " if condition else "  FAIL  ") + message)
	if not condition:
		failures += 1


func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func hold(action: StringName, seconds: float) -> void:
	Input.action_press(action)
	await frames(int(seconds * 60))
	Input.action_release(action)
	await frames(10)


func press(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await delivered()
		await frames(2)


## Parsed input is dispatched once per rendered (process) frame. Waiting only for physics frames
## isn't enough: when the engine catches up after a stall (e.g. a blocking relaunch) it runs
## several physics frames per process frame, and a check could run before the key arrived.
func delivered() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await delivered()
		await frames(2)


## Checks each line in turn: skips the typewriter effect, then advances.
func expect_lines(speaker: String, lines: Array, label: String) -> void:
	var hint := dialogue_box.get_node("%HintLabel") as Label
	for i in lines.size():
		check(DialogueManager.is_active() and box_name() == speaker and box_text() == lines[i],
				"%s, line %d: %s" % [label, i + 1, lines[i]])
		if not hint.visible:
			await press(&"interact")
		await press(&"interact")
	check(not DialogueManager.is_active(), "%s: dialogue ends" % label)


func wait_for_state(state: GameSession.State, max_frames := 120) -> bool:
	for i in max_frames:
		if GameSession.state == state and not SceneRouter.is_busy():
			return true
		await get_tree().physics_frame
	return false


func mouse_move(control: Control) -> void:
	var event := InputEventMouseMotion.new()
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	get_viewport().push_input(event, true)
	await frames(2)


func mouse_click(control: Control) -> void:
	await mouse_move(control)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = control.get_global_rect().get_center()
		event.global_position = event.position
		get_viewport().push_input(event, true)
		await frames(2)


func write_test_save(text: String) -> void:
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func starter_event() -> StarterSelectionEvent:
	return world.current_map.get_node("Events/StarterSelectionEvent") as StarterSelectionEvent


func starter_screen() -> StarterSelectionScreen:
	var event := world.current_map.get_node("Events/StarterSelectionEvent")
	for child in event.get_children():
		if child is StarterSelectionScreen and not child.is_queued_for_deletion():
			return child
	return null


func detail(node_name: String) -> String:
	return (starter_screen().get_node("%" + node_name) as Label).text


## Phase 12: interact with the bed and answer YES (the question defaults to NO).
func rest_in_bed() -> void:
	await press(&"interact")
	await press(&"ui_left")
	await press(&"ui_accept")


## Phase 12: Esc, then SAVE GAME (third option, after CONTINUE and CREATURES).
func pause_and_save() -> void:
	await press(&"ui_cancel")
	await press(&"ui_down")
	await press(&"ui_down")
	await press(&"ui_accept")


func close_dialogue() -> void:
	for i in 20:
		if not DialogueManager.is_active():
			return
		await press(&"interact")


func place(pos: Vector2, facing: Vector2) -> void:
	player.teleport(pos, facing)
	player.camera.reset_smoothing()
	await frames(3)


func wait_for_map(id: StringName, max_frames := 120) -> bool:
	for i in max_frames:
		if world.current_map and world.current_map.map_id == id and not SceneRouter.is_busy():
			return true
		await get_tree().physics_frame
	return false


func npc(node_name: StringName) -> NPC:
	return world.current_map.get_node("Objects/NPCs/" + node_name) as NPC


func interactable_of(node: Node) -> Interactable:
	return node.get_node("Interactable") as Interactable


func box_name() -> String:
	var label := dialogue_box.get_node("%NameLabel") as Label
	return label.text if label.visible else ""


func box_text() -> String:
	return (dialogue_box.get_node("%TextLabel") as Label).text


func shot(file_name: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image:
		image.save_png(shots_dir.path_join(file_name + ".png"))
