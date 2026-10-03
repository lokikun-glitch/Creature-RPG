class_name Interactable
extends Area2D
## Makes its parent usable with the interact key. Instance scenes/interaction/interactable.tscn
## (it sits on the "interactable" physics layer). Behaviour comes from `dialogue` and/or whatever
## the owner connects to `interacted`, so this node never needs to know what it is attached to.

signal interacted(actor: Node2D)

@export var interaction_name := ""
@export var interaction_enabled := true
## How far ahead of the player (px, measured along their facing) this can be used from.
@export var interaction_distance := 20.0
## When several interactables are in front of the player, the highest priority wins.
@export var interaction_priority := 0
## Shown when used. Optional: owners can handle `interacted` instead of, or as well as, this.
@export var dialogue: DialogueData
## Turn off for things meant to be used across solid geometry, e.g. a shopkeeper behind a counter.
@export var requires_line_of_sight := true
## Where the interaction prompt appears, relative to this node.
@export var prompt_offset := Vector2(0, -20)


func can_interact() -> bool:
	return interaction_enabled


func interact(actor: Node2D) -> void:
	if not can_interact():
		return
	interacted.emit(actor)
	if dialogue:
		DialogueManager.start(dialogue)


## The body this belongs to. Line-of-sight checks ignore it so an object never blocks itself.
func get_owner_body() -> CollisionObject2D:
	return get_parent() as CollisionObject2D
