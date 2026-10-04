class_name Vehicles
extends Node3D
## Araclar: kolay surus, binme/inme, yakit, basit onarim, bagaj, kayit.
## (Eski oyunda yalnizca veri + usler arasi hizli gecis vardi; surus yoktu.)
##
## KURALLAR
##   * Arac BLOK KIRMAZ: duvara carpinca durur ve kendisi hasar alir. Arac
##     carpmasi oyuncu icin alternatif blok kazma yontemi degildir.
##   * Inis noktasi GUVENLI olmali: iki yan, arka ve on denenir; su, duvar
##     ya da bosluk icine inilmez. Uygun nokta yoksa inilmez ve soylenir.
##   * Yakit, cantadaki `chemical_fuel` etiketli GERCEK esyalardan doldurulur
##     (kaynak sistemiyle ayni birim: supply_value).
##   * Surus gurultu yapar (travel.json `noise_radius`).

signal message(text: String, color: Color)

const TANK := 40.0
var fuel_multiplier := 1.0       # beceri: Arac lojistigi (x0.75)
var repair_share := 0.3           # beceri: Saha onarimi (0.5)
const SAFE_EXIT_SPEED := 2.0  # m/sn: bundan hizliyken inilmez
const MODEL_TO_DEF := {"sedan": "sedan", "taxi": "sedan", "police_car": "sedan",
	"van": "pickup", "ambulance": "pickup", "minibus": "minibus"}
const MAX_PARKED := 14
# Arac basamagi: yarim blok (kaldirim bordur farki 0.5 m). Tek bloklik duvar,
# kum torbasi ya da barikat ASILMAZ (bordur toleransi tirmanma yetenegine
# donusmesin). Egim, taban sutun sutun orneklendigi icin takilmadan cikilir.
const STEP := 0.55

var world: VoxelWorld
var actors: ActorRegistry
var entries: Array = []       # [{id, def_id, model_id, node, position, yaw, speed, fuel, durability, trunk}]
var driving: Dictionary = {}
var _next_id := 1
var _noise_timer := 0.0
var _unloaded_warning := 0.0


func setup(p_world: VoxelWorld, p_actors: ActorRegistry) -> void:
	world = p_world
	actors = p_actors


static func def_of(entry: Dictionary) -> Dictionary:
	return Content.travel.get("vehicles", {}).get(entry.def_id, {})


func spawn_parked(city: CityGenerator) -> void:
	## Sokaklara park etmis araclar: tohumlu, her oyunda ayni yerde.
	##   Kucuk harita (v1): sokaklara serpilir.
	##   Koridor (v2, 10 km): 14 arac rastgele dagilsa dogus cevresinde hic
	##   arac olmazdi. Dogus cevresine bir kume, koridora serpilmis araclar ve
	##   koprude terk edilmis bir arac sirasi konur.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(city.map_id + ":araclar")
	if city.format < 2:
		_spawn_on_roads(city, rng, MAX_PARKED, Vector2.ZERO, 0.0)
		return
	var spawn := city.spawn_point()
	_spawn_on_roads(city, rng, MAX_PARKED, Vector2(spawn.x, spawn.z), 450.0)
	_spawn_on_roads(city, rng, MAX_PARKED * 2, Vector2.ZERO, 0.0)
	_spawn_bridge_wrecks(city, rng)


func _spawn_on_roads(city: CityGenerator, rng: RandomNumberGenerator, count: int,
		center: Vector2, radius: float) -> void:
	var candidates := PackedInt32Array()
	for index in city.roads.size():
		var road: Dictionary = city.roads[index]
		if not road.type in ["residential", "secondary", "tertiary", "primary", "unclassified"]:
			continue
		var a: Vector2 = road.a
		if radius > 0.0 and a.distance_to(center) > radius:
			continue
		candidates.append(index)
	if candidates.is_empty():
		return
	var models := MODEL_TO_DEF.keys()
	var placed := 0
	var tries := 0
	while placed < count and tries < 4000:
		tries += 1
		var road: Dictionary = city.roads[candidates[rng.randi() % candidates.size()]]
		var t := rng.randf()
		var along: Vector2 = road.b - road.a
		if along.length() < 6.0:
			continue
		# Serit ortasi: kaldirim kenarina (bordur, agac govdesi) sikisik dogan
		# arac hareket edemiyordu. Terk edilmis arac yolun ortasinda da durur.
		var side := Vector2(-along.y, along.x).normalized() * (float(road.half) * 0.45)
		var p: Vector2 = road.a + along * t + side
		var x := floori(p.x)
		var z := floori(p.y)
		if world != null and not world.is_open_column(x, z):
			continue          # manzara seridine (girilemez) arac konmaz
		var info := city.column_info(x, z)
		if info.kind != "road" or info.has("bridge"):
			continue
		var position := Vector3(p.x, _footprint_surface(city, x, z) + 0.02, p.y)
		if _near_other(position, 7.0):
			continue
		var model: String = models[rng.randi() % models.size()]
		var entry := _create(MODEL_TO_DEF[model], model, position, atan2(-along.x, -along.y))
		entry.fuel = TANK * (0.0 if rng.randf() < 0.55 else rng.randf_range(0.05, 0.45))
		entry.durability = float(def_of(entry).get("durability", 100)) * rng.randf_range(0.35, 1.0)
		placed += 1


