class_name ZombieManager
extends Node3D
## Zombi nufusu: dusunme dongusu, ses dagitimi, uyku, dogus yonetimi.
## (Python: systems/ai.py ZombieAISystem + world/director.py HordeDirector)
##
## UC PERFORMANS KARARI (eski oyundan aynen):
##   1. Akis alani (NavGrid): ajan basina A* yok.
##   2. Uyku: uzaktaki zombi dusunmez ve hareket etmez.
##   3. Gorus hatti seyreltilir: zombi basina ~5 adimda bir.
##
## YONETICI (director): sabit dogus noktasi yok. Gurultu "isisi" nufusu ve
## ozel tip oranini artirir; gece nufus iki katina cikar; dogus daima
## oyuncunun GORUS HATTI DISINDA olur -- hicbir zombi goz onunde belirmez.

signal zombie_killed(zombie: Zombie)
signal player_struck(zombie: Zombie, amount: float, direction: Vector3)
signal npc_struck(zombie: Zombie, npc: Object, amount: float)
signal block_attacked(cell: Vector3i, destroyed: bool)
signal noise_made(position: Vector3, radius: float)

const ACTIVE_RADIUS := 80.0
const MIN_SPAWN := 38.0
const MAX_SPAWN := 72.0
const BASE_POPULATION := 26
const MAX_POPULATION := 150
const WAVE_POPULATION_CAP := 400
const SPAWN_INTERVAL := 2.4
const HEAT_DECAY := 0.14
const HEAT_PER_NOISE := 0.22
const MAX_CORPSES := 40
const NAV_BUDGET_USEC := 1800

var world: VoxelWorld
var nav: NavGrid
var actors: ActorRegistry
var sfx: Sfx
var effects: Effects
var ground_height: Callable        # (x, z) -> int
# (x, z) -> bool: sutun bir bina ayak izinde mi? Ic mekanlar gezilebilir
# oldugu icin zemin kat da "zemin" gorunur; oyuncu dolap ararken kapali
# odada birden zombi dogmasin diye bina icinde DOGMA yapilmaz (disaridan
# acik kapi / kirik duvardan girerler).
var indoor_column: Callable
var spawn_table: Array = []        # [[ZombieDef, agirlik]]
var region_table: Array = []
var zombies: Array = []
var corpses: Array = []
var heat := 0.0
var night_multiplier := 1.0
var wave_target := 0
var wave_focus := Vector3.INF
var enabled := true
var spawned_total := 0
var kills := 0
var awake_count := 0
var tick := 0
var context := {}
var _spawn_timer := 0.0
var _pending_noise: Array = []
var _rng := RandomNumberGenerator.new()
var _seed_counter := 1


func setup(p_world: VoxelWorld, p_nav: NavGrid, p_actors: ActorRegistry, p_sfx: Sfx,
		p_effects: Effects, p_ground_height: Callable) -> void:
	world = p_world
	nav = p_nav
	actors = p_actors
	sfx = p_sfx
	effects = p_effects
	ground_height = p_ground_height
	spawn_table = Content.zombie_spawn_table()
	_rng.seed = 777


# --- ses ---
func emit_noise(position: Vector3, radius: float) -> void:
	## Tum gurultuler (silah, arama, bagiran) tek yoldan gelir.
	_pending_noise.append([position, radius])
	heat = minf(1.0, heat + HEAT_PER_NOISE * (radius / Units.perception_m(400.0)))
	noise_made.emit(position, radius)


func _dispatch_noise() -> void:
	# Kuyruk: olay dongunun ortasinda gelebilir; adim basinda toplu islenir.
	for event: Array in _pending_noise:
		# Aktor listesinde NPC'ler de var: tip ancak kontrolden sonra daraltilir.
		for actor: Node3D in actors.near(event[0], event[1] + 1.0):
			if actor is Zombie and (actor as Zombie).awake:
				(actor as Zombie).hear(event[0], event[1])
	_pending_noise.clear()


# --- ana dongu ---
func physics_step(delta: float, ctx: Dictionary) -> void:
	tick += 1
	ctx["tick"] = tick
	ctx["nav"] = nav
	context = ctx
	heat = maxf(0.0, heat - HEAT_DECAY * delta)
	_update_nav(ctx.player_position)
	_dispatch_noise()
	var player_position: Vector3 = ctx.player_position
	awake_count = 0
	for zombie: Zombie in zombies:
		if not is_instance_valid(zombie) or zombie.state == Zombie.State.DEAD:
			continue
		var distance := zombie.global_position.distance_to(player_position)
		var in_wave := wave_target > 0 and wave_focus != Vector3.INF \
			and zombie.global_position.distance_to(wave_focus) < WaveSchedule.SIEGE_SPAWN_RADIUS_M * 1.3
		zombie.awake = distance <= ACTIVE_RADIUS or in_wave
		# Yuklenmemis chunk'ta uyanan zombi dusmesin: veri yoksa bekle.
		if zombie.awake and not world.has_chunk(VoxelWorld.chunk_of(VoxelWorld.cell_of(zombie.global_position))):
			zombie.awake = false
		if not zombie.awake:
			continue
		awake_count += 1
		zombie.think(delta, ctx)
	_director(delta, player_position, ctx)
	_update_corpses(delta)


