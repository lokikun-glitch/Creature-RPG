class_name GameMap
extends Node2D
## Base script for every explorable map (towns, routes, interiors).
## A map only describes itself; the World decides when it is loaded and where the player goes.

@export var map_id: StringName
@export var display_name: String
## Layer whose painted area defines the map edges, used for camera limits.
@export var bounds_layer: TileMapLayer


func get_bounds() -> Rect2:
	var used := bounds_layer.get_used_rect()
	var tile_size := Vector2(bounds_layer.tile_set.tile_size)
	var origin := bounds_layer.position + Vector2(used.position) * tile_size
	return Rect2(origin, Vector2(used.size) * tile_size)


func get_spawn_point(spawn_id: StringName) -> SpawnPoint:
	for node in get_tree().get_nodes_in_group(SpawnPoint.GROUP):
		var spawn := node as SpawnPoint
		if spawn and spawn.spawn_id == spawn_id and is_ancestor_of(spawn):
			return spawn
	return null
