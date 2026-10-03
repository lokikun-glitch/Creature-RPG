class_name WorldMenu
extends CanvasLayer
## Base for menus opened from the world (storage, shop, Yes/No questions). While one is open the
## player holds a control lock, so they can't move, interact, or open the pause menu underneath
## it. Subclasses call _open_menu() / _close_menu() and handle their own input.

signal closed

var _opened_frame := -1


func is_open() -> bool:
	return visible


func _open_menu() -> void:
	_opened_frame = Engine.get_process_frames()
	_set_player_locked(true)
	show()


func _close_menu() -> void:
	if not visible:
		return
	hide()
	_set_player_locked(false)
	closed.emit()


## True for input arriving in the frame the menu opened, i.e. the key press that opened it.
func _is_opening_input() -> bool:
	return Engine.get_process_frames() == _opened_frame


func _exit_tree() -> void:
	if visible:
		_set_player_locked(false)


func _set_player_locked(locked: bool) -> void:
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player == null:
		return
	var lock := StringName("menu_%d" % get_instance_id())
	if locked:
		player.add_control_lock(lock)
	else:
		player.remove_control_lock(lock)
