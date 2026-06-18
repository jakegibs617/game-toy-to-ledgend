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

## Bespoke style behaviors (Product_reqs.md): glass-only scratch/acid
## hands, the greyscale one-color scratch look, and acid orientation.

## True when the style can only be applied to glass (scratch + acid hands).
static func style_is_glass_only(style_id: String) -> bool:
	return bool(style_def(style_id).get("glass", false))

## True for the one-color/greyscale scratch hand (renders desaturated).
static func style_is_one_color(style_id: String) -> bool:
	return bool(style_def(style_id).get("oneColor", false))

## Render opacity for the style (scratch hands sit at ~0.5); 1.0 default.
static func style_opacity(style_id: String) -> float:
	return clampf(float(style_def(style_id).get("opacity", 1.0)), 0.0, 1.0)

## Exposure multiplier (>= 1.0): wildstyle structure takes the longest to
## paint, raising heat/patrol attention — and pays off on heaven spots
## (Product_reqs.md). Clamped to 1.0 so it never reduces heat or rep.
static func style_exposure(style_id: String) -> float:
	return maxf(float(style_def(style_id).get("exposure", 1.0)), 1.0)

## Orientations the style supports; horizontal-only unless the data says
## otherwise (acid hands list both horizontal and vertical).
static func style_orientations(style_id: String) -> Array:
	var orientations: Array = style_def(style_id).get("orientations", [])
	return orientations.duplicate() if not orientations.is_empty() else ["horizontal"]

## How a style should render on a wall, computed from the style data and
## the wall shape so paintable_wall (and the smoke test) share one rule:
##   greyscale  — one-color scratch hand, drawn desaturated
##   opacity    — label alpha (scratch hands are faint scratches)
##   orientation— "vertical" when the style allows it and the wall is
##                taller than wide (acid runs down a tall glass panel),
##                otherwise the first allowed orientation
static func render_plan(style_id: String, wall_is_portrait: bool) -> Dictionary:
	var orientations := style_orientations(style_id)
	var orientation := String(orientations[0])
	if wall_is_portrait and orientations.has("vertical"):
		orientation = "vertical"
	elif orientations.has("horizontal"):
		orientation = "horizontal"
	return {
		"greyscale": style_is_one_color(style_id),
		"opacity": style_opacity(style_id),
		"orientation": orientation,
	}

## Picks a style whose family is capable for a graffiti type. If the
## requested style already fits (or the type lists no families) it is
## kept; otherwise we fall back to the simplest capable style so a
## marker hand never renders a throw-up, a piece, a roller, etc.
## (Product_reqs.md: each type only shows fonts capable for that style.)
static func resolve_for_families(style_id: String, families: Array) -> String:
	_ensure_loaded()
	var resolved := resolve_style_id(style_id)
	if families.is_empty():
		return resolved if _styles.has(resolved) else DEFAULT_STYLE_ID
	var style: Dictionary = _styles.get(resolved, {})
	if _styles.has(resolved) and String(style.get("family", "")) in families:
		return resolved
	return default_style_for_families(families)

## The lowest-level (most basic) catalog style matching one of the
## families — a stable, deterministic default per type.
static func default_style_for_families(families: Array) -> String:
	_ensure_loaded()
	var best := ""
	var best_level := 1 << 30
	for sid in _order:
		var style: Dictionary = _styles[sid]
		if String(style.get("family", "")) in families:
			var level := int(style.get("level", 0))
			if level < best_level:
				best_level = level
				best = sid
	return best if best != "" else DEFAULT_STYLE_ID

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
