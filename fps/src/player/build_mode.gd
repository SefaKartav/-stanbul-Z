class_name BuildMode
extends Node3D
## Insa kipi (B): planli savunma ve us insasi.
##
## YAPI DONGUSU (belgenin 3. bolumu):
##   taslak/parca yerlestirme -> malzeme tuketme -> YUKSELTME -> hasar ->
##   ONARIM -> sinirli geri kazanim (SOK).
##   * Yapi parcasi: uretim ekraninda (C) uretilen `building` esyasi. Her
##     parca bir desendir (duvar 1x1..3x3, doseme, kolon, merdiven, rampa,
##     pencereli duvar, kapi boslugu, kapi, kapak...). Yerlestirme parcayi harcar.
##   * Eski dogrudan maliyetli bloklar (iskelet/barikat/kum torbasi) aynen kalir.
##   * Yukselt: bakilan OYUNCU blogu bir ust kademeye (upgrades tablosu),
##     malzeme odenir, can tam olur. Ahsap -> guclendirilmis ahsap -> tugla ->
##     beton -> betonarme -> celik gibi.
##   * Onar: hasarli blogu orantili malzemeyle onarir.
##   * Blok sok: OYUNCU blogunu kaldirir, kademenin `salvage` listesinden
##     KISMI malzeme doner (maliyetin altinda: koy-sok dongusu kazandirmaz).
##   * Yapi sok: yerlestirilmis tezgah/taret/tuzagi AYNI kalitede geri alir;
##     icindekiler (depo, sarjor) da doner.
##   * Kapi: iki hucrelik kapi parcasi E ile acilir/kapanir; kapaliyken katı,
##     acikken hava. Zombi kapali kapiya saldirir; kirilirsa kapi yok olur.
## Destek kurali BuildRules'ta (havaya sinirsiz platform yok).
## Insa kipinde silah INIKTIR: sol tik ates etmez, yapi kurar.

signal message(text: String, color: Color)

const REACH := 6.0

var game: Node
var rules: BuildRules
var active := false
var entries: Array = []            # [{kind, id, label, data?}]
var index := 0
var rotation_steps := 0
var doors: Dictionary = {}         # kok hucre (Vector3i) -> {material, cells: [Vector3i], open}
var _door_of: Dictionary = {}      # hucre -> kok
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _target_cells: Array = []
var _target_mats: Array = []
var _target_valid := false
var _target_reason := ""
var _target_extra: Dictionary = {}
var _toggling := false


func setup(p_game: Node) -> void:
	game = p_game
	rules = BuildRules.new(game.world)
	_ghost = MeshInstance3D.new()
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.no_depth_test = false
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	game.world.block_changed.connect(_on_block_changed)


func toggle() -> void:
	active = not active
	_ghost.visible = false
	if active:
		_rebuild_entries()
		message.emit("İnşa kipi: tekerlek seç, R döndür, sol tık kur. B ile çık.", Hud.ACCENT)
	game.weapon_view.visible = not active and game.combat.state != null


func select_item(item_id: String) -> void:
	## Uretim ekranindan "B kipinde kur": kipi acar ve esyayi secer.
	if not active:
		toggle()
	_rebuild_entries()
	for i in entries.size():
		if str(entries[i].get("id", "")) == item_id:
			index = i
			return


func _rebuild_entries() -> void:
	entries = [{"kind": "repair", "id": "repair", "label": "Onar"},
		{"kind": "upgrade", "id": "upgrade", "label": "Yükselt"},
		{"kind": "dismantle", "id": "dismantle", "label": "Yapı sök (geri al)"},
		{"kind": "unbuild", "id": "unbuild", "label": "Blok sök (kısmi geri kazanım)"}]
	for id: String in rules.blocks:
		var entry: Dictionary = rules.blocks[id]
		entries.append({"kind": "block", "id": id, "label": "Taslak: " + str(entry.label), "data": entry})
	# Envanterdeki yapi parcalari ve yerlestirilebilir uretilmis esyalar.
	var seen := {}
	for stack: ItemStack in game.inventory.stacks:
		var id := stack.definition.id
		if seen.has(id):
			continue
		if stack.definition.category == "building" and Content.build_pieces.has(stack.definition.build):
			seen[id] = true
			entries.append({"kind": "piece", "id": id, "label": "%s (%d)" % [stack.definition.name, game.inventory.count(id)],
				"data": Content.build_pieces[stack.definition.build]})
		elif game.placeables.is_placeable(id):
			seen[id] = true
			entries.append({"kind": "placeable", "id": id, "label": "%s (%d)" % [stack.definition.name, game.inventory.count(id)]})
	index = clampi(index, 0, entries.size() - 1)


