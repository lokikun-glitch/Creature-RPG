class_name StorageTerminal
extends StaticBody2D
## The creature storage terminal. Press E to be asked "Access Creature Storage?"; Yes opens the
## StorageScreen. Uses the shared Interactable like every other object.

@export var question := "Access Creature Storage?"
@export var prompt_scene: PackedScene = preload("res://scenes/ui/confirm_prompt.tscn")
@export var screen_scene: PackedScene = preload("res://scenes/ui/storage_screen.tscn")

var _prompt: ConfirmPrompt
var _screen: StorageScreen


func _ready() -> void:
	($Interactable as Interactable).interacted.connect(_on_interacted)


## The open Yes/No question, or null.
func get_prompt() -> ConfirmPrompt:
	return _prompt if is_instance_valid(_prompt) and _prompt.is_open() else null


## The open storage screen, or null.
func get_screen() -> StorageScreen:
	return _screen if is_instance_valid(_screen) and _screen.is_open() else null


func _on_interacted(_actor: Node2D) -> void:
	if get_prompt() or get_screen():
		return
	if _prompt == null:
		_prompt = prompt_scene.instantiate() as ConfirmPrompt
		add_child(_prompt)
		_prompt.chosen.connect(_on_chosen)
	_prompt.ask(question, "", PackedStringArray(["YES", "NO"]), 0, 1)


func _on_chosen(index: int) -> void:
	if index != 0:
		return
	if _screen == null:
		_screen = screen_scene.instantiate() as StorageScreen
		add_child(_screen)
	_screen.open()