static func _footprint_surface(city: CityGenerator, x: int, z: int) -> float:
	## Govdenin kapladigi sutunlarin EN YUKSEK yuzeyi: tek sutunun yuksekligine
	## konan arac egimde yan sutunlardaki yarim bloga gomulu dogup kilitleniyordu.
	var top := -INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			top = maxf(top, city.surface_y(x + dx, z + dz))
	return top


func _spawn_bridge_wrecks(city: CityGenerator, rng: RandomNumberGenerator) -> void:
	## Kopruden kacis yarida kalmis: yamuk durmus, cogu yakitsiz araclar.
	## Hem siper hem engel; surerek gecmek icin aralarindan dolasmak gerekir.
	var models := MODEL_TO_DEF.keys()
	for b: Dictionary in city.bridges:
		var direction: Vector2 = city.bridge_point(b, b.length * 0.5 + 1.0) - city.bridge_point(b, b.length * 0.5)
		var side := direction.orthogonal().normalized()
		var placed := 0
		for _try in 60:
			if placed >= 10:
				break
			var s := rng.randf_range(b.t1 - 60.0, b.t2 + 60.0)
			var p: Vector2 = city.bridge_point(b, s) + side * rng.randf_range(-(b.half - 3.0), b.half - 3.0)
			var x := floori(p.x)
			var z := floori(p.y)
			if city.column_info(x, z).get("bridge", "") != "deck":
				continue
			var position := Vector3(p.x, _footprint_surface(city, x, z) + 0.02, p.y)
			if _near_other(position, 6.0):
				continue
			var model: String = models[rng.randi() % models.size()]
			var yaw := atan2(-direction.x, -direction.y) + rng.randf_range(-0.6, 0.6) + (PI if rng.randf() < 0.3 else 0.0)
			var entry := _create(MODEL_TO_DEF[model], model, position, yaw)
			entry.fuel = TANK * (0.0 if rng.randf() < 0.75 else rng.randf_range(0.05, 0.3))
			entry.durability = float(def_of(entry).get("durability", 100)) * rng.randf_range(0.2, 0.7)
			placed += 1


func _near_other(position: Vector3, radius: float) -> bool:
	for entry: Dictionary in entries:
		if entry.position.distance_to(position) < radius:
			return true
	return false


func _create(def_id: String, model_id: String, position: Vector3, yaw: float) -> Dictionary:
	var def: Dictionary = Content.travel.get("vehicles", {}).get(def_id, {})
	# Carpisma olculeri MODELDEN (manifest dimensions_m): sedan 2.0 x 4.1 m,
	# minibus 2.35 x 5.2 m. Eskiden hepsi 2.1 m'lik kareydi.
	var dims: Array = AssetLibrary.entry(model_id).get("dimensions_m", [2.0, 1.5, 4.2])
	var entry := {"id": _next_id, "def_id": def_id, "model_id": model_id, "position": position,
		"yaw": yaw, "speed": 0.0, "fuel": 0.0, "durability": float(def.get("durability", 100)),
		"trunk": Inventory.new(float(def.get("capacity_kg", 120)), 40), "node": null, "vy": 0.0,
		"half_w": float(dims[0]) * 0.5 - 0.05, "half_l": float(dims[2]) * 0.5 - 0.05,
		"height": clampf(float(dims[1]), 1.3, 2.4), "steer": 0.0, "rig": null, "cabin": null,
		"parts": {}, "salvaged": false, "headlight": null}
	_next_id += 1
	var node := AssetLibrary.instantiate(model_id)
	add_child(node)
	entry.node = node
	entries.append(entry)
	_sync_node(entry)
	return entry


func _sync_node(entry: Dictionary) -> void:
	for key: String in ["node", "rig"]:
		var node: Node3D = entry.get(key)
		if node != null and is_instance_valid(node):
			node.position = entry.position
			node.rotation.y = entry.yaw


