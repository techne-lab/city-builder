extends Resource
class_name BuildingTuning

@export var id: StringName

@export var cost: Dictionary = {}

@export var produces_resource: StringName = &""
@export var production_amount: int = 0
@export var production_interval_sec: float = 0.0

@export var population_capacity: int = 0
@export var storage_capacity_bonus: int = 0

@export var color: Color = Color.WHITE

