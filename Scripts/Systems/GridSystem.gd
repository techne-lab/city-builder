extends Node2D
class_name GridSystem

## Grid settings (MVP)
@export var cell_size: int = 32
@export var grid_width: int = 40
@export var grid_height: int = 25
@export var show_grid: bool = true
@export var show_origin_marker: bool = true

## Random blocked cells (cannot place buildings)
@export var blocked_spawn_interval_sec: float = 10.0
@export var blocked_cell_color: Color = Color(1, 0.2, 0.2, 0.35)

## Visuals (placeholders)
@export var grid_color: Color = Color(1, 1, 1, 0.15)
@export var grid_border_color: Color = Color(1, 1, 1, 0.35)
@export var origin_color: Color = Color(1, 0.6, 0.2, 0.8)

# Occupancy for 1x1 placement: key = Vector2i cell, value = Variant (optional building reference/id)
var _occupied: Dictionary = {}
var _blocked: Dictionary = {} # key = Vector2i cell, value = true

var _blocked_timer: Timer
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_blocked_timer = Timer.new()
	_blocked_timer.name = "BlockedCellSpawn"
	_blocked_timer.one_shot = false
	_blocked_timer.autostart = true
	_blocked_timer.wait_time = maxf(blocked_spawn_interval_sec, 0.1)
	add_child(_blocked_timer)
	_blocked_timer.timeout.connect(_spawn_random_blocked_cell)
	queue_redraw()

func _draw() -> void:
	if show_grid:
		_draw_grid()
	_draw_blocked_cells()
	if show_origin_marker:
		_draw_origin()

func _draw_grid() -> void:
	var w_px := grid_width * cell_size
	var h_px := grid_height * cell_size

	# Border
	draw_rect(Rect2(Vector2.ZERO, Vector2(w_px, h_px)), grid_border_color, false, 2.0)

	# Vertical lines
	for x in range(1, grid_width):
		var px := float(x * cell_size)
		draw_line(Vector2(px, 0), Vector2(px, h_px), grid_color, 1.0)

	# Horizontal lines
	for y in range(1, grid_height):
		var py := float(y * cell_size)
		draw_line(Vector2(0, py), Vector2(w_px, py), grid_color, 1.0)

func _draw_origin() -> void:
	# Small cross at (0,0) to help with placement/orientation.
	draw_line(Vector2(-10, 0), Vector2(10, 0), origin_color, 2.0)
	draw_line(Vector2(0, -10), Vector2(0, 10), origin_color, 2.0)

func _draw_blocked_cells() -> void:
	if _blocked.is_empty():
		return
	for k in _blocked.keys():
		var cell := k as Vector2i
		var top_left := cell_to_local_top_left(cell)
		draw_rect(Rect2(top_left, Vector2(cell_size, cell_size)), blocked_cell_color, true)

## --- Coordinate conversions ---

func world_to_cell(world_pos: Vector2) -> Vector2i:
	# Grid is local to this node: (0,0) is top-left of the grid.
	var local := to_local(world_pos)
	return Vector2i(
		floori(local.x / float(cell_size)),
		floori(local.y / float(cell_size))
	)

func cell_to_local_top_left(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size, cell.y * cell_size)

func cell_to_world_top_left(cell: Vector2i) -> Vector2:
	return to_global(cell_to_local_top_left(cell))

func cell_to_world_center(cell: Vector2i) -> Vector2:
	return cell_to_world_top_left(cell) + Vector2(cell_size, cell_size) * 0.5

func get_mouse_cell() -> Vector2i:
	# Works when node is in the active viewport.
	return world_to_cell(get_global_mouse_position())

func get_snapped_world_pos_for_1x1(world_pos: Vector2) -> Vector2:
	# For 1x1 sprites/placeholder rectangles anchored top-left.
	return cell_to_world_top_left(world_to_cell(world_pos))

## --- Bounds & occupancy (1x1 only) ---

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_height

func is_cell_free(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	if _blocked.has(cell):
		return false
	return not _occupied.has(cell)

func occupy_cell(cell: Vector2i, payload: Variant = true) -> bool:
	# Returns true if the cell was free and is now occupied.
	if not is_cell_free(cell):
		return false
	_occupied[cell] = payload
	return true

func free_cell(cell: Vector2i) -> void:
	_occupied.erase(cell)

func clear() -> void:
	_occupied.clear()
	_blocked.clear()
	queue_redraw()

func get_occupied_payload(cell: Vector2i) -> Variant:
	return _occupied.get(cell, null)

func can_place_1x1_at_world(world_pos: Vector2) -> bool:
	var cell := world_to_cell(world_pos)
	return is_cell_free(cell)

func _spawn_random_blocked_cell() -> void:
	# Pick a random free cell. If grid is full, do nothing.
	var attempts := 64
	while attempts > 0:
		attempts -= 1
		var cell := Vector2i(_rng.randi_range(0, grid_width - 1), _rng.randi_range(0, grid_height - 1))
		if is_cell_free(cell):
			_blocked[cell] = true
			queue_redraw()
			return

