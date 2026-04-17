extends Node

signal victory_reached

@export var building_system_path: NodePath
@export var balance: Resource

const BuildingSystemScript := preload("res://Scripts/Systems/BuildingSystem.gd")
const BuildingDatabaseScript := preload("res://Scripts/Data/BuildingDatabase.gd")
const BuildingDataScript := preload("res://Scripts/Data/BuildingData.gd")
const BuildingScript := preload("res://Scripts/Buildings/Building.gd")
const GameBalanceScript := preload("res://Scripts/Data/GameBalance.gd")
const BuildingTuningScript := preload("res://Scripts/Data/BuildingTuning.gd")
const GridSystemScript := preload("res://Scripts/Systems/GridSystem.gd")

var _building_system: Node2D
var _victory: bool = false
var _victory_population: int = 30
var _base_caps := {&"wood": 100, &"food": 100, &"gold": 100, &"stone": 100}
var _resource_manager: Node
var _population_manager: Node
var _containment_timer: Timer

func _ready() -> void:
	_building_system = get_node_or_null(building_system_path) as Node2D
	if _building_system == null:
		push_error("GameManager: building_system_path is not set or invalid.")
		return

	(_building_system as BuildingSystemScript).building_placed.connect(_on_building_placed)

	_resource_manager = get_node_or_null("/root/ResourceManager")
	_population_manager = get_node_or_null("/root/PopulationManager")

	_apply_balance_if_any()

	_place_initial_house_center()

	if _population_manager != null:
		_population_manager.set_population(0)
		_population_manager.population_changed.connect(_on_population_changed)

	# New win condition: player wins when red spread is fully contained.
	_containment_timer = Timer.new()
	_containment_timer.name = "ContainmentCheck"
	_containment_timer.one_shot = false
	_containment_timer.autostart = true
	_containment_timer.wait_time = 0.5
	add_child(_containment_timer)
	_containment_timer.timeout.connect(_check_containment_victory)
	_check_containment_victory()

func _place_initial_house_center() -> void:
	var bs := _building_system as BuildingSystemScript
	if bs == null:
		return
	var grid := (bs.get_node_or_null(bs.grid_path) as GridSystemScript)
	if grid == null:
		return
	var cell := Vector2i(int(grid.grid_width / 2.0), int(grid.grid_height / 2.0))
	# Place the initial house (free), without place animation.
	bs.place_building_at_cell(&"house", cell, false)

func _on_building_placed(_building: Node2D, _cell: Vector2i, _building_id: StringName) -> void:
	_recalculate_derived_from_buildings()
	_assign_workers_from_population()

func _on_population_changed(pop: int, _cap: int) -> void:
	# Don't call _recalculate_derived_from_buildings() here: it sets capacity and would recurse.
	_assign_workers_from_population(pop)
	# Victory is no longer based on population; it's based on containing red spread.

func _check_containment_victory() -> void:
	if _victory:
		return
	var bs := _building_system as BuildingSystemScript
	if bs == null:
		return
	var grid := (bs.get_node_or_null(bs.grid_path) as GridSystemScript)
	if grid == null:
		return
	if not grid.can_blocked_propagate():
		_trigger_victory()

func _trigger_victory() -> void:
	_victory = true
	var bs := _building_system as BuildingSystemScript
	if bs != null:
		bs.set_gameplay_enabled(false)
	emit_signal("victory_reached")

func _recalculate_derived_from_buildings() -> void:
	# One pass for all building-derived stats (keeps the prototype deterministic).
	var total_pop_capacity: int = 0
	var total_storage_bonus: int = 0

	for b in _get_placed_buildings():
		var data := b.building_data as BuildingDataScript
		if data == null:
			continue
		total_pop_capacity += maxi(data.population_capacity * b.level, 0)
		total_storage_bonus += maxi(data.storage_capacity_bonus * b.level, 0)

	if _population_manager != null:
		_population_manager.capacity = total_pop_capacity

	if _resource_manager != null:
		var wood_cap: int = int(_base_caps.get(&"wood", 100)) + total_storage_bonus
		var food_cap: int = int(_base_caps.get(&"food", 100)) + total_storage_bonus
		var gold_cap: int = int(_base_caps.get(&"gold", 100)) + total_storage_bonus
		var stone_cap: int = int(_base_caps.get(&"stone", 100)) + total_storage_bonus
		_resource_manager.set_caps({&"wood": wood_cap, &"food": food_cap, &"gold": gold_cap, &"stone": stone_cap})

	_assign_workers_from_population()

