"""Aile hedeflerini tamamlayan ek tarifler: yeni islevli esyalar + ALTERNATIF
tarifler (ayni ciktiya farkli malzeme yolu; belgenin "alternatif girdi"
ilkesi). Her cikti mevcut bir isleyiciye baglanir (ItemUse)."""
from lib import Registry, I, T
from f_build import _box

F = "items/gen_extra.json"


def build(R: Registry) -> None:
    def alt(fam, rid, name, out, count, inputs, station, tier, cat, sub, desc, learn=""):
        R.recipe(fam, "rx_" + rid, name, out, count, inputs, station, tier, 6 + tier * 4, cat, sub, desc, learn=learn)

    def piece(fam, pid, name, desc, cells, material, inputs, station, stier, model, cat, sub, learn=""):
        iid = "bp_" + pid
        R.pieces[pid] = {"material": material, "cells": cells}
        R.item(F, iid, name, "building", 2, round(1.2 * len(cells), 1), 5 * len(cells), ["building_piece"],
               desc + " İnşa kipinde (B) yerleştirilir.", stack=5, model=R.model(model), build=pid)
        R.recipe(fam, "r_" + iid, name, iid, 1, inputs, station, stier, 6 + len(cells), cat, sub, desc, learn=learn)

    def placeable(fam, iid, name, tier, weight, value, desc, catalog, model, inputs, station, stier, cat, sub,
                  learn="", tags=("placeable",), effects=None):
        m = R.model(*model) if isinstance(model, tuple) else R.model(model)
        R.item(F, iid, name, "station", tier, weight, value, list(tags), desc + " İnşa kipinde (B) kurulur.",
               stack=2, model=m, effects=effects or {})
        R.placeables[iid] = {"label": name, "model": m, **catalog}
        R.recipe(fam, "r_" + iid, name, iid, 1, inputs, station, stier, 10 + tier * 4, cat, sub, desc, learn=learn)

    # ================= YAPI (build) =================
    piece("build", "stone_wall_low", "Alçak taş duvar 3×1", "Bahçe duvarı: yarım boy, üstünden ateş.",
          [[x, 0, 0] for x in range(-1, 2)], "pb_stone_slab", [I("stone_block", 2), I("mortar", 1)], "masonry", 1,
          "build_defense/defense_stone_wall_01", "yapi", "Duvar")
    piece("build", "brick_chimney", "Tuğla baca", "4 m tuğla kolon: taşıyıcı ve ocak bacası.",
          [[0, y, 0] for y in range(4)], "pb_brick", [T("brick_material", 12), I("mortar", 3)], "masonry", 1,
          "iz3_neighborhood_köşe_taş", "yapi", "Kolon")
    piece("build", "wood_fence", "Ahşap çit 3×1", "Yarım boy tahta çit: sınır çizer, zombiyi yavaşlatır.",
          [[x, 0, 0] for x in range(-1, 2)], "pb_wood_slab", [I("wood_plank", 3), I("nail", 4)], "carpentry", 1,
          "build_defense/defense_wood_wall_01", "yapi", "Duvar")
    piece("build", "steel_catwalk", "Çelik iskele 3×1", "Yarım kalınlık çelik yürüme yolu: duvar üstü devriye.",
          [[x, 0, 0] for x in range(-1, 2)], "pb_steel_slab", [I("steel_sheet", 2), I("rivets", 6)], "forge", 3,
          "build_defense/defense_ramp_02", "yapi", "Döşeme", learn="level:10")
    piece("build", "log_floor", "Kütük döşeme 2×2", "Kütükten sal döşeme: kulübe ve iskele.",
          [[x, 0, z] for x in range(-1, 1) for z in range(2)], "pb_log", [I("wood_log", 4), I("rope", 1)], "carpentry", 1,
          "build_defense/defense_ramp_01", "yapi", "Döşeme")
    piece("build", "concrete_bench", "Beton set 2×1", "Yarım boy beton set: oturma ve alçak siper.",
          [[0, 0, 0], [1, 0, 0]], "pb_concrete_slab", [I("concrete_mix", 1)], "masonry", 2,
          "iz3_environment_curb_01", "yapi", "Set")

    # ================= ISLEME (process) =================
    alt("process", "plywood_glue", "Tutkallı kontrplak", "plywood", 1, [I("wood_plank", 3), I("glue", 1)], "carpentry", 1,
        "metal", "Ahşap", "Kalası tutkalla preslemek: vidasız kontrplak.")
    alt("process", "rope_rags", "Paçavradan halat", "rope", 1, [I("cloth_rag", 4)], "hands", 1, "kumas", "İp",
        "Paçavraları örerek halat.")
    alt("process", "charcoal_logs", "Kütükten kömür", "charcoal", 4, [I("wood_log", 2)], "forge", 1, "kimya", "Yakıt",
        "Kapalı ocakta kütük yakma: bol kömür.")
    alt("process", "iron_from_rebar", "İnşaat demirinden çubuk", "iron_bar", 1, [I("rebar", 2), T("cook_fuel", 1)], "forge", 1,
        "metal", "Metal", "Hurda inşaat demirini döverek düzeltmek.")
    alt("process", "copper_from_wire", "Kablodan bakır külçe", "copper_ingot", 1, [I("copper_wire", 6), T("cook_fuel", 1)], "forge", 1,
        "metal", "Metal", "Kabloyu soyup eritmek.")
    alt("process", "rivets_nails", "Çividen perçin", "rivets", 6, [I("nail", 8), T("cook_fuel", 1)], "forge", 1,
        "metal", "Bağlantı", "Çivi başlarını ezip perçine çevirmek.")
    alt("process", "cloth_from_fiber", "Liften bez", "cloth_bolt", 1, [I("plant_fiber", 10)], "workbench", 1, "kumas", "Kumaş",
        "Bitki lifinden kaba dokuma.")
    alt("process", "mortar_clay", "Kil harcı", "mortar", 2, [I("clay", 3), I("sand", 2), T("water_raw", 1)], "masonry", 1,
        "insaat", "Harç", "Kireçsiz, kille bağlanan harç: yavaş kurur ama tutar.")

    # ================= ALET (tools) =================
    alt("tools", "hammer_scrap", "Hurda çekiç", "claw_hammer", 1, [I("scrap_metal", 3), I("tool_handle", 1)], "forge", 1,
        "alet", "El aleti", "Hurdadan dövülmüş çekiç.")
    alt("tools", "saw_blade", "Bıçak kütüğünden testere", "hand_saw", 1, [I("blade_blank", 1), I("tool_handle", 1), I("file_set", 1, tool=True)],
        "workbench", 1, "alet", "El aleti", "Bıçak kütüğüne diş açmak.")
    alt("tools", "crowbar_rebar", "İnşaat demirinden levye", "crowbar", 1, [I("rebar", 2), T("cook_fuel", 1)], "forge", 1,
        "toplama", "Toplama", "Demiri bükerek levye.")
    alt("tools", "shovel_sheet", "Sactan kürek", "steel_shovel", 1, [I("metal_plate", 2), I("tool_handle", 1), I("rivets", 3)], "forge", 1,
        "toplama", "Toplama", "Sac levhadan kürek ağzı.")
    alt("tools", "whetstone_brick", "Tuğladan bileği taşı", "whetstone", 1, [I("loose_brick", 2), I("sand", 1)], "hands", 1,
        "bakim", "Bakım", "Tuğlayı zımparalayarak bileği taşı.")
    alt("tools", "tool_repair_scrap", "Hurda alet onarım kiti", "tool_repair_kit", 1, [I("scrap_metal", 4), T("fastener", 4), T("adhesive", 1)],
        "workbench", 1, "bakim", "Onarım", "Parça ve tutkal: aleti yamar.")
    alt("tools", "field_patch_rags", "Paçavra yaması", "field_patch", 1, [I("cloth_rag", 3), T("adhesive", 1)], "hands", 1,
        "bakim", "Onarım", "Acil yama: bez ve tutkal.")
    alt("tools", "fire_striker_flint", "Çakmak taşı seti", "fire_striker", 1, [I("stone_chunk", 2), I("scrap_metal", 1)], "hands", 1,
        "alet", "Ateş", "Taş ve çelik: ateş yakmanın en eski yolu.")

    # ================= SAVUNMA (defense) =================
    piece("defense", "sandbag_ring", "Kum torbası çember", "Tam çevrili makineli mevzisi (8 torba).",
          [[x, 0, z] for x in range(-1, 2) for z in range(-1, 2) if not (x == 0 and z == 0)], "sandbag",
          [I("sand", 24), T("fabric", 8)], "workbench", 1, "sandbags", "savunma_yapisi", "Savunma yapısı")
    piece("defense", "sandbag_tall", "Yüksek kum torbası 3×2", "İki sıra torba: ayakta siper.",
          _box(3, 2, 1), "sandbag", [I("sand", 18), T("fabric", 6)], "workbench", 1, "sandbags", "savunma_yapisi", "Savunma yapısı")
    piece("defense", "gabion_wall", "Gabion duvarı 3×2", "Taş dolu tel kafes hattı: mermi yutar.",
          _box(3, 2, 1), "pb_gabion", [I("mesh_wire", 3), I("stone_chunk", 18)], "workbench", 1, "iz2_defense_gate_brace",
          "savunma_yapisi", "Savunma yapısı")
    piece("defense", "bars_window", "Pencere parmaklığı", "Tek hücre demir parmaklık: bakılır, geçilmez.",
          [[0, 0, 0]], "pb_bars", [I("iron_bar", 3), I("rivets", 2)], "forge", 1, "prison/bars_01", "savunma_yapisi", "Kapama")
    piece("defense", "bars_wall", "Parmaklık duvarı 3×2", "Hapishane tipi demir parmaklık.",
          _box(3, 2, 1), "pb_bars", [I("iron_bar", 12), I("rivets", 8)], "forge", 2, "prison/bars_02", "savunma_yapisi", "Kapama")
    piece("defense", "mesh_gate_panel", "Tel örgü panel 2×2", "Hafif çit paneli.",
          _box(2, 2, 1, 0), "pb_mesh", [I("mesh_wire", 2), I("pipe_steel", 1)], "workbench", 1, "iz2_defense_wire_fence",
          "savunma_yapisi", "Savunma yapısı")
    piece("defense", "concrete_barrier_long", "Uzun beton bariyer 4×1", "New Jersey tipi bariyer hattı.",
          [[x, 0, 0] for x in range(-2, 2)], "pb_concrete", [I("concrete_mix", 4), I("rebar", 2)], "masonry", 2,
          "build_defense/defense_concrete_wall_01", "savunma_yapisi", "Savunma yapısı")
    piece("defense", "steel_shutter", "Çelik kepenk 3×2", "Dükkân kepengi: cam ve kapıyı kapatır.",
          _box(3, 2, 1), "pb_scrap", [I("metal_plate", 4), I("rivets", 8), I("hinge", 2)], "forge", 2,
          "build_defense/defense_window_shutter_01", "savunma_yapisi", "Kapama")
    piece("defense", "log_barricade", "Kütük barikat 3×1", "Yatık kütük: ucuz, sağlam engel.",
          [[x, 0, 0] for x in range(-1, 2)], "pb_log", [I("wood_log", 3), I("rope", 1)], "hands", 1, "build_defense/defense_barricade_01",
          "savunma_yapisi", "Savunma yapısı")

    def trap(iid, name, tier, effects, catalog, desc, model, inputs, station, stier, learn=""):
        placeable("defense", iid, name, tier, 3.0 + tier, 40 * tier, desc, {"kind": "trap", "solid": False, **catalog}, model,
                  inputs, station, stier, "tuzak", "Tuzak", learn=learn, tags=("placeable", "defense"), effects=effects)

    trap("trap_glass_strip", "Cam Kırığı Şeridi", 1, {"damage": 5, "uses": 30}, {"effect": "slow", "slow": 0.3, "radius": 1.0, "cooldown": 0.5},
         "Kırık cam serpilmiş şerit: hafif yavaşlatır, sesi seni uyarır.", "rubble_pile",
         [I("glass_shard", 8), I("wood_plank", 1)], "hands", 1)
    trap("trap_nail_board", "Çivili Tahta", 1, {"damage": 10, "uses": 12}, {"effect": "damage", "radius": 0.8},
         "Yere yatırılmış çivili tahta.", "build_defense/defense_spikes_01", [I("wood_plank", 2), I("nail", 10)], "hands", 1)
    trap("trap_caltrops", "Dört Çatal Serpintisi", 2, {"damage": 8, "uses": 25}, {"effect": "slow", "slow": 0.45, "radius": 1.4, "cooldown": 0.5},
         "Kaynaklı dört çatallar: geniş alanı yavaşlatır.", "build_defense/defense_spikes_02", [I("nail", 16), I("welding_rod", 1)], "forge", 1)
    trap("trap_fire_ditch", "Yakıtlı Hendek", 2, {"damage": 16, "uses": 10}, {"effect": "burn", "radius": 1.6, "cooldown": 1.5},
         "Yakıt dökülmüş hendek: yanar.", "rubble_pile", [T("chemical_fuel", 3), I("wood_plank", 2)], "workbench", 1)
    trap("trap_spring_spear", "Yaylı Mızrak", 2, {"damage": 38, "uses": 6}, {"effect": "damage", "radius": 1.0, "cooldown": 2.0,
                                                                              "sound": "melee_swing"},
         "Tetiklenince fırlayan mızrak.", "build_defense/defense_trap_mech_01", [I("spring_heavy", 1), I("blade_blank", 1), I("wood_beam", 1)],
         "workbench", 2)
    trap("trap_acid_sprayer", "Asit Püskürtücü", 3, {"damage": 20, "uses": 10}, {"effect": "damage", "radius": 1.3, "cooldown": 1.2,
                                                                                   "damage_type": "acid", "power": 15},
         "Pompayla akü asidi püskürtür (15 W).", "build_defense/defense_trap_electric_02",
         [I("battery_acid", 2), I("pump_unit", 1), I("pipe_fitting", 2)], "chemistry", 2, learn="level:10")
    trap("trap_flashbang", "Flaş Tuzağı", 2, {"damage": 0, "uses": 8}, {"effect": "slow", "slow": 0.8, "radius": 2.0, "cooldown": 4.0,
                                                                       "sound": "break_glass", "power": 5},
         "Parlak flaş ve patlama sesi: zombiler sersemler (5 W).", "build_defense/defense_alarm_01",
         [I("led", 4), I("capacitor_salvaged", 2), I("circuit_basic", 1)], "electronics", 1)
    trap("trap_mine_nail", "Çivili Mayın", 3, {"damage": 70, "uses": 1}, {"effect": "explode", "radius": 1.0, "blast": 2.5},
         "Konserve kutusu, barut, çivi.", "iz2_mission_black_box", [I("refined_powder", 2), I("nail", 12), I("primer_compound", 1),
                                                                  I("bottle_empty", 1)], "workbench", 2, learn="level:8")

    # ================= ELEKTRIK (power) =================
    def light(iid, name, tier, power, rng, energy, color, night, desc, model, inputs, station, stier):
        placeable("power", iid, name, tier, 2.0 + tier, 12 * tier + power // 2, desc,
                  {"kind": "light", "power": power, "solid": False, "night_only": night,
                   "light": {"range": rng, "energy": energy, "color": color, "height": 1.8 if rng < 16 else 2.6}},
                  model, inputs, station, stier, "aydinlatma", "Lamba", tags=("placeable", "powered"))

    light("lamp_candle", "Mum Feneri", 1, 0, 6, 0.8, [255, 190, 120], False, "Kavanozda mum: elektriksiz, zayıf ışık.",
          "iz2_item_thermos", [I("bottle_empty", 1), I("cooking_oil", 1), I("cloth_rag", 1)], "hands", 1)
    light("lamp_emergency", "Acil Durum Lambası", 2, 4, 10, 1.4, [240, 246, 255], False, "Akülü ağda hep yanar (4 W).",
          "fluorescent_fixture", [I("led", 4), I("battery_cell", 1), I("plastic_sheet", 1)], "electronics", 1)
    light("lamp_red", "Kırmızı Gece Lambası", 1, 3, 9, 1.1, [255, 90, 70], True, "Göz alıştırmayan kırmızı ışık, yalnız gece (3 W).",
          "wall_sconce", [I("led", 3), I("insulated_wire", 1), I("glass_shard", 1)], "electronics", 1)
    light("lamp_garden_solar", "Bahçe Lambası", 1, 0, 7, 1.0, [220, 236, 255], True, "Kendi paneli var: yalnız gece yanar.",
          "iz3_environment_lamp_01", [I("solar_cell", 1), I("led", 2), I("battery_cell", 1)], "electronics", 1)
    light("lamp_tower", "Işık Kulesi", 3, 90, 28, 3.6, [255, 248, 230], False, "Avluyu gündüz gibi aydınlatır (90 W).",
          ("military/floodlight_02", "street_lamp"), [I("led_panel", 3), I("pipe_steel", 3), I("wire_spool", 1)], "forge", 2)
    light("lamp_workshop", "Atölye Lambası", 2, 20, 12, 1.8, [255, 240, 214], False, "Tezgâh üstü güçlü ışık (20 W).",
          "ceiling_lamp_apartment", [I("led_panel", 1), I("metal_bracket", 1), I("insulated_wire", 1)], "electronics", 1)
    placeable("power", "solar_roof_tile", "Güneş Kiremidi", 2, 4.0, 90, "Çatıya: gündüz 35 W.",
              {"kind": "solar", "output": 35, "material": "placed_light"}, ("production/solar_01", "solar_panel"),
              [I("solar_cell", 2), I("roof_tile_item", 1), I("insulated_wire", 1)], "electronics", 1, "enerji", "Güneş",
              tags=("placeable", "powered"))
    placeable("power", "water_wheel", "Su Çarkı", 2, 30.0, 260, "Dere/kıyı başında sürekli 120 W civarı.",
              {"kind": "turbine", "output": 120, "material": "placed_heavy"}, ("production/pump_02", "iz2_power_wind_micro"),
              [I("wood_beam", 6), I("axle", 1), I("alternator", 1), I("gear_large", 1)], "carpentry", 2, "enerji", "Rüzgâr",
              tags=("placeable", "powered"))
    placeable("power", "battery_bank_car", "Araba Aküsü Rafı", 1, 20.0, 80, "600 Wh: iki araba aküsü.",
              {"kind": "battery", "capacity": 600, "material": "placed_light"}, ("production/battery_01", "battery"),
              [I("battery_car", 1), I("insulated_wire", 2), I("wood_plank", 2)], "workbench", 1, "enerji", "Akü",
              tags=("placeable", "powered"))
    alt("power", "circuit_scrap", "Hurdadan basit devre", "circuit_basic", 1, [I("circuit_board_broken", 2), I("copper_wire", 1)],
        "electronics", 1, "elektronik", "Devre", "İki kırık karttan bir sağlam devre.")
    alt("power", "coil_wire", "Kablodan bobin", "copper_coil", 1, [I("copper_wire", 6)], "electronics", 1, "elektronik", "Devre",
        "Kabloyu makaraya sarmak.")
    alt("power", "wire_spool_copper", "Bakırdan kablo makarası", "wire_spool", 1, [I("copper_ingot", 1), I("rubber_sheet", 1)], "electronics", 2,
        "elektrik", "Dağıtım", "Külçeden çekilip kılıflanan kablo.")

    # ================= YEMEK (food) =================
    def dish(iid, name, fv, wv, shelf, desc, model, inputs, station, stier, count, effects=None, sub="Yemek", cat="yemek"):
        R.item(F, iid, name, "consumable", 2, 0.5, 4 + fv // 3, ["food", "cooked"], desc + f" (+{fv} tokluk, +{wv} su)", stack=8,
               model=R.model(model), effects=effects or {})
        n = {"food": fv, "water": wv}
        if shelf:
            n.update({"shelf_life_h": shelf, "spoils_to": "spoiled_food"})
        R.nutrition[iid] = n
        R.recipe("food", "r_" + iid, name, iid, count, inputs, station, stier, 8 + stier * 2, cat, sub, desc)

    fuel = T("cook_fuel", 1)
    water = I("water_bottle", 1)
    stew = "iz2_item_cooked_stew"
    dish("menemen_veg", "Sebzeli Menemen", 24, 8, 18, "Domates, biber: yumurtasız menemen.", stew,
         [I("tomato", 2), I("pepper", 1), I("cooking_oil", 1), fuel], "cooking", 1, 2)
    dish("potato_salad", "Patates Salatası", 20, 4, 24, "Haşlanmış patates, yeşillik.", stew, [I("potato", 2), I("herbs", 1), fuel], "cooking", 1, 2)
    dish("bean_salad", "Piyaz", 24, 4, 36, "Fasulye, sirke, soğansız.", stew, [I("beans_fresh", 2), I("vinegar", 1)], "hands", 1, 2)
    dish("pickled_fish", "Lakerda", 22, 0, 240, "Tuzlanmış balık: aylarca dayanır.", "iz2_district_fish_stall",
         [I("raw_fish", 2), I("salt_pack", 1)], "farming", 1, 2, sub="Saklama", cat="saklama")
    dish("wheat_porridge", "Buğday Lapası", 22, 10, 30, "Buğday ve su: tok tutar.", stew, [I("wheat", 3), water, fuel], "cooking", 1, 2)
    dish("linden_tea", "Ihlamur ve Adaçayı", 0, 14, 24, "Mideyi yatıştırır.", "iz2_item_thermos", [I("herbs", 1), water, fuel],
         "cooking", 1, 2, effects={"cure_sick": 1})
    dish("rice_pudding", "Sütlaç (sütsüz)", 20, 6, 48, "Pirinç, şeker, su.", stew, [I("rice_bag", 1), I("sugar_pack", 1), water, fuel], "cooking", 1, 3)
    dish("fish_stew", "Balık Buğulama", 30, 10, 18, "Balık, domates, biber.", stew, [I("raw_fish", 1), I("tomato", 1), I("pepper", 1), fuel],
         "cooking", 1, 2)
    dish("simit", "Simit", 16, 0, 72, "Susamsız ama simit.", "bread", [I("flour_sack", 1), I("sugar_pack", 1), water, fuel], "cooking", 2, 4)
    dish("dried_pepper", "Kurutulmuş Biber", 8, 0, 480, "İpe dizilip kurutulmuş biber: çok dayanır.", stew, [I("pepper", 4), I("rope", 1, tool=True)],
         "farming", 1, 2, sub="Saklama", cat="saklama")
    alt("food", "water_boil_pot", "Tencerede su kaynatma", "water_bottle", 3, [I("water_dirty", 3), fuel, I("cooking_pot", 1, tool=True)],
        "hands", 1, "su", "Su", "Tencereyle ateşte: üç şişe birden.")
    alt("food", "flour_potato", "Patates unu", "flour_sack", 1, [I("potato", 4)], "farming", 1, "tarim", "Değirmen",
        "Kurutulup dövülen patates: un yerine geçer.")
    alt("food", "compost_fiber", "Lif kompostu", "compost", 1, [I("plant_fiber", 6), T("water_raw", 1)], "farming", 1, "tarim", "Gübre",
        "Ot ve lif çürütülerek.")
    alt("food", "bait_fish", "Balık artığı yemi", "bait", 6, [I("raw_fish", 1)], "hands", 1, "tarim", "Balıkçılık",
        "Bir balık, altı yem.")

    # ================= SAGLIK (health) =================
    alt("health", "bandage_rags", "Paçavradan sargı", "bandage_clean", 1, [I("cloth_rag", 3), I("alcohol", 1)], "hands", 1,
        "tibbi", "Sargı", "Paçavra alkolle temizlenip sarılır.")
    alt("health", "painkiller_herbal", "Söğüt kabuğu ağrı kesici", "painkiller", 2, [I("herbs", 2), I("wood_log", 1)], "chemistry", 1,
        "tibbi", "İlaç", "Söğüt kabuğu özütü: aspirinin atası.")
    alt("health", "splint_scrap", "Sactan atel", "splint", 1, [I("metal_plate", 1), I("cloth_rag", 2)], "hands", 1, "tibbi", "Sarf",
        "İnce sac ve bez: kırığı sabitler.")
    alt("health", "cloth_mask_fiber", "Lif filtreli maske", "cloth_mask", 1, [I("cloth_bolt", 1), I("charcoal", 1)], "workbench", 1,
        "zirh", "Maske", "Kömür tabakalı bez maske.")

    # ================= ARAC VE KESIF (vehicle) =================
    parts = [
        ("engine_basic_tune", "Temel Motor Ayarı", "engine", 1, 30.0, {"vehicle_speed": 1.07},
         "Buji ve filtre değişimi: +%7 hız.", "motor_large", [I("oil_can", 1), I("spring", 2), I("filter_housing", 1)], "mechanic", 1),
        ("engine_military", "Askerî Motor", "engine", 4, 70.0, {"vehicle_speed": 1.45, "vehicle_noise": 1.2},
         "Turbolu dizel: +%45 hız, gürültülü.", "motor_large", [I("engine_rebuilt", 1), I("pump_unit", 1), I("transformer_coil", 1),
                                                               I("steel_ingot", 3)], "mechanic", 3),
        ("tires_patched", "Yamalı Lastikler", "tires", 1, 26.0, {"vehicle_armor": 5}, "Yamalanmış lastik: patlamaya biraz dayanır.",
         "tire_scrap", [I("tire_scrap", 3), I("glue", 1)], "workbench", 1),
        ("tires_military", "Askerî Lastik", "tires", 4, 44.0, {"vehicle_armor": 35, "vehicle_speed": 1.05}, "Zırhlı jant ve dolgulu lastik.",
         "tire_scrap", [I("tires_run_flat", 1), I("armor_plate_steel", 1), I("rubber_sheet", 2)], "mechanic", 3),
        ("armor_wood_car", "Tahta Kaplama", "armor", 1, 30.0, {"vehicle_armor": 15, "vehicle_speed": 0.97},
         "Camlara çakılmış kalas: ilk günlerin zırhı.", "wood_plank", [I("wood_plank", 8), I("nail", 16)], "carpentry", 1),
        ("armor_military_car", "Askerî Zırh Seti", "armor", 4, 110.0, {"vehicle_armor": 130, "vehicle_speed": 0.85, "vehicle_ram": 1.3},
         "Balistik plakalar: +130 sağlamlık.", "steel_bars", [I("armor_cage_car", 1), I("armor_plate_steel", 4), I("kevlar_panel", 2)], "forge", 3),
        ("tank_jerry_rack", "Bidon Askısı", "tank", 1, 8.0, {"vehicle_tank": 15}, "Arkaya iki bidon: +15 birim.", "gas_canister",
         [I("metal_bracket", 2), I("plastic_sheet", 2), I("rope", 1)], "workbench", 1),
        ("tank_military", "Askerî Yakıt Tankı", "tank", 4, 36.0, {"vehicle_tank": 100}, "+100 birim: şehri baştan başa geçer.", "gas_canister",
         [I("tank_long_range", 1), I("steel_sheet", 3), I("valve", 2)], "mechanic", 3),
        ("roof_rack_wood", "Ahşap Tavan Sepeti", "rack", 1, 10.0, {"vehicle_capacity": 35}, "+35 kg bagaj.", "wood_plank",
         [I("wood_plank", 6), I("rope", 2)], "carpentry", 1),
        ("bumper_pipe", "Boru Tampon", "bumper", 1, 18.0, {"vehicle_ram": 1.25}, "Boru kaynaklı tampon: ezme ×1,25.", "pipe_steel",
         [I("pipe_steel", 3), I("welding_rod", 1)], "forge", 1),
        ("bumper_spiked", "Çivili Tampon", "bumper", 2, 26.0, {"vehicle_ram": 1.8, "vehicle_armor": 5}, "Sivri çubuklu tampon: ezme ×1,8.",
         "steel_bars", [I("bumper_pipe", 1), I("blade_blank", 2), I("welding_rod", 2)], "forge", 2),
        ("lights_work", "Çalışma Farı", "lights", 1, 2.0, {"vehicle_light": 25}, "25 m far.", "led_panel", [I("lamp_bulb", 2), I("insulated_wire", 2)],
         "electronics", 1),
        ("muffler_patched", "Yamalı Egzoz", "muffler", 1, 8.0, {"vehicle_noise": 0.85}, "Delikleri kapatılmış egzoz: gürültü −%15.", "pipe_steel",
         [I("pipe_steel", 1), I("metal_plate", 1), I("welding_rod", 1)], "forge", 1),
        ("muffler_military", "Askerî Susturucu", "muffler", 4, 22.0, {"vehicle_noise": 0.3}, "Gürültü −%70.", "pipe_steel",
         [I("muffler_baffled", 1), I("ceramic_filter", 2), I("padding_pad", 2)], "mechanic", 3),
    ]
    for (iid, name, slot, tier, weight, effects, desc, model, inputs, station, stier) in parts:
        R.item(F, iid, name, "vehicle_part", tier, weight, 60 * tier, ["vehicle_part"], desc + " Aracın yanında envanterde \"Araca tak\".",
               stack=1, model=R.model(model), slot=slot, effects=effects)
        R.recipe("vehicle", "r_" + iid, name, iid, 1, inputs, station, stier, 16 + tier * 8, "arac", slot.capitalize(), desc)
    for iid, name, cap, tier, inputs, stier in [
        ("backpack_hiking", "Dağcı Çantası", 18, 2, [I("canvas_sheet", 3), I("leather_strap", 2), I("metal_bracket", 1)], 1),
        ("backpack_frame", "Çerçeveli Yük Çantası", 40, 4, [I("backpack_military", 1), I("aluminum_ingot", 2), I("padding_pad", 2)], 3),
    ]:
        R.item(F, iid, name, "tool", tier, 1.5 + tier * 0.4, 40 * tier, ["wearable"], f"+{cap} kg taşıma.", stack=1,
               model=R.model("canvas_sheet"), effects={"capacity": cap}, slot="backpack")
        R.recipe("vehicle", "r_" + iid, name, iid, 1, inputs, "workbench", stier, 12 + tier * 6, "kesif", "Keşif", f"+{cap} kg taşıma.")
    alt("vehicle", "ethanol_fruit", "Meyveden yakıt alkolü", "ethanol_fuel", 1, [I("dried_fruit", 4), I("sugar_pack", 1), T("water_raw", 1)],
        "chemistry", 2, "yakit", "Yakıt", "Mayalayıp damıtmak: yavaş ama her yerde.")
    alt("vehicle", "biodiesel_fat", "Yağdan biyodizel (alkollü)", "biodiesel", 1, [I("cooking_oil", 3), I("alcohol", 1)], "chemistry", 1,
        "yakit", "Yakıt", "Lye yerine ispirtoyla: daha az verim.")
    alt("vehicle", "compass_needle", "Mıknatıslı iğne pusulası", "compass_field", 1, [I("magnet", 1), I("bottle_empty", 1), I("nail", 1)],
        "hands", 1, "kesif", "Keşif", "Suda yüzen mıknatıslı iğne.")
    alt("vehicle", "map_kit_school", "Okul atlasından harita seti", "map_kit", 1, [I("textbook", 1), I("paper", 1)], "hands", 1,
        "kesif", "Keşif", "Atlas sayfaları ve notlar.")
    alt("vehicle", "headlamp_scrap", "Hurda kafa lambası", "headlamp", 1, [I("led", 2), I("battery_aa", 2), I("cloth_rag", 1)], "hands", 1,
        "kesif", "Keşif", "LED ve bezle bağlanmış pil.")
    alt("vehicle", "binoculars_scope", "Dürbünden sökülmüş optikle dürbün", "binoculars_field", 1,
        [I("optic_scope", 1), I("metal_plate", 1), I("leather_strap", 1)], "workbench", 2, "kesif", "Keşif",
        "Askerî nişangah merceği iki tüpe bölünür.")
    alt("vehicle", "jerrycan_diesel", "Mazotla dolu bidon", "fuel_jerrycan", 1, [I("diesel", 4), I("plastic_sheet", 2)], "workbench", 1,
        "yakit", "Yakıt", "Mazotu bidona boşaltmak.")