func current() -> Dictionary:
	return entries[index] if not entries.is_empty() else {}


func cycle(direction: int) -> void:
	if entries.is_empty():
		return
	index = posmod(index + direction, entries.size())


func update(_delta: float) -> void:
	if not active:
		return
	var entry := current()
	var eye: Vector3 = game.player.eye_position()
	var look: Vector3 = game.player.look_direction()
	var hit := VoxelRay.cast(game.world, eye, look, REACH)
	_target_cells = []
	_target_mats = []
	_target_extra = {}
	_target_valid = false
	_target_reason = "Hedef yok -- bir yüzeye bak"
	if entry.is_empty():
		return
	match entry.kind:
		"repair":
			if not hit.is_empty() and not hit.boundary:
				var repair := rules.repair_cost(hit.cell)
				_target_cells = [hit.cell]
				if repair.is_empty():
					_target_reason = "Onarılacak hasar yok (ya da bu malzeme onarılamaz)"
				else:
					var pay := BuildRules.can_pay(repair.cost, _sources())
					_target_valid = pay.ok
					_target_reason = "Onar: %s" % _cost_text(repair.cost) if pay.ok else "Eksik: " + pay.missing
					_target_extra = repair
		"upgrade":
			if not hit.is_empty() and not hit.boundary:
				_target_cells = [hit.cell]
				var material: String = game.world.materials.ids[hit.value]
				var up: Dictionary = Content.build_upgrades.get(material, {})
				if not game.world.placed.has(hit.cell):
					_target_reason = "Yalnızca kendi kurduğun blok yükseltilir"
				elif up.is_empty() or str(up.get("to", "")) == "":
					_target_reason = "%s en üst kademede" % str(Content.blocks.get_def(hit.value).get("name", material))
				elif is_door(hit.cell):
					_target_reason = "Kapı yükseltilmez; yeni kapı parçası kur"
				else:
					var cost: Array = up.get("cost", [])
					var pay := BuildRules.can_pay(cost, _sources())
					_target_valid = pay.ok
					var to_name := str(Content.blocks.defs.get(str(up.to), {}).get("name", up.to))
					_target_reason = ("Yükselt -> %s: %s" % [to_name, _cost_text(cost)]) if pay.ok else "Eksik: " + pay.missing
					_target_extra = {"to": str(up.to), "cost": cost}
		"dismantle":
			var near: Dictionary = game.placeables.nearest(eye + look * 2.0, 2.5)
			if not near.is_empty():
				_target_cells = [near.cell]
				_target_valid = true
				_target_reason = "Sök: %s" % Content.item(near.item_id).name
				_target_extra = near
			else:
				_target_reason = "Yakında sökülecek yapı yok"
		"unbuild":
			if not hit.is_empty() and not hit.boundary:
				_target_cells = [hit.cell]
				if not game.world.placed.has(hit.cell) or not game.placeables.entry_at_cell(hit.cell).is_empty():
					_target_reason = "Yalnızca kendi kurduğun blok sökülür (yapılar için \"Yapı sök\")"
				else:
					_target_valid = true
					var back := _salvage_of(game.world.materials.ids[hit.value])
					_target_reason = "Blok sök: geri %s" % (_cost_text(back) if not back.is_empty() else "hiçbir şey")
		"block", "placeable", "piece":
			if not hit.is_empty() and not hit.boundary:
				var origin: Vector3i = hit.cell + Vector3i(hit.normal)
				if entry.kind == "block":
					_target_cells = rules.cells_for(entry.data, origin, rotation_steps)
				elif entry.kind == "piece":
					for pair: Array in rules.piece_cells(entry.data, origin, rotation_steps):
						_target_cells.append(pair[0])
						_target_mats.append(pair[1])
				else:
					_target_cells = game.placeables.footprint(entry.id, origin, rotation_steps)
				var check := rules.validate(_target_cells, _bodies())
				if entry.kind == "placeable":
					for cell: Vector3i in _target_cells:
						if game.placeables.occupied(cell):
							check = {"ok": false, "reason": "Burada zaten bir yapı var"}
					if check.ok and not rules._is_support(origin + Vector3i.DOWN, {}):
						check = {"ok": false, "reason": "Zemine konmalı"}
				if not check.ok:
					_target_reason = check.reason
				elif entry.kind == "block":
					var pay := BuildRules.can_pay(entry.data.cost, _sources())
					_target_valid = pay.ok
					_target_reason = "Maliyet: %s" % _cost_text(entry.data.cost) if pay.ok else "Eksik: " + pay.missing
				else:
					_target_valid = game.inventory.count(entry.id) > 0
					_target_reason = ("Yerleştir: %s" % entry.label) if _target_valid else "Çantada kalmadı"
	_update_ghost()


