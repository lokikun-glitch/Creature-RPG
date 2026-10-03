class_name ItemData
extends Resource
## Describes an item. What an item *does* is decided by the system that uses it (e.g. the
## BattleManager for capture items); this resource never contains gameplay logic.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## Groups items by use, e.g. &"capture".
@export var category: StringName
@export var icon: Texture2D
## Shop price for one, in Coins. 0 means shops don't sell it.
@export_range(0, 99999) var price := 0
