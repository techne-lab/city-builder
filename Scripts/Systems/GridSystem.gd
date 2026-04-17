extends Node2D
class_name GridSystem

signal building_corrupted(building: Node, cell: Vector2i, building_id: StringName)

const BuildingScript := preload("res://Scripts/Buildings/Building.gd")
const BuildingDataScript := preload("res://Scripts/Data/BuildingData.gd")

## Grid settings (MVP)
@export var cell_size: int = 32
@export var grid_width: int = 40
@export var grid_height: int = 25
@export var show_grid: bool = true
@export var show_origin_marker: bool = true

## Random blocked cells (cannot place buildings)
@export var blocked_spawn_interval_sec: float = 5.0
@export var blocked_cell_color: Color = Color(1, 0.2, 0.2, 0.35)

## Stone tiles (cannot build on)
@export var stone_spawn_count: int = 100
@export var stone_cell_color: Color = Color(0.52, 0.55, 0.6, 0.92)
@export var stone_detail_color: Color = Color(0.75, 0.78, 0.83, 0.65)

## Visuals (placeholders)
@export var grid_color: Color = Color(1, 1, 1, 0.15)
@export var grid_border_color: Color = Color(1, 1, 1, 0.35)
@export var origin_color: Color = Color(1, 0.6, 0.2, 0.8)

## Ground tiles (lightweight 2-variant grass)
@export var show_ground: bool = true
@export var grass_tile_a: Texture2D
@export var grass_tile_b: Texture2D

# Occupancy for 1x1 placement: key = Vector2i cell, value = Variant (optional building reference/id)
var _occupied: Dictionary = {}
var _blocked: Dictionary = {} # key = Vector2i cell, value = true
var _stone: Dictionary = {} # key = Vector2i cell, value = true

var _blocked_timer: Timer
var _rng := RandomNumberGenerator.new()
var _infection_time_by_cell: Dictionary = {} # key = Vector2i, value = float seconds
var _building_corruption_time_by_cell: Dictionary = {} # key = Vector2i, value = float seconds
var _corrupted_buildings: Dictionary = {} # key = Vector2i, value = true

const INFECTION_REQUIRED_ADJ_BLOCKED: int = 2
const INFECTION_DURATION_SEC: float = 6.0
const BUILDING_CORRUPTION_DURATION_SEC: float = 20.0

func _ready() -> void:
	_rng.randomize()
	# Avoid hard preloads here (keeps tooling happy); Godot will load cached textures.
	if grass_tile_a == null:
		grass_tile_a = load("res://assets/tiles/grass_a.png") as Texture2D
	if grass_tile_b == null:
		grass_tile_b = load("res://assets/tiles/grass_b.png") as Texture2D
	_blocked_timer = Timer.new()
	_blocked_timer.name = "BlockedCellSpawn"
	_blocked_timer.one_shot = false
	_blocked_timer.autostart = true
	_blocked_timer.wait_time = maxf(blocked_spawn_interval_sec, 0.1)
	add_child(_blocked_timer)
	_blocked_timer.timeout.connect(_spawn_random_blocked_cell)
	_spawn_initial_blocked_border_cell()
	_spawn_initial_stones()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_update_infection(delta)
	_update_building_corruption(delta)

func _draw() -> void:
	if show_ground:
		_draw_ground()
	if show_grid:
		_draw_grid()
	_draw_stone_cells()
	_draw_blocked_cells()
	if show_origin_marker:
		_draw_origin()

func _draw_stone_cells() -> void:
	if _stone.is_empty():
		return
	for k in _stone.keys():
		var cell := k as Vector2i
		var top_left := cell_to_local_top_left(cell)
		var r := Rect2(top_left, Vector2(cell_size, cell_size))
		draw_rect(r, stone_cell_color, true)
		draw_circle(top_left + Vector2(cell_size * 0.35, cell_size * 0.45), maxf(2.0, cell_size * 0.10), stone_detail_color)
		draw_circle(top_left + Vector2(cell_size * 0.62, cell_size * 0.62), maxf(1.5, cell_size * 0.07), stone_detail_color)

