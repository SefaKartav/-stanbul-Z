"""Savunma ve tuzak ailesi: tuzaklar, taretler, alarmlar, yemler, savunma yapilari."""
from lib import Registry, I, T
from f_build import _box

F = "items/gen_defense.json"
FAM = "defense"


def build(R: Registry) -> None:
    R.category("tuzak", "Tuzaklar")
    R.category("taret", "Taretler")
    R.category("alarm", "Alarm ve yem")
    R.category("savunma_yapisi", "Savunma yapıları")
    R.category("insaat", "İnşaat ve savunma")
    R.tag("defense_piece", "savunma parçası")

    def placeable_item(iid, name, tier, weight, value, desc, effects, model, catalog, inputs, station, stier, cat, sub,
                       learn="", power=0.0):
        R.item(F, iid, name, "station", tier, weight, value, ["placeable", "defense"], desc + " İnşa kipinde (B) kurulur.",
               stack=6 if weight < 5 else 2, model=R.model(*model) if isinstance(model, tuple) else R.model(model),
               effects=effects)
        R.placeables[iid] = {"label": name, "model": R.model(*model) if isinstance(model, tuple) else R.model(model), **catalog}
        R.recipe(FAM, "r_" + iid, name, iid, 1, inputs, station, stier, 10 + tier * 4, cat, sub, desc, learn=learn)

    # --- tuzaklar ---
    traps = [
        ("trap_wood_spikes", "Ahşap Kazık Hattı", 1, 3.0, 40, {"damage": 14, "uses": 10}, {"effect": "damage", "radius": 0.9},
         "Sivri kazıklar: sessiz, ucuz, çabuk tükenir.", "build_defense/defense_spikes_01",
         [I("wood_plank", 4), I("nail", 6)], "carpentry", 1, ""),
        ("trap_steel_spikes", "Çelik Kazık Hattı", 2, 5.0, 120, {"damage": 26, "uses": 24}, {"effect": "damage", "radius": 0.9},
         "Kaynaklı çelik şişler.", "build_defense/defense_spikes_02", [I("iron_bar", 3), I("metal_plate", 1)], "forge", 2, ""),
        ("trap_barbed_wire", "Dikenli Tel Engeli", 1, 2.5, 50, {"damage": 4, "uses": 40}, {"effect": "slow", "slow": 0.5, "radius": 1.0,
                                                                                          "cooldown": 0.6},
         "Zombileri %50 yavaşlatır ve hafif yaralar.", "build_defense/defense_wire_01", [I("barbed_wire_coil", 1), I("wood_plank", 2)],
         "workbench", 1, ""),
        ("trap_razor_wire", "Jiletli Tel", 2, 3.0, 90, {"damage": 10, "uses": 40}, {"effect": "slow", "slow": 0.65, "radius": 1.0,
                                                                                    "cooldown": 0.6},
         "Jiletli sarma: %65 yavaşlatır, keser.", "build_defense/defense_wire_02", [I("barbed_wire_coil", 2), I("blade_blank", 1)],
         "workbench", 2, ""),
        ("trap_bear", "Ayı Kapanı", 2, 4.0, 100, {"damage": 45, "uses": 3}, {"effect": "slow", "slow": 0.85, "radius": 0.7,
                                                                           "cooldown": 3.0},
         "Bacağı kıskaca alır: ağır hasar, zombi neredeyse durur.", "build_defense/defense_trap_mech_01",
         [I("spring_heavy", 2), I("steel_sheet", 1), I("chain", 1)], "forge", 2, ""),
        ("trap_blade", "Döner Bıçak Tuzağı", 3, 12.0, 240, {"damage": 35, "uses": 30}, {"effect": "damage", "radius": 1.2, "power": 40,
                                                                                      "cooldown": 0.5, "sound": "impact_metal"},
         "Motorlu bıçaklar: ELEKTRİK ister (40 W).", "build_defense/defense_trap_mech_02",
         [I("motor_small", 1), I("blade_blank", 3), I("gear_large", 1), I("insulated_wire", 2)], "mechanic", 2, "level:10", 40),
        ("trap_dart", "Ok Tuzağı", 2, 4.0, 90, {"damage": 30, "uses": 12}, {"effect": "damage", "radius": 1.6, "cooldown": 1.2,
                                                                          "sound": "melee_swing"},
         "Tetik teline basan zombiye yaylı ok.", "build_defense/defense_trap_mech_01",
         [I("spring_heavy", 1), I("bolt", 6), I("wood_plank", 2)], "workbench", 2, ""),
        ("trap_flame", "Alev Tuzağı", 3, 6.0, 160, {"damage": 22, "uses": 15}, {"effect": "burn", "radius": 1.3, "cooldown": 1.0,
                                                                              "sound": "break_glass"},
         "Tetiklenince yakıt püskürtür ve tutuşturur.", "gas_cylinder",
         [I("gas_canister", 1), I("valve", 1), I("pipe_fitting", 2), I("spring", 1)], "mechanic", 2, "level:8"),
        ("trap_electric_fence", "Elektrikli Çit", 3, 8.0, 180, {"damage": 18, "uses": 999}, {"effect": "shock", "radius": 1.0, "power": 80,
                                                                                            "cooldown": 0.7, "sound": "impact_metal"},
         "Sürekli çarpar: ELEKTRİK ister (80 W). Sensörlü ağda yalnızca tetiklenince çeker.",
         "build_defense/defense_trap_electric_01", [I("mesh_wire", 2), I("insulated_wire", 4), I("relay_unit", 1)],
         "electronics", 2, "skill:cr_electric", 80),
        ("trap_shock_floor", "Elektrikli Zemin", 3, 6.0, 160, {"damage": 12, "uses": 999}, {"effect": "shock", "radius": 1.3, "power": 50,
                                                                                           "cooldown": 0.5, "sound": "impact_metal"},
         "Metal ızgaraya akım: geniş alanı çarpar (50 W).", "build_defense/defense_trap_electric_02",
         [I("metal_plate", 3), I("insulated_wire", 3), I("relay_unit", 1)], "electronics", 2, "skill:cr_electric", 50),
        ("trap_landmine", "Kara Mayını", 4, 1.5, 220, {"damage": 150, "uses": 1}, {"effect": "explode", "radius": 1.0, "blast": 4.0},
         "Üstüne basınca patlar: geniş alan, blok da kırar. Tek kullanımlık.", "iz2_mission_black_box",
         [I("military_explosive", 1), I("metal_plate", 1), I("primer_compound", 2), I("spring", 1)], "gunsmith", 3, "level:16"),
        ("trap_pipe_mine", "Boru Mayını", 3, 1.5, 120, {"damage": 90, "uses": 1}, {"effect": "explode", "radius": 1.0, "blast": 3.0},
         "El yapımı mayın: boru, barut, çivi.", "iz2_mission_black_box",
         [I("pipe_steel", 1), I("refined_powder", 3), I("nail", 8), I("primer_compound", 1)], "workbench", 2, ""),
        ("trap_tar_pit", "Katran Çukuru", 1, 5.0, 40, {"damage": 0, "uses": 60}, {"effect": "slow", "slow": 0.75, "radius": 1.2,
                                                                                "cooldown": 0.4},
         "Yapışkan zift: zombiler %75 yavaşlar.", "rubble_pile", [I("tar", 3), I("wood_plank", 2)], "workbench", 1, ""),
        ("trap_punji_pit", "Kazıklı Çukur", 2, 4.0, 70, {"damage": 30, "uses": 8}, {"effect": "slow", "slow": 0.9, "radius": 0.9,
                                                                                  "cooldown": 1.5},
         "Kamufle çukur: düşen zombi yaralanır ve takılır.", "build_defense/defense_spikes_01",
         [I("wood_plank", 3), I("nail", 10), I("plant_fiber", 4)], "carpentry", 1, ""),
    ]
    for (iid, name, tier, weight, value, effects, catalog, desc, model, inputs, station, stier, learn, *power) in traps:
        cat = {"kind": "trap", "solid": False, **catalog}
        placeable_item(iid, name, tier, weight, value, desc, effects, model, cat, inputs, station, stier, "tuzak", "Tuzak",
                       learn=learn)

    # --- taretler ---
    turrets = [
        ("turret_12ga", "Pompalı Taret", 4, 14.0, 700, {"damage": 34, "fire_rate": 1.2, "range": 180},
         {"ammo": "ammo_12ga", "magazine": 30, "noise": 520, "sound": "shot_shotgun"},
         "Yakın mesafe: kalabalığı durdurur. 12 kalibre harcar.", [I("gun_barrel", 1), I("firing_mechanism", 1), I("motor_small", 1),
                                                                     I("circuit_module", 1), I("metal_plate", 4)], "electronics", 3, "schematic"),
        ("turret_762", "Tüfek Tareti", 5, 16.0, 950, {"damage": 46, "fire_rate": 1.4, "range": 520},
         {"ammo": "ammo_762", "magazine": 40, "noise": 640, "pierce": 1, "sound": "shot_rifle"},
         "Uzun menzil, deler. 7.62 harcar.", [I("gun_barrel", 1), I("firing_mechanism", 1), I("motor_small", 2), I("circuit_module", 1),
                                               I("optic_assembly", 1), I("steel_sheet", 2)], "electronics", 3, "schematic"),
        ("turret_dart", "Arbalet Tareti", 3, 10.0, 380, {"damage": 30, "fire_rate": 1.0, "range": 260},
         {"ammo": "bolt", "magazine": 24, "noise": 60, "sound": "melee_swing"},
         "Neredeyse SESSİZ taret: arbalet oku harcar.", [I("spring_heavy", 2), I("motor_small", 1), I("pulley", 2), I("circuit_basic", 1),
                                                          I("wood_beam", 2)], "workbench", 3, ""),
        ("turret_smg", "Makineli Taret", 4, 12.0, 620, {"damage": 12, "fire_rate": 6.0, "range": 280},
         {"ammo": "ammo_9mm", "magazine": 90, "noise": 430, "sound": "shot_smg"},
         "Hızlı atar, çabuk bitirir. 9mm harcar.", [I("gun_barrel", 1), I("firing_mechanism", 1), I("motor_small", 1), I("magazine_blank", 2),
                                                     I("circuit_module", 1)], "electronics", 3, "level:14"),
        ("turret_tesla", "Tesla Bobini", 5, 20.0, 1200, {"damage": 22, "fire_rate": 2.0, "range": 120},
         {"ammo": "energy", "power": 250, "damage_type": "shock", "noise": 200, "sound": "impact_metal"},
         "Mermisiz: ELEKTRİK ile çarpar (250 W). Güçlü ağ ister.", [I("copper_coil", 4), I("capacitor_bank_part", 1), I("relay_unit", 2),
                                                                    I("steel_sheet", 2)], "electronics", 4, "skill:cr_automation", 250),
    ]
    for (iid, name, tier, weight, value, effects, catalog, desc, inputs, station, stier, learn, *power) in turrets:
        cat = {"kind": "turret", "material": "placed_heavy", **catalog}
        placeable_item(iid, name, tier, weight, value, desc + " Şarjörü E ile doldur; boşsa üs deposundan alır.", effects,
                       ("build_defense/defense_turret_02", "turret"), cat, inputs, station, stier, "taret", "Taret", learn=learn)

    # --- alarm ve yem ---
    alarms = [
        ("alarm_tripwire", "Teneke Alarmı", 1, 1.0, 15, {"kind": "alarm", "radius": 6, "noise": 250, "cooldown": 15, "solid": False,
                                                          "sound": "impact_metal"},
         "Tele takılan zombi teneke şıngırdatır: uyarı + dikkat çeken ses.", "iz2_defense_tripwire_alarm",
         [I("wire_steel", 3), I("scrap_metal", 2)], "hands", 1, "", 0),
        ("alarm_bell", "Çan Alarmı", 2, 3.0, 40, {"kind": "alarm", "radius": 10, "noise": 420, "cooldown": 20},
         "Menzilde zombi: çan çalar. Koloni uyanır, sürü de duyar.", "iz2_defense_bell_alarm",
         [I("metal_plate", 2), I("pulley", 1), I("rope", 1)], "workbench", 1, "", 0),
        ("alarm_siren", "Elektrikli Siren", 3, 4.0, 120, {"kind": "alarm", "radius": 16, "noise": 700, "cooldown": 25, "power": 20},
         "Geniş menzil, çok gürültülü (20 W).", "build_defense/defense_alarm_02",
         [I("speaker_unit", 1), I("sensor_module", 1), I("insulated_wire", 2)], "electronics", 2, "", 20),
        ("alarm_silent", "Sessiz Hareket Alarmı", 3, 2.0, 140, {"kind": "alarm", "radius": 20, "noise": 0, "cooldown": 15, "power": 5},
         "Yalnızca sana haber verir: ses yok (5 W).", "build_defense/defense_alarm_01",
         [I("sensor_module", 1), I("circuit_basic", 1), I("led", 2)], "electronics", 2, "", 5),
        ("decoy_radio", "Radyo Yemi", 2, 3.0, 90, {"kind": "decoy", "noise": 520, "interval": 14, "power": 10},
         "Aralıklı müzik: zombileri üssünden uzağa toplar (10 W).", "iz2_defense_decoy_speaker",
         [I("speaker_unit", 1), I("circuit_basic", 1), I("battery_pack", 1)], "electronics", 1, "", 10),
        ("decoy_clockwork", "Kurmalı Yem", 1, 2.0, 30, {"kind": "decoy", "noise": 360, "interval": 20},
         "Yaylı saat mekanizması: elektrik istemez.", "alarm_clock", [I("spring", 3), I("gear_small", 2), I("scrap_metal", 1)],
         "workbench", 1, "", 0),
    ]
    for (iid, name, tier, weight, value, catalog, desc, model, inputs, station, stier, learn, power) in alarms:
        placeable_item(iid, name, tier, weight, value, desc, {}, model, catalog, inputs, station, stier, "alarm",
                       "Alarm" if catalog["kind"] == "alarm" else "Yem", learn=learn)

    # --- savunma yapilari (B kipi parca) ---
    def dpiece(pid, name, desc, cells, material, inputs, station, stier, model, learn=""):
        iid = "bp_" + pid
        R.pieces[pid] = {"material": material, "cells": cells}
        R.item(F, iid, name, "building", 2, round(1.5 * len(cells), 1), 6 * len(cells), ["building_piece", "defense_piece"],
               desc + " İnşa kipinde (B) yerleştirilir.", stack=5, model=R.model(model), build=pid)
        R.recipe(FAM, "r_" + iid, name, iid, 1, inputs, station, stier, 6 + len(cells), "savunma_yapisi", "Savunma yapısı", desc,
                 learn=learn)

    dpiece("sandbag_1", "Kum torbası", "Kurşun tutan tek torba.", [[0, 0, 0]], "sandbag", [I("sand", 3), T("fabric", 1)], "hands", 1,
           "sandbags")
    dpiece("sandbag_wall", "Kum torbası duvarı 3×1", "Diz boyu siper hattı.", [[x, 0, 0] for x in range(-1, 2)], "sandbag",
           [I("sand", 8), T("fabric", 3)], "hands", 1, "sandbags")
    dpiece("sandbag_bunker", "Kum torbası mevzisi", "L biçimli 2 kat mevzi.",
           [[x, y, 0] for x in range(-1, 2) for y in range(2)] + [[-1, y, 1] for y in range(2)], "sandbag",
           [I("sand", 20), T("fabric", 7)], "workbench", 1, "sandbags")
    dpiece("concrete_barrier", "Beton bariyer", "2×1 yol bariyeri: aracı ve sürüyü keser.", [[0, 0, 0], [1, 0, 0]], "pb_concrete",
           [I("concrete_mix", 2), I("rebar", 1)], "masonry", 1, "road_barrier")
    dpiece("tank_trap", "Tanksavar", "Çelik çapraz: araç geçemez, zombi takılır.", [[0, 0, 0]], "pb_steel",
           [I("iron_bar", 3), I("rivets", 4)], "forge", 2, "steel_barricade")
    dpiece("palisade", "Palisat kütüğü", "3 m kütük direk.", [[0, y, 0] for y in range(3)], "pb_log", [I("wood_log", 2)], "carpentry", 1,
           "military/fence_01")
    dpiece("palisade_wall", "Palisat duvarı 3×3", "Kütük duvar: ucuz ve sağlam.", _box(3, 3, 1), "pb_log",
           [I("wood_log", 6), I("rope", 2)], "carpentry", 1, "military/fence_02")
    dpiece("gabion", "Gabion", "Taş dolu tel kafes: 1×2, mermiyi yutar.", [[0, 0, 0], [0, 1, 0]], "pb_gabion",
           [I("mesh_wire", 1), I("stone_chunk", 6)], "workbench", 1, "iz2_defense_gate_brace")
    dpiece("barricade_spiked", "Kazıklı barikat 3×2", "Sivri kazıklı ahşap barikat.", _box(3, 2, 1), "barricade",
           [I("wood_plank", 6), I("nail", 12), T("sharp", 6)], "carpentry", 1, "wood_barricade")
    dpiece("barricade_steel", "Çelik barikat 3×2", "Sac ve demir: uzun dayanır.", _box(3, 2, 1), "pb_steel",
           [I("steel_sheet", 3), I("iron_bar", 3), I("rivets", 8)], "forge", 3, "steel_barricade", learn="level:12")
    dpiece("chainlink_fence", "Tel örgü çit 3×2", "Görüş açık çit; zombi geçemez.", _box(3, 2, 1), "pb_mesh",
           [I("mesh_wire", 3), I("pipe_steel", 2)], "workbench", 1, "iz2_defense_wire_fence")
    dpiece("firing_step", "Atış basamağı 3×1", "Duvar arkasına yarım basamak: siperden ateş.", [[x, 0, 0] for x in range(-1, 2)],
           "pb_wood_slab", [I("wood_plank", 3), I("nail", 4)], "carpentry", 1, "pallet")
    # Salvage/onarim tarifesi (kum torbasi, barikat eski malzeme)
    for mat, item in [("sandbag", "sand"), ("barricade", "wood_plank"), ("pb_log", "wood_log"), ("pb_gabion", "stone_chunk")]:
        R.upgrades.setdefault(mat, {"to": "", "cost": [], "repair": [{"item": item, "count": 1}],
                                    "salvage": [{"item": item, "count": 1}]})

    # --- savunma isiklari ---
    for iid, name, tier, power, rng, energy, model, inputs, stier in [
        ("spotlight", "Projektör", 2, 60, 26, 3.0, "build_defense/defense_spotlight_01",
         [I("led_panel", 1), I("metal_plate", 1), I("insulated_wire", 2)], 2),
        ("searchlight", "Arama Işığı", 3, 120, 40, 4.5, ("iz2_defense_searchlight", "build_defense/defense_spotlight_02"),
         [I("led_panel", 2), I("glass_lens", 1), I("motor_small", 1), I("insulated_wire", 3)], 3),
    ]:
        placeable_item(iid, name, tier, 6.0, 90 * tier, f"Güçlü savunma ışığı ({power} W, {rng} m).", {}, model,
                       {"kind": "light", "power": power, "light": {"range": rng, "energy": energy, "height": 2.2, "shadow": True,
                                                                   "color": [255, 246, 226]}}, inputs, "electronics", stier,
                       "alarm", "Işık")
