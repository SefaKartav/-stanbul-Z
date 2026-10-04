extends RefCounted
## Crafting kurallari: tag girdisi, kalite secimi, tek islem guvenligi.
## Python tests/ altindaki crafting testlerinin davranis karsiliklari.


func _stack(item_id: String, amount: int, quality: float = 50.0) -> ItemStack:
	return ItemStack.new(Content.item(item_id), amount, quality)


func test_content_loads_without_errors(t) -> void:
	t.ok(Content.ok(), "icerik hatasiz yuklenmeli: %s" % [Content.errors])
	t.ok(Content.items.size() >= 100, "en az 100 esya")
	t.ok(Content.recipes.size() >= 50, "en az 50 tarif")


func test_tag_query_accepts_any_matching_item(t) -> void:
	# r_lockpick: 2x #wire -- bakir tel de celik tel de karsilar.
	var recipe: RecipeDef = Content.recipes["r_lockpick"]
	var service := CraftingService.new(Content.items)
	var bag := Inventory.new()
	bag.add(_stack("copper_wire", 1))
	bag.add(_stack("wire_steel", 1))
	var check := service.check(bag, recipe, "hands", 1)
	t.ok(check.ok, "iki farkli tel tag'i birlikte karsilamali: %s" % check.reason)


func test_lowest_quality_is_consumed_first(t) -> void:
	var bag := Inventory.new()
	bag.add(_stack("insulated_wire", 3, 80.0))
	bag.add(_stack("insulated_wire", 3, 10.0))
	var taken := bag.remove("insulated_wire", 2)
	t.eq(taken.size(), 1)
	t.near(taken[0].quality, 10.0, 0.01, "once hurda kalite harcanmali")
	t.eq(bag.count("insulated_wire"), 4)


func test_min_quality_filters_inputs(t) -> void:
	var recipe: RecipeDef = Content.recipes["r_medkit"]
	var service := CraftingService.new(Content.items)
	var bag := Inventory.new()
	bag.add(_stack("antiseptic", 2, 10.0))   # esik 25, yetmez
	bag.add(_stack("sterile_cloth", 3))
	bag.add(_stack("painkiller", 2))
	bag.add(_stack("adhesive_compound", 1))
	var check := service.check(bag, recipe, "workbench", 2)
	t.ok(not check.ok, "dusuk kaliteli antiseptik kabul edilmemeli")
	bag.add(_stack("antiseptic", 2, 60.0))
	check = service.check(bag, recipe, "workbench", 2)
	t.ok(check.ok, "esigi gecen antiseptikle yapilabilmeli: %s" % check.reason)


func test_station_and_tier_required(t) -> void:
	var recipe: RecipeDef = Content.recipes["r_medkit"]
	var service := CraftingService.new(Content.items)
	var bag := Inventory.new()
	t.ok(not service.check(bag, recipe, "hands", 1).ok, "elle yapilamamali")
	t.ok(not service.check(bag, recipe, "workbench", 1).ok, "T1 tezgah yetmemeli")


func test_tool_is_not_consumed(t) -> void:
	var recipe: RecipeDef = Content.recipes["r_workbench_kit"]
	var service := CraftingService.new(Content.items, 7)
	var bag := Inventory.new(999.0, 60)
	bag.add(_stack("wood_plank", 8))
	bag.add(_stack("scrap_metal", 6))
	bag.add(_stack("nail", 12))
	bag.add(_stack("toolkit", 1, 60.0))
	var result := service.craft(bag, recipe, "hands", 1)
	t.ok(result.success, "tezgah uretilmeli: %s" % result.reason)
	t.eq(bag.count("toolkit"), 1, "takim cantasi harcanmamali")
	t.eq(bag.count("wood_plank"), 0, "tahtalar harcanmali")
	t.eq(bag.count("workbench_kit"), 1)


func test_craft_is_atomic_when_output_does_not_fit(t) -> void:
	var recipe: RecipeDef = Content.recipes["r_lockpick"]
	var service := CraftingService.new(Content.items)
	# Tek yuvalik canta: tel yiginlari yuvayi doldurur, urun sigmaz.
	var bag := Inventory.new(999.0, 1)
	bag.add(_stack("copper_wire", 3))
	var result := service.craft(bag, recipe, "hands", 1)
	t.ok(not result.success, "urun sigmiyorsa uretim reddedilmeli")
	t.eq(bag.count("copper_wire"), 3, "reddedilen uretim girdileri harcamamali")


func test_quality_is_weighted_average(t) -> void:
	var recipe: RecipeDef = Content.recipes["r_lockpick"]
	var service := CraftingService.new(Content.items)
	var bag := Inventory.new()
	bag.add(_stack("insulated_wire", 1, 90.0))
	bag.add(_stack("insulated_wire", 1, 10.0))
	var check := service.check(bag, recipe, "hands", 1)
	# (90 + 10) / 2 = 50 + istasyon T1 (6) = 56
	t.near(check.predicted_quality, 56.0, 0.01, "agirlikli ortalama + istasyon bonusu")


func test_disassemble_returns_less_than_input(t) -> void:
	var service := CraftingService.new(Content.items)
	var bag := Inventory.new(999.0, 60)
	bag.add(_stack("toolkit", 1, 60.0))
	var toolkit: ItemStack = bag.find("toolkit")
	var result := service.disassemble(bag, toolkit, Content.recipes, Content.graph.produced_by)
	t.ok(result.success, "takim cantasi sokulebilmeli: %s" % result.reason)
	t.eq(bag.count("toolkit"), 0)
	var wood := bag.count("wood_plank")
	t.ok(wood >= 1 and wood < 2, "2 tahtanin %%55'i geri gelmeli (1), gelen %d" % wood)


func test_graph_has_no_unreachable_items(t) -> void:
	var errors := Content.graph.validate().filter(func(i: Dictionary) -> bool: return i.severity == "error")
	t.eq(errors.size(), 0, "grafik hatasi: %s" % [errors])


func test_loot_table_rolls_real_items(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var table: LootTable = Content.loot_tables["pharmacy"]
	var found := 0
	for _i in 20:
		for stack: ItemStack in table.roll(Content.items, rng):
			t.ok(stack.definition != null and stack.quantity > 0)
			found += 1
	t.ok(found > 0, "eczane tablosu bir sey dusurmeli")
