@tool
class_name NPC
extends CharacterBody2D
## A person standing in the world. Talking to them goes through the shared Interactable child,
## so each NPC only needs its own dialogue resource. They turn to face whoever talks to them and
## keep that facing afterwards.
##
## Trainers: set `trainer_id` to a TrainerCatalog id and the NPC becomes that trainer, with no new
## script. Until beaten they say the trainer's before-battle lines and then BattleManager starts the
## battle; afterwards they say the after-battle lines. While they can still be battled a small "!"
## shows above them. If the player has no creature able to fight, they use their ordinary dialogue.
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
## Optional TrainerCatalog id. Empty means an ordinary NPC.
@export var trainer_id: StringName:
	set(value):
		trainer_id = value
		_apply_dialogue()
		queue_redraw()

const MARKER_COLOR := Color("e8574f")
const MARKER_OUTLINE := Color("222034")

## True between a trainer's challenge lines and the battle they lead to.
var _challenging := false


func _ready() -> void:
	_apply_look()
	if Engine.is_editor_hint():
		return
	var interactable := $Interactable as Interactable
	interactable.interaction_name = display_name
	interactable.interacted.connect(_on_interacted)
	_apply_dialogue()
	if not trainer_id.is_empty():
		DialogueManager.dialogue_finished.connect(_on_dialogue_finished)
		GameState.flag_changed.connect(func(_flag: StringName, _value: Variant) -> void: queue_redraw())


## The TrainerData this NPC battles as, or null for an ordinary NPC (or an unknown id).
func get_trainer() -> TrainerData:
	return TrainerCatalog.get_trainer(trainer_id) if not trainer_id.is_empty() else null


## True for a trainer who hasn't been beaten yet (shown with a "!" marker).
func is_undefeated_trainer() -> bool:
	var trainer := get_trainer()
	return trainer != null and not trainer.is_defeated()


## What this NPC would say right now, given the story flags and, for trainers, whether they've
## been beaten and whether the player can battle.
func get_current_dialogue() -> DialogueData:
	var trainer := get_trainer()
	if trainer:
		if trainer.is_defeated():
			return trainer.dialogue_after
		if BattleManager.can_start_trainer_battle():
			return trainer.dialogue_before
	if alternate_dialogue and GameState.get_flag(alternate_flag, false) == true:
		return alternate_dialogue
	return dialogue


func _apply_dialogue() -> void:
	var interactable := get_node_or_null(^"Interactable") as Interactable
	if interactable == null or Engine.is_editor_hint():
		return
	interactable.dialogue = dialogue
	interactable.interaction_enabled = dialogue != null or not trainer_id.is_empty()


func _on_interacted(actor: Node2D) -> void:
	facing = (actor.global_position - global_position).normalized()
	# The Interactable starts its dialogue right after this signal, so pick the line now.
	var line := get_current_dialogue()
	($Interactable as Interactable).dialogue = line
	var trainer := get_trainer()
	_challenging = trainer != null and line == trainer.dialogue_before


func _on_dialogue_finished(finished: DialogueData) -> void:
	var trainer := get_trainer()
	if not _challenging or trainer == null or finished != trainer.dialogue_before:
		return
	_challenging = false
	BattleManager.start_trainer_battle(trainer)


func _draw() -> void:
	# A small "!" above trainers who can still be battled. Beaten trainers have none.
	var show_marker := not trainer_id.is_empty() if Engine.is_editor_hint() else is_undefeated_trainer()
	if not show_marker:
		return
	draw_rect(Rect2(-2, -31, 5, 9), MARKER_OUTLINE)
	draw_rect(Rect2(-1, -30, 3, 7), Color.WHITE)
	draw_rect(Rect2(0, -29, 1, 4), MARKER_COLOR)
	draw_rect(Rect2(0, -24, 1, 1), MARKER_COLOR)


func _apply_look() -> void:
	var sprite := get_node_or_null(^"Sprite") as CharacterSprite
	if sprite == null:
		return
	if sprite_sheet:
		sprite.texture = sprite_sheet
	sprite.face(facing)
