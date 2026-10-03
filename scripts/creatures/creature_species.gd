class_name CreatureSpecies
extends Resource
## What a creature *is*: shared, read-only data. One .tres per species in data/creatures/.
## Nothing about an individual owned creature belongs here; that lives in CreatureInstance.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var element: ElementData
## Short flavour label shown to the player, e.g. "Offensive".
@export var role := ""
@export var sprite: Texture2D

@export_group("Base stats")
@export var base_hp := 1
@export var base_attack := 1
@export var base_defense := 1
@export var base_speed := 1

@export_group("Moves")
## Moves a newly created creature knows. A level-based learnset can replace this later.
@export var starting_moves: Array[MoveData] = []

@export_group("Evolution")
## Species id this evolves into; empty if it doesn't evolve.
@export var evolves_into: StringName
@export var evolution_level := 0


func get_base_stat(stat: CreatureStats.Stat) -> int:
	match stat:
		CreatureStats.Stat.HP:
			return base_hp
		CreatureStats.Stat.ATTACK:
			return base_attack
		CreatureStats.Stat.DEFENSE:
			return base_defense
		_:
			return base_speed
