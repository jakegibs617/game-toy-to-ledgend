extends RefCounted
## Shared UI builders (ROADMAP.md §3.2): the outlined label and the
## accent-bordered dark panel every HUD piece uses. One recipe so the
## margins can't drift between panels again.
## Preload this script (CLAUDE.md headless class-cache rule):
##   const UiKit := preload("res://Scripts/UI/ui_kit.gd")

static func make_label(parent: Control, font_size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = color
	settings.outline_size = 6
	settings.outline_color = Color(0, 0, 0, 0.85)
	label.label_settings = settings
	parent.add_child(label)
	return label

## The HUD panel recipe: dark translucent box, rounded corners, accent
## left border. Modal panels read better slightly more opaque
## (bg_alpha 0.92) than passive HUD chrome (0.82).
static func panel_style(accent: Color, bg_alpha := 0.82,
		margin_h := 12.0, margin_v := 6.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.09, bg_alpha)
	style.set_corner_radius_all(6)
	style.border_color = accent
	style.border_width_left = 3
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	return style

## Panels that ARE the PanelContainer (blackbook, freehand) style
## themselves; pass mouse-transparent for read-only panels.
static func apply_panel_style(panel: PanelContainer, accent: Color, bg_alpha := 0.82,
		margin_h := 12.0, margin_v := 6.0, mouse_transparent := false) -> void:
	panel.add_theme_stylebox_override("panel", panel_style(accent, bg_alpha, margin_h, margin_v))
	if mouse_transparent:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func make_panel(accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	apply_panel_style(panel, accent, 0.82, 12.0, 6.0, true)
	return panel
