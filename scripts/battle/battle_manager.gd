extends Node
## Autoload that runs battles. Rules only: no UI, no waiting. It starts a battle for every wild
## encounter and for every trainer challenge (start_trainer_battle), resolves each player action
## into a list of BattleEvents for the BattleScene to play back, awards EXP and trainer rewards,
## and ends the encounter when the battle is over. Wild and trainer battles are the same battle;
## BattleContext.source decides the few rules that differ (no catching or running from trainers,
## the trainer sends out its next creature, a reward for beating the trainer).
##
## States: NONE -> INTRO -> PLAYER_ACTION <-> TURN_RESOLUTION
##         -> SWITCH_REQUIRED (active creature fainted, others can fight) -> PLAYER_ACTION
##         -> VICTORY (wild creature or whole trainer team beaten) | DEFEAT | ESCAPED | CAUGHT -> NONE
## Player actions: FIGHT (submit_move), CREATURE (submit_switch), ITEM (submit_item), RUN (submit_run).

signal battle_started(battle: BattleContext)
signal turn_resolved(events: Array[BattleEvent])
signal battle_won(battle: BattleContext)
signal battle_lost(battle: BattleContext)
signal battle_finished(battle: BattleContext)

enum State { NONE, INTRO, PLAYER_ACTION, TURN_RESOLUTION, SWITCH_REQUIRED, VICTORY, DEFEAT, ESCAPED, CAUGHT }

const CAPTURE_CATEGORY := &"capture"

var state := State.NONE
var battle: BattleContext
## Source of all battle randomness (damage roll, accuracy, speed ties, AI, escape, capture). Tests seed it.
var rng := RandomNumberGenerator.new()

# --- Test/debug overrides. Never set during normal play; see reset_test_overrides(). ---
## Every move hits.
var force_hit := false
## Damage random factor; negative means roll it.
var forced_random_factor := -1.0
## Exact damage for every hit; negative means calculate it.
var forced_damage := -1
## Move the opposing creature (wild or trainer) always uses; empty means BattleAI decides.
var forced_ai_move: StringName = &""
## 1 = player always first, -1 = opponent always first, 0 = decide by speed.
var forced_turn_order := 0
## 1 = running always works, -1 = always fails, 0 = roll the escape chance.
var forced_escape := 0
## 1 = capture always works, -1 = always fails, 0 = roll the capture chance.
var forced_capture := 0


func _ready() -> void:
	rng.randomize()
	EncounterManager.encounter_started.connect(start_battle)


func is_active() -> bool:
	return state != State.NONE


func start_battle(encounter: WildEncounter) -> bool:
	if is_active():
		return false
	var active := PartyManager.ensure_usable_active()
	if active == null:
		# EncounterManager already prevents this; never strand the player in an encounter.
		# Deferred so every encounter_started listener (e.g. the World's player lock) runs first.
		push_warning("BattleManager: no usable creature, encounter skipped.")
		EncounterManager.end_encounter.call_deferred()
		return false
	battle = BattleContext.new(encounter, active)
	_set_state(State.INTRO)
	battle_started.emit(battle)
	return true


## True if a trainer battle could start right now: no battle running and a creature that can fight.
func can_start_trainer_battle() -> bool:
	return not is_active() and GameSession.state == GameSession.State.PLAYING \
			and get_first_usable_creature() != null


## Starts a battle against `trainer`. Their team is built fresh from the TrainerData templates
## (temporary creatures, never added to the party, storage or save). Returns false if the trainer
## is invalid or no battle can start.
func start_trainer_battle(trainer: TrainerData) -> bool:
	if trainer == null or not can_start_trainer_battle() or not TrainerCatalog.validate_trainer(trainer).is_empty():
		return false
	var team: Array[CreatureInstance] = []
	for entry in trainer.team:
		team.append(CreatureFactory.create_from_trainer(entry))
	battle = BattleContext.for_trainer(trainer, team, PartyManager.ensure_usable_active())
	_set_state(State.INTRO)
	battle_started.emit(battle)
	return true


## The first party creature that can still fight.
func get_first_usable_creature() -> CreatureInstance:
	for creature in PartyManager.get_party():
		if creature.current_hp > 0:
			return creature
	return null


## Called once the battle intro has been shown.
func begin_player_turn() -> void:
	if state == State.INTRO:
		_set_state(State.PLAYER_ACTION)


func get_player_moves() -> Array[MoveData]:
	var moves: Array[MoveData] = []
	if battle:
		for move_id in battle.player.move_ids:
			var move := CreatureDatabase.get_move(move_id)
			if move:
				moves.append(move)
	return moves


