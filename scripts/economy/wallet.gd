class_name Wallet
extends RefCounted
## The player's money, in Coins (an original in-game currency; nothing to do with real money).
## Owned by GameSession and saved by SaveManager as a whole number. Only Shop spends it.

signal changed

const CURRENCY_NAME := "Coins"
## What a new game (and a migrated version 1 or 2 save) starts with.
const STARTING_COINS := 500
## Upper bound so a bug or an edited save can't push the amount past what the UI can show.
const MAX_COINS := 999_999

var _coins := 0


func get_coins() -> int:
	return _coins


func can_afford(amount: int) -> bool:
	return amount >= 0 and _coins >= amount


## Adds `amount` (>= 0), capped at MAX_COINS. Returns false (and changes nothing) for negative amounts.
func add(amount: int) -> bool:
	if amount < 0:
		return false
	_coins = mini(_coins + amount, MAX_COINS)
	changed.emit()
	return true


## Removes `amount` if it can be afforded. Returns false (and changes nothing) otherwise.
func spend(amount: int) -> bool:
	if amount < 0 or not can_afford(amount):
		return false
	_coins -= amount
	changed.emit()
	return true


func reset_to_starting_amount() -> void:
	_coins = STARTING_COINS
	changed.emit()


func to_save_data() -> int:
	return _coins


## Anything that doesn't validate loads as 0 (SaveManager rejects such saves before this point).
func load_save_data(data: Variant) -> void:
	_coins = mini(int(data), MAX_COINS) if validate_save_data(data).is_empty() else 0
	changed.emit()


## "500 Coins".
static func format(amount: int) -> String:
	return "%d %s" % [amount, CURRENCY_NAME]


## "" if `data` is a valid saved amount (a whole number >= 0), else the reason.
static func validate_save_data(data: Variant) -> String:
	if not (data is int or data is float):
		return "currency is not a number"
	if data != floorf(data) or data < 0:
		return "currency is not a whole number >= 0"
	return ""
