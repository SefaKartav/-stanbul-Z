class_name Game
extends Node3D
## Oyun sahnesi: dunya, oyuncu, sistemler ve arayuzu bir araya getirir.
##
## Sorumluluklar AYRI dosyalardadir (voxel/, player/, combat/, ai/, base/,
## crafting/, save/, ui/). Bu dosya BAGLAR ve sabit adimli simulasyonu
## surer; kural kodu icermemelidir.
##
## Komut satiri (`--` sonrasi; teshis ve otomatik ekran goruntusu icin):
##   --site=maltepe_besiktas|kadikoy|test   --pose=x,y,z,yaw,pitch   --zombies=<n>
##   --shot=<yol.png>  --shot-delay=<sn>  --script=<ad>  --load=<yuva>
##   --screen=craft|inventory|pause|map|colony|skills|journal  (acilista ekran ac)

signal world_ready
signal request_main_menu
signal request_restart(load_slot: String)

const DEATH_LOST_HOURS := 48.0
const DEATH_WAKE_HEALTH := 0.35
const AUTOSAVE_INTERVAL := 180.0
const BASE_CAPACITY_KG := 45.0

var load_slot := ""                   # Main tarafindan, sahneye eklenmeden once
var start_site := ""                  # testler icin: komut satirindan bagimsiz harita
var save_directory := ""              # testler icin: gercek kayit klasorune yazma
var world: VoxelWorld
var terrain: VoxelTerrain
var bridge_decor: BridgeDecor          # yalnizca buyuk koprulu haritada
var generator: Object
var environment_node: GameEnvironment
var player: Player
var vitals := PlayerVitals.new()
var inventory := Inventory.new(45.0, 80)
var progression := Progression.new()
var skills := SkillProfile.new()
var actors := ActorRegistry.new()
var hitscan: Hitscan
var combat: PlayerCombat
var weapon_view: WeaponView
var view_layer: WeaponView.ViewModelLayer
var effects: Effects
var sfx: Sfx
var pickups: WorldPickups
var zombies: ZombieManager
var population: Population            # sabit haritada kalici bolgesel nufus (yoksa null)
var nav: NavGrid
var time := TimeOfDay.new()
var waves := WaveSchedule.new()
var flashlight: SpotLight3D
var registry: BuildingRegistry
var containers: ContainerRegistry     # aranabilir mobilyalarin kalici durumu
var interiors: InteriorView           # yakin binalarin ic mekan gorseli + kapilar
var search: SearchSystem
var bases: BaseSystem
var placeables: Placeables
var survivors: SurvivorManager
var build: BuildMode
var abilities: Abilities
var vehicles: Vehicles
var throwables: Throwables
var survival: Survival                # kisisel aclik/susuzluk, bozulma, su kaynaklari
var props: WorldProps                 # cesme, sadirvan, gorev nesneleri (GLB + kutu carpisma)
var quests: QuestSystem               # gorev omurgasi (ana hedef: hayatta kalan agi)
var equipment := {"armor": null, "helmet": null, "mask": null, "backpack": null, "clothing": null, "lamp": null}
var power: PowerGrid                  # elektrik aglari (yerlestirilebilirler)
var gathering: Gathering              # alet ile kaynak toplama
var craft_queue: Array = []           # bekleyen uretim isleri (ilki craft_job olarak calisir)
const CRAFT_QUEUE_MAX := 8
var _farm_timer := 0.0
var _binocular_active := false
var _power_warned := false
var region_id := ""
var _region_timer := 0.0
var crafting := CraftingService.new(Content.items)
var craft_job: Dictionary = {}
var craft_done_last := 0            # son uretim isinde tamamlanan adet (ekran icin)
var saves := SaveSystem.new()
var load_failed := false
var map_id := "test"
var map_name := ""
var generator_version := 1
var waypoint := Vector3.INF
var hud: Hud
var crosshair: Crosshair
var hud_layer: CanvasLayer
var screen_layer: CanvasLayer
var debug_label: Label
var perf := PerfMonitor.new()
var site := "yeni_istanbul"          # yeni oyunun haritasi: sabit kurgusal 10x10 km sehir.
                                     # Eski kayitlar kendi haritasini (maltepe_besiktas, kadikoy) acar.
var ready_for_play := false
var ui_open := false
var current_screen: Screen
var _args := {}
var _shot_timer := -1.0
var _salvage_rng := RandomNumberGenerator.new()
var _interaction: Dictionary = {}
var _action: Dictionary = {}
var _autosave_timer := AUTOSAVE_INTERVAL
var _boot_time := 0.0
var _leak_markers: Array = []
var _leak_timer := 0.0
var _death_handled := false
var _pending_load: Dictionary = {}
var _bench_drive := Vector2.INF        # olcumde arac girdisi (gaz, direksiyon)
var _drive_look_offset := 0.0          # aractayken bakisin burna gore acisi
var _drive_look_idle := 0.0            # fare en son ne zaman oynadi (sn)
var _exit_frame := -1                  # aractan inilen fizik karesi
const DRIVE_LOOK_LIMIT := 1.92         # 110 derece
var _migrated := false                 # eski surum kayit yuklendi (bos nokta aranir)
var _migration_report: Dictionary = {}  # olcek gocu raporu (kayit acilisinda)


# ---------------------------------------------------------------------------
# Kurulum
# ---------------------------------------------------------------------------
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_parse_args()
	if save_directory != "":
		saves.directory = save_directory
	if start_site != "":
		site = start_site
	if _args.has("load"):
		load_slot = str(_args.load)
	# Kayit yukleniyorsa HARITAYI kayit belirler.
	if load_slot != "":
		_pending_load = saves.read(load_slot)
		if _pending_load.is_empty():
			load_failed = true
		else:
			site = str(_pending_load.get("world", {}).get("site", site))
	if start_site == "":
		site = _args.get("site", site)
	_salvage_rng.randomize()
	skills = SkillProfile.new(Content.skills, progression.ranks)
	_setup_world()
	_setup_systems()
	_build_hud()
	if not _pending_load.is_empty():
		var problem := saves.check_compatible(_pending_load, map_id, generator_version)
		if problem != "":
			# Uyumsuz kayit ACILMAZ ve dosya korunur; yeni oyun baslamaz.
			load_failed = true
			hud.message(problem, Hud.RED)
			_pending_load = {}
			call_deferred("_fail_to_menu", problem)
			return
		if generator is CityGenerator and SaveMigration.applies(_pending_load, map_id, generator_version):
			# Kaynak kayit dokunulmadan yedeklenir; goc bellekteki kopyada yapilir.
			var backup := saves.backup_copy(load_slot, "_olcek065_yedek")
			var report := SaveMigration.migrate(_pending_load, generator)
			_migrated = true
			_migration_report = report
			_migration_report["backup"] = ProjectSettings.globalize_path(backup) if backup != "" else ""
		_apply_save(_pending_load)
		if not _migration_report.is_empty():
			_announce_migration()
		if saves.last_error != "":
			hud.message(saves.last_error, Hud.ACCENT)
	elif load_slot != "":
		call_deferred("_fail_to_menu", "Kayit acilamadi: %s" % saves.last_error)
		return
	else:
		_give_start_kit()
		if site == "test":
			_spawn_range_targets()
	if _args.has("shot"):
		_shot_timer = float(_args.get("shot-delay", "1.0"))


func _announce_migration() -> void:
	var r := _migration_report
	var dropped: Dictionary = r.get("dropped", {})
	hud.message("Eski kayit 1:1 haritaya tasindi: konumun cografi olarak ayni yerde (%s)." % map_name, Hud.ACCENT)
	hud.message("Tasinamayan: %d degismis blok, %d hasarli blok (yeni izgara), %d zombi (yeniden dogar)." % [
		int(dropped.get("modified_cells", 0)), int(dropped.get("damaged_cells", 0)), int(dropped.get("zombies", 0))], Hud.ACCENT)
	if str(r.get("backup", "")) != "":
		hud.message("Orijinal kayit korunuyor: %s" % str(r.backup).get_file(), Hud.GREEN)
	if progression.migrated_points > 0:
		hud.message("Eski beceri rutbeleri %d puan olarak iade edildi -- beceri agacinda (K) yeniden dagit." % progression.migrated_points, Hud.GREEN)
	print("GOC RAPORU ", JSON.stringify(r))


func _fail_to_menu(reason: String) -> void:
	if get_parent() != null and get_parent().has_method("show_error"):
		get_parent().call("show_error", reason)
	request_main_menu.emit()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	# Olcum icin grafik on ayari (--preset=0|1|2): kullanicinin kayitli
	# ayarlarina YAZILMAZ, yalnizca bu calistirmada gecerli.
	if _args.has("preset"):
		var p: Array = Settings.PRESETS[clampi(int(_args.preset), 0, Settings.PRESETS.size() - 1)]
		Settings.shadow_quality = int(p[0])
		Settings.aa_mode = int(p[1])
		Settings.view_distance = int(p[2])
	if _args.has("aa"):
		Settings.aa_mode = clampi(int(_args.aa), 0, 3)
	if _args.has("legacy-look"):
		# Once/sonra karsilastirmasi icin 26 Eylul gorunumu (AA yok, sert golge).
		Settings.legacy_look = true
		Settings.soft_look = false
		Settings.aa_mode = 0


func _setup_world() -> void:
	world = VoxelWorld.new(Content.blocks)
	var map_path := "res://data/map/%s.json" % site
	if site != "test" and FileAccess.file_exists(map_path):
		var city := CityGenerator.new(Content.blocks, map_path)
		generator = city
		map_id = city.map_id
		map_name = str(city.data.get("name", city.map_id))
		generator_version = CityGenerator.GENERATOR_VERSION
		registry = BuildingRegistry.new(city)
		containers = ContainerRegistry.new(city)
		registry.containers = containers
		search = SearchSystem.new(containers)
		search.skills = skills
	else:
		site = "test"
		map_id = "test"
		map_name = "Test sahasi"
		generator = TestSiteGenerator.new(Content.blocks)
	generator.configure(world)
	QuestSystem.localize(map_id)

	environment_node = GameEnvironment.new()
	add_child(environment_node)
	terrain = VoxelTerrain.new()
	terrain.name = "Terrain"
	terrain.view_radius = Settings.view_distance
	add_child(terrain)
	terrain.setup(world, generator)
	if generator is CityGenerator and not (generator as CityGenerator).bridges.is_empty():
		bridge_decor = BridgeDecor.new()
		bridge_decor.name = "BridgeDecor"
		add_child(bridge_decor)
		bridge_decor.setup(generator, terrain.view_radius * 16.0)
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	## Gorus mesafesi oyun icinde degisince chunk akis yaricapi da degismeli
	## (sis GameEnvironment'ta zaten guncelleniyordu; akis eskiden yeniden
	## baslatmayi bekliyordu).
	if terrain.view_radius != Settings.view_distance:
		terrain.set_view_radius(Settings.view_distance)
	if bridge_decor != null:
		bridge_decor.set_reach(terrain.view_radius * 16.0)


func _setup_systems() -> void:
	effects = Effects.new()
	add_child(effects)
	sfx = Sfx.new()
	add_child(sfx)
	pickups = WorldPickups.new()
	add_child(pickups)

	player = Player.new()
	player.name = "Player"
	player.world = world
	add_child(player)
	player.position = generator.spawn_point()
	if _args.has("pose"):
		var p: PackedStringArray = str(_args.pose).split(",")
		if p.size() >= 5:
			player.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			player.yaw = deg_to_rad(float(p[3]))
			player.pitch = deg_to_rad(float(p[4]))
	terrain.focus = player.position
	player.footstep.connect(_on_footstep)
	player.landed.connect(func(speed: float) -> void:
		if speed > 13.0:
			# Yuksekten dusme: 4 m ustu can goturur (Cati kosucusu yariya indirir).
			vitals.take_hit((speed - 13.0) * 6.0 * skills.multiplier("fall_damage"), "true", Vector3.DOWN))

	hitscan = Hitscan.new(world, actors)
	weapon_view = WeaponView.new()
	view_layer = WeaponView.ViewModelLayer.new()
	add_child(view_layer)
	view_layer.setup(player.camera)
	view_layer.attach(weapon_view)
	crosshair = Crosshair.new()
	combat = PlayerCombat.new()
	add_child(combat)
	combat.skills = skills
	combat.setup(player, weapon_view, inventory, hitscan, actors, effects, sfx, crosshair)
	combat.message.connect(func(text: String) -> void: hud.message(text, Hud.ACCENT))
	combat.block_destroyed.connect(_on_block_destroyed)
	combat.noise.connect(on_noise_at)
	combat.actor_hit.connect(_on_actor_hit)
	vitals.damaged.connect(_on_player_damaged)
	vitals.died.connect(_on_player_died)

	nav = NavGrid.new(world, generator.ground_height)
	zombies = ZombieManager.new()
	add_child(zombies)
	zombies.setup(world, nav, actors, sfx, effects, generator.ground_height)
	if generator is CityGenerator:
		var city_gen: CityGenerator = generator
		zombies.indoor_column = func(x: int, z: int) -> bool: return city_gen.column_info(x, z).kind == "building"
		if not city_gen.districts.is_empty() and not _args.has("zombies"):
			population = Population.new()
			population.name = "Population"
			add_child(population)
			population.setup(city_gen, zombies, city_gen.spawn_point())
			zombies.enabled = false
	zombies.player_struck.connect(_on_zombie_strike)
	zombies.npc_struck.connect(func(_z: Zombie, npc: Object, amount: float) -> void:
		npc.receive_damage(amount, "physical", Vector3.ZERO, Vector3.ZERO, null, "body"))
	zombies.block_attacked.connect(func(cell: Vector3i, destroyed: bool) -> void:
		if destroyed and bases.settlement_at(Vector3(cell)) != null:
			hud.message("Zombiler bir barikati yikti!", Hud.RED))

	flashlight = SpotLight3D.new()
	flashlight.spot_range = 28.0
	flashlight.spot_angle = 28.0
	flashlight.light_energy = 2.2
	flashlight.light_color = Color(1.0, 0.94, 0.82)
	flashlight.shadow_enabled = true
	flashlight.visible = false
	flashlight.position = Vector3(0.18, -0.12, 0.0)
	player.camera.add_child(flashlight)

	if search != null:
		search.noise.connect(on_noise_at)
		search.completed.connect(_on_container_searched)
		search.interrupted.connect(func(reason: String) -> void:
			if reason != "":
				hud.message(reason, Hud.RED))
		interiors = InteriorView.new()
		interiors.name = "Interiors"
		add_child(interiors)
		interiors.setup(generator, world, containers, func() -> int: return time.day)
		# Ic mekan ve kabin modelleri arka planda yuklenmeye baslar (ilk binada takilma olmasin).
		AssetLibrary.warm(["models/containers/", "models/interiors/", "models/props/", "models/characters/",
			"models/district_identity/", "models/water_food/", "models/mission_props/",
			"models/vehicles_open/", "models/vehicle_interiors/"])
		interiors.container_destroyed.connect(func(debris: Array, at: Vector3, label: String) -> void:
			if not debris.is_empty():
				pickups.spawn(debris, at, label, "remnant")
				hud.message("%s kirildi -- icindekiler yere dustu" % label.trim_prefix("Enkaz: "), Hud.ACCENT))
		interiors.door_broken.connect(func(_at: Vector3) -> void: hud.message("Kapi kirildi", Hud.ACCENT))

	bases = BaseSystem.new()
	add_child(bases)
	bases.setup(world, nav, registry)
	bases.colony.colony_skills = skills
	bases.founded.connect(func(base: Settlement) -> void:
		hud.message("%s kuruldu. Binalara rol ver (L). Olumde artik burada uyanirsin." % base.name, Hud.GREEN))
	bases.breached.connect(func(base: Settlement) -> void:
		hud.message("%s ACILDI! Zombiler iceri girebilir -- gecidi kapat." % base.name, Hud.RED))
	bases.restored.connect(func(base: Settlement) -> void:
		hud.message("%s yeniden kapali." % base.name, Hud.GREEN))
	bases.message.connect(func(text: String, color: Color) -> void: hud.message(text, color))

	placeables = Placeables.new()
	add_child(placeables)
	placeables.setup(world)
	power = PowerGrid.new(placeables)
	placeables.destroyed.connect(func(entry: Dictionary) -> void:
		hud.message("%s yıkıldı!" % placeables.label_of(entry), Hud.RED)
		_sync_colony_capacity())
	placeables.changed.connect(_sync_colony_capacity)
	gathering = Gathering.new(world)
	combat.gathering = gathering
	combat.harvested.connect(_on_harvested)
	survivors = SurvivorManager.new()
	add_child(survivors)
	survivors.setup(world, actors, bases, hitscan, effects, sfx, registry)
	survivors.noise_callback = on_noise_at
	survivors.message.connect(func(text: String, color: Color) -> void: hud.message(text, color))

	throwables = Throwables.new()
	add_child(throwables)
	throwables.setup(self)
	# Sema bilgisi oyuncu ile zanaatkar arasinda PAYLASILIR.
	bases.colony.crafting.known_recipes = crafting.known_recipes

	vehicles = Vehicles.new()
	add_child(vehicles)
	vehicles.setup(world, actors)
	vehicles.message.connect(func(text: String, color: Color) -> void: hud.message(text, color))
	survival = Survival.new(self)
	vitals.need_warning.connect(func(text: String, urgent: bool) -> void:
		hud.message(text, Hud.RED if urgent else Hud.ACCENT))
	props = WorldProps.new()
	props.name = "WorldProps"
	add_child(props)
	if generator is CityGenerator:
		props.setup(generator, world)
		_place_water_points(generator)
		_place_district_props(generator)
	# Park etmis araclar ve katı dunya nesneleri oyuncu icin engeldir (siper).
	player.extra_boxes_provider = func() -> Array:
		return vehicles.boxes_near(player.global_position) + props.boxes_near(player.global_position)
	quests = QuestSystem.new(self)

	build = BuildMode.new()
	add_child(build)
	build.setup(self)
	build.message.connect(func(text: String, color: Color) -> void: hud.message(text, color))
	abilities = Abilities.new(self)
	progression.leveled.connect(func(level: int, _points: int) -> void:
		hud.message("Seviye %d! Beceri puanı kazandın (K)." % level, Hud.GREEN)
		sync_learned()
		sfx.play_ui("craft_done"))


