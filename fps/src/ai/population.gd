class_name Population
extends Node3D
## KALICI BOLGESEL ZOMBI NUFUSU (sabit harita; bkz. data/world/zones.json).
##
## Uc katman -- 100 km2'nin zombileri bastan sahneye konmaz:
##   1. BOLGE (uzak): 100 m hucre basina kalici nufus butcesi. Butce alan
##      yogunlugundan (merkez 250-450, konut 120-220, ceper 20-60 /km2) gelir;
##      buyuk kurum (hastane, askeri, hapishane, okul...) kendi hucrelerinde
##      alan butcesinin YERINE kendi nufusunu (40-120) koyar -- ikinci kez
##      eklenmez. Oldurulen zombi hucreden DUSER ve kayitta saklanir; gunde
##      yalnizca %5 geri dolar (oyuncu 300 m icindeyse hic dolmaz).
##   2. TEMSIL (orta, NEAR_R..MID_R): hucrenin yasayan nufusu kadar hafif
##      kayit: konum, tur, can. Seyrek guncellenir (0.5 sn), gurultuye dogru
##      suruklenir; tek bir MultiMesh ile cizilir (mahalle bos gorunmez).
##   3. TAM AI (yakin): temsil oyuncuya NEAR_R'den yaklasinca, GORUS HATTI
##      DISINDAYSA ve en az 35 m uzaktaysa gercek zombiye doner. Uzaklasan
##      uyuyan zombi can ve turuyle temsile geri doner (can sifirlanmaz).
## Ilk dogusun 100 m cevresi bos (nefes alani), 100-250 m arasi kademeli.

const CELL := 100
const NEAR_MAX := 90
const MID_MAX := 240
const NEAR_R := 105.0
const MID_R := 300.0
const DESPAWN_R := 150.0
const MIN_PROMOTE := 35.0
const SAFE_R := 100.0
const SAFE_RAMP := 150.0
const REGROW_PER_DAY := 0.05
const TICK := 0.5

var city: CityGenerator
var manager: ZombieManager
var n := 0
var budget := PackedFloat32Array()
var killed := PackedFloat32Array()
var out := PackedInt32Array()          # hucreden cikmis temsil + tam AI
var table_of := PackedInt32Array()     # hucre -> _tables indeksi
var danger := PackedFloat32Array()
var _tables: Array = []                # [[ZombieDef, agirlik], ...]
var reps: Array = []                   # [{p, def, cell, hp, v}]
var spawn_origin := Vector3.INF
var total_budget := 0.0
var promoted_total := 0
var demoted_total := 0
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _mm: MultiMeshInstance3D
var _noise := Vector3.INF
var _noise_time := 0.0


func setup(p_city: CityGenerator, p_manager: ZombieManager, origin: Vector3) -> void:
	city = p_city
	manager = p_manager
	spawn_origin = origin
	_rng.seed = hash(city.map_id + ":nufus")
	n = int(ceil(city.width / float(CELL)))
	budget.resize(n * n)
	killed.resize(n * n)
	out.resize(n * n)
	table_of.resize(n * n)
	danger.resize(n * n)
	var zone_tables := {}
	for zone_id: String in Content.zones:
		if zone_id.begins_with("_") or zone_id == "institutions":
			continue
		zone_tables[zone_id] = _add_table(Content.zones[zone_id].get("zombies", {}))
	for cz in n:
		for cx in n:
			var i := cz * n + cx
			var land := 0
			var zone := ""
			for s: Vector2 in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.5, 0.5), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]:
				var d := city.district_at((cx + s.x) * CELL, (cz + s.y) * CELL)
				if not d.is_empty():
					land += 1
					zone = str(d.zone)
			if zone == "" or not Content.zones.has(zone):
				table_of[i] = -1
				continue
			var prof: Dictionary = Content.zones[zone]
			var span: Array = prof.get("density_km2", [100, 100])
			var t := float(abs(hash(Vector2i(cx, cz))) % 1000) / 1000.0
			budget[i] = lerpf(float(span[0]), float(span[1]), t) * (CELL * CELL / 1e6) * land / 5.0
			table_of[i] = int(zone_tables[zone])
			danger[i] = float(prof.get("danger", 1.0))
	_apply_institutions()
	_apply_safe_zone()
	for v in budget:
		total_budget += v
	_mm = MultiMeshInstance3D.new()
	_mm.name = "PopulationImpostors"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.28
	mesh.height = 1.75
	mesh.radial_segments = 6
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.material = mat
	mm.mesh = mesh
	mm.instance_count = MID_MAX
	mm.visible_instance_count = 0
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)
	manager.zombie_killed.connect(_on_killed)
	manager.noise_made.connect(func(p: Vector3, r: float) -> void:
		if r > 25.0:
			_noise = p
			_noise_time = 20.0)


