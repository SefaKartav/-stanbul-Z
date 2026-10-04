class_name PowerGrid
extends RefCounted
## Elektrik: uretim / tuketim / depolama ve BAGLANTI.
##
## AG: elektrikli yapilar (jenerator, aku, gunes paneli, direk, anahtar,
## sensor ve guc ceken her yapi) birbirine kablo menzili icindeyse ayni
## aga baglanir. Menzil varsayilan 6 m; kablo diregi (relay) 24 m'ye kadar
## tasir. KAPALI ANAHTAR kablo tasimaz: agi ikiye boler. Direk yikilirsa ag
## kopar (yeniden hesaplanir) -- "baglanti kesilmesi" gercek bir olaydir.
##
## BUTCE (her 0.5 sn, OYUN SAATI cinsinden):
##   uretim  = acik ve yakitli jeneratorler + gunes (gun isigiyla)
##   talep   = calisan tuketiciler (lamba, istasyon uretimde, taret, tuzak,
##             alarm, aritici, hidroponik saksi, sensor bekleme gucu)
##   fazla   -> akulere (kapasiteye kadar); eksik -> akulerden
##   hala eksik -> ONCELIGE gore tuketici kapatilir (istasyon/taret > tuzak/
##   alarm > lamba). Gucsuz tuketici CALISMAZ (uretim durur, taret susar).
## Jenerator yakiti "tam yuk saati" olarak tutulur; yukle orantili yanar
## (bosta %25). Bitince ussun deposundan otomatik bir birim yakit alinir.
## Calisan jenerator GURULTU yapar (zombileri ceker).
## Sensor: aginda sensor varsa lamba ve elektrikli tuzaklar yalnizca
## tetiklenince (hareket / karanlik) calisir ve ancak o zaman guc ceker.

const TICK := 0.5
const DEFAULT_REACH := 6.0
const STANDBY := {"sensor": 2.0}
const PRIORITY := {"station": 4, "turret": 4, "purifier": 3, "planter": 3, "trap": 2, "alarm": 2, "decoy": 1,
	"light": 1, "sensor": 5}

var placeables: Placeables
var networks: Array = []       # [{members, generators, batteries, solars, consumers, sensors, stats}]
var _dirty := true
var _timer := 0.0
var _noise_timer := 0.0


func _init(p_placeables: Placeables) -> void:
	placeables = p_placeables
	placeables.changed.connect(mark_dirty)


func mark_dirty() -> void:
	_dirty = true


static func draw_of(info: Dictionary) -> float:
	return float(info.get("power", 0.0))


func is_electric(entry: Dictionary) -> bool:
	var info := placeables.info_of(entry)
	return entry.kind in Placeables.POWER_KINDS or draw_of(info) > 0.0


func reach_of(entry: Dictionary) -> float:
	var info := placeables.info_of(entry)
	return float(info.get("reach", 24.0 if entry.kind == "relay" else DEFAULT_REACH))


static func _pos(entry: Dictionary) -> Vector3:
	return Vector3(entry.cell) + Vector3(0.5, 0.5, 0.5)


func rebuild() -> void:
	_dirty = false
	networks.clear()
	var nodes: Array = placeables.entries.filter(is_electric)
	var parent := {}
	for entry: Dictionary in nodes:
		parent[entry.id] = entry.id
	var find := func(id: int) -> int:
		var root := id
		while parent[root] != root:
			root = parent[root]
		return root
	for i in nodes.size():
		var a: Dictionary = nodes[i]
		if a.kind == "switch" and not bool(a.on):
			continue
		for j in range(i + 1, nodes.size()):
			var b: Dictionary = nodes[j]
			if b.kind == "switch" and not bool(b.on):
				continue
			if _pos(a).distance_to(_pos(b)) <= maxf(reach_of(a), reach_of(b)):
				var ra: int = find.call(a.id)
				var rb: int = find.call(b.id)
				if ra != rb:
					parent[ra] = rb
	var groups := {}
	for entry: Dictionary in nodes:
		var root: int = find.call(entry.id)
		if not groups.has(root):
			groups[root] = {"members": [], "generators": [], "batteries": [], "solars": [], "consumers": [],
				"sensors": [], "stats": {}}
		var net: Dictionary = groups[root]
		net.members.append(entry)
		match entry.kind:
			"generator":
				net.generators.append(entry)
			"battery":
				net.batteries.append(entry)
			"solar", "turbine":
				net.solars.append(entry)
			"sensor":
				net.sensors.append(entry)
				net.consumers.append(entry)
			"relay", "switch":
				pass
			"cold_room":
				net.consumers.append(entry)
			_:
				net.consumers.append(entry)
	networks = groups.values()
	for entry: Dictionary in placeables.entries:
		if not is_electric(entry):
			entry.powered = true          # elektrik istemeyen yapi her zaman calisir
		elif draw_of(placeables.info_of(entry)) <= 0.0 and entry.kind in ["relay", "switch", "generator", "battery", "solar"]:
			entry.powered = true


