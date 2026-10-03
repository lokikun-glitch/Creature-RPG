class_name WildEncounter
extends RefCounted
## Runtime state of the current wild encounter. Temporary: never saved and never part of the party.

var creature: CreatureInstance
var table: EncounterTable
## Map the encounter happened on (GameMap.map_id).
var source_map_id: StringName
## Zone that triggered it; only valid while that map is loaded.
var source_zone: EncounterZone


func _init(wild_creature: CreatureInstance, from_table: EncounterTable, map_id: StringName,
		zone: EncounterZone) -> void:
	creature = wild_creature
	table = from_table
	source_map_id = map_id
	source_zone = zone
