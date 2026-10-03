@tool
class_name NPC
extends CharacterBody2D
## A person standing in the world. Talking to them goes through the shared Interactable child,
## so each NPC only needs its own dialogue resource. They turn to face whoever talks to them and
## keep that facing afterwards.
##
## Collision: the body shape is the space another character's feet can't enter without the two
## sprites overlapping (a character is drawn ~19 px above and 3 px below its feet, 5 px to each
## side). So the player stops just touching the NPC from every side instead of standing inside
## their sprite, and the Interactable's reach is long enough to talk from any of those spots.

@export var npc_id: StringName
@export var display_name := ""
@export var sprite_sheet: Texture2D:
	set(value):
		sprite_sheet = value
		_apply_look()
@export var facing := Vector2.DOWN:
	set(value):
		facing = value
		_apply_look()
## What this NPC says when the player talks to them. No dialogue means they can't be talked to.
## Story events may swap this at runtime.
@export var dialogue: DialogueData:
	set(value):
		dialogue = value
		_apply_dialogue()
## Optional: said instead of `dialogue` once the GameState flag `alternate_flag` is true (e.g. a
## different line after the player has chosen a starter).
@export var alternate_dialogue: DialogueData
@export var alternate_flag: StringName = &"starter_selected"


func _ready() -> void:
	_apply_look()
	if Engine.is_editor_hint():
		return
	var interactable := $Interactable as Interactable
	interactable.interaction_name = display_name
	interactable.interacted.connect(_on_interacted)
	_apply_dialogue()


## What this NPC would say right now, given the story flags.
func get_current_dialogue() -> DialogueData:
	if alternate_dialogue and GameState.get_flag(alternate_flag, false) == true:
		return alternate_dialogue
	return dialogue


func _apply_dialogue() -> void:
	var interactable := get_node_or_null(^"Interactable") as Interactable
	if interactable == null or Engine.is_editor_hint():
		return
	interactable.dialogue = dialogue
	interactable.interaction_enabled = dialogue != null


func _on_interacted(actor: Node2D) -> void:
	facing = (actor.global_position - global_position).normalized()
	# The Interactable starts its dialogue right after this signal, so pick the line now.
	($Interactable as Interactable).dialogue = get_current_dialogue()


func _apply_look() -> void:
	var sprite := get_node_or_null(^"Sprite") as CharacterSprite
	if sprite == null:
		return
	if sprite_sheet:
		sprite.texture = sprite_sheet
	sprite.face(facing)
