extends CanvasLayer

@export var building_system_path: NodePath
@export var building_db: Resource
@export var game_manager_path: NodePath
@export var grid_path: NodePath

const BuildingSystemScript := preload("res://Scripts/Systems/BuildingSystem.gd")
const GridSystemScript := preload("res://Scripts/Systems/GridSystem.gd")
const BuildingDatabaseScript := preload("res://Scripts/Data/BuildingDatabase.gd")
const BuildingDataScript := preload("res://Scripts/Data/BuildingData.gd")
const PurifyPreviewScript := preload("res://Scripts/UI/PurifyPreview.gd")

@onready var wood_value: Label = %WoodValue
@onready var wood_rate: Label = %WoodRate
@onready var food_value: Label = %FoodValue
@onready var food_rate: Label = %FoodRate
@onready var gold_value: Label = %GoldValue
@onready var gold_rate: Label = %GoldRate
@onready var stone_value: Label = %StoneValue
@onready var pop_value: Label = %PopValue

@onready var wood_icon: TextureRect = $"TopBar/TopBarContent/WoodTop/WoodIcon"
@onready var food_icon: TextureRect = $"TopBar/TopBarContent/FoodTop/FoodIcon"
@onready var gold_icon: TextureRect = $"TopBar/TopBarContent/GoldTop/GoldIcon"
@onready var stone_icon: TextureRect = $"TopBar/TopBarContent/StoneTop/StoneIcon"
@onready var pop_icon: TextureRect = $"TopBar/TopBarContent/PopTop/PopIcon"
@onready var blocked_label: Label = %BlockedLabel
@onready var selected_label: Label = %SelectedLabel
@onready var rates_label: Label = %RatesLabel
@onready var food_net_label: Label = %FoodNetLabel
@onready var details_label: Label = %SelectedDetailsLabel
@onready var cell_details_label: Label = %CellDetailsLabel
@onready var upgrade_button: Button = %UpgradeButton
@onready var purify_button: Button = %PurifyButton
@onready var mining_button: Button = %MiningButton
@onready var toast_label: Label = %ToastLabel
@onready var toast_panel: Control = %ToastPanel
@onready var tutorial_panel: Control = %TutorialPanel
@onready var tutorial_text: Label = %TutorialText
@onready var victory_panel: Control = $Victory
@onready var defeat_panel: Control = $Defeat

var _building_system: Node
var _grid: Node2D
var _resource_manager: Node
var _population_manager: Node
var _game_manager: Node
var _rates_timer: Timer
var _toast_tween: Tween
var _tutorial_timer: Timer
var _tutorial_elapsed: float = 0.0
var _tutorial_final_elapsed: float = 0.0
var _purify_preview: Node2D

const BuildingScript := preload("res://Scripts/Buildings/Building.gd")
const TUTORIAL_DURATION_SEC: float = 60.0
const TUTORIAL_FINAL_DURATION_SEC: float = 10.0

static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D

var _cell_select_mode: bool = false
var _purify_mode: bool = false
var _mining_mode: bool = false
var _selected_cell: Vector2i = Vector2i(-999, -999)
var _selected_placed_building: BuildingScript = null

const PURIFY_COST_LIGHT: int = 9
const MINING_YIELD_STONE: int = 1

func _ready() -> void:
	_building_system = get_node_or_null(building_system_path)
	if _building_system == null:
		push_error("HUD: building_system_path is not set or invalid.")

	_grid = get_node_or_null(grid_path) as Node2D
	if _grid == null:
		push_error("HUD: grid_path is not set or invalid.")
	else:
		# Purify range preview (drawn in world/grid space).
		_purify_preview = PurifyPreviewScript.new()
		_purify_preview.name = "PurifyPreview"
		(_purify_preview as PurifyPreviewScript).grid_path = NodePath("..") # relative to preview node once parented to grid
		_grid.add_child(_purify_preview)

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
		if _game_manager.has_signal("defeat_reached"):
			_game_manager.defeat_reached.connect(_on_defeat)

	# Buttons
	if purify_button != null:
		purify_button.toggled.connect(_set_purify_mode)
	if mining_button != null:
		mining_button.pressed.connect(_mine_selected_stone_now)
		mining_button.visible = false
	upgrade_button.pressed.connect(_try_upgrade_selected_building)
	%HouseButton.pressed.connect(func(): _select(&"house"))
	%FarmButton.pressed.connect(func(): _select(&"farm"))
	%LumberMillButton.pressed.connect(func(): _select(&"sawmill"))
	%StorageButton.pressed.connect(func(): _select(&"storage"))
	%MineButton.pressed.connect(func(): _select(&"mine"))
	%FountainButton.pressed.connect(func(): _select(&"fountain"))
	%WallButton.pressed.connect(func(): _select(&"wall"))

	_apply_ui_skin()

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
	_refresh_overlay_minimal()
	_refresh_context_overlay()

