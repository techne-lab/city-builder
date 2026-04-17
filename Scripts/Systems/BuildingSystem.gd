extends Node2D
class_name BuildingSystem

signal selection_changed(building_id: StringName)
signal building_placed(building: Node2D, cell: Vector2i, building_id: StringName)
signal placement_denied(message: String)

const GridSystemScript := preload("res://Scripts/Systems/GridSystem.gd")
const BuildingScript := preload("res://Scripts/Buildings/Building.gd")
const BuildingDatabaseScript := preload("res://Scripts/Data/BuildingDatabase.gd")

@export var grid_path: NodePath
@export var building_db: Resource

var _resource_manager: Node

@export var preview_alpha: float = 0.55
@export var preview_ok_tint: Color = Color(0.35, 1.0, 0.45, 1) # green
@export var preview_blocked_tint: Color = Color(1.0, 0.25, 0.25, 1) # red

var selected_building_id: StringName = &"":
	set(value):
		selected_building_id = value
		_emit_selection_changed()
		_update_preview_visibility()

var _grid: Node2D
var _preview: Node2D
var _preview_cell: Vector2i = Vector2i(-999, -999)
var _gameplay_enabled: bool = true

func _ready() -> void:
	_grid = get_node_or_null(grid_path) as Node2D
	if _grid == null:
		push_error("BuildingSystem: grid_path is not set or invalid.")
		return
	if building_db == null:
		push_error("BuildingSystem: building_db is not set (assign a BuildingDatabase resource).")
		return
	_resource_manager = get_node_or_null("/root/ResourceManager")
	if _resource_manager == null:
		push_error("BuildingSystem: ResourceManager autoload not found.")

	_preview = BuildingScript.new()
	_preview.name = "Preview"
	_preview.z_index = 100
	_preview.modulate.a = preview_alpha
	add_child(_preview)

	_update_preview_visibility()
	set_process(true)

func _process(_delta: float) -> void:
	if not _gameplay_enabled:
		return
	if _grid == null:
		return
	if selected_building_id == &"":
		return

	var cell: Vector2i = (_grid as GridSystemScript).get_mouse_cell()
	if cell != _preview_cell:
		_preview_cell = cell
		_update_preview_at_cell(cell)
	else:
		# Still refresh tint in case occupancy changed.
		_update_preview_tint(cell)

func _unhandled_input(event: InputEvent) -> void:
	if not _gameplay_enabled:
		return
	if _grid == null:
		return
	if selected_building_id == &"":
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_place_at_mouse()

func select_building(id: StringName) -> void:
	selected_building_id = id

func cancel_selection() -> void:
	selected_building_id = &""

func set_gameplay_enabled(enabled: bool) -> void:
	_gameplay_enabled = enabled
	if not enabled:
		cancel_selection()
		if _preview != null:
			_preview.visible = false

func _try_place_at_mouse() -> void:
	var grid := _grid as GridSystemScript
	var cell: Vector2i = grid.get_mouse_cell()
	if not grid.is_cell_free(cell):
		_play_invalid_placement_feedback()
		return

	# Expansion rule: can only place adjacent to an existing building.
	if not grid.has_adjacent_building(cell):
		emit_signal("placement_denied", "You can only build next to your existing buildings.")
		_play_invalid_placement_feedback()
		return

	# Pay cost (prototype): if you can't pay, placement is invalid.
	var db := building_db as BuildingDatabaseScript
	var data = (db.get_by_id(selected_building_id) if db != null else null)
	if data != null and _resource_manager != null:
		var cost: Dictionary = data.cost
		if cost.size() > 0 and not _resource_manager.can_afford(cost):
			emit_signal("placement_denied", _format_missing_cost_message(cost))
			_play_invalid_placement_feedback()
			return
		if cost.size() > 0 and not _resource_manager.try_spend(cost):
			_play_invalid_placement_feedback()
			return

	# Occupy first to prevent race with other systems.
	var building: Node2D = _create_building_instance(selected_building_id)
	if not grid.occupy_cell(cell, building):
		building.queue_free()
		return

	(building as BuildingScript).set_cell_and_snap(cell, grid.cell_to_world_top_left(cell), grid.cell_size)
	add_child(building)
	(building as BuildingScript).play_place_feedback()
	emit_signal("building_placed", building, cell, selected_building_id)