func _draw_ground() -> void:
	# Deterministic variation to reduce repetition (no RNG needed).
	if grass_tile_a == null:
		return
	var w_px := grid_width * cell_size
	var h_px := grid_height * cell_size
	draw_rect(Rect2(Vector2.ZERO, Vector2(w_px, h_px)), Color(0.49, 0.72, 0.42, 1.0), true)

	for y in range(grid_height):
		for x in range(grid_width):
			var top_left := Vector2(x * cell_size, y * cell_size)
			var key := int(x * 73856093) ^ int(y * 19349663)
			var pick: int = abs(key) % 7
			var tex := (grass_tile_b if (pick == 0 or pick == 3) and grass_tile_b != null else grass_tile_a)
			draw_texture_rect(tex, Rect2(top_left, Vector2(cell_size, cell_size)), false)

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
	if _stone.has(cell):
		return false
	return not _occupied.has(cell)

func is_cell_stone(cell: Vector2i) -> bool:
	return _stone.has(cell)

func mine_stone(cell: Vector2i) -> bool:
	if not _stone.has(cell):
		return false
	_stone.erase(cell)
	queue_redraw()
	return true

func has_adjacent_building(cell: Vector2i) -> bool:
	# 4-neighborhood adjacency to already placed buildings.
	# Rule: walls do NOT count as expansion anchors.
	# Note: preview ghost is not in _occupied, so it doesn't affect this rule.
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for d in dirs:
		var n: Vector2i = cell + d
		var payload: Variant = get_occupied_payload(n)
		if payload is BuildingScript:
			if (payload as BuildingScript).building_id != &"wall":
				return true
	return false

func has_adjacent_building_or_wall(cell: Vector2i) -> bool:
	# 4-neighborhood adjacency to any placed building, including walls.
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for d in dirs:
		var n: Vector2i = cell + d
		if get_occupied_payload(n) is BuildingScript:
			return true
	return false

func _occupant_blocks_adjacent_infection(cell: Vector2i) -> bool:
	var payload: Variant = get_occupied_payload(cell)
	if payload is BuildingScript:
		var d := (payload as BuildingScript).building_data as BuildingDataScript
		return d != null and d.blocks_adjacent_infection
	return false

func _has_infection_blocker_neighbor(cell: Vector2i) -> bool:
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for d in dirs:
		if _occupant_blocks_adjacent_infection(cell + d):
			return true
	return false

func can_blocked_propagate() -> bool:
	# Returns true if a new blocked cell could be created given current state.
	# This checks both propagation systems:
	# - Adjacent spawn growth
	# - Infection growth (>=2 adjacent blocked for 10s on a player-adjacent free tile)

	# If there are no blocked cells left, propagation is impossible.
	if _blocked.is_empty():
		return false

	# 1) Adjacent growth: any free neighbor of an existing blocked cell.
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for k in _blocked.keys():
		var bcell := k as Vector2i
		for d in dirs:
			var n := bcell + d
			if is_cell_free(n):
				return true

	# 2) Infection growth: any currently-eligible tile (timer not required here, just possibility).
	for y in range(grid_height):
		for x in range(grid_width):
			var cell := Vector2i(x, y)
			if _blocked.has(cell):
				continue
			if _stone.has(cell):
				continue
			if _occupied.has(cell):
				continue
			if not has_adjacent_building(cell):
				continue
			if _has_infection_blocker_neighbor(cell):
				continue
			if _count_adjacent_blocked(cell) >= INFECTION_REQUIRED_ADJ_BLOCKED:
				return true

	return false

func _count_adjacent_blocked(cell: Vector2i) -> int:
	var n := 0
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for d in dirs:
		var c: Vector2i = cell + d
		if _blocked.has(c):
			n += 1
	return n

