extends Resource
class_name GameBalance

## Central place to tweak game-design values for the prototype.

@export var victory_population: int = 30

@export var base_wood_cap: int = 100
@export var base_food_cap: int = 100
@export var base_gold_cap: int = 100
@export var base_stone_cap: int = 100

@export var starting_food: int = 20
@export var starting_gold: int = 0
@export var starting_wood: int = 20
@export var starting_stone: int = 0
@export var starting_population: int = 2

@export var pop_tick_interval_sec: float = 1.0
@export var food_consumption_interval_sec: float = 6.0
@export var gold_income_interval_sec: float = 5.0
@export var starvation_decrease_per_tick: int = 1
@export var growth_per_tick: int = 1
@export var food_cost_per_new_person: int = 1

@export var buildings: Array[BuildingTuning] = []