func _add_table(weights: Dictionary) -> int:
	var table: Array = []
	for id: String in weights:
		var def: ZombieDef = Content.zombies.get(id)
		if def != null:
			table.append([def, float(weights[id])])
	_tables.append(table)
	return _tables.size() - 1


func _apply_institutions() -> void:
	var inst: Dictionary = Content.zones.get("institutions", {})
	# Buyuk kurum once: hucresini kucuk kurum (kapidaki kontrol noktasi) almaz.
	var order: Array = city.pois().filter(func(p: Dictionary) -> bool: return inst.has(str(p.get("kind", ""))))
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(inst[a.kind].count[1]) > float(inst[b.kind].count[1]))
	var claimed := {}
	for poi: Dictionary in order:
		var kind := str(poi.get("kind", ""))
		var prof: Dictionary = inst[kind]
		var span: Array = prof.get("count", [40, 80])
		var count := lerpf(float(span[0]), float(span[1]), float(abs(hash(str(poi.name))) % 1000) / 1000.0)
		var table := _add_table(prof.get("zombies", {}))
		var cells: Array = []
		var p := Vector2(float(poi.p[0]), float(poi.p[1]))
		var reach := 90.0 if kind in ["hospital", "military", "prison", "school"] else 30.0
		for cz in range(int((p.y - reach) / CELL), int((p.y + reach) / CELL) + 1):
			for cx in range(int((p.x - reach) / CELL), int((p.x + reach) / CELL) + 1):
				if cx >= 0 and cz >= 0 and cx < n and cz < n:
					var c := Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL)
					if c.distance_to(p) <= reach + CELL * 0.71 and not claimed.has(cz * n + cx):
						cells.append(cz * n + cx)
		if cells.is_empty():
			continue
		for i: int in cells:
			# Kurum nufusu alan butcesinin YERINE gecer (ikinci kez eklenmez).
			budget[i] = count / cells.size()
			claimed[i] = true
			table_of[i] = table
			danger[i] = float(prof.get("danger", 1.2))


func _apply_safe_zone() -> void:
	if spawn_origin == Vector3.INF:
		return
	for cz in n:
		for cx in n:
			var c := Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL)
			var d := c.distance_to(Vector2(spawn_origin.x, spawn_origin.z)) - CELL * 0.5
			if d < SAFE_R:
				budget[cz * n + cx] = 0.0
			elif d < SAFE_R + SAFE_RAMP:
				budget[cz * n + cx] *= (d - SAFE_R) / SAFE_RAMP


func alive(i: int) -> float:
	return maxf(0.0, budget[i] - killed[i])


func cell_of(p: Vector3) -> int:
	var cx := clampi(int(p.x) / CELL, 0, n - 1)
	var cz := clampi(int(p.z) / CELL, 0, n - 1)
	return cz * n + cx


func density_at(p: Vector3) -> float:
	## Yasayan nufus / km2 (3x3 hucre ortalamasi) -- dalga olcegi ve teshis.
	var c := cell_of(p)
	var cx := c % n
	var cz := c / n
	var total := 0.0
	var cells := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if cx + dx >= 0 and cz + dz >= 0 and cx + dx < n and cz + dz < n:
				total += alive((cz + dz) * n + cx + dx)
				cells += 1
	return total / maxf(1.0, cells) / (CELL * CELL / 1e6)


func wave_scale(focus: Vector3) -> float:
	## Yedinci gece dalgasi ussun bolgesine gore: kalabalik merkezde buyur,
	## ceperde kuculur (konut 170/km2 = 1.0).
	if focus == Vector3.INF:
		return 1.0
	return clampf(density_at(focus) / 170.0, 0.6, 1.9)


# ---------------------------------------------------------------------------
# Dongu
# ---------------------------------------------------------------------------
func tick(delta: float, player: Vector3, ctx: Dictionary) -> void:
	_timer += delta
	_noise_time -= delta
	if _timer < TICK:
		return
	var dt := _timer
	_timer = 0.0
	_fill_reps(player)
	_move_reps(dt, player)
	_promote(player, ctx)
	_demote(player)
	_draw(player)


