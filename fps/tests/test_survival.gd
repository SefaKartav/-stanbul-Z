extends RefCounted
## Kisisel aclik/susuzluk, su aritma, pisirme ve bozulma.


static func _hours(vitals: PlayerVitals, hours: float, fps: float, activity: String = "walk") -> void:
	## `hours` oyun saatini `fps` kare hiziyla isle (1 oyun saati = 40 sn).
	var dt := 1.0 / fps
	var per_frame := dt / 40.0
	var frames := roundi(hours / per_frame)
	for _i in frames:
		vitals.tick_needs(per_frame, activity)


func test_needs_are_frame_rate_independent(t) -> void:
	var results: Array = []
	for fps: float in [30.0, 60.0, 144.0]:
		var v := PlayerVitals.new()
		v.satiety = 90.0
		v.hydration = 90.0
		_hours(v, 2.0, fps)
		results.append([v.satiety, v.hydration])
	for r: Array in results:
		t.near(r[0], results[0][0], 0.02, "tokluk kare hizindan bagimsiz")
		t.near(r[1], results[0][1], 0.02, "hidrasyon kare hizindan bagimsiz")
	var rates: Dictionary = Content.nutrition.rates
	t.near(90.0 - float(results[0][0]), 2.0 * float(rates.satiety_per_hour), 0.05, "tokluk oyun saatine bagli")
	# Hedef tempo: su karari 15-25 gercek dk, yemek 30-45 dk (normal, yuruyus).
	var water_min := (100.0 - 25.0) / float(rates.hydration_per_hour) * 40.0 / 60.0
	var food_min := (100.0 - 25.0) / float(rates.satiety_per_hour) * 40.0 / 60.0
	print("  dolu -> dusuk esik: su %.0f dk, yemek %.0f dk (gercek)" % [water_min, food_min])
	t.ok(water_min >= 15.0 and water_min <= 30.0, "su karari ~15-25 dk (%.0f)" % water_min)
	t.ok(food_min >= 30.0 and food_min <= 50.0, "yemek karari ~30-45 dk (%.0f)" % food_min)
	t.ok(water_min < food_min, "susuzluk aclıktan acil")


func test_zero_needs_warn_before_damage(t) -> void:
	var v := PlayerVitals.new()
	var warnings: Array = []
	v.need_warning.connect(func(text: String, _u: bool) -> void: warnings.append(text))
	v.hydration = 0.5
	v.satiety = 60.0
	v.tick_needs(1.0, "walk")
	t.near(v.health, 100.0, 0.01, "sifira iner inmez can gitmez (uyari suresi)")
	t.ok(warnings.size() >= 1, "uyari gelmeli")
	v.tick_needs(1.5, "walk")
	t.near(v.health, 100.0, 0.01, "3 saatlik uyari suresi dolmadan can gitmez")
	v.tick_needs(2.0, "walk")
	t.ok(v.health < 100.0, "uyari suresinden sonra can kaybi (%.1f)" % v.health)
	t.ok(v.health > 80.0, "can kaybi ani olum degil")
	t.ok(v.stamina_cap() >= 35.0, "nefes tavani en az %35 (hareket edebilir)")


func test_drink_returns_bottle_and_is_atomic(t) -> void:
	var v := PlayerVitals.new()
	v.hydration = 30.0
	var inv := Inventory.new(45.0, 10)
	inv.add(ItemStack.new(Content.item("water_bottle"), 2, 50.0))
	var skills := SkillProfile.new()
	var result := ItemUsage.use(inv.find("water_bottle"), v, inv, skills)
	t.ok(result.ok, "su icilmeli: %s" % result.message)
	t.near(v.hydration, 70.0, 0.01, "+40 su")
	t.eq(inv.count("water_bottle"), 1, "bir sise azaldi")
	t.eq(inv.count("bottle_empty"), 1, "bos sise geri kaldi")
	# Dolu canta: yeni yigin acilamiyorsa hicbir sey tuketilmez.
	var full := Inventory.new(999.0, 1)
	full.add(ItemStack.new(Content.item("water_bottle"), 3, 50.0))
	v.hydration = 30.0
	var refused := ItemUsage.use(full.find("water_bottle"), v, full, skills)
	t.ok(not refused.ok, "bos kap sigmiyorsa icilmez")
	t.eq(full.count("water_bottle"), 3, "hicbir sey tuketilmedi")
	t.near(v.hydration, 30.0, 0.01, "etki uygulanmadi")


func test_raw_staples_need_cooking(t) -> void:
	var v := PlayerVitals.new()
	v.satiety = 20.0
	var inv := Inventory.new(45.0, 10)
	inv.add(ItemStack.new(Content.item("rice_bag"), 1, 50.0))
	var check := ItemUsage.can_use(inv.find("rice_bag"), v)
	t.ok(not check[0], "cig pirinc yenmez")
	t.ok(str(check[1]).contains("pisir"), "neden soylenir: %s" % check[1])


