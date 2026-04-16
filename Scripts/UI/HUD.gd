extends CanvasLayer

@export var building_system_path: NodePath
@export var building_db: Resource
@export var game_manager_path: NodePath
@export var grid_path: NodePath

const BuildingSystemScript := preload("res://Scripts/Systems/BuildingSystem.gd")
const GridSystemScript := preload("res://Scripts/Systems/GridSystem.gd")
const BuildingDatabaseScript := preload("res://Scripts/Data/BuildingDatabase.gd")
const BuildingDataScript := preload("res://Scripts/Data/BuildingData.gd")

@onready var wood_label: Label = %WoodLabel
@onready var food_label: Label = %FoodLabel
@onready var gold_label: Label = %GoldLabel
@onready var pop_label: Label = %PopLabel
@onready var selected_label: Label = %SelectedLabel
@onready var rates_label: Label = %RatesLabel
@onready var food_net_label: Label = %FoodNetLabel
@onready var details_label: Label = %SelectedDetailsLabel
@onready var cell_details_label: Label = %CellDetailsLabel
@onready var upgrade_button: Button = %UpgradeButton
@onready var toast_label: Label = %ToastLabel
@onready var toast_panel: Control = %ToastPanel
@onready var tutorial_panel: Control = %TutorialPanel
@onready var tutorial_text: Label = %TutorialText
@onready var victory_panel: Control = $Victory

var _building_system: Node
var _grid: Node2D
var _resource_manager: Node
var _population_manager: Node
var _game_manager: Node
var _rates_timer: Timer
var _toast_tween: Tween
var _tutorial_timer: Timer
var _tutorial_elapsed: float = 0.0

const BuildingScript := preload("res://Scripts/Buildings/Building.gd")
const TUTORIAL_DURATION_SEC: float = 60.0

var _cell_select_mode: bool = false
var _selected_cell: Vector2i = Vector2i(-999, -999)
var _selected_placed_building: BuildingScript = null

func _ready() -> void:
	_building_system = get_node_or_null(building_system_path)
	if _building_system == null:
		push_error("HUD: building_system_path is not set or invalid.")

	_grid = get_node_or_null(grid_path) as Node2D
	if _grid == null:
		push_error("HUD: grid_path is not set or invalid.")

	_resource_manager = get_node_or_null("/root/ResourceManager")
	_population_manager = get_node_or_null("/root/PopulationManager")
	_game_manager = get_node_or_null(game_manager_path)

	if _resource_manager != null:
		_resource_manager.resources_changed.connect(_on_resources_changed)
		_on_resources_changed(_resource_manager.get_all())

	if _population_manager != null:
		_population_manager.population_changed.connect(_on_population_changed)
		_on_population_changed(_population_manager.population, _population_manager.capacity)

	if _building_system != null:
		(_building_system as BuildingSystemScript).selection_changed.connect(_on_selection_changed)
		_on_selection_changed((_building_system as BuildingSystemScript).selected_building_id)
		(_building_system as BuildingSystemScript).building_placed.connect(func(_b, _c, _id): _update_rates())
		(_building_system as BuildingSystemScript).placement_denied.connect(_show_toast)

	if _game_manager != null:
		_game_manager.victory_reached.connect(_on_victory)

	# Buttons
	%SelectCellButton.toggled.connect(_set_cell_select_mode)
	upgrade_button.pressed.connect(_try_upgrade_selected_building)
	%HouseButton.pressed.connect(func(): _select(&"house"))
	%FarmButton.pressed.connect(func(): _select(&"farm"))
	%LumberMillButton.pressed.connect(func(): _select(&"sawmill"))
	%StorageButton.pressed.connect(func(): _select(&"storage"))

	_rates_timer = Timer.new()
	_rates_timer.name = "RatesTimer"
	_rates_timer.one_shot = false
	_rates_timer.autostart = true
	_rates_timer.wait_time = 0.5
	add_child(_rates_timer)
	_rates_timer.timeout.connect(_update_rates)
	_update_rates()

	_tutorial_timer = Timer.new()
	_tutorial_timer.name = "TutorialTimer"
	_tutorial_timer.one_shot = false
	_tutorial_timer.autostart = true
	_tutorial_timer.wait_time = 0.5
	add_child(_tutorial_timer)
	_tutorial_timer.timeout.connect(_update_tutorial)
	_update_tutorial()

func _select(id: StringName) -> void:
	if _building_system == null:
		return
	# Selecting a building turns off cell select mode.
	if _cell_select_mode:
		%SelectCellButton.button_pressed = false
		_set_cell_select_mode(false)
	_clear_selected_placed_building()
	(_building_system as BuildingSystemScript).select_building(id)