func _update_infection(delta: float) -> void:
	# Rule: if a player-adjacent free tile is adjacent to >=2 blocked tiles
	# continuously for 10s, it becomes blocked.
	# We treat "player tile" as any tile adjacent to an occupied (building) cell.
	if _occupied.is_empty() or _blocked.is_empty():
		_infection_time_by_cell.clear()
		return

	# Iterate whole grid (small in prototype: 40x25).
	for y in range(grid_height):
		for x in range(grid_width):
			var cell := Vector2i(x, y)
			if _blocked.has(cell):
				_infection_time_by_cell.erase(cell)
				continue
			# Don't infect stone tiles: they are a separate obstacle type.
			if _stone.has(cell):
				_infection_time_by_cell.erase(cell)
				continue
			# Don't infect occupied building tiles (we only turn terrain tiles red).
			if _occupied.has(cell):
				_infection_time_by_cell.erase(cell)
				continue
			# Only tiles within player's reachable area (adjacent to buildings).
			if not has_adjacent_building(cell):
				_infection_time_by_cell.erase(cell)
				continue
			# Walls (and similar): adjacent free tiles cannot be corrupted by red spread.
			if _has_infection_blocker_neighbor(cell):
				_infection_time_by_cell.erase(cell)
				continue
			# Must be a free tile (not blocked, not occupied) — already ensured.
			var adj := _count_adjacent_blocked(cell)
			if adj >= INFECTION_REQUIRED_ADJ_BLOCKED:
				var t: float = float(_infection_time_by_cell.get(cell, 0.0)) + delta
				if t >= INFECTION_DURATION_SEC:
					_blocked[cell] = true
					_infection_time_by_cell.erase(cell)
				else:
					_infection_time_by_cell[cell] = t
			else:
				_infection_time_by_cell.erase(cell)

	if not _infection_time_by_cell.is_empty():
		queue_redraw()

func occupy_cell(cell: Vector2i, payload: Variant = true) -> bool:
	# Returns true if the cell was free and is now occupied.
	if not is_cell_free(cell):
		return false
	_occupied[cell] = payload
	return true

func free_cell(cell: Vector2i) -> void:
	_occupied.erase(cell)
	_building_corruption_time_by_cell.erase(cell)
	_corrupted_buildings.erase(cell)

func clear() -> void:
	_occupied.clear()
	_blocked.clear()
	_stone.clear()
	_building_corruption_time_by_cell.clear()
	_corrupted_buildings.clear()
	queue_redraw()

func is_building_corrupted_at_cell(cell: Vector2i) -> bool:
	return _corrupted_buildings.has(cell)

func are_all_non_wall_buildings_corrupted() -> bool:
	var total := 0
	var corrupted := 0
	for k in _occupied.keys():
		var cell := k as Vector2i
		var payload: Variant = get_occupied_payload(cell)
		if not (payload is BuildingScript):
			continue
		var b := payload as BuildingScript
		if b.building_id == &"wall":
			continue
		total += 1
		if b.corrupted or is_building_corrupted_at_cell(cell):
			corrupted += 1
	return total > 0 and corrupted >= total

func _update_building_corruption(delta: float) -> void:
	# Rule: if a building (except walls) is adjacent to at least 1 blocked cell
	# continuously for 20s, the building becomes corrupted.
	if _occupied.is_empty() or _blocked.is_empty():
		_building_corruption_time_by_cell.clear()
		return

	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for k in _occupied.keys():
		var cell := k as Vector2i
		var payload: Variant = get_occupied_payload(cell)
		if not (payload is BuildingScript):
			_building_corruption_time_by_cell.erase(cell)
			continue
		var b := payload as BuildingScript
		if b.building_id == &"wall":
			_building_corruption_time_by_cell.erase(cell)
			continue
		if b.corrupted or _corrupted_buildings.has(cell):
			_building_corruption_time_by_cell.erase(cell)
			continue

		var adj_blocked := false
		for d in dirs:
			if _blocked.has(cell + d):
				adj_blocked = true
				break

		if adj_blocked:
			var t: float = float(_building_corruption_time_by_cell.get(cell, 0.0)) + delta
			if t >= BUILDING_CORRUPTION_DURATION_SEC:
				_corrupted_buildings[cell] = true
				b.corrupted = true
				_building_corruption_time_by_cell.erase(cell)
				emit_signal("building_corrupted", b, cell, b.building_id)
			else:
				_building_corruption_time_by_cell[cell] = t
		else:
			_building_corruption_time_by_cell.erase(cell)

func get_occupied_payload(cell: Vector2i) -> Variant:
	return _occupied.get(cell, null)

func is_cell_blocked(cell: Vector2i) -> bool:
	return _blocked.has(cell)

