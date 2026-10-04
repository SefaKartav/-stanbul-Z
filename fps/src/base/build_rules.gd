class_name BuildRules
extends RefCounted
## Insa kurallari: yerlestirme gecerliligi, maliyet, onarim.
##
## EKONOMI KURALLARI (belgenin 8. bolumu)
##   * Konan blok ORIGIN_PLACED isaretlenir; kirilinca kurtarma dususu
##     VERMEZ. Koy-kir, onar-kir dongulerinde bedelsiz net kazanc olusmaz.
##   * Maliyet mevcut esya ve tag zincirinden odenir (ayri ekonomi yok).
##   * Odeme TEK ISLEMDIR: once kopyalarda denenir; eksik varsa hicbir
##     sey harcanmaz.
##
## DESTEK KURALI (havaya sinirsiz blok, suya yapay kita yok)
##   Yeni blok ya altindaki katı bloga oturur, ya da yanindaki bir blogun
##   uzerine en fazla CANTILEVER hucre tasabilir. Haritanin kendi yapisi
##   (kopru tabliyesi, iskele, rihtim) destek sayilir: gercek kopru
##   onarilabilir; kiyidan denize 2 bloktan uzun platform uzatilamaz.
##   Su ve sivi destek DEGILDIR.

const CANTILEVER := 2
const REACH := 6.0

var world: VoxelWorld
var blocks: Dictionary = {}         # katalog: blok girdileri
var errors: Array = []


func _init(p_world: VoxelWorld) -> void:
	world = p_world
	blocks = Content.build_blocks
	for id: String in blocks:
		var entry: Dictionary = blocks[id]
		if world.materials.index_of(entry.get("material", "")) == 0:
			errors.append("build_catalog: '%s' bilinmeyen malzeme" % id)
		for cost: Dictionary in entry.get("cost", []) + entry.get("repair", []):
			if cost.has("item") and not Content.items.has(cost.item):
				errors.append("build_catalog: '%s' bilinmeyen esya %s" % [id, cost.item])


func cells_for(entry: Dictionary, origin: Vector3i, rotation_steps: int) -> Array:
	## Coklu hucreli yapinin hucreleri (orn. 3x2 barikat), donuse gore.
	var size: Array = entry.get("size", [1, 1, 1])
	var cells: Array = []
	var w := int(size[0])
	var h := int(size[1])
	var d := int(size[2])
	for y in h:
		for i in w:
			for k in d:
				var offset := Vector3i(i - w / 2, y, k)
				if rotation_steps % 2 == 1:
					offset = Vector3i(k, y, i - w / 2)
				cells.append(origin + offset)
	return cells


func supported(cell: Vector3i, pending: Dictionary = {}) -> bool:
	## Hucre dogrudan ya da kisa bir cikma ile destekleniyor mu?
	if _is_support(cell + Vector3i.DOWN, pending):
		return true
	return _cantilever_depth(cell, pending, 0) <= CANTILEVER


func _is_support(cell: Vector3i, pending: Dictionary) -> bool:
	if pending.has(cell):
		return true
	var value := world.get_cell(cell)
	if value == 0 or value == VoxelWorld.BOUNDARY:
		return false
	return world.materials.solid[value] == 1


func _cantilever_depth(cell: Vector3i, pending: Dictionary, depth: int) -> int:
	## Yandaki desteklere olan en kisa cikma uzunlugu (buyuk = desteksiz).
	if depth > CANTILEVER:
		return 99
	var best := 99
	for o: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n := cell + o
		if not _is_support(n, pending):
			continue
		# Haritanin kendi yapisi (kopru, rihtim): tam destek.
		if not world.placed.has(n) and not pending.has(n):
			return 1
		# Oyuncu blogu: kendisi yere oturuyorsa 1, degilse zincir uzar.
		if _is_support(n + Vector3i.DOWN, pending):
			best = mini(best, 1)
		else:
			best = mini(best, 1 + _cantilever_depth(n, pending, depth + 1))
	return best


func validate(cells: Array, bodies: Array) -> Dictionary:
	## {ok, reason}. `bodies`: [[aabb_min, aabb_max]] -- oyuncu/NPC/zombi.
	var pending := {}
	for cell: Vector3i in cells:
		pending[cell] = true
	for cell: Vector3i in cells:
		if not world.in_bounds(cell):
			return {"ok": false, "reason": "Harita sinirinin disi"}
		if not world.has_chunk(VoxelWorld.chunk_of(cell)):
			return {"ok": false, "reason": "Bolge yuklenmedi"}
		var value := world.get_cell(cell)
		if value != 0 and world.materials.liquid[value] == 0:
			return {"ok": false, "reason": "Dolu hucre"}
		var box_min := Vector3(cell)
		var box_max := box_min + Vector3.ONE
		for body: Array in bodies:
			var bmin: Vector3 = body[0]
			var bmax: Vector3 = body[1]
			if bmax.x > box_min.x and bmin.x < box_max.x and bmax.y > box_min.y and bmin.y < box_max.y \
					and bmax.z > box_min.z and bmin.z < box_max.z:
				return {"ok": false, "reason": "Birinin ustune konamaz"}
	# Destek: EN AZ BIR hucre desteklenmeli, gerisi ona baglanir (ayni yapi).
	var any := false
	for cell: Vector3i in cells:
		var below := cell + Vector3i.DOWN
		if not pending.has(below) and supported(cell, {}):
			any = true
			break
	if not any:
		return {"ok": false, "reason": "Destek yok -- havaya ya da suya blok konamaz"}
	return {"ok": true, "reason": ""}


