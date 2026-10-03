class_name StarterCard
extends PanelContainer
## One option on the starter screen. Display only: shows a species and whether it's highlighted.

signal clicked(card: StarterCard)

const DIMMED := Color(0.6, 0.6, 0.68)

@export var normal_style: StyleBox
@export var selected_style: StyleBox

var species: CreatureSpecies

var _selected := false
var _time := 0.0

@onready var _sprite: TextureRect = %Sprite
@onready var _name_label: Label = %NameLabel
@onready var _element_tag: PanelContainer = %ElementTag
@onready var _element_label: Label = %ElementLabel
@onready var _role_label: Label = %RoleLabel


func setup(option: CreatureSpecies) -> void:
	species = option
	_sprite.texture = option.sprite
	_name_label.text = option.display_name.to_upper()
	_role_label.text = option.role
	if option.element:
		_element_label.text = option.element.display_name.to_upper()
		var tag := StyleBoxFlat.new()
		tag.bg_color = option.element.color
		tag.set_corner_radius_all(2)
		tag.content_margin_left = 4
		tag.content_margin_right = 4
		_element_tag.add_theme_stylebox_override(&"panel", tag)
	set_selected(false)


func set_selected(selected: bool) -> void:
	_selected = selected
	_time = 0.0
	add_theme_stylebox_override(&"panel", selected_style if selected else normal_style)
	modulate = Color.WHITE if selected else DIMMED
	_sprite.position.y = 0.0


func _process(delta: float) -> void:
	if _selected:
		_time += delta
		_sprite.position.y = -absf(roundf(sin(_time * 5.0) * 2.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()