func nearest(position: Vector3, radius: float = 3.2) -> Dictionary:
	## Arac GOVDESINE (merkeze degil) en yakin arac: minibusun arkasinda da binilir.
	var best := {}
	var best_d := radius
	for entry: Dictionary in entries:
		var d := _distance_to_body(entry, position)
		if d < best_d:
			best = entry
			best_d = d
	return best


func _distance_to_body(entry: Dictionary, position: Vector3) -> float:
	var local: Vector3 = Basis(Vector3.UP, float(entry.yaw)).inverse() * (position - entry.position)
	var dx := maxf(0.0, absf(local.x) - float(entry.half_w))
	var dz := maxf(0.0, absf(local.z) - float(entry.half_l))
	return Vector2(dx, dz).length()


func boxes_near(position: Vector3, radius: float = 8.0) -> Array:
	## Oyuncu ve zombi carpismasi icin park etmis araclarin kutulari.
	var result: Array = []
	for entry: Dictionary in entries:
		if entry == driving:
			continue
		if entry.position.distance_to(position) > radius + 3.0:
			continue
		var p: Vector3 = entry.position
		# Donuk dikdortgenin eksen hizali kapsayan kutusu (yaklasik).
		var fwd := Vector3(-sin(entry.yaw), 0, -cos(entry.yaw))
		var right := Vector3(fwd.z, 0, -fwd.x)
		var extent := (fwd * float(entry.half_l)).abs() + (right * float(entry.half_w)).abs()
		result.append([p - Vector3(extent.x, 0, extent.z), p + Vector3(extent.x, float(entry.height), extent.z)])
	return result


# --- surucu gorunumu ---
func _set_driver_view(entry: Dictionary, on: bool) -> void:
	## Surucu koltugunda eski DOLU model (opak cam, dolu kabin) GIZLENIR; ayni
	## kok donusumunde acik kabuk + kabin kurulur (paket vehicle_compatibility).
	## Iki model ayni anda gorunmez. Cift yoksa eski model kalir (yer tutucu).
	if entry.get("rig") != null and is_instance_valid(entry.rig):
		entry.rig.queue_free()
	entry.rig = null
	entry.cabin = null
	var pair := AssetLibrary.vehicle_pair(str(entry.model_id))
	if on and not pair.is_empty():
		var rig := Node3D.new()
		rig.name = "SurucuKabini"
		var shell := AssetLibrary.instantiate(pair.shell)
		var cabin := AssetLibrary.instantiate(pair.cabin)
		rig.add_child(shell)
		rig.add_child(cabin)
		add_child(rig)
		entry.rig = rig
		entry.cabin = cabin
		entry.node.visible = false
	else:
		entry.node.visible = true
	_sync_node(entry)


func driver_eye_local(entry: Dictionary) -> Vector3:
	## Modele ozel surucu gozu: kabin GLB'sindeki `driver_eye` dugumu. Kabin
	## yoksa test edilmis gecici konum (sol koltuk, tavanin altinda).
	var pair := AssetLibrary.vehicle_pair(str(entry.model_id))
	if not pair.is_empty():
		var marker := AssetLibrary.marker(pair.cabin, "driver_eye")
		if marker != Transform3D():
			return marker.origin
	return Vector3(-0.4, float(entry.height) * 0.72, 0.05)


func cabin_vertical_fov(entry: Dictionary, aspect: float) -> float:
	## Kabin modeli belirli bir YATAY gorus acisina gore tasarlandi (metadata
	## horizontal_fov_degrees, sedan 82). Oyunun genis dikey FOV'u (75) 16:9'da
	## ~106 derece yataya denk gelir ve tavan ekranin ucte birini kaplar.
	## Godot kamerasi dikey FOV aldigi icin en-boy oranina gore cevrilir.
	## Metadata yoksa 0 (oyuncunun ayari gecerli).
	var pair := AssetLibrary.vehicle_pair(str(entry.model_id))
	if pair.is_empty():
		return 0.0
	var horizontal := float(AssetLibrary.metadata(pair.cabin).get("horizontal_fov_degrees", 0.0))
	if horizontal <= 0.0:
		return 0.0
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal) * 0.5) / maxf(0.5, aspect)))


# --- surus ---
func enter(entry: Dictionary) -> String:
	if bool(entry.get("salvaged", false)):
		return "Bu araç sökülmüş: yalnızca hurda"
	if entry.durability <= 0.0:
		return "Arac hurda: once onar (takim cantasi + hurda metal)"
	entry.position = _settle(entry, entry.position)
	driving = entry
	entry.speed = 0.0
	entry.steer = 0.0
	_set_driver_view(entry, true)
	return ""


