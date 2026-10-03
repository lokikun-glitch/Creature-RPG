class_name CreatureStats
## Stat names and the stat formula, kept in one place so the UI never computes stats.
##
## Placeholder formula (deterministic, level-based):
##   max HP     = base HP + level * 2
##   other stat = base stat + level

enum Stat { HP, ATTACK, DEFENSE, SPEED }

const DISPLAY_NAMES := {
	Stat.HP: "HP", Stat.ATTACK: "Attack", Stat.DEFENSE: "Defense", Stat.SPEED: "Speed",
}


static func calculate(stat: Stat, base_value: int, level: int) -> int:
	if stat == Stat.HP:
		return base_value + level * 2
	return base_value + level
