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
const CAMERA_DISTANCE := 3.5    # mirror Player; spring arm length (camera behind player)
const GOTO_STOP_DIST := 3.0     # stop walking once this close to the target wall
const GOTO_ACTOR_STOP_DIST := 2.5
const GOTO_ACTOR_HARD_STOP_DIST := 1.5
const AIM_DONE_RAD := deg_to_rad(3.0)
const GOTO_MOVE_CONE := deg_to_rad(35.0)  # only walk forward when roughly facing target
const STUCK_FRAMES_MAX := 90       # ~1.5 s at 60 fps before triggering a side-step
const STUCK_MIN_PROGRESS := 0.3   # metres per STUCK_FRAMES_MAX window to count as moving
const STUCK_SIDESTEP_DUR := 0.5   # seconds to hold the side-step key

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
var _goto_actor := ""
var _goto_moving := false
var _nav_mouse_mode_before := -1
# Stuck-detection: fires a side-step when dist hasn't decreased by STUCK_MIN_PROGRESS
# over STUCK_FRAMES_MAX consecutive frames while move_forward is held.
var _stuck_check_dist := -1.0
var _stuck_frames := 0
var _stuck_side := 1   # +1 = right next, -1 = left next (alternates each unstick)
# paint_objective macro: navigate → aim → press paint once focused on the target wall.
var _paint_obj_wall := ""
var _paint_obj_can_slot := 0       # 0 = no can swap needed
var _paint_obj_can_selected := false
# Frames spent steering at the wall after aim exits but before physics confirms focus.
var _paint_obj_stall := 0
const PAINT_OBJ_STALL_MAX := 120  # ~2s at 60fps before giving up and re-approaching

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
	elif _goto_actor != "":
		_pursue_actor_goto()
	elif _aim_target != "":
		_pursue_aim()
	if _paint_obj_wall != "":
		_pursue_paint_obj()

func _pursue_aim() -> void:
	var node = WallManager.wall_nodes.get(_aim_target, null)
	if node == null:
		_aim_target = ""
		_restore_nav_mouse_mode_if_idle()
		return
	var err := _steer_toward(node.global_position)
	if _focused_wall_id() == _aim_target or absf(err) <= AIM_DONE_RAD:
		_aim_target = ""
		_restore_nav_mouse_mode_if_idle()

func _pursue_goto() -> void:
	var node = WallManager.wall_nodes.get(_goto_target, null)
	if node == null:
		_stop_goto()
		return
	var dist: float = _player.global_position.distance_to(node.global_position)
	if _focused_wall_id() == _goto_target:
		_stop_goto()
		return
	if dist <= GOTO_STOP_DIST:
		var target := _goto_target
		_stop_goto(false)
		_begin_nav_capture()
		_aim_target = target
		return
	var err := _steer_toward(node.global_position)
	# Only walk forward once roughly facing the wall, so we don't circle it.
	if absf(err) <= GOTO_MOVE_CONE:
		if not _goto_moving:
			Input.action_press("move_forward")
			_goto_moving = true
		_update_stuck(dist)
	elif _goto_moving:
		Input.action_release("move_forward")
		_goto_moving = false

func _stop_goto(restore_mouse := true) -> void:
	if _goto_moving:
		Input.action_release("move_forward")
		_goto_moving = false
	_goto_target = ""
	_goto_actor = ""
	_reset_stuck()
	if restore_mouse:
		_restore_nav_mouse_mode_if_idle()

func _reset_stuck() -> void:
	_stuck_check_dist = -1.0
	_stuck_frames = 0

## Call once per frame while move_forward is held. If dist hasn't decreased by
## STUCK_MIN_PROGRESS over STUCK_FRAMES_MAX frames, side-steps to get around
## blocking geometry or an NPC standing in the way.
func _update_stuck(dist: float) -> void:
	# Pause counting during an active side-step so the counter doesn't re-fire
	# before the player has had time to move clear of the blocker.
	if _holds.has("move_left") or _holds.has("move_right"):
		_stuck_check_dist = dist
		return
	if _stuck_check_dist < 0.0:
		_stuck_check_dist = dist
		return
	if _stuck_check_dist - dist >= STUCK_MIN_PROGRESS:
		_stuck_check_dist = dist
		_stuck_frames = 0
		return
	_stuck_frames += 1
	if _stuck_frames >= STUCK_FRAMES_MAX:
		_stuck_frames = 0
		_stuck_check_dist = -1.0
		var side := "right" if _stuck_side > 0 else "left"
		_stuck_side *= -1
		_move(side, STUCK_SIDESTEP_DUR)

