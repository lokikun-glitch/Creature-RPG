extends Node
## Autoload that decides when wild encounters happen and creates the wild creature.
## It knows nothing about how an encounter is shown or fought: listeners of encounter_started
## (the BattleManager) take over and call end_encounter().

signal encounter_started(encounter: WildEncounter)
signal encounter_ended(encounter: WildEncounter)

## Steps after an encounter during which no new random encounter can happen.
const COOLDOWN_STEPS := 3

## Source of all encounter randomness. Tests replace it with a seeded generator.
var rng := RandomNumberGenerator.new()
## Total valid steps taken inside encounter zones; useful for tests and debugging.
var steps_in_zones := 0
var active_encounter: WildEncounter
## Zone the player is currently inside, if any.
var current_zone: EncounterZone

var _force_next := false
## Debug/test: species and level for the next encounter instead of rolling the table.
var _forced_species := &""
var _forced_level := 0
var _cooldown := 0


func _ready() -> void:
	rng.randomize()


func has_active_encounter() -> bool:
	return active_encounter != null


## Called by an EncounterZone for each step the player walks inside it.
func register_step(zone: EncounterZone) -> void:
	steps_in_zones += 1
	if not zone.encounter_enabled or not _can_start():
		return
	if _force_next:
		_force_next = false
		start_encounter(zone.encounter_table, zone)
	elif _cooldown > 0:
		_cooldown -= 1
	elif roll_encounter(zone.encounter_rate):
		start_encounter(zone.encounter_table, zone)


## True with probability `rate` (0..1).
func roll_encounter(rate: float) -> bool:
	return rng.randf() < rate


## Creates a wild creature from `table`: weighted species pick, then a level within the entry's range.
## The creature belongs to nobody; it is never added to the party here.
func generate_wild_creature(table: EncounterTable) -> CreatureInstance:
	var entry := table.pick_entry(rng) if table else null
	if entry == null:
		return null
	var species := CreatureDatabase.get_species(entry.species_id)
	var level := rng.randi_range(mini(entry.min_level, entry.max_level), maxi(entry.min_level, entry.max_level))
	return CreatureFactory.create_from_species(species, level)


func start_encounter(table: EncounterTable, zone: EncounterZone = null) -> WildEncounter:
	if not _can_start():
		return null
	var creature := _take_forced_creature() if not _forced_species.is_empty() else generate_wild_creature(table)
	if creature == null:
		push_warning("EncounterManager: table '%s' has no usable entries." % (table.id if table else &""))
		return null
	var map := zone.get_map() if zone else null
	active_encounter = WildEncounter.new(creature, table, map.map_id if map else &"", zone)
	encounter_started.emit(active_encounter)
	return active_encounter


func end_encounter() -> void:
	if active_encounter == null:
		return
	var finished := active_encounter
	active_encounter = null
	_cooldown = COOLDOWN_STEPS
	encounter_ended.emit(finished)


## Development/testing: the next valid step in an encounter zone always triggers an encounter.
func force_next_encounter() -> void:
	_force_next = true


## Development/testing: the next valid step in an encounter zone always triggers an encounter
## with this registered species at this level, regardless of the zone's table.
func force_next_encounter_species(species_id: StringName, level: int) -> void:
	_forced_species = species_id
	_forced_level = level
	_force_next = true


## Clears everything for a new session (new game, continue, return to title).
func reset() -> void:
	active_encounter = null
	current_zone = null
	_force_next = false
	_forced_species = &""
	_forced_level = 0
	_cooldown = 0


func _take_forced_creature() -> CreatureInstance:
	var species := CreatureDatabase.get_species(_forced_species)
	var level := _forced_level
	_forced_species = &""
	_forced_level = 0
	return CreatureFactory.create_from_species(species, level) if species else null


func zone_entered(zone: EncounterZone) -> void:
	current_zone = zone


func zone_exited(zone: EncounterZone) -> void:
	if current_zone == zone:
		current_zone = null


func _can_start() -> bool:
	return active_encounter == null and GameSession.state == GameSession.State.PLAYING \
			and not SceneRouter.is_busy() and not DialogueManager.is_active() and party_can_battle()


## Wild creatures only appear once the player has a starter that can still fight.
func party_can_battle() -> bool:
	return GameState.starter_selected \
			and PartyManager.get_party().any(func(c: CreatureInstance) -> bool: return c.current_hp > 0)


func _unhandled_input(event: InputEvent) -> void:
	# DEVELOPMENT ONLY (debug builds): F6 forces a wild encounter, immediately when standing in an
	# encounter zone, otherwise on the next step taken in one.
	if OS.is_debug_build() and event.is_action_pressed(&"debug_force_encounter"):
		get_viewport().set_input_as_handled()
		if current_zone and current_zone.encounter_enabled:
			start_encounter(current_zone.encounter_table, current_zone)
		else:
			force_next_encounter()
