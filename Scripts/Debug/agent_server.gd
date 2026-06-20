extends Node
## Agent control server — Phase 2 of docs/OLLAMA_AGENT_PLAN.md.
##
## Exposes a tiny localhost HTTP API so an external Ollama pilot can play the
## game the way a human does: GET /observe returns a player's-eye view (state
## JSON + a screenshot path), POST /act applies one macro-action by
## **synthesizing real input** through the same chain a keypress takes — never
## by mutating managers directly.
##
## Gated by AGENT=1 and self-disables under SMOKE_TEST (same pattern as
## Scripts/Debug/playtest_metrics.gd) so normal play and the smoke test pay
## nothing. Multimodal screenshots need a renderer, so run windowed:
##   AGENT=1 /Applications/Godot.app/Contents/MacOS/Godot --path .

const HOST := "127.0.0.1"
const PORT := 8088
const FRAME_PATH := "user://agent_frame.png"
const NEARBY_RADIUS := 14.0
# Mirror Player so the aim/goto controllers drive the same input math.
const MOUSE_SENSITIVITY := 0.0025
const INTERACT_RANGE := 3.5
const AIM_STEP_MAX := 45.0      # max synthesized mouse px/frame, so turns look human
const GOTO_STOP_DIST := 3.0     # stop walking once this close to the target wall
const AIM_DONE_RAD := deg_to_rad(3.0)
const GOTO_MOVE_CONE := deg_to_rad(35.0)  # only walk forward when roughly facing target

var _server: TCPServer = null
var _conn: StreamPeerTCP = null
var _buf := ""
# Untyped on purpose: avoids relying on the global class_name cache and lets us
# read Player/Hud members dynamically (see CLAUDE.md class-cache rule).
var _player = null
var _hud = null
# Watchable on-screen overlay (Scripts/UI/agent_overlay.gd); only under AGENT=1.
var _overlay = null
# action -> physics frames remaining, so timed holds (movement) release later.
var _holds: Dictionary = {}
# Persistent navigation targets, pursued each frame in _update_nav.
var _aim_target := ""
var _goto_target := ""
var _goto_moving := false

func bind_world(player, hud) -> void:
	_player = player
	_hud = hud

func _ready() -> void:
	if OS.get_environment("AGENT") != "1" or OS.get_environment("SMOKE_TEST") == "1":
		set_process(false)
		return
	if DisplayServer.get_name() == "headless":
		push_warning("AGENT server: headless has no renderer — screenshots will be empty.")
	_server = TCPServer.new()
	var err := _server.listen(PORT, HOST)
	if err != OK:
		push_error("AGENT server: cannot listen on %s:%d (err %d)" % [HOST, PORT, err])
		set_process(false)
		return
	print("AGENT: listening on http://%s:%d  (GET /observe, POST /act)" % [HOST, PORT])
	# Watchable overlay so a human can see what the pilot perceives and chooses.
	_overlay = preload("res://Scripts/UI/agent_overlay.gd").new()
	add_child(_overlay)

func _process(_delta: float) -> void:
	_tick_holds()
	_update_nav()
	_pump_server()

# --- input holds (movement) -------------------------------------------------

func _tick_holds() -> void:
	for action in _holds.keys():
		_holds[action] -= 1
		if _holds[action] <= 0:
			Input.action_release(action)
			_holds.erase(action)

## Release every timed hold now (used when nav takes over movement, so a stale
## move hold can't release a key the goto controller still believes is down).
func _clear_holds() -> void:
	for action in _holds.keys():
		Input.action_release(action)
	_holds.clear()

# --- navigation controllers (aim_at / goto_wall) ----------------------------

## Each frame, steer the camera (and, for goto, the legs) toward the stored
## target wall by feeding the same mouse/movement input a human produces.
func _update_nav() -> void:
	if _player == null:
		return
	if _goto_target != "":
		_pursue_goto()
	elif _aim_target != "":
		_pursue_aim()

func _pursue_aim() -> void:
	var node = WallManager.wall_nodes.get(_aim_target, null)
	if node == null:
		_aim_target = ""
		return
	var err := _steer_toward(node.global_position)
	if _focused_wall_id() == _aim_target or absf(err) <= AIM_DONE_RAD:
		_aim_target = ""

func _pursue_goto() -> void:
	var node = WallManager.wall_nodes.get(_goto_target, null)
	if node == null:
		_stop_goto()
		return
	var dist: float = _player.global_position.distance_to(node.global_position)
	if dist <= GOTO_STOP_DIST or _focused_wall_id() == _goto_target:
		_stop_goto()
		return
	var err := _steer_toward(node.global_position)
	# Only walk forward once roughly facing the wall, so we don't circle it.
	if absf(err) <= GOTO_MOVE_CONE:
		if not _goto_moving:
			Input.action_press("move_forward")
			_goto_moving = true
	elif _goto_moving:
		Input.action_release("move_forward")
		_goto_moving = false

