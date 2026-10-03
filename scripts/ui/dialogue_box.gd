class_name DialogueBox
extends PanelContainer
## Bottom-of-screen dialogue window. It only displays what DialogueManager sends
## and asks it to advance; it holds no conversation state of its own.

@export var characters_per_second := 50.0

var _typing := false
var _elapsed := 0.0

@onready var _name_label: Label = %NameLabel
@onready var _text_label: Label = %TextLabel
@onready var _hint_label: Label = %HintLabel


func _ready() -> void:
	hide()
	DialogueManager.dialogue_started.connect(func(_dialogue: DialogueData) -> void: show())
	DialogueManager.line_shown.connect(_show_line)
	DialogueManager.dialogue_finished.connect(func(_dialogue: DialogueData) -> void: hide())


func _show_line(_line: DialogueLine, speaker: String, text: String) -> void:
	_name_label.text = speaker
	_name_label.visible = not speaker.is_empty()
	_text_label.text = text
	_text_label.visible_characters = 0
	_hint_label.visible = false
	_elapsed = 0.0
	_typing = true


func _process(delta: float) -> void:
	if not _typing:
		return
	_elapsed += delta
	var shown := int(_elapsed * characters_per_second)
	if shown >= _text_label.get_total_character_count():
		_finish_typing()
	else:
		_text_label.visible_characters = shown


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		# First press completes the typewriter effect; the next one advances.
		if _typing:
			_finish_typing()
		else:
			DialogueManager.advance()


func _finish_typing() -> void:
	_typing = false
	_text_label.visible_characters = -1
	_hint_label.visible = true
