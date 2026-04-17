extends Node2D
class_name Building

const BuildingDataScript := preload("res://Scripts/Data/BuildingData.gd")

@export var cell: Vector2i = Vector2i(-999, -999)
@export var size_cells: Vector2i = Vector2i(1, 1)
@export var cell_size: int = 32

@export var building_type: int = 0
@export var fill_color: Color = Color.WHITE
@export var outline_color: Color = Color(0, 0, 0, 0.35)
@export var outline_width: float = 2.0

@export var upgraded_outline_color: Color = Color(1.0, 0.9, 0.25, 0.95)
@export var upgraded_outline_width: float = 3.5

@export var building_id: StringName = &""

var building_data: Resource
var _production_timer: Timer
var _resource_manager: Node
var _place_tween: Tween
var _sprite: Sprite2D

# Current upgrade level (1–5).
var level: int = 1

# Production buildings require a worker to operate (assigned by GameManager).
var _worker_assigned: bool = true
var worker_assigned: bool:
	get:
		return _worker_assigned
	set(value):
		if _worker_assigned == value:
			return
		_worker_assigned = value
		queue_redraw()

# Visual indicator for worker assignment (production buildings only)
@export var show_worker_indicator: bool = true
@export var worker_indicator_radius_px: float = 5.0
@export var worker_indicator_margin_px: float = 6.0
@export var worker_assigned_color: Color = Color(0.25, 1.0, 0.35, 0.95)
@export var worker_unassigned_color: Color = Color(1.0, 0.25, 0.25, 0.95)

func set_visual(type_id: int, color: Color) -> void:
	building_type = type_id
	fill_color = color
	queue_redraw()

func _ready() -> void:
	_ensure_sprite()

func _ensure_sprite() -> void:
	if _sprite != null:
		return
	_sprite = get_node_or_null("Sprite") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		add_child(_sprite)
	# We keep the Building node anchored top-left; the sprite fits the cell.
	_sprite.centered = false
	_sprite.position = Vector2.ZERO
	_sprite.z_index = 0

func _set_sprite_texture(tex: Texture2D) -> void:
	_ensure_sprite()
	_sprite.texture = tex
	_sprite.visible = tex != null

func _sync_sprite_scale() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	# Source art is 64x64; scale it to the current cell size (default 32).
	var s := float(cell_size) / 64.0
	_sprite.scale = Vector2(s, s)

func apply_building_data(id: StringName, data: Resource) -> void:
	building_id = id
	building_data = data

	var d := building_data as BuildingDataScript
	if d != null:
		set_visual(building_type, d.color)
		_set_sprite_texture(d.sprite)
		_sync_sprite_scale()
		_apply_upgrade_visuals()
		_setup_production_from_data(d)
	else:
		_set_sprite_texture(null)
		_clear_production()
		_apply_upgrade_visuals()

func _apply_upgrade_visuals() -> void:
	# Outline and badge are now driven by `level` inside _draw(); just trigger redraw.
	queue_redraw()

func get_effective_production() -> int:
	var data := building_data as BuildingDataScript
	if data == null:
		return 0
	var bonus: float = data.production_level_bonus
	return int(float(data.production_amount) * (1.0 + float(level - 1) * bonus))

func get_upgrade_cost() -> Dictionary:
	var data := building_data as BuildingDataScript
	if data == null:
		return {}
	var base: Dictionary = data.upgrade_cost
	if base.is_empty():
		return {}
	var scale_factor: float = pow(data.upgrade_cost_scale, float(level - 1))
	var result := {}
	for k in base.keys():
		var v := int(base[k])
		result[k] = maxi(1, roundi(float(v) * scale_factor))
	return result

func upgrade() -> void:
	var data := building_data as BuildingDataScript
	var max_lv: int = data.max_level if data != null else 5
	level = mini(level + 1, max_lv)
	queue_redraw()

func set_cell_and_snap(new_cell: Vector2i, top_left_world: Vector2, new_cell_size: int) -> void:
	cell = new_cell
	cell_size = new_cell_size
	global_position = top_left_world
	_sync_sprite_scale()
	queue_redraw()