func _stop_goto() -> void:
	if _goto_moving:
		Input.action_release("move_forward")
		_goto_moving = false
	_goto_target = ""

func _cancel_nav() -> void:
	_aim_target = ""
	_stop_goto()

## Feed one bounded step of yaw (and gentle pitch) toward a world point and
## return the remaining horizontal angle error in radians.
func _steer_toward(pos: Vector3) -> float:
	var origin: Vector3 = _player.global_position
	var dx := pos.x - origin.x
	var dz := pos.z - origin.z
	var desired_yaw := atan2(-dx, -dz)
	var yaw_err := wrapf(desired_yaw - _player.rotation.y, -PI, PI)
	# rotate_y(-rel.x * SENS): to change yaw by yaw_err, rel.x = -yaw_err / SENS.
	var rel_x := clampf(-yaw_err / MOUSE_SENSITIVITY, -AIM_STEP_MAX, AIM_STEP_MAX)
	# Gentle pitch toward the target height (camera sits ~1.5 m up).
	var horiz := Vector2(dx, dz).length()
	var rel_y := 0.0
	if "_pivot" in _player and _player._pivot != null and horiz > 0.01:
		var desired_pitch := atan2(pos.y - (origin.y + 1.5), horiz)
		var pitch_err: float = desired_pitch - _player._pivot.rotation.x
		rel_y = clampf(-pitch_err / MOUSE_SENSITIVITY, -AIM_STEP_MAX, AIM_STEP_MAX)
	_look(rel_x, rel_y)
	return yaw_err

# --- HTTP plumbing ----------------------------------------------------------

func _pump_server() -> void:
	if _server == null:
		return
	if _conn == null and _server.is_connection_available():
		_conn = _server.take_connection()
		_buf = ""
	if _conn == null:
		return
	_conn.poll()
	if _conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_conn = null
		return
	var avail := _conn.get_available_bytes()
	if avail > 0:
		var res := _conn.get_partial_data(avail)
		if res[0] == OK:
			_buf += (res[1] as PackedByteArray).get_string_from_utf8()
	_try_handle_request()

func _try_handle_request() -> void:
	var header_end := _buf.find("\r\n\r\n")
	if header_end == -1:
		return
	var lines := _buf.substr(0, header_end).split("\r\n")
	var request_line: PackedStringArray = lines[0].split(" ")
	if request_line.size() < 2:
		_respond({"error": "bad request"})
		return
	var method := request_line[0]
	var path := request_line[1]
	var content_length := 0
	for i in range(1, lines.size()):
		var low := lines[i].to_lower()
		if low.begins_with("content-length:"):
			content_length = low.split(":")[1].strip_edges().to_int()
	var body := _buf.substr(header_end + 4)
	if body.length() < content_length:
		return  # body still arriving; wait for the next pump
	body = body.substr(0, content_length)
	_respond(_route(method, path, body))

func _route(_method: String, path: String, body: String) -> Dictionary:
	var parts := path.split("?")
	var clean := parts[0]
	match clean:
		"/observe":
			# Skip the screenshot when the client opts out (?shot=0) — heuristic
			# and text-only pilots never read it, so don't pay the PNG write.
			var want_shot := not (parts.size() > 1 and "shot=0" in parts[1])
			return _observe(want_shot)
		"/act":
			var parsed = JSON.parse_string(body)
			if parsed is Dictionary:
				return _act(parsed)
			return {"ok": false, "error": "body must be a JSON object"}
		_:
			return {"error": "unknown path", "path": clean}

func _respond(payload: Dictionary) -> void:
	if _conn == null:
		return
	var body := JSON.stringify(payload)
	var bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % bytes.size()
	_conn.put_data(head.to_utf8_buffer())
	_conn.put_data(bytes)
	_conn.disconnect_from_host()
	_conn = null
	_buf = ""

# --- observation ------------------------------------------------------------

func _observe(want_shot := true) -> Dictionary:
	var obj: Dictionary = MissionManager.current_objective()
	var view := {
		"alias": GameState.alias,
		"alias_chosen": GameState.alias_chosen,
		"selected_can": GameState.selected_graffiti_type,
		"unlocked_cans": GameState.unlocked_types.keys(),
		"paint": GameState.paint,
		"cash": GameState.cash,
		"reputation": GameState.reputation,
		"rank": GameState.rank,
		"district": GameState.current_district_id,
		"heat": HeatManager.heat,
		"objective": String(obj.get("text", "")) if obj else "",
		"prompt": _hud_prompt(),
		"focused_wall": _focused_wall_id(),
		"nearby_walls": _nearby_walls(),
		"nav": {"aim_target": _aim_target, "goto_target": _goto_target},
		"legal_actions": _legal_actions(),
		"screenshot": _capture_screenshot() if want_shot else "",
	}
	if _overlay != null:
		_overlay.set_state(view)
	return view

func _hud_prompt() -> String:
	if _hud != null and "_prompt_label" in _hud and _hud._prompt_label != null:
		return _hud._prompt_label.text
	return ""

