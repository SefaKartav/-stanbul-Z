extends RefCounted
## Koloni kurallari (Python tests/test_colony*.py davranis karsiliklari).


func _base() -> Settlement:
	var base := Settlement.new()
	base.id = "base1"
	base.name = "Deneme"
	for x in 20:
		for z in 20:
			base.interior[Vector2i(x, z)] = 0
	base.roles = {"b_dorm": "dorm", "b_work": "workshop", "b_kitchen": "kitchen"}
	base.building_scales = {"b_dorm": 3.0, "b_work": 1.0, "b_kitchen": 1.0}
	base.stockpile = Inventory.new(999.0, 200)
	return base


func _stack(id: String, n: int, q: float = 50.0) -> ItemStack:
	return ItemStack.new(Content.item(id), n, q)


func test_day_is_processed_once(t) -> void:
	var base := _base()
	var colony := Colony.new([base])
	colony.recruit(base, "murat")
	colony.assign("murat", "crafter")
	base.stockpile.add(_stack("sterile_cloth", 10))
	base.stockpile.add(_stack("duct_tape", 10))
	colony.advance_day(2, {})
	var after_first := base.stockpile.count("bandage_clean")
	colony.advance_day(2, {})
	t.eq(base.stockpile.count("bandage_clean"), after_first, "ayni gun ikinci kez uretim olmamali")
	t.ok(after_first > 0, "zanaatkar uretmeli")


func test_crafter_consumes_real_inputs(t) -> void:
	var base := _base()
	var colony := Colony.new([base])
	colony.recruit(base, "murat")
	colony.assign("murat", "crafter")
	base.stockpile.add(_stack("sterile_cloth", 1))
	base.stockpile.add(_stack("duct_tape", 1))
	colony.advance_day(2, {})
	t.eq(base.stockpile.count("sterile_cloth"), 0, "girdi depodan harcanmali")
	t.eq(base.stockpile.count("bandage_clean"), 3)


func test_work_order_uses_stockpile_and_recipe(t) -> void:
	var base := _base()
	var colony := Colony.new([base])
	colony.recruit(base, "murat")
	colony.assign("murat", "crafter")
	colony.work_orders.add("r_lockpick", 2, base.id)
	base.stockpile.add(_stack("copper_wire", 4))
	colony.advance_day(2, {})
	t.eq(base.stockpile.count("lockpick"), 3, "is emri tarifi gercekten uretmeli")
	t.eq(base.stockpile.count("copper_wire"), 2, "tarif girdisi depodan harcanmali")
	t.eq(int(colony.work_orders.orders[0].done), 1, "gunde tek adet")


func test_full_stockpile_loses_nothing(t) -> void:
	var base := _base()
	# 3 yuva: girdiler harcansa da yiginlar kalir, urun icin yer olmaz.
	base.stockpile = Inventory.new(999.0, 3)
	var colony := Colony.new([base])
	colony.recruit(base, "murat")
	colony.assign("murat", "crafter")
	base.stockpile.add(_stack("sterile_cloth", 2))
	base.stockpile.add(_stack("duct_tape", 2))
	base.stockpile.add(_stack("scrap_metal", 1))
	colony.advance_day(2, {})
	t.eq(base.stockpile.count("sterile_cloth"), 2, "depo doluysa girdi kaybolmamali")
	t.eq(colony.residents.murat.status, "colony.stock_full")


func test_harvest_returns_seed(t) -> void:
	var base := _base()
	var colony := Colony.new([base])
	base.stockpile.add(_stack("vegetable_seeds", 2))
	base.stockpile.add(_stack("water_canister", 20))
	t.eq(colony.plant(base), "colony.planted")
	colony.recruit(base, "zeynep")
	colony.assign("zeynep", "farmer")
	for day in range(2, 6):
		colony.advance_day(day, {})
	t.eq(colony.harvest(base), "colony.harvested")
	t.ok(base.stockpile.count("dry_goods") >= 9, "urun gelmeli")
	t.ok(base.stockpile.count("vegetable_seeds") >= 2, "tohum geri donmeli (dongu kapanir)")


func test_starving_resident_eventually_leaves_with_supplies(t) -> void:
	var base := _base()
	var colony := Colony.new([base])
	colony.recruit(base, "deniz")
	base.stockpile.add(_stack("canned_food", 10))
	colony.residents.deniz.morale = 10.0
	var trace := PackedStringArray()
	for day in range(2, 8):
		if colony.residents.has("deniz"):
			colony.advance_day(day, {"base1": {"food": true}})
			if colony.residents.has("deniz"):
				var r: Dictionary = colony.residents.deniz
				trace.append("g%d m%.0f d%d h%.0f" % [day, r.morale, r.low_morale_days, r.health])
	t.ok(not colony.residents.has("deniz"), "morali dipte kalan sakin gitmeli: %s" % [trace])


func test_no_beds_no_recruit(t) -> void:
	var base := _base()
	base.roles = {}
	var colony := Colony.new([base])
	t.eq(colony.recruit(base, "ayse"), "colony.no_beds", "yatakhane yoksa katilamaz")