func _refresh_overlay_minimal() -> void:
	# Overlay should only show essential info (hide empty/"none" placeholders).
	if selected_label != null:
		var t := selected_label.text.strip_edges()
		selected_label.visible = t != "" and t != "Selected: (none)"
	if details_label != null:
		var dt := details_label.text.strip_edges()
		details_label.visible = dt != "" and dt != "Details: -"
	if cell_details_label != null:
		cell_details_label.visible = cell_details_label.text.strip_edges() != ""

func _refresh_context_overlay() -> void:
	# Context actions live in the bottom overlay:
	# - Upgrade: when a placed building is selected (handled by _refresh_upgrade_ui).
	# - Pickaxe: when a stone tile is selected in cell select mode and can be mined.
	if mining_button != null:
		var should_show := false
		if _cell_select_mode and _grid != null and _selected_cell != Vector2i(-999, -999):
			var grid := _grid as GridSystemScript
			if grid != null:
				should_show = grid.is_cell_stone(_selected_cell) and grid.has_adjacent_building(_selected_cell)
		mining_button.visible = should_show

func _mine_selected_stone_now() -> void:
	if _grid == null:
		return
	if _resource_manager == null:
		_resource_manager = get_node_or_null("/root/ResourceManager")
	var grid := _grid as GridSystemScript
	if grid == null:
		return
	if _selected_cell == Vector2i(-999, -999):
		return
	# Same rule as mining mode: only stone adjacent to player's buildings.
	if not grid.is_cell_stone(_selected_cell):
		return
	if not grid.has_adjacent_building(_selected_cell):
		return

	if grid.mine_stone(_selected_cell):
		if _resource_manager != null:
			_resource_manager.add(&"stone", MINING_YIELD_STONE)
		_show_toast("Stone gathered (+1).")
	_refresh_context_overlay()

func _select(id: StringName) -> void:
	if _building_system == null:
		return
	# Selecting a building turns off purify mode.
	if _purify_mode and purify_button != null:
		purify_button.button_pressed = false
		_set_purify_mode(false)
	# Selecting a building turns off mining mode.
	if _mining_mode and mining_button != null:
		mining_button.button_pressed = false
		_set_mining_mode(false)
	# Selecting a building turns off cell select mode.
	if _cell_select_mode:
		_set_cell_select_mode(false)
	_clear_selected_placed_building()
	(_building_system as BuildingSystemScript).select_building(id)
	_refresh_context_overlay()

func _on_resources_changed(res: Dictionary) -> void:
	var w := int(res.get(&"wood", 0))
	var f := int(res.get(&"food", 0))
	var g := int(res.get(&"gold", 0))
	var s := int(res.get(&"stone", 0))
	if wood_value != null:
		wood_value.text = str(w)
	if food_value != null:
		food_value.text = str(f)
	if gold_value != null:
		gold_value.text = str(g)
	if stone_value != null:
		stone_value.text = str(s)

func _on_population_changed(pop: int, cap: int) -> void:
	if pop_value != null:
		pop_value.text = "%d / %d" % [pop, cap]
	_update_rates()