## Resolves one full turn with the player's chosen move. Returns what happened, in order.
func submit_move(move_id: StringName) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	if state != State.PLAYER_ACTION or not battle.player.move_ids.has(move_id) \
			or CreatureDatabase.get_move(move_id) == null:
		return events
	_set_state(State.TURN_RESOLUTION)
	battle.turn += 1
	var actions := {BattleSide.Side.PLAYER: move_id, BattleSide.Side.WILD: _choose_opponent_move()}
	for side in determine_turn_order():
		_execute_move(side, actions[side], events)
		if _resolve_faints(events):
			break
	return _finish_turn(events)


## Switches the active creature to `party_index`. A voluntary switch (PLAYER_ACTION) uses the
## player's turn, so the wild creature then attacks the newcomer. Replacing a fainted creature
## (SWITCH_REQUIRED) is free.
func submit_switch(party_index: int) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	var replacing_fainted := state == State.SWITCH_REQUIRED
	if not (replacing_fainted or state == State.PLAYER_ACTION) or not PartyManager.can_switch_to(party_index):
		return events
	_set_state(State.TURN_RESOLUTION)
	if not replacing_fainted:
		battle.turn += 1
		var recalled := BattleEvent.new(BattleEvent.Type.RECALLED, BattleSide.Side.PLAYER)
		recalled.creature = battle.player
		events.append(recalled)
	PartyManager.switch_active(party_index)
	battle.player = PartyManager.get_active_creature()
	battle.awaiting_switch = false
	var sent := BattleEvent.new(BattleEvent.Type.SENT_OUT, BattleSide.Side.PLAYER)
	sent.creature = battle.player
	events.append(sent)
	if not replacing_fainted:
		_execute_move(BattleSide.Side.WILD, _choose_opponent_move(), events)
		_resolve_faints(events)
	return _finish_turn(events)


## Why `item_id` can't be used right now, or "" if it can. Only capture items exist so far, and
## they only work on wild creatures: a trainer's creature can't be captured (nothing is used up).
func get_item_problem(item_id: StringName) -> String:
	var item := ItemCatalog.get_item(item_id)
	if state != State.PLAYER_ACTION or item == null or item.category != CAPTURE_CATEGORY:
		return BattleMessages.CANT_CATCH
	if battle.is_trainer_battle():
		return BattleMessages.CANT_CAPTURE_TRAINER
	if not GameSession.inventory.has_item(item_id):
		return BattleMessages.OUT_OF_ITEM.format({"item": item.display_name})
	if battle.wild.current_hp <= 0:
		return BattleMessages.CANT_CATCH
	return ""


## Uses a capture item: consumes one, then rolls the capture. Success ends the battle (no EXP) and
## gives the player an owned copy of the wild creature in its current state; failure gives the
## wild creature its turn.
func submit_item(item_id: StringName) -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	if not get_item_problem(item_id).is_empty():
		return events
	_set_state(State.TURN_RESOLUTION)
	battle.turn += 1
	GameSession.inventory.remove_item(item_id)
	var thrown := BattleEvent.new(BattleEvent.Type.CAPTURE_THROWN, BattleSide.Side.PLAYER)
	thrown.move_id = item_id
	events.append(thrown)
	if _roll_capture():
		_catch(events)
	else:
		events.append(BattleEvent.new(BattleEvent.Type.CAPTURE_FAILED, BattleSide.Side.WILD))
		_execute_move(BattleSide.Side.WILD, _choose_opponent_move(), events)
		_resolve_faints(events)
	return _finish_turn(events)


## Why running isn't possible right now, or "" if the player may try. There's no running from a
## trainer: refusing uses no turn and rolls nothing.
func get_run_problem() -> String:
	if state != State.PLAYER_ACTION:
		return BattleMessages.ESCAPE_FAILED
	if battle.is_trainer_battle():
		return BattleMessages.CANT_RUN_TRAINER
	return ""


## Tries to run from a wild battle. Success ends it (no EXP); failure gives the wild creature a free turn.
func submit_run() -> Array[BattleEvent]:
	var events: Array[BattleEvent] = []
	if not get_run_problem().is_empty():
		return events
	_set_state(State.TURN_RESOLUTION)
	battle.turn += 1
	if _roll_escape():
		events.append(BattleEvent.new(BattleEvent.Type.ESCAPED, BattleSide.Side.PLAYER))
		battle.outcome = BattleContext.OUTCOME_ESCAPED
		_set_state(State.ESCAPED)
	else:
		battle.failed_escapes += 1
		events.append(BattleEvent.new(BattleEvent.Type.ESCAPE_FAILED, BattleSide.Side.PLAYER))
		_execute_move(BattleSide.Side.WILD, _choose_opponent_move(), events)
		_resolve_faints(events)
	return _finish_turn(events)