func _place_water_points(city: CityGenerator) -> void:
	## Haritadaki su noktalari (OSM cesme/icme suyu, cami sadirvani, park
	## pompasi) -> dunya nesnesi. Hepsi KIRLI su verir.
	var models := {"cesme": "iz2_district_fountain_wall", "icme_suyu": "iz2_district_fountain_drinking",
		"sadirvan": "iz2_district_fountain_wall", "el_pompasi": "iz2_water_hand_pump"}
	var labels := {"cesme": "Cesme", "icme_suyu": "Icme suyu musluğu", "sadirvan": "Sadirvan", "el_pompasi": "El pompasi"}
	var n := 0
	for w: Dictionary in city.data.get("water_points", []):
		var kind := str(w.get("kind", "cesme"))
		var label := str(labels.get(kind, "Su"))
		if str(w.get("name", "")) != "" and kind != "sadirvan":
			label = "%s (%s)" % [label, w.name]
		props.add({"id": "su:%d" % n, "asset": models.get(kind, "iz2_district_fountain_drinking"),
			"pos": Vector3(float(w.p[0]), 0.0, float(w.p[1])), "kind": "water_source", "label": label})
		n += 1


func _place_district_props(city: CityGenerator) -> void:
	## Semt kimligi (600 paket): meydanlara tezgah/araba/pano, iskelelere kiyi
	## nesneleri, parklara pergola. Konum OSM alanindan KARARLI (alan sirasi +
	## tohum); gorsel yalnizca yakinda kurulur (WorldProps), carpisma kutusu var.
	var sets := {
		"plaza": ["iz2_district_market_canopy", "iz2_district_fruit_cart", "iz2_district_newsstand",
			"iz2_district_chestnut_cart", "iz2_district_corn_cart", "iz2_district_flower_stall",
			"iz2_district_book_stall", "iz2_district_neighborhood_notice", "iz2_district_market_crate_stack",
			"iz2_district_fish_stall", "iz2_district_tea_garden_partition", "iz2_bicycle_rack"],
		"pier": ["iz2_district_lifebuoy_station", "iz2_district_mooring_bollard", "iz2_district_fishing_rod_rack",
			"iz2_district_ferry_queue_rail", "iz2_district_seaside_steps"],
		"park": ["iz2_district_courtyard_pergola", "iz2_district_plane_tree_guard", "iz2_district_laundry_line"],
	}
	var n := 0
	for i in city.areas.size():
		var area: Dictionary = city.areas[i]
		var kind := str(area.kind)
		if not sets.has(kind):
			continue
		var c: Vector2 = (area.lo + area.hi) * 0.5
		if not city.is_inside(floori(c.x), floori(c.y)):
			continue
		var size: Vector2 = area.hi - area.lo
		var count := clampi(int(size.length() / 25.0), 1, 4)
		var list: Array = sets[kind]
		for k in count:
			var h := absi(hash("%d:%d" % [i, k]))
			var asset: String = list[h % list.size()]
			if not AssetLibrary.has(asset):
				continue
			var offset := Vector2(float(h % 17) - 8.0, float((h / 17) % 17) - 8.0) * minf(1.0, size.length() / 60.0)
			var p := c + offset
			props.add({"id": "semt:%d:%d" % [i, k], "asset": asset, "pos": Vector3(p.x, 0.0, p.y),
				"kind": "decor", "label": "", "yaw": float(h % 4) * PI * 0.5})
			n += 1


func _give_start_kit() -> void:
	var errors: Array = []
	var kit: Variant = ContentValidator.load_json("res://data/world/start_kit.json", errors)
	if typeof(kit) != TYPE_DICTIONARY:
		return
	inventory.capacity_kg = float(kit.get("capacity_kg", BASE_CAPACITY_KG))
	inventory.max_slots = int(kit.get("max_slots", 80))
	var entries: Array = kit.get("items", [])
	if site == "test":
		entries = entries + kit.get("test_site_extra", [])
	for entry: Dictionary in entries:
		var definition := Content.item(entry.get("item", ""))
		if definition == null:
			push_warning("Baslangic kiti: bilinmeyen esya %s" % entry)
			continue
		var stack := ItemStack.new(definition, int(entry.get("count", 1)), float(entry.get("quality", 50)))
		stack.loaded = int(entry.get("loaded", 0))
		inventory.add(stack)


func _spawn_range_targets() -> void:
	for x: int in [-28, -22, -16, -10, -4, 2, 8]:
		var dummy := TargetDummy.new()
		add_child(dummy)
		dummy.global_position = Vector3(x + 2.0, 0.0, 14.5)
		actors.add(dummy)


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUD"
	add_child(hud_layer)
	hud = Hud.new()
	hud_layer.add_child(hud)
	hud_layer.add_child(crosshair)
	debug_label = Label.new()
	debug_label.position = Vector2(16, 12)
	debug_label.add_theme_font_size_override("font_size", 16)
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_label.add_theme_constant_override("outline_size", 6)
	debug_label.visible = false
	hud_layer.add_child(debug_label)
	screen_layer = CanvasLayer.new()
	screen_layer.layer = 10
	screen_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(screen_layer)


func refresh_skill_effects() -> void:
	## Kalici etkiler (tasima kapasitesi, zirh) her adim degil, rutbe ya da
	## kusanilan esya degisince tazelenir.
	skills.ranks = progression.ranks
	skills.refresh_tree(progression.nodes)
	sync_learned()
	# Agac davranislarinin sistem ayarlari (tek yerde).
	Zombie.player_head_mult = 2.0 * skills.multiplier("headshot_damage")
	vitals.stabilize = skills.has_behavior("stabilize")
	if vehicles != null:
		var logistics := skills.has_behavior("vehicle_logistics")
		vehicles.fuel_multiplier = 0.75 if logistics else 1.0
		vehicles.repair_share = 0.5 if skills.has_behavior("field_repair") else 0.3
		for car: Dictionary in vehicles.entries:
			var base_kg := float(Vehicles.def_of(car).get("capacity_kg", 120))
			(car.trunk as Inventory).capacity_kg = base_kg * (1.5 if logistics else 1.0)
	# Kusanilanlarin toplami. Kalite olceklendirir (0.7x..1.3x); dayanikliligi
	# bitmis parca KORUMAZ (bozuk zirh sadece agirliktir).
	var bonus := 0.0
	vitals.armor = 0.0
	vitals.toxin_resist = 0.0
	var light_range := 0.0
	for slot: String in equipment:
		var worn: ItemStack = equipment[slot]
		if worn == null or worn.broken():
			continue
		var scale := 0.7 + 0.6 * worn.quality / 100.0
		var e := worn.definition.effects
		bonus += float(e.get("capacity", 0.0))
		vitals.armor += float(e.get("armor", 0.0)) * scale
		vitals.toxin_resist = maxf(vitals.toxin_resist, float(e.get("toxin_resist", 0.0)) * minf(1.0, scale))
		light_range = maxf(light_range, float(e.get("light_range", 0.0)))
	inventory.capacity_kg = (BASE_CAPACITY_KG + bonus) * skills.multiplier("carry_capacity")
	if flashlight != null:
		# Kafa lambasi feneri guclendirir (menzil, genis huzme).
		flashlight.spot_range = 28.0 + light_range
		flashlight.spot_angle = 28.0 + light_range * 0.4


func equipment_bonus(key: String) -> float:
	## Kusanilan (bozuk olmayan) esyalarin toplam etkisi: stamina_bonus,
	## noise_bonus (gurultu azaltma orani), light_range...
	var total := 0.0
	for slot: String in equipment:
		var worn: ItemStack = equipment[slot]
		if worn != null and not worn.broken():
			total += float(worn.definition.effects.get(key, 0.0))
	return total


func _equipment_dict() -> Dictionary:
	var result := {}
	for slot: String in equipment:
		result[slot] = equipment[slot].to_dict() if equipment[slot] != null else {}
	return result


func equip_item(stack: ItemStack) -> String:
	var slot := stack.definition.slot
	if not stack.definition.equippable() or not equipment.has(slot):
		return "Bu eşya kuşanılmaz"
	var one: ItemStack = inventory.take_from_stack(stack, 1)
	if one == null:
		return "Esya bulunamadi"
	var previous: ItemStack = equipment[slot]
	equipment[slot] = one
	if previous != null:
		inventory.add(previous)
	refresh_skill_effects()
	return "Kusanildi: %s" % one.display_name()


func unequip(slot: String) -> String:
	var stack: ItemStack = equipment.get(slot)
	if stack == null:
		return ""
	if inventory.add(stack.copy()) > 0:
		return "Cantada yer yok"
	equipment[slot] = null
	refresh_skill_effects()
	return "Cikarildi: %s" % stack.display_name()


func repair_item(stack: ItemStack) -> String:
	## Tezgahta silah/esya onarimi: dayanikliligin %40'i, metal + baglanti.
	var stations: Dictionary = placeables.best_station(player.global_position).available
	if not stations.has("workbench") and not stations.has("gunsmith") and not skills.has_behavior("field_repair"):
		return "Onarim icin yakinda Calisma Tezgahi ya da Silah Tezgahi olmali (ya da Saha onarimi becerisi)"
	var maximum := stack.definition.durability
	if maximum <= 0 or stack.durability >= maximum:
		return "Onarima gerek yok"
	var sources: Array = [inventory]
	if bases.inside != null:
		sources.append(bases.inside.stockpile)
	if not BuildRules.pay([{"tag": "structural_metal", "count": 1}, {"tag": "fastener", "count": 2}], sources):
		return "Onarim icin 1 metal + 2 baglanti parcasi gerekli"
	stack.durability = mini(maximum, stack.durability + int(maximum * 0.4 * skills.multiplier("repair_amount")
		* skills.multiplier("craft_quality")))
	progression.count("repaired")
	return "Onarildi: %s (%d/%d)" % [stack.definition.name, stack.durability, maximum]


func _sync_region() -> void:
	## Oyuncunun GERCEK konumuna en yakin semt: zombi havuzu ve ganimet
	## carpani oradan gelir. Semtler yalnizca doku rengiyle degil davranisla
	## ayrisir (belgenin 8.6 maddesi).
	if not generator is CityGenerator:
		return
	var city: CityGenerator = generator
	if not city.districts.is_empty():
		_sync_district(city)
		return
	var center: Dictionary = city.data.get("center", {})
	if center.is_empty():
		return
	var scale := float(city.data.get("scale", 1.0))
	var lat0 := float(center.lat)
	var lon0 := float(center.lon)
	var p := player.global_position
	var lat := lat0 - (p.z - city.height * 0.5) / scale / 110540.0
	var lon := lon0 + (p.x - city.width * 0.5) / (scale * 111320.0 * cos(deg_to_rad(lat0)))
	var best := ""
	var best_d := INF
	for id: String in Content.regions:
		var region: Dictionary = Content.regions[id]
		if not region.has("lat"):
			continue
		var d := Vector2(float(region.lat) - lat, (float(region.lon) - lon) * cos(deg_to_rad(lat))).length()
		if d < best_d:
			best_d = d
			best = id
	if best == "" or best == region_id:
		return
	region_id = best
	var region: Dictionary = Content.regions[best]
	var table: Array = []
	for zombie_id: String in region.get("zombies", {}):
		var definition: ZombieDef = Content.zombies.get(zombie_id)
		if definition != null:
			table.append([definition, float(region.zombies[zombie_id])])
	zombies.region_table = table
	map_name = str(region.get("name", map_name))
	hud.message(map_name, Hud.BLUE)
	if progression.on_region(best):
		hud.message("Yeni semt kesfedildi: %s (+%d deneyim)" % [map_name, int(Progression.REGION_XP)], Hud.GREEN)


func _sync_district(city: CityGenerator) -> void:
	## Sabit harita: semt izgarasindan gercek semt; zombi karisimi ALAN
	## profilinden (data/world/zones.json).
	var p := player.global_position
	var d := city.district_at(p.x, p.z)
	_check_border(city, p)
	if d.is_empty() or str(d.id) == region_id:
		return
	region_id = str(d.id)
	var zone: Dictionary = Content.zones.get(str(d.zone), {})
	var table: Array = []
	for zombie_id: String in zone.get("zombies", {}):
		var definition: ZombieDef = Content.zombies.get(zombie_id)
		if definition != null:
			table.append([definition, float(zone.zombies[zombie_id])])
	if not table.is_empty():
		zombies.region_table = table
	map_name = str(d.name)
	hud.message("%s · %s" % [map_name, str(zone.get("label", ""))], Hud.BLUE)
	if progression.on_region(region_id):
		hud.message("Yeni semt keşfedildi: %s (+%d deneyim)" % [map_name, int(Progression.REGION_XP)], Hud.GREEN)


var _border_warned := 0.0


func _check_border(city: CityGenerator, p: Vector3) -> void:
	## Dunya siniri SESSIZ gorunmez duvar degildir: yaklasinca uyarilir.
	var d := city.border_distance(p.x, p.z)
	if d > 70.0:
		_border_warned = 0.0
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _border_warned < 12.0:
		return
	_border_warned = now
	var at_sea: bool = str(city.column_info(int(p.x), int(p.z)).kind) == "sea"
	hud.message(("Açık deniz: şehrin sınırı %d m ileride, ötesine geçilemez." if at_sea
		else "Şehir sınırı %d m ileride: ötesi kapalı bölge (sur ve orman hattı).") % maxi(0, int(d)), Hud.ACCENT)


# ---------------------------------------------------------------------------
# Dongu
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not ready_for_play:
		return
	var accepting := not ui_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not vitals.dead
	var in_vehicle := not vehicles.driving.is_empty()
	player.input_enabled = accepting
	player.driving = in_vehicle
	combat.input_enabled = accepting and not build.active and not in_vehicle
	player.speed_factor = inventory.speed_factor() * vitals.statuses.speed_multiplier()
	if in_vehicle:
		_drive(delta, accepting)
	elif not _binocular_active:
		player.fov_override = 0.0
	player.physics_step(delta)
	combat.physics_step(delta)
	# Kisisel ihtiyac: koloni stogu oyuncuyu uzaktan BESLEMEZ (eski baglanti
	# vitals.starving = bases.shortages kaldirildi).
	if not vitals.dead:
		survival.tick(delta)
	vitals.tick(delta, skills)
	var t0 := Time.get_ticks_usec()
	props.update(delta, player.global_position)
	perf.section("props", Time.get_ticks_usec() - t0)
	t0 = Time.get_ticks_usec()
	quests.tick(delta)
	perf.section("quests", Time.get_ticks_usec() - t0)
	abilities.tick(delta)
	throwables.tick(delta)
	if accepting and not in_vehicle:
		abilities.handle_input()
		if Input.is_action_just_pressed("throw"):
			throwables.throw_current()
		if Input.is_action_just_pressed("throw_cycle"):
			throwables.cycle()
	_region_timer -= delta
	if _region_timer <= 0.0:
		_region_timer = 2.0
		_sync_region()
	_update_time(delta)
	actors.rebuild()
	var ctx := _zombie_context()
	t0 = Time.get_ticks_usec()
	zombies.physics_step(delta, ctx)
	if population != null:
		population.tick(delta, player.global_position, ctx)
	perf.section("zombies", Time.get_ticks_usec() - t0)
	t0 = Time.get_ticks_usec()
	survivors.sync(player.global_position)
	perf.section("survivors", Time.get_ticks_usec() - t0)
	survivors.physics_step(delta, ctx)
	bases.physics_step(delta, player.global_position, vitals)
	power.tick(delta, self)
	placeables.tick(delta, self)
	_tick_farming(delta)
	combat.focus = vitals.statuses.spread_multiplier()
	if not in_vehicle:
		terrain.focus = player.position   # aractayken _drive onden bakar
	if interiors != null:
		t0 = Time.get_ticks_usec()
		interiors.update(delta, player.global_position)
		perf.section("interiors", Time.get_ticks_usec() - t0)
	_update_interaction(delta)
	_update_craft_job(delta)
	build.update(delta)
	if accepting and Input.is_action_just_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	_autosave(delta)


