class_name TrainerCreature
extends Resource
## One creature in a trainer's team: a template, not a creature. CreatureFactory.create_from_trainer()
## builds a temporary battle creature from it each time the trainer is fought.

@export var species_id: StringName
@export_range(1, 100) var level := 1
## Optional. Empty means the species name is shown.
@export var nickname := ""
## Optional, but listing moves keeps battles predictable. Empty means the species' starting moves
## (the last CreatureInstance.MAX_MOVES of them, the same rule as any new creature).
@export var move_ids: Array[StringName] = []
