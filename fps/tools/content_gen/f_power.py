"""Elektrik ve aydinlatma ailesi: devre bilesenleri, uretim, depolama, dagitim, tuketim."""
from lib import Registry, I, T

F = "items/gen_power.json"
FAM = "power"


def build(R: Registry) -> None:
    R.category("elektrik", "Elektrik")
    R.category("elektronik", "Elektronik")
    R.category("enerji", "Enerji üretimi ve depolama")
    R.category("aydinlatma", "Aydınlatma")
    R.category("elektrikli_cihaz", "Elektrikli cihazlar")
    for tag, name in [("coil", "bakır bobin"), ("relay", "röle"), ("sensor", "sensör modülü"), ("led_panel", "LED panel"),
                      ("battery_cell", "pil hücresi"), ("speaker", "hoparlör"), ("circuit", "devre kartı")]:
        R.tag(tag, name)

    def comp(iid, name, tier, weight, value, tags, desc, model, inputs, station, stier, count=1, learn=""):
        R.item(F, iid, name, "component", tier, weight, value, tags, desc, stack=20, model=R.model(model))
        R.recipe(FAM, "r_" + iid, name, iid, count, inputs, station, stier, 6 + tier * 3, "elektronik", "Devre", desc, learn=learn)

    comp("circuit_basic", "Basit Devre", 1, 0.05, 14, ["circuit", "electronic", "logic"],
         "Kırık kartlardan kurtarılmış basit devre: multimetre, alarm, yem.", "electronics",
         [I("circuit_board_broken", 1), I("solder", 1)], "electronics", 1)
    comp("copper_coil", "Bakır Bobin", 2, 0.4, 20, ["coil", "conductive_metal", "electronic"],
         "Sarılmış bakır: motor, trafo, tesla.", "electronics", [I("copper_ingot", 1), T("insulator", 1)], "electronics", 1, count=2)
    comp("relay_unit", "Röle Ünitesi", 2, 0.1, 22, ["relay", "electronic", "logic"],
         "Güç devresini açıp kapatan anahtar: anahtar, elektrikli tuzak.", "electronics",
         [I("relay_switch", 1), I("circuit_basic", 1)], "electronics", 1, count=2)
    comp("sensor_module", "Sensör Modülü", 3, 0.1, 40, ["sensor", "electronic", "logic"],
         "Hareket ve ışık algılayıcı.", "electronics", [I("circuit_basic", 1), I("led", 2), I("transistor", 1)], "electronics", 2)
    comp("led_panel", "LED Panel", 2, 0.3, 24, ["led_panel", "light_source", "electronic"],
         "Çok sayıda LED: lamba ve projektör.", "electronics", [I("led", 6), I("circuit_basic", 1), I("plastic_sheet", 1)],
         "electronics", 1)
    comp("battery_cell", "Pil Hücresi", 2, 0.3, 18, ["battery_cell", "power_source", "electronic"],
         "Yeniden şarj edilebilir hücre: akü paketinin yapı taşı.", "battery",
         [I("battery_aa", 4), I("insulated_wire", 1)], "electronics", 1)
    comp("battery_pack", "Akü Paketi", 3, 1.2, 60, ["power_source", "energy_storage", "electronic"],
         "Taşınabilir güç: akülü aletler, yem, şok bombası.", "battery",
         [I("battery_cell", 3), I("circuit_basic", 1), I("plastic_sheet", 1)], "electronics", 2)
    comp("transformer_coil", "Trafo Bobini", 3, 2.5, 60, ["coil", "electronic", "heavy"],
         "Kaynak makinesi ve inverterin kalbi.", "iz2_power_transformer", [I("copper_coil", 3), I("steel_sheet", 1)], "electronics", 2)
    comp("inverter_unit", "İnvertör", 3, 1.5, 70, ["electronic", "logic"],
         "Akü gücünü evsel akıma çevirir: güneş sistemi ve büyük aküler.", "iz2_power_inverter",
         [I("transformer_coil", 1), I("circuit_module", 1), I("capacitor_salvaged", 2)], "electronics", 3)
    comp("charge_controller", "Şarj Kontrolcüsü", 3, 0.4, 50, ["electronic", "logic"],
         "Güneş panelini aküye güvenle bağlar.", "iz2_power_charge_controller",
         [I("circuit_module", 1), I("relay_unit", 1), I("fuse", 2)], "electronics", 2)
    comp("speaker_unit", "Hoparlör", 2, 0.5, 18, ["speaker", "electronic", "magnetic"],
         "Mıknatıs ve bobin: siren ve radyo yemi.", "iz2_defense_decoy_speaker", [I("magnet", 1), I("copper_coil", 1), I("plastic_sheet", 1)],
         "electronics", 1)
    comp("capacitor_bank_part", "Kondansatör Bankası", 4, 1.5, 110, ["electronic", "energy_storage"],
         "Ani yüksek akım: tesla bobini.", "iz2_power_battery_bank", [I("capacitor_salvaged", 8), I("insulated_wire", 3), I("circuit_module", 1)],
         "electronics", 3, learn="skill:cr_automation")
    comp("wire_spool", "Kablo Makarası", 1, 1.5, 12, ["wire", "conductive_metal"],
         "Direk ve tesisat için uzun kablo.", "iz2_power_cable_reel_heavy", [I("insulated_wire", 6)], "workbench", 1)

    def dev(iid, name, tier, weight, value, desc, catalog, model, inputs, station, stier, cat, sub, learn="", effects=None):
        m = R.model(*model) if isinstance(model, tuple) else R.model(model)
        R.item(F, iid, name, "station", tier, weight, value, ["placeable", "powered"], desc + " İnşa kipinde (B) kurulur.",
               stack=2, model=m, effects=effects or {})
        R.placeables[iid] = {"label": name, "model": m, **catalog}
        R.recipe(FAM, "r_" + iid, name, iid, 1, inputs, station, stier, 12 + tier * 5, cat, sub, desc, learn=learn)

    # --- uretim ---
    dev("generator_small", "Küçük Jeneratör", 2, 25.0, 300, "400 W; saatte bir birim yakıt yakar (yükle orantılı). GÜRÜLTÜLÜ.",
        {"kind": "generator", "output": 400, "fuel_hours": 4, "tank_hours": 12, "noise": 300, "material": "placed_heavy"},
        ("production/generator_01", "generator"), [I("motor_small", 1), I("alternator", 1), I("metal_plate", 3), I("insulated_wire", 3)],
        "mechanic", 1, "enerji", "Jeneratör")
    dev("generator_diesel", "Mazot Jeneratörü", 3, 60.0, 700, "1500 W; mazot/benzin/yağ yakar. Çok gürültülü.",
        {"kind": "generator", "output": 1500, "fuel_hours": 5, "tank_hours": 20, "noise": 480, "material": "placed_heavy"},
        ("iz2_power_fuel_generator_large", "military/generator_01"),
        [I("motor_large", 1), I("alternator", 1), I("crank_shaft", 1), I("steel_sheet", 2), I("wire_spool", 1)],
        "mechanic", 3, "enerji", "Jeneratör", learn="level:12")
    dev("generator_wood", "Odun Gazlaştırıcı", 3, 45.0, 500, "800 W; YAKIT olarak ateş yakıtı (odun, kömür) da yakar.",
        {"kind": "generator", "output": 800, "fuel_hours": 3, "tank_hours": 12, "noise": 260, "material": "placed_heavy",
         "fuel_tag": "cook_fuel"},
        ("military/generator_02", "generator"), [I("motor_small", 1), I("alternator", 1), I("pipe_fitting", 4), I("steel_sheet", 2),
                                                 I("valve", 1)], "mechanic", 2, "enerji", "Jeneratör")
    dev("generator_pedal", "Pedallı Jeneratör", 1, 12.0, 90, "60 W sabit (koloni pedal çevirir): sessiz, yakıtsız.",
        {"kind": "turbine", "output": 60, "material": "placed_light"},
        "iz2_power_pedal_generator", [I("alternator", 1), I("gear_large", 1), I("chain", 1), I("wood_beam", 2)], "mechanic", 1,
        "enerji", "Jeneratör")
    dev("solar_small", "Küçük Güneş Paneli", 2, 6.0, 120, "Gündüz 60 W, gece üretmez. Sessiz.",
        {"kind": "solar", "output": 60, "material": "placed_light"},
        ("production/solar_01", "solar_panel"), [I("solar_cell", 4), I("plastic_sheet", 1), I("insulated_wire", 2)], "electronics", 1,
        "enerji", "Güneş")
    dev("solar_panel_kit", "Güneş Paneli", 3, 14.0, 300, "Gündüz 160 W.",
        {"kind": "solar", "output": 160, "material": "placed_light"},
        ("production/solar_02", "solar_panel"), [I("solar_cell", 10), I("glass_pane", 1), I("aluminum_ingot", 2), I("charge_controller", 1)],
        "electronics", 2, "enerji", "Güneş")
    dev("solar_array", "Güneş Dizisi", 4, 40.0, 800, "Gündüz 420 W: büyük üssün omurgası.",
        {"kind": "solar", "output": 420, "material": "placed_heavy", "size": [2, 1, 2]},
        ("iz2_power_solar_mount", "solar_panel"), [I("solar_cell", 24), I("glass_pane", 3), I("aluminum_ingot", 4),
                                                   I("charge_controller", 1), I("inverter_unit", 1)], "electronics", 3, "enerji", "Güneş",
        learn="skill:cr_quality")
    dev("wind_small", "Küçük Rüzgâr Türbini", 2, 18.0, 220, "Gece gündüz 90 W civarı, rüzgârla dalgalanır.",
        {"kind": "turbine", "output": 90, "material": "placed_light"},
        "iz2_power_wind_micro", [I("alternator", 1), I("aluminum_ingot", 2), I("axle", 1), I("pipe_steel", 2)], "mechanic", 2,
        "enerji", "Rüzgâr")
    dev("wind_large", "Rüzgâr Türbini", 3, 45.0, 520, "Gece gündüz 260 W civarı.",
        {"kind": "turbine", "output": 260, "material": "placed_heavy"},
        ("military/radar_01", "iz2_power_wind_micro"), [I("alternator", 2), I("aluminum_ingot", 4), I("axle", 1), I("gear_large", 2),
                                                        I("wood_beam", 4)], "mechanic", 3, "enerji", "Rüzgâr", learn="level:14")
    # --- depolama ---
    dev("battery_bank_small", "Akü Grubu", 2, 30.0, 150, "1200 Wh depolar: gece ışığı.",
        {"kind": "battery", "capacity": 1200, "material": "placed_heavy"},
        ("production/battery_01", "battery"), [I("battery_car", 2), I("insulated_wire", 3), I("fuse", 2)], "electronics", 1,
        "enerji", "Akü")
    dev("battery_bank_lead", "Kurşun Akü Bankası", 3, 60.0, 380, "3500 Wh depolar.",
        {"kind": "battery", "capacity": 3500, "material": "placed_heavy"},
        ("production/battery_02", "iz2_power_battery_bank"), [I("battery_car", 4), I("battery_acid", 2), I("inverter_unit", 1),
                                                              I("wire_spool", 1)], "electronics", 2, "enerji", "Akü")
    dev("battery_bank_lithium", "Lityum Paket Dolabı", 4, 25.0, 900, "8000 Wh: hafif ve büyük depo.",
        {"kind": "battery", "capacity": 8000, "material": "placed_heavy"},
        "iz2_power_battery_bank", [I("battery_pack", 6), I("circuit_module", 2), I("inverter_unit", 1), I("metal_plate", 2)],
        "electronics", 3, "enerji", "Akü", learn="skill:cr_quality")
    # --- dagitim ---
    dev("power_pole_wood", "Ahşap Kablo Direği", 1, 8.0, 30, "Kabloyu 16 m taşır: uzak yapıları aynı ağa bağlar.",
        {"kind": "relay", "reach": 16, "material": "placed_light"},
        ("production/cable_01", "street_lamp"), [I("wood_beam", 1), I("wire_spool", 1)], "carpentry", 1, "elektrik", "Dağıtım")
    dev("power_pole_steel", "Çelik Kablo Direği", 2, 14.0, 70, "Kabloyu 26 m taşır.",
        {"kind": "relay", "reach": 26, "material": "placed_heavy"},
        ("production/cable_02", "street_lamp"), [I("pipe_steel", 3), I("wire_spool", 2), I("rivets", 4)], "forge", 2, "elektrik", "Dağıtım")
    dev("junction_box", "Bağlantı Kutusu", 1, 2.0, 20, "Kısa menzil bağlantı (10 m), duvar dibine.",
        {"kind": "relay", "reach": 10, "material": "placed_light"},
        ("production/distribution_01", "iz2_power_fuse_box_weather"), [I("insulated_wire", 3), I("fuse", 2), I("plastic_sheet", 1)],
        "electronics", 1, "elektrik", "Dağıtım")
    dev("power_switch", "Şalter", 1, 1.5, 25, "E ile aç/kapat: kapalıyken ağı ikiye böler.",
        {"kind": "switch", "reach": 6, "material": "placed_light"},
        ("production/distribution_02", "electrical_breaker_panel"), [I("relay_unit", 1), I("insulated_wire", 2), I("plastic_sheet", 1)],
        "electronics", 1, "elektrik", "Dağıtım")
    dev("sensor_motion", "Hareket Sensörü", 2, 0.8, 60, "Ağdaki lamba ve elektrikli tuzaklar yalnızca zombi gelince çalışır.",
        {"kind": "sensor", "mode": "motion", "radius": 12, "solid": False},
        "build_defense/defense_alarm_01", [I("sensor_module", 1), I("insulated_wire", 2)], "electronics", 2, "elektrik", "Sensör")
    dev("sensor_night", "Alacakaranlık Sensörü", 2, 0.8, 50, "Ağdaki lambalar yalnızca karanlıkta yanar.",
        {"kind": "sensor", "mode": "night", "solid": False},
        "build_defense/defense_alarm_02", [I("sensor_module", 1), I("solar_cell", 1)], "electronics", 2, "elektrik", "Sensör")
    dev("sensor_plate", "Basınç Plakası", 1, 1.5, 30, "Üstüne basan zombi ağı tetikler (1 m).",
        {"kind": "sensor", "mode": "motion", "radius": 1.2, "solid": False},
        "iz2_roadwork_plate", [I("metal_plate", 1), I("spring", 2), I("relay_unit", 1)], "workbench", 1, "elektrik", "Sensör")

    # --- aydinlatma ---
    lights = [
        ("lamp_oil", "Gaz Lambası", 1, 0, 8, 1.2, [255, 200, 140], False, "Yakıtsız değil ama elektriksiz: hep yanar (E ile söndür).",
         "desk_lamp", [I("bottle_empty", 1), T("chemical_fuel", 1), I("cloth_rag", 1)], "hands", 1),
        ("lamp_solar", "Güneş Şarjlı Lamba", 2, 0, 9, 1.3, [220, 236, 255], True, "Kendi paneli var: yalnızca geceleri yanar.",
         "street_lamp", [I("solar_cell", 2), I("led", 3), I("battery_cell", 1)], "electronics", 1),
        ("lamp_ceiling", "Ampullü Lamba", 1, 15, 10, 1.5, [255, 222, 170], False, "Basit tavan lambası (15 W).",
         "ceiling_lamp_apartment", [I("lamp_bulb", 1), I("insulated_wire", 1)], "workbench", 1),
        ("lamp_led", "LED Lamba", 2, 6, 12, 1.6, [235, 242, 255], False, "Az güç, çok ışık (6 W).",
         "fluorescent_fixture", [I("led_panel", 1), I("insulated_wire", 1)], "electronics", 1),
        ("lamp_string", "Işık Zinciri", 1, 10, 14, 1.0, [255, 214, 150], False, "Avlu boyunca sıra lamba (10 W).",
         "iz2_district_laundry_line", [I("led", 6), I("insulated_wire", 3)], "electronics", 1),
        ("lamp_street", "Sokak Lambası", 2, 40, 18, 2.4, [255, 236, 200], False, "Yüksek direk lambası (40 W).",
         "street_lamp", [I("led_panel", 1), I("pipe_steel", 2), I("insulated_wire", 3)], "forge", 2),
        ("lamp_flood", "Taşkın Işığı", 3, 60, 22, 3.0, [255, 250, 236], False, "Geniş alan projektörü (60 W).",
         ("military/floodlight_01", "street_lamp"), [I("led_panel", 2), I("metal_plate", 1), I("insulated_wire", 2)], "electronics", 2),
        ("lamp_wall", "Duvar Apliği", 1, 8, 8, 1.4, [255, 226, 180], False, "Koridor için küçük aplik (8 W).",
         "wall_sconce", [I("led", 3), I("insulated_wire", 1), I("plastic_sheet", 1)], "electronics", 1),
    ]
    for (iid, name, tier, power, rng, energy, color, night, desc, model, inputs, station, stier) in lights:
        dev(iid, name, tier, 2.0 + tier, 12 * tier + power // 2, desc,
            {"kind": "light", "power": power, "solid": False, "night_only": night,
             "light": {"range": rng, "energy": energy, "color": color, "height": 1.8 if rng < 16 else 2.6}},
            model, inputs, station, stier, "aydinlatma", "Lamba")

    # --- elektrikli cihazlar ---
    dev("fridge_electric", "Elektrikli Buzdolabı", 3, 40.0, 380, "Üs deposunda yemek bozulmasını dörtte bire indirir; YAKIT değil ELEKTRİK (120 W).",
        {"kind": "cold_room", "power": 120, "material": "placed_heavy"},
        ("health/cooler_01", "fridge_apartment"), [I("motor_small", 1), I("copper_coil", 2), I("metal_plate", 4), I("insulated_wire", 3)],
        "electronics", 2, "elektrikli_cihaz", "Mutfak")
    dev("purifier_electric", "Elektrikli Arıtıcı", 3, 30.0, 420, "Her gün üs deposundaki kirli suyun 8 şişesini temizler (60 W).",
        {"kind": "purifier", "power": 60, "daily": 8, "material": "placed_heavy"},
        ("production/filter_02", "iz2_water_purifier_pump"), [I("pump_unit", 1), I("filter_cartridge", 2), I("ceramic_filter", 2),
                                                              I("circuit_basic", 1)], "electronics", 2, "elektrikli_cihaz", "Su",
        learn="skill:cr_water_eng")
    dev("hydroponic_tray", "Hidroponik Tepsi", 3, 15.0, 300, "Elektrikle %60 hızlı büyütür, yarı su harcar (35 W).",
        {"kind": "planter", "power": 35, "growth": 1.0, "material": "placed_light"},
        ("iz2_farm_vertical_planter", "crop_bed"), [I("pump_unit", 1), I("led_panel", 2), I("plastic_sheet", 3), I("pvc_pipe", 2)],
        "electronics", 2, "elektrikli_cihaz", "Tarım", learn="skill:cr_electric")
