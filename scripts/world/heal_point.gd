class_name HealPoint
extends Node2D
## Somewhere to rest (e.g. the player's bed). Asks first (default No); on Yes, CreatureManagement
## restores every owned creature, party and storage, and autosaves only if anything was healed.
## Uses the shared Interactable, so it behaves like any other object you press E on.

@export var question := "Rest and restore your creatures?"
## Shown after resting when something was healed.
@export var rested_dialogue: DialogueData
## Shown after resting when everyone was already at full health.
@export var already_rested_dialogue: DialogueData
@export var prompt_scene: PackedScene = preload("res://scenes/ui/confirm_prompt.tscn")

var _prompt: ConfirmPrompt


func _ready() -> void:
	($Interactable as Interactable).interacted.connect(_on_interacted)


## The open Yes/No question, or null.
func get_prompt() -> ConfirmPrompt:
	return _prompt if is_instance_valid(_prompt) and _prompt.is_open() else null


func _on_interacted(_actor: Node2D) -> void:
	if get_prompt():
		return
	if _prompt == null:
		_prompt = prompt_scene.instantiate() as ConfirmPrompt
		add_child(_prompt)
		_prompt.chosen.connect(_on_chosen)
	_prompt.ask(question, "", PackedStringArray(["YES", "NO"]), 1, 1)


func _on_chosen(index: int) -> void:
	if index != 0:
		return
	var healed := CreatureManagement.rest_all()
	DialogueManager.start(rested_dialogue if healed else already_rested_dialogue)