func _fill_reps(player: Vector3) -> void:
	## Halkadaki hucrelerin yasayan nufusu kadar temsil; halka disindakiler
	## hucreye (sayiya) doner.
	for rep: Dictionary in reps.duplicate():
		if Vector2(rep.p.x - player.x, rep.p.z - player.z).length() > MID_R + CELL:
			reps.erase(rep)
			out[int(rep.cell)] -= 1
	var pc := cell_of(player)
	var pcx := pc % n
	var pcz := pc / n
	var r := int(ceil(MID_R / CELL))
	var cells: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cx := pcx + dx
			var cz := pcz + dz
			if cx < 0 or cz < 0 or cx >= n or cz >= n:
				continue
			var i := cz * n + cx
			if table_of[i] < 0:
				continue
			var c := Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL)
			var d := c.distance_to(Vector2(player.x, player.z))
			if d <= MID_R + CELL * 0.5:
				cells.append([d, i])
	cells.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in cells:
		if reps.size() >= MID_MAX:
			break
		var i: int = entry[1]
		var want := int(round(alive(i)))
		var tries := 0
		while out[i] < want and reps.size() < MID_MAX and tries < 12:
			tries += 1
			var p := _random_point(i, player)
			if p == Vector3.INF:
				continue
			var table: Array = _tables[table_of[i]]
			var def := _pick(table)
			reps.append({"p": p, "def": def, "cell": i, "hp": def.health, "v": Vector3.ZERO})
			out[i] += 1


func _random_point(i: int, player: Vector3) -> Vector3:
	var cx := i % n
	var cz := i / n
	var x := (cx + _rng.randf()) * CELL
	var z := (cz + _rng.randf()) * CELL
	# Yeni temsil oyuncunun dibinde belirmez.
	if Vector2(x - player.x, z - player.z).length() < 60.0:
		return Vector3.INF
	var info := city.column_info(int(x), int(z))
	if info.kind in ["building", "sea", "void"] or info.has("bridge"):
		return Vector3.INF
	return Vector3(x, city.surface_y(int(x), int(z)), z)


func _pick(table: Array) -> ZombieDef:
	var total := 0.0
	for e: Array in table:
		total += float(e[1])
	var roll := _rng.randf() * total
	for e: Array in table:
		roll -= float(e[1])
		if roll <= 0.0:
			return e[0]
	return table[0][0]


func _move_reps(dt: float, player: Vector3) -> void:
	## Seyrek ve ucuz hareket: yavas dolasma; son buyuk gurultuye dogru suruklenme.
	for rep: Dictionary in reps:
		var v: Vector3 = rep.v
		if _noise_time > 0.0 and Vector2(rep.p.x - _noise.x, rep.p.z - _noise.z).length() < 220.0:
			v = (Vector3(_noise.x, 0, _noise.z) - Vector3(rep.p.x, 0, rep.p.z)).normalized() * 1.6
		elif _rng.randf() < 0.2:
			var a := _rng.randf() * TAU
			v = Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.0, 0.7)
		rep.v = v
		var next: Vector3 = rep.p + v * dt
		var info := city.column_info(int(next.x), int(next.z))
		if info.kind in ["building", "sea", "void"]:
			rep.v = -v
			continue
		next.y = city.surface_y(int(next.x), int(next.z))
		rep.p = next


func _promote(player: Vector3, ctx: Dictionary) -> void:
	var full := 0
	for z: Zombie in manager.zombies:
		if is_instance_valid(z) and z.has_meta("pop_cell"):
			full += 1
	if full >= NEAR_MAX:
		return
	var eye: Vector3 = ctx.get("player_eye", player + Vector3(0, 1.6, 0))
	var look: Vector3 = ctx.get("player_look", Vector3.FORWARD)
	for rep: Dictionary in reps.duplicate():
		if full >= NEAR_MAX:
			break
		var d := Vector2(rep.p.x - player.x, rep.p.z - player.z).length()
		if d > NEAR_R or d < MIN_PROMOTE:
			continue
		var cell := VoxelWorld.cell_of(rep.p)
		if not manager.world.has_chunk(VoxelWorld.chunk_of(cell)):
			continue
		var column: Array = manager.nav.column(cell.x, cell.z)
		if column[0] == NavGrid.NONE or column[1]:
			continue
		var at := Vector3(cell.x + 0.5, column[0], cell.z + 0.5)
		var to := at + Vector3(0, 1.0, 0) - eye
		if to.normalized().dot(look) > 0.35 and VoxelRay.line_clear(manager.world, eye, at + Vector3(0, 1.0, 0)):
			continue            # goz onunde belirmez
		var z := manager.spawn(rep.def, at)
		z.health = float(rep.hp)
		z.set_meta("pop_cell", int(rep.cell))
		reps.erase(rep)
		promoted_total += 1
		full += 1