func _create_building_instance(id: StringName) -> Node2D:
	var db := building_db as BuildingDatabaseScript
	var data = db.get_by_id(id)
	if data == null:
		push_error("BuildingSystem: unknown building id: %s" % String(id))
		return BuildingScript.new()

	var b: Node2D = BuildingScript.new()
	b.name = "Building_%s" % data.display_name
	b.z_index = 10
	(b as BuildingScript).size_cells = Vector2i(1, 1)
	(b as BuildingScript).apply_building_data(id, data)
	return b

func _emit_selection_changed() -> void:
	emit_signal("selection_changed", selected_building_id)

func _update_preview_visibility() -> void:
	if _preview == null:
		return
	_preview.visible = selected_building_id != &""
	if _preview.visible:
		var db := building_db as BuildingDatabaseScript
		var data = db.get_by_id(selected_building_id)
		if data == null:
			_preview.visible = false
			return
		(_preview as BuildingScript).size_cells = Vector2i(1, 1)
		(_preview as BuildingScript).apply_building_data(selected_building_id, data)

func _update_preview_at_cell(cell: Vector2i) -> void:
	var grid := _grid as GridSystemScript
	(_preview as BuildingScript).set_cell_and_snap(cell, grid.cell_to_world_top_left(cell), grid.cell_size)
	_update_preview_tint(cell)

func _update_preview_tint(cell: Vector2i) -> void:
	var g := _grid as GridSystemScript
	var ok: bool = (g.is_cell_free(cell) and g.has_adjacent_building(cell))
	_preview.modulate = (preview_ok_tint if ok else preview_blocked_tint)
	_preview.modulate.a = preview_alpha

func place_building_at_cell(id: StringName, cell: Vector2i, play_feedback: bool = true) -> Node2D:
	# Utility for scripted placement (eg. initial building). Does not pay cost.
	if _grid == null:
		return null
	var grid := _grid as GridSystemScript
	if grid == null:
		return null
	if not grid.is_cell_free(cell):
		return null

	var building: Node2D = _create_building_instance(id)
	if not grid.occupy_cell(cell, building):
		building.queue_free()
		return null
	(building as BuildingScript).set_cell_and_snap(cell, grid.cell_to_world_top_left(cell), grid.cell_size)
	add_child(building)
	if play_feedback:
		(building as BuildingScript).play_place_feedback()
	emit_signal("building_placed", building, cell, id)
	return building

func _play_invalid_placement_feedback() -> void:
	# Small red flash to make the failure readable.
	if _preview == null:
		return
	var t := create_tween()
	t.tween_property(_preview, "modulate", preview_blocked_tint, 0.05)
	t.tween_property(_preview, "modulate", preview_blocked_tint.darkened(0.35), 0.07)
	t.tween_property(_preview, "modulate", preview_blocked_tint, 0.06)

func _format_missing_cost_message(cost: Dictionary) -> String:
	if _resource_manager == null:
		return "Purchase failed."
	var parts: Array[String] = []
	var keys := cost.keys()
	keys.sort_custom(func(a, b): return str(a) < str(b))
	for k in keys:
		var res_name: StringName = StringName(str(k))
		var need: int = int(cost.get(k, 0))
		if need <= 0:
			continue
		var have: int = int(_resource_manager.get_amount(res_name))
		var missing: int = need - have
		if missing > 0:
			parts.append("%d %s" % [missing, str(k)])
	if parts.is_empty():
		return "Purchase failed."
	return "Missing: %s" % ", ".join(parts)