## How effective one of the player's moves would be against the opposing creature, straight from
## BattleCalculator, so menus never work out matchups themselves.
func preview_effectiveness(move_id: StringName) -> float:
	var move := CreatureDatabase.get_move(move_id)
	return BattleCalculator.element_multiplier(move, battle.wild) if move and battle else 1.0


func get_escape_chance() -> float:
	return BattleCalculator.escape_chance(battle.player.get_stat(CreatureStats.Stat.SPEED),
			battle.wild.get_stat(CreatureStats.Stat.SPEED), battle.failed_escapes)


func get_capture_chance() -> float:
	return BattleCalculator.capture_chance(battle.wild.current_hp, battle.wild.get_max_hp())


## Order in which the two sides act this turn.
func determine_turn_order() -> Array[BattleSide.Side]:
	var player_first: bool
	if forced_turn_order != 0:
		player_first = forced_turn_order > 0
	else:
		player_first = BattleCalculator.player_moves_first(battle.player.get_stat(CreatureStats.Stat.SPEED),
				battle.wild.get_stat(CreatureStats.Stat.SPEED), rng)
	if player_first:
		return [BattleSide.Side.PLAYER, BattleSide.Side.WILD]
	return [BattleSide.Side.WILD, BattleSide.Side.PLAYER]


## Called by the presentation once the result has been shown. Ends the encounter too.
func end_battle() -> void:
	if not [State.VICTORY, State.DEFEAT, State.ESCAPED, State.CAUGHT].has(state):
		return
	var finished := battle
	battle = null
	_set_state(State.NONE)
	battle_finished.emit(finished)
	EncounterManager.end_encounter()


## Drops any battle without results, e.g. when a new session starts.
func reset() -> void:
	battle = null
	state = State.NONE


func reset_test_overrides() -> void:
	force_hit = false
	forced_random_factor = -1.0
	forced_damage = -1
	forced_ai_move = &""
	forced_turn_order = 0
	forced_escape = 0
	forced_capture = 0


func _finish_turn(events: Array[BattleEvent]) -> Array[BattleEvent]:
	if state == State.TURN_RESOLUTION:
		_set_state(State.PLAYER_ACTION)
	turn_resolved.emit(events)
	return events


func _roll_escape() -> bool:
	if forced_escape != 0:
		return forced_escape > 0
	return rng.randf() < get_escape_chance()


func _roll_capture() -> bool:
	if forced_capture != 0:
		return forced_capture > 0
	return rng.randf() < get_capture_chance()


## Wild creatures and trainers choose the same way for now: a random valid move (BattleAI).
func _choose_opponent_move() -> StringName:
	if not forced_ai_move.is_empty():
		return forced_ai_move
	return BattleAI.choose_move(battle.wild, rng)


func _catch(events: Array[BattleEvent]) -> void:
	var owned := CreatureFactory.create_from_wild(battle.wild)
	battle.caught_creature = owned
	events.append(BattleEvent.new(BattleEvent.Type.CAPTURE_SUCCEEDED, BattleSide.Side.WILD))
	var placed: BattleEvent
	if PartyManager.add_creature(owned) >= 0:
		placed = BattleEvent.new(BattleEvent.Type.JOINED_PARTY, BattleSide.Side.PLAYER)
	else:
		GameSession.storage.add_creature(owned)
		placed = BattleEvent.new(BattleEvent.Type.SENT_TO_STORAGE, BattleSide.Side.PLAYER)
	placed.creature = owned
	events.append(placed)
	battle.outcome = BattleContext.OUTCOME_CAUGHT
	_set_state(State.CAUGHT)


func _execute_move(side: BattleSide.Side, move_id: StringName, events: Array[BattleEvent]) -> void:
	var attacker := battle.creature(side)
	var target_side := battle.opponent(side)
	var defender := battle.creature(target_side)
	var move := CreatureDatabase.get_move(move_id)
	if attacker.current_hp <= 0 or move == null:
		return
	var used := BattleEvent.new(BattleEvent.Type.MOVE_USED, side)
	used.move_id = move_id
	used.creature = attacker
	events.append(used)
	if not force_hit and not BattleCalculator.roll_hit(move, rng):
		var missed := BattleEvent.new(BattleEvent.Type.MISSED, side)
		missed.creature = attacker
		events.append(missed)
		return
	var factor := forced_random_factor if forced_random_factor >= 0.0 else BattleCalculator.roll_random_factor(rng)
	var result := BattleCalculator.calculate_damage(attacker, defender, move, factor)
	var damage: int = forced_damage if forced_damage >= 0 else result["damage"]
	var hit := BattleEvent.new(BattleEvent.Type.DAMAGE, target_side)
	hit.creature = defender
	hit.move_id = move_id
	hit.amount = damage
	hit.effectiveness = result["effectiveness"]
	hit.hp_before = defender.current_hp
	defender.current_hp = maxi(defender.current_hp - damage, 0)
	hit.hp_after = defender.current_hp
	events.append(hit)