func _process(delta: float) -> void:
	for zombie: Zombie in zombies:
		if is_instance_valid(zombie) and zombie.awake:
			zombie.animate(delta)
	for corpse: Zombie in corpses:
		if is_instance_valid(corpse):
			corpse.animate(delta)


func _update_nav(player_position: Vector3) -> void:
	var cell := Vector2i(floori(player_position.x), floori(player_position.z))
	if not nav.building():
		# Hedef bir kac hucre kaydiysa ya da alan eskidiyse yeniden baslat.
		if nav.ready_target.distance_to(cell) >= 1.0 or tick % 30 == 0:
			nav.begin(cell)
	nav.step(NAV_BUDGET_USEC)


# --- carpisma yardimcilari ---
func separation(zombie: Zombie) -> Vector3:
	var push := Vector3.ZERO
	for other: Node3D in actors.near(zombie.global_position, 1.2):
		if other == zombie or not other.is_alive():
			continue
		var offset := zombie.global_position - other.global_position
		offset.y = 0.0
		var d := offset.length()
		if d > 0.001 and d < 0.9:
			push += offset / d * (0.9 - d) * 3.0
	return push


# --- saldiri sonuclari ---
func zombie_strikes(zombie: Zombie, victim: Object, direction: Vector3) -> void:
	play_sound("zombie_attack", zombie.global_position, -2.0)
	if victim != null and victim.has_method("faction") and victim.faction() == "player":
		player_struck.emit(zombie, zombie.def.damage, direction)
	elif victim != null:
		npc_struck.emit(zombie, victim, zombie.def.damage)


func zombie_hits_block(zombie: Zombie, cell: Vector3i, amount: float) -> void:
	var value := world.get_cell(cell)
	if value == 0 or value == VoxelWorld.BOUNDARY or not world.placed.has(cell):
		return
	var result := world.apply_damage(cell, amount)
	if effects != null:
		effects.impact(Vector3(cell) + Vector3(0.5, 0.5, 0.5), Vector3.UP, world.materials.colors[value], result.destroyed)
	play_sound("impact_wood" if not result.destroyed else "break_block", Vector3(cell), -3.0)
	block_attacked.emit(cell, result.destroyed)
	if result.destroyed:
		zombie.state = Zombie.State.CHASE


func on_zombie_died(zombie: Zombie) -> void:
	kills += 1
	actors.remove(zombie)
	zombies.erase(zombie)
	corpses.append(zombie)
	play_sound("zombie_death", zombie.global_position, -2.0)
	while corpses.size() > MAX_CORPSES:
		var oldest: Zombie = corpses.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	zombie_killed.emit(zombie)


func _update_corpses(delta: float) -> void:
	for corpse: Zombie in corpses.duplicate():
		if not is_instance_valid(corpse):
			corpses.erase(corpse)
			continue
		corpse.corpse_timer -= delta
		if corpse.corpse_timer <= 0.0:
			corpses.erase(corpse)
			corpse.queue_free()


func nearest_corpse(position: Vector3, radius: float) -> Zombie:
	var best: Zombie = null
	var best_d := radius
	for corpse: Zombie in corpses:
		if is_instance_valid(corpse) and not corpse.looted:
			var d := corpse.global_position.distance_to(position)
			if d < best_d:
				best = corpse
				best_d = d
	return best


func play_sound(id: String, position: Vector3, volume: float) -> void:
	if sfx != null:
		sfx.play_at(id, position, volume)


# --- yonetici (director) ---
func target_population() -> int:
	var base := BASE_POPULATION + (MAX_POPULATION - BASE_POPULATION) * heat
	var target := int(base * night_multiplier)
	if wave_target > 0:
		target = maxi(target, wave_target)
	return mini(WAVE_POPULATION_CAP if wave_target > 0 else MAX_POPULATION, target)


func _director(delta: float, player_position: Vector3, ctx: Dictionary) -> void:
	# Kalici nufus (Population) varsa yonetici yalnizca DALGA dogurur.
	if not enabled and wave_target <= 0:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = SPAWN_INTERVAL
	var deficit := target_population() - zombies.size()
	if deficit <= 0:
		return
	var batch := mini(deficit, 1 + int(heat * 5.0) + (4 if wave_target > 0 else 0))
	for _i in batch:
		var point := _find_spawn_point(player_position, ctx)
		if point == Vector3.INF:
			break
		spawn(_pick_definition(), point)