func get_cell_properties(cell: Vector2i) -> Dictionary:
	var props: Dictionary = {}
	props[&"cell"] = cell
	props[&"in_bounds"] = is_in_bounds(cell)
	props[&"blocked"] = is_cell_blocked(cell)
	props[&"stone"] = is_cell_stone(cell)
	var payload: Variant = get_occupied_payload(cell)
	props[&"occupied"] = payload != null
	props[&"occupant_name"] = (payload.name if (payload is Node) else "")
	if payload != null:
		# Building nodes expose building_id.
		if payload is BuildingScript:
			props[&"building_id"] = (payload as BuildingScript).building_id
	return props

func get_blocked_count() -> int:
	return _blocked.size()

func get_blocked_spawn_interval_sec() -> float:
	return blocked_spawn_interval_sec

func purify_3x3(center: Vector2i) -> int:
	# Removes blocked cells in a 3x3 area (returns how many were removed).
	var removed := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := center + Vector2i(dx, dy)
			if not is_in_bounds(c):
				continue
			if _blocked.erase(c):
				removed += 1
			_infection_time_by_cell.erase(c)
	if removed > 0:
		queue_redraw()
	return removed

func _spawn_initial_stones() -> void:
	# Spawn stone obstacles at start. Keep the center tile empty for the initial House.
	_stone.clear()
	var reserved := Vector2i(int(grid_width / 2.0), int(grid_height / 2.0))
	var target := clampi(stone_spawn_count, 0, grid_width * grid_height)
	var attempts := target * 12 + 200
	while _stone.size() < target and attempts > 0:
		attempts -= 1
		var cell := Vector2i(_rng.randi_range(0, grid_width - 1), _rng.randi_range(0, grid_height - 1))
		if cell == reserved:
			continue
		if _blocked.has(cell):
			continue
		if _occupied.has(cell):
			continue
		_stone[cell] = true

func _is_border_cell(cell: Vector2i) -> bool:
	return cell.x == 0 or cell.y == 0 or cell.x == grid_width - 1 or cell.y == grid_height - 1

func _random_border_cell() -> Vector2i:
	# Pick a random border cell.
	# Randomly choose which edge, then a coordinate along it.
	var edge := _rng.randi_range(0, 3)
	match edge:
		0: # top
			return Vector2i(_rng.randi_range(0, grid_width - 1), 0)
		1: # bottom
			return Vector2i(_rng.randi_range(0, grid_width - 1), grid_height - 1)
		2: # left
			return Vector2i(0, _rng.randi_range(0, grid_height - 1))
		_:# right
			return Vector2i(grid_width - 1, _rng.randi_range(0, grid_height - 1))

func _spawn_initial_blocked_border_cell() -> void:
	# At game start: place a first blocked cell on the border.
	var attempts := 128
	while attempts > 0:
		attempts -= 1
		var cell := _random_border_cell()
		if is_cell_free(cell):
			_blocked[cell] = true
			queue_redraw()
			return

func _spawn_blocked_adjacent_once() -> bool:
	# Spawn one blocked cell adjacent to an existing blocked cell.
	if _blocked.is_empty():
		return false
	var keys := _blocked.keys()
	var attempts := 96
	while attempts > 0:
		attempts -= 1
		var base := keys[_rng.randi_range(0, keys.size() - 1)] as Vector2i
		var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		var d: Vector2i = dirs[_rng.randi_range(0, dirs.size() - 1)]
		var candidate: Vector2i = base + d
		if is_cell_free(candidate):
			_blocked[candidate] = true
			return true
	return false

func can_place_1x1_at_world(world_pos: Vector2) -> bool:
	var cell := world_to_cell(world_pos)
	return is_cell_free(cell)

func _spawn_random_blocked_cell() -> void:
	# Every tick: grow blocked area by 2 cells adjacent to existing blocked cells.
	var spawned := 0
	var attempts := 6
	while spawned < 2 and attempts > 0:
		attempts -= 1
		if _spawn_blocked_adjacent_once():
			spawned += 1
	# Fallback: if no spawn was possible (unlikely), keep system alive by seeding the border again.
	if spawned == 0 and _blocked.is_empty():
		_spawn_initial_blocked_border_cell()
	queue_redraw()

