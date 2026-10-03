class_name BattleStatusPanel
extends PanelContainer
## Name, level and HP (optionally HP numbers and EXP) for one side of a battle.

const HP_HIGH := Color(0.42, 0.78, 0.36)
const HP_MID := Color(0.95, 0.78, 0.3)
const HP_LOW := Color(0.9, 0.32, 0.26)

@export var show_hp_numbers := false
@export var show_exp := false

var _max_hp := 1
var _hp_fill := StyleBoxFlat.new()

@onready var _name_label: Label = %Name
@onready var _level_label: Label = %Level
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _element_tag: PanelContainer = %ElementTag
@onready var _element_label: Label = %ElementLabel
@onready var _exp_bar: ProgressBar = %ExpBar


func _ready() -> void:
	_hp_bar.add_theme_stylebox_override(&"fill", _hp_fill)
	_hp_label.visible = show_hp_numbers
	_exp_bar.get_parent().visible = show_exp


func show_creature(display_name: String, creature: CreatureInstance) -> void:
	_name_label.text = display_name
	_show_element(creature.get_species().element)
	set_level(creature.level, creature.get_max_hp(), creature.current_hp)
	set_exp_ratio(exp_ratio(creature))


func set_level(level: int, max_hp: int, current_hp: int) -> void:
	_level_label.text = "Lv. %d" % level
	_max_hp = maxi(max_hp, 1)
	_hp_bar.max_value = _max_hp
	_set_hp(current_hp)


func animate_hp(from: int, to: int, duration: float) -> void:
	var tween := create_tween()
	tween.tween_method(_set_hp, float(from), float(to), duration)
	await tween.finished


func set_exp_ratio(ratio: float) -> void:
	_exp_bar.value = ratio * _exp_bar.max_value


func animate_exp_ratio(ratio: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_exp_bar, "value", ratio * _exp_bar.max_value, duration)
	await tween.finished


func get_hp_text() -> String:
	return _hp_label.text


func get_element_text() -> String:
	return _element_label.text if _element_tag.visible else ""


static func exp_ratio(creature: CreatureInstance) -> float:
	return float(creature.experience) / CreatureProgression.exp_to_next_level(creature.level)


func _show_element(element: ElementData) -> void:
	_element_tag.visible = element != null
	if element == null:
		return
	_element_label.text = element.display_name.to_upper()
	var tag := StyleBoxFlat.new()
	tag.bg_color = element.color
	tag.set_corner_radius_all(2)
	tag.content_margin_left = 3
	tag.content_margin_right = 3
	_element_tag.add_theme_stylebox_override(&"panel", tag)


func _set_hp(value: float) -> void:
	_hp_bar.value = value
	_hp_label.text = "%d/%d" % [roundi(value), _max_hp]
	var ratio := value / _max_hp
	_hp_fill.bg_color = HP_HIGH if ratio > 0.5 else (HP_MID if ratio > 0.2 else HP_LOW)
