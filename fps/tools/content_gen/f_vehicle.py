"""Arac ve kesif ailesi: yakitlar, arac parcalari (8 yuva), kesif ekipmani."""
from lib import Registry, I, T

F = "items/gen_vehicle.json"
FAM = "vehicle"


def build(R: Registry) -> None:
    R.category("arac", "Araç parçaları")
    R.category("yakit", "Yakıt")
    R.category("kesif", "Keşif")
    R.tag("vehicle_part", "araç parçası")

    # --- yakitlar (chemical_fuel + supply: depoya giren birim) ---
    fuels = [
        ("biodiesel", "Biyodizel", 2, 1.6, 24, 4.0, "Kızartma yağından metanolle dönüştürülmüş yakıt.",
         [I("cooking_oil", 3), I("ethanol", 1), I("lye", 1)], "chemistry", 1, 2),
        ("ethanol_fuel", "Yakıt Alkolü", 2, 1.0, 18, 3.0, "Damıtılmış yakıt alkolü: motorda benzin yerine yanar.",
         [I("ethanol", 3), I("bottle_empty", 1)], "chemistry", 1, 1),
        ("refined_gasoline", "Rafine Benzin", 3, 1.5, 40, 6.0, "Tortusu süzülmüş benzin: uzun yol.",
         [I("gasoline", 2), I("ceramic_filter", 1)], "chemistry", 2, 2),
        ("fuel_jerrycan", "Dolu Bidon", 3, 6.0, 90, 14.0, "20 litrelik dolu bidon: tek seferde depo.",
         [T("chemical_fuel", 4), I("plastic_sheet", 2), I("pipe_fitting", 1)], "mechanic", 1, 1),
    ]
    for (iid, name, tier, weight, value, supply, desc, inputs, station, stier, count) in fuels:
        R.item(F, iid, name, "material", tier, weight, value, ["chemical", "chemical_fuel", "volatile"],
               desc + " Aracın yanında envanterde \"Araca yakıt doldur\".", stack=8,
               model=R.model("gasoline", "diesel"), effects={"supply": supply})
        R.recipe(FAM, "r_" + iid, name, iid, count, inputs, station, stier, 10 + tier * 4, "yakit", "Yakıt", desc)

    # --- arac parcalari ---
    parts = [
        # kimlik, ad, yuva, kademe, agirlik, deger, etkiler, aciklama, model, girdiler, istasyon, kademe, ogrenme
        ("engine_tuned", "Ayarlı Motor", "engine", 2, 40.0, 260, {"vehicle_speed": 1.15, "vehicle_noise": 1.1},
         "Karbüratörü ayarlı motor: +%15 hız.", "motor_large", [I("motor_large", 1), I("piston", 2), I("gear_large", 1), I("oil_can", 1)],
         "mechanic", 2, ""),
        ("engine_rebuilt", "Revizyonlu Motor", "engine", 3, 55.0, 520, {"vehicle_speed": 1.3, "vehicle_noise": 1.05},
         "Silindirleri yenilenmiş motor: +%30 hız.", "motor_large", [I("engine_tuned", 1), I("crank_shaft", 1), I("piston", 2), I("steel_ingot", 2)],
         "mechanic", 3, "level:12"),
        ("tires_offroad", "Arazi Lastiği Takımı", "tires", 2, 30.0, 180, {"vehicle_speed": 1.05, "vehicle_armor": 10},
         "Kalın dişli lastik: enkazda daha az hasar.", "tire_scrap", [I("tire_scrap", 4), I("rubber_sheet", 2), I("steel_bars", 1)],
         "mechanic", 1, ""),
        ("tires_run_flat", "Patlamaz Lastik", "tires", 3, 36.0, 340, {"vehicle_armor": 25},
         "İçi dolgulu lastik: araç çok daha dayanıklı.", "tire_scrap", [I("tires_offroad", 1), I("rubber_sheet", 4), I("kevlar_panel", 1)],
         "mechanic", 2, ""),
        ("armor_plating_car", "Sac Kaplama", "armor", 2, 50.0, 220, {"vehicle_armor": 40, "vehicle_speed": 0.93},
         "Kapı ve camlara kaynaklı sac: +40 sağlamlık, biraz yavaş.", "metal_plate", [I("steel_sheet", 4), I("welding_rod", 3), I("rivets", 10)],
         "forge", 2, ""),
        ("armor_cage_car", "Çelik Kafes", "armor", 3, 80.0, 480, {"vehicle_armor": 80, "vehicle_speed": 0.88, "vehicle_ram": 1.2},
         "Tam kafes: +80 sağlamlık, ezme gücü artar.", "steel_bars", [I("armor_plating_car", 1), I("steel_bars", 4), I("armor_plate_steel", 2)],
         "forge", 3, "level:10"),
        ("tank_extended", "Ek Depo", "tank", 2, 16.0, 150, {"vehicle_tank": 30},
         "Bagaja bağlı ek depo: +30 birim yakıt.", "gas_canister", [I("steel_sheet", 2), I("pipe_fitting", 2), I("valve", 1)],
         "mechanic", 1, ""),
        ("tank_long_range", "Uzun Menzil Deposu", "tank", 3, 26.0, 300, {"vehicle_tank": 60},
         "Çift cidarlı depo: +60 birim.", "gas_canister", [I("tank_extended", 1), I("steel_sheet", 3), I("pump_unit", 1)],
         "mechanic", 2, ""),
        ("roof_rack", "Tavan Bagajı", "rack", 1, 14.0, 90, {"vehicle_capacity": 60},
         "Tavana bağlı sepet: +60 kg bagaj.", "metal_bracket", [I("iron_bar", 4), I("metal_bracket", 4), I("rope", 2)],
         "workbench", 1, ""),
        ("cargo_trailer_hitch", "Yük Sepeti ve Çeki Demiri", "rack", 3, 40.0, 260, {"vehicle_capacity": 150, "vehicle_speed": 0.95},
         "Arka sepet: +150 kg bagaj.", "steel_bars", [I("roof_rack", 1), I("steel_bars", 3), I("axle", 1), I("hinge_heavy", 2)],
         "forge", 2, ""),
        ("bull_bar", "Ön Koruma Demiri", "bumper", 2, 30.0, 200, {"vehicle_ram": 1.5, "vehicle_armor": 10},
         "Zombi ezme hasarı ×1,5, araç daha az hasar alır.", "steel_bars", [I("steel_bars", 3), I("pipe_steel", 2), I("welding_rod", 2)],
         "forge", 2, ""),
        ("plow_blade", "Kar Küreği Bıçağı", "bumper", 3, 55.0, 420, {"vehicle_ram": 2.2, "vehicle_armor": 20, "vehicle_speed": 0.92},
         "Sürüyü biçer: ezme ×2,2.", "blade_blank", [I("bull_bar", 1), I("steel_sheet", 4), I("blade_blank", 2)],
         "forge", 3, "level:14"),
        ("headlights_led", "LED Far Takımı", "lights", 2, 3.0, 120, {"vehicle_light": 45},
         "Geceyi 45 m aydınlatır.", "led_panel", [I("led_panel", 2), I("insulated_wire", 3), I("relay_unit", 1)],
         "electronics", 1, ""),
        ("searchlight_car", "Tavan Projektörü", "lights", 3, 8.0, 260, {"vehicle_light": 80},
         "80 m projektör.", "led_panel", [I("headlights_led", 1), I("glass_lens", 1), I("transformer_coil", 1)],
         "electronics", 2, ""),
        ("muffler_quiet", "Sessiz Egzoz", "muffler", 2, 12.0, 160, {"vehicle_noise": 0.65},
         "Sürüyü çekmez: gürültü −%35.", "pipe_steel", [I("pipe_steel", 3), I("padding_pad", 2), I("steel_sheet", 1)],
         "mechanic", 1, ""),
        ("muffler_baffled", "Çok Odalı Susturucu", "muffler", 3, 18.0, 320, {"vehicle_noise": 0.45},
         "Gürültü −%55.", "pipe_steel", [I("muffler_quiet", 1), I("ceramic_filter", 1), I("steel_sheet", 2)],
         "mechanic", 2, ""),
    ]
    for (iid, name, slot, tier, weight, value, effects, desc, model, inputs, station, stier, learn) in parts:
        R.item(F, iid, name, "vehicle_part", tier, weight, value, ["vehicle_part"], desc + " Aracın yanında envanterde \"Araca tak\".",
               stack=1, model=R.model(model), slot=slot, effects=effects)
        R.recipe(FAM, "r_" + iid, name, iid, 1, inputs, station, stier, 20 + tier * 8, "arac", slot.capitalize(), desc, learn=learn)

    # --- kesif ekipmani ---
    gear = [
        ("compass_field", "Arazi Pusulası", "tool", 1, 0.2, 40, ["utility", "compass"], {"compass": 1},
         "Çantadayken HUD'da yön şeridi gösterir.", "iz2_gear_compass", [I("metal_plate", 1), I("magnet", 1), I("glass_shard", 1)],
         "workbench", 1, ""),
        ("binoculars_field", "Dürbün", "tool", 2, 0.8, 120, ["utility", "binoculars"], {"zoom": 4.0},
         "O tuşuyla bakılır: 4× yakınlaştırma.", "iz2_gear_binoculars", [I("glass_lens", 2), I("metal_plate", 1), I("rubber_sheet", 1)],
         "workbench", 2, ""),
        ("map_kit", "Harita Seti", "tool", 1, 0.3, 60, ["utility", "map_tool"], {"map_reveal": 1},
         "Haritada (M) önemli yerleri, POI türlerini ve güvenli noktaları gösterir.", "paper",
         [I("paper", 3), I("charcoal", 1), I("compass_field", 1, tool=True)], "workbench", 1, ""),
        ("headlamp", "Kafa Lambası", "equip", 1, 0.3, 60, ["wearable", "light"], {"light_range": 14},
         "Başa takılır: el feneri yuvası boşken de ışık verir.", "lamp_bulb", [I("lamp_bulb", 1), I("battery_aa", 2), I("leather_strap", 1)],
         "electronics", 1, ""),
        ("headlamp_led", "LED Kafa Lambası", "equip", 2, 0.3, 140, ["wearable", "light"], {"light_range": 24},
         "Daha geniş ışık.", "led_panel", [I("led_panel", 1), I("battery_cell", 1), I("leather_strap", 1)], "electronics", 2, ""),
        ("backpack_canvas", "Kanvas Sırt Çantası", "equip", 1, 1.2, 60, ["wearable"], {"capacity": 10},
         "+10 kg taşıma.", "canvas_sheet", [I("canvas_sheet", 2), I("leather_strap", 2), I("twine", 2)], "workbench", 1, ""),
        ("backpack_military", "Askerî Sırt Çantası", "equip", 3, 2.2, 260, ["wearable"], {"capacity": 30},
         "+30 kg taşıma, bel kemeri.", "canvas_sheet", [I("backpack_canvas", 1), I("canvas_sheet", 2), I("metal_bracket", 2), I("padding_pad", 1)],
         "workbench", 2, "level:8"),
    ]
    for (iid, name, kind, tier, weight, value, tags, effects, desc, model, inputs, station, stier, learn) in gear:
        extra = {}
        cat = "tool"
        if kind == "equip":
            cat = "tool"
            extra["slot"] = "lamp" if "light" in tags else "backpack"
        R.item(F, iid, name, cat, tier, weight, value, tags, desc, stack=1, model=R.model(model), effects=effects, **extra)
        R.recipe(FAM, "r_" + iid, name, iid, 1, inputs, station, stier, 10 + tier * 6, "kesif", "Keşif", desc, learn=learn)