func _update_ghost() -> void:
	if _target_cells.is_empty():
		_ghost.visible = false
		return
	var lo := Vector3(_target_cells[0])
	var hi := lo + Vector3.ONE
	for cell: Vector3i in _target_cells:
		lo = lo.min(Vector3(cell))
		hi = hi.max(Vector3(cell) + Vector3.ONE)
	var box := BoxMesh.new()
	box.size = (hi - lo) + Vector3(0.02, 0.02, 0.02)
	_ghost_material.albedo_color = Color(0.3, 0.9, 0.4, 0.35) if _target_valid else Color(0.95, 0.25, 0.2, 0.35)
	box.material = _ghost_material
	_ghost.mesh = box
	_ghost.global_position = (lo + hi) * 0.5
	_ghost.visible = true


func status_text() -> String:
	if not active:
		return ""
	var entry := current()
	return "[İNŞA] %s  (%d/%d)  R: döndür · %s" % [entry.get("label", ""), index + 1, entries.size(), _target_reason]


func _sources() -> Array:
	var sources: Array = [game.inventory]
	if game.bases.inside != null:
		sources.append(game.bases.inside.stockpile)
	return sources


func _bodies() -> Array:
	var bodies: Array = []
	var p: Vector3 = game.player.global_position
	bodies.append([p - Vector3(0.3, 0, 0.3), p + Vector3(0.3, 1.8, 0.3)])
	for actor: Node3D in game.actors.near(p, 12.0):
		var a := actor.global_position
		bodies.append([a - Vector3(0.35, 0, 0.35), a + Vector3(0.35, 1.9, 0.35)])
	return bodies


static func _cost_text(cost: Array) -> String:
	var parts := PackedStringArray()
	for need: Dictionary in cost:
		var label: String = str(Content.ui_names.get("tags", {}).get(str(need.tag), "#" + str(need.tag))) \
			if need.has("tag") else Content.item(need.item).name
		parts.append("%d× %s" % [int(need.count), label])
	return ", ".join(parts)


static func _salvage_of(material: String) -> Array:
	return Content.build_upgrades.get(material, {}).get("salvage", [])


