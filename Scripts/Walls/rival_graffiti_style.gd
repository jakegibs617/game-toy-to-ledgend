extends RefCounted
## Deterministic lightweight layout choices for rival graffiti. The
## wall renderer consumes this instead of storing rendered rival images,
## so saves stay small and screenshots stay stable by graffiti id.

static func variant_for(graffiti: Dictionary) -> Dictionary:
	var seed := stable_seed("%s|%s|%s" % [
		String(graffiti.get("graffitiId", "")),
		String(graffiti.get("crewId", "")),
		String(graffiti.get("type", "")),
	])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var type := String(graffiti.get("type", "tag"))
	return {
		"seed": seed,
		"slant": rng.randf_range(-4.5, 4.5),
		"xOffset": rng.randf_range(-0.14, 0.14),
		"yOffset": rng.randf_range(-0.08, 0.1),
		"stripeCount": _range_for(type, rng, 2, 5),
		"chipCount": _range_for(type, rng, 2, 6),
		"repeatCount": _range_for(type, rng, 1, 3),
	}

static func stable_seed(text: String) -> int:
	var hash_value := 5381
	for i in text.length():
		hash_value = int((hash_value * 33 + text.unicode_at(i)) & 0x7fffffff)
	return maxi(hash_value, 1)

static func _range_for(type: String, rng: RandomNumberGenerator, low: int, high: int) -> int:
	match type:
		"tag":
			return rng.randi_range(low, mini(high, 3))
		"stencil":
			return rng.randi_range(low, mini(high, 4))
		"roller":
			return rng.randi_range(maxi(low, 3), high + 1)
		"piece", "throwup":
			return rng.randi_range(maxi(low, 3), high)
		_:
			return rng.randi_range(low, high)
