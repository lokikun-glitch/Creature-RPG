class_name BattleContext
extends RefCounted
## Who is fighting in the current battle. `player` is the real party CreatureInstance, so damage
## and EXP apply to it directly; `wild` is the encounter's temporary creature.

var encounter: WildEncounter
var player: CreatureInstance
var wild: CreatureInstance
var turn := 0
## Escape attempts that failed so far; each one makes the next more likely to succeed.
var failed_escapes := 0
const OUTCOME_VICTORY := &"victory"
const OUTCOME_DEFEAT := &"defeat"
const OUTCOME_ESCAPED := &"escaped"
const OUTCOME_CAUGHT := &"caught"

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
	wild = from_encounter.creature


func is_finished() -> bool:
	return not outcome.is_empty()


func creature(side: BattleSide.Side) -> CreatureInstance:
	return player if side == BattleSide.Side.PLAYER else wild


func opponent(side: BattleSide.Side) -> BattleSide.Side:
	return BattleSide.Side.WILD if side == BattleSide.Side.PLAYER else BattleSide.Side.PLAYER


func display_name(side: BattleSide.Side) -> String:
	var name := creature(side).get_display_name()
	return name if side == BattleSide.Side.PLAYER else "Wild " + name
