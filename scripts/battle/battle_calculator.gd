class_name BattleCalculator
## Battle maths, kept free of state and presentation so it can be tested directly.
##
## Damage formula (placeholder):
##   base   = ((2 * level / 5 + 2) * power * attack / defense) / 50 + 2
##   damage = floor(base * random_factor * element_multiplier)
## random_factor is 0.85-1.0; element_multiplier comes from ElementData (2x / 1x / 0.5x).
## Any move with power > 0 deals at least 1 damage. Critical hits don't exist yet.
##
## Escape chance (placeholder, wild battles):
##   chance = clamp(0.75 * player_speed / wild_speed + 0.15 * failed_attempts, 0.25, 0.95)
## Equal speed gives 75%, a faster player up to 95%, a much slower one down to 25%.
##
## Capture chance (placeholder):
##   chance = clamp(base_rate * (1 - current_hp / max_hp), 0.02, 0.95)
## base_rate is 0.65: a full-HP creature is a 2% long shot, half HP ~33%, nearly fainted ~65%.
## A creature at 0 HP (or invalid HP) can't be caught: 0.

const MIN_RANDOM_FACTOR := 0.85
const MAX_RANDOM_FACTOR := 1.0
const MIN_ESCAPE_CHANCE := 0.25
const MAX_ESCAPE_CHANCE := 0.95
const CAPTURE_BASE_RATE := 0.65
const MIN_CAPTURE_CHANCE := 0.02
const MAX_CAPTURE_CHANCE := 0.95


## Returns {"damage": int, "effectiveness": float, "critical": bool}.
static func calculate_damage(attacker: CreatureInstance, defender: CreatureInstance, move: MoveData,
		random_factor := 1.0) -> Dictionary:
	var effectiveness := element_multiplier(move, defender)
	if move.power <= 0:
		return {"damage": 0, "effectiveness": effectiveness, "critical": false}
	var attack := float(attacker.get_stat(CreatureStats.Stat.ATTACK))
	var defense := float(maxi(defender.get_stat(CreatureStats.Stat.DEFENSE), 1))
	var base := ((2.0 * attacker.level / 5.0 + 2.0) * move.power * attack / defense) / 50.0 + 2.0
	var damage := floori(base * random_factor * effectiveness)
	return {"damage": maxi(damage, 1), "effectiveness": effectiveness, "critical": false}


## Element multiplier of `move` against `defender` (2.0 / 1.0 / 0.5), from the ElementData chart.
static func element_multiplier(move: MoveData, defender: CreatureInstance) -> float:
	var defender_species := defender.get_species()
	if move.element == null or defender_species == null:
		return 1.0
	return move.element.effectiveness_against(defender_species.element)


static func roll_random_factor(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(MIN_RANDOM_FACTOR, MAX_RANDOM_FACTOR)


static func roll_hit(move: MoveData, rng: RandomNumberGenerator) -> bool:
	return move.accuracy >= 100 or rng.randi_range(1, 100) <= move.accuracy


static func escape_chance(player_speed: int, wild_speed: int, failed_attempts: int) -> float:
	var chance := 0.75 * player_speed / float(maxi(wild_speed, 1)) + 0.15 * failed_attempts
	return clampf(chance, MIN_ESCAPE_CHANCE, MAX_ESCAPE_CHANCE)


static func capture_chance(current_hp: int, max_hp: int, base_rate := CAPTURE_BASE_RATE) -> float:
	if current_hp <= 0 or max_hp <= 0:
		return 0.0
	var health_factor := 1.0 - float(mini(current_hp, max_hp)) / max_hp
	return clampf(base_rate * health_factor, MIN_CAPTURE_CHANCE, MAX_CAPTURE_CHANCE)


## Faster creature acts first; equal speed is a coin flip from `rng`.
static func player_moves_first(player_speed: int, wild_speed: int, rng: RandomNumberGenerator) -> bool:
	if player_speed != wild_speed:
		return player_speed > wild_speed
	return rng.randf() < 0.5
