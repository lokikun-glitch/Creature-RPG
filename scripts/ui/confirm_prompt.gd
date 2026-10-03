class_name ConfirmPrompt
extends WorldMenu
## A Yes/No (or any options) question asked from the world, e.g. by the bed or the storage
## terminal. Wraps the shared ChoiceDialog and holds a player lock while it's open.

signal chosen(index: int)

@onready var _dialog: ChoiceDialog = %Dialog


func _ready() -> void:
	_dialog.chosen.connect(_on_dialog_chosen)


## `cancel_index` is chosen by Esc; -1 means Esc does nothing.
func ask(title: String, message: String, options: PackedStringArray, default_index := 0, cancel_index := -1) -> void:
	_dialog.open(title, message, options, default_index, cancel_index)
	_open_menu()


func get_dialog() -> ChoiceDialog:
	return _dialog


func _on_dialog_chosen(index: int) -> void:
	_close_menu()
	chosen.emit(index)
