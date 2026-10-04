class_name SurvivorManager
extends Node3D
## Hayatta kalanlar: kurtarma -> izleme -> usse katilma; sakin bedenleri.
##
## KURTARMA AKISI (belgede korunmasi istenen hedef; eski oyunda sakinler
## yalnizca bir listeden secilerek alinabiliyordu):
##   1. Henuz katilmamis her profil sehirde SABIT bir noktada bekler
##      (tohumdan secilir; kayitta degismez).
##   2. Telsiz tasiyan oyuncu en yakin sinyalin yonunu ve uzakligini gorur.
##   3. [E] ile ikna edilen kisi oyuncuyu izler; zombiler ona da saldirir.
##   4. Yatak kapasitesi olan kapali bir usse girince KOLONIYE KATILIR.

signal message(text: String, color: Color)

var world: VoxelWorld
var actors: ActorRegistry
var bases: BaseSystem
var hitscan: Hitscan
var effects: Effects
var sfx: Sfx
var registry: BuildingRegistry
var noise_callback: Callable
var nodes: Dictionary = {}          # profil -> Survivor
var rescued: Dictionary = {}        # kurtarilmis ya da olmus profiller (tekrar dogmaz)
var _out_of_ammo_warned := {}


func setup(p_world: VoxelWorld, p_actors: ActorRegistry, p_bases: BaseSystem, p_hitscan: Hitscan,
		p_effects: Effects, p_sfx: Sfx, p_registry: BuildingRegistry) -> void:
	world = p_world
	actors = p_actors
	bases = p_bases
	hitscan = p_hitscan
	effects = p_effects
	sfx = p_sfx
	registry = p_registry


func colony() -> Colony:
	return bases.colony


func base_of(profile_id: String) -> Settlement:
	var r: Dictionary = colony().residents.get(profile_id, {})
	return colony().base_by_id(r.get("settlement_id", ""))


var overrides: Dictionary = {}       # profil -> Vector3 (gorev: sabit kurtarma noktasi)


func waiting_point(profile_id: String) -> Vector3:
	## Profilin sehirdeki bekleme noktasi: tohumlu, bir bina kenarinda. Gorev
	## sistemi bir profili belirli bir yere (ornegin ilk kurtarma: dogusa
	## yakin) sabitleyebilir. Nokta her zaman OYNANABILIR koridordadir.
	if overrides.has(profile_id):
		return overrides[profile_id]
	if registry == null or registry.count() == 0:
		return Vector3.INF
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("survivor:" + profile_id)
	var generator := registry.generator
	for _attempt in 60:
		var index := rng.randi() % registry.count()
		var b := registry.get_building(index)
		var c: Vector2 = b.centroid
		# Binanin disindaki en yakin yurunebilir hucre.
		for r in range(2, 30):
			var angle := rng.randf() * TAU
			var x := floori(c.x + cos(angle) * r)
			var z := floori(c.y + sin(angle) * r)
			var info := generator.column_info(x, z)
			if info.kind in ["sidewalk", "plaza", "ground", "park"] and world.is_open_column(x, z):
				var y := generator.ground_height(x, z)
				return Vector3(x + 0.5, y, z + 0.5)
	return Vector3.INF


func sync(player_position: Vector3) -> void:
	## Bekleyenleri ve sakinleri dunyada gorunur tutar.
	for profile_id: String in Content.colony.profiles:
		var resident: Dictionary = colony().residents.get(profile_id, {})
		var node: Survivor = nodes.get(profile_id)
		if not resident.is_empty():
			if resident.health <= 0:
				continue
			var base := base_of(profile_id)
			if base == null or resident.status == "colony.expedition":
				_despawn(profile_id)
				continue
			if node == null or not is_instance_valid(node):
				var p := base.centre()
				node = _spawn(profile_id, p + Vector3(randf_range(-2, 2), 0.2, randf_range(-2, 2)), Survivor.Mode.RESIDENT)
			elif node.mode != Survivor.Mode.RESIDENT:
				node.set_mode(Survivor.Mode.RESIDENT)
			continue
		if rescued.has(profile_id):
			continue
		if node != null and is_instance_valid(node):
			continue
		var point := waiting_point(profile_id)
		if point == Vector3.INF:
			continue
		# Yalnizca yakindaysa ve chunk yukluyse gorunur yap.
		if point.distance_to(player_position) < 90.0 and world.has_chunk(VoxelWorld.chunk_of(VoxelWorld.cell_of(point))):
			_spawn(profile_id, point + Vector3(0, 0.1, 0), Survivor.Mode.WAITING)


func _spawn(profile_id: String, position: Vector3, mode: int) -> Survivor:
	var node := Survivor.new()
	node.setup(profile_id, self, mode)
	add_child(node)
	node.global_position = position
	nodes[profile_id] = node
	actors.add(node)
	return node


func _despawn(profile_id: String) -> void:
	var node: Survivor = nodes.get(profile_id)
	if node != null and is_instance_valid(node):
		actors.remove(node)
		node.queue_free()
	nodes.erase(profile_id)


func physics_step(delta: float, ctx: Dictionary) -> void:
	for profile_id: String in nodes.keys():
		var node: Survivor = nodes[profile_id]
		if not is_instance_valid(node):
			nodes.erase(profile_id)
			continue
		if not world.has_chunk(VoxelWorld.chunk_of(VoxelWorld.cell_of(node.global_position))):
			continue
		node.think(delta, ctx)
		if node.mode == Survivor.Mode.FOLLOW:
			_try_join(node)


