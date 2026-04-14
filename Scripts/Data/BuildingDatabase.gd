extends Resource
class_name BuildingDatabase

@export var buildings: Array[BuildingData] = []

var _by_id: Dictionary = {}
var _index_ready: bool = false

func _init() -> void:
	_rebuild_index()

func _set(property: StringName, value: Variant) -> bool:
	# Keep index coherent when edited in inspector.
	if property == &"buildings":
		buildings = value
		_rebuild_index()
		return true
	return false

func _rebuild_index() -> void:
	_by_id.clear()
	for b in buildings:
		if b == null:
			continue
		if b.id == &"":
			continue
		_by_id[b.id] = b
	_index_ready = true

func get_by_id(id: StringName) -> BuildingData:
	if id == &"":
		return null

	# Robustness: Resource loading doesn't always call _init() the way you expect,
	# so we build lazily on first access.
	if not _index_ready or _by_id.is_empty():
		_rebuild_index()

	var v = _by_id.get(id, null)
	if v != null:
		return v

	# Fallback: scan the array (keeps prototype behavior resilient).
	for b in buildings:
		if b != null and b.id == id:
			_by_id[id] = b
			return b
	return null

func all_ids() -> Array[StringName]:
	if not _index_ready or _by_id.is_empty():
		_rebuild_index()
	var ids: Array[StringName] = []
	for k in _by_id.keys():
		ids.append(k)
	ids.sort()
	return ids

