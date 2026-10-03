class_name TrainerData
extends Resource
## An opposing trainer, stored as a .tres in data/trainers/ and registered by TrainerCatalog.
## Immutable template: the team is a list of TrainerCreature entries, never live creatures.
## An NPC becomes this trainer by setting its `trainer_id`.

@export var id: StringName
## The trainer's own name, e.g. "Rory".
@export var display_name := ""
## What kind of trainer, e.g. "Young Trainer". (`class_name` is a GDScript keyword.)
@export var trainer_class := ""
## Said when the player talks to them while they can still battle; the battle starts afterwards.
@export var dialogue_before: DialogueData
## Said once they have been defeated.
@export var dialogue_after: DialogueData
## In order: the first one leads, the next healthy one comes out when one faints.
@export var team: Array[TrainerCreature] = []
## Coins paid to the player for winning, once.
@export_range(0, 99999) var reward_coins := 0


## "Young Trainer Rory".
func get_title() -> String:
	return ("%s %s" % [trainer_class, display_name]).strip_edges()


## The GameState flag recording a win against this trainer, e.g. trainer_hiker_defeated.
func get_defeated_flag() -> StringName:
	return defeated_flag_for(id)


func is_defeated() -> bool:
	return GameState.get_flag(get_defeated_flag(), false) == true


static func defeated_flag_for(trainer_id: StringName) -> StringName:
	return StringName("trainer_%s_defeated" % trainer_id)