func _drive(delta: float, accepting: bool) -> void:
	var throttle := 0.0
	var steer := 0.0
	var brake := false
	if accepting:
		throttle = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		steer = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		brake = Input.is_action_pressed("jump")
	if _bench_drive != Vector2.INF:
		throttle = _bench_drive.x          # olcum senaryosu surer (bkz. _run_bench)
		steer = _bench_drive.y
	# SERBEST BAKIS: fare direksiyonu CEVIRMEZ. Bakis aracin burnuna gore
	# goreli bir aci olarak tutulur (+-110 derece, omuz ustu bakilabilir ama
	# kafa arkaya donmez); arac donunce bakis da onunla doner.
	var car_yaw: float = vehicles.driving.yaw
	var offset := wrapf(player.yaw - car_yaw, -PI, PI)
	if absf(offset - _drive_look_offset) > 0.0005:
		_drive_look_idle = 0.0              # fare oynadi
	else:
		_drive_look_idle += delta
	offset = clampf(offset, -DRIVE_LOOK_LIMIT, DRIVE_LOOK_LIMIT)
	if accepting and Input.is_action_just_pressed("look_center"):
		offset = 0.0
		player.pitch = -0.05
	elif _drive_look_idle > 2.5 and absf(float(vehicles.driving.speed)) > 4.0:
		# Hizlanirken fare birakildiysa bakis yavasca yola doner (ani ziplama yok).
		offset = move_toward(offset, 0.0, delta * 0.8)
		player.pitch = move_toward(player.pitch, -0.05, delta * 0.4)
	player.pitch = clampf(player.pitch, deg_to_rad(-55.0), deg_to_rad(35.0))
	vehicles.drive(delta, throttle, steer, brake, on_noise_at)
	player.yaw = float(vehicles.driving.yaw) + offset
	_drive_look_offset = offset
	var seat := vehicles.seat_transform()
	player.global_position = seat.origin - Vector3(0, player.eye_height, 0)
	var view_size := get_viewport().get_visible_rect().size
	player.fov_override = vehicles.cabin_vertical_fov(vehicles.driving, view_size.x / maxf(1.0, view_size.y))
	# Akis hiz yonunde onden yuklensin: yol ilerisi bosluk kalmasin.
	var ahead := Vector3(-sin(vehicles.driving.yaw), 0, -cos(vehicles.driving.yaw))
	terrain.focus = player.position + ahead * float(vehicles.driving.speed) * 1.5
	if accepting and Input.is_action_just_pressed("interact"):
		_exit_vehicle()


func _exit_vehicle() -> void:
	var too_fast := vehicles.can_exit()
	if too_fast != "":
		hud.message(too_fast, Hud.RED)
		return
	var point := vehicles.exit_point(Player.HALF_WIDTH, Player.STAND_HEIGHT)
	if point == Vector3.INF:
		hud.message("Guvenli inis noktasi yok (duvar, su ya da bosluk) -- baska yere cek", Hud.RED)
		return
	vehicles.leave()
	_exit_frame = Engine.get_physics_frames()
	player.driving = false
	player.teleport(point)
	weapon_view.visible = combat.state != null


func _zombie_context() -> Dictionary:
	var light_bonus := 1.0
	if flashlight.visible and time.is_night():
		light_bonus = 1.6          # isik = risk
	return {
		"player": player, "player_alive": not vitals.dead,
		"player_position": player.global_position,
		"player_eye": player.eye_position(), "player_look": player.look_direction(),
		"colonists": survivors.living_colonists(),
		"sight_multiplier": time.sight_multiplier(),
		"speed_multiplier": time.zombie_speed_multiplier(),
		"light_bonus": light_bonus,
		# Duman perdesinin icinde gorulmezsin (yalnizca ses ele verir).
		"stealth": skills.multiplier("detection_range") * (0.05 if throwables.in_smoke(player.global_position) else 1.0),
	}


func _update_time(delta: float) -> void:
	var turned := time.update(delta)
	for _i in turned:
		_on_new_day()
	environment_node.set_time_of_day(time.normalized, time.darkness())
	vehicles.update_lights(time.darkness() > 0.45)
	if bridge_decor != null:
		bridge_decor.set_sky(environment_node.environment.fog_light_color)
	zombies.night_multiplier = time.horde_multiplier()
	var event := waves.update(time.day, time.normalized)
	if event == "started":
		zombies.wave_focus = _wave_focus()
		zombies.wave_target = int(waves.wave_size(waves.active_day) * (population.wave_scale(zombies.wave_focus)
			if population != null else 1.0))
		hud.message("BUYUK DALGA -- yaklasik %d zombi%s" % [zombies.wave_target,
			" ussunun cevresinde" if not bases.settlements.is_empty() else ""], Hud.RED)
	elif event == "ended":
		zombies.wave_target = 0
		zombies.wave_focus = Vector3.INF
		hud.message("Dalga atlatildi. Sabah oldu.", Hud.GREEN)


func _wave_focus() -> Vector3:
	## Dalga USSU arar (oyuncu kacsa bile); us yoksa oyuncuyu.
	if not bases.settlements.is_empty():
		return (bases.settlements[0] as Settlement).centre()
	return player.global_position


func _on_new_day() -> void:
	if population != null:
		population.on_new_day()
	_colony_daily_placeables()
	for entry: Array in bases.consume_daily(time.day):
		hud.message(entry[0], entry[1])
	for entry: Array in survival.on_new_day(time.day):
		hud.message(entry[0], entry[1])
	quests.on_new_day(time.day)
	hud.message("Gun %d" % time.day, Hud.ACCENT)


func _process(delta: float) -> void:
	perf.push(delta)
	perf.section("terrain", terrain.last_step_usec)
	if not ready_for_play:
		_boot_time += delta
		if terrain.progress() >= 0.999 or (terrain.progress() > 0.6 and _shot_timer < 0.0):
			_on_world_ready()
		elif _boot_time > 25.0 and _args.has("shot"):
			print("HAZIR DEGIL: ilerleme %.3f, veri %d, mesh %d" % [terrain.progress(), world.chunks.size(),
				terrain.mesh_node_count()])
			_on_world_ready()
		else:
			hud.progress = terrain.progress()
			hud.progress_label = "İstanbul yükleniyor…"
	if Input.is_action_just_pressed("debug_overlay"):
		debug_label.visible = not debug_label.visible
	if debug_label.visible and Engine.get_process_frames() % 10 == 0:
		_update_debug()
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	weapon_view.update_view(delta, player.aiming, speed, player.on_floor)
	view_layer.sync_lighting(environment_node.sun, environment_node.environment.ambient_light_energy)
	crosshair.spread_degrees = combat.current_spread()
	crosshair.visible_cross = not ui_open and not build.active and vehicles.driving.is_empty() \
		and (not player.aiming or combat.state == null or combat.state.weapon.is_melee())
	_update_hud()
	_update_optics()
	_update_leak_markers(delta)
	if _shot_timer >= 0.0 and ready_for_play:
		_shot_timer -= delta
		if _shot_timer < 0.0:
			_take_screenshot(str(_args.shot))


func _gear_effect(key: String) -> float:
	## Cantadaki aletlerin en iyi degeri (pusula, durbun yakinlastirmasi).
	var best := 0.0
	for stack: ItemStack in inventory.stacks:
		best = maxf(best, float(stack.definition.effects.get(key, 0.0)))
	return best


func _update_optics() -> void:
	## Durbun: O basili tutulunca gorus acisi daralir (yakinlastirma).
	var zoom := _gear_effect("zoom")
	_binocular_active = zoom > 1.0 and not ui_open and vehicles.driving.is_empty() and Input.is_action_pressed("binoculars")
	if _binocular_active:
		player.fov_override = Settings.fov / zoom
		weapon_view.visible = false
	elif vehicles.driving.is_empty() and player.fov_override > 0.0:
		player.fov_override = 0.0
		weapon_view.visible = combat.state != null and not build.active
	hud.heading = fposmod(-rad_to_deg(player.yaw), 360.0) if _gear_effect("compass") > 0.0 else -1.0
	hud.power_text = ""
	if bases.inside != null:
		var p := power.summary_for(bases.inside)
		if int(p.networks) > 0:
			hud.power_text = "⚡ %d / %d W · akü %d/%d Wh" % [int(p.production), int(p.demand), int(p.stored), int(p.capacity)]


func _update_hud() -> void:
	hud.health_ratio = vitals.ratio()
	hud.energy_ratio = vitals.energy / PlayerVitals.BASE_ENERGY
	hud.stamina_ratio = player.stamina / Player.STAMINA_MAX
	hud.stamina_cap = player.stamina_cap / Player.STAMINA_MAX
	hud.satiety = vitals.satiety / 100.0
	hud.hydration = vitals.hydration / 100.0
	hud.statuses = vitals.statuses.labels()
	hud.objective = quests.hud_line() if quests != null else ""
	var state := combat.state
	if build.active:
		hud.weapon_name = "İnşa kipi"
		hud.ammo_text = ""
		hud.durability_ratio = -1.0
	elif state == null:
		hud.weapon_name = "Silahsız"
		hud.ammo_text = ""
		hud.durability_ratio = -1.0
	else:
		hud.weapon_name = state.stack.display_name()
		if state.weapon.is_melee():
			hud.ammo_text = "Yakın dövüş"
			hud.ammo_low = false
		elif state.reloading():
			hud.ammo_text = "Dolduruluyor..."
			hud.ammo_low = false
		else:
			hud.ammo_text = "%d / %d" % [state.loaded(), state.reserve()]
			hud.ammo_low = state.loaded() <= maxi(1, state.magazine_size() / 4)
		var max_durability := state.stack.definition.durability
		hud.durability_ratio = float(state.stack.durability) / max_durability if max_durability > 0 else -1.0
	hud.slots = []
	for i in PlayerCombat.SLOT_COUNT:
		var stack: ItemStack = combat.slots[i]
		hud.slots.append({"name": stack.definition.name.left(9) if stack != null else "",
			"active": i == combat.active_slot,
			"icon_id": AssetLibrary.item_model_id(stack.definition) if stack != null else ""})
	var prompt: String = _interaction.get("prompt", "")
	if build.active:
		prompt = build.status_text()
	hud.vehicle = {}
	if not vehicles.driving.is_empty():
		# Arac gostergesi alt ortada ayri panelde (bkz. Hud._draw_vehicle);
		# ekran ortasindaki ipucu yolu kapatmasin diye bos birakilir.
		var car := vehicles.driving
		var max_durability := Vehicles.max_durability(car)
		var hint := "[%s] in   [%s] bakisi ortala   [%s] el freni" % [Settings.binding_label("interact"),
			Settings.binding_label("look_center"), Settings.binding_label("jump")]
		if vehicles.can_exit() != "":
			hint = "Inmek icin dur   [%s] bakisi ortala   [%s] el freni" % [
				Settings.binding_label("look_center"), Settings.binding_label("jump")]
		hud.vehicle = {"speed": int(absf(car.speed) * 3.6), "gear": vehicles.gear_label(),
			"fuel": float(car.fuel) / Vehicles.tank(car), "fuel_text": "%d/%d" % [int(car.fuel), int(Vehicles.tank(car))],
			"condition": float(car.durability) / maxf(1.0, max_durability), "hint": hint,
			"warning": "YAKIT BITTI" if car.fuel <= 0.0 else ""}
		prompt = ""
	hud.prompt = prompt
	hud.clock_text = time.clock()
	hud.day_text = "Gün %d · %s" % [time.day, time.phase_name()]
	if waves.active():
		hud.wave_text = "BÜYÜK DALGA SÜRÜYOR"
	else:
		var days := waves.days_until(time.day, time.normalized)
		hud.wave_text = ("Büyük dalgaya %d gün (~%d zombi)" % [days, waves.expected_size(time.day, time.normalized)]) \
			if days > 0 else "Büyük dalga BU GECE (~%d zombi)" % waves.expected_size(time.day, time.normalized)
	var region := map_name
	if bases.inside != null:
		region = "%s -- %s%s" % [map_name, bases.inside.name, " (AÇIK)" if bases.inside.breached else ""]
	var extras := PackedStringArray([region])
	if inventory.count("radio_handheld") > 0 or quests.flags.has("network"):
		var signal_info := survivors.radio_signal(player.global_position)
		if not signal_info.is_empty():
			extras.append("Telsiz: %s %d m" % [_bearing(signal_info.position), int(signal_info.distance)])
			if skills.has_behavior("radio_all") or quests.flags.has("network"):
				extras.append("(%d kisi yardim bekliyor)" % survivors.waiting_count())
	if skills.has_behavior("tracking"):
		var nearest: Zombie = null
		var best := 45.0
		for z: Zombie in zombies.zombies:
			if is_instance_valid(z) and z.is_alive() and z.state != Zombie.State.IDLE:
				var d := z.global_position.distance_to(player.global_position)
				if d < best:
					best = d
					nearest = z
		if nearest != null:
			extras.append("Iz: %s %d m" % [_bearing(nearest.global_position), int(best)])
	if waypoint != Vector3.INF:
		extras.append("Hedef: %s %d m" % [_bearing(waypoint), int(Vector2(waypoint.x, waypoint.z).distance_to(
			Vector2(player.global_position.x, player.global_position.z)))])
	hud.region_text = "   ".join(extras)
	if not craft_job.is_empty() and search != null and not search.active() and _action.is_empty():
		hud.progress = clampf(craft_job.elapsed / maxf(0.1, craft_job.recipe.time), 0.0, 1.0)
		hud.progress_label = "Üretiliyor: %s (%d kaldı)" % [craft_job.recipe.name, craft_job.remaining]


func _bearing(target: Vector3) -> String:
	## Hedefin bakis yonune gore saat yonu: "12" onde, "3" sagda.
	var to := target - player.global_position
	var look := player.look_direction()
	var angle := rad_to_deg(atan2(to.x, -to.z) - atan2(look.x, -look.z))
	angle = fposmod(angle, 360.0)
	var hour := int(round(angle / 30.0)) % 12
	return "saat %d yonu" % (12 if hour == 0 else hour)


