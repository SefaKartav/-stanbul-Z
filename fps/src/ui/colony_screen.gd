class_name ColonyScreen
extends Screen
## Koloni ve us (L): us kurma, bina rolleri, sakin gorevleri, tarim,
## seferler, is emirleri.
##
## "Neden us kurulmuyor?" oyuncunun en sik yasayacagi an: kurma denemesi
## SESSIZ DEGILDIR; sebep ve en yakin acik gecitler (sizinti) gosterilir.

var left: VBoxContainer
var middle: VBoxContainer
var right: VBoxContainer


func _init() -> void:
	super._init()
	title = "Koloni ve Üs"
	toggle_action = "colony"


func _build_content() -> void:
	left = Screen.column(520)
	middle = Screen.column(560)
	right = Screen.column(520)
	for column: VBoxContainer in [left, middle, right]:
		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(scroll)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(column)
	footer.text = "Us: sokagin gecitlerini barikatla kapat, icinde dur ve 'Burada us kur' de. Binalara rol ver: Yatakhane olmadan kimse katilamaz."


func _clear(box: Container) -> void:
	for child in box.get_children():
		child.queue_free()


func refresh() -> void:
	_clear(left)
	_clear(middle)
	_clear(right)
	var bases: BaseSystem = game.bases
	var base: Settlement = bases.inside
	if base == null:
		_no_base(bases)
	else:
		_base_panel(bases, base)
		_residents_panel(bases, base)
		_orders_panel(bases, base)


func _no_base(bases: BaseSystem) -> void:
	left.add_child(UiTheme.label("Bir ussun icinde degilsin.", 24, UiTheme.ACCENT))
	left.add_child(UiTheme.label("Us = kapatilmis bir sokak parcasi. Binalar zaten duvardir; sokagin acik "
		+ "uclarini insa kipinde (B) barikat ya da duvarla kapat, sonra ortada dur.", 19))
	left.add_child(UiTheme.button("Burada us kur", func() -> void:
		var result: Dictionary = bases.try_found(game.player.global_position, game.time.day)
		if result.enclosed:
			game.hud.message("Us kuruldu! (%d m2)" % result.interior.size(), Hud.GREEN)
			game.show_leaks([])
		else:
			game.hud.message("Us kurulamadi: %s" % result.reason, Hud.RED)
			game.show_leaks(result.get("leaks", []))
		refresh()))
	var last: Dictionary = bases.last_result
	if not last.is_empty() and not last.get("enclosed", false):
		left.add_child(UiTheme.label("Son deneme: %s" % last.reason, 19, UiTheme.BAD))
		var leaks: Array = last.get("leaks", [])
		if not leaks.is_empty():
			left.add_child(UiTheme.label("Acik gecit yonleri dunyada kirmizi isaretle gosteriliyor (%d)." % leaks.size(), 18, UiTheme.MUTED))
	middle.add_child(UiTheme.label("Usler", 24, UiTheme.ACCENT))
	if bases.settlements.is_empty():
		middle.add_child(UiTheme.label("Henuz us yok. Olum, us yokken OYUNU BITIRIR.", 19, UiTheme.BAD))
	for other: Settlement in bases.settlements:
		var p := other.centre()
		var d := Vector2(p.x, p.z).distance_to(Vector2(game.player.global_position.x, game.player.global_position.z))
		middle.add_child(UiTheme.label("%s -- %d m uzakta%s, %d kisi" % [other.name, int(d),
			" (ACIK)" if other.breached else "", other.population], 19))