func confirm() -> void:
	## Sol tik: gecerliyse uygula. Odeme ve yerlestirme TEK islem.
	if not active or not _target_valid:
		if active and _target_reason != "":
			message.emit(_target_reason, Hud.RED)
			game.sfx.play_ui("ui_error")
		return
	var entry := current()
	var speed: float = game.skills.multiplier("build_speed")
	match entry.kind:
		"block":
			if not BuildRules.pay(entry.data.cost, _sources()):
				message.emit("Ödeme yapılamadı", Hud.RED)
				return
			var material: int = game.world.materials.index_of(entry.data.material)
			for cell: Vector3i in _target_cells:
				game.world.set_block(cell, material, VoxelWorld.ORIGIN_PLACED)
			game.sfx.play_at("build_place", Vector3(_target_cells[0]) + Vector3(0.5, 0.5, 0.5), -2.0)
		"piece":
			var stack: ItemStack = game.inventory.find(entry.id)
			if stack == null or game.inventory.take_from_stack(stack, 1) == null:
				_rebuild_entries()
				return
			var data: Dictionary = entry.data
			for i in _target_cells.size():
				game.world.set_block(_target_cells[i], _target_mats[i], VoxelWorld.ORIGIN_PLACED)
			if bool(data.get("door", false)):
				_register_door(_target_cells.duplicate(), str(data.material))
			game.sfx.play_at("build_place", Vector3(_target_cells[0]) + Vector3(0.5, 0.5, 0.5), -2.0)
			game.progression.count("built")
			_rebuild_entries()
		"placeable":
			var stack: ItemStack = game.inventory.find(entry.id)
			if stack == null:
				_rebuild_entries()
				return
			var one: ItemStack = game.inventory.take_from_stack(stack, 1)
			game.placeables.place(one, _target_cells[0], rotation_steps)
			game.sfx.play_at("build_place", Vector3(_target_cells[0]), -2.0)
			message.emit("%s yerleştirildi" % one.definition.name, Hud.GREEN)
			_rebuild_entries()
		"repair":
			if BuildRules.pay(_target_extra.cost, _sources()):
				game.world.repair(_target_cells[0], _target_extra.amount * maxf(1.0, speed))
				game.sfx.play_at("build_place", Vector3(_target_cells[0]), -6.0)
		"upgrade":
			if not BuildRules.pay(_target_extra.cost, _sources()):
				message.emit("Ödeme yapılamadı", Hud.RED)
				return
			var cell: Vector3i = _target_cells[0]
			var to: int = game.world.materials.index_of(str(_target_extra.to))
			game.world.set_block(cell, to, VoxelWorld.ORIGIN_PLACED)
			game.sfx.play_at("build_place", Vector3(cell), -3.0)
			message.emit("Yükseltildi: %s" % str(Content.blocks.get_def(to).get("name", "")), Hud.GREEN)
		"unbuild":
			var cell: Vector3i = _target_cells[0]
			var material: String = game.world.materials.ids[game.world.get_cell(cell)]
			var back: Array = []
			# Hasarli blok daha az verir (yari canin altinda hic).
			var ratio: float = game.world.hp_of(cell) / maxf(1.0, game.world.materials.max_hp[game.world.get_cell(cell)])
			if ratio >= 0.5:
				for need: Dictionary in _salvage_of(material):
					var def := Content.item(str(need.get("item", "")))
					if def != null:
						back.append(ItemStack.new(def, int(need.count), 30.0))
			_forget_door_cell(cell)
			game.world.set_block(cell, 0, VoxelWorld.ORIGIN_WORLD)
			var left: Array = []
			for stack: ItemStack in back:
				var n: int = game.inventory.add(stack.copy())
				if n > 0:
					left.append(stack.copy(n))
			if not left.is_empty():
				game.pickups.spawn(left, Vector3(cell) + Vector3(0.5, 0.2, 0.5), "Söküm", "remnant")
			message.emit("Söküldü%s" % (": " + _cost_text(_salvage_of(material)) if not back.is_empty() else " (hasarlı: geri kazanım yok)"),
				Hud.GREEN if not back.is_empty() else Hud.ACCENT)
		"dismantle":
			var contents: Array = game.placeables.take_contents(_target_extra)
			var returned: ItemStack = game.placeables.remove_entry(_target_extra)
			if returned != null:
				contents.append(returned)
			var leftover: Array = []
			for stack: ItemStack in contents:
				var n: int = game.inventory.add(stack.copy())
				if n > 0:
					leftover.append(stack.copy(n))
			if not leftover.is_empty():
				game.pickups.spawn(leftover, Vector3(_target_extra.cell) + Vector3(0.5, 0.2, 0.5), "Sökülen", "remnant")
			if returned != null:
				message.emit("%s geri alındı" % returned.definition.name, Hud.GREEN)
			_rebuild_entries()