func seat_transform() -> Transform3D:
	var entry := driving
	var basis := Basis(Vector3.UP, entry.yaw)
	return Transform3D(basis, entry.position + basis * driver_eye_local(entry))


func can_exit() -> String:
	## Hizli giderken inilmez (bos dize = inilebilir).
	if driving.is_empty():
		return ""
	if absf(float(driving.speed)) > SAFE_EXIT_SPEED:
		return "Cok hizli -- once dur (fren: %s)" % Settings.binding_label("jump")
	return ""


func exit_point(player_half: float, player_height: float) -> Vector3:
	## Guvenli inis: once kabin marker'lari (exit_left/right), sonra arka ve on.
	## Su, duvar ya da bosluk icine inilmez; uygun nokta yoksa INF.
	var entry := driving
	var basis := Basis(Vector3.UP, entry.yaw)
	var offsets: Array = []
	var pair := AssetLibrary.vehicle_pair(str(entry.model_id))
	for marker_name: String in ["exit_left", "exit_right"]:
		if not pair.is_empty() and AssetLibrary.has_marker(pair.cabin, marker_name):
			offsets.append(AssetLibrary.marker(pair.cabin, marker_name).origin)
	var hw: float = entry.half_w
	var hl: float = entry.half_l
	offsets.append_array([Vector3(-(hw + 0.6), 0, 0), Vector3(hw + 0.6, 0, 0), Vector3(0, 0, hl + 0.7), Vector3(0, 0, -(hl + 0.7))])
	for offset: Vector3 in offsets:
		var candidate: Vector3 = entry.position + basis * Vector3(offset.x, 0.0, offset.z) + Vector3(0, 0.1, 0)
		if VoxelBody.is_blocked(world, candidate, player_half, player_height):
			continue
		# Altinda zemin olmali (en fazla 1.5 m asagi), sivi olmamali.
		var below := VoxelRay.cast(world, candidate + Vector3(0, 0.2, 0), Vector3.DOWN, 1.8)
		if below.is_empty() or below.boundary:
			continue
		if world.materials.liquid[below.value] == 1:
			continue
		var liquid_here := world.get_block(floori(candidate.x), floori(candidate.y), floori(candidate.z))
		if liquid_here != 0 and liquid_here != VoxelWorld.BOUNDARY and world.materials.liquid[liquid_here] == 1:
			continue
		return below.position + Vector3(0, 0.02, 0)
	return Vector3.INF


func leave() -> void:
	if not driving.is_empty():
		driving.speed = 0.0
		driving.steer = 0.0
		_set_driver_view(driving, false)
	driving = {}