func _base_panel(bases: BaseSystem, base: Settlement) -> void:
	left.add_child(UiTheme.label("%s%s" % [base.name, "  -- ACIK! gecitleri kapat" if base.breached else ""], 26,
		UiTheme.BAD if base.breached else UiTheme.ACCENT))
	left.add_child(UiTheme.label("Alan: %d m2   Nufus: %d   Yatak: %d" % [base.area(), base.population,
		int(base.capacity("dorm"))], 19))
	left.add_child(UiTheme.label("Depo: %.0f / %.0f kg" % [base.stockpile.weight(), base.stockpile.capacity_kg], 19))
	for resource: Dictionary in Content.resources.resources.values():
		var stock := Content.resources.stock(base.stockpile, resource)
		var days := Content.resources.days_left(base.stockpile, resource, base.population, base.roles.size())
		var text := "%s: %.1f birim" % [resource.name, stock]
		text += "  (%s)" % ("sinirsiz" if is_inf(days) else "%.1f gun" % days)
		left.add_child(UiTheme.label(text, 19, UiTheme.BAD if days < 1.0 else UiTheme.TEXT))
	left.add_child(UiTheme.label("Bina rolleri (binaya girilmez; rol bir kapasitedir):", 20, UiTheme.ACCENT))
	for index: int in bases.adjacent_buildings(base):
		var b: Dictionary = game.registry.get_building(index)
		var row := HBoxContainer.new()
		var label := UiTheme.label("%s %s (%d m2)" % [Content.building_class(b.class).label, b.name, int(game.registry.area_m2(index))], 17)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var roles := OptionButton.new()
		for role: String in Settlement.ROLES:
			roles.add_item(Settlement.ROLE_LABELS[role])
		roles.select(Settlement.ROLES.find(base.role_of(b.id)))
		roles.item_selected.connect(func(i: int) -> void:
			bases.assign_role(base, b.id, Settlement.ROLES[i])
			refresh())
		row.add_child(roles)
		left.add_child(row)
	var farm := HBoxContainer.new()
	left.add_child(farm)
	farm.add_child(UiTheme.button("Tarla ek", func() -> void:
		game.hud.message(_tr(bases.colony.plant(base)), Hud.ACCENT)
		refresh()))
	farm.add_child(UiTheme.button("Hasat", func() -> void:
		game.hud.message(_tr(bases.colony.harvest(base)), Hud.ACCENT)
		refresh()))
	var plots := bases.colony.fields.filter(func(p: Dictionary) -> bool: return p.settlement_id == base.id)
	left.add_child(UiTheme.label("Tarla: %d (%s)" % [plots.size(), ", ".join(plots.map(func(p: Dictionary) -> String:
		return "%d/%d" % [p.growth, int(Content.colony.farming.growth_days)]))], 18))


func _residents_panel(bases: BaseSystem, base: Settlement) -> void:
	var colony := bases.colony
	middle.add_child(UiTheme.label("Sakinler", 24, UiTheme.ACCENT))
	var members := colony.members(base.id, false)
	if members.is_empty():
		middle.add_child(UiTheme.label("Kimse yok. Sehirde yardim bekleyenleri bul (telsiz yon gosterir), [E] ile ikna et, usse getir.", 19))
	var role_ids: Array = Content.colony.roles.keys().filter(func(r: String) -> bool: return r != "expedition")
	for r: Dictionary in members:
		middle.add_child(UiTheme.label("%s -- %s" % [r.name, r.background], 21, UiTheme.TEXT if r.health > 0 else UiTheme.MUTED))
		var skills := PackedStringArray()
		for skill: String in r.skills:
			skills.append("%s %d" % [skill, r.skills[skill]])
		middle.add_child(UiTheme.label("Can %d  Moral %d  Aclik %d  Susuzluk %d  Yorgunluk %d  |  %s" % [
			int(r.health), int(r.morale), int(r.hunger), int(r.thirst), int(r.fatigue), ", ".join(skills)], 16, UiTheme.MUTED))
		middle.add_child(UiTheme.label("Durum: %s" % _tr(r.status), 16, UiTheme.MUTED))
		if r.health <= 0 or r.role == "expedition":
			continue
		var roles := OptionButton.new()
		for role: String in role_ids:
			roles.add_item(Content.colony.roles[role].label)
		roles.select(role_ids.find(r.role))
		roles.item_selected.connect(func(i: int) -> void:
			colony.assign(r.id, role_ids[i])
			refresh())
		middle.add_child(roles)
	# Seferler
	middle.add_child(UiTheme.label("Sefer", 22, UiTheme.ACCENT))
	var cost := colony.expedition_cost(1)
	middle.add_child(UiTheme.label("Kisi basi azik: %.0f yiyecek, %.0f su (CIKISTA depodan alinir)." % [cost.food, cost.water], 17))
	var region_box := OptionButton.new()
	var region_ids: Array = Content.regions.keys()
	for region_id: String in region_ids:
		var region: Dictionary = Content.regions[region_id]
		region_box.add_item("%s (tehlike x%.1f, ganimet x%.1f)" % [region.name, region.danger_multiplier, region.loot_multiplier])
	middle.add_child(region_box)
	middle.add_child(UiTheme.button("Bosta olanlari sefere gonder", func() -> void:
		var idle := colony.members(base.id).filter(func(r: Dictionary) -> bool: return r.role == "idle").map(func(r: Dictionary) -> String: return r.id)
		var result := colony.launch_expedition(base, region_ids[maxi(0, region_box.selected)], idle)
		game.hud.message(_tr(result), Hud.ACCENT)
		refresh()))
	for exp: Dictionary in colony.expeditions:
		if exp.settlement_id == base.id:
			middle.add_child(UiTheme.label("%s: %s" % [exp.id, exp.report if exp.status != "active" else "suruyor (%d gun)" % exp.duration], 16))