func on_buildings_changed() -> void:
	# Public hook for UI-driven changes (ex: upgrades).
	_recalculate_derived_from_buildings()

func _assign_workers_from_population(available_workers: int = -1) -> void:
	if _building_system == null:
		return
	if available_workers < 0:
		available_workers = (_population_manager.population if _population_manager != null else 0)
	available_workers = maxi(available_workers, 0)

	var producers: Array[BuildingScript] = []
	for b in _get_placed_buildings():
		var data := b.building_data as BuildingDataScript
		if data != null and data.is_producer():
			producers.append(b)
		else:
			# Non-producers don't need workers.
			b.worker_assigned = true

	# Stable assignment so the same buildings stay active.
	producers.sort_custom(func(a: BuildingScript, c: BuildingScript) -> bool:
		var pa := _producer_priority(a)
		var pc := _producer_priority(c)
		if pa != pc:
			return pa < pc
		return a.get_instance_id() < c.get_instance_id()
	)

	var active := mini(available_workers, producers.size())
	for i in range(producers.size()):
		producers[i].worker_assigned = i < active

func _producer_priority(b: BuildingScript) -> int:
	# Lower = higher priority. Game design rule: sawmills first, then farms.
	match b.building_id:
		&"sawmill":
			return 0
		&"farm":
			return 1
		&"mine":
			return 2
		_:
			return 3

func _get_placed_buildings() -> Array[BuildingScript]:
	var out: Array[BuildingScript] = []
	for child in _building_system.get_children():
		# Skip the preview ghost
		if child is Node and (child as Node).name == "Preview":
			continue
		if child is BuildingScript:
			out.append(child as BuildingScript)
	return out

func _apply_balance_if_any() -> void:
	if balance == null:
		# Fallback: keep previous behavior.
		_base_caps = {&"wood": 100, &"food": 100, &"gold": 100}
		_victory_population = 30
		if _resource_manager != null:
			_resource_manager.set_amount(&"food", 20)
			_resource_manager.set_amount(&"gold", 0)
		_recalculate_derived_from_buildings()
		return

	var b := balance as GameBalanceScript
	if b == null:
		push_error("GameManager: balance is set but is not a GameBalance resource.")
		return

	_victory_population = maxi(b.victory_population, 1)
	_base_caps = {
		&"wood": maxi(b.base_wood_cap, 0),
		&"food": maxi(b.base_food_cap, 0),
		&"gold": maxi(b.base_gold_cap, 0),
		&"stone": maxi(b.base_stone_cap, 0),
	}

	# Apply pop simulation tuning
	if _population_manager != null:
		_population_manager.tick_interval_sec = maxf(b.pop_tick_interval_sec, 0.1)
		_population_manager.food_consumption_interval_sec = maxf(b.food_consumption_interval_sec, 0.01)
		_population_manager.gold_income_interval_sec = maxf(b.gold_income_interval_sec, 0.01)
		_population_manager.starvation_decrease_per_tick = maxi(b.starvation_decrease_per_tick, 0)
		_population_manager.growth_per_tick = maxi(b.growth_per_tick, 0)
		_population_manager.food_cost_per_new_person = maxi(b.food_cost_per_new_person, 0)

	# Apply building tuning to the database used by BuildingSystem.
	var bs := _building_system as BuildingSystemScript
	if bs != null:
		var db := bs.building_db as BuildingDatabaseScript
		if db != null:
			for t in b.buildings:
				var tune := t as BuildingTuningScript
				if tune == null or tune.id == &"":
					continue
				var data := db.get_by_id(tune.id) as BuildingDataScript
				if data == null:
					continue
				data.cost = tune.cost.duplicate(true)
				data.produces_resource = tune.produces_resource
				data.production_amount = tune.production_amount
				data.production_interval_sec = tune.production_interval_sec
				data.population_capacity = tune.population_capacity
				data.storage_capacity_bonus = tune.storage_capacity_bonus
				data.blocks_adjacent_infection = tune.blocks_adjacent_infection
				data.color = tune.color

	# Apply starting resources & caps
	if _resource_manager != null:
		_resource_manager.set_amount(&"wood", maxi(b.starting_wood, 0))
		_resource_manager.set_amount(&"food", maxi(b.starting_food, 0))
		_resource_manager.set_amount(&"gold", maxi(b.starting_gold, 0))
		_resource_manager.set_amount(&"stone", maxi(b.starting_stone, 0))

	if _population_manager != null:
		_population_manager.set_population(maxi(b.starting_population, 0))

	_recalculate_derived_from_buildings()
