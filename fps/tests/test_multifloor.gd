extends RefCounted
## KABUL: gercek koridor haritasindan en az 30 sabit bina ornegi; her birinde
## sokak -> giris -> her kat -> cati (varsa) rotasi GERCEK oyuncu govdesiyle
## (0.6 x 1.8 m) yurunur. Olculen: ulasilan kat, cati, basamak bas boslugu,
## erisilemeyen container, oda alanlari. Sonuc docs/reports/ic_mekan_raporu.*
## dosyalarina yazilir.
##
## Ornek kumeleri (sabit sira, kararli): 2, 3-4, 5-7, 8-11, 12+ katli; avlulu;
## karma kullanim (zemin dukkan); dar ayak izi; duzensiz (8+ koseli) ayak izi.

const MAP := "res://data/map/maltepe_besiktas.json"

static var _city: CityGenerator


static func _get_city() -> CityGenerator:
	if _city == null:
		_city = CityGenerator.new(Content.blocks, MAP)
	return _city


static func _pick(city: CityGenerator) -> Array:
	## Kadikoy cevresinden (dogus) baslayarak her kumeden sabit sayida bina.
	var spawn: Array = city.data.get("spawn", [0, 0])
	var near := Vector3(float(spawn[0]), 0, float(spawn[1]))
	var groups := {"2 kat": [], "3-4 kat": [], "5-7 kat": [], "8-11 kat": [], "12+ kat": [], "avlulu": [],
		"karma": [], "dar": [], "duzensiz": []}
	var want := {"2 kat": 4, "3-4 kat": 4, "5-7 kat": 5, "8-11 kat": 5, "12+ kat": 3, "avlulu": 2, "karma": 4,
		"dar": 3, "duzensiz": 3}
	var candidates := city.buildings_near(near, 3500.0)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		var da: float = (city.buildings[a].centroid as Vector2).distance_to(Vector2(near.x, near.z))
		var db: float = (city.buildings[b].centroid as Vector2).distance_to(Vector2(near.x, near.z))
		return da < db if absf(da - db) > 0.01 else a < b)
	var used := {}
	for index: int in candidates:
		var b: Dictionary = city.buildings[index]
		if not bool(b.interior) or not city.is_inside(floori(b.centroid.x), floori(b.centroid.y)):
			continue
		var levels := int(b.levels)
		var group := ""
		var w: float = (b.hi - b.lo).x
		var d: float = (b.hi - b.lo).y
		if not (b.holes as Array).is_empty():
			group = "avlulu"
		elif str(b["class"]) in ["market", "pharmacy", "electronics"] and levels >= 3:
			group = "karma"
		elif minf(w, d) <= 7.5 and levels >= 3:
			group = "dar"
		elif (b.poly as PackedVector2Array).size() >= 9 and levels >= 3:
			group = "duzensiz"
		elif levels == 2:
			group = "2 kat"
		elif levels <= 4:
			group = "3-4 kat"
		elif levels <= 7:
			group = "5-7 kat"
		elif levels <= 11:
			group = "8-11 kat"
		else:
			group = "12+ kat"
		if (groups[group] as Array).size() < int(want[group]) and not used.has(index):
			groups[group].append(index)
			used[index] = true
	return [groups, used.keys()]


