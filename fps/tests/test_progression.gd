extends RefCounted
## Seviye (1-50), beceri agaci (6 dal x 8), ustalik, goc ve deneyim temposu.


func test_tree_shape_and_behaviors(t) -> void:
	var nodes: Dictionary = Content.skill_tree.nodes
	t.ok(nodes.size() >= 48, "en az 48 dugum (%d)" % nodes.size())
	var branches := {}
	var behavior := 0
	var damage_only := 0
	for id: String in nodes:
		var n: Dictionary = nodes[id]
		branches[n.branch] = int(branches.get(n.branch, 0)) + 1
		if n.has("behavior") or n.has("unlock"):
			behavior += 1
		var effects: Dictionary = n.get("effects", {})
		if effects.size() == 1 and (effects.keys()[0] as String).ends_with("damage") and not n.has("behavior"):
			damage_only += 1
	t.eq(branches.size(), 6, "alti dal")
	for b: String in branches:
		t.ok(int(branches[b]) >= 8, "%s dalinda en az 8 dugum" % b)
	t.ok(behavior >= 18, "en az 18 dugum yeni eylem/tarif/erisim acar (%d)" % behavior)
	t.ok(damage_only <= 8, "yalniz hasar yuzdesi veren dugum az (%d)" % damage_only)
	var points_at_50 := 49 + 7
	print("  agac toplam maliyeti %d puan, 50. seviyede ~%d puan" % [SkillTree.total_cost(), points_at_50])
	t.ok(SkillTree.total_cost() > points_at_50 * 1.5, "tek oyunda agacin hepsi acilmaz (uzmanlasma)")
	var errors: Array = []
	SkillTree.validate(errors)
	t.eq(errors, [], "agac dogrulamasi temiz")


func test_unlock_conditions(t) -> void:
	var p := Progression.new()
	p.points = 0
	t.ok(not SkillTree.check("cb_control", p)[0], "puansiz acilmaz")
	p.points = 10
	t.ok(SkillTree.check("cb_control", p)[0], "tier 1 puanla acilir")
	t.ok(not SkillTree.check("cb_shove", p)[0], "onkosul yoksa acilmaz")
	t.ok(p.upgrade("cb_control"), "acildi")
	t.eq(p.points, 9, "maliyet dusuldu")
	t.ok(str(SkillTree.check("cb_shove", p)[1]).contains("Seviye"), "seviye kosulu: %s" % SkillTree.check("cb_shove", p)[1])
	p.level = 10
	t.ok(p.upgrade("cb_shove"), "seviye ve onkosulla acilir")
	t.eq(p.rank_of("shove"), 3, "yetenek rutbesi +2")
	p.upgrade("cb_reload")
	var weak := SkillTree.check("cb_weakspot", p)
	t.ok(not weak[0] and str(weak[1]).begins_with("Ustalik"), "ustalik sayaci ister: %s" % weak[1])
	p.count("kills_firearm", 40)
	t.ok(p.upgrade("cb_weakspot"), "ustalikla acilir")
	var skills := SkillProfile.new(Content.skills, p.ranks)
	skills.refresh_tree(p.nodes)
	t.near(skills.multiplier("weapon_spread"), 0.85, 0.001, "etki SkillProfile'dan sistemlere")
	t.near(skills.multiplier("headshot_damage"), 1.25, 0.001, "kafa isabeti")


func test_level_cap_and_curve(t) -> void:
	var p := Progression.new()
	var total := Progression.total_xp_to(Progression.max_level())
	print("  1 -> %d seviye: %d deneyim" % [Progression.max_level(), int(total)])
	p.award_source(total + 100000.0, "kill")
	t.eq(p.level, Progression.max_level(), "seviye tavani 50")
	t.eq(p.points, 1 + Progression.max_level() - 1, "her seviye 1 puan")


func test_exploit_limits(t) -> void:
	var p := Progression.new()
	p.on_craft(2, "r_x")
	var first: float = p.sources.craft
	p.on_craft(2, "r_x")
	var second: float = p.sources.craft - first
	t.ok(first > second * 2.5, "ilk uretim bonuslu, tekrar azalir (%.0f / %.0f)" % [first, second])
	for i in 30:
		p.on_craft(2, "r_x")
	var late: float = p.sources.craft
	t.ok(late < first * 15.0, "ayni tarifin tekrari doyar")
	t.ok(p.on_region("kadikoy"), "ilk semt kesfi deneyim verir")
	t.ok(not p.on_region("kadikoy"), "ikinci kez vermez")


func test_old_ranks_are_refunded(t) -> void:
	var p := Progression.new()
	p.load_dict({"xp": 10.0, "level": 7, "points": 1, "ranks": {"marksmanship": 3, "shove": 2}})
	t.eq(p.migrated_points, 3, "eski rutbelere harcanan 3 puan")
	t.eq(p.points, 4, "puan iade edildi (1 + 3)")
	t.eq(p.rank_of("shove"), 1, "rutbe temel degere dondu")
	var again := Progression.new()
	again.load_dict(p.to_dict())
	t.eq(again.points, 4, "goc bir kez yapilir")


func test_pacing_simulation(t) -> void:
	## Asama bazli tempo: saatlik tipik deneyim (oldurme, ilk arama, uretim,
	## gorev, kesif) ile hedef seviye araliklari. Olculmus sure DEGIL;
	## dengenin buyukluk sirasini denetler.
	var per_hour := {"kill": 35 * 11.0, "search": 55 * 12.0, "craft": 8 * 20.0, "quest": 350.0, "discovery": 60.0}
	var hourly := 0.0
	for k: String in per_hour:
		hourly += float(per_hour[k])
	var levels := {}
	for hours: int in [1, 3, 10, 30, 45]:
		var p := Progression.new()
		p.award_source(hourly * hours, "sim")
		levels[hours] = p.level
	print("  tempo (saat -> seviye): %s, saatlik %.0f deneyim" % [levels, hourly])
	t.ok(int(levels[1]) >= 4, "ilk saatte birkac seviye")
	t.ok(int(levels[30]) >= 25 and int(levels[30]) < 50, "30 saatte ana omurga seviyesi, tavan degil")
	t.ok(int(levels[45]) >= 35, "40+ saatte uzmanlasma devam")