# ---------------------------------------------------------------------------
# Etkilesim
# ---------------------------------------------------------------------------
func _update_interaction(delta: float) -> void:
	## Oncelik: yerdeki esya > arac > kurtarilacak kisi > ceset > bakilan
	## mobilya/kapi. Bina cephesinden toplu arama YOKTUR.
	_interaction = {}
	hud.progress = -1.0 if ready_for_play else hud.progress
	if vitals.dead or not vehicles.driving.is_empty():
		return
	var key := Settings.binding_label("interact")
	# Inis karesinde ayni E basisi yeniden "bin" sayilmasin (aninda geri biniliyordu).
	var pressed := Input.is_action_just_pressed("interact") and player.input_enabled and not build.active \
		and Engine.get_physics_frames() != _exit_frame
	if search != null and search.active():
		search.update(delta, player.global_position)
		hud.progress = search.progress()
		hud.progress_label = "Aranıyor: %s" % search.label()
		if pressed:
			search.cancel("Aramayi biraktin")
		return
	if not _action.is_empty():
		_action.elapsed += delta
		hud.progress = clampf(_action.elapsed / _action.duration, 0.0, 1.0)
		hud.progress_label = _action.label
		var moved := Vector2(player.global_position.x - _action.origin.x, player.global_position.z - _action.origin.z)
		if pressed or moved.length() > SearchSystem.CANCEL_MOVE:
			_action = {}
			return
		if _action.elapsed >= _action.duration:
			var done: Callable = _action.done
			_action = {}
			done.call()
		return
	if not abilities.casting.is_empty():
		hud.progress = 1.0 - abilities.casting.left / maxf(0.1, float(abilities.casting.power.cast_time))
		hud.progress_label = "İlk yardım"

	var nearby := pickups.nearest(player.position + Vector3(0, 0.5, 0))
	var car := vehicles.nearest(player.global_position)
	if not nearby.is_empty():
		_interaction = {"kind": "pickup", "entry": nearby, "prompt": "[%s] Al -- %s" % [key, pickups.describe(nearby)]}
	elif not car.is_empty():
		var def := Vehicles.def_of(car)
		_interaction = {"kind": "vehicle", "entry": car, "prompt": "[%s] Bin: %s  (yakit %d/%d, saglamlik %d/%d)  -- [I] yakit/onarim/bagaj" % [
			key, def.get("name", car.def_id), int(car.fuel), int(Vehicles.tank(car)), int(car.durability), int(Vehicles.max_durability(car))]}
	else:
		var person := survivors.nearest_waiting(player.global_position, 2.5)
		if person != null:
			_interaction = {"kind": "survivor", "node": person,
				"prompt": "[%s] Konus: %s -- 'Benimle gel, usse goturecegim.'" % [key, Content.colony.profiles[person.profile_id].name]}
		else:
			var corpse := zombies.nearest_corpse(player.global_position, 2.0)
			var prop := props.nearest(player.global_position, 2.3, ["water_source", "mission"])
			var built := _placeable_target()
			if corpse != null:
				_interaction = {"kind": "corpse", "corpse": corpse, "prompt": "[%s] Cesedi ara (%s)" % [key, corpse.def.name]}
			elif not prop.is_empty():
				if prop.kind == "water_source":
					_interaction = {"kind": "water", "prop": prop, "prompt": "[%s] %s: bos siseleri doldur (KIRLI su, %d bos sise)" % [
						key, prop.label, inventory.count("bottle_empty")]}
				else:
					_interaction = quests.interaction_for(prop, key)
			elif not built.is_empty():
				_interaction = {"kind": "placeable", "entry": built, "prompt": _placeable_prompt(built, key)}
			elif _gear_effect("fishing") > 0.0 and _looking_at_water():
				_interaction = {"kind": "fish", "prompt": "[%s] Balık tut (olta%s)" % [key,
					", yem var" if inventory.count_by_tag("bait") > 0 else ", yemsiz: az şans"]}
			elif interiors != null:
				_interaction = _interior_interaction(key)
	if _interaction.is_empty() and vehicles.driving.is_empty():
		# Oyuncunun kurdugu kapi (B kipi): acik/kapali, zombi kirabilir.
		var door_cell := _built_door_target()
		if door_cell != Vector3i.MAX:
			_interaction = {"kind": "built_door", "cell": door_cell,
				"prompt": "[%s] %s" % [key, "Kapıyı kapat" if build.door_open(door_cell) else "Kapıyı aç"]}
	if _interaction.is_empty() or not pressed:
		return
	match _interaction.kind:
		"pickup":
			var result := pickups.take(_interaction.entry, inventory)
			_report_loot(_interaction.entry.label, result.taken, result.left)
		"survivor":
			survivors.persuade(_interaction.node)
		"vehicle":
			var problem := vehicles.enter(_interaction.entry)
			if problem != "":
				hud.message(problem, Hud.RED)
			else:
				weapon_view.visible = false
				if build.active:
					build.toggle()
				_drive_look_offset = 0.0
				player.yaw = float(_interaction.entry.yaw)
				player.pitch = -0.05
				hud.message("W gaz, S fren/geri vites, A/D direksiyon, Space el freni, fare serbest bakis, H ortala, E in (dururken). Surus gurultu yapar.", Hud.ACCENT)
		"unlock":
			var plan_u: Dictionary = _interaction.plan
			var f_u: Dictionary = _interaction.f
			var tool_u: ItemStack = _interaction.get("tool")
			_action = {"label": "Kilit açılıyor", "duration": 3.0 if tool_u == null else 4.5, "elapsed": 0.0,
				"origin": player.global_position,
				"done": func() -> void:
					if tool_u != null:
						if tool_u.broken() or not inventory.stacks.has(tool_u):
							return
						tool_u.durability = maxi(0, tool_u.durability - 15)
						on_noise_at(player.global_position, Units.perception_m(220.0))
					else:
						if inventory.count("lockpick") <= 0:
							return
						inventory.remove("lockpick", 1)
					containers.unlock(f_u.id)
					hud.message("Kilit açıldı", Hud.GREEN)
					search.begin(plan_u, f_u, player.global_position, false)}
			sfx.play_at("search_rustle", player.global_position, -12.0)
		"water":
			var prop: Dictionary = _interaction.prop
			_action = {"label": "Su dolduruluyor", "duration": Survival.FILL_SECONDS, "elapsed": 0.0,
				"origin": player.global_position, "done": func() -> void:
					var text := survival.fill_from_source(str(prop.label))
					hud.message(text, Hud.BLUE)
					quests.notify("water_filled", {"source": prop.id})}
			sfx.play_at("search_rustle", player.global_position, -10.0)
		"mission":
			quests.interact(_interaction)
		"placeable":
			_use_placeable(_interaction.entry)
		"fish":
			_action = {"label": "Balık tutuluyor", "duration": 7.0, "elapsed": 0.0,
				"origin": player.global_position, "done": _catch_fish}
			sfx.play_at("search_rustle", player.global_position, -14.0)
		"built_door":
			hud.message(build.toggle_door(_interaction.cell, _body_in_box), Hud.ACCENT)
			sfx.play_at("impact_wood", player.global_position, -10.0)
		"corpse":
			var corpse: Zombie = _interaction.corpse
			_action = {"label": "Ceset araniyor", "duration": 1.6, "elapsed": 0.0,
				"origin": player.global_position, "done": _loot_corpse.bind(corpse)}
			sfx.play_at("search_rustle", player.global_position, -8.0)
		"container":
			var plan: Dictionary = _interaction.plan
			var f: Dictionary = _interaction.f
			match containers.status(f):
				"unsearched":
					search.begin(plan, f, player.global_position, false)
					sfx.play_at("search_rustle", player.global_position, -6.0)
				"empty":
					if containers.can_restock(plan, f, time.day):
						search.begin(plan, f, player.global_position, true)
						sfx.play_at("search_rustle", player.global_position, -6.0)
					else:
						_open_loot(plan, f)
				"items":
					_open_loot(plan, f)
		"door":
			var result := interiors.toggle_door(_interaction.plan, _interaction.door, _body_in_box)
			hud.message(result, Hud.ACCENT)
			sfx.play_at("impact_wood" if str(_interaction.door.material) == "door_wood" else "impact_metal",
				player.global_position, -10.0)


func _loot_corpse(corpse: Zombie) -> void:
	if not is_instance_valid(corpse) or corpse.looted:
		return
	corpse.looted = true
	var table: LootTable = Content.loot_tables.get("zombie_corpse")
	if table == null:
		return
	var taken: Array = []
	var left: Array = []
	for stack: ItemStack in table.roll(Content.items, _salvage_rng, skills.bonus("loot_luck")):
		var wanted := stack.quantity
		var leftover := inventory.add(stack.copy())
		if wanted - leftover > 0:
			taken.append(stack.copy(wanted - leftover))
		if leftover > 0:
			left.append(stack.copy(leftover))
	if not left.is_empty():
		pickups.spawn(left, corpse.global_position + Vector3(0, 0.1, 0), "Cesetten kalan", "remnant")
	progression.on_corpse()
	_report_loot("Ceset", taken, left)


func _interior_interaction(key: String) -> Dictionary:
	## Bakilan mobilya/kapi. Durumlar acikca yazilir: aranmamis, dolu, bos, kirik.
	var target := interiors.find_target(player.eye_position(), player.look_direction(), player.global_position)
	match str(target.get("kind", "")):
		"container":
			var f: Dictionary = target.f
			var def := ContainerRegistry.type_def(f.container)
			var label := str(def.get("label", "Dolap"))
			var text := ""
			match containers.status(f):
				"unsearched":
					if bool(def.get("locked", false)) and not containers.is_unlocked(f.id):
						# KILITLI: maymuncuk + "Kilit acma" becerisi, ya da silahla kir (icerik enkaza duser).
						if skills.has_behavior("lockpick") and inventory.count("lockpick") > 0:
							return {"kind": "unlock", "plan": target.plan, "f": f,
								"prompt": "[%s] %s: maymuncukla aç (1 maymuncuk)" % [key, label]}
						var cutter := _lock_tool()
						if cutter != null:
							return {"kind": "unlock", "plan": target.plan, "f": f, "tool": cutter,
								"prompt": "[%s] %s: %s ile aç (alet aşınır, gürültülü)" % [key, label, cutter.definition.name]}
						return {"kind": "none", "prompt": "%s KİLİTLİ · maymuncuk + Kilit açma becerisi (K), cıvata makası ya da silahla kır" % label}
					var done := containers.progress(f.id)
					text = "[%s] %s%s" % [key, def.get("verb", "Ara"), "  (%d%% arandi)" % int(done * 100) if done > 0.0 else ""]
				"items":
					text = "[%s] Ac: %s (%d yigin)" % [key, label, containers.items(f.id).size()]
				"empty":
					if containers.can_restock(target.plan, f, time.day):
						text = "[%s] Tekrar ara: %s" % [key, label]
					else:
						text = "%s: bos  [%s] ac" % [label, key]
				"destroyed":
					return {"kind": "none", "prompt": "%s: kirik" % label}
			return {"kind": "container", "plan": target.plan, "f": f, "prompt": text}
		"door":
			var verb := "Kapiyi ac" if target.state == "closed" else "Kapiyi kapat"
			return {"kind": "door", "plan": target.plan, "door": target.door, "prompt": "[%s] %s" % [key, verb]}
		"blocked":
			return {"kind": "none", "prompt": str(target.reason)}
	return {}


func _body_in_box(lo: Vector3, hi: Vector3) -> bool:
	## Kapi kapanmadan once: kapi hucresinde oyuncu ya da zombi var mi?
	var box := AABB(lo, hi - lo)
	var p := player.global_position
	if box.intersects(AABB(p - Vector3(0.3, 0, 0.3), Vector3(0.6, 1.8, 0.6))):
		return true
	for zombie: Zombie in zombies.zombies:
		if is_instance_valid(zombie) and box.intersects(AABB(zombie.global_position - Vector3(0.35, 0, 0.35), Vector3(0.7, 1.8, 0.7))):
			return true
	return false


func _on_container_searched(plan: Dictionary, f: Dictionary, restock: bool) -> void:
	## Arama bitti: zar (ya da yenilenme) BIR KEZ, sonra loot paneli.
	var luck := skills.bonus("loot_luck")
	if restock:
		# Yeniden arama deneyim VERMEZ (ayni kutuyu tekrar acma somurusu).
		if not containers.restock(plan, f, time.day, luck):
			hud.message("Yeni bir sey yok", Color(0.7, 0.7, 0.7))
		_open_loot(plan, f)
		return
	else:
		containers.roll(plan, f, time.day, luck)
		# SEMA KESFI: karakol, askeri tesis, elektronikci, sanayi ve atolyelerin
		# ofis/silah/takim dolaplarinda kilitli tariflerin semasi bulunabilir.
		# Yalniz "sema" ile acilan tarifler; seviye/beceri kilidi loot'la atlanmaz.
		if plan["class"] in ["police", "military", "electronics", "industrial", "workshop", "prison", "school", "checkpoint"] \
				and f.container in ["weapon_locker", "tool_cabinet", "filing_cabinet", "display_cabinet", "safe", "locker"] \
				and _salvage_rng.randf() < 0.12:
			var locked: Array = []
			for recipe: RecipeDef in Content.recipes.values():
				if recipe.learn_kind() == "schematic" and not crafting.known_recipes.has(recipe.id):
					locked.append(recipe)
			if not locked.is_empty():
				var found: RecipeDef = locked[_salvage_rng.randi() % locked.size()]
				crafting.known_recipes[found.id] = true
				hud.message("SEMA BULUNDU: %s -- artik uretilebilir" % found.name, Hud.GREEN)
				sfx.play_ui("craft_done")
	progression.on_loot()
	var floor_use := str(plan.floors[int(f.floor)].get("use", plan["class"])) if int(f.floor) < plan.floors.size() else str(plan["class"])
	quests.notify("search", {"class": floor_use})
	_open_loot(plan, f)


func _open_loot(plan: Dictionary, f: Dictionary) -> void:
	interiors.set_container_open(plan, f, true)
	var screen := LootScreen.new()
	screen.title = str(ContainerRegistry.type_def(f.container).get("label", "Dolap"))
	screen.plan = plan
	screen.f = f
	screen.origin = player.global_position
	if containers.items(f.id).is_empty():
		hud.message("%s: bos" % ContainerRegistry.type_def(f.container).get("label", "Dolap"), Color(0.7, 0.7, 0.7))
	open_screen(screen)

func _report_loot(label: String, taken: Array, left: Array) -> void:
	## Bulunan, alinan ve GERIDE KALAN esya acikca gosterilir.
	if taken.is_empty() and left.is_empty():
		hud.message("%s: bos" % label, Color(0.7, 0.7, 0.7))
		return
	if not taken.is_empty():
		sfx.play_ui("pickup")
		var names := PackedStringArray()
		for stack: ItemStack in taken:
			names.append("%s x%d" % [stack.display_name(), stack.quantity])
		hud.message("Alindi: " + ", ".join(names), Hud.GREEN)
	if not left.is_empty():
		var names := PackedStringArray()
		for stack: ItemStack in left:
			names.append("%s x%d" % [stack.display_name(), stack.quantity])
		hud.message("Sigmadi, yerde kaldi: " + ", ".join(names), Hud.RED)


# ---------------------------------------------------------------------------
# Yerlestirilebilirler, toplama, tarim, bakim
# ---------------------------------------------------------------------------
func _on_harvested(drops: Array, at: Vector3) -> void:
	## Aletle sokulen kaynak: cantaya; sigmayan yere duser (kaybolmaz).
	var taken: Array = []
	var left: Array = []
	for stack: ItemStack in drops:
		var wanted := stack.quantity
		var leftover := inventory.add(stack.copy())
		if wanted - leftover > 0:
			taken.append(stack.copy(wanted - leftover))
		if leftover > 0:
			left.append(stack.copy(leftover))
	if not left.is_empty():
		pickups.spawn(left, at, "Toplanan", "remnant")
	progression.count("gathered")
	_report_loot("Toplandı", taken, left)


func _lock_tool() -> ItemStack:
	for stack: ItemStack in inventory.stacks:
		if stack.definition.has_tag("lockpick_tool") and not stack.broken():
			return stack
	return null


func _looking_at_water() -> bool:
	var hit := VoxelRay.cast(world, player.eye_position(), player.look_direction(), 6.0)
	if not hit.is_empty() and not hit.boundary and world.materials.liquid[hit.value] == 1:
		return true
	# Isin suyu gecer (sivi katı degil): bakis boyunca su hucresi ara.
	var p := player.eye_position()
	for i in 12:
		p += player.look_direction() * 0.5
		var v := world.get_block(floori(p.x), floori(p.y), floori(p.z))
		if v != 0 and v != VoxelWorld.BOUNDARY and world.materials.liquid[v] == 1:
			return true
	return false


func _catch_fish() -> void:
	## Olta: yem (etiket "bait") varsa sans yuksek ve yem harcanir. Olta
	## her denemede asinir. Cig balik ocakta pisirilir.
	var rod: ItemStack = null
	for stack: ItemStack in inventory.stacks:
		if float(stack.definition.effects.get("fishing", 0.0)) > 0.0 and not stack.broken():
			rod = stack
			break
	if rod == null:
		return
	var chance := 0.25 * float(rod.definition.effects.fishing)
	var bait := inventory.matching_tag("bait")
	if not bait.is_empty():
		inventory.take_from_stack(bait[0], 1)
		chance += 0.4
	if rod.definition.durability > 0:
		rod.durability = maxi(0, rod.durability - 2)
	# Av tablosu harvest.json "fishing": [{item, count, chance}] (ilk tutan).
	var catch_def: Dictionary = {}
	if _salvage_rng.randf() < minf(0.9, chance):
		for entry: Variant in Content.harvest.get("fishing", [{"item": "raw_fish", "count": [1, 2], "chance": 1.0}]):
			if typeof(entry) == TYPE_DICTIONARY and Content.item(str(entry.get("item", ""))) != null \
					and _salvage_rng.randf() < float(entry.get("chance", 1.0)):
				catch_def = entry
				break
	if not catch_def.is_empty():
		var span: Array = catch_def.get("count", [1, 1])
		var def := Content.item(str(catch_def.item))
		var left := inventory.add(ItemStack.new(def, _salvage_rng.randi_range(int(span[0]), int(span[-1])), 50.0))
		hud.message("%s tuttun!%s" % [def.name, " (çanta dolu, kaçtı)" if left > 0 else ""], Hud.GREEN)
		progression.count("fish_caught")
	else:
		hud.message("Balık yakalanmadı", Color(0.7, 0.7, 0.7))