func _apply_ui_skin() -> void:
	var ui_button_tex := _tex("res://assets/ui/button.png")
	var icon_wood := _tex("res://assets/icons/wood.png")
	var icon_food := _tex("res://assets/icons/food.png")
	var icon_gold := _tex("res://assets/icons/gold.png")
	var icon_pop := _tex("res://assets/icons/population.png")
	var icon_stone := _tex("res://assets/icons/stone.png")

	var icon_btn_house := _tex("res://assets/icons/btn_house.png")
	var icon_btn_farm := _tex("res://assets/icons/btn_farm.png")
	var icon_btn_sawmill := _tex("res://assets/icons/btn_sawmill.png")
	var icon_btn_storage := _tex("res://assets/icons/btn_storage.png")
	var icon_btn_mine := _tex("res://assets/icons/btn_mine.png")
	var icon_btn_wall := _tex("res://assets/icons/btn_wall.png")
	var icon_btn_mining := _tex("res://assets/icons/btn_mining.png")

	var ui_text := Color(0.22, 0.19, 0.15, 1.0)
	# Top bar icons + values
	if wood_icon != null:
		wood_icon.texture = icon_wood
	if food_icon != null:
		food_icon.texture = icon_food
	if gold_icon != null:
		gold_icon.texture = icon_gold
	if stone_icon != null:
		stone_icon.texture = icon_stone
	if pop_icon != null:
		pop_icon.texture = icon_pop

	# Top bar values sit on a light panel.
	for l in [blocked_label, wood_value, wood_rate, food_value, food_rate, gold_value, gold_rate, stone_value, pop_value]:
		if l != null:
			l.add_theme_color_override("font_color", ui_text)

	# Overlay text (transparent panels) sits over the world: use light text + subtle shadow.
	var overlay_text := Color(0.98, 0.97, 0.94, 1.0)
	var overlay_shadow := Color(0.0, 0.0, 0.0, 0.55)
	var overlay_labels: Array[Label] = [selected_label, rates_label, food_net_label, details_label, cell_details_label]
	for l in overlay_labels:
		if l == null:
			continue
		l.add_theme_color_override("font_color", overlay_text)
		l.add_theme_color_override("font_shadow_color", overlay_shadow)
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)

	if tutorial_text != null:
		tutorial_text.add_theme_color_override("font_color", overlay_text)
		tutorial_text.add_theme_color_override("font_shadow_color", overlay_shadow)
		tutorial_text.add_theme_constant_override("shadow_offset_x", 1)
		tutorial_text.add_theme_constant_override("shadow_offset_y", 1)
	if toast_label != null:
		toast_label.add_theme_color_override("font_color", overlay_text)
		toast_label.add_theme_color_override("font_shadow_color", overlay_shadow)
		toast_label.add_theme_constant_override("shadow_offset_x", 1)
		toast_label.add_theme_constant_override("shadow_offset_y", 1)

	# Button backgrounds + icons (keeps prototype simple but cohesive)
	var normal := _make_button_style(ui_button_tex, Color(1, 1, 1, 1))
	var hover := _make_button_style(ui_button_tex, Color(1, 1, 1, 1))
	var pressed := _make_button_style(ui_button_tex, Color(0.98, 0.96, 0.92, 1))
	var disabled := _make_button_style(ui_button_tex, Color(1, 1, 1, 0.6))

	var house_btn: Button = %HouseButton
	var farm_btn: Button = %FarmButton
	var mill_btn: Button = %LumberMillButton
	var storage_btn: Button = %StorageButton
	var mine_btn: Button = %MineButton
	var fountain_btn: Button = %FountainButton
	var wall_btn: Button = %WallButton
	var purify_btn: Button = purify_button
	var mining_btn: Button = mining_button

	for b in [house_btn, farm_btn, mill_btn, storage_btn, mine_btn, fountain_btn, wall_btn, purify_btn, mining_btn, upgrade_button]:
		if b == null:
			continue
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("disabled", disabled)
		b.custom_minimum_size = Vector2(140, 40)
		b.add_theme_color_override("font_color", ui_text)
		b.add_theme_color_override("font_hover_color", ui_text)
		b.add_theme_color_override("font_pressed_color", ui_text)
		b.add_theme_color_override("font_hover_pressed_color", ui_text)
		b.add_theme_color_override("font_focus_color", ui_text)
		b.add_theme_color_override("font_disabled_color", Color(ui_text, 0.6))

	if house_btn != null:
		house_btn.icon = icon_btn_house
	if farm_btn != null:
		farm_btn.icon = icon_btn_farm
	if mill_btn != null:
		mill_btn.icon = icon_btn_sawmill
	if storage_btn != null:
		storage_btn.icon = icon_btn_storage
	if mine_btn != null:
		mine_btn.icon = icon_btn_mine
	if wall_btn != null:
		wall_btn.icon = icon_btn_wall
	if mining_btn != null:
		mining_btn.icon = icon_btn_mining