func _cancel_nav() -> void:
	_aim_target = ""
	_clear_paint_obj()
	_stop_goto()

func _pursue_actor_goto() -> void:
	var node: Node3D = _actor_node(_goto_actor)
	if node == null:
		_stop_goto()
		return
	# If a non-paint interact prompt appeared, we're already in the actor's
	# interact range — stop nav and let the model press E instead of pressing
	# deeper into counter/desk geometry trying to close the last 0.5 m.
	var prompt := _hud_prompt()
	var prompt_matches_actor := "[E]" in prompt and not "Paint" in prompt \
			and not "Rest" in prompt and _actor_prompt_matches(_goto_actor, node, prompt)
	var wrong_interact_prompt := "[E]" in prompt and not "Paint" in prompt \
			and not "Rest" in prompt and not prompt_matches_actor
	if prompt_matches_actor:
		_stop_goto()
		return
	var dist: float = _player.global_position.distance_to(node.global_position)
	var err := _steer_toward(node.global_position)
	# Stop when close and roughly facing — use GOTO_MOVE_CONE (35°) not AIM_DONE_RAD (3°)
	# so the player doesn't overshoot trying to hit an impossibly precise angle.
	if dist <= GOTO_ACTOR_STOP_DIST and absf(err) <= GOTO_MOVE_CONE \
			and not wrong_interact_prompt:
		_stop_goto()
		return
	# Don't walk forward once close — prevents oscillating past the target.
	if dist <= GOTO_ACTOR_STOP_DIST and (not wrong_interact_prompt \
			or dist <= GOTO_ACTOR_HARD_STOP_DIST):
		if _goto_moving:
			Input.action_release("move_forward")
			_goto_moving = false
		return
	if absf(err) <= GOTO_MOVE_CONE:
		if not _goto_moving:
			Input.action_press("move_forward")
			_goto_moving = true
		_update_stuck(dist)
	elif _goto_moving:
		Input.action_release("move_forward")
		_goto_moving = false

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

func _graffiti_type_slot(graffiti_type: String) -> int:
	match graffiti_type:
		"tag": return 1
		"throwup": return 2
		"piece": return 3
		"stencil": return 4
		"roller": return 5
		"mural": return 6
	return 0

func _clear_paint_obj() -> void:
	_paint_obj_wall = ""
	_paint_obj_can_slot = 0
	_paint_obj_can_selected = false
	_paint_obj_stall = 0