func _tick_farming(delta: float) -> void:
	_farm_timer += delta
	if _farm_timer < 1.0:
		return
	var hours := _farm_timer * time.hours_per_second()
	_farm_timer = 0.0
	for entry: Dictionary in placeables.entries:
		if entry.kind == "planter":
			Farming.tick(entry, hours)


func _colony_daily_placeables() -> void:
	## Gunluk: usteki ciftci saksilari sular; elektrikli aritici depodaki
	## kirli suyu temizler (guc yoksa calismaz).
	for base: Settlement in bases.settlements:
		var inside: Array = placeables.entries.filter(func(e: Dictionary) -> bool:
			return base.contains_position(Vector3(e.cell)))
		var farmers := bases.colony.members(base.id).filter(func(r: Dictionary) -> bool: return r.role == "farmer").size()
		if farmers > 0:
			var planters := inside.filter(func(e: Dictionary) -> bool: return e.kind == "planter")
			var n := Farming.colony_water(base, planters)
			if n > 0:
				hud.message("%s: çiftçi %d saksıyı suladı" % [base.name, n], Hud.BLUE)
		for entry: Dictionary in inside:
			# DONUSTURUCU (arıtıcı, kompost kutusu): her gun ussun deposundan
			# `from` alir, `to` verir; `consumes` varsa gunde bir sarf harcar.
			if entry.kind != "purifier" or not bool(entry.powered):
				continue
			var info := placeables.info_of(entry)
			var from := str(info.get("from", "water_dirty"))
			var to := str(info.get("to", "water_bottle"))
			var amount := mini(int(info.get("daily", 6)), base.stockpile.count(from))
			if amount <= 0 or Content.item(to) == null:
				continue
			var consumes := str(info.get("consumes", ""))
			var trial := base.stockpile.clone()
			if consumes != "":
				if trial.count(consumes) <= 0:
					hud.message("%s: %s için %s yok" % [base.name, placeables.label_of(entry), Content.item(consumes).name], Hud.RED)
					continue
				trial.remove(consumes, 1)
			trial.remove(from, amount)
			if trial.add(ItemStack.new(Content.item(to), amount, 60.0)) == 0:
				base.stockpile.replace_with(trial)
				hud.message("%s: %s %d× %s üretti" % [base.name, placeables.label_of(entry), amount, Content.item(to).name], Hud.BLUE)


func _sync_colony_capacity() -> void:
	## Usteki koloni yapilari -> rol kapasitesi (yatak, revir, mutfak, raf...).
	if bases == null:
		return
	for base: Settlement in bases.settlements:
		var extra := {}
		for entry: Dictionary in placeables.entries:
			if not base.contains_position(Vector3(entry.cell)):
				continue
			var colony: Dictionary = placeables.info_of(entry).get("colony", {})
			for role: String in colony:
				extra[role] = float(extra.get(role, 0.0)) + float(colony[role]) * (0.8 + 0.4 * float(entry.quality) / 100.0)
		base.extra_capacity = extra
		base.apply_storage_capacity()


func _built_door_target() -> Vector3i:
	var hit := VoxelRay.cast(world, player.eye_position(), player.look_direction(), 3.0)
	if not hit.is_empty() and not hit.boundary and build.is_door(hit.cell):
		return build.door_root(hit.cell)
	# Acik kapi hava hucresidir: bakis noktasina yakin acik kapi.
	var probe := player.eye_position() + player.look_direction() * 1.5
	return build.open_door_near(probe, 1.2)


func _placeable_target() -> Dictionary:
	## Bakilan yapi: once gorunmez carpisma hucresine isin, yoksa bakis
	## noktasina yakin katı olmayan yapi (tuzak, lamba, saksi).
	var eye := player.eye_position()
	var look := player.look_direction()
	var hit := VoxelRay.cast(world, eye, look, 3.5)
	if not hit.is_empty() and not hit.boundary:
		var owner := placeables.entry_at_cell(hit.cell)
		if not owner.is_empty():
			return owner
	var probe := eye + look * 1.8
	var best := {}
	var best_d := 1.4
	for entry: Dictionary in placeables.entries:
		var d := (Vector3(entry.cell) + Vector3(0.5, 0.4, 0.5)).distance_to(probe)
		if d < best_d:
			best = entry
			best_d = d
	return best


func _placeable_prompt(entry: Dictionary, key: String) -> String:
	var name := placeables.label_of(entry)
	var info := placeables.info_of(entry)
	var needs_power := PowerGrid.draw_of(info) > 0.0
	var power_note := "" if not needs_power else (" · elektrik var" if bool(entry.powered) else " · ELEKTRİK YOK")
	match entry.kind:
		"storage":
			return "[%s] Aç: %s (%.0f/%.0f kg)" % [key, name, (entry.inv as Inventory).weight(), (entry.inv as Inventory).capacity_kg]
		"switch":
			return "[%s] %s: %s" % [key, name, "kapat" if bool(entry.on) else "aç"]
		"light", "alarm", "decoy":
			return "[%s] %s: %s%s" % [key, name, "kapat" if bool(entry.on) else "aç", power_note]
		"generator":
			var tank := float(info.get("tank_hours", float(info.get("fuel_hours", 4.0)) * 3.0))
			return "[%s] %s: yakıt %.1f/%.0f saat · %s" % [key, name, float(entry.fuel), tank,
				"yakıt koy / kapat" if bool(entry.on) else "aç"]
		"battery":
			return "%s: %.0f / %.0f Wh" % [name, float(entry.charge), power.battery_capacity(entry)]
		"solar":
			return "%s: gündüz %d W üretir" % [name, int(float(info.get("output", 100.0)))]
		"bed":
			return "[%s] %s: uyu (sabaha kadar ya da 4 saat)" % [key, name]
		"planter":
			return "[%s] %s: %s" % [key, name, Farming.status_text(entry)]
		"turret":
			var ammo := Content.item(str(info.get("ammo", "")))
			if ammo == null:
				return "%s: elektrikle atar%s" % [name, power_note]
			return "[%s] %s: şarjör %d · %s doldur%s" % [key, name, int(entry.ammo), ammo.name, power_note]
		"station":
			return "[%s] %s T%d: üretim (C)%s" % [key, name, int(entry.tier), power_note]
		"trap":
			return "%s: %d kullanım kaldı%s" % [name, int(entry.uses), power_note]
		"colony", "cold_room", "rain_collector", "purifier", "relay", "sensor":
			return "%s (%s)%s" % [name, Placeables.KIND_NAMES.get(entry.kind, entry.kind), power_note]
	return name


func _use_placeable(entry: Dictionary) -> void:
	var info := placeables.info_of(entry)
	match entry.kind:
		"storage":
			var screen := StorageScreen.new()
			screen.entry = entry
			open_screen(screen)
		"switch", "light", "alarm", "decoy":
			entry.on = not bool(entry.on)
			power.mark_dirty()
			hud.message("%s %s" % [placeables.label_of(entry), "açıldı" if entry.on else "kapatıldı"], Hud.ACCENT)
		"generator":
			var used := power.add_fuel(entry, inventory)
			if used > 0:
				entry.on = true
				hud.message("%s: %d birim yakıt kondu (%.1f saat)" % [placeables.label_of(entry), used, float(entry.fuel)], Hud.GREEN)
			else:
				entry.on = not bool(entry.on)
				hud.message("%s %s%s" % [placeables.label_of(entry), "çalıştırıldı" if entry.on else "durduruldu",
					"" if float(entry.fuel) > 0.0 else " (yakıt yok: benzin, mazot, motor yağı...)"], Hud.ACCENT)
			power.mark_dirty()
		"bed":
			sleep(entry)
		"planter":
			hud.message(Farming.interact(entry, inventory, _salvage_rng, skills), Hud.GREEN)
		"turret":
			var ammo_id := str(info.get("ammo", ""))
			var def := Content.item(ammo_id)
			if def == null:
				return
			var cap := int(info.get("magazine", 60))
			var want := cap - int(entry.ammo)
			var have := inventory.count(ammo_id)
			var n := mini(want, have)
			if n <= 0:
				hud.message("%s: %s" % [placeables.label_of(entry), "şarjör dolu" if want <= 0 else "çantada %s yok" % def.name], Hud.RED)
				return
			inventory.remove(ammo_id, n)
			entry.ammo = int(entry.ammo) + n
			hud.message("%s: %d %s dolduruldu (%d/%d)" % [placeables.label_of(entry), n, def.name, entry.ammo, cap], Hud.GREEN)
		"station":
			_toggle_screen(CraftingScreen)
		_:
			hud.message(_placeable_prompt(entry, ""), Hud.ACCENT)


func sleep(bed: Dictionary) -> void:
	## Uyku: gece ise sabaha (06:00), degilse 4 saat atlar. Yakinda uyanik
	## zombi varsa uyunmaz. Atlanan saatlerde aclik/susuzluk ISLER (bedava
	## zaman yok); can dinlenmeyle yavasca dolar. Dalga gecesi atlanirsa
	## tanimli kuralla cozulur.
	for z: Zombie in zombies.zombies:
		if is_instance_valid(z) and z.is_alive() and z.state != Zombie.State.IDLE \
				and z.global_position.distance_to(player.global_position) < 30.0:
			hud.message("Yakında uyanık zombi var -- uyuyamazsın", Hud.RED)
			return
	var hours := 4.0
	if time.is_night():
		var now := time.normalized * 24.0
		hours = fposmod(6.0 - now, 24.0)
	var info := placeables.info_of(bed)
	vitals.tick_needs(hours, "idle", skills)
	var heal_rate := float(info.get("heal_per_hour", 4.0)) * (0.8 + 0.4 * float(bed.quality) / 100.0)
	vitals.heal(heal_rate * hours)
	vitals.energy = vitals.energy_max
	player.stamina = player.stamina_cap
	var turned := time.advance_hours(hours)
	for i in turned:
		_resolve_skipped_night(time.day - turned + i)
		_on_new_day()
	Survival.stamp(inventory, time.total_hours())
	hud.message("%.0f saat uyudun (+%d can). Gün %d %s" % [hours, int(heal_rate * hours), time.day, time.clock()], Hud.GREEN)


func sync_learned() -> void:
	## Seviye ve beceri yoluyla ogrenilen tarifler kendiliginden acilir.
	for recipe: RecipeDef in Content.recipes.values():
		if recipe.unlocked or crafting.known_recipes.has(recipe.id):
			continue
		match recipe.learn_kind():
			"level":
				if progression.level >= int(recipe.learn_arg()):
					crafting.known_recipes[recipe.id] = true
			"skill":
				if progression.nodes.has(recipe.learn_arg()):
					crafting.known_recipes[recipe.id] = true


func attach_mod(weapon: ItemStack, mod: ItemStack) -> String:
	## Modu silaha takar; ayni yuvadaki eski mod cantaya doner. Uyum:
	## modun `fits` listesi silahin kategorisini (ya da silah kimligini) icermeli.
	var wdef: WeaponDef = Content.weapons.get(weapon.definition.weapon_id)
	if wdef == null or mod.definition.category != "mod":
		return "Bu eşya silaha takılmaz"
	var fits := mod.definition.fits
	if not fits.is_empty() and not wdef.category in fits and not wdef.id in fits:
		return "%s bu silaha uymaz (uyumlu: %s)" % [mod.definition.name, ", ".join(fits)]
	if fits.is_empty() and wdef.is_melee():
		return "Ateşli silah modu yakın dövüş silahına takılmaz"
	var one := inventory.take_from_stack(mod, 1)
	if one == null:
		return "Mod bulunamadı"
	var old := weapon.mod_in_slot(one.definition.mod_slot)
	if old != null:
		weapon.mods.erase(old)
		if inventory.add(old) > 0:
			pickups.spawn([old], player.global_position + Vector3(0, 0.3, 0), "Sökülen mod", "remnant")
	weapon.mods.append(one)
	if combat.state != null and combat.state.stack == weapon:
		combat.equip(combat.active_slot)
	return "%s takıldı: %s" % [one.definition.name, weapon.definition.name]


func detach_mod(weapon: ItemStack, mod: ItemStack) -> String:
	if not weapon.mods.has(mod):
		return ""
	if inventory.add(mod.copy()) > 0:
		return "Çantada yer yok"
	weapon.mods.erase(mod)
	if combat.state != null and combat.state.stack == weapon:
		combat.equip(combat.active_slot)
	return "Söküldü: %s" % mod.definition.name


func select_ammo(ammo: ItemStack) -> String:
	## Uyumlu silahlarin tercih ettigi mermi cesidi. Sarjordeki farkli cesit
	## cantaya geri konur (mermi kaybolmaz), sonra doldurma yeni cesidi alir.
	var changed := 0
	for stack: ItemStack in inventory.stacks:
		var wdef: WeaponDef = Content.weapons.get(stack.definition.weapon_id)
		if wdef == null or wdef.ammo_type != ammo.definition.ammo_type:
			continue
		if stack.ammo_id != ammo.definition.id and stack.loaded > 0 and stack.ammo_id != "":
			var old := Content.item(stack.ammo_id)
			if old != null and inventory.add(ItemStack.new(old, stack.loaded, 50.0)) == 0:
				stack.loaded = 0
		stack.ammo_id = ammo.definition.id
		changed += 1
	if changed == 0:
		return "Bu mermiyi kullanan silahın yok"
	return "%d silah artık %s kullanacak (R ile doldur)" % [changed, ammo.definition.name]


func use_repair_kit(kit: ItemStack) -> String:
	## Onarim kiti: hedefi etkisinden secer ve kiti HARCAR.
	var e := kit.definition.effects
	var amount := 0.0
	var target := ""
	if e.has("repair_weapon") and combat.state != null:
		var w: ItemStack = combat.state.stack
		if w.definition.durability > 0 and w.durability < w.definition.durability:
			amount = float(e.repair_weapon) * (0.7 + 0.6 * kit.quality / 100.0)
			w.durability = mini(w.definition.durability, w.durability + int(amount))
			target = w.definition.name
	if target == "" and (e.has("repair_armor") or e.has("repair_tool")):
		var worst: ItemStack = null
		for slot: String in equipment:
			var s: ItemStack = equipment[slot]
			if e.has("repair_armor") and s != null and s.definition.durability > 0 and s.durability < s.definition.durability:
				worst = s
		if worst == null and e.has("repair_tool"):
			for s: ItemStack in inventory.stacks:
				if s.definition.durability > 0 and s.durability < s.definition.durability and s.definition.category in ["tool", "weapon"]:
					if worst == null or float(s.durability) / s.definition.durability < float(worst.durability) / worst.definition.durability:
						worst = s
		if worst != null:
			amount = float(e.get("repair_armor", e.get("repair_tool", 0.0))) * (0.7 + 0.6 * kit.quality / 100.0)
			worst.durability = mini(worst.definition.durability, worst.durability + int(amount))
			target = worst.definition.name
	if target == "" and e.has("repair_vehicle"):
		var car := vehicles.nearest(player.global_position, 3.5)
		if not car.is_empty():
			var maximum := float(Vehicles.def_of(car).get("durability", 100))
			if float(car.durability) < maximum:
				amount = float(e.repair_vehicle)
				car.durability = minf(maximum, float(car.durability) + amount)
				target = str(Vehicles.def_of(car).get("name", "araç"))
	if target == "":
		return "Onarılacak uygun bir şey yok (silahı kuşan, hasarlı zırhı giy ya da aracın yanına git)"
	inventory.take_from_stack(kit, 1)
	refresh_skill_effects()
	progression.count("repaired")
	return "%s onarıldı (+%d)" % [target, int(amount)]


