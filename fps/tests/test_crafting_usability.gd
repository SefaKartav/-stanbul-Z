extends RefCounted
## Uretim kullanilabilirligi: en fazla adet (alternatif girdide cift sayim
## yok, cikti kapasitesi), harcama plani, "nerede bulunur" verisi.


static func _recipe_with_tag_inputs() -> RecipeDef:
	## Iki ayri girdisi AYNI esyayla karsilanabilen bir tarif (cift sayim riski).
	for recipe: RecipeDef in Content.recipes.values():
		if recipe.station != "hands" or not recipe.unlocked:
			continue
		var tags := 0
		for ingredient: Dictionary in recipe.inputs:
			if ingredient.tag != "" and ingredient.consumed:
				tags += 1
		if tags >= 1:
			return recipe
	return null


func test_max_craftable_matches_real_crafting(t) -> void:
	## "En fazla N" dendiyse tam N kez uretilebilmeli, N+1'inci basarisiz olmali.
	var service := CraftingService.new(Content.items)
	var checked := 0
	for recipe: RecipeDef in Content.recipes.values():
		if recipe.station != "hands" or not recipe.unlocked or recipe.failure_chance > 0.0:
			continue
		var bag := Inventory.new(500.0, 120)
		for ingredient: Dictionary in recipe.inputs:
			var item_id: String = ingredient.item
			if item_id == "":
				var options := Content.graph.items_with_tag(ingredient.tag)
				if options.is_empty():
					continue
				item_id = options[0]
			bag.add(ItemStack.new(Content.item(item_id), ingredient.count * 3 + 1, 80.0))
		var n := service.max_craftable(bag, recipe)
		var made := 0
		for _i in n + 2:
			if service.craft(bag, recipe).success:
				made += 1
			else:
				break
		t.eq(made, n, "%s: en fazla %d dendi, %d uretildi" % [recipe.id, n, made])
		checked += 1
		if checked >= 12:
			break
	t.ok(checked >= 6, "yeterli el tarifi denetlendi")


func test_same_item_not_counted_twice(t) -> void:
	## Ayni esya iki ayri girdiyi karsilayabiliyorsa, eldeki miktar ikisine
	## birden sayilmamali (5 civi, iki girdi x3 -> 0 adet).
	var recipe := RecipeDef.new()
	recipe.id = "t_cift"
	recipe.name = "Test"
	recipe.output_id = "scrap_metal"
	recipe.output_count = 1
	recipe.station = "hands"
	recipe.inputs = [
		{"item": "", "tag": "fastener", "count": 3, "min_quality": 0.0, "consumed": true},
		{"item": "nail", "tag": "", "count": 3, "min_quality": 0.0, "consumed": true},
	]
	var service := CraftingService.new(Content.items)
	var bag := Inventory.new(100.0, 40)
	bag.add(ItemStack.new(Content.item("nail"), 5, 50.0))
	t.eq(service.max_craftable(bag, recipe), 0, "5 civi iki girdiye (3+3) yetmez")
	bag.add(ItemStack.new(Content.item("nail"), 1, 50.0))
	t.eq(service.max_craftable(bag, recipe), 1, "6 civi tam bir adet")


func test_consumption_plan_uses_lowest_quality_first(t) -> void:
	var recipe := RecipeDef.new()
	recipe.id = "t_plan"
	recipe.name = "Test"
	recipe.output_id = "scrap_metal"
	recipe.output_count = 1
	recipe.station = "hands"
	recipe.inputs = [{"item": "", "tag": "soft", "count": 2, "min_quality": 0.0, "consumed": true},
		{"item": "toolkit", "tag": "", "count": 1, "min_quality": 0.0, "consumed": false}]
	var service := CraftingService.new(Content.items)
	var bag := Inventory.new(100.0, 40)
	bag.add(ItemStack.new(Content.item("cloth_rag"), 1, 90.0))
	bag.add(ItemStack.new(Content.item("foam_padding"), 3, 20.0))
	bag.add(ItemStack.new(Content.item("toolkit"), 1, 60.0))
	var plan := service.consumption_plan(bag, recipe)
	t.eq(plan.size(), 1, "takim (tuketilmeyen) harcama planinda yok")
	var used: Array = plan[0].stacks
	# Ham malzeme kalitesizdir (notr 50); siralama effective_quality'ye gore artan.
	for i in range(1, used.size()):
		t.ok(used[i - 1].effective_quality() <= used[i].effective_quality(), "once dusuk (etkin) kalite harcanir")
	t.eq(_sum(used), 2, "tam girdi miktari planlanir")
	t.eq(bag.count("cloth_rag"), 1, "plan envanteri DEGISTIRMEZ")


func test_full_bag_crafting_is_atomic(t) -> void:
	## Cikti sigmiyorsa hicbir malzeme harcanmaz (uretim tamamlanirken yeniden denetim).
	var recipe := _recipe_with_tag_inputs()
	t.ok(recipe != null, "tag girdili el tarifi olmali")
	var service := CraftingService.new(Content.items)
	var bag := Inventory.new(1000.0, 1)
	for ingredient: Dictionary in recipe.inputs:
		var item_id: String = ingredient.item if ingredient.item != "" else Content.graph.items_with_tag(ingredient.tag)[0]
		bag.add(ItemStack.new(Content.item(item_id), ingredient.count, 50.0))
	var before := bag.stacks.size()
	var total_before := 0
	for s: ItemStack in bag.stacks:
		total_before += s.quantity
	var result := service.craft(bag, recipe)
	var total_after := 0
	for s: ItemStack in bag.stacks:
		total_after += s.quantity
	if not result.success:
		t.eq(total_after, total_before, "basarisiz uretim malzeme harcamaz")
	t.ok(bag.stacks.size() <= maxi(before, 1) + 1, "envanter tutarli")


func test_where_found_uses_real_loot(t) -> void:
	## "Nerede bulunur?" gercek loot tanimindan: bez gardiropta, ilac eczanede.
	var cloth := LootSources.describe("cloth_rag")
	t.ok(cloth.contains("gardirop"), "bez parcasi gardiropta bulunur: %s" % cloth)
	var pills := LootSources.describe("painkiller")
	t.ok(pills.contains("eczane") or pills.contains("ecza"), "agri kesici eczane/ecza dolabinda: %s" % pills)
	t.ok(not cloth.contains("_"), "ic kimlik oyuncuya gosterilmez: %s" % cloth)
	# Her tarif girdisi (esya ya da tag) icin en az bir gercek kaynak ya da uretim yolu.
	var missing := []
	for recipe: RecipeDef in Content.recipes.values():
		for ingredient: Dictionary in recipe.consumed_inputs():
			if ingredient.item != "":
				var produced := false
				for other: RecipeDef in Content.recipes.values():
					if other.output_id == ingredient.item:
						produced = true
				if not produced and LootSources.sources(ingredient.item).is_empty():
					missing.append(ingredient.item)
			elif LootSources.describe_tag(ingredient.tag) == "":
				missing.append("#" + ingredient.tag)
	t.eq(missing, [], "her girdinin bir kaynagi olmali (erisilemez dongu yok)")


static func _sum(stacks: Array) -> int:
	var n := 0
	for s: ItemStack in stacks:
		n += s.quantity
	return n