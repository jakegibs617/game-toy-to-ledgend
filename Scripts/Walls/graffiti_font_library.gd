extends RefCounted
## Central catalog for tag lettering fonts. Graffiti records store the
## selected style id; this loader turns that id into a Font resource.

const FONTS_PATH := "res://Data/graffiti_font_styles.json"
const DEFAULT_STYLE_ID := "ff_comma_trial"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")

static var _styles: Dictionary = {}
static var _order: Array = []
static var _font_cache: Dictionary = {}
static var _loaded := false
static var _aliases := {
	"toy_hand": "ff_comma_trial",
	"simplerounded": "simple_rounded",
	"don-graffiti": "don_graffiti",
	"ff-comma-trial": "ff_comma_trial",
	"hoax-vandal": "hoax_vandal",
	"secret-labs": "secret_labs",
	"street-toxic": "street_toxic",
	"the-battle-continuez": "the_battle_continuez",
}

static func all_styles() -> Dictionary:
	_ensure_loaded()
	return _styles

static func style_ids() -> Array:
	_ensure_loaded()
	return _order.duplicate()

static func default_style_id() -> String:
	return DEFAULT_STYLE_ID

static func is_valid_style(style_id: String) -> bool:
	_ensure_loaded()
	return _styles.has(resolve_style_id(style_id))

static func resolve_style_id(style_id: String) -> String:
	return String(_aliases.get(style_id, style_id))

static func style_label(style_id: String) -> String:
	_ensure_loaded()
	var resolved := resolve_style_id(style_id)
	var style: Dictionary = _styles.get(resolved, {})
	return String(style.get("label", style_id))

static func style_def(style_id: String) -> Dictionary:
	_ensure_loaded()
	return _styles.get(resolve_style_id(style_id), {})

static func apply_to_label(label: Label3D, style_id: String) -> void:
	var font := font_for_style(style_id)
	if font != null:
		label.font = font

static func font_for_style(style_id: String) -> Font:
	_ensure_loaded()
	var style_key := resolve_style_id(style_id)
	var resolved := style_key if _styles.has(style_key) else DEFAULT_STYLE_ID
	if _font_cache.has(resolved):
		return _font_cache[resolved]
	var style: Dictionary = _styles.get(resolved, {})
	var path := String(style.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return null
	var font := FontFile.new()
	if font.load_dynamic_font(path) == OK:
		_font_cache[resolved] = font
		return font
	_font_cache[resolved] = null
	return null

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = DataLoader.load_json(FONTS_PATH, "GraffitiFontLibrary")
	_styles = parsed if parsed is Dictionary else {}
	_order = []
	for style_id in _styles:
		_order.append(String(style_id))
		var style: Dictionary = _styles[style_id]
		DataLoader.require_fields(style,
			["label", "path", "level", "family", "tool"],
			"GraffitiFontLibrary: style \"%s\"" % String(style_id))
		var path := String(style.get("path", ""))
		if path != "" and not FileAccess.file_exists(path):
			DataLoader.report("GraffitiFontLibrary: missing font \"%s\" for style \"%s\"" % [
				path, String(style_id)])
