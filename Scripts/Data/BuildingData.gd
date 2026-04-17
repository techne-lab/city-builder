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

# If true, free tiles in the 4-neighborhood never turn red from the spread rule.
@export var blocks_adjacent_infection: bool = false

# Placeholder visuals
@export var color: Color = Color.WHITE
@export var sprite: Texture2D

# Upgrade system
# Cost to upgrade from this building's current level to the next (scaled per level).
@export var upgrade_cost: Dictionary = {}
# Maximum level this building can reach (1 = not upgradable).
@export var max_level: int = 5
# Each level above 1 adds this fraction of base production (0.5 = +50% per level).
@export var production_level_bonus: float = 0.5
# Upgrade cost is multiplied by this value for each additional level.
@export var upgrade_cost_scale: float = 1.5

func is_producer() -> bool:
	return produces_resource != &"" and production_amount != 0 and production_interval_sec > 0.0