## Drives the paint_objective macro each frame: select can → navigate → aim → press paint.
func _pursue_paint_obj() -> void:
	# Phase 1: select the required can once before starting nav.
	if _paint_obj_can_slot > 0 and not _paint_obj_can_selected:
		_press("slot_%d" % _paint_obj_can_slot)
		_paint_obj_can_selected = true
		return
	# Phase 2: wait while goto or aim nav is still running.
	if _goto_target != "" or _aim_target != "":
		return
	# Phase 3a: standard path — RayCast3D confirms focus (common after aim cycle).
	if _focused_wall_id() == _paint_obj_wall and "Paint" in _hud_prompt():
		_press("interact")
		_clear_paint_obj()
		_restore_nav_mouse_mode_if_idle()
		return
	# Phase 3b: yaw-based check — _player.rotation.y is already updated by aim's mouse
	# events, while direct_space_state still reflects the previous physics step (so a
	# raycast would always return false here). If close enough and roughly facing the
	# wall, force-set focus and fire interact directly.
	if WallManager.wall_nodes.has(_paint_obj_wall):
		var wnode: Node3D = WallManager.wall_nodes[_paint_obj_wall] as Node3D
		if wnode != null:
			var to: Vector3 = wnode.global_position - _player.global_position
			var dist: float = to.length()
			if dist <= INTERACT_RANGE + 1.5:
				var desired_yaw: float = atan2(-to.x, -to.z)
				var yaw_err: float = absf(wrapf(desired_yaw - _player.rotation.y, -PI, PI))
				if yaw_err <= AIM_DONE_RAD * 4.0:
					_player._focused = wnode
					_player.focus_changed.emit(_player._focused)
					_press("interact")
					_clear_paint_obj()
					_restore_nav_mouse_mode_if_idle()
					return
	# Phase 4: camera not yet on wall — rotate toward it directly (more reliable
	# than synthesized mouse events which can be lost if routing is wrong).
	if not WallManager.wall_nodes.has(_paint_obj_wall):
		_clear_paint_obj()
		_restore_nav_mouse_mode_if_idle()
		return
	_paint_obj_stall += 1
	if _paint_obj_stall > PAINT_OBJ_STALL_MAX:
		_paint_obj_stall = 0
		_begin_nav_capture()
		_goto_target = _paint_obj_wall
		return
	var node = WallManager.wall_nodes[_paint_obj_wall]
	var to: Vector3 = node.global_position - _player.global_position
	var desired_yaw := atan2(-to.x, -to.z)
	_player.rotation.y = lerp_angle(_player.rotation.y, desired_yaw, 0.3)
	if "_pivot" in _player and _player._pivot != null:
		var horiz: float = Vector2(to.x, to.z).length()
		if horiz > 0.01:
			var desired_pitch := atan2(to.y - 1.5, horiz)
			_player._pivot.rotation.x = lerp_angle(
				_player._pivot.rotation.x, desired_pitch, 0.3)

func _begin_nav_capture() -> void:
	_reset_stuck()
	if _nav_mouse_mode_before == -1:
		_nav_mouse_mode_before = int(Input.get_mouse_mode())
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _restore_nav_mouse_mode_if_idle() -> void:
	if _nav_mouse_mode_before == -1:
		return
	if _aim_target != "" or _goto_target != "" or _goto_actor != "" or _paint_obj_wall != "":
		return
	Input.set_mouse_mode(_nav_mouse_mode_before)
	_nav_mouse_mode_before = -1

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

## Current nav state for the observe payload: targets, live distance to the
## active target, whether move_forward is pressed, and the stuck-frame counter.
func _nav_state() -> Dictionary:
	var dist := -1.0
	if _player != null:
		if _goto_target != "":
			var wnode = WallManager.wall_nodes.get(_goto_target, null)
			if wnode != null:
				dist = snappedf(_player.global_position.distance_to(wnode.global_position), 0.1)
		elif _goto_actor != "":
			var anode := _actor_node(_goto_actor)
			if anode != null:
				dist = snappedf(_player.global_position.distance_to(anode.global_position), 0.1)
	return {
		"aim_target": _aim_target,
		"goto_target": _goto_target,
		"goto_actor": _goto_actor,
		"moving": _goto_moving,
		"dist": dist,
		"stuck_frames": _stuck_frames,
	}

func _observe(want_shot := true) -> Dictionary:
	var obj: Dictionary = MissionManager.current_objective()
	var paint_fields := _paint_objective_fields(obj)
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
		"objective_target": _objective_target(obj),
		"objective_required_can": paint_fields["objective_required_can"],
		"objective_can_slot": paint_fields["objective_can_slot"],
		"objective_ready_to_interact": paint_fields["objective_ready_to_interact"],
		"objective_distance": paint_fields["objective_distance"],
		"prompt": _hud_prompt(),
		"focused_wall": _focused_wall_id(),
		"nearby_walls": _nearby_walls(),
		"nearby_actors": _nearby_actors(),
		"nav": _nav_state(),
		"legal_actions": _legal_actions(),
		"screenshot": _capture_screenshot() if want_shot else "",
	}
	if _overlay != null:
		_overlay.set_state(view)
	return view