func _demote(player: Vector3) -> void:
	for z: Zombie in manager.zombies.duplicate():
		if not is_instance_valid(z) or not z.has_meta("pop_cell") or z.state == Zombie.State.DEAD:
			continue
		if z.global_position.distance_to(player) < DESPAWN_R or z.state in [Zombie.State.CHASE, Zombie.State.ATTACK]:
			continue
		reps.append({"p": z.global_position, "def": z.def, "cell": int(z.get_meta("pop_cell")), "hp": z.health,
			"v": Vector3.ZERO})
		manager.actors.remove(z)
		manager.zombies.erase(z)
		z.queue_free()
		demoted_total += 1


func _on_killed(z: Zombie) -> void:
	## Olum hucreden duser (kalici). Nufus disi (dalga) zombisi de oldugu
	## hucrenin nufusundan bir dusurur: bolge temizligi emegi korunur.
	var i := int(z.get_meta("pop_cell")) if z.has_meta("pop_cell") else cell_of(z.global_position)
	if i < 0 or i >= budget.size():
		return
	killed[i] = minf(budget[i], killed[i] + 1.0)
	if z.has_meta("pop_cell"):
		out[i] = maxi(0, out[i] - 1)


func _draw(player: Vector3) -> void:
	## Orta mesafe temsilleri: yakin cemberdekiler (tam AI'ya donusecekler)
	## cizilmez; digerleri tek MultiMesh.
	var mm := _mm.multimesh
	var k := 0
	for rep: Dictionary in reps:
		if k >= MID_MAX:
			break
		var p: Vector3 = rep.p
		if Vector2(p.x - player.x, p.z - player.z).length() < NEAR_R * 0.8:
			continue
		var tr := Transform3D(Basis(), p + Vector3(0, 0.9, 0))
		mm.set_instance_transform(k, tr)
		var shade := 0.22 + 0.1 * float(abs(hash(rep.def.id)) % 5) / 5.0
		mm.set_instance_color(k, Color(shade * 0.9, shade, shade * 0.85))
		k += 1
	mm.visible_instance_count = k


func on_new_day() -> void:
	## Yavas geri dolma: oyuncunun 300 m cevresindeki temizlenmis hucreler dolmaz.
	for i in killed.size():
		if killed[i] > 0.0:
			killed[i] = maxf(0.0, killed[i] - budget[i] * REGROW_PER_DAY)


func near_counts(player: Vector3) -> Dictionary:
	var full := 0
	for z: Zombie in manager.zombies:
		if is_instance_valid(z) and z.has_meta("pop_cell"):
			full += 1
	var remaining := 0.0
	for i in budget.size():
		remaining += alive(i)
	return {"full": full, "reps": reps.size(), "regional": int(remaining), "budget": int(total_budget),
		"density": int(density_at(player))}


func to_dict() -> Dictionary:
	var k := {}
	for i in killed.size():
		if killed[i] > 0.0:
			k[str(i)] = snappedf(killed[i], 0.01)
	return {"killed": k, "n": n}


func load_dict(data: Dictionary) -> void:
	if int(data.get("n", n)) != n:
		return
	var k: Dictionary = data.get("killed", {})
	for key: String in k:
		var i := int(key)
		if i >= 0 and i < killed.size():
			killed[i] = minf(budget[i], float(k[key]))


func adopt_loaded(zombies: Array) -> void:
	## Kayittan gelen tam AI zombileri hucrelerinin cikis sayisina yazilir
	## (yuklemede ayni nufus iki kez dogmasin).
	for z: Zombie in zombies:
		if is_instance_valid(z) and z.has_meta("pop_cell"):
			out[int(z.get_meta("pop_cell"))] += 1
