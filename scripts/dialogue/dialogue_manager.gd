extends Node
## Autoload that runs one conversation at a time.
## The dialogue box listens to draw lines; gameplay listens to pause the player.

signal dialogue_started(dialogue: DialogueData)
signal line_shown(line: DialogueLine, speaker: String, text: String)
signal dialogue_finished(dialogue: DialogueData)

var _dialogue: DialogueData
var _index := -1
var _variables: Dictionary = {}


func is_active() -> bool:
	return _dialogue != null


## `variables` fill {placeholders} in line text, e.g. {"creature": "Flamkit"}.
func start(dialogue: DialogueData, variables: Dictionary = {}) -> void:
	if is_active() or dialogue == null or dialogue.lines.is_empty():
		return
	_dialogue = dialogue
	_variables = variables
	_index = -1
	dialogue_started.emit(dialogue)
	advance()


func advance() -> void:
	if not is_active():
		return
	_index += 1
	if _index >= _dialogue.lines.size():
		var finished := _dialogue
		_dialogue = null
		dialogue_finished.emit(finished)
		return
	var line := _dialogue.lines[_index]
	line_shown.emit(line, _dialogue.speaker_for(line), line.text.format(_variables))
