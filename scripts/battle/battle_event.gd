class_name BattleEvent
extends RefCounted
## One thing that happened during a turn. BattleManager produces a list of these; the BattleScene
## plays them back with messages and animations. Rules never wait for the presentation.

enum Type {
	MOVE_USED,
	MISSED,
	DAMAGE,
	FAINTED,
	VICTORY,
	EXP_GAINED,
	LEVEL_UP,
	DEFEAT,
	NO_USABLE_CREATURES,
	ESCAPED,
	ESCAPE_FAILED,
	RECALLED,
	SENT_OUT,
	CAPTURE_THROWN,
	CAPTURE_SUCCEEDED,
	CAPTURE_FAILED,
	JOINED_PARTY,
	SENT_TO_STORAGE,
	SWITCH_REQUIRED,
	TRAINER_SENT_OUT,
	TRAINER_DEFEATED,
	REWARD,
}

var type: Type
## Side the event is about (the attacker for MOVE_USED/MISSED, the target for DAMAGE/FAINTED).
var side: BattleSide.Side
var move_id: StringName
## Damage dealt, EXP gained or Coins received.
var amount := 0
var effectiveness := 1.0
var hp_before := 0
var hp_after := 0
var level := 0
## The creature an event is about. Set whenever it may differ from the side's current creature by
## the time the event is shown (switching, capture, a trainer sending out the next creature).
var creature: CreatureInstance


func _init(event_type: Type, event_side: BattleSide.Side) -> void:
	type = event_type
	side = event_side