func test_dirty_water_can_make_you_sick(t) -> void:
	var inv := Inventory.new(45.0, 20)
	var skills := SkillProfile.new()
	var rng := RandomNumberGenerator.new()
	var sick := 0
	for i in 60:
		var v := PlayerVitals.new()
		v.hydration = 20.0
		inv.clear()
		inv.add(ItemStack.new(Content.item("water_dirty"), 1, 0.0))
		rng.seed = i
		ItemUsage.use(inv.find("water_dirty"), v, inv, skills, rng)
		if v.statuses.has(PlayerVitals.SICK):
			sick += 1
	print("  kirli su: 60 icisin %d'inde mide bulantisi" % sick)
	t.ok(sick > 5 and sick < 40, "risk olasiliksal (~%%35): %d/60" % sick)
	var v := PlayerVitals.new()
	v.hydration = 80.0
	var w := PlayerVitals.new()
	w.hydration = 80.0
	w.statuses.apply(PlayerVitals.SICK, 100.0, 1.0)
	v.tick_needs(1.0, "walk")
	w.tick_needs(1.0, "walk")
	t.ok(w.hydration < v.hydration - 1.0, "hasta iken su daha hizli gider")


func test_purify_boil_and_cook(t) -> void:
	var service := CraftingService.new(Content.items)
	var inv := Inventory.new(80.0, 40)
	inv.add(ItemStack.new(Content.item("water_dirty"), 3, 0.0))
	inv.add(ItemStack.new(Content.item("wood_plank"), 1, 0.0))
	var boil := service.craft(inv, Content.recipes["r_boil_water"], "cooking", 1)
	t.ok(boil.success, "kaynatma: %s" % boil.reason)
	t.eq(inv.count("water_bottle"), 3, "uc sise temiz su")
	t.eq(inv.count("water_dirty"), 0, "kirli su harcandi")
	t.eq(inv.count("wood_plank"), 0, "yakit harcandi")
	var no_stove := service.check(inv, Content.recipes["r_boil_water"], "hands", 1)
	t.ok(not no_stove.ok, "ocaksiz kaynatilmaz")
	inv.add(ItemStack.new(Content.item("lentil_bag"), 2, 50.0))
	inv.add(ItemStack.new(Content.item("charcoal"), 1, 0.0))
	var cook := service.craft(inv, Content.recipes["r_cook_staple"], "cooking", 1)
	t.ok(cook.success, "pisirme: %s" % cook.reason)
	t.eq(inv.count("cooked_meal"), 3, "uc porsiyon")
	t.eq(inv.count("bottle_empty"), 1, "pisirmede kullanilan su sisesi geri doner")
	var tabs := Inventory.new(10.0, 10)
	tabs.add(ItemStack.new(Content.item("water_dirty"), 1, 0.0))
	tabs.add(ItemStack.new(Content.item("purification_tabs"), 1, 50.0))
	t.ok(service.craft(tabs, Content.recipes["r_purify_tablet"], "hands", 1).success, "tabletle sahada aritilir")


func test_spoilage_follows_world_time_and_survives_save(t) -> void:
	var inv := Inventory.new(80.0, 20)
	inv.add(ItemStack.new(Content.item("cooked_meal"), 2, 50.0))
	inv.add(ItemStack.new(Content.item("canned_food"), 2, 50.0))
	Survival.stamp(inv, 10.0)
	var meal := inv.find("cooked_meal")
	t.near(meal.expires, 10.0 + 36.0, 0.01, "son kullanma dunya saatiyle damgalanir")
	t.eq(inv.find("canned_food").expires, -1.0, "konserve bozulmaz")
	# Kayit/yukleme saati sifirlamaz.
	var restored := Inventory.new(80.0, 20)
	restored.load_dict(inv.to_dict(), Content.items)
	t.near(restored.find("cooked_meal").expires, 46.0, 0.01, "kayitta son kullanma korunur")
	t.eq(Survival.spoil(restored, 40.0), 0, "suresi dolmadan bozulmaz")
	t.eq(Survival.spoil(restored, 46.5), 2, "suresi dolunca bozulur")
	t.eq(restored.count("spoiled_food"), 2, "ayni adette bozuk yemek")
	t.eq(restored.count("cooked_meal"), 0, "taze yemek kalmadi")
	# Eski ve taze yemek birlesirse erken tarih kalir.
	var a := ItemStack.new(Content.item("cooked_meal"), 1, 50.0)
	a.expires = 20.0
	var b := ItemStack.new(Content.item("cooked_meal"), 1, 50.0)
	b.expires = 50.0
	a.merge(b)
	t.near(a.expires, 20.0, 0.01, "birlesen yiginda erken bozulma tarihi")


func test_old_save_gets_safe_defaults(t) -> void:
	var v := PlayerVitals.new()
	v.load_dict({"health": 70.0})
	t.near(v.satiety, 80.0, 0.01, "eski kayit tokluk varsayilani")
	t.near(v.hydration, 80.0, 0.01, "eski kayit su varsayilani")
	t.ok(v.hours_until("water") > 10.0, "yuklenen oyuncu hemen susamaz")
