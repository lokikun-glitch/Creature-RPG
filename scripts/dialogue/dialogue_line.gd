class_name DialogueLine
extends Resource
## One line of a conversation. Choices, conditions and events will attach here in later phases.

## Overrides the conversation's default speaker for this line.
@export var speaker := ""
@export_multiline var text := ""
