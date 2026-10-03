class_name DialogueData
extends Resource
## An ordered conversation, stored as a .tres in data/dialogue/ and referenced by whatever owns it.

## Default speaker for lines that don't set their own. Empty means no name is shown (e.g. signs).
@export var speaker := ""
@export var lines: Array[DialogueLine] = []


func speaker_for(line: DialogueLine) -> String:
	return line.speaker if not line.speaker.is_empty() else speaker
