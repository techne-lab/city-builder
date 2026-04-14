extends Resource
class_name BuildingData

@export var id: StringName
@export var display_name: String = ""

# Example: {"wood": 10, "stone": 5}
@export var cost: Dictionary = {}

# Production (optional)
@export var produces_resource: StringName = &""
@export var production_amount: int = 0
@export var production_interval_sec: float = 0.0

# Population (optional)
@export var population_capacity: int = 0

# Storage (optional): increases max resource capacity when > 0
@export var storage_capacity_bonus: int = 0

# Placeholder visuals
@export var color: Color = Color.WHITE

func is_producer() -> bool:
	return produces_resource != &"" and production_amount != 0 and production_interval_sec > 0.0

