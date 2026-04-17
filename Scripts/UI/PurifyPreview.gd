extends Node2D
class_name PurifyPreview

const GridSystemScript := preload("res://Scripts/Systems/GridSystem.gd")

@export var grid_path: NodePath

@export var fill_color: Color = Color(0.45, 0.9, 1.0, 0.18)
@export var outline_color: Color = Color(0.45, 0.9, 1.0, 0.55)
@export var outline_width: float = 2.0

var _grid: GridSystemScript
var _cell: Vector2i = Vector2i(-999, -999)

func _ready() -> void:
	_grid = get_node_or_null(grid_path) as GridSystemScript
	# We draw in grid-local coordinates; keep our own transform neutral.
	position = Vector2.ZERO
	z_index = 50
	visible = false
	set_process(true)

func set_enabled(enabled: bool) -> void:
	visible = enabled
	if enabled:
		queue_redraw()

func _process(_delta: float) -> void:
	if not visible:
		return
	if _grid == null:
		_grid = get_node_or_null(grid_path) as GridSystemScript
		if _grid == null:
			return
	var c := _grid.get_mouse_cell()
	if c != _cell:
		_cell = c
		queue_redraw()

func _draw() -> void:
	if not visible:
		return
	if _grid == null:
		return

	var cs := _grid.cell_size
	# 3x3 centered on hovered cell.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := _cell + Vector2i(dx, dy)
			if not _grid.is_in_bounds(c):
				continue
			var top_left := _grid.cell_to_local_top_left(c)
			var r := Rect2(top_left, Vector2(cs, cs))
			draw_rect(r, fill_color, true)
			draw_rect(r, outline_color, false, outline_width)