func test_thirty_buildings_every_floor_walkable(t) -> void:
	var city := _get_city()
	var picked := _pick(city)
	var groups: Dictionary = picked[0]
	var rows: Array = []
	var total := 0
	var fully := 0
	var unreachable_containers := 0
	var head_bad := 0
	var worst_head := 99.0
	var failures: Array = []
	var room_stats := {}
	for group: String in groups:
		for index: int in groups[group]:
			var b: Dictionary = city.buildings[index]
			var plan := city.interior_plan(index)
			total += 1
			var row := {"id": b.id, "group": group, "class": b["class"], "levels": b.levels,
				"height_source": b.get("height_source", ""), "area_m2": snappedf(float(b.area), 0.1), "ok": plan.get("ok", false)}
			if not plan.get("ok", false):
				row["reason"] = plan.get("reason", "?")
				rows.append(row)
				failures.append("%s (%s): plan yok -- %s" % [b.id, group, row.reason])
				continue
			var world := TestWalker.world_around(city, plan, int(b.top_y) + 2)
			TestWalker.open_door(world, plan)
			var door: Dictionary = plan.doors[0]
			var outside: Vector2i = door.cell + door.outward
			var o: Vector2i = plan.origin
			var s: Vector2i = plan.size
			var reach := TestWalker.walk(world, outside, city.surface_y(outside.x, outside.y), o - Vector2i(2, 2),
				o + s + Vector2i(2, 2), float(plan.floors[0].y) - 3.0, float(b.top_y) + 3.0)
			var floors_ok := 0
			for k in plan.floors.size():
				if k < int(plan.accessible) and TestWalker.floor_reached(reach, plan, k):
					floors_ok += 1
			var stairs: Dictionary = plan.stairs
			var roof_ok := false
			if not stairs.is_empty() and bool(stairs.roof):
				roof_ok = TestWalker.reached(reach, stairs.exit, float(b.top_y) + 1.0)
			var bad_containers := 0
			var containers := 0
			for f: Dictionary in plan.furniture:
				if f.container == "" or int(f.floor) >= int(plan.accessible):
					continue
				containers += 1
				var any := false
				for a: Vector2i in f.get("access", []):
					if TestWalker.reached(reach, a, float(plan.floors[int(f.floor)].y)):
						any = true
				if not any:
					bad_containers += 1
					if bad_containers <= 3:
						var seen := PackedStringArray()
						for a: Vector2i in f.get("access", []):
							for s3: Vector3i in reach:
								if s3.x == a.x and s3.z == a.y:
									seen.append(str(s3.y * 0.5))
						print("    erisilemez: %s kat %d %s access %s y=%s, ulasilan y: %s" % [f.id, int(f.floor), f.asset,
							f.get("access", []), plan.floors[int(f.floor)].y, seen])
			if not stairs.is_empty():
				var head: Array = TestWalker.headroom_ok(world, reach, stairs.tops, float(plan.floors[0].y))
				head_bad += int(head[0])
				if int(head[2]) > 0:
					worst_head = minf(worst_head, float(head[1]))
				row["headroom_min_m"] = head[1]
			for k in mini(int(plan.accessible), plan.floors.size()):
				for room: Dictionary in plan.floors[k].get("rooms", []):
					var type := str(room.type)
					if not room_stats.has(type):
						room_stats[type] = []
					room_stats[type].append(int(room.get("area", 0)))
			unreachable_containers += bad_containers
			row.merge({"accessible": plan.accessible, "floors_walked": floors_ok, "stairs": stairs.get("template", "-"),
				"roof_exit": bool(stairs.get("roof", false)), "roof_walked": roof_ok, "containers": containers,
				"unreachable_containers": bad_containers, "reason_upper": plan.get("reason_upper", "")})
			rows.append(row)
			var all_floors := floors_ok == int(b.levels)
			if all_floors and (not bool(stairs.get("roof", false)) or roof_ok) and bad_containers == 0:
				fully += 1
			else:
				failures.append("%s (%s, %d kat, %s): %d/%d kat yurundu, cati %s, erisilemez %d %s" % [b.id, group, b.levels,
					stairs.get("template", "merdiven yok"), floors_ok, b.levels, roof_ok, bad_containers, plan.get("reason_upper", "")])
	for line: String in failures:
		print("  sorun: ", line)
	var summary := {}
	for type: String in room_stats:
		var list: Array = room_stats[type]
		list.sort()
		summary[type] = {"n": list.size(), "min": list[0], "median": list[list.size() / 2], "max": list[list.size() - 1]}
	print("  %d bina: %d tamamen yurunebilir; erisilemez container %d; bas boslugu en kotu %.2f m, yetersiz nokta %d" % [
		total, fully, unreachable_containers, worst_head, head_bad])
	print("  oda alanlari (m2): %s" % summary)
	_write_report(rows, summary, total, fully, unreachable_containers, worst_head, head_bad)
	t.ok(total >= 30, "en az 30 ornek bina (%d)" % total)
	t.ok(fully >= int(total * 0.9), "orneklerin en az %%90'inda butun katlar ve cati yurunebilir (%d/%d)" % [fully, total])
	t.eq(unreachable_containers, 0, "baslangicta erisilemeyen container olmamali")
	t.eq(head_bad, 0, "basamaklarda bas boslugu >= 2.05 m")
	var tall := 0
	for row: Dictionary in rows:
		if int(row.levels) >= 12 and int(row.get("floors_walked", 0)) >= 12:
			tall += 1
	t.ok(tall >= 1, "12+ katli en az bir binanin butun katlari yurunmeli")


static func _write_report(rows: Array, rooms: Dictionary, total: int, fully: int, unreachable: int, head: float, head_bad: int) -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/reports")
	var data := {"generated": Time.get_datetime_string_from_system(), "buildings": total, "fully_walkable": fully,
		"unreachable_containers": unreachable, "headroom_worst_m": head, "headroom_bad_points": head_bad,
		"room_areas_m2": rooms, "rows": rows}
	var f := FileAccess.open("res://docs/reports/ic_mekan_raporu.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, " "))
	var lines := PackedStringArray(["# Ic mekan erisim raporu (%s)" % data.generated, "",
		"Gercek koridor haritasindan %d bina; gercek govde (0.6 x 1.8 m) ile sokak -> giris -> her kat -> cati." % total,
		"Tamamen yurunebilir: %d. Erisilemeyen container: %d. Basamak bas boslugu en kotu %.2f m (hedef >= 2.05), yetersiz nokta %d." % [fully, unreachable, head, head_bad],
		"", "| Bina | Kume | Sinif | Kat | Kaynak | Alan m2 | Merdiven | Yurunen kat | Cati | Container | Erisilemez |",
		"|---|---|---|---:|---|---:|---|---:|---|---:|---:|"])
	for r: Dictionary in rows:
		lines.append("| %s | %s | %s | %d | %s | %.0f | %s | %s | %s | %s | %s |" % [r.id, r.group, r["class"], int(r.levels),
			r.get("height_source", ""), float(r.area_m2), r.get("stairs", "-"), str(r.get("floors_walked", "-")),
			("evet" if r.get("roof_walked", false) else ("cati cikisi yok" if not r.get("roof_exit", false) else "HAYIR")),
			str(r.get("containers", "-")), str(r.get("unreachable_containers", "-"))])
	lines.append("")
	lines.append("Oda alanlari (m2, 1 hucre = 1 m2): %s" % JSON.stringify(rooms))
	var md := FileAccess.open("res://docs/reports/ic_mekan_raporu.md", FileAccess.WRITE)
	if md != null:
		md.store_string("\n".join(lines) + "\n")
