"""Depolama ve koloni ailesi: istasyon kitleri (12 istasyon, kademeli), depolar, koloni yapilari."""
from lib import Registry, I, T

F = "items/gen_storage.json"
FAM = "storage"


def build(R: Registry) -> None:
    R.category("istasyon", "İstasyonlar")
    R.category("depolama", "Depolama")
    R.category("koloni", "Koloni")

    def kit(iid, name, tier, weight, value, desc, catalog, model, inputs, station, stier, cat="istasyon", sub="İstasyon",
            learn="", effects=None):
        m = R.model(*model) if isinstance(model, tuple) else R.model(model)
        R.item(F, iid, name, "station", tier, weight, value, ["placeable", "crafting_station" if catalog["kind"] == "station" else "colony"],
               desc + " İnşa kipinde (B) kurulur; yanında (4 m) o istasyonun tarifleri açılır." if catalog["kind"] == "station"
               else desc + " İnşa kipinde (B) kurulur.",
               stack=1, model=m, effects=effects or {})
        R.placeables[iid] = {"label": name, "model": m, **catalog}
        R.recipe(FAM, "r_" + iid, name, iid, 1, inputs, station, stier, 14 + tier * 6, cat, sub, desc, learn=learn)

    stations = [
        # kimlik, ad, istasyon, kademe, agirlik, aciklama, model, girdiler, uretim istasyonu, kademe, ogrenme, guc
        ("workbench_basic", "Basit Tezgâh", "workbench", 1, 10.0, "Kalas ve çividen ilk tezgâh.", ("production/workbench_01", "workbench"),
         [I("wood_plank", 6), T("fastener", 8)], "hands", 1, ""),
        ("workbench_heavy", "Ağır Tezgâh", "workbench", 3, 30.0, "Mengene ve çelik tabla: T3 tarifler.", ("production/workbench_02", "workbench"),
         [I("workbench_kit", 1), I("steel_sheet", 2), I("gear_large", 1), I("bolt_nut", 8)], "workbench", 2, "level:8"),
        ("carpentry_bench", "Marangoz Tezgâhı", "carpentry", 1, 16.0, "Kütük biçer, kalas ve kiriş keser.",
         ("production/carpentry_01", "workbench"), [I("wood_plank", 8), I("hand_saw", 1), T("fastener", 8)], "workbench", 1, ""),
        ("carpentry_pro", "Kereste Tezgâhı", "carpentry", 2, 30.0, "Motorlu testere: T2 marangoz işleri.",
         ("production/carpentry_02", "workbench"), [I("carpentry_bench", 1), I("motor_small", 1), I("blade_blank", 2), I("axle", 1)],
         "mechanic", 1, ""),
        ("forge_stone", "Taş Ocak", "forge", 1, 40.0, "Taş ve kilden ilk ocak: dövme ve eritme T1.", ("production/forge_01", "generator"),
         [I("stone_chunk", 10), I("clay", 6), I("charcoal", 4)], "hands", 1, ""),
        ("forge_brick", "Tuğla Ocak", "forge", 2, 60.0, "Körüklü tuğla ocak: T2.", ("production/kiln_01", "generator"),
         [I("fired_brick", 16), I("mortar", 4), I("pipe_steel", 2), I("canvas", 2)], "masonry", 1, ""),
        ("masonry_bench", "Taş ve Beton Tezgâhı", "masonry", 1, 25.0, "Harç, briket, kesme taş.", ("production/concrete_01", "workbench"),
         [I("stone_chunk", 8), I("wood_plank", 4), I("trowel", 1)], "workbench", 1, ""),
        ("masonry_mixer", "Beton Karıştırıcı", "masonry", 2, 55.0, "Tamburlu karıştırıcı: T2 beton işleri.",
         ("production/concrete_02", "workbench"), [I("masonry_bench", 1), I("motor_small", 1), I("steel_sheet", 2), I("gear_large", 1)],
         "mechanic", 2, ""),
        ("masonry_plant", "Beton Santrali", "masonry", 3, 90.0, "Betonarme ve ağır döküm: T3.", ("production/silo_01", "workbench"),
         [I("masonry_mixer", 1), I("pump_unit", 1), I("steel_sheet", 4), I("rebar_mesh", 2)], "mechanic", 3, "level:14"),
        ("mechanic_bench", "Mekanik Atölye", "mechanic", 1, 30.0, "Mengene, eğe, anahtar: dişli ve vida.",
         ("production/mechanic_01", "workbench"), [I("workbench_basic", 1), I("iron_bar", 4), I("wrench_set", 1)], "workbench", 1, ""),
        ("mechanic_lathe", "Torna Tezgâhı", "mechanic", 2, 60.0, "Aks, piston, pompa: T2.", ("production/mechanic_02", "drill_press"),
         [I("mechanic_bench", 1), I("motor_large", 1), I("axle", 1), I("steel_ingot", 2)], "mechanic", 1, ""),
        ("mechanic_heavy", "Ağır Makine Atölyesi", "mechanic", 3, 90.0, "Motorlu alet ve jeneratör: T3 (ELEKTRİK ister).",
         ("production/anvil_01", "engine_hoist"), [I("mechanic_lathe", 1), I("transformer_coil", 1), I("gear_large", 2), I("steel_sheet", 3)],
         "electronics", 2, "level:12"),
        ("gunsmith_basic", "Basit Silah Tezgâhı", "gunsmith", 2, 20.0, "Tetik grubu, atölye silahı ve fişek: T2.",
         ("production/toolrack_01", "workbench"), [I("workbench_kit", 1), I("file_set", 1), I("iron_bar", 3)], "workbench", 2, ""),
        ("gunsmith_mid", "Silah Tezgâhı II", "gunsmith", 3, 25.0, "Namlu işleme ve AP fişek: T3.",
         ("production/toolrack_02", "workbench"), [I("gunsmith_basic", 1), I("machined_part", 3), I("steel_ingot", 2)], "mechanic", 2, "level:10"),
        ("electronics_basic", "Lehim Masası", "electronics", 1, 8.0, "Havya ve büyüteç: basit devreler.",
         ("production/electronics_01", "workbench"), [I("soldering_iron", 1), I("wood_plank", 4), I("circuit_board_broken", 2)], "workbench", 1, ""),
        ("electronics_mid", "Elektronik Tezgâhı", "electronics", 2, 14.0, "Ölçü aletli tezgâh: T2.",
         ("production/electronics_02", "workbench"), [I("electronics_basic", 1), I("multimeter", 1), I("insulated_wire", 4)], "electronics", 1, ""),
        ("electronics_lab", "Elektronik Laboratuvarı", "electronics", 4, 30.0, "Osiloskop ve trafo: T4 (ELEKTRİK ister).",
         "iz2_electronics_solder_station", [I("electronics_bench", 1), I("transformer_coil", 1), I("circuit_module", 3), I("glass_lens", 1)],
         "electronics", 3, "skill:cr_quality"),
        ("chemistry_basic", "Damıtma Seti", "chemistry", 1, 6.0, "Cam balon ve soğutucu: temel kimya.",
         ("production/chemistry_01", "cooking_station"), [I("bottle_empty", 4), I("pvc_pipe", 2), T("cook_fuel", 2)], "workbench", 1, ""),
        ("chemistry_mid", "Kimya Tezgâhı", "chemistry", 2, 10.0, "Isıtıcı ve süzgeç: T2.", ("production/chemistry_02", "cooking_station"),
         [I("chemistry_basic", 1), I("glass_pane", 2), I("metal_plate", 2), I("valve", 1)], "workbench", 2, ""),
        ("chemistry_lab", "Kimya Laboratuvarı", "chemistry", 4, 25.0, "Çeker ocak: ilaç ve patlayıcı T4.", ("school/lab_01", "cooking_station"),
         [I("chemistry_set", 1), I("pump_unit", 1), I("glass_pane", 4), I("circuit_module", 1)], "electronics", 3, "skill:md_pharma"),
        ("kitchen_stove", "Mutfak Ocağı", "cooking", 2, 30.0, "Fırınlı ocak: ekmek ve fırın yemekleri (T2). Üste mutfak kapasitesi verir.",
         ("production/kitchen_01", "stove_apartment"), [I("metal_plate", 4), I("fired_brick", 6), I("gas_canister", 1), I("valve", 1)], "workbench", 2, ""),
        ("stove_electric", "Elektrikli Ocak", "cooking", 3, 25.0, "Yakıtsız pişirme (T3).", ("production/kitchen_02", "stove_apartment"),
         [I("kitchen_stove", 1), I("copper_coil", 3), I("relay_unit", 1)], "electronics", 2, ""),
        ("water_ceramic_station", "Seramik Arıtma İstasyonu", "water", 2, 14.0, "Seramik mumlu arıtma (T2).",
         ("production/filter_01", "iz2_water_purifier_gravity"), [I("water_tank_part", 1), I("ceramic_filter", 2), I("pipe_fitting", 2)],
         "workbench", 1, ""),
        ("farming_bench", "Tarım ve İşleme Tezgâhı", "farming", 1, 14.0, "Tohum ayıklama, değirmen, turşu, kurutma.",
         ("production/pump_01", "worktable_large"), [I("wood_plank", 6), I("stone_chunk", 4), T("fastener", 6)], "carpentry", 1, ""),
        ("farming_pro", "Tütsü ve Mayalama Odası", "farming", 2, 30.0, "Tütsü, konserve ve fermantasyon (T2).",
         ("iz2_food_smoking_cabinet", "worktable_large"), [I("farming_bench", 1), I("fired_brick", 8), I("glass_pane", 2), I("pipe_fitting", 2)],
         "masonry", 1, ""),
    ]
    for (iid, name, station, tier, weight, desc, model, inputs, pst, ptier, learn) in stations:
        colony = {"kitchen": 1} if iid in ("kitchen_stove", "stove_electric") else ({"workshop": 0.5} if station in ("workbench", "mechanic") and tier >= 2 else {})
        catalog = {"kind": "station", "station": station, "tier": tier, "material": "placed_heavy" if weight >= 25 else "placed_light"}
        if colony:
            catalog["colony"] = colony
        kit(iid, name, tier, weight, 60 * tier + 40, desc, catalog, model, inputs, pst, ptier, learn=learn,
            effects={"station_tier": tier})

    storage = [
        ("crate_small", "Küçük Sandık", 1, 6.0, 40, 16, "Yere konan kapaklı sandık: 40 kg, 16 yuva.", ("production/storage_01", "storage_crate"),
         [I("wood_plank", 4), I("nail", 6)], "carpentry", 1),
        ("chest_wood", "Ahşap Sandık", 2, 12.0, 70, 24, "70 kg, 24 yuva.", ("loot_chest_wood", "storage_crate"),
         [I("plywood", 2), I("hinge", 2), I("wood_plank", 2)], "carpentry", 1),
        ("locker_metal", "Metal Dolap", 2, 20.0, 90, 30, "90 kg, 30 yuva; zombiye dayanıklı.", ("school/locker_01", "locker_double"),
         [I("metal_plate", 4), I("hinge", 2), I("rivets", 6)], "forge", 1),
        ("gun_safe", "Silah Kasası", 3, 60.0, 60, 20, "Ağır çelik kasa: zor kırılır.", ("safe_tall", "weapon_locker"),
         [I("steel_sheet", 3), I("padlock", 1), I("hinge_heavy", 2)], "forge", 3),
        ("shelf_unit", "Raf Ünitesi", 2, 16.0, 120, 40, "Açık raf: 120 kg, 40 yuva.", ("production/storage_02", "warehouse_rack"),
         [I("metal_bracket", 4), I("plywood", 3)], "workbench", 2),
        ("barrel_storage", "Varil Depo", 1, 8.0, 60, 12, "Kapaklı varil: 60 kg, az yuva.", ("water_tank", "storage_crate"),
         [I("plastic_sheet", 3), I("metal_bracket", 1)], "workbench", 1),
        ("warehouse_rack", "Depo Rafı", 3, 40.0, 200, 60, "Endüstriyel raf: 200 kg, 60 yuva.", ("warehouse_rack", "storage_crate"),
         [I("iron_bar", 6), I("metal_plate", 4), I("bolt_nut", 12)], "forge", 2),
    ]
    for (iid, name, tier, weight, kg, slots, desc, model, inputs, station, stier) in storage:
        kit(iid, name, tier, weight, 20 * tier + kg // 4, desc + " E ile aç.",
            {"kind": "storage", "capacity_kg": kg, "slots": slots, "material": "placed_heavy" if tier >= 2 else "placed_light"},
            model, inputs, station, stier, cat="depolama", sub="Depo")

    colony = [
        ("bedroll", "Uyku Tulumu", 1, 2.0, {"kind": "bed", "heal_per_hour": 3, "colony": {"dorm": 1}, "solid": False},
         "Yere serilir: uyu (E), üste 1 yatak.", ("base/bedroll", "bedroll"), [I("cloth_bolt", 1), I("padding_pad", 1)], "hands", 1),
        ("cot", "Portatif Yatak", 1, 8.0, {"kind": "bed", "heal_per_hour": 4, "colony": {"dorm": 1}},
         "Katlanır karyola.", ("military/bunk_01", "bed_single_apartment"), [I("wooden_frame", 1), I("canvas_sheet", 1)], "carpentry", 1),
        ("bunk_bed", "Ranza", 2, 20.0, {"kind": "bed", "heal_per_hour": 4, "colony": {"dorm": 2}},
         "İki kişilik: üste 2 yatak.", ("prison/bunk_01", "bed_bunk_hostel"), [I("iron_bar", 4), I("padding_pad", 2), I("wood_plank", 4)], "forge", 1),
        ("hospital_bed", "Hastane Yatağı", 3, 30.0, {"kind": "bed", "heal_per_hour": 8, "colony": {"infirmary": 1}},
         "Uyurken çok iyileşir; üste revir kapasitesi.", ("health/bed_01", "hospital_bed"),
         [I("iron_bar", 4), I("padding_pad", 3), I("gear_small", 2), I("canvas_sheet", 1)], "workbench", 2),
        ("medical_table", "Muayene Masası", 3, 25.0, {"kind": "colony", "colony": {"infirmary": 1.5}},
         "Revir kapasitesi +1,5: doktor ve iyileşme.", ("health/operating_01", "medical_table"),
         [I("steel_sheet", 2), I("padding_pad", 2), I("surgical_kit", 1)], "workbench", 2),
        ("dining_table", "Yemekhane Masası", 1, 20.0, {"kind": "colony", "colony": {"kitchen": 0.25}},
         "Mutfak kapasitesi +0,25.", ("school/cafetable_01", "dining_table_apartment"), [I("wood_plank", 8), I("nail", 10)], "carpentry", 1),
        ("craftsman_bench", "Zanaatkâr Tezgâhı", 2, 25.0, {"kind": "colony", "colony": {"workshop": 1}},
         "Atölye kapasitesi +1: zanaatkâr iş emirleri.", ("iz2_tailor_cutting_table", "worktable_large"),
         [I("wood_beam", 2), I("plywood", 2), I("metal_bracket", 2), I("claw_hammer", 1)], "carpentry", 2),
        ("colony_rack", "Ortak Depo Rafı", 2, 20.0, {"kind": "colony", "colony": {"storage": 150}},
         "Üssün ortak deposuna +150 kg.", ("iz2_logistics_supply_cage", "warehouse_rack"),
         [I("iron_bar", 4), I("plywood", 4), I("bolt_nut", 8)], "forge", 1),
    ]
    for (iid, name, tier, weight, catalog, desc, model, inputs, station, stier) in colony:
        if "material" not in catalog and catalog.get("solid", True):
            catalog["material"] = "placed_light"
        kit(iid, name, tier, weight, 30 * tier, desc, catalog, model, inputs, station, stier, cat="koloni", sub="Koloni")