# ---------------------------------------------------------------------------
# Uretim isi
# ---------------------------------------------------------------------------
## URETIM KUYRUGU POLITIKASI (belgenin 3. bolumu, acikca):
##   * En fazla CRAFT_QUEUE_MAX is; ilki calisir (craft_job), digerleri bekler.
##   * GIRDI REZERVASYONU YOK: malzeme her adet TAMAMLANDIGINDA o anda
##     yeniden denetlenip tek islemde harcanir. Bu yuzden iptal ve kuyruktan
##     cikarma bedelsizdir: hicbir sey iade edilmez cunku hicbir sey alinmadi;
##     kopyalama da olamaz (ayni malzeme iki ise sayilmaz, harcama aninda biter).
##   * DURAKLAMA (iptal degil): istasyondan uzaklasma, istasyonun KIRILMASI,
##     tarifin gucu olup istasyonun ELEKTRIKSIZ kalmasi, ortak depo isinde
##     ussun disina cikma. Duraklayan is ilerlemez (bedelsiz uretim yok);
##     kosul duzelince kaldigi yerden devam eder.
##   * Dolu cikti alani: adet tamamlanamaz, is DURAKLAR ("yer ac" uyarisi).
##   * Kayit: kuyruk (tarif, kalan, ilerleme, istasyon, kaynak turu) kaydedilir.
func start_craft(recipe: RecipeDef, quantity: int, source: Inventory, station: String, tier: int) -> bool:
	if craft_queue.size() >= CRAFT_QUEUE_MAX:
		hud.message("Üretim kuyruğu dolu (en fazla %d iş)" % CRAFT_QUEUE_MAX, Hud.RED)
		return false
	var job := {"recipe": recipe, "remaining": mini(quantity, recipe.max_batch), "elapsed": 0.0, "source": source,
		"station": station, "tier": tier, "done": 0, "paused": "",
		"base": depot_base() if source != inventory else null}
	craft_queue.append(job)
	craft_job = craft_queue[0]
	craft_done_last = 0
	hud.message("Üretim %s: %d× %s" % ["başladı" if craft_queue.size() == 1 else "kuyruğa eklendi (%d. sıra)" % craft_queue.size(),
		job.remaining, recipe.name], Hud.ACCENT)
	return true


func dequeue_craft(index: int) -> void:
	## Kuyruktan cikar. Malzeme ALINMADIGI icin iade de yoktur (bkz. politika).
	if index < 0 or index >= craft_queue.size():
		return
	var job: Dictionary = craft_queue[index]
	craft_queue.remove_at(index)
	craft_job = craft_queue[0] if not craft_queue.is_empty() else {}
	hud.message("Kuyruktan çıkarıldı: %s (malzeme harcanmamıştı)" % (job.recipe as RecipeDef).name, Hud.ACCENT)


func _queue_dict() -> Array:
	var list: Array = []
	for job: Dictionary in craft_queue:
		list.append({"recipe": (job.recipe as RecipeDef).id, "remaining": int(job.remaining),
			"elapsed": snappedf(float(job.elapsed), 0.01), "station": job.station, "tier": int(job.tier),
			"done": int(job.done), "source": "bag" if job.source == inventory else "depot",
			"base": (job.base as Settlement).id if job.base != null else ""})
	return list


func _load_queue(raw: Variant) -> void:
	craft_queue.clear()
	craft_job = {}
	if typeof(raw) != TYPE_ARRAY:
		return
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY or not Content.recipes.has(str(entry.get("recipe", ""))):
			continue
		var base: Settlement = null
		var source: Inventory = inventory
		if str(entry.get("source", "bag")) == "depot":
			for b: Settlement in bases.settlements:
				if b.id == str(entry.get("base", "")):
					base = b
			if base == null:
				continue           # usu artik yok: is dusulur (malzeme alinmamisti)
			source = base.stockpile
		craft_queue.append({"recipe": Content.recipes[str(entry.recipe)], "remaining": maxi(1, int(entry.get("remaining", 1))),
			"elapsed": float(entry.get("elapsed", 0.0)), "source": source, "station": str(entry.get("station", "hands")),
			"tier": int(entry.get("tier", 1)), "done": int(entry.get("done", 0)), "paused": "", "base": base})
		if craft_queue.size() >= CRAFT_QUEUE_MAX:
			break
	craft_job = craft_queue[0] if not craft_queue.is_empty() else {}


func depot_base() -> Settlement:
	## Uretim/aktarim icin kullanilabilir us deposu: icinde bulunulan us; beceri
	## "Ortak depo kurallari" ile 80 m icindeki en yakin us da.
	if bases.inside != null:
		return bases.inside
	if not skills.has_behavior("remote_depot"):
		return null
	var best: Settlement = null
	var best_d := 80.0
	for base: Settlement in bases.settlements:
		var d := base.centre().distance_to(player.global_position)
		if d <= best_d:
			best_d = d
			best = base
	return best


func _after_craft(recipe: RecipeDef, source: Inventory) -> void:
	## Ustalik sayaclari ve agac davranislari (Kaynatma verimi, Filtre bakimi).
	if recipe.output_id == "water_bottle" and recipe.id != "r_decant_canister":
		progression.count("water_purified")
	if recipe.output_id == "cooked_meal":
		progression.count("meals_cooked")
	if recipe.id in ["r_boil_water", "r_boil_field"] and skills.has_behavior("boil_bonus"):
		if source.add(ItemStack.new(Content.item("water_bottle"), 1, 50.0)) == 0:
			hud.message("Kaynatma verimi: +1 sise", Hud.GREEN)
	if recipe.id == "r_filter_water" and skills.has_behavior("filter_saver") and _salvage_rng.randf() < 0.5:
		if source.add(ItemStack.new(Content.item("filter_cartridge"), 1, 50.0)) == 0:
			hud.message("Filtre bakimi: kartus tukenmedi", Hud.GREEN)
	Survival.stamp(source, time.total_hours())


func show_campaign_result() -> void:
	## Ana hedef tamam: sonuc ekrani. Dunya devam eder (oyun bitmez).
	var screen := Screen.new()
	screen.title = "Hayatta kalan agi kuruldu"
	screen.game = self
	screen.pauses_world = true
	open_screen(screen)
	var box := Screen.column(900)
	screen.body.add_child(box)
	var colonists: int = bases.colony.residents.size()
	box.add_child(UiTheme.label("Gun %d. Moda'dan Besiktas'a su, telsiz ve kopru hatti ayakta." % time.day, 26, UiTheme.ACCENT))
	box.add_child(UiTheme.label("Uslerin: %d   Sakinler: %d   Seviye: %d   Oldurulen: %d   Aranan dolap: %d" % [
		bases.settlements.size(), colonists, progression.level, progression.total_kills, progression.containers_looted], 20))
	box.add_child(UiTheme.label("Sehir hala tehlikeli: dalgalar gelmeye devam edecek, yan gorevler ve uzmanlik dallari acik. Istersen yeni us kur, yeni insanlar bul, agi genislet.", 20))
	box.add_child(UiTheme.button("Devam et", close_screen))


func cancel_craft() -> void:
	if not craft_job.is_empty():
		dequeue_craft(0)


func _pause_job(job: Dictionary, reason: String) -> void:
	if str(job.get("paused", "")) != reason:
		job.paused = reason
		if reason != "":
			hud.message("Üretim duraklatıldı: %s" % reason, Hud.RED)


func craft_block_reason(job: Dictionary) -> String:
	## Isin su an ilerleyememe nedeni (bos = ilerler).
	var recipe: RecipeDef = job.recipe
	var station: String = job.station
	if station != "hands":
		var info := placeables.best_station(player.global_position)
		if not info.available.has(station):
			return "%s yakında değil (ya da kırıldı)" % RecipeDef.STATION_NAMES.get(station, station)
		if recipe.power > 0.0:
			var entry: Dictionary = info.entries.get(station, {})
			entry["active"] = true
			if not bool(entry.get("powered", false)):
				return "istasyonun elektriği yok (%d W gerekli)" % int(recipe.power)
	if job.base != null and depot_base() != job.base:
		return "ortak depo işi için üssün içinde olmalısın"
	return ""


func _update_craft_job(delta: float) -> void:
	# Istasyonlarin "uretimde" bayragi her kare yeniden kurulur (guc talebi).
	for entry: Dictionary in placeables.entries:
		if entry.kind == "station":
			entry["active"] = false
	if craft_queue.is_empty() or vitals.dead:
		craft_job = {}
		return
	craft_job = craft_queue[0]
	var reason := craft_block_reason(craft_job)
	if reason != "":
		craft_job["pause_kind"] = "condition"
		_pause_job(craft_job, reason)
		return
	if str(craft_job.get("pause_kind", "")) == "condition":
		craft_job["pause_kind"] = ""
		_pause_job(craft_job, "")        # kosul duzeldi: devam
	craft_job.elapsed += delta
	var recipe: RecipeDef = craft_job.recipe
	if craft_job.elapsed < recipe.time:
		return
	# Tamamlanma aninda yeniden denetle: o arada malzeme harcandiysa uretim
	# DURUR, esya yakilmaz; dolu cantada adet tamamlanmaz (is duraklar).
	var result := crafting.craft(craft_job.source, recipe, craft_job.station, int(craft_job.tier),
		skills.bonus("craft_quality") * 100.0)
	if result.success:
		craft_job.elapsed = 0.0
		craft_job["pause_kind"] = ""
		craft_job.paused = ""
		var output: ItemStack = result.output
		hud.message("Üretildi: %s ×%d" % [output.display_name(), output.quantity], Hud.GREEN)
		sfx.play_ui("craft_done")
		progression.on_craft(output.definition.tier, recipe.id)
		_after_craft(recipe, craft_job.source)
		quests.notify("craft", {"recipe": recipe.id})
		craft_job.done = int(craft_job.done) + 1
		craft_done_last = int(craft_job.done)
	elif result.consumed.is_empty():
		# Adet tamamlanamadi, hicbir sey harcanmadi: is BEKLER ve saniyede bir
		# yeniden dener (malzeme gelince / yer acilinca kendiliginden devam).
		craft_job.elapsed = recipe.time - 1.0
		craft_job["pause_kind"] = "craft"
		if str(result.reason).begins_with("Canta") or str(result.reason).begins_with("Yan urun"):
			_pause_job(craft_job, "çıktı için yer yok")
		else:
			_pause_job(craft_job, str(result.reason))
		return
	else:
		craft_job.elapsed = 0.0
		hud.message(result.reason, Hud.RED)       # basarisizlik: malzeme gitti, urun yok
	craft_job.remaining -= 1
	if craft_job.remaining <= 0:
		craft_queue.pop_front()
		craft_job = craft_queue[0] if not craft_queue.is_empty() else {}
	if current_screen != null:
		current_screen.refresh()


# ---------------------------------------------------------------------------
# Olaylar
# ---------------------------------------------------------------------------
func on_noise_at(position: Vector3, radius: float) -> void:
	zombies.emit_noise(position, radius)


func _on_block_destroyed(cell: Vector3i, value: int, origin: int) -> void:
	## Kurtarma dususu yalnizca HARITANIN KENDI blogundan ve nadiren.
	## Oyuncunun koydugu blok dusus VERMEZ; her hucre bir kez kirilir.
	if origin != VoxelWorld.ORIGIN_WORLD:
		return
	var def := Content.blocks.get_def(value)
	var drops: Array = []
	for entry: Dictionary in def.get("salvage", []):
		if _salvage_rng.randf() < float(entry.get("chance", 0.0)):
			var count: Array = entry.get("count", [1, 1])
			var item := Content.item(entry.item)
			if item != null:
				drops.append(ItemStack.new(item, _salvage_rng.randi_range(int(count[0]), int(count[1])), 20.0))
	if not drops.is_empty():
		pickups.spawn(drops, Vector3(cell) + Vector3(0.5, 0.1, 0.5), "Enkaz")


func _on_actor_hit(actor: Object, killed: bool, _zone: String) -> void:
	if killed and actor is Zombie:
		var melee: bool = combat.state != null and combat.state.weapon.is_melee()
		progression.on_kill((actor as Zombie).def.id, melee)
		quests.notify("kill", {"zombie": (actor as Zombie).def.id})


func _on_zombie_strike(zombie: Zombie, amount: float, direction: Vector3) -> void:
	var dealt := vitals.take_hit(amount, "physical", direction)
	if dealt > 0.0 and zombie.def.bite_status != "" and zombie.def.bite_duration > 0.0:
		vitals.statuses.apply(zombie.def.bite_status, zombie.def.bite_duration, zombie.def.bite_magnitude)
		hud.message("%s: %s!" % [zombie.def.name, StatusEffects.LABELS.get(zombie.def.bite_status, "")], Hud.RED)
	player.velocity += Vector3(direction.x, 0, direction.z) * 2.5


func _on_player_damaged(amount: float, direction: Vector3) -> void:
	# Zirh ve kask darbe aldikca asinir; biten parca korumaz (onarim kiti ile duzelir).
	for slot: String in ["armor", "helmet"]:
		var worn: ItemStack = equipment.get(slot)
		if worn != null and worn.definition.durability > 0 and not worn.broken():
			worn.durability = maxi(0, worn.durability - maxi(1, int(amount / 8.0)))
			if worn.broken():
				hud.message("%s parçalandı -- artık korumuyor (onarım kiti ya da tezgâh)" % worn.definition.name, Hud.RED)
				refresh_skill_effects()
	var local := player.head.global_basis.inverse() * direction
	hud.hurt(amount, atan2(local.x, -local.z))
	player.add_trauma(clampf(amount / 25.0, 0.1, 0.6))
	sfx.play_at("player_hurt", player.eye_position(), -4.0)
	if search != null:
		search.on_player_damaged()
	_action = {}
	abilities.interrupt()


func _on_footstep() -> void:
	var below := world.get_block(floori(player.position.x), floori(player.position.y - 0.2), floori(player.position.z))
	var soft: bool = below > 0 and below != VoxelWorld.BOUNDARY \
		and Content.blocks.get_def(below).get("impact_sound_id", "") in ["impact_dirt", "impact_leaves"]
	sfx.play_at("footstep_soft" if soft else "footstep_hard", player.position, -14.0 if not player.sprinting else -9.0, 0.15)
	if player.sprinting:
		# Kosmak ses cikarir (gizlilik becerisi ve sessiz giysi daraltir).
		on_noise_at(player.global_position, Units.perception_m(90.0) * skills.multiplier("noise_radius")
			* (1.0 - clampf(equipment_bonus("noise_bonus"), 0.0, 0.7)))


# ---------------------------------------------------------------------------
# Olum: kalici yenilgi degil, GERI KAZANILABILIR kayip (eski oyunun kurali)
#   1. Ussunde uyanirsin; us yoksa (ya da hepsi aciksa) oyun gercekten biter.
#   2. Cantan dustugun yerde kalir (haritada X).
#   3. 48 oyun-saati gecer: erzak tukenir, dalga yaklasir.
# ---------------------------------------------------------------------------
func _on_player_died() -> void:
	if _death_handled:
		return
	_death_handled = true
	player.alive = false
	craft_queue.clear()
	craft_job = {}
	if search != null:
		search.cancel()
	var base := bases.respawn_base()
	if base == null:
		_game_over()
		return
	for slot: String in equipment:
		if equipment[slot] != null:
			inventory.stacks.append(equipment[slot])
			equipment[slot] = null
	refresh_skill_effects()
	if not inventory.stacks.is_empty():
		var stacks := inventory.stacks.duplicate()
		inventory.clear()
		pickups.spawn(stacks, player.global_position + Vector3(0, 0.2, 0), "Cantan (olum)", "pack")
	combat.load_dict({"slots": [-1, -1, -1, -1], "active": -1})
	var turned := time.advance_hours(DEATH_LOST_HOURS)
	for i in turned:
		_resolve_skipped_night(time.day - turned + i)
		_on_new_day()
	player.teleport(base.centre() + Vector3(0, 0.2, 0))
	vitals.revive(DEATH_WAKE_HEALTH)
	# DIRILME IHTIYAC POLITIKASI: 48 saatlik atlama oyuncunun toklugunu
	# ISLEMEZ (baygin yatarken ussun insanlari bakti). Us deposundan GERCEKTEN
	# bir yiyecek ve bir su harcanir; stok yoksa oyuncu zayif uyanir ama
	# hemen olmez (yeniden olum zinciri yok).
	var policy: Dictionary = Content.nutrition.get("respawn", {})
	var fed := _consume_base_ration(base, "food")
	var watered := _consume_base_ration(base, "water")
	var floor_food := float(policy.get("min_satiety", 55)) if fed else float(policy.get("without_stock", 35))
	var floor_water := float(policy.get("min_hydration", 55)) if watered else float(policy.get("without_stock", 35))
	vitals.satiety = maxf(vitals.satiety, floor_food)
	vitals.hydration = maxf(vitals.hydration, floor_water)
	player.alive = true
	_death_handled = false
	hud.message("Ussunde uyandin. 48 saat gecti; cantan oldugun yerde (haritada X).", Hud.ACCENT)
	hud.message("Us deposundan %s ve %s verildi." % ["yemek" if fed else "yemek YOKTU", "su" if watered else "su YOKTU"],
		Hud.GREEN if fed and watered else Hud.RED)