# ---------------------------------------------------------------------------
# Kapilar
# ---------------------------------------------------------------------------
func _register_door(cells: Array, material: String) -> void:
	var root: Vector3i = cells[0]
	for c: Vector3i in cells:
		if c.y < root.y:
			root = c
	doors[root] = {"material": material, "cells": cells, "open": false}
	for c: Vector3i in cells:
		_door_of[c] = root


func is_door(cell: Vector3i) -> bool:
	return _door_of.has(cell) and not bool(doors[_door_of[cell]].open)


func door_root(cell: Vector3i) -> Vector3i:
	return _door_of.get(cell, cell)


func door_open(root: Vector3i) -> bool:
	return doors.has(root) and bool(doors[root].open)


func open_door_near(point: Vector3, radius: float) -> Vector3i:
	for root: Vector3i in doors:
		if not bool(doors[root].open):
			continue
		for c: Vector3i in doors[root].cells:
			if (Vector3(c) + Vector3(0.5, 0.5, 0.5)).distance_to(point) < radius:
				return root
	return Vector3i.MAX


func toggle_door(root: Vector3i, body_check: Callable) -> String:
	if not doors.has(root):
		return ""
	var door: Dictionary = doors[root]
	var material: int = game.world.materials.index_of(str(door.material))
	_toggling = true
	if bool(door.open):
		for c: Vector3i in door.cells:
			if body_check.is_valid() and body_check.call(Vector3(c), Vector3(c) + Vector3.ONE):
				_toggling = false
				return "Kapının önünde biri var"
		for c: Vector3i in door.cells:
			game.world.set_block(c, material, VoxelWorld.ORIGIN_PLACED)
		door.open = false
	else:
		for c: Vector3i in door.cells:
			game.world.set_block(c, 0, VoxelWorld.ORIGIN_WORLD)
		door.open = true
	_toggling = false
	return "Kapı %s" % ("açıldı" if door.open else "kapandı")


func _forget_door_cell(cell: Vector3i) -> void:
	if not _door_of.has(cell):
		return
	var root: Vector3i = _door_of[cell]
	for c: Vector3i in doors[root].cells:
		_door_of.erase(c)
	doors.erase(root)


func _on_block_changed(cell: Vector3i, _previous: int, current: int) -> void:
	## Kapali kapi hucresi kirildi (zombi/patlama): kapi yok olur.
	if _toggling or current != 0 or not _door_of.has(cell):
		return
	var root: Vector3i = _door_of[cell]
	if bool(doors[root].open):
		return
	_toggling = true
	for c: Vector3i in doors[root].cells:
		if c != cell and game.world.get_cell(c) != 0 and game.world.placed.has(c):
			game.world.set_block(c, 0, VoxelWorld.ORIGIN_WORLD)
	_toggling = false
	_forget_door_cell(cell)
	message.emit("Bir kapı kırıldı!", Hud.RED)


func to_dict() -> Dictionary:
	var list: Array = []
	for root: Vector3i in doors:
		var d: Dictionary = doors[root]
		var cells: Array = []
		for c: Vector3i in d.cells:
			cells.append([c.x, c.y, c.z])
		list.append({"material": d.material, "cells": cells, "open": d.open})
	return {"doors": list}


func load_dict(data: Dictionary) -> void:
	doors.clear()
	_door_of.clear()
	for raw: Variant in data.get("doors", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var cells: Array = []
		for c: Variant in raw.get("cells", []):
			cells.append(Vector3i(int(c[0]), int(c[1]), int(c[2])))
		if cells.is_empty():
			continue
		_register_door(cells, str(raw.get("material", "door_wood")))
		doors[door_root(cells[0])].open = bool(raw.get("open", false))
