class_name InteractionManager
extends Node2D
## Finds the Interactable directly in front of its parent, using the parent's position and facing.
## Place it at the centre of the parent's collision shape. The owner sets `facing` and `active`
## every physics frame and calls try_interact() when the interact key is pressed.

signal target_changed(target: Interactable)

const WORLD_MASK := 1 << 0
const INTERACTABLE_MASK := 1 << 3

## Length of the probe ahead of the parent. Each Interactable may further limit its own reach.
@export var probe_length := 32.0
@export var probe_width := 6.0

var facing := Vector2.DOWN
var active := true
## What E would interact with right now; also what the prompt shows.
var target: Interactable

var _probe_horizontal := RectangleShape2D.new()
var _probe_vertical := RectangleShape2D.new()


func _ready() -> void:
	_probe_horizontal.size = Vector2(probe_length, probe_width)
	_probe_vertical.size = Vector2(probe_width, probe_length)


func _physics_process(_delta: float) -> void:
	var found := find_target() if active else null
	if found != target:
		target = found
		target_changed.emit(found)


func try_interact(actor: Node2D) -> bool:
	if not is_instance_valid(target) or not target.can_interact():
		return false
	target.interact(actor)
	return true


func find_target() -> Interactable:
	var direction := Direction.to_cardinal(facing)
	if direction == Vector2.ZERO:
		return null
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _probe_horizontal if direction.x != 0.0 else _probe_vertical
	query.transform = Transform2D(0.0, global_position + direction * probe_length / 2.0)
	query.collision_mask = INTERACTABLE_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var best: Interactable
	var best_score := INF
	for hit in space.intersect_shape(query, 16):
		var candidate := hit.collider as Interactable
		if candidate == null or not candidate.can_interact():
			continue
		var offset := candidate.global_position - global_position
		var along := offset.dot(direction)
		var lateral := absf(offset.dot(direction.orthogonal()))
		# Ahead, in reach, and inside a 45° cone, so things beside the player never count.
		if along <= 0.0 or along > candidate.interaction_distance or lateral >= along:
			continue
		if candidate.requires_line_of_sight and not _has_line_of_sight(candidate):
			continue
		# Straight ahead beats off-centre, then nearer beats farther.
		var score := along + lateral * 2.0
		if best == null or candidate.interaction_priority > best.interaction_priority \
				or (candidate.interaction_priority == best.interaction_priority and score < best_score):
			best = candidate
			best_score = score
	return best


func _has_line_of_sight(candidate: Interactable) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, candidate.global_position, WORLD_MASK)
	var body := candidate.get_owner_body()
	if body:
		query.exclude = [body.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()