func network_of(entry: Dictionary) -> Dictionary:
	for net: Dictionary in networks:
		if net.members.has(entry):
			return net
	return {}


func _sensors_triggered(net: Dictionary, game: Node) -> bool:
	if net.sensors.is_empty():
		return true
	for sensor: Dictionary in net.sensors:
		var info := placeables.info_of(sensor)
		var mode := str(info.get("mode", "motion"))
		if mode == "night":
			if game.time.darkness() > 0.45:
				return true
			continue
		var radius := float(info.get("radius", 10.0))
		var at := _pos(sensor)
		for actor: Node3D in game.actors.near(at, radius):
			if actor.is_alive() and actor.faction() == "zombie":
				return true
		if game.player.global_position.distance_to(at) <= radius and str(info.get("detect", "zombie")) == "all":
			return true
	return false


func _demand_of(entry: Dictionary, triggered: bool, game: Node) -> float:
	var info := placeables.info_of(entry)
	var draw := draw_of(info)
	match entry.kind:
		"sensor":
			return float(STANDBY.sensor)
		"light":
			return draw if bool(entry.on) and triggered else 0.0
		"trap":
			return draw if triggered else 0.0
		"station":
			return draw if bool(entry.get("active", false)) else 0.0
		"planter":
			return draw if str(entry.state.get("seed", "")) != "" else 0.0
		"alarm", "decoy", "purifier":
			return draw if bool(entry.on) else 0.0
	return draw


func tick(delta: float, game: Node) -> void:
	_timer += delta
	if _timer < TICK:
		return
	var dt := _timer
	_timer = 0.0
	if _dirty:
		rebuild()
	var hours: float = dt * game.time.hours_per_second()
	var daylight: float = clampf(1.0 - game.time.darkness(), 0.0, 1.0)
	var any_generator := false
	for net: Dictionary in networks:
		var triggered := _sensors_triggered(net, game)
		# Talep
		var demands: Array = []
		var demand := 0.0
		for c: Dictionary in net.consumers:
			var d := _demand_of(c, triggered, game)
			demands.append([c, d])
			demand += d
		# Uretim
		var production := 0.0
		for g: Dictionary in net.generators:
			var info := placeables.info_of(g)
			if not bool(g.on):
				continue
			if float(g.fuel) <= 0.0:
				_refuel_from_base(g, game)
			if float(g.fuel) <= 0.0:
				continue
			var output := float(info.get("output", 400.0)) * (0.8 + 0.4 * float(g.quality) / 100.0)
			production += output
			any_generator = true
			g["running"] = true
		for s: Dictionary in net.solars:
			var info := placeables.info_of(s)
			# Gunes gun isigiyla; ruzgar turbini gun boyu, ruzgarla dalgali.
			var factor := daylight if s.kind == "solar" else 0.55 + 0.35 * sin(game.time.total_hours() * 0.7 + float(s.id))
			production += float(info.get("output", 100.0)) * factor * (0.8 + 0.4 * float(s.quality) / 100.0)
		# Yakit: yuk oraninda (bosta %25)
		var gen_capacity := 0.0
		for g: Dictionary in net.generators:
			if bool(g.get("running", false)):
				gen_capacity += float(placeables.info_of(g).get("output", 400.0))
		var solar_now := production - gen_capacity
		var gen_load := clampf((demand - solar_now) / maxf(1.0, gen_capacity), 0.25, 1.0) if gen_capacity > 0.0 else 0.0
		for g: Dictionary in net.generators:
			if bool(g.get("running", false)):
				g.fuel = maxf(0.0, float(g.fuel) - hours * gen_load)
				g["running"] = false
		# Denge
		var capacity_wh := 0.0
		var stored := 0.0
		for b: Dictionary in net.batteries:
			capacity_wh += battery_capacity(b)
			stored += float(b.charge)
		var balance := production - demand
		var budget := production
		if balance >= 0.0:
			_charge(net.batteries, balance * hours)
			budget = demand
		else:
			var need_wh := -balance * hours
			var from_battery := minf(need_wh, stored)
			_charge(net.batteries, -from_battery)
			budget = production + (from_battery / maxf(1e-6, hours))
		# Guc dagitimi (oncelik sirasiyla)
		demands.sort_custom(func(a: Array, b: Array) -> bool:
			return int(PRIORITY.get(a[0].kind, 1)) > int(PRIORITY.get(b[0].kind, 1)))
		var left := budget + 0.01
		for pair: Array in demands:
			var c: Dictionary = pair[0]
			var d: float = pair[1]
			if d <= 0.0:
				# Istemiyor (kapali/tetiklenmedi): calisma izni yine agin varligina bagli.
				c.powered = (production + stored) > 0.0 and (triggered or c.kind in ["station", "turret", "purifier", "planter"])
				continue
			c.powered = left >= d
			if c.powered:
				left -= d
		net.stats = {"production": production, "demand": demand, "stored": stored, "capacity": capacity_wh,
			"triggered": triggered}
	# Calisan jenerator gurultusu
	_noise_timer -= dt
	if any_generator and _noise_timer <= 0.0:
		_noise_timer = 5.0
		for net: Dictionary in networks:
			for g: Dictionary in net.generators:
				if bool(g.on) and float(g.fuel) > 0.0:
					game.on_noise_at(_pos(g), Units.perception_m(float(placeables.info_of(g).get("noise", 260.0))))


