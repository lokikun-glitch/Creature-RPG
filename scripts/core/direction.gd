@tool
class_name Direction
## Shared 4-way facing rule, so a character's sprite and its interaction probe always agree.


## Snaps a direction to up/down/left/right. Exact diagonals resolve to vertical.
static func to_cardinal(direction: Vector2) -> Vector2:
	if direction.is_zero_approx():
		return Vector2.ZERO
	if absf(direction.x) > absf(direction.y):
		return Vector2.RIGHT if direction.x > 0 else Vector2.LEFT
	return Vector2.DOWN if direction.y > 0 else Vector2.UP