# --- odeme ---
static func can_pay(cost: Array, sources: Array) -> Dictionary:
	## {ok, missing: "2x wood_plank, ..."}
	var trial: Array = sources.map(func(inv: Inventory) -> Inventory: return inv.clone())
	var missing := PackedStringArray()
	for need: Dictionary in cost:
		var left := int(need.get("count", 1))
		for inventory: Inventory in trial:
			left = _take(inventory, need, left)
			if left <= 0:
				break
		if left > 0:
			var label: String = str(Content.ui_names.get("tags", {}).get(str(need.tag), "#" + str(need.tag))) \
				if need.has("tag") else Content.item(need.item).name
			missing.append("%dx %s" % [left, label])
	return {"ok": missing.is_empty(), "missing": ", ".join(missing)}


static func pay(cost: Array, sources: Array) -> bool:
	## Tek islem: once kopyalarda dene, basariliysa asillarina uygula.
	var trial: Array = sources.map(func(inv: Inventory) -> Inventory: return inv.clone())
	for need: Dictionary in cost:
		var left := int(need.get("count", 1))
		for inventory: Inventory in trial:
			left = _take(inventory, need, left)
			if left <= 0:
				break
		if left > 0:
			return false
	for i in sources.size():
		(sources[i] as Inventory).replace_with(trial[i])
	return true


static func _take(inventory: Inventory, need: Dictionary, amount: int) -> int:
	# Dusuk kaliteden once: iyi malzeme kendiliginden korunur.
	var candidates: Array
	if need.has("tag"):
		candidates = inventory.matching_tag(need.tag)
	else:
		candidates = inventory.stacks.filter(func(s: ItemStack) -> bool: return s.definition.id == need.item)
		candidates.sort_custom(Inventory._by_quality)
	for stack: ItemStack in candidates:
		if amount <= 0:
			break
		var take := mini(amount, stack.quantity)
		stack.quantity -= take
		amount -= take
	inventory.compact()
	return amount


func repair_cost(cell: Vector3i) -> Dictionary:
	## Hasarli blogun onarim maliyeti ve miktari: {entry_id, cost, amount}
	var value := world.get_cell(cell)
	if value == 0 or value == VoxelWorld.BOUNDARY or not world.damage.has(cell):
		return {}
	var material := world.materials.ids[value]
	# Onarim tarifesi: once malzeme kademesi tablosu (upgrades[malzeme].repair),
	# sonra eski dogrudan bloklar.
	var repair: Array = Content.build_upgrades.get(material, {}).get("repair", [])
	var entry_id := material
	if repair.is_empty():
		for id: String in blocks:
			if blocks[id].material == material:
				repair = blocks[id].get("repair", [])
				entry_id = id
				break
	if repair.is_empty():
		return {}
	var maximum: float = world.materials.max_hp[value]
	var missing: float = maximum - world.hp_of(cell)
	# Tam onarim maliyeti `repair`; kismi hasarda orantili, en az 1.
	var fraction := clampf(missing / maximum, 0.0, 1.0)
	var cost: Array = []
	for c: Dictionary in repair:
		var scaled := c.duplicate()
		scaled.count = maxi(1, int(ceil(int(c.count) * fraction)))
		cost.append(scaled)
	return {"entry_id": entry_id, "cost": cost, "amount": missing}


static func rotate_offset(o: Vector3i, steps: int) -> Vector3i:
	## Y ekseni etrafinda 90 derece adimlarla (parca desenleri).
	match posmod(steps, 4):
		1:
			return Vector3i(-o.z, o.y, o.x)
		2:
			return Vector3i(-o.x, o.y, -o.z)
		3:
			return Vector3i(o.z, o.y, -o.x)
	return o


func piece_cells(piece: Dictionary, origin: Vector3i, steps: int) -> Array:
	## Yapi parcasinin hucreleri ve malzemeleri: [[hucre, malzeme_indeksi], ...].
	## `cells` deseni varsa o ([x,y,z] ya da [x,y,z,malzeme]); yoksa `size` kutusu.
	var base_material := world.materials.index_of(str(piece.get("material", "")))
	var result: Array = []
	var pattern: Array = piece.get("cells", [])
	if pattern.is_empty():
		var size: Array = piece.get("size", [1, 1, 1])
		var w := int(size[0])
		for y in int(size[1]):
			for i in w:
				for k in int(size[2]):
					pattern.append([i - w / 2, y, k])
	for raw: Variant in pattern:
		var o := Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
		var material := base_material
		if raw.size() >= 4:
			material = world.materials.index_of(str(raw[3]))
		result.append([origin + rotate_offset(o, steps), material])
	return result
