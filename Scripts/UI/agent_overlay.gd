extends CanvasLayer
## Watchable agent overlay — plan item 2b of docs/OLLAMA_AGENT_PLAN.md.
##
## Only created under AGENT=1 (by agent_server.gd). It draws a small panel that
## shows what the external pilot last PERCEIVED (the observation), the ACTION it
## chose with its stated reason, and a rolling log of recent turns — so a human
## can sit and WATCH the agent play and understand *why* it acted, not just that
## it's running.
##
## Pure visual sink: the server pushes state on each /observe and a log line on
## each /act. No class_name; preload per the headless class-cache rule (CLAUDE.md).

const UiKit := preload("res://Scripts/UI/ui_kit.gd")
## Cyan, deliberately unlike the HUD's yellow, so it reads as debug chrome.
const ACCENT := Color("#3fb0ff")
const OK_COLOR := Color("#7be05a")
const REJECT_COLOR := Color("#ff6b6b")
const DIM := Color("#9aa0b0")
const LOG_LINES := 8
const PANEL_WIDTH := 360.0

var _turn := 0
var _title_label: Label
var _state_label: Label
var _action_label: Label
var _recommendation_label: Label
var _log_label: Label
var _log: Array[String] = []

func _ready() -> void:
	layer = 128  # above the gameplay HUD
	var panel := UiKit.make_panel(ACCENT)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	# Pin the top-right corner to the viewport's top-right; grow left and down
	# to fit content so it never overlaps the HUD's top-left readouts.
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_right = -12.0
	panel.offset_top = 12.0
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	_title_label = UiKit.make_label(box, 18, ACCENT)
	_title_label.text = "AGENT  ·  waiting for pilot"
	_state_label = UiKit.make_label(box, 14)
	_state_label.text = "(no observation yet)"
	_action_label = UiKit.make_label(box, 16, OK_COLOR)
	_action_label.text = "→ —"
	_recommendation_label = UiKit.make_label(box, 13, DIM)
	_recommendation_label.text = ""
	var log_title := UiKit.make_label(box, 13, DIM)
	log_title.text = "recent turns"
	_log_label = UiKit.make_label(box, 13, DIM)
	_log_label.text = ""

## Refresh the perceived-state block. Called on every /observe with the same
## dict the pilot receives, so the watcher sees exactly what the model sees.
func set_state(obs: Dictionary) -> void:
	if _state_label == null:
		return
	_state_label.text = "\n".join([
		"rep %s   cash %s   paint %s" % [
			obs.get("reputation", 0), obs.get("cash", 0), obs.get("paint", 0)],
		"heat %s   can %s" % [obs.get("heat", 0), obs.get("selected_can", "-")],
		"focus: %s" % [obs.get("focused_wall", "") if obs.get("focused_wall", "") else "-"],
		"obj: %s" % _trim(String(obs.get("objective", "")), 46),
		"prompt: %s" % _trim(String(obs.get("prompt", "")), 46),
	])

## Record the action the pilot chose this turn. Called on every /act with the
## action object (carries the model's `reason`) and the server's result, so
## rejected actions show up too.
func log_action(action: Dictionary, result: Dictionary) -> void:
	if _action_label == null:
		return
	_turn += 1
	var act_name := String(action.get("action", "?"))
	var reason := String(action.get("reason", ""))
	var recommendation := String(action.get("recommendation", ""))
	var category := String(action.get("recommendation_category", "other"))
	var ok := bool(result.get("ok", true))
	_title_label.text = "AGENT  ·  turn %d" % _turn
	_action_label.text = "→ %s%s" % [act_name, "   (%s)" % reason if reason != "" else ""]
	_action_label.add_theme_color_override("font_color", OK_COLOR if ok else REJECT_COLOR)
	if _recommendation_label != null:
		_recommendation_label.text = "rec[%s]: %s" % [
			category, _trim(recommendation, 70)] if recommendation != "" else ""
	var detail := _action_detail(act_name, action)
	var line := "%3d  %s%s%s" % [
		_turn, act_name, "  %s" % detail if detail != "" else "", "" if ok else "  ✗"]
	_log.push_front(line)
	if _log.size() > LOG_LINES:
		_log.resize(LOG_LINES)
	_log_label.text = "\n".join(_log)

## The argument worth showing in the compact log line, per action kind.
func _action_detail(act_name: String, action: Dictionary) -> String:
	match act_name:
		"select_can":
			return "slot %s" % action.get("slot", "?")
		"aim_at", "goto_wall":
			return String(action.get("wallId", ""))
		"goto_actor":
			return String(action.get("actorId", ""))
		"goto_objective":
			return "objective"
		"move":
			return String(action.get("dir", ""))
		_:
			return ""

func _trim(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, limit - 1) + "…"
