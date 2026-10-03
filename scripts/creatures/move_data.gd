class_name MoveData
extends Resource
## A move as shared data. Owned creatures reference moves by id; BattleManager resolves them.

@export var id: StringName
@export var display_name := ""
@export var element: ElementData
@export var power := 0
## Chance to hit, in percent. 100 never misses.
@export_range(1, 100) var accuracy := 100
@export_multiline var description := ""