func _consume_base_ration(base: Settlement, kind: String) -> bool:
	## Ussun deposundan tek bir tuketilebilir porsiyon (beslenme tablosundan).
	for stack: ItemStack in base.stockpile.stacks:
		var info := Content.nutrition_of(stack.definition.id)
		if float(info.get(kind, 0.0)) > 0.0 and float(info.get("illness", 0.0)) <= 0.0:
			base.stockpile.take_from_stack(stack, 1)
			var back := str(info.get("returns", ""))
			if back != "":
				base.stockpile.add(ItemStack.new(Content.item(back), 1, 0.0))
			return true
	return false


func _resolve_skipped_night(day: int) -> void:
	## Atlanan gece bir dalga gecesiyse TANIMLI kuralla ve BIR KEZ cozulur:
	## savunma gucu (nobetci, taret, barikat) dalgaya karsi olculur.
	if not (day >= waves.first_wave_day and (day - waves.first_wave_day) % waves.interval == 0):
		return
	var size := waves.wave_size(day)
	for base: Settlement in bases.settlements:
		var guards := bases.colony.members(base.id).filter(func(r: Dictionary) -> bool: return r.role == "guard").size()
		var turrets := placeables.entries.filter(func(e: Dictionary) -> bool:
			return e.kind == "turret" and base.contains_position(Vector3(e.cell))).size()
		var walls := 0
		for cell: Vector3i in world.placed:
			if Vector2(cell.x, cell.z).distance_to(Vector2(base.seed_cell)) < Settlement.MAX_RADIUS:
				walls += 1
		var defense := guards * 8.0 + turrets * 12.0 + walls * 0.5
		var ammo_used := mini(base.stockpile.count(Content.colony.settings.guard_ammo), size / 2)
		base.stockpile.remove(Content.colony.settings.guard_ammo, ammo_used)
		if defense >= size * 0.6 and not base.breached:
			hud.message("Sen yokken %s dalgayi puskurttu (%d fisek harcandi)." % [base.name, ammo_used], Hud.GREEN)
		else:
			for resource_id: String in ["food", "water"]:
				var resource := Content.resources.get_resource(resource_id)
				var stock := Content.resources.stock(base.stockpile, resource)
				Content.resources.consume(base.stockpile, resource, stock * 0.25)
			for r: Dictionary in bases.colony.members(base.id):
				r.health = maxf(1.0, float(r.health) - 20.0)
			hud.message("Sen yokken dalga %s'i zorladi: erzak ve saglik kaybi." % base.name, Hud.RED)
	waves.survived += 1


func _game_over() -> void:
	var screen := Screen.new()
	screen.title = "Öldün — üssün yoktu"
	screen.game = self
	screen.pauses_world = true
	open_screen(screen)
	# Govde yatay kutudur: metin sutunsuz eklenirse genisligi sifira coker
	# ve harf harf alt alta dizilirdi.
	var box := Screen.column(760)
	box.add_theme_constant_override("separation", 16)
	screen.body.add_child(box)
	var text := UiTheme.label("Gün %d · seviye %d · %d zombi. Üs kurmadan ölüm oyunu bitirir." % [
		time.day, progression.level, progression.total_kills], 24)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	box.add_child(UiTheme.primary_button("Son kaydı yükle", func() -> void: request_load(SaveSystem.AUTOSAVE)))
	box.add_child(UiTheme.button("Ana menü", to_main_menu))


# ---------------------------------------------------------------------------
# Ekranlar
# ---------------------------------------------------------------------------
func open_screen(screen: Screen) -> void:
	if current_screen != null:
		close_screen()
	screen.game = self
	screen_layer.add_child(screen)
	screen.build()
	screen.closed.connect(close_screen)
	current_screen = screen
	ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if screen.pauses_world:
		get_tree().paused = true


func close_screen() -> void:
	if current_screen == null:
		return
	var screen := current_screen
	current_screen = null
	screen.queue_free()
	ui_open = false
	get_tree().paused = false
	if ready_for_play and not vitals.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _toggle_screen(script: GDScript) -> void:
	if current_screen != null and current_screen.get_script() == script:
		close_screen()
		return
	open_screen(script.new())


func show_leaks(leaks: Array) -> void:
	## "Neden us kurulmuyor?" -- acik gecitler dunyada kirmizi sutunla.
	for marker: Node in _leak_markers:
		marker.queue_free()
	_leak_markers.clear()
	for cell: Vector2i in leaks:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.6, 6.0, 0.6)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1, 0.15, 0.1, 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box.material = material
		mesh.mesh = box
		mesh.position = Vector3(cell.x + 0.5, nav.column(cell.x, cell.y)[0] + 3.0, cell.y + 0.5)
		add_child(mesh)
		_leak_markers.append(mesh)
	_leak_timer = 30.0


func _update_leak_markers(delta: float) -> void:
	if _leak_markers.is_empty():
		return
	_leak_timer -= delta
	if _leak_timer <= 0.0:
		show_leaks([])


