class_name ElementData
extends Resource
## An element (type). Shared by species and moves. Matchups are data: each element lists which
## element ids its attacks are strong or weak against; anything unlisted is a normal 1x hit.

const SUPER_EFFECTIVE := 2.0
const NOT_VERY_EFFECTIVE := 0.5

@export var id: StringName
@export var display_name := ""
## Used by UI tags and bars.
@export var color := Color.WHITE
## Element ids this element's attacks deal SUPER_EFFECTIVE damage to.
@export var strong_against: Array[StringName] = []
## Element ids this element's attacks deal NOT_VERY_EFFECTIVE damage to.
@export var weak_against: Array[StringName] = []


## Damage multiplier for an attack of this element hitting `defender`.
func effectiveness_against(defender: ElementData) -> float:
	if defender == null:
		return 1.0
	if strong_against.has(defender.id):
		return SUPER_EFFECTIVE
	if weak_against.has(defender.id):
		return NOT_VERY_EFFECTIVE
	return 1.0
