class_name BattleContext
extends RefCounted
## Who is fighting in the current battle. `player` is the real party CreatureInstance, so damage
## and EXP apply to it directly. `wild` is the opposing creature currently out (BattleSide.WILD is
## the opposing side): the encounter's creature, or the trainer's active one. Opposing creatures
## are always temporary and never saved.

## Where the battle came from: SOURCE_WILD (an encounter) or SOURCE_TRAINER (a trainer's challenge).
## Rules that differ (catching, running, rewards) check this, never the UI.
const SOURCE_WILD := &"wild"
const SOURCE_TRAINER := &"trainer"

var source := SOURCE_WILD
## Null for trainer battles.
var encounter: WildEncounter
var player: CreatureInstance
var wild: CreatureInstance
## Trainer battles only: who is battling, and their temporary team in order (the creatures
## CreatureFactory.create_from_trainer() made for this battle).
var trainer: TrainerData
var trainer_team: Array[CreatureInstance] = []
## Coins paid to the player for winning (trainer battles); 0 otherwise.
var reward := 0
var turn := 0
## Escape attempts that failed so far; each one makes the next more likely to succeed.
var failed_escapes := 0
const OUTCOME_VICTORY := &"victory"
const OUTCOME_DEFEAT := &"defeat"
const OUTCOME_ESCAPED := &"escaped"
const OUTCOME_CAUGHT := &"caught"
## The player beat a trainer (every creature in the trainer's team fainted). OUTCOME_DEFEAT
## always means the player lost.
const OUTCOME_TRAINER_DEFEATED := &"trainer_defeated"

## How the battle ended: one of the OUTCOME_* constants, empty while the battle is running.
var outcome := &""
## The owned creature made from the wild one when it was caught (null otherwise).
var caught_creature: CreatureInstance
## True when the active creature has fainted but the player still has others: the player must
## switch in a new one. Distinct from losing, which only happens when nobody can fight.
var awaiting_switch := false


func _init(from_encounter: WildEncounter, player_creature: CreatureInstance) -> void:
	encounter = from_encounter
	player = player_creature
	wild = from_encounter.creature if from_encounter else null


## A battle against `trainer_data`, whose temporary `team` was built for it.
static func for_trainer(trainer_data: TrainerData, team: Array[CreatureInstance],
		player_creature: CreatureInstance) -> BattleContext:
	var context := BattleContext.new(null, player_creature)
	context.source = SOURCE_TRAINER
	context.trainer = trainer_data
	context.trainer_team = team
	context.wild = team[0]
	return context


func is_trainer_battle() -> bool:
	return source == SOURCE_TRAINER


## The trainer's next creature that can still fight, in team order, or null.
func next_trainer_creature() -> CreatureInstance:
	for creature in trainer_team:
		if creature.current_hp > 0:
			return creature
	return null


## How many of the trainer's creatures can still fight.
func trainer_creatures_left() -> int:
	return trainer_team.filter(func(c: CreatureInstance) -> bool: return c.current_hp > 0).size()


func is_finished() -> bool:
	return not outcome.is_empty()


func creature(side: BattleSide.Side) -> CreatureInstance:
	return player if side == BattleSide.Side.PLAYER else wild


func opponent(side: BattleSide.Side) -> BattleSide.Side:
	return BattleSide.Side.WILD if side == BattleSide.Side.PLAYER else BattleSide.Side.PLAYER


func display_name(side: BattleSide.Side) -> String:
	return name_of(creature(side), side)


## How a creature on `side` is named in messages: "Wild Pebblit" in wild battles; a trainer's
## creature by its nickname, or its species name if it has none.
func name_of(who: CreatureInstance, side: BattleSide.Side) -> String:
	var name := who.get_display_name()
	return "Wild " + name if side == BattleSide.Side.WILD and not is_trainer_battle() else name
