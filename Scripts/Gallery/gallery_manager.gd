extends Node
## Gallery commissions (Milestone 21 — Plan.md §18, §43). Vesper the
## gallery contact buys freehand canvases once the writer is Known:
## the Milestone 14 canvas becomes the gameplay, and the freehand
## style multiplier becomes the judge's score. An accepted canvas pays
## cash and public rep but costs crew rep — the §11 public/crew split
## in minimal form, tracked as the one value GameState.crew_rep.
## Autoloaded as GalleryManager (after the managers it pays into,
## before SaveManager).

signal commission_started(commission: Dictionary)
signal commission_resolved(result: Dictionary)
signal gallery_event(message: String)

const GALLERY_PATH := "res://Data/gallery.json"
const DataLoader := preload("res://Scripts/Data/data_loader.gd")

var config: Dictionary = {}
var commission_active := false
var sales: Array = []  # {score, cash, rep} per accepted canvas — JSON-safe

func _ready() -> void:
	var parsed: Variant = DataLoader.load_json(GALLERY_PATH, "GalleryManager")
	if parsed is Dictionary:
		config = parsed
		DataLoader.require_fields(config,
			["contactName", "minRank", "canvasLabel", "canvasSize",
			"basePay", "repBase", "crewRepCost", "acceptScore"],
			"GalleryManager: gallery config")

## §43 "appears at rank Known": the gallery only deals with names.
func is_unlocked() -> bool:
	return GameState.rank_index(GameState.rank) \
		>= GameState.rank_index(String(config.get("minRank", "Known")))

## Why a commission can't start right now, or "" when it can.
func commission_block_reason() -> String:
	if config.is_empty():
		return "The gallery isn't buying."
	if not is_unlocked():
		return "Vesper only buys from writers who are %s." % String(config.get("minRank", "Known"))
	if not GameState.is_type_unlocked("piece"):
		return "Gallery work needs the Piece can unlocked."
	if commission_active:
		return "You already have a canvas on the easel."
	if GameState.paint < _paint_cost():
		return "Not enough paint for a canvas."
	return ""

func start_commission() -> bool:
	var block := commission_block_reason()
	if block != "":
		gallery_event.emit(block)
		return false
	commission_active = true
	commission_started.emit({
		"label": String(config.get("canvasLabel", "Gallery canvas")),
		"size": config.get("canvasSize", [3.0, 2.0]),
	})
	gallery_event.emit("Vesper stretches a canvas. Make it worth hanging — she judges coverage and color.")
	return true

func cancel_commission() -> void:
	if not commission_active:
		return
	commission_active = false
	gallery_event.emit("You leave the canvas blank. Vesper shrugs.")

## The judge's score IS the freehand style multiplier (Plan_v2.md
## Milestone 21). Accepted work pays cash (scaled by Hustle like other
## income) plus public rep and costs crew rep; weak work is refused —
## paint spent, nothing paid, no crew rep lost (you didn't sell out).
func submit(_image: Image, colors_used: int, coverage: float) -> Dictionary:
	if not commission_active:
		return {"ok": false, "reason": "No commission in progress."}
	if not GameState.try_spend_paint(_paint_cost()):
		return {"ok": false, "reason": "Not enough paint."}
	commission_active = false
	var score := WallManager.freehand_style_multiplier(colors_used, coverage)
	if score < float(config.get("acceptScore", 1.0)):
		var rejection := {"ok": true, "accepted": false, "score": score}
		gallery_event.emit("Vesper waves it off — \"Not gallery-ready.\" (score x%.2f)" % score)
		commission_resolved.emit(rejection)
		return rejection
	var cash := roundi(float(config.get("basePay", 60)) * score * StatsManager.delivery_multiplier())
	var rep := roundi(float(config.get("repBase", 25)) * score)
	var crew_cost := int(config.get("crewRepCost", 15))
	GameState.add_cash(cash)
	GameState.add_reputation(rep)
	GameState.add_crew_rep(-crew_cost)
	StatsManager.add_xp("hustle", int(config.get("hustleXp", 10)))
	sales.append({"score": score, "cash": cash, "rep": rep})
	var result := {"ok": true, "accepted": true, "score": score,
		"cash": cash, "rep": rep, "crewRep": -crew_cost}
	gallery_event.emit("SOLD — Vesper scores it x%.2f. +$%d, +%d public rep… and the street hears about it (crew rep -%d)." % [
		score, cash, rep, crew_cost])
	MissionManager.notify_gallery_sale()
	commission_resolved.emit(result)
	return result

func sales_count() -> int:
	return sales.size()

func save_state() -> Dictionary:
	return {"sales": sales.duplicate(true)}

func load_state(data: Dictionary) -> void:
	sales = data.get("sales", []).duplicate(true)
	# The loaded world may not match a half-painted canvas.
	commission_active = false

func _paint_cost() -> int:
	return SupplyManager.paint_cost(WallManager.styles.get("piece", {}))
