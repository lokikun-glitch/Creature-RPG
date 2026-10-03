class_name ShopCounter
extends StaticBody2D
## A shop you use by facing its counter and pressing E. It only opens the ShopScreen with this
## shop's name and stock; prices live on each ItemData and buying goes through GameSession.
## The shopkeeper standing behind it is a plain NPC placed in the map.

@export var shop_name := "Shop"
@export var greeting := ""
@export var stock: Array[ItemData] = []
@export var screen_scene: PackedScene = preload("res://scenes/ui/shop_screen.tscn")

var _screen: ShopScreen


func _ready() -> void:
	($Interactable as Interactable).interacted.connect(_on_interacted)


## The open shop screen, or null.
func get_screen() -> ShopScreen:
	return _screen if is_instance_valid(_screen) and _screen.is_open() else null


func _on_interacted(_actor: Node2D) -> void:
	if get_screen():
		return
	if _screen == null:
		_screen = screen_scene.instantiate() as ShopScreen
		add_child(_screen)
	_screen.open(shop_name, stock, greeting)
