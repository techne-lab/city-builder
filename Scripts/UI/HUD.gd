extends CanvasLayer

@export var building_system_path: NodePath
@export var building_db: Resource
@export var game_manager_path: NodePath

const BuildingSystemScript := preload("res://Scripts/Systems/BuildingSystem.gd")
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
@onready var toast_label: Label = %ToastLabel
@onready var toast_panel: Control = %ToastPanel
@onready var tutorial_panel: Control = %TutorialPanel
@onready var tutorial_text: Label = %TutorialText
@onready var victory_panel: Control = $Victory

var _building_system: Node
var _resource_manager: Node
var _population_manager: Node
var _game_manager: Node
var _rates_timer: Timer
var _toast_tween: Tween
var _tutorial_timer: Timer
var _tutorial_elapsed: float = 0.0

const BuildingScript := preload("res://Scripts/Buildings/Building.gd")
const TUTORIAL_DURATION_SEC: float = 60.0

func _ready() -> void:
	_building_system = get_node_or_null(building_system_path)
	if _building_system == null:
		push_error("HUD: building_system_path is not set or invalid.")

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
	%HouseButton.pressed.connect(func(): _select(&"house"))
	%FarmButton.pressed.connect(func(): _select(&"farm"))
	%LumberMillButton.pressed.connect(func(): _select(&"sawmill"))
	%StorageButton.pressed.connect(func(): _select(&"storage"))
	%House2Button.pressed.connect(func(): _select(&"house_2"))
	%Farm2Button.pressed.connect(func(): _select(&"farm_2"))
	%LumberMill2Button.pressed.connect(func(): _select(&"sawmill_2"))

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
	elif farms == 0:
		step_text = "2) Construis une Farm pour produire de la nourriture.\nSurveille Food net pour éviter la famine."
	elif mills == 0:
		step_text = "3) Construis une Lumber Mill pour produire du wood.\nTu en auras besoin pour étendre la ville."
	else:
		step_text = "4) Équilibre: Farms + Houses + Lumber Mills.\nObjectif: atteindre 30 population."

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
