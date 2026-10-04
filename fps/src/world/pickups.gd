class_name WorldPickups
extends Node3D
## Dunyada duran esya yiginlari: blok kurtarma dususu, olumde birakilan
## canta, aramada tasinamayip GERIDE KALAN esyalar.
##
## Geride kalan esya SILINMEZ (eski oyun onu sessizce kaybediyordu): arama
## noktasinin onunde bir yigin olarak kalir, oyuncu yer acip geri gelir.
## Her yigin sonludur; almak onu eksiltir, hicbir sey kendiliginden yenilenmez.

signal changed

const PICKUP_RANGE := 2.4
const MAX_PICKUPS := 400

var entries: Array = []           # [{id, position, stacks, label, kind, node}]
var _next_id := 1


func spawn(stacks: Array, position: Vector3, label: String, kind: String = "item") -> Dictionary:
	var filtered := stacks.filter(func(s: ItemStack) -> bool: return s != null and s.quantity > 0)
	if filtered.is_empty():
		return {}
	# Yakinda ayni turden yigin varsa ona ekle: kirilan duvarin yuzlerce
	# ayri kutu birakmasi ekrani ve kayit dosyasini sisirirdi.
	if kind == "item":
		for entry: Dictionary in entries:
			if entry.kind == "item" and entry.position.distance_to(position) < 1.2:
				for stack: ItemStack in filtered:
					entry.stacks.append(stack)
				_merge(entry)
				changed.emit()
				return entry
	var entry := {"id": _next_id, "position": position, "stacks": filtered, "label": label,
		"kind": kind, "node": null}
	_next_id += 1
	_merge(entry)
	entries.append(entry)
	_build_node(entry)
	while entries.size() > MAX_PICKUPS:
		# Yalnizca "item" turu (kurtarma dususu) budanir; canta ve kalinti asla.
		var oldest := -1
		for i in entries.size():
			if entries[i].kind == "item":
				oldest = i
				break
		if oldest < 0:
			break
		_remove_at(oldest)
	changed.emit()
	return entry


func _merge(entry: Dictionary) -> void:
	var inventory := Inventory.new(9999.0, 999)
	for stack: ItemStack in entry.stacks:
		inventory.add(stack.copy())
	entry.stacks = inventory.stacks


func _build_node(entry: Dictionary) -> void:
	var node: Node3D
	if entry.kind == "pack":
		node = AssetLibrary.instantiate("backpack")
	elif entry.kind == "remnant":
		node = AssetLibrary.instantiate("storage_crate")
		node.scale = Vector3.ONE * 0.6
	else:
		var first: ItemStack = entry.stacks[0]
		node = AssetLibrary.instantiate(AssetLibrary.item_model_id(first.definition))
		var box := AssetLibrary.bounds(AssetLibrary.item_model_id(first.definition))
		var biggest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if biggest > 0.5:
			node.scale = Vector3.ONE * (0.5 / biggest)
	node.position = entry.position
	node.rotation.y = randf() * TAU
	add_child(node)
	entry.node = node


func nearest(position: Vector3, radius: float = PICKUP_RANGE) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := radius
	for entry: Dictionary in entries:
		var distance: float = entry.position.distance_to(position)
		if distance <= best_distance:
			best = entry
			best_distance = distance
	return best


func take(entry: Dictionary, inventory: Inventory) -> Dictionary:
	## Sigan her seyi alir. {taken: [ItemStack], left: [ItemStack]}
	var taken: Array = []
	var left: Array = []
	for stack: ItemStack in entry.stacks:
		var wanted := stack.quantity
		var leftover := inventory.add(stack.copy())
		if wanted - leftover > 0:
			taken.append(stack.copy(wanted - leftover))
		if leftover > 0:
			left.append(stack.copy(leftover))
	entry.stacks = left
	if left.is_empty():
		_remove_at(entries.find(entry))
	changed.emit()
	return {"taken": taken, "left": left}


func _remove_at(index: int) -> void:
	if index < 0:
		return
	var entry: Dictionary = entries[index]
	if entry.node != null and is_instance_valid(entry.node):
		entry.node.queue_free()
	entries.remove_at(index)


func describe(entry: Dictionary) -> String:
	var parts := PackedStringArray()
	for stack: ItemStack in entry.stacks.slice(0, 3):
		parts.append("%s x%d" % [stack.display_name(), stack.quantity])
	if entry.stacks.size() > 3:
		parts.append("+%d" % (entry.stacks.size() - 3))
	return "%s: %s" % [entry.label, ", ".join(parts)]


func to_dict() -> Dictionary:
	var data: Array = []
	for entry: Dictionary in entries:
		var stacks: Array = []
		for stack: ItemStack in entry.stacks:
			stacks.append(stack.to_dict())
		data.append({"p": [entry.position.x, entry.position.y, entry.position.z],
			"s": stacks, "label": entry.label, "kind": entry.kind})
	return {"entries": data}


func load_dict(data: Dictionary) -> void:
	for i in range(entries.size() - 1, -1, -1):
		_remove_at(i)
	for raw: Variant in data.get("entries", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var stacks: Array = []
		for s: Variant in raw.get("s", []):
			if typeof(s) == TYPE_DICTIONARY:
				var stack := ItemStack.from_dict(s, Content.items)
				if stack != null:
					stacks.append(stack)
		var p: Array = raw.get("p", [0, 0, 0])
		var entry := {"id": _next_id, "position": Vector3(p[0], p[1], p[2]), "stacks": stacks,
			"label": str(raw.get("label", "Esya")), "kind": str(raw.get("kind", "item")), "node": null}
		_next_id += 1
		if stacks.is_empty():
			continue
		entries.append(entry)
		_build_node(entry)
	changed.emit()
