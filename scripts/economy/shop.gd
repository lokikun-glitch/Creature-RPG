class_name Shop
extends RefCounted
## Buying rules. Prices come from ItemData.price (0 = not sold). A purchase changes the wallet and
## the inventory together or not at all. Screens only ask; GameSession.buy_item() calls purchase()
## and then saves.

const NOT_ENOUGH_COINS := "Not enough Coins."
const NOT_FOR_SALE := "That item isn't for sale."
const INVALID_QUANTITY := "Choose how many to buy."
## Most of one item bought in a single purchase.
const MAX_QUANTITY := 99


## Price of one, or 0 if the item doesn't exist or isn't for sale.
static func get_price(item_id: StringName) -> int:
	var item := ItemCatalog.get_item(item_id)
	return item.price if item else 0


static func get_total(item_id: StringName, quantity: int) -> int:
	return get_price(item_id) * quantity


## How many the wallet can pay for (capped at MAX_QUANTITY). 0 if not even one.
static func max_affordable(item_id: StringName, wallet: Wallet) -> int:
	var price := get_price(item_id)
	return mini(wallet.get_coins() / price, MAX_QUANTITY) if price > 0 else 0


## "" if the purchase can go ahead, otherwise the message to show.
static func get_purchase_problem(item_id: StringName, quantity: int, wallet: Wallet) -> String:
	if get_price(item_id) <= 0:
		return NOT_FOR_SALE
	if quantity < 1 or quantity > MAX_QUANTITY:
		return INVALID_QUANTITY
	if not wallet.can_afford(get_total(item_id, quantity)):
		return NOT_ENOUGH_COINS
	return ""


## Pays and hands over the items. Returns "" on success; otherwise the problem, with nothing changed.
static func purchase(item_id: StringName, quantity: int, wallet: Wallet, inventory: Inventory) -> String:
	var problem := get_purchase_problem(item_id, quantity, wallet)
	if not problem.is_empty():
		return problem
	var total := get_total(item_id, quantity)
	wallet.spend(total)
	if not inventory.add_item(item_id, quantity):
		wallet.add(total)
		return NOT_FOR_SALE
	return ""
