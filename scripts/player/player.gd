class_name Player
extends CharacterBody2D
## Top-down player controller with smoothed 8-direction movement.
## Knows nothing about maps: the World positions it and hands its camera the map bounds.

const GROUP := &"player"

@export var max_speed := 80.0
@export var acceleration := 800.0
@export var friction := 1000.0

## Last movement direction; the InteractionManager uses it to find what the player is facing.
var facing := Vector2.DOWN
var controls_enabled: bool:
	get:
		return _control_locks.is_empty()

# Independent systems (map transitions, dialogue, menus) each hold their own lock,
# so one finishing can't re-enable movement while another is still running.
var _control_locks := {}

@onready var camera: PlayerCamera = $Camera
@onready var _sprite: CharacterSprite = $Sprite
@onready var _interaction: InteractionManager = $InteractionManager


func _enter_tree() -> void:
	add_to_group(GROUP)


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

	if input.is_zero_approx():
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	else:
		facing = input.normalized()
		velocity = velocity.move_toward(input * max_speed, acceleration * delta)
	move_and_slide()

	_sprite.face(facing)
	_sprite.set_walking(not input.is_zero_approx() and get_real_velocity().length() > 5.0)
	_interaction.facing = facing
	_interaction.active = controls_enabled


func _unhandled_input(event: InputEvent) -> void:
	if controls_enabled and event.is_action_pressed(&"interact"):
		if _interaction.try_interact(self):
			get_viewport().set_input_as_handled()


func add_control_lock(source: StringName) -> void:
	_control_locks[source] = true
	velocity = Vector2.ZERO


func remove_control_lock(source: StringName) -> void:
	_control_locks.erase(source)


func teleport(target: Vector2, face_direction: Vector2) -> void:
	global_position = target
	velocity = Vector2.ZERO
	facing = face_direction
	_sprite.face(face_direction)
	_sprite.set_walking(false)
	reset_physics_interpolation()