func _on_resources_changed(res: Dictionary) -> void:
	wood_label.text = "Wood: %d" % int(res.get(&"wood", 0))
	food_label.text = "Food: %d" % int(res.get(&"food", 0))
	gold_label.text = "Gold: %d" % int(res.get(&"gold", 0))

func _on_population_changed(pop: int, cap: int) -> void:
	pop_label.text = "Pop: %d / %d" % [pop, cap]
	_update_rates()

func _on_selection_changed(id: StringName) -> void:
	if id == &"":
		selected_label.text = "Selected: (none)"
		details_label.text = "Details: -"
		return
	var db := building_db as BuildingDatabaseScript
	if db == null:
		selected_label.text = "Selected: %s" % String(id)
		details_label.text = "Details:\n- id: %s" % String(id)
		return
	var data := db.get_by_id(id) as BuildingDataScript
	if data == null:
		selected_label.text = "Selected: %s" % String(id)
		details_label.text = "Details:\n- id: %s" % String(id)
		return

	selected_label.text = "Selected: %s" % data.display_name
	details_label.text = _format_building_details(id, data)

func _set_cell_select_mode(enabled: bool) -> void:
	_cell_select_mode = enabled
	if enabled:
		# Prevent accidental placement while selecting cells.
		if _building_system != null:
			(_building_system as BuildingSystemScript).cancel_selection()
		selected_label.text = "Selected: Cell"
		details_label.text = "Details:\n- Clique une case sur la grille."
		cell_details_label.text = ""
		upgrade_button.visible = false
		upgrade_button.disabled = true
		_clear_selected_placed_building()
	else:
		_selected_cell = Vector2i(-999, -999)
		cell_details_label.text = ""

func _unhandled_input(event: InputEvent) -> void:
	if not _cell_select_mode:
		# Allow selecting placed buildings (when not placing).
		_try_select_placed_building_input(event)
		return
	if _grid == null:
		return

	# Ignore selection when pointer is over UI.
	var vp := get_viewport()
	if vp != null and vp.gui_get_hovered_control() != null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var grid := _grid as GridSystemScript
		if grid == null:
			return
		var cell := grid.get_mouse_cell()
		_selected_cell = cell
		var props: Dictionary = grid.get_cell_properties(cell)
		_show_selected_cell_props(props)

		# If the selected cell contains a building, switch to building selection (upgrade, details, etc.).
		var payload: Variant = grid.get_occupied_payload(cell)
		if payload is BuildingScript:
			%SelectCellButton.button_pressed = false
			_set_cell_select_mode(false)
			_select_placed_building(payload as BuildingScript)

func _try_select_placed_building_input(event: InputEvent) -> void:
	if _grid == null or _building_system == null:
		return

	var vp := get_viewport()
	if vp != null and vp.gui_get_hovered_control() != null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var grid := _grid as GridSystemScript
		if grid == null:
			return
		var cell := grid.get_mouse_cell()
		var payload: Variant = grid.get_occupied_payload(cell)
		if payload is BuildingScript:
			# Clicking an existing building switches to inspect/upgrade mode.
			(_building_system as BuildingSystemScript).cancel_selection()
			_select_placed_building(payload as BuildingScript)
		else:
			# Clicking empty terrain clears inspection selection, but keeps current placement mode.
			_clear_selected_placed_building()

func _select_placed_building(b: BuildingScript) -> void:
	_selected_placed_building = b
	var id := b.building_id

	# Cancel placement selection if any (click-to-select implies inspect/upgrade mode).
	(_building_system as BuildingSystemScript).cancel_selection()

	var db := building_db as BuildingDatabaseScript
	var data := (db.get_by_id(id) if db != null else null) as BuildingDataScript
	selected_label.text = "Selected: %s" % (data.display_name if data != null else String(id))
	details_label.text = (_format_selected_building_details_with_upgrade_cost(id, data) if data != null else "Details:\n- id: %s" % String(id))
	cell_details_label.text = ""
	_refresh_upgrade_ui()

func _format_selected_building_details_with_upgrade_cost(id: StringName, data: BuildingDataScript) -> String:
	var lines: Array[String] = []
	lines.append("Details:")
	lines.append("- id: %s" % String(id))

	# If an upgrade exists, show upgrade cost instead of initial build cost.
	var upgrade_id := _get_upgrade_id_if_any(id)
	if upgrade_id != &"":
		var db := building_db as BuildingDatabaseScript
		var up := (db.get_by_id(upgrade_id) if db != null else null) as BuildingDataScript
		var up_cost: Dictionary = (up.cost if up != null else {})
		lines.append("- upgrade cost: %s" % _format_cost(up_cost))
	else:
		lines.append("- cost: %s" % _format_cost(data.cost))

	# Production
	if data.produces_resource != &"" and data.production_amount != 0 and data.production_interval_sec > 0.0:
		lines.append("- production: %d %s / %.1fs" % [data.production_amount, String(data.produces_resource), data.production_interval_sec])
	else:
		lines.append("- production: none")

	# Population / storage
	if data.population_capacity > 0:
		lines.append("- pop cap: +%d" % data.population_capacity)
	if data.storage_capacity_bonus > 0:
		lines.append("- storage cap: +%d (all)" % data.storage_capacity_bonus)

	return "\n".join(lines)