func seed_population(player_position: Vector3, count: int, ctx: Dictionary) -> int:
	## Sehir bastan yasamali (yani olmeli): ilk nufus aninda yerlestirilir.
	var spawned := 0
	for _i in count:
		var point := _find_spawn_point(player_position, ctx)
		if point == Vector3.INF:
			continue
		spawn(_pick_definition(), point)
		spawned += 1
	return spawned


func spawn(definition: ZombieDef, position: Vector3) -> Zombie:
	var zombie := Zombie.new()
	zombie.setup(definition, self, _seed_counter)
	_seed_counter += 1
	add_child(zombie)
	zombie.global_position = position
	zombie.facing = Vector3(cos(_rng.randf() * TAU), 0, sin(_rng.randf() * TAU)).normalized()
	zombies.append(zombie)
	actors.add(zombie)
	spawned_total += 1
	return zombie


func _pick_definition() -> ZombieDef:
	## Isi arttikca ozel tipler daha olasi: gurultu yapan oyuncu yalnizca
	## daha COK degil daha ZOR dusman ceker.
	var table := region_table if not region_table.is_empty() else spawn_table
	var weights: Array = []
	var total := 0.0
	for entry: Array in table:
		var weight: float = entry[1]
		if entry[0].id != "walker":
			weight *= 0.35 + 1.6 * heat
		weights.append(weight)
		total += weight
	var roll := _rng.randf_range(0.0, total)
	for i in table.size():
		roll -= weights[i]
		if roll <= 0.0:
			return table[i][0]
	return table[0][0]


func _find_spawn_point(player_position: Vector3, ctx: Dictionary) -> Vector3:
	var center := player_position
	var minimum := MIN_SPAWN
	var maximum := MAX_SPAWN
	var require_hidden := true
	if wave_target > 0 and wave_focus != Vector3.INF:
		# Dalga USSUN cevresinde dogar: oyuncu kacsa da dalga usse yurur.
		center = wave_focus
		minimum = WaveSchedule.SIEGE_SPAWN_RADIUS_M * 0.55
		maximum = WaveSchedule.SIEGE_SPAWN_RADIUS_M
		require_hidden = false
	var eye: Vector3 = ctx.get("player_eye", player_position + Vector3(0, 1.6, 0))
	var look: Vector3 = ctx.get("player_look", Vector3.FORWARD)
	for _attempt in 24:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(minimum, maximum)
		var x := floori(center.x + cos(angle) * distance)
		var z := floori(center.z + sin(angle) * distance)
		if not world.in_bounds(Vector3i(x, 0, z)):
			continue
		if not world.has_chunk(VoxelWorld.chunk_of(Vector3i(x, 0, z))):
			continue
		if indoor_column.is_valid() and indoor_column.call(x, z):
			continue
		var info := nav.column(x, z)
		if info[0] == NavGrid.NONE or info[1]:
			continue
		var position := Vector3(x + 0.5, info[0], z + 0.5)
		if world.get_block(x, info[0] - 1, z) != 0 and world.materials.liquid[world.get_block(x, info[0] - 1, z)] == 1:
			continue
		if require_hidden:
			# Gorus hatti: oyuncunun baktigi ve gordugu bir yerde dogurma.
			var to := position + Vector3(0, 1.0, 0) - eye
			var in_front := to.normalized().dot(look) > 0.35
			if in_front and VoxelRay.line_clear(world, eye, position + Vector3(0, 1.0, 0)):
				continue
		return position
	return Vector3.INF


# --- kalicilik ---
func to_dict() -> Dictionary:
	var list: Array = []
	for zombie: Zombie in zombies:
		if is_instance_valid(zombie) and zombie.state != Zombie.State.DEAD:
			var e := {"id": zombie.def.id, "p": [zombie.global_position.x, zombie.global_position.y,
				zombie.global_position.z], "hp": zombie.health}
			if zombie.has_meta("pop_cell"):
				e["cell"] = int(zombie.get_meta("pop_cell"))
			list.append(e)
	return {"zombies": list, "heat": heat, "kills": kills}


func load_dict(data: Dictionary) -> void:
	clear()
	heat = clampf(float(data.get("heat", 0.0)), 0.0, 1.0)
	kills = int(data.get("kills", 0))
	for entry: Variant in data.get("zombies", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var definition: ZombieDef = Content.zombies.get(entry.get("id", ""))
		if definition == null:
			continue
		var p: Array = entry.get("p", [0, 0, 0])
		var zombie := spawn(definition, Vector3(p[0], p[1], p[2]))
		zombie.health = clampf(float(entry.get("hp", definition.health)), 1.0, definition.health)
		if entry.has("cell"):
			zombie.set_meta("pop_cell", int(entry.cell))


func clear() -> void:
	for zombie: Zombie in zombies + corpses:
		if is_instance_valid(zombie):
			actors.remove(zombie)
			zombie.queue_free()
	zombies.clear()
	corpses.clear()