func _process(delta: float) -> void:
	for node: Survivor in nodes.values():
		if is_instance_valid(node):
			node.animate(delta)


func living_colonists() -> Array:
	## Zombilerin hedefleyebilecegi NPC'ler.
	var list: Array = []
	for node: Survivor in nodes.values():
		if is_instance_valid(node) and node.mode != Survivor.Mode.DEAD:
			list.append(node)
	return list


func nearest_waiting(position: Vector3, radius: float) -> Survivor:
	var best: Survivor = null
	var best_d := radius
	for node: Survivor in nodes.values():
		if is_instance_valid(node) and node.mode == Survivor.Mode.WAITING:
			var d := node.global_position.distance_to(position)
			if d < best_d:
				best = node
				best_d = d
	return best


func persuade(node: Survivor) -> void:
	node.set_mode(Survivor.Mode.FOLLOW)
	var name: String = Content.colony.profiles[node.profile_id].name
	message.emit("%s seni izliyor -- onu kapali bir usse goturmelisin." % name, Hud.ACCENT)


func _try_join(node: Survivor) -> void:
	var base := bases.settlement_at(node.global_position)
	if base == null:
		return
	var result := colony().recruit(base, node.profile_id)
	var name: String = Content.colony.profiles[node.profile_id].name
	match result:
		"colony.recruited":
			rescued[node.profile_id] = true
			node.set_mode(Survivor.Mode.RESIDENT)
			message.emit("%s %s'e katildi! (Koloni: L)" % [name, base.name], Hud.GREEN)
		"colony.no_beds":
			if not node.has_meta("warned_beds"):
				node.set_meta("warned_beds", true)
				message.emit("%s icin yatak yok -- bir binaya Yatakhane rolu ver (L)." % name, Hud.RED)
		"colony.unsafe":
			if not node.has_meta("warned_unsafe"):
				node.set_meta("warned_unsafe", true)
				message.emit("Us acik (delik var); %s katilmaya cekiniyor." % name, Hud.RED)


func radio_signal(position: Vector3) -> Dictionary:
	## Telsiz: en yakin bekleyen kisinin yonu ve uzakligi.
	var best := {}
	var best_d := INF
	for profile_id: String in Content.colony.profiles:
		if colony().residents.has(profile_id) or rescued.has(profile_id):
			continue
		var point := waiting_point(profile_id)
		if point == Vector3.INF:
			continue
		var d := point.distance_to(position)
		if d < best_d:
			best_d = d
			best = {"profile": profile_id, "position": point, "distance": d}
	return best


func waiting_count() -> int:
	var n := 0
	for profile_id: String in Content.colony.profiles:
		if not colony().residents.has(profile_id) and not rescued.has(profile_id):
			n += 1
	return n


func waiting_points() -> Array:
	## Haritada gosterim (Telsiz agi becerisi / ag acik): [{profile, name, position}]
	var list: Array = []
	for profile_id: String in Content.colony.profiles:
		if colony().residents.has(profile_id) or rescued.has(profile_id):
			continue
		var p := waiting_point(profile_id)
		if p != Vector3.INF:
			list.append({"profile": profile_id, "name": Content.colony.profiles[profile_id].name, "position": p})
	return list


func random_point_in_base(profile_id: String, current: Vector3) -> Vector3:
	var base := base_of(profile_id)
	if base == null or base.interior.is_empty():
		return current
	var cells := base.interior.keys()
	var cell: Vector2i = cells[randi() % cells.size()]
	return Vector3(cell.x + 0.5, float(base.interior[cell]), cell.y + 0.5)


func guard_fire(node: Survivor, eye: Vector3, direction: Vector3, damage: float, noise_radius: float) -> void:
	var result := hitscan.fire(eye, direction, eye, 60.0, damage, "physical", 0, "survivor", node, false)
	if effects != null:
		effects.tracer(eye + direction * 0.5, result.end)
		effects.muzzle_flash(eye + direction * 0.5, 0.6)
	if sfx != null:
		sfx.play_at("shot_pistol", eye, -3.0)
	if noise_callback.is_valid():
		noise_callback.call(eye, noise_radius)


func guard_out_of_ammo(profile_id: String) -> void:
	if _out_of_ammo_warned.get(profile_id, false):
		return
	_out_of_ammo_warned[profile_id] = true
	var name: String = Content.colony.profiles[profile_id].name
	message.emit("%s: cephane bitti! Depoya %s koy." % [name, Content.item(Content.colony.settings.guard_ammo).name], Hud.RED)


func on_survivor_died(node: Survivor) -> void:
	var name: String = Content.colony.profiles.get(node.profile_id, {}).get("name", node.profile_id)
	message.emit("%s oldu." % name, Hud.RED)
	rescued[node.profile_id] = true
	actors.remove(node)
	var r: Dictionary = colony().residents.get(node.profile_id, {})
	if not r.is_empty():
		r.status = "colony.dead"


func to_dict() -> Dictionary:
	var following: Array = []
	for node: Survivor in nodes.values():
		if is_instance_valid(node) and node.mode == Survivor.Mode.FOLLOW:
			following.append(node.profile_id)
	return {"rescued": rescued.keys(), "following": following}


func load_dict(data: Dictionary) -> void:
	for profile_id: String in nodes.keys():
		_despawn(profile_id)
	rescued.clear()
	for profile_id: Variant in data.get("rescued", []):
		rescued[str(profile_id)] = true