func _make_button_style(tex: Texture2D, modulate: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 16
	sb.texture_margin_top = 16
	sb.texture_margin_right = 16
	sb.texture_margin_bottom = 16
	sb.modulate_color = modulate
	return sb

func _on_selection_changed(id: StringName) -> void:
	if id == &"":
		selected_label.text = "Selected: (none)"
		details_label.text = "Details: -"
		cell_details_label.text = ""
		_refresh_overlay_minimal()
		return
	var db := building_db as BuildingDatabaseScript
	if db == null:
		selected_label.text = "Selected: %s" % String(id)
		details_label.text = "Details: -"
		cell_details_label.text = ""
		_refresh_overlay_minimal()
		return
	var data := db.get_by_id(id) as BuildingDataScript
	if data == null:
		selected_label.text = "Selected: %s" % String(id)
		details_label.text = "Details: -"
		cell_details_label.text = ""
		_refresh_overlay_minimal()
		return

	selected_label.text = "Selected: %s" % data.display_name
	details_label.text = _format_building_details(id, data)
	cell_details_label.text = ""
	_refresh_overlay_minimal()

func _set_cell_select_mode(enabled: bool) -> void:
	_cell_select_mode = enabled
	if enabled:
		# Mutually exclusive with purify mode.
		if _purify_mode and purify_button != null:
			purify_button.button_pressed = false
			_set_purify_mode(false)
		# Mutually exclusive with mining mode.
		if _mining_mode and mining_button != null:
			mining_button.button_pressed = false
			_set_mining_mode(false)
		# Prevent accidental placement while selecting cells.
		if _building_system != null:
			(_building_system as BuildingSystemScript).cancel_selection()
		selected_label.text = "Selected: Cell"
		details_label.text = "Details:\n- Click a tile on the grid."
		cell_details_label.text = ""
		upgrade_button.visible = false
		upgrade_button.disabled = true
		_clear_selected_placed_building()
		_refresh_overlay_minimal()
		_refresh_context_overlay()
	else:
		_selected_cell = Vector2i(-999, -999)
		cell_details_label.text = ""
		_refresh_overlay_minimal()
		_refresh_context_overlay()

func _set_purify_mode(enabled: bool) -> void:
	_purify_mode = enabled
	if _purify_preview != null and _purify_preview.has_method("set_enabled"):
		_purify_preview.call("set_enabled", enabled)
	if enabled:
		# Mutually exclusive with cell select mode.
		if _cell_select_mode:
			_set_cell_select_mode(false)
		# Mutually exclusive with mining mode.
		if _mining_mode and mining_button != null:
			mining_button.button_pressed = false
			_set_mining_mode(false)
		# Prevent accidental placement while purifying.
		if _building_system != null:
			(_building_system as BuildingSystemScript).cancel_selection()
		selected_label.text = "Selected: Purify"
		details_label.text = "Details:\n- Click a tile to purify (3x3).\n- Cost: 9 light."
		cell_details_label.text = ""
		upgrade_button.visible = false
		upgrade_button.disabled = true
		_clear_selected_placed_building()
		_refresh_overlay_minimal()
		_refresh_context_overlay()
	else:
		_selected_cell = Vector2i(-999, -999)
		cell_details_label.text = ""
		_refresh_overlay_minimal()
		_refresh_context_overlay()

func _set_mining_mode(enabled: bool) -> void:
	_mining_mode = enabled
	if enabled:
		# Mutually exclusive with cell select mode.
		if _cell_select_mode:
			_set_cell_select_mode(false)
		# Mutually exclusive with purify mode.
		if _purify_mode and purify_button != null:
			purify_button.button_pressed = false
			_set_purify_mode(false)
		# Prevent accidental placement while mining.
		if _building_system != null:
			(_building_system as BuildingSystemScript).cancel_selection()
		selected_label.text = "Selected: Pickaxe"
		details_label.text = "Details:\n- Click a stone tile next to your buildings.\n- Gain: +1 stone."
		cell_details_label.text = ""
		upgrade_button.visible = false
		upgrade_button.disabled = true
		_clear_selected_placed_building()
		_refresh_overlay_minimal()
		_refresh_context_overlay()
	else:
		_selected_cell = Vector2i(-999, -999)
		cell_details_label.text = ""
		_refresh_overlay_minimal()
		_refresh_context_overlay()

func _unhandled_input(event: InputEvent) -> void:
	# Right click: clear any selection, but don't consume input
	# so camera panning (also right click) still works.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_clear_all_selection()
		return

	if _purify_mode:
		_try_purify_input(event)
		return
	if _mining_mode:
		_try_mining_input(event)
		return
	if _grid == null:
		return

	# Ignore selection when pointer is over UI.
	var vp := get_viewport()
	if vp != null and vp.gui_get_hovered_control() != null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# If not currently selecting cells, a click on the grid enters cell select mode
		# when we are NOT in placement mode.
		if not _cell_select_mode:
			var bs := (_building_system as BuildingSystemScript if _building_system != null else null)
			var in_placement_mode := (bs != null and bs.selected_building_id != &"")
			if not in_placement_mode:
				_set_cell_select_mode(true)
			else:
				return

		var grid := _grid as GridSystemScript
		if grid == null:
			return
		var cell := grid.get_mouse_cell()
		_selected_cell = cell
		var props: Dictionary = grid.get_cell_properties(cell)
		_show_selected_cell_props(props)
		_refresh_context_overlay()

func _clear_all_selection() -> void:
	# Cancel placement selection (if any), clear inspected building, clear cell selection,
	# and turn off modal tools.
	if _building_system != null:
		(_building_system as BuildingSystemScript).cancel_selection()

	if _purify_mode and purify_button != null:
		purify_button.button_pressed = false
	_purify_mode = false
	if _mining_mode and mining_button != null:
		# Mining is now a context action, but keep state consistent if it was ever enabled.
		mining_button.button_pressed = false
	_mining_mode = false

	if _cell_select_mode:
		_set_cell_select_mode(false)

	_selected_cell = Vector2i(-999, -999)
	cell_details_label.text = ""
	_clear_selected_placed_building()
	_refresh_overlay_minimal()
	_refresh_context_overlay()

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
			_refresh_overlay_minimal()

func _try_purify_input(event: InputEvent) -> void:
	if _grid == null:
		return
	var vp := get_viewport()
	if vp != null and vp.gui_get_hovered_control() != null:
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	if _resource_manager == null:
		_resource_manager = get_node_or_null("/root/ResourceManager")
	if _resource_manager == null:
		return

	var cost := {&"light": PURIFY_COST_LIGHT}
	if not _resource_manager.can_afford(cost):
		_show_toast("Not enough light (need 9).")
		return
	if not _resource_manager.try_spend(cost):
		_show_toast("Not enough light (need 9).")
		return

	var grid := _grid as GridSystemScript
	var cell := grid.get_mouse_cell()
	var removed := 0
	if grid != null and grid.has_method("purify_3x3"):
		removed = int(grid.call("purify_3x3", cell))
	_show_toast("Purified %d tiles." % removed)

	# Exit mode after one use.
	if purify_button != null:
		purify_button.button_pressed = false
	_set_purify_mode(false)

func _try_mining_input(event: InputEvent) -> void:
	if _grid == null:
		return
	var vp := get_viewport()
	if vp != null and vp.gui_get_hovered_control() != null:
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	if _resource_manager == null:
		_resource_manager = get_node_or_null("/root/ResourceManager")
	if _resource_manager == null:
		return

	var grid := _grid as GridSystemScript
	if grid == null:
		return
	var cell := grid.get_mouse_cell()

	# Must click a stone tile adjacent to player's buildings.
	if not grid.is_cell_stone(cell):
		_show_toast("Click a stone tile.")
		return
	if not grid.has_adjacent_building(cell):
		_show_toast("Pickaxe only works on stone next to your buildings.")
		return

	if grid.mine_stone(cell):
		_resource_manager.add(&"stone", MINING_YIELD_STONE)
		_show_toast("Stone gathered (+1).")
	else:
		_show_toast("No stone here.")

	# Exit mode after one use.
	if mining_button != null:
		mining_button.button_pressed = false
	_set_mining_mode(false)

func _select_placed_building(b: BuildingScript) -> void:
	_selected_placed_building = b
	var id := b.building_id

	# Cancel placement selection if any (click-to-select implies inspect/upgrade mode).
	(_building_system as BuildingSystemScript).cancel_selection()

	var db := building_db as BuildingDatabaseScript
	var data := (db.get_by_id(id) if db != null else null) as BuildingDataScript
	selected_label.text = "Selected: %s" % (data.display_name if data != null else String(id))
	details_label.text = (_format_selected_building_details_with_upgrade_cost(id, data) if data != null else "Details: -")
	cell_details_label.text = ""
	_refresh_upgrade_ui()
	_refresh_overlay_minimal()

func _format_selected_building_details_with_upgrade_cost(id: StringName, data: BuildingDataScript) -> String:
	var lines: Array[String] = []
	lines.append("Details:")

	lines.append("- cost: %s" % _format_cost(data.cost))

	var up_cost := _get_upgrade_cost_if_any(id, data)
	if up_cost.size() > 0:
		lines.append("- upgrade cost: %s" % _format_cost(up_cost))

	# Production
	if data.produces_resource != &"" and data.production_amount != 0 and data.production_interval_sec > 0.0:
		lines.append("- production: %d %s / %.1fs" % [data.production_amount, String(data.produces_resource), data.production_interval_sec])

	# Population / storage
	if data.population_capacity > 0:
		lines.append("- pop cap: +%d" % data.population_capacity)
	if data.storage_capacity_bonus > 0:
		lines.append("- storage cap: +%d (all)" % data.storage_capacity_bonus)
	if data.blocks_adjacent_infection:
		lines.append("- stops red spread on adjacent tiles")

	return "\n".join(lines)

func _get_upgrade_cost_if_any(id: StringName, data: BuildingDataScript) -> Dictionary:
	if _selected_placed_building == null:
		return {}
	# Only production buildings are upgradable; mine and fountain are not.
	if id == &"mine" or id == &"fountain":
		return {}
	if not data.is_producer():
		return {}
	if (_selected_placed_building as BuildingScript).is_upgraded():
		return {}

	var out: Dictionary = {}
	for k in data.cost.keys():
		var res_name: StringName = StringName(str(k))
		var base := int(data.cost.get(k, 0))
		if base <= 0:
			continue
		out[res_name] = int(ceili(float(base) * 1.5))
	return out

func _clear_selected_placed_building() -> void:
	_selected_placed_building = null
	upgrade_button.visible = false
	upgrade_button.disabled = true
	if selected_label != null:
		selected_label.text = "Selected: (none)"
	if details_label != null:
		details_label.text = "Details: -"
	if cell_details_label != null:
		cell_details_label.text = ""
	_refresh_overlay_minimal()
	_refresh_context_overlay()

func _refresh_upgrade_ui() -> void:
	if upgrade_button == null:
		return
	if _selected_placed_building == null:
		upgrade_button.visible = false
		upgrade_button.disabled = true
		return
	var from_id := _selected_placed_building.building_id
	if from_id == &"mine" or from_id == &"fountain":
		upgrade_button.visible = false
		upgrade_button.disabled = true
		return
	if (_selected_placed_building as BuildingScript).is_upgraded():
		upgrade_button.visible = false
		upgrade_button.disabled = true
		return

	upgrade_button.visible = true

	var db := building_db as BuildingDatabaseScript
	var data := (db.get_by_id(from_id) if db != null else null) as BuildingDataScript
	if data == null or not data.is_producer():
		upgrade_button.disabled = true
		return

	var cost: Dictionary = _get_upgrade_cost_if_any(from_id, data)
	var can: bool = (_resource_manager.can_afford(cost) if _resource_manager != null else false)
	upgrade_button.disabled = not can
	_refresh_context_overlay()

func _try_upgrade_selected_building() -> void:
	if _selected_placed_building == null:
		return
	var from_id := _selected_placed_building.building_id
	if from_id == &"mine" or from_id == &"fountain":
		return

	var db := building_db as BuildingDatabaseScript
	var data := (db.get_by_id(from_id) if db != null else null) as BuildingDataScript
	if data == null or not data.is_producer():
		return
	if (_selected_placed_building as BuildingScript).is_upgraded():
		return

	var cost: Dictionary = _get_upgrade_cost_if_any(from_id, data)
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

	_selected_placed_building.apply_production_upgrade()

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
	_refresh_overlay_minimal()

func _format_building_details(_id: StringName, data: BuildingDataScript) -> String:
	var lines: Array[String] = []
	lines.append("Details:")

	# Cost
	var cost_str := _format_cost(data.cost)
	lines.append("- cost: %s" % cost_str)

	# Production
	if data.produces_resource != &"" and data.production_amount != 0 and data.production_interval_sec > 0.0:
		lines.append("- production: %d %s / %.1fs" % [data.production_amount, String(data.produces_resource), data.production_interval_sec])

	# Population / storage
	if data.population_capacity > 0:
		lines.append("- pop cap: +%d" % data.population_capacity)
	if data.storage_capacity_bonus > 0:
		lines.append("- storage cap: +%d (all)" % data.storage_capacity_bonus)
	if data.blocks_adjacent_infection:
		lines.append("- stops red spread on adjacent tiles")

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
	if defeat_panel != null:
		defeat_panel.visible = false

func _on_defeat() -> void:
	if defeat_panel != null:
		defeat_panel.visible = true
	if tutorial_panel != null:
		tutorial_panel.visible = false
	if victory_panel != null:
		victory_panel.visible = false

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
	var wood_prod_per_sec: float = 0.0
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
			if data.produces_resource == &"wood" and data.production_interval_sec > 0.0:
				wood_prod_per_sec += float(data.production_amount) / float(data.production_interval_sec)

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

	var food_net: float = food_prod_per_sec - food_cons_per_sec
	if food_net_label != null:
		food_net_label.text = "Food net: %+.2f/s" % food_net
		food_net_label.modulate = (Color(0.55, 1.0, 0.6, 1.0) if food_net >= 0.0 else Color(1.0, 0.55, 0.55, 1.0))
	if rates_label != null:
		rates_label.text = "Rates: food +%.2f/s, food -%.2f/s, gold +%.2f/s" % [food_prod_per_sec, food_cons_per_sec, gold_inc_per_sec]

	# Top bar compact display: show net food and gold income next to quantities.
	var pos_col := Color(0.18, 0.82, 0.32, 1.0)
	var neg_col := Color(0.95, 0.22, 0.22, 1.0)
	if wood_rate != null:
		wood_rate.text = "(%+.2f/s)" % wood_prod_per_sec
		wood_rate.modulate = (pos_col if wood_prod_per_sec >= 0.0 else neg_col)
	if food_rate != null:
		food_rate.text = "(%+.2f/s)" % food_net
		food_rate.modulate = (pos_col if food_net >= 0.0 else neg_col)
	if gold_rate != null:
		gold_rate.text = "(%+.2f/s)" % gold_inc_per_sec
		gold_rate.modulate = (pos_col if gold_inc_per_sec >= 0.0 else neg_col)

	# Blocked cells info (top-left)
	var grid := _grid as GridSystemScript
	if blocked_label != null and grid != null and grid.has_method("get_blocked_count") and grid.has_method("get_blocked_spawn_interval_sec"):
		var n := int(grid.call("get_blocked_count"))
		var interval := float(grid.call("get_blocked_spawn_interval_sec"))
		blocked_label.text = "Blocked: %d (every %ds)" % [n, int(round(interval))]

func _update_tutorial() -> void:
	if tutorial_panel == null or tutorial_text == null:
		return
	_tutorial_elapsed += 0.5

	# Light state-based hints (still simple): check what the player has already built.
	var farms := _count_placed_buildings([&"farm", &"farm_2"])
	var mills := _count_placed_buildings([&"sawmill", &"sawmill_2"])

	var step_text := ""
	var show_time := false
	var remaining := 0

	if mills == 0:
		step_text = "1) Build a Sawmill to produce wood.\nYou'll need it to expand the town."
		_tutorial_final_elapsed = 0.0
	elif farms == 0:
		step_text = "2) Build a Farm to produce food.\nWatch Food net to avoid starvation."
		_tutorial_final_elapsed = 0.0
	else:
		step_text = "3) Balance Farms + Houses + Sawmills.\nGoal: reach 30 population."
		show_time = true
		_tutorial_final_elapsed += 0.5
		remaining = int(ceil(TUTORIAL_FINAL_DURATION_SEC - _tutorial_final_elapsed))
		if remaining <= 0:
			tutorial_panel.visible = false
			return

	tutorial_panel.visible = true
	if show_time:
		tutorial_text.text = "Tutorial (%ds)\n%s" % [remaining, step_text]
	else:
		tutorial_text.text = "Tutorial\n%s" % step_text

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
