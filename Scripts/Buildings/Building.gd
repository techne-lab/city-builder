extends Node2D
class_name Building

const BuildingDataScript := preload("res://Scripts/Data/BuildingData.gd")

@export var cell: Vector2i = Vector2i(-999, -999)
@export var size_cells: Vector2i = Vector2i(1, 1)
@export var cell_size: int = 32

@export var building_type: int = 0
@export var fill_color: Color = Color.WHITE
@export var outline_color: Color = Color(0, 0, 0, 0.35)

@export var building_id: StringName = &""

var building_data: Resource
var _production_timer: Timer
var _resource_manager: Node
var _place_tween: Tween

func set_visual(type_id: int, color: Color) -> void:
	building_type = type_id
	fill_color = color
	queue_redraw()

func apply_building_data(id: StringName, data: Resource) -> void:
	building_id = id
	building_data = data

	var d := building_data as BuildingDataScript
	if d != null:
		set_visual(building_type, d.color)
		_setup_production_from_data(d)
	else:
		_clear_production()

func set_cell_and_snap(new_cell: Vector2i, top_left_world: Vector2, new_cell_size: int) -> void:
	cell = new_cell
	cell_size = new_cell_size
	global_position = top_left_world
	queue_redraw()

func _setup_production_from_data(d: Resource) -> void:
	_clear_production()

	var data := d as BuildingDataScript
	if data == null:
		return
	if not data.is_producer():
		return

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
	if _resource_manager == null:
		_resource_manager = get_node_or_null("/root/ResourceManager")
	if _resource_manager == null:
		return
	_resource_manager.add(data.produces_resource, data.production_amount)

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
	# Simple placeholder: filled rect + outline, anchored top-left.
	var px_size := Vector2(size_cells.x * cell_size, size_cells.y * cell_size)
	draw_rect(Rect2(Vector2.ZERO, px_size), fill_color, true)
	draw_rect(Rect2(Vector2.ZERO, px_size), outline_color, false, 2.0)