func _orders_panel(bases: BaseSystem, base: Settlement) -> void:
	var colony := bases.colony
	right.add_child(UiTheme.label("Is emirleri", 24, UiTheme.ACCENT))
	right.add_child(UiTheme.label("Uretim ekranindan (C) 'is emri ver'. Zanaatkar gunde 1 adet uretir; malzemeyi ORTAK DEPODAN harcar.", 17))
	var orders: Array = colony.work_orders.orders
	for i in orders.size():
		var order: Dictionary = orders[i]
		if order.settlement_id != base.id:
			continue
		var recipe: RecipeDef = Content.recipes.get(order.recipe_id)
		var row := HBoxContainer.new()
		var text := "%s  %d/%d" % [recipe.name if recipe != null else order.recipe_id, order.done, order.quantity]
		if order.blocked != "":
			text += "  -- bekliyor: %s" % _tr(order.blocked)
		var label := UiTheme.label(text, 17, UiTheme.BAD if order.blocked != "" else UiTheme.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(UiTheme.button("Iptal", func() -> void:
			colony.work_orders.cancel(i)
			refresh()))
		right.add_child(row)
	right.add_child(UiTheme.label("Us adi", 20, UiTheme.ACCENT))
	var rename := LineEdit.new()
	rename.text = base.name
	rename.text_submitted.connect(func(text: String) -> void:
		base.name = text.strip_edges().left(24) if text.strip_edges() != "" else base.name
		refresh())
	right.add_child(rename)


static func _tr(key: String) -> String:
	const TEXT := {
		"colony.resting": "dinleniyor", "colony.assigned": "goreve atandi", "colony.working": "calisiyor",
		"colony.completed": "isini bitirdi", "colony.no_materials": "malzeme yok", "colony.stock_full": "depo dolu",
		"colony.no_workplace": "is yeri (bina rolu) yok", "colony.unsafe": "us acik/guvensiz",
		"colony.guarding": "nobette", "colony.tended": "tarlaya bakti", "colony.no_field": "tarla yok",
		"colony.no_water": "tarla icin su yok", "colony.no_patient": "hasta yok", "colony.dead": "olu",
		"colony.expedition": "seferde", "colony.planted": "Tarla ekildi", "colony.no_seed": "Tohum yok (depoda)",
		"colony.no_space": "Tarla icin yer yok", "colony.not_ready": "Hasat icin hazir tarla yok",
		"colony.harvested": "Hasat yapildi", "colony.recruited": "Katildi", "colony.no_beds": "Yatak yok",
		"colony.unavailable": "Uygun degil", "colony.invalid_region": "Gecersiz bolge",
		"colony.no_members": "Gonderilecek bosta sakin yok", "colony.no_supplies": "Sefer icin azik yetmiyor",
		"colony.expedition_launched": "Sefer basladi", "workorder.blocked": "engellendi",
		"workorder.unknown_recipe": "bilinmeyen tarif",
	}
	return TEXT.get(key, key)