func drive(delta: float, throttle: float, steer: float, brake: bool, on_noise: Callable) -> void:
	## KOLAY SURUS
	##   * Kademeli gaz/fren. W ileri; S ileri giderken FREN, durunca GERI VITES
	##     (acik geri vites: gaz tusuna basili tutmak aniden yon degistirmez).
	##   * Direksiyon yumusak: hedefe 3.5/sn doner, birakinca 5/sn toparlanir.
	##     Donus hiza bagli: dururken donulmez, yuksek hizda dar donus yok.
	##   * Carpisma: yonlendirilmis taban dikdortgeni voxel sutunlarinda
	##     orneklenir, hareket <= 0.25 m alt adimlara bolunur (tunelleme yok).
	##     Basamak toleransi 0.55 m: bordura cikilir, duvara/barikata DEGIL.
	##   * Yuklenmemis chunk: dunya boslugu gibi davranilmaz; arac once
	##     yavaslar, sinira gelince HASARSIZ durur.
	var entry := driving
	if entry.is_empty():
		return
	var def := def_of(entry)
	var top := Units.move_m(float(def.get("speed", 380))) * 0.55 * part_mult(entry, "vehicle_speed")    # sehir ici tavan
	var accel := Units.move_m(float(def.get("acceleration", 220))) * 0.6
	if entry.fuel <= 0.0:
		throttle = 0.0          # yakitsiz: yalnizca yuvarlanir ve frenlenir
	var speed: float = entry.speed
	if brake:
		speed = move_toward(speed, 0.0, accel * 2.6 * delta)
	elif throttle > 0.01:
		if speed < -0.3:
			speed = move_toward(speed, 0.0, accel * 2.2 * delta)      # geri giderken W: once fren
		else:
			speed = minf(top, speed + throttle * accel * delta * (1.0 - 0.5 * clampf(speed / top, 0.0, 1.0)))
	elif throttle < -0.01:
		if speed > 0.3:
			speed = move_toward(speed, 0.0, accel * 2.2 * delta)      # ileri giderken S: fren
		else:
			speed = maxf(-top * 0.35, speed + throttle * accel * 0.6 * delta)
	else:
		speed = move_toward(speed, 0.0, accel * 0.45 * delta)         # motor freni
	# Direksiyon yumusatma ve kendiliginden toparlanma.
	var target := clampf(steer, -1.0, 1.0)
	var rate := 3.5 if absf(target) > 0.05 else 5.0
	entry.steer = move_toward(float(entry.steer), target, rate * delta)
	# Yuklenmemis bolgeye dogru: fren (hasarsiz guvenli durus).
	var forward := Vector3(-sin(entry.yaw), 0, -cos(entry.yaw))
	var probe: Vector3 = entry.position + forward * signf(speed) * (float(entry.half_l) + absf(speed) * 0.9 + 2.0)
	var probe_cell := Vector3i(floori(probe.x), floori(entry.position.y), floori(probe.z))
	if absf(speed) > 0.5 and world.is_open_column(probe_cell.x, probe_cell.z) \
			and not world.has_chunk(VoxelWorld.chunk_of(probe_cell)):
		speed = move_toward(speed, 0.0, accel * 3.0 * delta)
		if _unloaded_warning <= 0.0:
			message.emit("Yol ilerisi yukleniyor -- yavasla", Hud.ACCENT)
			_unloaded_warning = 3.0
	_unloaded_warning -= delta
	var turn_scale := clampf(absf(speed) / 4.0, 0.0, 1.0) / (1.0 + absf(speed) / 14.0)
	var yaw_rate := -float(entry.steer) * 1.5 * turn_scale * signf(speed if absf(speed) > 0.05 else 1.0)
	# Alt adimlar: hizli arac duvarin otesine atlamasin.
	var distance := absf(speed) * delta
	var steps := maxi(1, ceili(distance / 0.25))
	var dt := delta / steps
	var crashed := false
	var moved_total := 0.0
	for _i in steps:
		var new_yaw: float = entry.yaw + yaw_rate * dt
		var fwd := Vector3(-sin(new_yaw), 0, -cos(new_yaw))
		var target_pos: Vector3 = entry.position + fwd * speed * dt
		var result := _try_place(entry, target_pos, new_yaw)
		if result.ok:
			moved_total += Vector2(target_pos.x - entry.position.x, target_pos.z - entry.position.z).length()
			entry.position = Vector3(target_pos.x, result.y, target_pos.z)
			entry.yaw = new_yaw
			continue
		# Kayma: yalnizca x ya da yalnizca z yonunde dene (duvara surtunme).
		var slid := false
		for axis: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
			var part: Vector3 = entry.position + fwd * speed * dt * axis
			var partial := _try_place(entry, part, entry.yaw)
			if partial.ok and part.distance_to(entry.position) > 0.001:
				entry.position = Vector3(part.x, partial.y, part.z)
				slid = true
				break
		if result.get("unloaded", false):
			speed = 0.0              # yuklenmemis chunk: hasarsiz dur
			break
		if not slid:
			crashed = true
			break
		speed *= 0.85
	# Yercekimi: tabanin altinda bosluk varsa duser.
	var ground := _ground_under(entry, entry.position, entry.yaw)
	if ground < entry.position.y - 0.02:
		entry.vy = maxf(-30.0, float(entry.vy) - 22.0 * delta)
		entry.position.y = maxf(ground, entry.position.y + entry.vy * delta)
	else:
		entry.vy = 0.0
		entry.position.y = maxf(entry.position.y, ground)
	if crashed:
		if absf(speed) > 4.0:
			# Duvar DURDURUR ve araci hasarlar; blok kirilmaz.
			entry.durability = maxf(0.0, entry.durability - absf(speed) * 1.5 * (1.0 - clampf(part_sum(entry, "vehicle_armor") / 200.0, 0.0, 0.6)))
			message.emit("Carpisma! Arac hasari: %d" % int(entry.durability), Hud.RED)
			speed = -speed * 0.2
		else:
			speed = 0.0
	entry.speed = speed
	# Yakit: km basina tuketim.
	# GERCEK KM (1:1 harita): moved_total gercek metredir. Katsayi 3.9 = eski
	# 6.0 x 0.65 -- gercek km basina yakit dengesi eskisiyle ayni kalir.
	entry.fuel = maxf(0.0, entry.fuel - moved_total / 1000.0 * float(def.get("fuel_per_km", 1.2)) * 3.9 * fuel_multiplier)
	# Zombilere carpma.
	forward = Vector3(-sin(entry.yaw), 0, -cos(entry.yaw))
	if absf(speed) > 3.0:
		for actor: Node3D in actors.near(entry.position + forward * signf(speed) * float(entry.half_l), 1.6):
			if actor.faction() == "zombie" and actor.is_alive():
				actor.receive_damage(absf(speed) * 6.0 * part_mult(entry, "vehicle_ram"), "physical", forward, actor.global_position, null, "body")
				entry.durability = maxf(0.0, entry.durability - 2.0 / part_mult(entry, "vehicle_ram"))
	_noise_timer -= delta
	if _noise_timer <= 0.0 and absf(speed) > 1.0:
		_noise_timer = 1.0
		on_noise.call(entry.position, Units.perception_m(float(def.get("noise_radius", 520))) * clampf(absf(speed) / top, 0.4, 1.0) * part_mult(entry, "vehicle_noise"))
	_sync_node(entry)
	_animate_cabin(entry, top)


