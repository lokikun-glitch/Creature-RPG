class_name CreatureProgression
## Experience and levelling for owned creatures.
##
## Placeholder formulas:
##   EXP for defeating a creature   = max(1, its level * 10)
##   EXP to go from level L to L+1  = L * L * 10
## CreatureInstance.experience is the progress *within* the current level, so a fresh level-5
## creature has 0 and needs 250 more to reach level 6.


static func exp_reward(defeated_level: int) -> int:
	return maxi(1, defeated_level * 10)


static func exp_to_next_level(level: int) -> int:
	return level * level * 10


## Adds EXP and levels up as many times as it allows. Returns each new level reached, in order.
## Stats are derived from level, so they update automatically; future stat growth hooks in here.
static func award_experience(creature: CreatureInstance, amount: int) -> Array[int]:
	var new_levels: Array[int] = []
	if creature.level >= CreatureInstance.MAX_LEVEL:
		return new_levels
	creature.experience += maxi(amount, 0)
	while creature.level < CreatureInstance.MAX_LEVEL \
			and creature.experience >= exp_to_next_level(creature.level):
		creature.experience -= exp_to_next_level(creature.level)
		var old_max_hp := creature.get_max_hp()
		creature.level += 1
		# Keep damage taken: current HP rises by exactly what max HP gained.
		creature.current_hp = mini(creature.current_hp + creature.get_max_hp() - old_max_hp, creature.get_max_hp())
		new_levels.append(creature.level)
	if creature.level >= CreatureInstance.MAX_LEVEL:
		creature.experience = 0
	return new_levels