## Compute the four paint-objective observe fields from the current objective dict.
func _paint_objective_fields(obj: Dictionary) -> Dictionary:
	var required_can := ""
	var can_slot := 0
	var ready := false
	var dist := -1.0
	if not obj.is_empty() and String(obj.get("type", "")) == "paint":
		var types: Array = obj.get("graffitiTypes", [])
		required_can = String(types[0]) if not types.is_empty() else ""
		can_slot = _graffiti_type_slot(required_can)
		var target_wall := _resolve_mission_wall(String(obj.get("wall", "")))
		if target_wall != "":
			var focused := _focused_wall_id()
			var correct_can := required_can == "" or GameState.selected_graffiti_type == required_can
			ready = focused == target_wall and correct_can and "Paint" in _hud_prompt()
	var target := _objective_target(obj)
	if not target.is_empty() and _player != null:
		match String(target.get("type", "")):
			"wall":
				var wnode = WallManager.wall_nodes.get(String(target.get("wallId", "")), null)
				if wnode != null:
					dist = snappedf(_player.global_position.distance_to(wnode.global_position), 0.1)
			"actor":
				var anode := _actor_node(String(target.get("actorId", "")))
				if anode != null:
					dist = snappedf(_player.global_position.distance_to(anode.global_position), 0.1)
	return {
		"objective_required_can": required_can,
		"objective_can_slot": can_slot,
		"objective_ready_to_interact": ready,
		"objective_distance": dist,
	}

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

func _is_neutral(wall_id: String) -> bool:
	for def in WallManager.wall_defs:
		if String(def.get("wallId", "")) == wall_id:
			return bool(def.get("territoryNeutral", false))
	return false

func _nearby_walls() -> Array:
	var out: Array = []
	if _player == null:
		return out
	var origin: Vector3 = _player.global_position
	for wall_id in WallManager.wall_nodes:
		var node = WallManager.wall_nodes[wall_id]
		if node == null:
			continue
		# Skip walls significantly above the player — they require climbing and
		# the straight-line navigator cannot reach them from the ground.
		if node.global_position.y - origin.y > 5.0:
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
			"territory_neutral": _is_neutral(String(wall_id)),
		})
	out.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return out

func _nearby_actors() -> Array:
	var out: Array = []
	if _player == null:
		return out
	var origin: Vector3 = _player.global_position
	for node in _all_actor_nodes():
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		var actor_id := _node_actor_id(node)
		if actor_id == "":
			continue
		var to: Vector3 = node.global_position - origin
		var dist := to.length()
		if dist > NEARBY_RADIUS:
			continue
		var prompt := ""
		if node.has_method("prompt_text"):
			prompt = String(node.prompt_text())
		out.append({
			"actorId": actor_id,
			"distance": snappedf(dist, 0.1),
			"bearing": int(round(rad_to_deg(atan2(to.x, -to.z)))),
			"prompt": prompt,
		})
	out.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return out

func _all_actor_nodes() -> Array:
	var out: Array = []
	var root := get_tree().current_scene
	if root != null:
		_collect_actor_nodes(root, out)
	return out

func _collect_actor_nodes(node: Node, out: Array) -> void:
	if _node_actor_id(node) != "":
		out.append(node)
	for child in node.get_children():
		_collect_actor_nodes(child, out)

func _node_actor_id(node: Node) -> String:
	if "actor_id" in node:
		return String(node.actor_id)
	if "member_id" in node:
		return "pickup_%s" % String(node.member_id)
	if "data" in node and node.data is Dictionary:
		if node.data.has("memberId"):
			return String(node.data.get("memberId", ""))
		return String(node.data.get("actorId", ""))
	return ""

func _actor_node(actor_id: String) -> Node3D:
	for node in _all_actor_nodes():
		if _node_actor_id(node) == actor_id:
			return node as Node3D
	return null

func _actor_prompt_matches(actor_id: String, node: Node, prompt: String) -> bool:
	var low := prompt.to_lower()
	if "pick up" in low and not ("member_id" in node):
		return false
	var candidates: Array = [actor_id, actor_id.replace("_", " ")]
	if "data" in node and node.data is Dictionary:
		var data: Dictionary = node.data
		for key in ["name", "alias", "roleLabel", "role"]:
			var value := String(data.get(key, ""))
			if value != "":
				candidates.append(value)
	for candidate in candidates:
		var needle := String(candidate).strip_edges().to_lower()
		if needle != "" and needle in low:
			return true
	return false

