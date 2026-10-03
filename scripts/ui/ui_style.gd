class_name UiStyle
extends RefCounted
## Shared colours and box styles for the menu screens that build their layout in code (party,
## storage, shop, creature details), matching the pause menu and battle overlays.

const TEXT := Color("f2ebd9")
const TEXT_DIM := Color(0.72, 0.7, 0.64)
const TEXT_DISABLED := Color(0.48, 0.48, 0.55)
const ACCENT := Color(0.96, 0.8, 0.42)
const GOOD := Color(0.56, 0.84, 0.58)
const BAD := Color(0.9, 0.42, 0.38)
const BORDER := Color(0.95, 0.92, 0.85)
const BACKGROUND := Color(0.13, 0.13, 0.2, 0.98)
const DIM := Color(0.04, 0.04, 0.08, 0.6)


static func panel(margin_x := 8.0, margin_y := 5.0) -> StyleBoxFlat:
	var box := _box(BACKGROUND, BORDER, 3)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y + 1.0
	return box


## Background of a list row or option; `selected` gives it the gold highlight.
static func row(selected: bool) -> StyleBoxFlat:
	var box := _box(Color(0.96, 0.8, 0.42, 0.16) if selected else Color(0, 0, 0, 0),
			ACCENT if selected else Color(0, 0, 0, 0), 2)
	box.content_margin_left = 4.0
	box.content_margin_right = 4.0
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	return box


static func label(text: String, size := 7, color := TEXT) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override(&"font_size", size)
	result.add_theme_color_override(&"font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


## A full-screen translucent backdrop that also swallows mouse clicks meant for the world.
static func backdrop() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = DIM
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


static func _box(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	return box
