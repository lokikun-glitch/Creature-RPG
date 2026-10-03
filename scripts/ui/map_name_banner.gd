class_name MapNameBanner
extends PanelContainer
## Briefly shows the name of the map the player just entered.

@export var hold_time := 1.8

var _tween: Tween

@onready var _label: Label = $Label


func show_for_map(map: GameMap) -> void:
	if map.display_name.is_empty():
		return
	_label.text = map.display_name
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	_tween.tween_interval(hold_time)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