func _footprint(entry: Dictionary, position: Vector3, yaw: float) -> Array:
	## Taban dikdortgeninin ornek noktalari (0.5 m aralik + koseler).
	var points: Array = []
	var basis := Basis(Vector3.UP, yaw)
	var hw: float = entry.half_w
	var hl: float = entry.half_l
	var nx := maxi(1, ceili(hw * 2.0 / 0.5))
	var nz := maxi(1, ceili(hl * 2.0 / 0.5))
	for iz in nz + 1:
		for ix in nx + 1:
			var local := Vector3(-hw + hw * 2.0 * ix / nx, 0, -hl + hl * 2.0 * iz / nz)
			points.append(position + basis * local)
	return points


func _surface_at(x: int, z: int, around_y: float) -> Array:
	## [yuzey y, yuklu mu]: around_y + STEP'e kadar ilk katı hucrenin ustu.
	var top_cell := floori(around_y + STEP + 0.01)
	for y in range(top_cell, floori(around_y) - 4, -1):
		var value := world.get_block(x, y, z)
		if value == VoxelWorld.BOUNDARY:
			# Harita/koridor siniri duvardir; sinir icinde olup chunk'i henuz
			# yuklenmemis hucre ise "bilinmiyor" (bosluk sanilip dusulmez).
			if world.is_open_column(x, z) and world.in_bounds(Vector3i(x, y, z)) \
					and not world.has_chunk(VoxelWorld.chunk_of(Vector3i(x, y, z))):
				return [around_y, false]
			return [float(y + 1), true]
		var h := world.cell_height(value)
		if h > 0.0:
			return [float(y) + h, true]
	return [around_y - 4.0, true]


func _ground_under(entry: Dictionary, position: Vector3, yaw: float) -> float:
	var ground := -INF
	for p: Vector3 in _footprint(entry, position, yaw):
		ground = maxf(ground, _surface_at(floori(p.x), floori(p.z), position.y)[0])
	return ground


func _try_place(entry: Dictionary, position: Vector3, yaw: float) -> Dictionary:
	## Arac bu konuma/yone sigar mi? {ok, y, unloaded}
	var ground := -INF
	for p: Vector3 in _footprint(entry, position, yaw):
		var s: Array = _surface_at(floori(p.x), floori(p.z), entry.position.y)
		if not s[1]:
			return {"ok": false, "unloaded": true}
		ground = maxf(ground, s[0])
	if ground > entry.position.y + STEP:
		return {"ok": false}                   # duvar ya da yuksek basamak
	# Basamak kadar inis yapistirilir (bordurden inerken zipla-dus yok);
	# daha derin bosluga yercekimi indirir.
	var y: float = ground if ground >= entry.position.y - STEP else entry.position.y
	# Govde yuksekliginde engel (sarkan dal, alcak tavan, park etmis arac).
	for p: Vector3 in _footprint(entry, position, yaw):
		for cy in range(floori(y + STEP + 0.05), floori(y + float(entry.height)) + 1):
			var value := world.get_block(floori(p.x), cy, floori(p.z))
			if value != 0 and (value == VoxelWorld.BOUNDARY or world.materials.solid[value] == 1):
				return {"ok": false}
	for other: Dictionary in entries:
		if other == entry or other.position.distance_to(position) > 8.0:
			continue
		if _boxes_overlap(entry, position, yaw, other):
			return {"ok": false}
	return {"ok": true, "y": y}


