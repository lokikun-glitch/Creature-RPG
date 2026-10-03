class_name CreatureRow
extends RefCounted
## How one creature is summarised in a MenuList row, shared by the party and storage screens:
## nickname, species, level, HP, element, status and a LEAD tag. Display only.

const EMPTY := "Empty"
const LEAD_TAG := "LEAD"
const STATUS_OK := "OK"
const STATUS_FAINTED := "Fainted"


static func cells(creature: CreatureInstance, is_lead := false, highlight := false) -> Array:
	var species := creature.get_species()
	var element := species.element if species else null
	var fainted := creature.current_hp <= 0
	return [
		{"text": creature.get_display_name(), "expand": true, "clip": true,
				"color": UiStyle.ACCENT if highlight else UiStyle.TEXT},
		{"text": species.display_name if species else String(creature.species_id), "width": 50, "clip": true,
				"color": UiStyle.TEXT_DIM},
		{"text": "Lv %d" % creature.level, "width": 24},
		{"text": "%d/%d" % [creature.current_hp, creature.get_max_hp()], "width": 32,
				"align": HORIZONTAL_ALIGNMENT_RIGHT, "color": UiStyle.BAD if fainted else UiStyle.TEXT},
		{"text": element.display_name if element else "", "width": 34,
				"color": element.color if element else UiStyle.TEXT},
		{"text": status_text(creature), "width": 30, "color": UiStyle.BAD if fainted else UiStyle.TEXT_DIM},
		{"text": LEAD_TAG if is_lead else "", "width": 20, "color": UiStyle.ACCENT},
	]


static func empty_cells() -> Array:
	return [{"text": EMPTY, "expand": true, "color": UiStyle.TEXT_DISABLED}]


## "Fainted" at 0 HP, otherwise the status, or "OK" for none.
static func status_text(creature: CreatureInstance) -> String:
	if creature.current_hp <= 0:
		return STATUS_FAINTED
	return String(creature.status).capitalize() if not creature.status.is_empty() else STATUS_OK
