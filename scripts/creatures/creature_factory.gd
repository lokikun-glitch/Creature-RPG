class_name CreatureFactory
## The single place owned creatures are created. Starters and caught creatures use it now; gift,
## trainer and hatched creatures (and evolution) will go through it too.

## Makes UIDs unique even when several are generated within the same millisecond.
static var _uid_counter := 0


static func create_from_species(species: CreatureSpecies, level: int) -> CreatureInstance:
	var creature := CreatureInstance.new()
	creature.uid = generate_uid()
	creature.species_id = species.id
	creature.level = clampi(level, 1, CreatureInstance.MAX_LEVEL)
	creature.experience = 0
	# A creature knows at most MAX_MOVES moves; keep the most recently listed ones.
	for move in species.starting_moves.slice(-CreatureInstance.MAX_MOVES):
		if move:
			creature.move_ids.append(move.id)
	creature.current_hp = CreatureStats.calculate(CreatureStats.Stat.HP, species.base_hp, creature.level)
	return creature


## Turns a caught wild creature into an owned one, exactly as it was when caught: same species,
## level, EXP, current HP, moves and status. It gets its own new UID, and its nickname starts as
## the species name.
static func create_from_wild(wild: CreatureInstance) -> CreatureInstance:
	var creature := CreatureInstance.new()
	creature.uid = generate_uid()
	creature.species_id = wild.species_id
	creature.level = wild.level
	creature.experience = wild.experience
	creature.current_hp = wild.current_hp
	creature.move_ids = wild.move_ids.duplicate()
	creature.status = wild.status
	var species := wild.get_species()
	creature.nickname = species.display_name if species else String(wild.species_id)
	return creature


static func generate_uid() -> String:
	_uid_counter += 1
	return "%x-%08x-%x" % [int(Time.get_unix_time_from_system() * 1000.0), randi(), _uid_counter]
