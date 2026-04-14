extends Node

## MVP population simulation:
## - Max capacity comes from placed houses (or any BuildingData.population_capacity > 0).
## - Every tick: consumes food per inhabitant, generates gold per inhabitant.
## - If not enough food: population decreases (simple starvation rule).

signal population_changed(population: int, capacity: int)

@export var tick_interval_sec: float = 1.0
@export var food_per_person_per_tick: int = 1
@export var gold_per_person_per_tick: int = 1
@export var starvation_decrease_per_tick: int = 1
@export var growth_per_tick: int = 1
@export var food_cost_per_new_person: int = 1

# Optional interval-based economy tuning (recommended for balancing).
@export var food_consumption_interval_sec: float = 6.0
@export var gold_income_interval_sec: float = 5.0

var _food_remainder: float = 0.0
var _gold_remainder: float = 0.0

var population: int = 0:
	set(value):
		population = maxi(value, 0)
		if population > capacity:
			population = capacity
		emit_signal("population_changed", population, capacity)

var capacity: int = 0:
	set(value):
		capacity = maxi(value, 0)
		if population > capacity:
			population = capacity
		emit_signal("population_changed", population, capacity)

var _timer: Timer
var _resource_manager: Node

func _ready() -> void:
	_resource_manager = get_node_or_null("/root/ResourceManager")
	if _resource_manager == null:
		push_error("PopulationManager: ResourceManager autoload not found.")

	_timer = Timer.new()
	_timer.name = "PopulationTick"
	_timer.one_shot = false
	_timer.autostart = true
	_timer.wait_time = tick_interval_sec
	add_child(_timer)
	_timer.timeout.connect(_on_tick)

	emit_signal("population_changed", population, capacity)

func add_capacity(amount: int) -> void:
	capacity += amount

func add_population(amount: int) -> void:
	population += amount

func set_population(value: int) -> void:
	population = value

func _on_tick() -> void:
	if _resource_manager == null:
		return
	if capacity <= 0:
		return

	var dt: float = tick_interval_sec

	var needed_food: int = 0
	if food_consumption_interval_sec > 0.0:
		var food_f := (float(population) * dt / food_consumption_interval_sec) + _food_remainder
		needed_food = int(floor(food_f))
		_food_remainder = food_f - float(needed_food)
	else:
		needed_food = population * food_per_person_per_tick

	if needed_food > 0 and not _resource_manager.can_afford({&"food": needed_food}):
		# Starvation rule (simple & tweakable):
		# - If you can't feed everyone this tick, you lose N population.
		# - We also drain remaining food to 0 to keep behavior predictable.
		_resource_manager.set_amount(&"food", 0)
		population = maxi(population - starvation_decrease_per_tick, 0)
		return

	# Consume food
	if needed_food > 0:
		_resource_manager.try_spend({&"food": needed_food})

	# Generate gold
	var gold_gain: int = 0
	if gold_income_interval_sec > 0.0:
		var gold_f := (float(population) * dt / gold_income_interval_sec) + _gold_remainder
		gold_gain = int(floor(gold_f))
		_gold_remainder = gold_f - float(gold_gain)
	else:
		gold_gain = population * gold_per_person_per_tick

	if gold_gain != 0:
		_resource_manager.add(&"gold", gold_gain)

	# Simple growth: if you have spare food and free capacity, population increases.
	if population < capacity and growth_per_tick > 0 and food_cost_per_new_person > 0:
		var can_add: int = mini(growth_per_tick, capacity - population)
		# Pay food per newcomer (prototype rule)
		var growth_food: int = can_add * food_cost_per_new_person
		if _resource_manager.can_afford({&"food": growth_food}):
			_resource_manager.try_spend({&"food": growth_food})
			population += can_add
