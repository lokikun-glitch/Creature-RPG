class_name PlayerCamera
extends Camera2D
## Follows the player and stays inside the current map.


## Maps smaller than the screen are centred rather than pinned to the top-left corner.
func set_bounds(bounds: Rect2) -> void:
	var view_size := get_viewport_rect().size / zoom
	var pad := (view_size - bounds.size).max(Vector2.ZERO) / 2.0
	var area := bounds.grow_individual(pad.x, pad.y, pad.x, pad.y)
	limit_left = floori(area.position.x)
	limit_top = floori(area.position.y)
	limit_right = ceili(area.end.x)
	limit_bottom = ceili(area.end.y)
