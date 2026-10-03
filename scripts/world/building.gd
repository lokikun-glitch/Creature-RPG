@tool
class_name Building
extends StaticBody2D
## Placeholder building drawn from its exported properties, so new houses need no art.
## The origin is the bottom-centre of the front wall (where the door is), which keeps Y-sorting correct.

const TILE := 16
const OUTLINE := Color("222034")
## Collision matches the drawing, so the player's sprite never overlaps the building: the body
## covers the roof and walls (the roof hangs 2 px past each wall), grown by how far a character
## sprite reaches past its feet collision (1 px sideways, 2 px above the head, 12 px in front of
## the feet; the same rule as the NPC body). Only the doorway is left open, so the player can
## still step up to the door.
const SIDE_MARGIN := 3
const TOP_MARGIN := 2
const FRONT_DEPTH := 12
## Width of the opening in front of the door (the door itself is 12 px wide).
const DOORWAY_WIDTH := 14

@export var size_tiles := Vector2i(6, 5):
	set(value):
		size_tiles = value.max(Vector2i(3, 3))
		_refresh()
@export var roof_color := Color("b4475c"):
	set(value):
		roof_color = value
		_refresh()
@export var wall_color := Color("eadfc4"):
	set(value):
		wall_color = value
		_refresh()
@export var door_color := Color("7a4e30"):
	set(value):
		door_color = value
		_refresh()
@export var label_text := "":
	set(value):
		label_text = value
		_refresh()

@export_group("Door")
## Map entered through the door. Leave empty for a door that can't be entered yet.
@export_file("*.tscn") var door_target_map := ""
@export var door_target_spawn: StringName
## Off: walking into the door enters. On: the player must face the door and press interact.
@export var enter_on_interact := false
## Shown when the player interacts with a door that has no target map.
@export var locked_dialogue: DialogueData
## Id of the spawn point just outside this door, so other maps can send the player here.
@export var exit_spawn_id: StringName


func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		return
	var has_target := not door_target_map.is_empty()
	var door := $Door as MapTransition
	door.target_map = "" if enter_on_interact else door_target_map
	door.target_spawn = door_target_spawn

	var door_interactable := $DoorInteractable as Interactable
	if has_target and enter_on_interact:
		door_interactable.interacted.connect(_on_door_interacted)
	elif not has_target:
		door_interactable.dialogue = locked_dialogue
	door_interactable.interaction_enabled = \
			(has_target and enter_on_interact) or (not has_target and locked_dialogue != null)

	($ExitSpawn as SpawnPoint).spawn_id = exit_spawn_id


func _on_door_interacted(_actor: Node2D) -> void:
	SceneRouter.go_to(door_target_map, door_target_spawn)


func _refresh() -> void:
	queue_redraw()
	var shape_node := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return
	var half_width := size_tiles.x * TILE / 2.0 + SIDE_MARGIN
	var body_height := size_tiles.y * TILE + TOP_MARGIN
	(shape_node.shape as RectangleShape2D).size = Vector2(half_width * 2.0, body_height)
	shape_node.position = Vector2(0, -body_height / 2.0)
	# The strip in front of the wall, either side of the doorway.
	var strip_width := half_width - DOORWAY_WIDTH / 2.0
	for side in [-1.0, 1.0]:
		var strip := _front_strip(&"FrontLeft" if side < 0.0 else &"FrontRight")
		(strip.shape as RectangleShape2D).size = Vector2(strip_width, FRONT_DEPTH)
		strip.position = Vector2(side * (DOORWAY_WIDTH / 2.0 + strip_width / 2.0), FRONT_DEPTH / 2.0)


## The collision shape for one front strip, created on first use. Built in code (and never saved
## into the scene) so every building, old or new, gets the same shape from its size.
func _front_strip(strip_name: StringName) -> CollisionShape2D:
	var strip := get_node_or_null(NodePath(strip_name)) as CollisionShape2D
	if strip == null:
		strip = CollisionShape2D.new()
		strip.name = strip_name
		strip.shape = RectangleShape2D.new()
		add_child(strip)
	return strip


func _draw() -> void:
	var w := float(size_tiles.x * TILE)
	var h := float(size_tiles.y * TILE)
	var left := -w / 2.0
	var wall_h := roundf(h * 0.45)

	draw_rect(Rect2(left + 3, -2, w, 5), Color(0, 0, 0, 0.25))
	_box(Rect2(left, -wall_h, w, wall_h), wall_color)
	_draw_windows(left, w, wall_h)
	_box(Rect2(-6, -14, 12, 14), door_color)
	draw_rect(Rect2(2, -8, 2, 2), Color("f2d16b"))

	var roof := Rect2(left - 2, -h, w + 4, h - wall_h + 2)
	_box(roof, roof_color)
	var stripe := roof_color.darkened(0.15)
	for y in range(int(roof.position.y) + 4, int(roof.end.y) - 4, 4):
		draw_rect(Rect2(roof.position.x + 1, y, roof.size.x - 2, 1), stripe)
	draw_rect(Rect2(roof.position.x + 1, roof.end.y - 4, roof.size.x - 2, 3), roof_color.darkened(0.3))

	if not label_text.is_empty():
		_draw_label(roof)


func _draw_windows(left: float, w: float, wall_h: float) -> void:
	var x := left + 8
	while x + 10 <= left + w - 8:
		# Skip window slots that would overlap the door.
		if absf(x + 5) > 14:
			_box(Rect2(x, -wall_h + 5, 10, 8), Color("8fc7e8"))
			draw_rect(Rect2(x + 5, -wall_h + 6, 1, 6), OUTLINE)
		x += 26


func _draw_label(roof: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 8
	var text_w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var plaque := Rect2(roundf(-text_w / 2.0) - 3, roof.end.y - 16, roundf(text_w) + 6, 10)
	_box(plaque, Color("f4ecd8"))
	draw_string(font, Vector2(plaque.position.x + 3, plaque.end.y - 2), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, OUTLINE)


## Filled rectangle with a crisp 1px outline (draw_rect's unfilled mode blurs at pixel scale).
func _box(rect: Rect2, fill: Color) -> void:
	draw_rect(rect, OUTLINE)
	draw_rect(rect.grow(-1), fill)