func _boxes_overlap(a: Dictionary, a_pos: Vector3, a_yaw: float, b: Dictionary) -> bool:
	## Iki yonlendirilmis dikdortgen (ayrik eksen testi, 2B).
	var axes: Array = [Vector2(cos(a_yaw), -sin(a_yaw)), Vector2(sin(a_yaw), cos(a_yaw)),
		Vector2(cos(b.yaw), -sin(b.yaw)), Vector2(sin(b.yaw), cos(b.yaw))]
	var ca := Vector2(a_pos.x, a_pos.z)
	var cb := Vector2(b.position.x, b.position.z)
	for axis: Vector2 in axes:
		var ra := _project_radius(a, a_yaw, axis)
		var rb := _project_radius(b, float(b.yaw), axis)
		if absf((cb - ca).dot(axis)) > ra + rb:
			return false
	return true


static func _project_radius(entry: Dictionary, yaw: float, axis: Vector2) -> float:
	var right := Vector2(cos(yaw), -sin(yaw))
	var back := Vector2(sin(yaw), cos(yaw))
	return absf(right.dot(axis)) * float(entry.half_w) + absf(back.dot(axis)) * float(entry.half_l)


func _settle(entry: Dictionary, position: Vector3) -> Vector3:
	## Tabanin en yuksek yuzeyine otur (egimde yarim bloga gomulu kalmasin).
	var ground := -INF
	for p: Vector3 in _footprint(entry, position, entry.yaw):
		ground = maxf(ground, _surface_at(floori(p.x), floori(p.z), position.y + 0.5)[0])
	return Vector3(position.x, maxf(position.y, ground) if ground > -INF else position.y, position.z)


func _animate_cabin(entry: Dictionary, top: float) -> void:
	## Direksiyon ve ibreler kendi yerel Z ekseninde (paket sozlesmesi).
	var cabin: Node3D = entry.get("cabin")
	if cabin == null or not is_instance_valid(cabin):
		return
	_turn_part(cabin, "steering_wheel", -float(entry.steer) * 2.4)
	_turn_part(cabin, "speedometer_needle", -clampf(absf(float(entry.speed)) / maxf(1.0, top), 0.0, 1.0) * 3.8)
	_turn_part(cabin, "fuel_needle", -clampf(float(entry.fuel) / tank(entry), 0.0, 1.0) * 2.6)


static func _turn_part(root: Node3D, part_name: String, angle: float) -> void:
	var part := root.find_child(part_name, true, false) as Node3D
	if part == null:
		return
	if not part.has_meta("rest"):
		part.set_meta("rest", part.transform)
	var rest: Transform3D = part.get_meta("rest")
	part.transform = Transform3D(rest.basis * Basis(Vector3(0, 0, 1), angle), rest.origin)


# --- arac parcalari ---
## ARAC PARCASI (esya kategorisi vehicle_part, `slot` = motor/lastik/zirh/
## depo/port bagaj/tampon/far/susturucu). Takilan parca aracin kaydina
## yazilir ve etkisi hemen uygulanir:
##   vehicle_speed    : hiz tavani carpani      vehicle_tank   : +depo birimi
##   vehicle_capacity : +bagaj kg               vehicle_armor  : +saglamlik, carpma hasari azalir
##   vehicle_noise    : gurultu carpani         vehicle_ram    : zombi ezme hasari carpani, kendi hasari azalir
##   vehicle_light    : far menzili (m)
## Ayni yuvaya yeni parca takilinca eskisi cantaya doner (parca kaybolmaz).
static func part_sum(entry: Dictionary, key: String) -> float:
	var total := 0.0
	for slot: String in entry.get("parts", {}):
		var def := Content.item(str(entry.parts[slot].get("id", "")))
		if def != null:
			total += float(def.effects.get(key, 0.0))
	return total


static func part_mult(entry: Dictionary, key: String) -> float:
	var total := 1.0
	for slot: String in entry.get("parts", {}):
		var def := Content.item(str(entry.parts[slot].get("id", "")))
		if def != null and def.effects.has(key):
			total *= float(def.effects[key])
	return total


static func tank(entry: Dictionary) -> float:
	return TANK + part_sum(entry, "vehicle_tank")


static func max_durability(entry: Dictionary) -> float:
	return float(def_of(entry).get("durability", 100)) + part_sum(entry, "vehicle_armor")


func _apply_parts(entry: Dictionary) -> void:
	var base_kg := float(def_of(entry).get("capacity_kg", 120))
	(entry.trunk as Inventory).capacity_kg = base_kg + part_sum(entry, "vehicle_capacity")
	var light_range := part_sum(entry, "vehicle_light")
	if entry.get("headlight") != null and is_instance_valid(entry.headlight):
		entry.headlight.queue_free()
		entry.headlight = null
	if light_range > 0.0 and entry.node != null:
		var spot := SpotLight3D.new()
		spot.spot_range = light_range
		spot.spot_angle = 34.0
		spot.light_energy = 3.0
		spot.light_color = Color(1.0, 0.95, 0.82)
		spot.position = Vector3(0, 0.9, -float(entry.half_l))
		spot.visible = false
		entry.node.add_child(spot)
		entry.headlight = spot


