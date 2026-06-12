extends RefCounted
## Shared JSON loading and startup validation (Plan_v2.md §3.6).
## Every manager loads its /Data file through load_json and checks
## required fields with require_fields, so a typo'd entry fails loudly
## at boot instead of silently defaulting into a 4×3 gray box.
## Preload this script (CLAUDE.md headless class-cache rule):
##   const DataLoader := preload("res://Scripts/Data/data_loader.gd")

## Validation failures found at startup; the smoke test asserts this
## stays 0 for shipped data.
static var error_count := 0

static func load_json(path: String, context: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		report("%s: cannot open %s" % [context, path])
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		report("%s: invalid JSON in %s" % [context, path])
	return parsed

## Counts and reports one validation failure.
static func report(message: String) -> void:
	error_count += 1
	push_error(message)

## push_errors every missing required field on `entry`. Returns true
## when the entry is complete. Accepts Variant so a malformed entry
## (e.g. a bare string in a defs array) is reported like any other
## validation failure instead of crashing the validator.
static func require_fields(entry: Variant, fields: Array, context: String) -> bool:
	if not (entry is Dictionary):
		report("%s: expected an object, got %s" % [context, type_string(typeof(entry))])
		return false
	var ok := true
	for field in fields:
		if not entry.has(field):
			ok = false
			report("%s: missing required field \"%s\"" % [context, field])
	return ok
