extends Node
class_name ResourceSystem

signal resources_changed(resources: Dictionary)

var _resources: Dictionary = {
	"wood": 50,
}

func get_all() -> Dictionary:
	return _resources.duplicate(true)

func get_amount(resource_name: String) -> int:
	return int(_resources.get(resource_name, 0))

func can_afford(cost: Dictionary) -> bool:
	for k in cost.keys():
		if get_amount(str(k)) < int(cost[k]):
			return false
	return true

func try_spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false

	for k in cost.keys():
		var key := str(k)
		_resources[key] = get_amount(key) - int(cost[k])
	emit_signal("resources_changed", get_all())
	return true

func add(resource_name: String, amount: int) -> void:
	if amount == 0:
		return
	_resources[resource_name] = get_amount(resource_name) + amount
	emit_signal("resources_changed", get_all())

