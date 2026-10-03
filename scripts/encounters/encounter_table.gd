class_name EncounterTable
extends Resource
## Which wild creatures can appear somewhere, at what levels and how often.
## One .tres per area in data/encounters/; any EncounterZone can use any table.

@export var id: StringName
@export var entries: Array[EncounterEntry] = []


## Weighted random pick. Entries with unknown species or no weight are never chosen.
func pick_entry(rng: RandomNumberGenerator) -> EncounterEntry:
	var total := get_total_weight()
	if total <= 0:
		return null
	return entry_for_roll(rng.randi_range(1, total))


## The entry a weighted roll in 1..get_total_weight() lands on. Each usable entry owns exactly
## `weight` consecutive roll values, which makes the weighting provable without statistics.
func entry_for_roll(roll: int) -> EncounterEntry:
	for entry in get_usable_entries():
		roll -= entry.weight
		if roll <= 0:
			return entry
	return null


func get_total_weight() -> int:
	var total := 0
	for entry in get_usable_entries():
		total += entry.weight
	return total


func get_usable_entries() -> Array[EncounterEntry]:
	var usable: Array[EncounterEntry] = []
	for entry in entries:
		if entry and entry.weight > 0 and CreatureDatabase.get_species(entry.species_id):
			usable.append(entry)
	return usable
