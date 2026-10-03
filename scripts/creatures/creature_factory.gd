class_name CreatureFactory
## The single place creatures are created: owned ones (starters, caught creatures), wild ones and
## temporary trainer ones. Gift and hatched creatures (and evolution) will go through it too.

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


## Builds a trainer's creature for one battle from its TrainerCreature template: full HP, the
## listed moves (or the species' starting moves if none are listed) and the optional nickname.
## It is temporary and belongs to nobody, so it gets no UID and is never saved. Returns null if
## the species doesn't exist.
static func create_from_trainer(entry: TrainerCreature) -> CreatureInstance:
	var species := CreatureDatabase.get_species(entry.species_id) if entry else null
	if species == null:
		return null
	var creature := create_from_species(species, entry.level)
	creature.uid = ""
	creature.nickname = entry.nickname
	if not entry.move_ids.is_empty():
		creature.move_ids.clear()
		for move_id in entry.move_ids.slice(0, CreatureInstance.MAX_MOVES):
			if CreatureDatabase.get_move(move_id):
				creature.move_ids.append(move_id)
	return creature


static func generate_uid() -> String:
	_uid_counter += 1
	return "%x-%08x-%x" % [int(Time.get_unix_time_from_system() * 1000.0), randi(), _uid_counter]
