extends Node
class_name CameraDragPan

@export var camera_path: NodePath
@export var grid_path: NodePath

@export var drag_button: MouseButton = MOUSE_BUTTON_RIGHT
@export var enabled: bool = true

var _camera: Camera2D
var _grid: Node2D
var _dragging: bool = false

func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera2D
	if _camera == null:
		push_error("CameraDragPan: camera_path is not set or invalid.")
	_grid = get_node_or_null(grid_path) as Node2D
	if _grid == null:
		push_error("CameraDragPan: grid_path is not set or invalid.")

func _input(event: InputEvent) -> void:
	if not enabled or _camera == null:
		return

	# Don't start or continue a drag when interacting with UI.
	var vp := get_viewport()
	if vp != null and vp.gui_get_hovered_control() != null:
		if event is InputEventMouseButton and event.button_index == drag_button and not event.pressed:
			_dragging = false
		return

	if event is InputEventMouseButton and event.button_index == drag_button:
		_dragging = event.pressed
		return

	if _dragging and event is InputEventMouseMotion:
		# Dragging the terrain: move camera opposite to mouse motion.
		var rel := (event as InputEventMouseMotion).relative
		var z := _camera.zoom
		var denom := Vector2(maxf(z.x, 0.001), maxf(z.y, 0.001))
		_camera.global_position -= rel / denom
		_clamp_to_grid_bounds()

func _clamp_to_grid_bounds() -> void:
	# Best-effort clamp so you can't lose the map.
	if _grid == null:
		return
	if not (_grid.has_method("grid_width") and _grid.has_method("grid_height") and _grid.has_method("cell_size")):
		# GridSystem stores those as exported vars; without a typed reference we can't reliably read them.
		pass

	var cell_size: float = float(_grid.get("cell_size"))
	var w: float = float(_grid.get("grid_width")) * cell_size
	var h: float = float(_grid.get("grid_height")) * cell_size

	var view_size := get_viewport().get_visible_rect().size
	var half := (view_size * 0.5) / Vector2(maxf(_camera.zoom.x, 0.001), maxf(_camera.zoom.y, 0.001))

	var min_x := _grid.global_position.x + half.x
	var min_y := _grid.global_position.y + half.y
	var max_x := _grid.global_position.x + w - half.x
	var max_y := _grid.global_position.y + h - half.y

	# If viewport is larger than the grid, just keep centered on grid.
	if min_x > max_x:
		_camera.global_position.x = _grid.global_position.x + w * 0.5
	else:
		_camera.global_position.x = clampf(_camera.global_position.x, min_x, max_x)
	if min_y > max_y:
		_camera.global_position.y = _grid.global_position.y + h * 0.5
	else:
		_camera.global_position.y = clampf(_camera.global_position.y, min_y, max_y)
