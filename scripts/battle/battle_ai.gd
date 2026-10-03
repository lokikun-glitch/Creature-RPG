class_name BattleAI
## Chooses moves for computer-controlled creatures. For now: a random valid move.


## Returns a move id the creature knows and that exists, or &"" if it has none.
static func choose_move(creature: CreatureInstance, rng: RandomNumberGenerator) -> StringName:
	var valid: Array[StringName] = []
	for move_id in creature.move_ids:
		if CreatureDatabase.get_move(move_id):
			valid.append(move_id)
	if valid.is_empty():
		return &""
	return valid[rng.randi_range(0, valid.size() - 1)]
