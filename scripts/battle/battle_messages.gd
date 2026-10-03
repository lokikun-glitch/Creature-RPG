class_name BattleMessages
## Every battle message in one place, as templates. Turns BattleEvents into the lines shown in
## the battle text box.

const WILD_APPEARED := "A wild {name} appeared!"
const SEND_OUT := "Go, {name}!"
const PROMPT := "What should {name} do?"
const MOVE_USED := "{user} used {move}!"
const MISSED := "{user}'s attack missed!"
const SUPER_EFFECTIVE := "Super effective!"
const NOT_VERY_EFFECTIVE := "Not very effective..."
const DAMAGE := "{target} took {amount} damage!"
const FAINTED := "{target} fainted!"
const VICTORY := "{name} won the battle!"
const EXP_GAINED := "{name} gained {amount} EXP!"
const LEVEL_UP := "{name} grew to level {level}!"
const NO_USABLE_CREATURES := "Your team has no other available creatures."
const ESCAPED := "Got away safely!"
const ESCAPE_FAILED := "You couldn't get away!"
const ALREADY_IN_BATTLE := "{name} is already in battle!"
const NO_ENERGY := "{name} has no energy left to battle!"
const ONLY_ONE_CREATURE := "Only one creature is available."
const NO_ITEMS := "You have no items."
const RECALLED := "{name}, come back!"
const CAPTURE_THROWN := "You threw a {item}!"
const CAPTURE_SUCCEEDED := "{name} was caught!"
const CAPTURE_FAILED := "Oh no! {name} broke free!"
const JOINED_PARTY := "{name} joined your team!"
const PARTY_FULL := "Your party is full."
const SENT_TO_STORAGE := "{name} was sent to storage."
const SWITCH_REQUIRED := "Choose a creature to send out."
const OUT_OF_ITEM := "Out of {item}s."
const CANT_CATCH := "It can't be caught right now."
const TRAINER_CHALLENGE := "{trainer} challenges you!"
const TRAINER_SENT_OUT := "{trainer} sent out {name}!"
const TRAINER_DEFEATED := "You defeated {trainer}!"
const REWARD := "You received {amount} Coins!"
const CANT_CAPTURE_TRAINER := "You can't capture another Trainer's creature."
const CANT_RUN_TRAINER := "You can't run from a Trainer battle!"
const FAINTED_TAG := "Fainted"
const ACTIVE_TAG := "Active"


## Short matchup label for the move menu, from a multiplier BattleCalculator produced.
static func effectiveness_label(multiplier: float) -> String:
	if multiplier > 1.0:
		return "Effective"
	if multiplier < 1.0:
		return "Not very effective"
	return "Normal"


static func describe(event: BattleEvent, battle: BattleContext) -> PackedStringArray:
	var who := battle.name_of(event.creature, event.side) if event.creature else battle.display_name(event.side)
	var trainer := battle.trainer.get_title() if battle.trainer else ""
	match event.type:
		BattleEvent.Type.MOVE_USED:
			var move := CreatureDatabase.get_move(event.move_id)
			return [MOVE_USED.format({"user": who, "move": move.display_name if move else String(event.move_id)})]
		BattleEvent.Type.MISSED:
			return [MISSED.format({"user": who})]
		BattleEvent.Type.DAMAGE:
			# Damage first, then how effective it was.
			var lines := PackedStringArray([DAMAGE.format({"target": who, "amount": event.amount})])
			if event.effectiveness > 1.0:
				lines.append(SUPER_EFFECTIVE)
			elif event.effectiveness < 1.0:
				lines.append(NOT_VERY_EFFECTIVE)
			return lines
		BattleEvent.Type.FAINTED:
			return [FAINTED.format({"target": who})]
		BattleEvent.Type.VICTORY:
			return [VICTORY.format({"name": who})]
		BattleEvent.Type.EXP_GAINED:
			return [EXP_GAINED.format({"name": who, "amount": event.amount})]
		BattleEvent.Type.LEVEL_UP:
			return [LEVEL_UP.format({"name": who, "level": event.level})]
		BattleEvent.Type.NO_USABLE_CREATURES:
			return [NO_USABLE_CREATURES]
		BattleEvent.Type.ESCAPED:
			return [ESCAPED]
		BattleEvent.Type.ESCAPE_FAILED:
			return [ESCAPE_FAILED]
		BattleEvent.Type.RECALLED:
			return [RECALLED.format({"name": event.creature.get_display_name()})]
		BattleEvent.Type.SENT_OUT:
			return [SEND_OUT.format({"name": event.creature.get_display_name()})]
		BattleEvent.Type.TRAINER_SENT_OUT:
			return [TRAINER_SENT_OUT.format({"trainer": trainer, "name": event.creature.get_display_name()})]
		BattleEvent.Type.TRAINER_DEFEATED:
			return [TRAINER_DEFEATED.format({"trainer": trainer})]
		BattleEvent.Type.REWARD:
			return [REWARD.format({"amount": event.amount})]
		BattleEvent.Type.CAPTURE_THROWN:
			var item := ItemCatalog.get_item(event.move_id)
			return [CAPTURE_THROWN.format({"item": item.display_name if item else String(event.move_id)})]
		BattleEvent.Type.CAPTURE_SUCCEEDED:
			return [CAPTURE_SUCCEEDED.format({"name": battle.wild.get_display_name()})]
		BattleEvent.Type.CAPTURE_FAILED:
			return [CAPTURE_FAILED.format({"name": battle.wild.get_display_name()})]
		BattleEvent.Type.JOINED_PARTY:
			return [JOINED_PARTY.format({"name": event.creature.get_display_name()})]
		BattleEvent.Type.SENT_TO_STORAGE:
			return [PARTY_FULL, SENT_TO_STORAGE.format({"name": event.creature.get_display_name()})]
		BattleEvent.Type.SWITCH_REQUIRED:
			return [SWITCH_REQUIRED]
	return []
