extends Node

@export var building_system_path: NodePath

const BuildingSystemScript := preload("res://Scripts/Systems/BuildingSystem.gd")

var _building_system: Node2D

func _ready() -> void:
	_building_system = get_node_or_null(building_system_path) as Node2D
	if _building_system == null:
		push_error("DebugInput: building_system_path is not set or invalid.")

func _unhandled_input(event: InputEvent) -> void:
	if _building_system == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				(_building_system as BuildingSystemScript).select_building(&"house")
			KEY_2:
				(_building_system as BuildingSystemScript).select_building(&"farm")
			KEY_3:
				(_building_system as BuildingSystemScript).select_building(&"sawmill")
			KEY_ESCAPE:
				(_building_system as BuildingSystemScript).cancel_selection()