func _focused_wall_id() -> String:
	if _player == null:
		return ""
	var focus = _player._focused
	if focus == null:
		return ""
	# PaintableWall sets its node name to the wallId (paintable_wall.gd).
	var node_name := String(focus.name)
	if WallManager.wall_nodes.has(node_name):
		return node_name
	# Fallback: match the node by identity.
	for wall_id in WallManager.wall_nodes:
		if WallManager.wall_nodes[wall_id] == focus:
			return String(wall_id)
	return ""

func _nearby_walls() -> Array:
	var out: Array = []
	if _player == null:
		return out
	var origin: Vector3 = _player.global_position
	for wall_id in WallManager.wall_nodes:
		var node = WallManager.wall_nodes[wall_id]
		if node == null:
			continue
		var to: Vector3 = node.global_position - origin
		var dist := to.length()
		if dist > NEARBY_RADIUS:
			continue
		var state := ""
		if WallManager.wall_states.has(wall_id):
			state = String(WallManager.wall_states[wall_id].get("state", ""))
		out.append({
			"wallId": wall_id,
			"distance": snappedf(dist, 0.1),
			"bearing": int(round(rad_to_deg(atan2(to.x, -to.z)))),
			"state": state,
		})
	out.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return out

func _legal_actions() -> Array:
	var actions := [
		"select_can", "cycle_color", "cycle_cap", "look", "move",
		"stop", "wait",
	]
	if not _nearby_walls().is_empty():
		actions.append("aim_at")
		actions.append("goto_wall")
	var prompt := _hud_prompt()
	var focused_wall := _focused_wall_id()
	var focused_state := ""
	if focused_wall != "" and WallManager.wall_states.has(focused_wall):
		focused_state = String(WallManager.wall_states[focused_wall].get("state", ""))
	var fresh_focused_wall := focused_wall != "" and not focused_state.begins_with("player_")
	if not GameState.alias_chosen or ("Paint" in prompt and fresh_focused_wall):
		actions.append("paint")
	if "Rest" in prompt:
		actions.append("rest")
	if "Paint" in prompt and fresh_focused_wall and GameState.selected_graffiti_type == "piece":
		actions.append("freehand")
	return actions

func _capture_screenshot() -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var viewport := get_viewport()
	if viewport == null:
		return ""
	var tex := viewport.get_texture()
	if tex == null:
		return ""
	var img := tex.get_image()
	if img == null:
		return ""
	if img.save_png(FRAME_PATH) != OK:
		return ""
	return ProjectSettings.globalize_path(FRAME_PATH)

# --- actions (executed via synthesized real input) --------------------------

## Run one action and mirror the result to the overlay (so the watcher sees
## rejections too), then hand the result back to the HTTP responder.
func _act(data: Dictionary) -> Dictionary:
	var res := _act_impl(data)
	if _overlay != null:
		_overlay.log_action(data, res)
	return res

func _act_impl(data: Dictionary) -> Dictionary:
	var action := String(data.get("action", ""))
	match action:
		"select_can":
			_press("slot_%d" % clampi(int(data.get("slot", 1)), 1, GameState.SLOT_COUNT))
		"cycle_color":
			_press("cycle_color")
		"cycle_cap":
			_press("cycle_cap")
		"paint":
			_press("interact")
		"freehand":
			_press("freehand_paint")
		"rest":
			_press("safehouse_rest")
		"look":
			_cancel_nav()
			_look(float(data.get("dx", 0.0)), float(data.get("dy", 0.0)))
		"move":
			_cancel_nav()
			_move(String(data.get("dir", "forward")), float(data.get("seconds", 0.4)))
		"aim_at":
			var wall := String(data.get("wallId", ""))
			if not WallManager.wall_nodes.has(wall):
				return {"ok": false, "error": "unknown wallId: %s" % wall}
			_clear_holds()
			_stop_goto()
			_aim_target = wall
		"goto_wall":
			var wall := String(data.get("wallId", ""))
			if not WallManager.wall_nodes.has(wall):
				return {"ok": false, "error": "unknown wallId: %s" % wall}
			_clear_holds()
			_aim_target = ""
			_goto_target = wall
		"stop":
			_cancel_nav()
		"wait":
			pass
		_:
			return {"ok": false, "error": "unknown action: %s" % action}
	return {"ok": true, "action": action}

## Fire a tap on an input action through the real input chain (the same path
## a physical keypress takes into Player._unhandled_input / HUD modals).
func _press(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)

## Hold a movement action for a duration; released later in _tick_holds.
func _move(dir: String, seconds: float) -> void:
	var action := "move_%s" % dir
	if dir not in ["forward", "back", "left", "right"] or not InputMap.has_action(action):
		return
	Input.action_press(action)
	_holds[action] = maxi(1, int(round(clampf(seconds, 0.05, 3.0) * 60.0)))

## Nudge the camera, as a mouse motion event (Player reads relative motion
## while the mouse is captured).
func _look(dx: float, dy: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	Input.parse_input_event(ev)