func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_play:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		weapon_view.add_sway((event as InputEventMouseMotion).relative)
	if ui_open:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Pencereye donus tiklamasi ATES DEGILDIR: yalnizca fareyi yakalar.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if vitals.dead:
		return
	if event.is_action_pressed("pause"):
		open_screen(PauseScreen.new())
	elif event.is_action_pressed("inventory") or event.is_action_pressed("inventory_alt"):
		_toggle_screen(InventoryScreen)
	elif event.is_action_pressed("craft"):
		_toggle_screen(CraftingScreen)
	elif event.is_action_pressed("map"):
		if generator is CityGenerator:
			_toggle_screen(MapScreen)
	elif event.is_action_pressed("colony"):
		_toggle_screen(ColonyScreen)
	elif event.is_action_pressed("skills"):
		_toggle_screen(SkillsScreen)
	elif event.is_action_pressed("journal"):
		_toggle_screen(JournalScreen)
	elif event.is_action_pressed("quick_eat"):
		survival.quick("food")
	elif event.is_action_pressed("quick_drink"):
		survival.quick("water")
	elif event.is_action_pressed("build"):
		build.toggle()
	elif event.is_action_pressed("quick_save"):
		save_game(SaveSystem.QUICKSAVE)
	elif event.is_action_pressed("quick_load"):
		request_load(SaveSystem.QUICKSAVE)
	elif build.active:
		if event.is_action_pressed("fire"):
			build.confirm()
		elif event.is_action_pressed("reload"):
			build.rotation_steps = (build.rotation_steps + 1) % 4
		elif event.is_action_pressed("weapon_next"):
			build.cycle(1)
		elif event.is_action_pressed("weapon_prev"):
			build.cycle(-1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and ready_for_play and not ui_open:
		# Alt-Tab: fareyi birak ve oyunu duraklat; donuste menuden devam.
		# Olcum/ekran goruntusu kosulari odak kaybinda duraklamaz (olcum bozulurdu).
		if not _args.has("shot") and not _args.has("script"):
			open_screen(PauseScreen.new())


# ---------------------------------------------------------------------------
# Hazirlik, kayit
# ---------------------------------------------------------------------------
func _on_world_ready() -> void:
	ready_for_play = true
	hud.progress = -1.0
	# Yuklenen oyuncu bir duvar/mobilya icinde kalmissa (kayit gocu: eski dolu
	# binanin yerinde artik oda duvari olabilir) en yakin bos noktaya al.
	player.teleport(free_spot(player.position))
	if not _args.has("shot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _pending_load.is_empty():
		hud.message("%s · [I] envanter  [C] üretim  [B] inşa  [L] koloni  [M] harita  [E] ara/al" % map_name, Hud.ACCENT)
		hud.message("Binalara kapıdan gir, dolapları tek tek ara (E). Sokağı barikatla kapatıp üs kur (L). İlk dalgaya 6 gün var.", Hud.ACCENT)
		var seed_count := int(_args.get("zombies", "12" if site == "test" else str(ZombieManager.BASE_POPULATION)))
		if population == null:
			zombies.seed_population(player.global_position, seed_count, _zombie_context())
		if generator is CityGenerator:
			vehicles.spawn_parked(generator)
	_pending_load = {}
	world_ready.emit()
	if _args.has("script"):
		_run_script(str(_args.script))
	if _args.has("screen"):
		# Arayuz incelemesi: --screen=craft|inventory|pause|map|colony|skills|journal
		var screens := {"craft": CraftingScreen, "inventory": InventoryScreen, "map": MapScreen,
			"colony": ColonyScreen, "skills": SkillsScreen, "journal": JournalScreen, "pause": PauseScreen}
		var chosen: GDScript = screens.get(str(_args.screen))
		if chosen != null:
			open_screen(chosen.new())
	if _args.has("shot"):
		# Duraklatan ekranlarda da (harita, Esc) calissin diye duraklamadan
		# etkilenmeyen zamanlayici.
		_shot_timer = -1.0
		get_tree().create_timer(float(_args.get("shot-delay", "1.0")), true).timeout.connect(
			func() -> void: _take_screenshot(str(_args.shot)))


func _autosave(delta: float) -> void:
	## Yalnizca oyuncu yasarken ve YUKLEME HATASI YOKKEN: olum aninda kaydetmek
	## oyuncuyu kacinilmaz olume kilitlerdi; bozuk kaydin ustune yazmak da
	## son saglam kaydi yok ederdi.
	if vitals.dead or load_failed:
		return
	# Teshis/olcum kosulari (--shot, --script) oyuncunun gercek otomatik
	# kaydini EZMEZ: olcum senaryosu 3 dakikayi asabiliyor.
	if _args.has("shot") or _args.has("script"):
		return
	_autosave_timer -= delta
	if _autosave_timer > 0.0:
		return
	_autosave_timer = AUTOSAVE_INTERVAL
	if save_game(SaveSystem.AUTOSAVE, false):
		hud.message("Otomatik kayit", Hud.GREEN)


func free_spot(position: Vector3) -> Vector3:
	## Govdenin sigdigi en yakin nokta: once yatayda halka halka (ayni kat),
	## sonra yukari. Duvara gomulu dogan oyuncu kilitlenmesin.
	if not VoxelBody.is_blocked(world, position, Player.HALF_WIDTH, Player.STAND_HEIGHT):
		return position
	for r in range(1, 6):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				for dy: float in [0.0, 0.5, -0.5, 1.0]:
					var candidate := position + Vector3(dx, dy, dz)
					if not VoxelBody.is_blocked(world, candidate, Player.HALF_WIDTH, Player.STAND_HEIGHT) \
							and VoxelBody.is_blocked(world, candidate - Vector3(0, 0.3, 0), Player.HALF_WIDTH, Player.STAND_HEIGHT):
						return candidate
	return VoxelBody.unstick(world, position, Player.HALF_WIDTH, Player.STAND_HEIGHT)


func save_game(slot: String, loud: bool = true) -> bool:
	if vitals.dead:
		hud.message("Olu iken kaydedilemez", Hud.RED)
		return false
	var ok := saves.write(slot, _collect_save())
	if loud:
		hud.message("Kaydedildi (%s)" % slot if ok else "Kayit basarisiz: %s" % saves.last_error, Hud.GREEN if ok else Hud.RED)
	if ok:
		load_failed = false
	return ok


func _collect_save() -> Dictionary:
	return {
		"world": {"site": site, "map_id": map_id, "generator_version": generator_version, "voxels": world.to_dict()},
		"player": {"body": player.to_dict(), "vitals": vitals.to_dict(), "inventory": inventory.to_dict(),
			"loadout": combat.to_dict(), "progression": progression.to_dict(), "abilities": abilities.to_dict()},
		"time": time.to_dict(), "waves": waves.to_dict(), "zombies": zombies.to_dict(),
		"population": population.to_dict() if population != null else {},
		"pickups": pickups.to_dict(),
		"containers": containers.to_dict() if containers != null else {},
		"doors_broken": interiors.broken_doors.keys() if interiors != null else [],
		"bases": bases.to_dict(), "placeables": placeables.to_dict(), "survivors": survivors.to_dict(),
		"vehicles": vehicles.to_dict(),
		"equipment": _equipment_dict(),
		"craft_queue": _queue_dict(),
		"build": build.to_dict(),
		"schematics": crafting.known_recipes.keys(),
		"waypoint": [waypoint.x, waypoint.y, waypoint.z] if waypoint != Vector3.INF else [],
		"quests": quests.to_dict(),
		"transform": (generator as CityGenerator).geo.to_dict() if generator is CityGenerator else {},
	}


func _apply_save(data: Dictionary) -> void:
	## Dunya farklari chunk uretiminden ONCE uygulanir: kirilan duvar bir
	## kare bile saglam gorunmez.
	world.load_dict(data.get("world", {}).get("voxels", {}))
	time.load_dict(data.get("time", {}))
	waves.load_dict(data.get("waves", {}))
	var p: Dictionary = data.get("player", {})
	player.load_dict(p.get("body", {}))
	terrain.focus = player.position
	vitals.load_dict(p.get("vitals", {}))
	inventory.load_dict(p.get("inventory", {}), Content.items)
	progression.load_dict(p.get("progression", {}))
	var gear: Dictionary = data.get("equipment", {})
	for slot: String in equipment:
		var raw: Variant = gear.get(slot, {})
		equipment[slot] = ItemStack.from_dict(raw, Content.items) if typeof(raw) == TYPE_DICTIONARY and not raw.is_empty() else null
	crafting.known_recipes.clear()
	for recipe_id: Variant in data.get("schematics", []):
		if Content.recipes.has(str(recipe_id)):
			crafting.known_recipes[str(recipe_id)] = true
	refresh_skill_effects()
	abilities.load_dict(p.get("abilities", {}))
	combat.load_dict(p.get("loadout", {}))
	pickups.load_dict(data.get("pickups", {}))
	if containers != null:
		if int(data.get("version", SaveSystem.VERSION)) < 2 and not data.has("migration"):
			# KAYIT GOCU v1 -> v2: bina arama haklari container durumuna cevrilir.
			var report := containers.migrate_v1(data.get("buildings", {}), time.day)
			_migrated = true
			hud.message("Eski kayit aktarildi: %d binanin arama gecmisi dolaplara islendi" % report.buildings, Hud.ACCENT)
		else:
			containers.load_dict(data.get("containers", {}))
		interiors.broken_doors.clear()
		for door_id: Variant in data.get("doors_broken", []):
			interiors.broken_doors[str(door_id)] = true
		interiors.refresh_all()
	bases.load_dict(data.get("bases", {}), time.day)
	placeables.load_dict(data.get("placeables", {}))
	survivors.load_dict(data.get("survivors", {}))
	vehicles.load_dict(data.get("vehicles", {}))
	zombies.load_dict(data.get("zombies", {}))
	if population != null:
		population.load_dict(data.get("population", {}))
		population.adopt_loaded(zombies.zombies)
	if data.get("waves", {}).get("active_day", 0) != 0:
		zombies.wave_target = waves.wave_size(waves.active_day)
		zombies.wave_focus = _wave_focus()
	var w: Array = data.get("waypoint", [])
	waypoint = Vector3(w[0], w[1], w[2]) if w.size() == 3 else Vector3.INF
	quests.load_dict(data.get("quests", {}))
	_load_queue(data.get("craft_queue", []))
	build.load_dict(data.get("build", {}))
	sync_learned()
	_sync_colony_capacity()
	power.mark_dirty()
	hud.message("Kayit yuklendi: Gun %d %s" % [time.day, time.clock()], Hud.GREEN)


func request_load(slot: String) -> void:
	if not saves.exists(slot):
		hud.message("Kayit yok: %s" % slot, Hud.RED)
		return
	get_tree().paused = false
	request_restart.emit(slot)


func to_main_menu() -> void:
	get_tree().paused = false
	request_main_menu.emit()


# ---------------------------------------------------------------------------
# Teshis
# ---------------------------------------------------------------------------
func _run_script(name: String) -> void:
	match name:
		"shoot_walls":
			var x := -28
			for _i in 7:
				var eye := Vector3(x + 1.5, 1.5, 6.0)
				for _s in 4:
					hitscan.fire(eye, Vector3(0, 0, 1), eye, 40.0, 26.0, "physical", 0, "player", player)
				x += 6
			combat.equip(0)
		"zombie_demo":
			var forward := player.look_direction()
			forward.y = 0.0
			forward = forward.normalized()
			var right := forward.cross(Vector3.UP)
			var ids := ["walker", "runner", "brute", "worker", "armored"]
			for i in ids.size():
				var position := player.global_position + forward * (9.0 + i * 1.5) + right * ((i - 2) * 2.2)
				var z := zombies.spawn(Content.zombies[ids[i]], Vector3(position.x, player.global_position.y, position.z))
				z.facing = -forward
			combat.equip(0)
		"inventory":
			open_screen(InventoryScreen.new())
		"crafting":
			var crafting_screen := CraftingScreen.new()
			open_screen(crafting_screen)
			if _args.has("recipe") and Content.recipes.has(str(_args.recipe)):
				crafting_screen._select(Content.recipes[str(_args.recipe)], false)
		"colony":
			open_screen(ColonyScreen.new())
		"map":
			open_screen(MapScreen.new())
		"pause":
			open_screen(PauseScreen.new())
		"build":
			build.toggle()
			build.index = 3
		"bench":
			_run_bench()
		"night":
			time.normalized = 0.93
			flashlight.visible = true
			combat.equip(0)
		"car":
			if not vehicles.entries.is_empty():
				var best: Dictionary = vehicles.entries[0]
				for entry: Dictionary in vehicles.entries:
					if entry.position.distance_to(player.global_position) < best.position.distance_to(player.global_position):
						best = entry
				var p: Vector3 = best.position + Vector3(4.5, 0.3, 3.0)
				player.teleport(p)
				var to: Vector3 = best.position - p
				player.yaw = atan2(-to.x, -to.z)
				player.pitch = -0.2
		"interior":
			# Ic mekan teshisi: istenen yerlesimdeki (--layout=market) en yakin
			# binanin kapisini ac, oyuncuyu iceri, odaya bakar halde koy.
			var wanted_layout := str(_args.get("layout", "apartment"))
			var city: CityGenerator = generator
			for radius: float in [60.0, 200.0, 600.0]:
				var best := {}
				for index: int in city.buildings_near(player.global_position, radius):
					var plan := city.interior_plan(index)
					if plan.get("ok", false) and plan.layout == wanted_layout:
						best = plan
						break
				if best.is_empty():
					continue
				var door: Dictionary = best.doors[0]
				if interiors.door_state(best, door) == "closed":
					interiors.toggle_door(best, door, Callable())
				# Kat girisinde dur, katin en buyuk odasinin merkezine bak. --floor=k
				# ile ust kat (merdiven varisi), --stairs ile merdiven kalkisina bakis.
				var k := clampi(int(_args.get("floor", "0")), 0, int(best.accessible) - 1)
				var fl: Dictionary = best.floors[k]
				var inside: Vector2i = fl.entry
				var target := Vector2(inside) + Vector2(door.outward) * -3.0
				var biggest := 0
				for room: Dictionary in fl.rooms:
					if room.cells.size() > biggest and room.type != "corridor":
						biggest = room.cells.size()
						var sum := Vector2.ZERO
						for c: Vector2i in room.cells:
							sum += Vector2(c)
						target = sum / room.cells.size()
				if _args.has("stairs") and not best.stairs.is_empty():
					inside = best.stairs.exit
					target = Vector2(best.stairs.entry) + (Vector2(best.stairs.entry) - Vector2(best.stairs.exit)) * 0.0
					for c: Vector2i in best.stairs.cells:
						target = Vector2(c)
						break
				player.teleport(Vector3(inside.x + 0.5, float(fl.y) + 0.05, inside.y + 0.5))
				var to := target - Vector2(inside)
				player.yaw = atan2(-to.x, -to.y)
				player.pitch = deg_to_rad(float(_args.get("look-pitch", "-8")))
				terrain.focus = player.position
				if _args.has("time"):
					time.normalized = float(_args.time)     # gece okunurluk denetimi
					flashlight.visible = _args.has("flashlight")
				break
		"loot":
			# Loot paneli teshisi: en yakin binada bir dolabi ara ve paneli ac.
			var city: CityGenerator = generator
			for index: int in city.buildings_near(player.global_position, 300.0):
				var plan := city.interior_plan(index)
				if not plan.get("ok", false) or plan.layout != str(_args.get("layout", "apartment")):
					continue
				var chosen := {}
				for f: Dictionary in plan.furniture:
					if f.container != "" and int(f.floor) == 0 and not f.get("access", []).is_empty():
						chosen = f
						break
				if chosen.is_empty():
					continue
				var a: Vector2i = chosen.access[0]
				player.teleport(Vector3(a.x + 0.5, float(plan.floors[0].y) + 0.05, a.y + 0.5))
				var to: Vector3 = chosen.origin - player.position
				player.yaw = atan2(-to.x, -to.z)
				player.pitch = -0.3
				terrain.focus = player.position
				await get_tree().create_timer(1.0).timeout
				search.begin(plan, chosen, player.global_position)
				search.update(999.0, player.global_position)
				break
		"drive":
			# Surucu koltugu teshisi: istenen modeldeki (--car=van) en yakin araca bin.
			var wanted := str(_args.get("car", ""))
			var chosen: Dictionary = {}
			for entry: Dictionary in vehicles.entries:
				if wanted != "" and entry.model_id != wanted:
					continue
				if chosen.is_empty() or entry.position.distance_to(player.global_position) \
						< chosen.position.distance_to(player.global_position):
					chosen = entry
			if not chosen.is_empty():
				chosen.durability = maxf(float(chosen.durability), 50.0)
				if vehicles.enter(chosen) == "":
					weapon_view.visible = false
					player.driving = true
					player.pitch = float(_args.get("look-pitch", "-0.05"))
					_drive_look_offset = deg_to_rad(float(_args.get("look-yaw", "0")))
					player.yaw = float(chosen.yaw) + _drive_look_offset
					if _args.has("throttle"):
						_bench_drive = Vector2(float(_args.throttle), float(_args.get("steer", "0")))


func _run_bench() -> void:
	## Olcum senaryosu (belgenin 9. bolumu): ayni sahnede gezinme, arka
	## arkaya duvar kirma, kalabalik saldiri. Her evre icin ortalama FPS,
	## p95/p99 kare suresi, chunk guncelleme gecikmesi, RAM/VRAM, gorunur
	## ilkel sayisi ve uyanik AI yazilir. Arac gecisi ve (koridor haritasinda)
	## arac hizinda uzun yol akisi da olculur.
	var tree := get_tree()
	player.input_enabled = false
	# Olcum oyuncunun hayatta kalmasini degil cizimi/akisi olcer: gezinmede
	# catidan dusup olmek (olum ekrani dunyayi durdurur) sonraki evreleri bozardi.
	vitals.health = 100000.0
	var start := player.global_position
	var report := func(name: String) -> void:
		var r := perf.report()
		print("OLCUM %-16s FPS %5.0f  ort %5.2f ms  p95 %5.2f  p99 %5.2f  maks %6.2f | mesh maks %5.1f ms son %4.1f atilan %d | chunk %d mesh %d | uyanik AI %d | cizim %d ilkel %d | VRAM %.0f MB RAM %.0f MB" % [
			name, r.fps, r.avg_ms, r.p95_ms, r.p99_ms, r.max_ms, terrain.stats.max_mesh_usec / 1000.0,
			terrain.stats.last_mesh_usec / 1000.0, terrain.stats.discarded, world.chunks.size(), terrain.mesh_node_count(),
			zombies.awake_count,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
			OS.get_static_memory_usage() / 1048576.0])
		print("  en kotu bolumler (ms): ", perf.worst_sections())
		if population != null:
			print("  nufus: ", population.near_counts(player.global_position))
		perf.reset()
		terrain.stats.max_mesh_usec = 0
	zombies.clear()
	perf.reset()
	await tree.create_timer(6.0).timeout
	report.call("bosta")
	# Ic mekan: en yakin apartmanin icinde 6 sn etrafa bakis (mobilya GLB
	# dugumleri, gizli katı hucreler, kapilar). Sonra ayni noktaya donulur.
	if generator is CityGenerator and interiors != null:
		var city_bench: CityGenerator = generator
		for index: int in city_bench.buildings_near(start, 250.0):
			var plan := city_bench.interior_plan(index)
			if not plan.get("ok", false) or plan.layout != "apartment":
				continue
			var door: Dictionary = plan.doors[0]
			if interiors.door_state(plan, door) == "closed":
				interiors.toggle_door(plan, door, Callable())
			var inside: Vector2i = door.cell - door.outward
			player.teleport(Vector3(inside.x + 0.5, float(plan.floors[0].y) + 0.05, inside.y + 0.5))
			await tree.create_timer(1.5).timeout
			perf.reset()
			var look := 0.0
			while look < 6.0:
				await tree.physics_frame
				look += get_physics_process_delta_time()
				player.yaw += get_physics_process_delta_time() * 1.0
			report.call("ic_mekan")
			print("  ic mekan: %d bina gorseli yuklu" % interiors.loaded_count())
			player.global_position = start
			break
	# Gezinme: sokak boyunca 8 m/sn (chunk akisi).
	var t := 0.0
	while t < 12.0:
		await tree.physics_frame
		t += get_physics_process_delta_time()
		player.yaw += get_physics_process_delta_time() * 0.3
		var dir := Vector3(sin(t * 0.35), 0, cos(t * 0.35))
		player.global_position = VoxelBody.unstick(world, player.global_position + dir * 8.0 * get_physics_process_delta_time(), 0.3, 1.8)
	report.call("gezinme")
	if interiors != null:
		print("  ic mekan: tek bina gorseli en fazla %.1f ms" % (interiors.load_usec_max / 1000.0))
	# Arka arkaya duvar kirma: en yakin cepheye 240 atis (tabanca hasari).
	player.global_position = start
	var hits := 0
	var destroyed := 0
	for i in 240:
		var angle := i * 0.21
		var dir := Vector3(cos(angle), -0.05, sin(angle)).normalized()
		var result := hitscan.fire(player.eye_position(), dir, player.eye_position(), 40.0, 26.0, "physical", 0, "player", player)
		for impact: Dictionary in result.impacts:
			if impact.kind == "block":
				hits += 1
				if impact.destroyed:
					destroyed += 1
		if i % 4 == 0:
			await tree.process_frame
	await tree.create_timer(3.0).timeout
	report.call("duvar_kirma")
	print("  duvar kirma: %d isabet, %d blok yikildi" % [hits, destroyed])
	# Arac: en yakin araca bin, 10 sn tam gaz + salinan direksiyon. Carparsa
	# durur (arac blok kirmaz); olcum surus fizigi + akis icindir.
	var car: Dictionary = {}
	for entry: Dictionary in vehicles.entries:
		# Onu en az 25 m acik olan en yakin arac (duvara bakan secilirse olcum
		# surusu degil carpismayi olcer).
		var yaw: float = entry.yaw
		var ahead := Vector3(-sin(yaw), 0, -cos(yaw))
		var clear := true
		for step in range(3, 9, 2):
			var probe: Vector3 = entry.position + ahead * step + Vector3(0, 1.0, 0)
			if world.get_block(floori(probe.x), floori(probe.y), floori(probe.z)) != 0:
				clear = false
				break
		if clear and world.has_chunk(VoxelWorld.chunk_of(VoxelWorld.cell_of(entry.position))) \
				and (car.is_empty() or entry.position.distance_to(start) < car.position.distance_to(start)):
			car = entry
	if car.is_empty():
		# Yakin arac yuklu halkanin disinda: en yakin araclarin yanina gidip
		# chunk'lar yuklenince yeniden yokla (buyuk sabit harita).
		var near: Array = vehicles.entries.duplicate()
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.position.distance_to(start) < b.position.distance_to(start))
		for entry: Dictionary in near.slice(0, 8):
			player.global_position = entry.position + Vector3(3, 1.0, 0)
			var waited := 0.0
			while waited < 3.0:
				await tree.process_frame
				waited += get_process_delta_time()
			var yaw2: float = entry.yaw
			var ahead2 := Vector3(-sin(yaw2), 0, -cos(yaw2))
			var ok := true
			for step in range(3, 9, 2):
				var probe2: Vector3 = entry.position + ahead2 * step + Vector3(0, 1.0, 0)
				if world.get_block(floori(probe2.x), floori(probe2.y), floori(probe2.z)) != 0:
					ok = false
					break
			if ok:
				car = entry
				break
	print("  arac adayi: %d kayit, secilen %s" % [vehicles.entries.size(), "yok" if car.is_empty() else str(car.model_id)])
	if not car.is_empty():
		car.fuel = Vehicles.TANK
		car.durability = maxf(float(car.durability), 60.0)
		var car_start: Vector3 = car.position
		var why := vehicles.enter(car)
		if why != "":
			print("  arac binilemedi: ", why)
		else:
			player.driving = true
			_bench_drive = Vector2(1.0, 0.0)
			t = 0.0
			while t < 10.0:
				await tree.physics_frame
				t += get_physics_process_delta_time()
				_bench_drive.y = sin(t * 0.6) * 0.4
			_bench_drive = Vector2.INF
			var car_end: Vector3 = vehicles.driving.position
			vehicles.leave()
			player.driving = false
			report.call("arac")
			print("  arac: %.0f m yol" % car_start.distance_to(car_end))
	# Uzun yol akisi: harita omurgasi boyunca 20 m/sn (arac hizi) duz gidis.
	# Chunk uretim/meshleme akisinin en agir durumu budur.
	if generator is CityGenerator and not (generator as CityGenerator).data.get("spine", []).is_empty():
		var spine: Array = (generator as CityGenerator).data.spine
		var nearest := 0
		for i in spine.size():
			if Vector2(spine[i][0], spine[i][1]).distance_to(Vector2(start.x, start.z)) \
					< Vector2(spine[nearest][0], spine[nearest][1]).distance_to(Vector2(start.x, start.z)):
				nearest = i
		var next := mini(nearest + 1, spine.size() - 1)
		var from := mini(nearest, spine.size() - 2)
		var way := (Vector2(spine[next][0], spine[next][1]) - Vector2(spine[from][0], spine[from][1])).normalized()
		player.global_position = start
		t = 0.0
		while t < 12.0:
			await tree.physics_frame
			t += get_physics_process_delta_time()
			var p := player.global_position + Vector3(way.x, 0, way.y) * 20.0 * get_physics_process_delta_time()
			p.y = generator.ground_height(floori(p.x), floori(p.z)) + 1.5
			player.global_position = VoxelBody.unstick(world, p, 0.3, 1.8)
		report.call("uzun_yol_20ms")
	player.global_position = start
	await tree.create_timer(5.0).timeout
	perf.reset()
	# Kalabalik saldiri: 80 zombi oyuncunun cevresinde.
	for i in 80:
		var a := TAU * i / 80.0
		var d := 12.0 + (i % 5) * 4.0
		var cell := Vector2i(floori(start.x + cos(a) * d), floori(start.z + sin(a) * d))
		var y := int(generator.ground_height(cell.x, cell.y))
		zombies.spawn(Content.zombies["walker" if i % 3 else "runner"], Vector3(cell.x + 0.5, y + 0.2, cell.y + 0.5))
	vitals.health = 10000.0
	await tree.create_timer(12.0).timeout
	report.call("kalabalik_80")
	get_tree().quit()


func _update_debug() -> void:
	var r := perf.report()
	var p := player.position
	debug_label.text = "FPS %.0f  ort %.1f ms  p95 %.1f  p99 %.1f  maks %.1f\n" % [r.fps, r.avg_ms, r.p95_ms, r.p99_ms, r.max_ms] \
		+ "konum %.1f %.1f %.1f  yerde:%s  aktor %d  uyanik zombi %d/%d\n" % [p.x, p.y, p.z, player.on_floor,
			actors.actors.size(), zombies.awake_count, zombies.zombies.size()] \
		+ "chunk veri %d  mesh %d  meshlenen %d  atilan %d  son mesh %.1f ms (maks %.1f)  nav %d\n" % [
			world.chunks.size(), terrain.mesh_node_count(), terrain.stats.meshed, terrain.stats.discarded,
			terrain.stats.last_mesh_usec / 1000.0, terrain.stats.max_mesh_usec / 1000.0, nav.rebuilds] \
		+ "cizim %d  nesne %d  VRAM %.0f MB  RAM %.0f MB  hasarli blok %d  degisen %d" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
			OS.get_static_memory_usage() / 1048576.0, world.damage.size(), world.modified.size()]
	if population != null:
		var c := population.near_counts(player.global_position)
		debug_label.text += "\nnufus: tam AI %d  temsil %d  bolgesel %d/%d  yerel yogunluk %d/km2" % [
			c.full, c.reps, c.regional, c.budget, c.density]


func _take_screenshot(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("Ekran goruntusu: ", path)
	_update_debug()
	print(debug_label.text)
	get_tree().quit()