## Returns true if this turn must stop: the battle is over, or a fainted creature must be replaced.
func _resolve_faints(events: Array[BattleEvent]) -> bool:
	if battle.wild.current_hp <= 0:
		var fainted := BattleEvent.new(BattleEvent.Type.FAINTED, BattleSide.Side.WILD)
		fainted.creature = battle.wild
		events.append(fainted)
		if not battle.is_trainer_battle():
			_win(events)
			return true
		_award_experience(events)
		var next := battle.next_trainer_creature()
		if next:
			# The trainer sends out the next healthy creature in team order; the turn ends there.
			battle.wild = next
			var sent := BattleEvent.new(BattleEvent.Type.TRAINER_SENT_OUT, BattleSide.Side.WILD)
			sent.creature = next
			events.append(sent)
		else:
			_defeat_trainer(events)
		return true
	if battle.player.current_hp <= 0:
		var fainted := BattleEvent.new(BattleEvent.Type.FAINTED, BattleSide.Side.PLAYER)
		fainted.creature = battle.player
		events.append(fainted)
		if get_first_usable_creature() != null:
			# Losing one creature isn't losing the battle while others can still fight.
			battle.awaiting_switch = true
			events.append(BattleEvent.new(BattleEvent.Type.SWITCH_REQUIRED, BattleSide.Side.PLAYER))
			_set_state(State.SWITCH_REQUIRED)
		else:
			_lose(events)
		return true
	return false


## Beat a wild creature.
func _win(events: Array[BattleEvent]) -> void:
	_set_state(State.VICTORY)
	battle.outcome = BattleContext.OUTCOME_VICTORY
	events.append(BattleEvent.new(BattleEvent.Type.VICTORY, BattleSide.Side.PLAYER))
	_award_experience(events)
	battle_won.emit(battle)


## EXP for the opposing creature that just fainted (each trainer creature counts, like a wild one).
func _award_experience(events: Array[BattleEvent]) -> void:
	var gained := BattleEvent.new(BattleEvent.Type.EXP_GAINED, BattleSide.Side.PLAYER)
	gained.amount = CreatureProgression.exp_reward(battle.wild.level)
	events.append(gained)
	for new_level in CreatureProgression.award_experience(battle.player, gained.amount):
		var level_up := BattleEvent.new(BattleEvent.Type.LEVEL_UP, BattleSide.Side.PLAYER)
		level_up.level = new_level
		events.append(level_up)


## Every creature in the trainer's team has fainted: the trainer loses. The reward is paid and the
## win recorded (GameState flag) right here, once, before the battle closes, so the autosave that
## follows the battle contains both.
func _defeat_trainer(events: Array[BattleEvent]) -> void:
	_set_state(State.VICTORY)
	battle.outcome = BattleContext.OUTCOME_TRAINER_DEFEATED
	events.append(BattleEvent.new(BattleEvent.Type.TRAINER_DEFEATED, BattleSide.Side.WILD))
	battle.reward = battle.trainer.reward_coins
	if battle.reward > 0:
		GameSession.wallet.add(battle.reward)
		var paid := BattleEvent.new(BattleEvent.Type.REWARD, BattleSide.Side.PLAYER)
		paid.amount = battle.reward
		events.append(paid)
	GameState.set_flag(battle.trainer.get_defeated_flag(), true)
	battle_won.emit(battle)


## Only reached when no party creature can fight any more.
func _lose(events: Array[BattleEvent]) -> void:
	_set_state(State.DEFEAT)
	battle.outcome = BattleContext.OUTCOME_DEFEAT
	events.append(BattleEvent.new(BattleEvent.Type.NO_USABLE_CREATURES, BattleSide.Side.PLAYER))
	events.append(BattleEvent.new(BattleEvent.Type.DEFEAT, BattleSide.Side.PLAYER))
	battle_lost.emit(battle)


func _set_state(new_state: State) -> void:
	state = new_state