func _interact_objective_actor() -> bool:
	var target := _objective_target(MissionManager.current_objective())
	if String(target.get("type", "")) != "actor":
		return false
	var node := _actor_node(String(target.get("actorId", "")))
	if node == null or not node.has_method("interact"):
		return false
	if not _objective_actor_in_range(node):
		return false
	_cancel_nav()
	node.interact()
	return true

func _objective_actor_in_range(node: Node3D = null) -> bool:
	if _player == null:
		return false
	var actor_node := node
	if actor_node == null:
		var target := _objective_target(MissionManager.current_objective())
		if String(target.get("type", "")) != "actor":
			return false
		actor_node = _actor_node(String(target.get("actorId", "")))
	if actor_node == null:
		return false
	return _player.global_position.distance_to(actor_node.global_position) <= INTERACT_RANGE

func _objective_target(obj: Dictionary) -> Dictionary:
	if obj.is_empty():
		return {}
	var type := String(obj.get("type", ""))
	if type == "reach_wall":
		var wall_id := _resolve_mission_wall(String(obj.get("wall", "")))
		if wall_id != "":
			var reach_actor := "reach_%s" % wall_id
			if _actor_node(reach_actor) != null:
				return {"type": "actor", "actorId": reach_actor}
			return {"type": "wall", "wallId": wall_id}
	if type == "paint" and obj.has("wall"):
		var paint_wall_id := _resolve_mission_wall(String(obj.get("wall", "")))
		if paint_wall_id != "":
			return {"type": "wall", "wallId": paint_wall_id}
	if obj.has("actorId"):
		var actor_id := String(obj.get("actorId", ""))
		if actor_id != "":
			return {"type": "actor", "actorId": actor_id}
	if obj.has("memberId"):
		var member_id := String(obj.get("memberId", ""))
		if member_id != "":
			if String(obj.get("stage", "")) == "item_recovered":
				return {"type": "actor", "actorId": "pickup_%s" % member_id}
			return {"type": "actor", "actorId": member_id}
	return {}

func _action_objective_target(data: Dictionary) -> Dictionary:
	match String(data.get("targetType", "")):
		"wall":
			var wall_id := String(data.get("targetWallId", ""))
			if wall_id != "":
				return {"type": "wall", "wallId": wall_id}
		"actor":
			var actor_id := String(data.get("targetActorId", ""))
			if actor_id != "":
				return {"type": "actor", "actorId": actor_id}
	return {}

## Nearest wall not yet owned by the player, searching all of WallManager (not
## just nearby_walls) so the fallback can still find a target from far away.
## Walls more than 5 m above the player (rooftop/elevated, unreachable without
## climbing) are skipped so the fallback never sends the agent to a roof wall.
func _nearest_unowned_wall() -> String:
	if _player == null:
		return ""
	var best_id := ""
	var best_dist := INF
	var player_y: float = _player.global_position.y
	for wall_id in WallManager.wall_nodes:
		var state := ""
		if WallManager.wall_states.has(wall_id):
			state = String(WallManager.wall_states[wall_id].get("state", ""))
		if state.begins_with("player_"):
			continue
		# Territory-neutral walls (e.g. glass) don't count toward district influence —
		# skip them so the agent targets walls that actually advance claim_district objectives.
		if _is_neutral(String(wall_id)):
			continue
		var node = WallManager.wall_nodes[wall_id]
		if node == null:
			continue
		# Skip walls significantly above the player — they require climbing and
		# the straight-line navigator cannot reach them from the ground.
		if node.global_position.y - player_y > 5.0:
			continue
		var dist: float = _player.global_position.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_id = String(wall_id)
	return best_id

func _resolve_mission_wall(ref: String) -> String:
	if ref == "":
		return ""
	if ref.begins_with("@"):
		return String(MissionManager.remembered.get(ref.substr(1), ""))
	return ref