func _clear_selected_placed_building() -> void:
	_selected_placed_building = null
	upgrade_button.visible = false
	upgrade_button.disabled = true

func _refresh_upgrade_ui() -> void:
	if upgrade_button == null:
		return
	if _selected_placed_building == null:
		upgrade_button.visible = false
		upgrade_button.disabled = true
		return
	var from_id := _selected_placed_building.building_id
	var to_id := _get_upgrade_id_if_any(from_id)
	if to_id == &"":
		upgrade_button.visible = false
		upgrade_button.disabled = true
		return

	upgrade_button.visible = true

	var db := building_db as BuildingDatabaseScript
	var to_data := (db.get_by_id(to_id) if db != null else null) as BuildingDataScript
	if to_data == null:
		upgrade_button.disabled = true
		return

	var cost: Dictionary = to_data.cost
	var can: bool = (_resource_manager.can_afford(cost) if _resource_manager != null else false)
	upgrade_button.disabled = not can

func _get_upgrade_id_if_any(from_id: StringName) -> StringName:
	# Convention: base_id -> base_id_2
	if String(from_id).ends_with("_2"):
		return &""
	var candidate := StringName("%s_2" % String(from_id))
	var db := building_db as BuildingDatabaseScript
	if db == null:
		return &""
	return (candidate if db.get_by_id(candidate) != null else &"")

func _try_upgrade_selected_building() -> void:
	if _selected_placed_building == null:
		return
	var from_id := _selected_placed_building.building_id
	var to_id := _get_upgrade_id_if_any(from_id)
	if to_id == &"":
		return

	var db := building_db as BuildingDatabaseScript
	var to_data := (db.get_by_id(to_id) if db != null else null) as BuildingDataScript
	if to_data == null:
		return

	var cost: Dictionary = to_data.cost
	if _resource_manager == null:
		_resource_manager = get_node_or_null("/root/ResourceManager")
	if _resource_manager == null:
		return
	if cost.size() > 0 and not _resource_manager.can_afford(cost):
		_refresh_upgrade_ui()
		return
	if cost.size() > 0 and not _resource_manager.try_spend(cost):
		_refresh_upgrade_ui()
		return

	_selected_placed_building.apply_building_data(to_id, to_data)

	# Recompute derived stats and worker assignment after changes.
	if _game_manager != null and _game_manager.has_method("on_buildings_changed"):
		_game_manager.call("on_buildings_changed")
	_update_rates()
	_refresh_upgrade_ui()

func _show_selected_cell_props(props: Dictionary) -> void:
	var cell: Vector2i = props.get(&"cell", Vector2i(-999, -999))
	var in_bounds: bool = bool(props.get(&"in_bounds", false))
	var blocked: bool = bool(props.get(&"blocked", false))
	var occupied: bool = bool(props.get(&"occupied", false))
	var occupant_name: String = String(props.get(&"occupant_name", ""))
	var building_id: String = String(props.get(&"building_id", ""))

	selected_label.text = "Selected: Cell (%d, %d)" % [cell.x, cell.y]

	var lines: Array[String] = []
	lines.append("Cell:")
	lines.append("- in bounds: %s" % ("yes" if in_bounds else "no"))
	lines.append("- blocked: %s" % ("yes" if blocked else "no"))
	lines.append("- occupied: %s" % ("yes" if occupied else "no"))
	if occupied:
		if building_id != "":
			lines.append("- building id: %s" % building_id)
		if occupant_name != "":
			lines.append("- node: %s" % occupant_name)
	cell_details_label.text = "\n".join(lines)

func _format_building_details(id: StringName, data: BuildingDataScript) -> String:
	var lines: Array[String] = []
	lines.append("Details:")
	lines.append("- id: %s" % String(id))

	# Cost
	var cost_str := _format_cost(data.cost)
	lines.append("- cost: %s" % cost_str)

	# Production
	if data.produces_resource != &"" and data.production_amount != 0 and data.production_interval_sec > 0.0:
		lines.append("- production: %d %s / %.1fs" % [data.production_amount, String(data.produces_resource), data.production_interval_sec])
	else:
		lines.append("- production: none")

	# Population / storage
	if data.population_capacity > 0:
		lines.append("- pop cap: +%d" % data.population_capacity)
	if data.storage_capacity_bonus > 0:
		lines.append("- storage cap: +%d (all)" % data.storage_capacity_bonus)

	return "\n".join(lines)