func install_part(entry: Dictionary, stack: ItemStack, inventory: Inventory) -> String:
	if stack.definition.category != "vehicle_part":
		return "Bu bir araç parçası değil"
	if bool(entry.get("salvaged", false)):
		return "Sökülmüş araca parça takılmaz"
	var slot := stack.definition.slot
	var one := inventory.take_from_stack(stack, 1)
	if one == null:
		return "Parça bulunamadı"
	var old: Dictionary = entry.parts.get(slot, {})
	if not old.is_empty():
		var back := ItemStack.from_dict(old, Content.items)
		if back != null and inventory.add(back) > 0:
			inventory.add(one)
			return "Eski parça için çantada yer yok"
	entry.parts[slot] = one.to_dict()
	_apply_parts(entry)
	entry.durability = minf(max_durability(entry), float(entry.durability) + float(one.definition.effects.get("vehicle_armor", 0.0)))
	return "%s takıldı (%s)" % [one.definition.name, str(def_of(entry).get("name", "araç"))]


func update_lights(night: bool) -> void:
	## Surulen aracin farlari gece yanar.
	for entry: Dictionary in entries:
		var h: Variant = entry.get("headlight")
		if h != null and is_instance_valid(h):
			(h as SpotLight3D).visible = night and entry == driving


func gear_label() -> String:
	if driving.is_empty():
		return ""
	var s: float = driving.speed
	return "G" if s < -0.2 else ("N" if absf(s) <= 0.2 else "I")

func refuel(entry: Dictionary, inventory: Inventory) -> String:
	var resource := Content.resources.get_resource("fuel")
	var need: float = tank(entry) - entry.fuel
	if need <= 0.5:
		return "Depo zaten dolu"
	var have := Content.resources.stock(inventory, resource)
	if have <= 0.0:
		return "Cantada yakit yok (benzin, motor yagi...)"
	var used: float = Content.resources.consume(inventory, resource, minf(need, have))[0]
	entry.fuel = minf(tank(entry), entry.fuel + used)
	return "Depoya %.0f birim yakıt kondu (%.0f/%.0f)" % [used, entry.fuel, tank(entry)]


func repair(entry: Dictionary, inventory: Inventory) -> String:
	var maximum := max_durability(entry)
	if bool(entry.get("salvaged", false)):
		return "Sökülmüş araç onarılamaz"
	if entry.durability >= maximum:
		return "Araç sağlam"
	if inventory.count("toolkit") <= 0:
		return "Onarim icin takim cantasi gerekli"
	var cost := [{"tag": "structural_metal", "count": 2}, {"tag": "fastener", "count": 2}]
	if not BuildRules.pay(cost, [inventory]):
		return "Onarim icin 2 metal + 2 baglanti parcasi gerekli"
	entry.durability = minf(maximum, entry.durability + maximum * repair_share)
	return "Arac onarildi (%d/%d)" % [int(entry.durability), int(maximum)]


func to_dict() -> Dictionary:
	var list: Array = []
	for entry: Dictionary in entries:
		list.append({"def": entry.def_id, "model": entry.model_id,
			"p": [entry.position.x, entry.position.y, entry.position.z], "yaw": entry.yaw,
			"fuel": entry.fuel, "durability": entry.durability, "trunk": entry.trunk.to_dict(),
			"parts": entry.parts.duplicate(true), "salvaged": entry.salvaged})
	return {"entries": list, "spawned": true}


func load_dict(data: Dictionary) -> void:
	for entry: Dictionary in entries:
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	entries.clear()
	driving = {}
	for raw: Variant in data.get("entries", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var p: Array = raw.get("p", [0, 0, 0])
		var entry := _create(str(raw.get("def", "sedan")), str(raw.get("model", "sedan")),
			Vector3(p[0], p[1], p[2]), float(raw.get("yaw", 0.0)))
		var parts: Variant = raw.get("parts", {})
		if typeof(parts) == TYPE_DICTIONARY:
			for slot: String in parts:
				if typeof(parts[slot]) == TYPE_DICTIONARY and Content.items.has(str(parts[slot].get("id", ""))):
					entry.parts[slot] = parts[slot]
		entry.salvaged = bool(raw.get("salvaged", false))
		entry.fuel = clampf(float(raw.get("fuel", 0.0)), 0.0, tank(entry))
		entry.durability = float(raw.get("durability", entry.durability))
		entry.trunk.load_dict(raw.get("trunk", {}), Content.items)
		_apply_parts(entry)
