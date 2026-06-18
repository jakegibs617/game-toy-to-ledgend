extends PanelContainer
## Nightclub dance floor (Product_reqs.md "dance / club / DJ rep-based
## invite"). Opened by Hud once the bouncer waves the writer past a
## rep-gated club door. The DJ plays a short set of `beats`: a marker
## sweeps a bar, and tapping the dance key while it crosses the centre
## target lands an on-beat hit. Final hype (hits / beats) scales the
## payout — Style XP, crew rep, and DJ tip cash.
##
## The dance model (beats, hits, hype) lives apart from the UI nodes so
## the headless smoke test can begin()/register()/result() off-tree; the
## UI's _process only decides on_beat from the marker and calls register.

signal finished(payout: Dictionary)
signal cancelled

const UiKit := preload("res://Scripts/UI/ui_kit.gd")
const ACCENT := Color("#ff2f86")

## Seconds the marker takes to sweep the bar once (one beat).
const BEAT_PERIOD := 0.75
## Half-width (as a fraction of the sweep) of the centre target zone — a
## tap within it counts as on-beat.
const HIT_FRACTION := 0.12

var _club: Dictionary = {}
var _beats_total := 0
var _beats_left := 0
var _hits := 0
var _combo := 0
var _best_combo := 0
var _clock := 0.0  # advances every frame; phase across it gives marker pos

var _title_label: Label
var _meter_label: Label
var _footer_label: Label
var _marker: ColorRect
var _bar: Panel
var _target: ColorRect

func _ready() -> void:
	UiKit.apply_panel_style(self, ACCENT, 0.93, 14.0, 10.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(420, 0)
	add_child(box)
	_title_label = UiKit.make_label(box, 22, ACCENT)

	_bar = Panel.new()
	_bar.custom_minimum_size = Vector2(380, 36)
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.08, 0.06, 0.12, 0.95)
	bar_style.set_corner_radius_all(6)
	_bar.add_theme_stylebox_override("panel", bar_style)
	box.add_child(_bar)

	# Centre target zone the marker should cross on the beat.
	_target = ColorRect.new()
	_target.color = Color(ACCENT, 0.35)
	_bar.add_child(_target)
	# The sweeping marker.
	_marker = ColorRect.new()
	_marker.color = Color("#f2f2f2")
	_bar.add_child(_marker)

	_meter_label = UiKit.make_label(box, 18, Color(1, 1, 1, 0.9))
	_footer_label = UiKit.make_label(box, 15, Color(1, 1, 1, 0.8))
	_footer_label.text = "[E/Space] hit the beat   ·   [Esc] leave"
	_refresh_ui()

## ---- Dance model (safe off-tree) ------------------------------------

## Starts a fresh set for `club`. Resets the beat clock so the first
## sweep begins cleanly.
func begin(club: Dictionary) -> void:
	_club = club
	_beats_total = maxi(int(club.get("beats", 12)), 1)
	_beats_left = _beats_total
	_hits = 0
	_combo = 0
	_best_combo = 0
	_clock = 0.0
	_refresh_ui()

## Spends one beat of the set. `on_beat` is true when the tap landed in
## the target window. Returns the post-tap state. No-op once the set is
## spent (so a late key press can't over-score).
func register(on_beat: bool) -> Dictionary:
	if _beats_left <= 0:
		return {"done": true, "hit": false, "beatsLeft": 0}
	_beats_left -= 1
	if on_beat:
		_hits += 1
		_combo += 1
		_best_combo = maxi(_best_combo, _combo)
	else:
		_combo = 0
	return {"done": _beats_left <= 0, "hit": on_beat, "beatsLeft": _beats_left}

func is_done() -> bool:
	return _beats_left <= 0

## Hype as a 0..100 percentage of the set hit on-beat.
func hype_pct() -> int:
	return int(round(100.0 * float(_hits) / float(_beats_total)))

## The set's payout, scaled by hype. Computed off the club's max values.
func result() -> Dictionary:
	var frac := float(_hits) / float(_beats_total)
	return {
		"hypePct": hype_pct(),
		"hits": _hits,
		"beats": _beats_total,
		"bestCombo": _best_combo,
		"styleXp": int(round(float(_club.get("styleXp", 0)) * frac)),
		"crewRep": int(round(float(_club.get("crewRep", 0)) * frac)),
		"cash": int(round(float(_club.get("tipCash", 0)) * frac)),
	}

## ---- UI / input -----------------------------------------------------

## Routes modal input from Hud. Returns true when consumed.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("toggle_mouse"):
		cancelled.emit()
		return true
	if event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		_tap()
		return true
	# Hold the writer at the booth: swallow movement so they can't wander
	# off the floor mid-set (the modal owns input while open).
	if event.is_action_pressed("move_forward") or event.is_action_pressed("move_back") \
			or event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		return true
	return false

## A dance key press: score it against the marker, then advance the set.
func _tap() -> void:
	if is_done():
		return
	var phase := fmod(_clock, BEAT_PERIOD) / BEAT_PERIOD
	var on_beat := absf(phase - 0.5) <= HIT_FRACTION
	register(on_beat)
	if is_done():
		finished.emit(result())
	else:
		_refresh_ui()

func _process(delta: float) -> void:
	# Only sweep while the floor is actually showing an unfinished set — a
	# set bailed early (Esc) leaves the model unfinished but the panel hidden.
	if is_done() or not visible or _bar == null:
		return
	_clock += delta
	var phase := fmod(_clock, BEAT_PERIOD) / BEAT_PERIOD
	var width := _bar.size.x
	var half := HIT_FRACTION * width
	_target.position = Vector2(width * 0.5 - half, 0)
	_target.size = Vector2(half * 2.0, _bar.size.y)
	_marker.position = Vector2(clampf(phase * width - 3.0, 0.0, width - 6.0), 0)
	_marker.size = Vector2(6.0, _bar.size.y)

func _refresh_ui() -> void:
	if _title_label == null:
		return
	_title_label.text = "%s — DJ SET" % String(_club.get("label", "THE CLUB"))
	_meter_label.text = "Beat %d/%d   ·   Hype %d%%   ·   Combo x%d" % [
		_beats_total - _beats_left, _beats_total, hype_pct(), _combo]
