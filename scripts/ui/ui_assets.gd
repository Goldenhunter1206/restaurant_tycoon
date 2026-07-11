class_name UiAssets
extends RefCounted
## Central registry for generated UI art: icons, star sprites, world pins.
## Every icon lives as its own PNG under assets/ui/icons/ (sliced from
## generated sheets). All lookups are cached and null-safe: a missing file
## returns null so call sites can keep a text fallback during the transition.

const ICON_DIR: String = "res://assets/ui/icons/"
const PIN_DIR: String = "res://assets/ui/pins/"

## emoji/glyph -> icon name; documents the purge and drives helper swaps.
const EMOJI_TO_ICON: Dictionary = {
	"💰": "money_bag", "💵": "banknotes", "🪙": "coin", "🏦": "bank",
	"📈": "chart_up", "📊": "chart_bars", "📅": "calendar", "🕐": "clock",
	"⏸": "pause", "▶": "play", "⏩": "fast", "⏭": "fastest",
	"⏳": "hourglass", "🏆": "trophy", "⭐": "star", "🔔": "bell",
	"🔨": "hammer", "🏗": "hammer", "👥": "people", "🍕": "pizza",
	"📣": "megaphone", "🛵": "scooter", "🚚": "truck", "🚶": "walker",
	"🗺": "city_map", "🏪": "store", "☰": "menu", "✕": "close",
	"✔": "check", "🏠": "house", "🍽": "dining", "👨‍🍳": "chef_hat",
	"🧾": "receipt", "🚦": "traffic", "🧺": "basket", "📍": "pin",
	"⚙": "gear",
}

static var _cache: Dictionary = {}


static func icon(icon_name: StringName) -> Texture2D:
	return _load_cached(ICON_DIR + String(icon_name) + ".png")


static func pin(pin_name: StringName) -> Texture2D:
	return _load_cached(PIN_DIR + "pin_" + String(pin_name) + ".png")


static func star(kind: StringName) -> Texture2D:
	return _load_cached("res://assets/ui/star_" + String(kind) + ".png")


static func has_icon(icon_name: StringName) -> bool:
	return icon(icon_name) != null


static func icon_rect(icon_name: StringName, px: int = 20) -> TextureRect:
	## Sized TextureRect for layout code; empty rect if the icon is missing
	## so row layouts stay aligned either way.
	var rect: TextureRect = TextureRect.new()
	var tex: Texture2D = icon(icon_name)
	if tex != null:
		rect.texture = tex
	rect.custom_minimum_size = Vector2(px, px)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func icon_button(button: Button, icon_name: StringName, px: int = 20) -> void:
	## Puts a real icon on a Button, replacing any leading emoji in its text.
	var tex: Texture2D = icon(icon_name)
	if tex == null:
		return
	button.icon = tex
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", px)


static func _load_cached(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[path] = tex
	return tex
