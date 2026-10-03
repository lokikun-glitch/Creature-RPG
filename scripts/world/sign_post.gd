class_name SignPost
extends StaticBody2D
## A readable sign (or any object you can read or inspect, e.g. a campfire or a survey marker).
## Its text is a DialogueData resource shown through the shared Interactable.

@export var dialogue: DialogueData


func _ready() -> void:
	var interactable := $Interactable as Interactable
	interactable.dialogue = dialogue
	interactable.interaction_enabled = dialogue != null