func _format_cost(cost: Dictionary) -> String:
	if cost == null or cost.size() == 0:
		return "free"
	var parts: Array[String] = []
	var keys := cost.keys()
	keys.sort_custom(func(a, b): return str(a) < str(b))
	for k in keys:
		var amount := int(cost.get(k, 0))
		if amount <= 0:
			continue
		parts.append("%d %s" % [amount, str(k)])
	if parts.is_empty():
		return "free"
	return ", ".join(parts)

func _on_victory() -> void:
	victory_panel.visible = true
	if tutorial_panel != null:
		tutorial_panel.visible = false

func _show_toast(message: String) -> void:
	if toast_label == null or toast_panel == null:
		return
	toast_panel.visible = true
	toast_label.text = message
	toast_label.modulate = Color(1, 0.85, 0.85, 1)

	if _toast_tween != null and _toast_tween.is_running():
		_toast_tween.kill()
	toast_panel.modulate.a = 0.85
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.25)
	_toast_tween.tween_callback(func():
		toast_label.text = ""
		toast_panel.visible = false
	)

func _update_rates() -> void:
	# Food production per second from placed buildings
	var food_prod_per_sec: float = 0.0
	if _building_system != null:
		for child in _building_system.get_children():
			if child is Node and (child as Node).name == "Preview":
				continue
			if not (child is BuildingScript):
				continue
			var b := child as BuildingScript
			var data := b.building_data as BuildingDataScript
			if data == null:
				continue
			# Production buildings require an assigned worker to operate.
			if data.is_producer() and not b.worker_assigned:
				continue
			if data.produces_resource == &"food" and data.production_interval_sec > 0.0:
				food_prod_per_sec += float(data.production_amount) / float(data.production_interval_sec)

	# Food consumption & gold income per second from population rules
	var pop: int = (_population_manager.population if _population_manager != null else 0)
	var food_cons_per_sec: float = 0.0
	var gold_inc_per_sec: float = 0.0
	if _population_manager != null:
		var food_i: float = _population_manager.food_consumption_interval_sec
		var gold_i: float = _population_manager.gold_income_interval_sec
		if food_i > 0.0:
			food_cons_per_sec = float(pop) / food_i
		if gold_i > 0.0:
			gold_inc_per_sec = float(pop) / gold_i

	rates_label.text = "Rates: food +%.2f/s, food -%.2f/s, gold +%.2f/s" % [food_prod_per_sec, food_cons_per_sec, gold_inc_per_sec]

	var food_net: float = food_prod_per_sec - food_cons_per_sec
	food_net_label.text = "Food net: %+.2f/s" % food_net
	food_net_label.modulate = (Color(0.55, 1.0, 0.6, 1.0) if food_net >= 0.0 else Color(1.0, 0.55, 0.55, 1.0))

func _update_tutorial() -> void:
	if tutorial_panel == null or tutorial_text == null:
		return
	_tutorial_elapsed += 0.5
	if _tutorial_elapsed >= TUTORIAL_DURATION_SEC:
		tutorial_panel.visible = false
		return

	tutorial_panel.visible = true

	# Light state-based hints (still simple): check what the player has already built.
	var farms := _count_placed_buildings([&"farm", &"farm_2"])
	var mills := _count_placed_buildings([&"sawmill", &"sawmill_2"])
	var houses := _count_placed_buildings([&"house", &"house_2"])

	var remaining := int(ceil(TUTORIAL_DURATION_SEC - _tutorial_elapsed))
	var step_text := ""

	# Important: without a House, capacity is 0 => population stays at 0 => no gold income.
	if houses == 0:
		step_text = "1) Construis une House d'abord.\nSans House, la population reste à 0 → pas d'or."
	elif mills == 0:
		step_text = "2) Construis une Scierie (Sawmill) pour produire du wood.\nTu en auras besoin pour étendre la ville."
	elif farms == 0:
		step_text = "3) Construis une Ferme (Farm) pour produire de la nourriture.\nSurveille Food net pour éviter la famine."
	else:
		step_text = "4) Équilibre: Farms + Houses + Sawmills.\nObjectif: atteindre 30 population."

	tutorial_text.text = "Tutoriel (%ds)\n%s" % [remaining, step_text]

func _count_placed_buildings(ids: Array[StringName]) -> int:
	if _building_system == null:
		return 0
	var n := 0
	for child in _building_system.get_children():
		if child is Node and (child as Node).name == "Preview":
			continue
		if not (child is BuildingScript):
			continue
		var b := child as BuildingScript
		if ids.has(b.building_id):
			n += 1
	return n
