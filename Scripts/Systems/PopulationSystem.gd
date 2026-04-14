extends Node
class_name PopulationSystem

signal population_changed(population: int)

var population: int = 0:
	set(value):
		population = value
		emit_signal("population_changed", population)

func add_people(amount: int) -> void:
	if amount == 0:
		return
	population += amount