func _setup_production_from_data(d: Resource) -> void:
	_clear_production()

	var data := d as BuildingDataScript
	if data == null:
		return
	if not data.is_producer():
		return
	# Producers may be disabled if not enough population is available.
	# (Assignment is handled externally; default is enabled.)
	worker_assigned = true

	_production_timer = Timer.new()
	_production_timer.name = "ProductionTimer"
	_production_timer.one_shot = false
	_production_timer.autostart = true
	_production_timer.wait_time = data.production_interval_sec
	add_child(_production_timer)
	_production_timer.timeout.connect(_on_production_timeout)

func _clear_production() -> void:
	if _production_timer != null:
		_production_timer.queue_free()
		_production_timer = null

func _on_production_timeout() -> void:
	var data := building_data as BuildingDataScript
	if data == null:
		return
	if not data.is_producer():
		return
	if not worker_assigned:
		return
	if _resource_manager == null:
		_resource_manager = get_node_or_null("/root/ResourceManager")
	if _resource_manager == null:
		return
	_resource_manager.add(data.produces_resource, get_effective_production())

func play_place_feedback() -> void:
	# Minimal "pop" animation to confirm placement.
	if _place_tween != null and _place_tween.is_running():
		_place_tween.kill()

	var base_scale := scale
	scale = base_scale * 0.92

	_place_tween = create_tween()
	_place_tween.set_trans(Tween.TRANS_BACK)
	_place_tween.set_ease(Tween.EASE_OUT)
	_place_tween.tween_property(self, "scale", base_scale, 0.14)

func _draw() -> void:
	# Visuals: sprite when available; otherwise placeholder rect. Always keep outline for readability.
	var px_size := Vector2(size_cells.x * cell_size, size_cells.y * cell_size)
	if _sprite == null or _sprite.texture == null:
		draw_rect(Rect2(Vector2.ZERO, px_size), fill_color, true)

	# Outline color and width scale with level.
	var oc: Color
	var ow: float
	match level:
		1:
			oc = Color(0, 0, 0, 0.35)
			ow = 2.0
		2:
			oc = Color(0.80, 0.50, 0.20, 0.95)  # Bronze
			ow = 2.5
		3:
			oc = Color(0.75, 0.75, 0.75, 0.95)  # Silver
			ow = 3.0
		4:
			oc = Color(1.0, 0.85, 0.0, 0.95)    # Gold
			ow = 3.5
		_:  # Level 5+
			oc = Color(0.0, 0.95, 1.0, 0.95)    # Cyan
			ow = 4.0
	draw_rect(Rect2(Vector2.ZERO, px_size), oc, false, ow)

	# Level badge: filled circle in the bottom-right corner (hidden at level 1).
	if level >= 2:
		var badge_r: float = 7.0
		var badge_margin: float = 4.0
		var badge_pos := Vector2(px_size.x - badge_margin - badge_r, px_size.y - badge_margin - badge_r)
		var badge_color: Color
		match level:
			2: badge_color = Color(0.80, 0.50, 0.20, 0.95)
			3: badge_color = Color(0.75, 0.75, 0.75, 0.95)
			4: badge_color = Color(1.0, 0.85, 0.0, 0.95)
			_: badge_color = Color(0.0, 0.95, 1.0, 0.95)
		draw_circle(badge_pos, badge_r, badge_color)
		draw_circle(badge_pos, badge_r, Color(0, 0, 0, 0.5), false, 1.0)
		var font := ThemeDB.fallback_font
		var font_size: int = 9
		var lv_str := str(level)
		var str_size := font.get_string_size(lv_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := badge_pos - str_size * 0.5 + Vector2(0.0, str_size.y * 0.5 - 1.0)
		draw_string(font, text_pos, lv_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.08, 0.08, 0.08, 1.0))

	# Worker indicator circle (top-right corner).
	if not show_worker_indicator:
		return
	var d := building_data as BuildingDataScript
	if d == null or not d.is_producer():
		return
	var r := worker_indicator_radius_px
	var pos := Vector2(px_size.x - worker_indicator_margin_px - r, worker_indicator_margin_px + r)
	draw_circle(pos, r, (worker_assigned_color if worker_assigned else worker_unassigned_color))

