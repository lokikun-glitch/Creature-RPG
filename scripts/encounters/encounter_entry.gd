class_name EncounterEntry
extends Resource
## One possible wild creature in an EncounterTable.

@export var species_id: StringName
@export_range(1, 100) var min_level := 1
@export_range(1, 100) var max_level := 1
## Relative chance compared to the other entries in the same table.
@export_range(0, 1000) var weight := 1
