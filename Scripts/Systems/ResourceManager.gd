extends Node

## Global, simple resource store for an MVP city builder.
## Intended to be used as an AutoLoad singleton (see project.godot [autoload]).

signal resources_changed(resources: Dictionary)
signal resource_changed(resource_name: StringName, new_amount: int)
signal caps_changed(caps: Dictionary)

const WOOD: StringName = &"wood"
const FOOD: StringName = &"food"
const GOLD: StringName = &"gold"
const STONE: StringName = &"stone"

var _res: Dictionary = {
	WOOD: 0,
	FOOD: 0,
	GOLD: 0,
	STONE: 0,
}

var _caps: Dictionary = {
	WOOD: 100,
	FOOD: 100,
	GOLD: 100,
	STONE: 100,
}

func _ready() -> void:
	_emit_all_changed()

func get_all() -> Dictionary:
	return _res.duplicate(true)

func get_caps() -> Dictionary:
	return _caps.duplicate(true)

func get_cap(resource_name: StringName) -> int:
	return int(_caps.get(resource_name, 0))

func set_caps(new_caps: Dictionary) -> void:
	# Expected: {&"wood": 200, &"food": 150, &"gold": 100}
	for k in new_caps.keys():
		var res_name: StringName = k
		_caps[res_name] = maxi(int(new_caps[k]), 0)

	# Clamp current amounts to new caps.
	for k in _res.keys():
		var res_name: StringName = k
		var capped := _clamp_to_cap(res_name, get_amount(res_name))
		_res[res_name] = capped

	emit_signal("caps_changed", get_caps())
	_emit_all_changed()

func get_amount(resource_name: StringName) -> int:
	return int(_res.get(resource_name, 0))

func set_amount(resource_name: StringName, amount: int) -> void:
	var new_amount: int = _clamp_to_cap(resource_name, amount)
	_res[resource_name] = new_amount
	emit_signal("resource_changed", resource_name, new_amount)
	emit_signal("resources_changed", get_all())

func add(resource_name: StringName, amount: int) -> void:
	if amount == 0:
		return
	set_amount(resource_name, get_amount(resource_name) + amount)

func can_afford(cost: Dictionary) -> bool:
	# cost example: {&"wood": 10, &"gold": 5}
	for k in cost.keys():
		var res_name: StringName = StringName(str(k))
		var needed := int(cost[k])
		if needed <= 0:
			continue
		if get_amount(res_name) < needed:
			return false
	return true

func try_spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false

	for k in cost.keys():
		var res_name: StringName = StringName(str(k))
		var needed := int(cost[k])
		if needed <= 0:
			continue
		_res[res_name] = get_amount(res_name) - needed

	_emit_all_changed()
	return true

func _clamp_to_cap(resource_name: StringName, amount: int) -> int:
	var a: int = maxi(amount, 0)
	var cap: int = maxi(get_cap(resource_name), 0)
	return mini(a, cap)

func _emit_all_changed() -> void:
	# Emit per-resource first (handy for UI bindings),
	# then a full snapshot for simple HUD updates.
	for k in _res.keys():
		emit_signal("resource_changed", k, int(_res[k]))
	emit_signal("resources_changed", get_all())