func _legal_actions() -> Array:
	if not GameState.alias_chosen:
		return ["paint", "wait"]
	var actions := [
		"select_can", "cycle_color", "cycle_cap", "look", "move",
		"stop", "wait",
	]
	if not _nearby_walls().is_empty():
		actions.append("aim_at")
		actions.append("goto_wall")
	if not _nearby_actors().is_empty():
		actions.append("goto_actor")
	var cur_obj: Dictionary = MissionManager.current_objective()
	if not _objective_target(cur_obj).is_empty():
		actions.append("goto_objective")
	if String(cur_obj.get("type", "")) == "paint" and cur_obj.has("wall"):
		var paint_wall_id := _resolve_mission_wall(String(cur_obj.get("wall", "")))
		if paint_wall_id != "" and WallManager.wall_nodes.has(paint_wall_id):
			actions.append("paint_objective")
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
	# Expose a generic interact for NPC / pickup prompts that aren't paint or rest.
	if "[E]" in prompt and not "Paint" in prompt and not "Rest" in prompt:
		actions.append("interact")
	if not actions.has("interact") and _objective_actor_in_range():
		actions.append("interact")
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
	if not GameState.alias_chosen and action not in ["paint", "wait"]:
		return {"ok": false, "error": "alias modal is active"}
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
		"interact":
			if not _interact_objective_actor():
				_press("interact")
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
			_begin_nav_capture()
			_aim_target = wall
		"goto_wall":
			var wall := String(data.get("wallId", ""))
			if not WallManager.wall_nodes.has(wall):
				# Soft fallback: no valid wallId supplied — pick the nearest unowned wall.
				wall = _nearest_unowned_wall()
				if wall == "":
					return {"ok": false, "error": "goto_wall: no wallId and no reachable wall found"}
			_clear_holds()
			_aim_target = ""
			_goto_actor = ""
			_begin_nav_capture()
			_goto_target = wall
		"goto_actor":
			var actor_id := String(data.get("actorId", ""))
			if _actor_node(actor_id) == null:
				return {"ok": false, "error": "unknown actorId: %s" % actor_id}
			_clear_holds()
			_aim_target = ""
			_goto_target = ""
			_begin_nav_capture()
			_goto_actor = actor_id
		"paint_objective":
			var pobj: Dictionary = MissionManager.current_objective()
			if pobj.is_empty() or String(pobj.get("type", "")) != "paint":
				return {"ok": false, "error": "current objective is not a paint task"}
			var wall_ref := String(pobj.get("wall", ""))
			if wall_ref == "":
				return {"ok": false, "error": "paint objective has no specific wall target"}
			var resolved_wall := _resolve_mission_wall(wall_ref)
			if resolved_wall == "" or not WallManager.wall_nodes.has(resolved_wall):
				return {"ok": false, "error": "cannot resolve objective wall: %s" % wall_ref}
			# If the macro is already running for this wall, don't restart it — let
			# the existing navigate→aim→paint sequence complete uninterrupted.
			if _paint_obj_wall == resolved_wall:
				return {"ok": true, "action": "paint_objective", "status": "macro_running"}
			var types: Array = pobj.get("graffitiTypes", [])
			var required_slot := _graffiti_type_slot(String(types[0]) if not types.is_empty() else "")
			_clear_holds()
			_aim_target = ""
			_goto_actor = ""
			_goto_target = ""
			_paint_obj_wall = resolved_wall
			_paint_obj_can_slot = required_slot
			_paint_obj_can_selected = false
			_begin_nav_capture()
			_goto_target = resolved_wall
		"goto_objective":
			var target := _action_objective_target(data)
			if target.is_empty():
				target = _objective_target(MissionManager.current_objective())
			if target.is_empty():
				return {"ok": false, "error": "objective has no navigation target"}
			match String(target.get("type", "")):
				"wall":
					var wall := String(target.get("wallId", ""))
					if not WallManager.wall_nodes.has(wall):
						return {"ok": false, "error": "unknown objective wallId: %s" % wall}
					_clear_holds()
					_aim_target = ""
					_goto_actor = ""
					_begin_nav_capture()
					_goto_target = wall
				"actor":
					var actor_id := String(target.get("actorId", ""))
					if _actor_node(actor_id) == null:
						return {"ok": false, "error": "unknown objective actorId: %s" % actor_id}
					_clear_holds()
					_aim_target = ""
					_goto_target = ""
					_begin_nav_capture()
					_goto_actor = actor_id
				_:
					return {"ok": false, "error": "unsupported objective target"}
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
