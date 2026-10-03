class_name StarterSelectionEvent
extends Node
## Lab story event: after Professor Elian's intro, lets the player choose a starter, gives it to
## them, records it and switches his dialogue. Elian stays a plain NPC; this node owns the sequence.

const PLAYER_LOCK := &"starter_selection"

@export var professor: NPC
@export var starter_set: StarterSet
@export var screen_scene: PackedScene

@export_group("Dialogue")
@export var intro_dialogue: DialogueData
@export var cancelled_dialogue: DialogueData
## May use {creature} for the chosen creature's name.
@export var joined_dialogue: DialogueData
@export var after_dialogue: DialogueData

var _screen: StarterSelectionScreen


func _ready() -> void:
	DialogueManager.dialogue_finished.connect(_on_dialogue_finished)
	GameState.flag_changed.connect(_on_flag_changed)
	_refresh_professor_dialogue()


func is_selecting() -> bool:
	return _screen != null


func _refresh_professor_dialogue() -> void:
	professor.dialogue = after_dialogue if GameState.starter_selected else intro_dialogue


func _on_flag_changed(flag: StringName, _value: Variant) -> void:
	if flag == GameState.STARTER_SELECTED:
		_refresh_professor_dialogue()


func _on_dialogue_finished(dialogue: DialogueData) -> void:
	if dialogue == intro_dialogue and not GameState.starter_selected and _screen == null:
		_open_selection()


func _open_selection() -> void:
	_set_player_locked(true)
	_screen = screen_scene.instantiate() as StarterSelectionScreen
	add_child(_screen)
	_screen.species_chosen.connect(_on_species_chosen)
	_screen.cancelled.connect(_on_cancelled)
	_screen.open(starter_set.species)


func _on_species_chosen(species: CreatureSpecies) -> void:
	_close_selection()
	# Guards against ever handing out a second starter.
	if GameState.starter_selected:
		return
	var creature := CreatureFactory.create_from_species(species, starter_set.level)
	if PartyManager.add_creature(creature) < 0:
		push_error("StarterSelectionEvent: no room in the party for the starter.")
		return
	GameState.set_flag(GameState.STARTER_SPECIES, String(species.id))
	GameState.starter_selected = true
	GameSession.request_save(&"starter_selected")
	DialogueManager.start(joined_dialogue, {"creature": creature.get_display_name()})


func _on_cancelled() -> void:
	_close_selection()
	DialogueManager.start(cancelled_dialogue)


func _close_selection() -> void:
	_screen.queue_free()
	_screen = null
	_set_player_locked(false)


func _set_player_locked(locked: bool) -> void:
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player == null:
		return
	if locked:
		player.add_control_lock(PLAYER_LOCK)
	else:
		player.remove_control_lock(PLAYER_LOCK)