func battery_capacity(entry: Dictionary) -> float:
	return float(placeables.info_of(entry).get("capacity", 1000.0)) * (0.8 + 0.4 * float(entry.quality) / 100.0)


func _charge(batteries: Array, wh: float) -> void:
	## Pozitif: sarj (kapasiteye kadar, esit paylasim); negatif: desarj.
	if batteries.is_empty() or is_zero_approx(wh):
		return
	var share := wh / batteries.size()
	var carry := 0.0
	for b: Dictionary in batteries:
		var cap := battery_capacity(b)
		var want := share + carry
		var before := float(b.charge)
		b.charge = clampf(before + want, 0.0, cap)
		carry = want - (float(b.charge) - before)


func _refuel_from_base(generator: Dictionary, game: Node) -> void:
	## Yakiti biten jenerator ussun deposundan (varsa) bir birim yakit alir.
	var base: Settlement = game.bases.settlement_at(Vector3(generator.cell))
	if base == null:
		return
	var fuel := base.stockpile.matching_tag(str(placeables.info_of(generator).get("fuel_tag", "chemical_fuel")))
	if fuel.is_empty():
		return
	base.stockpile.take_from_stack(fuel[0], 1)
	generator.fuel = float(placeables.info_of(generator).get("fuel_hours", 4.0))


func add_fuel(generator: Dictionary, inventory: Inventory) -> int:
	## Oyuncu E ile yakit koyar: depo dolana kadar chemical_fuel harcar.
	var info := placeables.info_of(generator)
	var per := float(info.get("fuel_hours", 4.0))
	var tank := float(info.get("tank_hours", per * 3.0))
	var used := 0
	while float(generator.fuel) + per <= tank + 0.01:
		var fuel := inventory.matching_tag(str(info.get("fuel_tag", "chemical_fuel")))
		if fuel.is_empty():
			break
		inventory.take_from_stack(fuel[0], 1)
		generator.fuel = float(generator.fuel) + per
		used += 1
	return used


func summary_for(base: Settlement) -> Dictionary:
	## Koloni ekrani: ussun icindeki aglarin toplami.
	var total := {"production": 0.0, "demand": 0.0, "stored": 0.0, "capacity": 0.0, "networks": 0}
	for net: Dictionary in networks:
		var inside := false
		for m: Dictionary in net.members:
			if base.contains_position(Vector3(m.cell)):
				inside = true
				break
		if not inside or net.stats.is_empty():
			continue
		total.networks += 1
		for key: String in ["production", "demand", "stored", "capacity"]:
			total[key] += float(net.stats.get(key, 0.0))
	return total
