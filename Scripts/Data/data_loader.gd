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
		error_count += 1
		push_error("%s: cannot open %s" % [context, path])
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		error_count += 1
		push_error("%s: invalid JSON in %s" % [context, path])
	return parsed

## push_errors every missing required field on `entry`. Returns true
## when the entry is complete.
static func require_fields(entry: Dictionary, fields: Array, context: String) -> bool:
	var ok := true
	for field in fields:
		if not entry.has(field):
			ok = false
			error_count += 1
			push_error("%s: missing required field \"%s\"" % [context, field])
	return ok
