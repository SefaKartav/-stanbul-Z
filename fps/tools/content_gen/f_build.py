"""Yapi ve guclendirme ailesi: malzeme kademeleri x yapi bicimleri, kapilar, catilar,
merdivenler, yukseltme kitleri. Ayrica oyuncu yapisi blok malzemeleri (60+ indeks).

ISLEV FARKLARI (belgenin istedigi aciklama):
  * Malzeme kademesi: can (HP), mermi carpani, delinme direnci ve zombinin kirma
    suresi. Iskelet 60 HP (gecici), ahsap 220, guclendirilmis ahsap 420, hurda sac
    500, tugla 700, kesme tas 900, beton 1300, betonarme 2000, celik 3000.
  * Bicim: yerlestirilen hucre deseni. Duvar 1x1/2x2/3x3 (hiz ve maliyet), doseme
    (yatay: kat, kopru, cati), kolon (tasiyici), kose (L), kapi boslugu (geçit),
    pencereli duvar (gorus + mermi gecmez cam), mazgal (1 hucrelik atis deligi:
    zombi gecemez, sen ates edersin), siper (ust sira seyrek: comelip ates),
    yarim blok ve alcak siper (0.5 m: ustunden ates, arkasinda comel), merdiven
    (0.5 m basamak: yuruyerek cikilir), arac rampasi (3 genis: arac cikar).
  * Kapi/kapak/garaj: E ile acilip kapanir; kapaliyken kati, zombi kirabilir.
"""
from lib import Registry, I, T

F = "items/gen_building.json"
FAM = "build"

# kimlik, ad, can, mermi carpani, delinme, doku, zombi kirar, ses, dilim (slab) cani
TIERS = [
    ("frame", "İskelet", 60, 1.2, 0.2, "pb_frame", "impact_wood"),
    ("wood", "Ahşap", 220, 1.0, 0.4, "wood_plank", "impact_wood"),
    ("woodr", "Güçlendirilmiş ahşap", 420, 0.8, 0.6, "pb_wood_reinforced", "impact_wood"),
    ("scrap", "Hurda sac", 500, 0.6, 0.8, "pb_scrap", "impact_metal"),
    ("brick", "Tuğla", 700, 0.7, 0.9, "brick", "impact_stone"),
    ("stone", "Kesme taş", 900, 0.55, 1.1, "pb_stone_block", "impact_stone"),
    ("concrete", "Beton", 1300, 0.5, 1.2, "concrete", "impact_stone"),
    ("rconcrete", "Betonarme", 2000, 0.4, 1.5, "pb_rconcrete", "impact_stone"),
    ("steel", "Çelik", 3000, 0.35, 1.8, "pb_steel_plate", "impact_metal"),
]

# Hucre basina maliyet, istasyon, kademe, yukseltme hedefi, sokum geri kazanimi
TIER_COST = {
    "frame": ([("wood_plank", 1), ("nail", 1)], "hands", 1, "wood", [("wood_plank", 1)]),
    "wood": ([("wood_plank", 2), ("#fastener", 2)], "carpentry", 1, "woodr", [("wood_plank", 1)]),
    "woodr": ([("wood_plank", 2), ("metal_bracket", 1), ("#fastener", 2)], "carpentry", 2, "brick", [("wood_plank", 1)]),
    "scrap": ([("scrap_metal", 3), ("rivets", 3)], "forge", 1, "steel", [("scrap_metal", 1)]),
    "brick": ([("#brick_material", 4), ("mortar", 1)], "masonry", 1, "concrete", [("loose_brick", 2)]),
    "stone": ([("stone_block", 1), ("mortar", 1)], "masonry", 1, "concrete", [("stone_chunk", 2)]),
    "concrete": ([("concrete_mix", 1), ("cinder_block", 1)], "masonry", 2, "rconcrete", [("concrete_rubble", 1)]),
    "rconcrete": ([("concrete_mix", 2), ("rebar_mesh", 1)], "masonry", 3, "steel", [("concrete_rubble", 1), ("rebar", 1)]),
    "steel": ([("steel_sheet", 1), ("rivets", 4)], "forge", 3, "", [("scrap_metal", 2)]),
}
# Yukseltme kiti: bir hucreyi ust kademeye tasir (malzeme + kit)
UPGRADE_KITS = {
    "frame": ("Ahşap kaplama kiti", [I("wood_plank", 2), T("fastener", 2)], "carpentry", 1),
    "wood": ("Ahşap güçlendirme kiti", [I("metal_bracket", 1), I("wood_plank", 1), T("fastener", 2)], "carpentry", 2),
    "woodr": ("Tuğla örme kiti", [T("brick_material", 3), I("mortar", 1)], "masonry", 1),
    "scrap": ("Çelik kaplama kiti", [I("steel_sheet", 1), I("rivets", 4)], "forge", 3),
    "brick": ("Beton döküm kiti", [I("concrete_mix", 1), I("cinder_block", 1)], "masonry", 2),
    "stone": ("Taş üstü beton kiti", [I("concrete_mix", 1)], "masonry", 2),
    "concrete": ("Betonarme kiti", [I("concrete_mix", 1), I("rebar_mesh", 1)], "masonry", 3),
    "rconcrete": ("Çelik zırh kiti", [I("steel_sheet", 1), I("rivets", 4)], "forge", 3),
}

# bicim kimligi, ad, desen fonksiyonu, maliyet carpani (indirim), aciklama
def _box(w, h, d, xoff=None):
    xoff = -(w // 2) if xoff is None else xoff
    return [[x + xoff, y, z] for y in range(h) for x in range(w) for z in range(d)]


def _floor(w, d):
    return [[x - (w // 2), 0, z] for x in range(w) for z in range(d)]


SHAPES = [
    ("block", "blok", [[0, 0, 0]], 1.0, "Tek blok."),
    ("wall2", "duvar 2×2", _box(2, 2, 1, 0), 0.95, "2×2 duvar: tek hamlede dört blok."),
    ("wall3", "duvar 3×3", _box(3, 3, 1), 0.9, "3×3 duvar: bir sokak ağzının bir parçası."),
    ("floor2", "döşeme 2×2", _floor(2, 2), 0.95, "Yatay döşeme: kat, köprü, çatı."),
    ("floor3", "döşeme 3×3", _floor(3, 3), 0.9, "Geniş döşeme."),
    ("pillar", "kolon", [[0, y, 0] for y in range(3)], 0.95, "3 m taşıyıcı kolon: döşemeye destek olur."),
    ("corner", "köşe", [[0, y, 0] for y in range(2)] + [[1, y, 0] for y in range(2)] + [[0, y, 1] for y in range(2)], 0.95,
     "L biçimli köşe: iki duvarı bağlar."),
    ("doorway", "kapı boşluğu", [c for c in _box(3, 3, 1) if not (c[0] == 0 and c[1] < 2)], 0.9,
     "Ortası açık 3×3 duvar: kapı parçası buraya takılır."),
    ("window", "pencereli duvar", [c + (["pb_glass_reinforced"] if c[0] == 0 and c[1] == 1 else []) for c in _box(3, 3, 1)], 0.9,
     "Ortası cam: içerisi görülür, mermi ve zombi geçmez (cam kırılabilir)."),
    ("slit", "mazgal", [c for c in _box(3, 2, 1) if not (c[0] == 0 and c[1] == 1)], 0.9,
     "Tek hücrelik atış deliği: sen ateş edersin, zombi sığmaz."),
    ("parapet", "siper", [c for c in _box(3, 2, 1) if not (c[1] == 1 and c[0] == 0)], 0.9,
     "Alt sıra dolu, üst sıra seyrek: arkasında çömelip ateş."),
]
SLAB_SHAPES = [
    ("half", "yarım blok", [[0, 0, 0]], 1.0, "0,5 m blok: basamak, set, alçak siper."),
    ("lowcover", "alçak siper", [[-1, 0, 0], [0, 0, 0], [1, 0, 0]], 0.95, "0,5 m yüksek 3 blok: üstünden ateş, arkasında çömel."),
]


def _stairs(width):
    cells = []
    for x in range(width):
        cells += [[x, 0, 0, "S"], [x, 0, 1, "F"], [x, 1, 2, "S"], [x, 1, 3, "F"]]
    return cells


def build(R: Registry) -> None:
    R.category("yapi", "Yapı parçaları")
    R.category("yukseltme", "Yükseltme kitleri")
    R.category("kapi", "Kapı ve kapaklar")
    R.category("cati", "Çatı ve merdiven")
    for tag, name in [("building_piece", "yapı parçası")]:
        R.tag(tag, name)

    # --- blok malzemeleri ---
    index = 62
    tier_mat = {}
    for tid, tname, hp, mult, pen, tex, sound in TIERS:
        mid = "pb_" + tid
        R.blocks[mid] = {"index": index, "name": tname, "max_hp": hp, "bullet_damage_multiplier": mult,
                         "penetration_resistance": pen, "texture": {"all": tex}, "zombie_breakable": True,
                         "impact_sound_id": sound, "color": [150, 140, 128],
                         **({"transparent": True} if tid == "frame" else {})}
        tier_mat[tid] = mid
        index += 1
    for tid, tname, hp, mult, pen, tex, sound in TIERS:
        mid = "pb_" + tid + "_slab"
        R.blocks[mid] = {"index": index, "name": tname + " (yarım)", "max_hp": int(hp * 0.6), "bullet_damage_multiplier": mult,
                         "penetration_resistance": pen * 0.7, "texture": {"all": tex}, "shape": "slab",
                         "zombie_breakable": True, "impact_sound_id": sound, "color": [150, 140, 128]}
        index += 1
    extra_mats = [
        ("pb_glass_reinforced", "Takviyeli cam", 160, 1.2, 0.3, {"all": "pb_glass_reinforced"}, {"transparent": True}, "break_glass"),
        ("pb_bars", "Demir parmaklık", 600, 0.3, 0.1, {"all": "pb_bars"}, {"transparent": True}, "impact_metal"),
        ("pb_mesh", "Tel örgü", 250, 0.4, 0.05, {"all": "pb_mesh"}, {"transparent": True}, "impact_metal"),
        ("pb_log", "Kütük palisat", 500, 0.8, 0.9, {"top": "log_top", "side": "log_side", "bottom": "log_top"}, {}, "impact_wood"),
        ("pb_gabion", "Gabion", 900, 0.4, 1.4, {"all": "pb_gabion"}, {}, "impact_stone"),
        ("pb_door_wood", "Ahşap kapı", 250, 1.0, 0.4, {"all": "pb_door_wood"}, {}, "impact_wood"),
        ("pb_door_reinforced", "Takviyeli ahşap kapı", 520, 0.8, 0.7, {"all": "pb_door_reinforced"}, {}, "impact_wood"),
        ("pb_door_metal", "Sac kapı", 900, 0.6, 1.0, {"all": "pb_door_metal"}, {}, "impact_metal"),
        ("pb_door_steel", "Çelik kapı", 1800, 0.4, 1.6, {"all": "pb_door_steel"}, {}, "impact_metal"),
        ("pb_roof_tile", "Kiremit çatı", 300, 0.9, 0.6, {"all": "roof_tile"}, {}, "impact_stone"),
        ("pb_roof_sheet", "Sac çatı", 400, 0.6, 0.7, {"all": "metal_sheet"}, {}, "impact_metal"),
        ("pb_roof_shingle", "Ahşap kiremit çatı", 240, 1.0, 0.4, {"all": "pb_shingle"}, {}, "impact_wood"),
        ("pb_ladder_wood", "Ahşap merdiven", 150, 1.0, 0.1, {"all": "pb_ladder_wood"},
         {"transparent": True, "passable": True, "climbable": True}, "impact_wood"),
        ("pb_ladder_steel", "Çelik merdiven", 450, 0.6, 0.1, {"all": "ladder"},
         {"transparent": True, "passable": True, "climbable": True}, "impact_metal"),
        ("placed_light", "Yapı (hafif)", 150, 1.0, 0.5, {"all": "wood_plank"}, {"render": "none"}, "impact_wood"),
        ("placed_heavy", "Yapı (ağır)", 450, 0.6, 1.0, {"all": "steel"}, {"render": "none"}, "impact_metal"),
    ]
    for mid, name, hp, mult, pen, tex, flags, sound in extra_mats:
        R.blocks[mid] = {"index": index, "name": name, "max_hp": hp, "bullet_damage_multiplier": mult,
                         "penetration_resistance": pen, "texture": tex, "zombie_breakable": True,
                         "impact_sound_id": sound, "color": [150, 140, 128], **flags}
        index += 1
    assert index <= 250

    def piece(piece_id, name, desc, cells, material, cost, station, stier, sub, cat="yapi", door=False, model="wood_barricade",
              fam=FAM, file=F, learn=""):
        """Yapi parcasi esyasi + build_catalog parcasi + uretim tarifi."""
        item_id = "bp_" + piece_id
        n = len(cells)
        R.pieces[piece_id] = {"material": material, "cells": cells, **({"door": True} if door else {})}
        R.item(file, item_id, name, "building", 1 + min(4, n // 4), round(1.0 + 0.8 * n, 1), 4 * n,
               ["building_piece"], desc + f" ({n} hücre) İnşa kipinde (B) yerleştirilir.",
               stack=10 if n <= 4 else 5, model=R.model(model), build=piece_id)
        inputs = []
        for key, per in cost:
            amount = max(1, round(per * n))
            inputs.append(T(key[1:], amount) if key.startswith("#") else I(key, amount))
        R.recipe(fam, "r_" + item_id, name, item_id, 1, inputs, station, stier, 4 + n * 0.8, cat, sub, desc,
                 learn=learn)
        return item_id

    tier_models = {"frame": "pallet", "wood": "build_defense/defense_wood_wall_01", "woodr": "build_defense/defense_wood_wall_02",
                   "scrap": "steel_barricade", "brick": "build_defense/defense_stone_wall_01", "stone": "build_defense/defense_stone_wall_02",
                   "concrete": "build_defense/defense_concrete_wall_01", "rconcrete": "build_defense/defense_concrete_wall_02",
                   "steel": "build_defense/defense_steel_wall_01"}
    tier_names = {t[0]: t[1] for t in TIERS}
    for tid, tname, hp, *_ in TIERS:
        cost, station, stier, up, salvage = TIER_COST[tid]
        mat = tier_mat[tid]
        slab = mat + "_slab"
        learn = "level:%d" % {"frame": 0, "wood": 0, "woodr": 3, "scrap": 3, "brick": 6, "stone": 8, "concrete": 10,
                               "rconcrete": 16, "steel": 20}[tid]
        learn = "" if learn == "level:0" else learn
        for sid, sname, pattern, discount, sdesc in SHAPES:
            cells = [list(c[:3]) + ([c[3]] if len(c) > 3 else []) for c in pattern]
            scaled = [(k, v * discount) for k, v in cost]
            piece(f"{tid}_{sid}", f"{tname} {sname}", f"{tname} ({hp} HP/blok): {sdesc}", cells, mat, scaled, station, stier,
                  tname, model=tier_models[tid], learn=learn)
        for sid, sname, pattern, discount, sdesc in SLAB_SHAPES:
            scaled = [(k, v * discount * 0.6) for k, v in cost]
            piece(f"{tid}_{sid}", f"{tname} {sname}", f"{tname}: {sdesc}", [list(c) for c in pattern], slab, scaled,
                  station, stier, tname, model=tier_models[tid], learn=learn)
        # Merdiven (2 genis) ve arac rampasi (3 genis): 0,5 m basamak
        for sid, sname, width, sdesc in [("stairs", "merdiven", 2, "0,5 m basamaklar: yürüyerek bir kat çıkılır."),
                                         ("ramp", "araç rampası", 3, "3 geniş, 0,5 m basamaklı: araç ve yaya çıkar.")]:
            cells = [[c[0], c[1], c[2], slab if c[3] == "S" else mat] for c in _stairs(width)]
            scaled = [(k, v * 0.8) for k, v in cost]
            piece(f"{tid}_{sid}", f"{tname} {sname}", f"{tname}: {sdesc}", cells, mat, scaled, station, stier, tname,
                  cat="cati", model="iz2_stair_straight_concrete" if tid in ("concrete", "rconcrete", "brick", "stone")
                  else ("iz2_stair_straight_steel" if tid in ("steel", "scrap") else "iz2_stair_straight_wood"), learn=learn)
        # Yukseltme: B kipinde "Yukselt" bu kiti harcar
        if up:
            kit_name, kit_inputs, kst, ktier = UPGRADE_KITS[tid]
            kit_id = f"upgrade_{tid}_{up}"
            R.item(F, kit_id, kit_name, "material", 2, 1.5, 12, ["upgrade_kit"],
                   f"İnşa kipinde (B) \"Yükselt\": bakılan {tname.lower()} bloğunu {tier_names[up].lower()} yapar ({hp} → "
                   f"{[t[2] for t in TIERS if t[0] == up][0]} HP).", stack=20, model=R.model("toolbox"), quality=False)
            R.recipe(FAM, "r_" + kit_id, kit_name, kit_id, 1, kit_inputs, kst, ktier, 6, "yukseltme", tname,
                     f"{tname} → {tier_names[up]} yükseltmesi için bir blokluk kit.", learn=learn)
            R.upgrades[mat] = {"to": tier_mat[up], "cost": [{"item": kit_id, "count": 1}],
                               "repair": [_need(k, max(1, v // 2 if v > 1 else 1)) for k, v in cost[:1]],
                               "salvage": [{"item": k, "count": v} for k, v in salvage]}
            R.upgrades[slab] = {"to": "", "cost": [], "repair": [_need(k, 1) for k, v in cost[:1]],
                                "salvage": [{"item": salvage[0][0], "count": 1}]}
        else:
            R.upgrades[mat] = {"to": "", "cost": [], "repair": [_need(k, 1) for k, v in cost[:1]],
                               "salvage": [{"item": k, "count": v} for k, v in salvage]}
            R.upgrades[slab] = {"to": "", "cost": [], "repair": [_need(k, 1) for k, v in cost[:1]],
                                "salvage": [{"item": salvage[0][0], "count": 1}]}

    # --- cam, parmaklik, tel orgu ---
    for mid, mname, cost, station, stier, model in [
        ("pb_glass_reinforced", "Takviyeli cam", [("glass_pane", 1), ("mesh_wire", 0.5)], "forge", 2, "iz2_partition_glass"),
        ("pb_bars", "Demir parmaklık", [("iron_bar", 2)], "forge", 1, "prison/bars_01"),
        ("pb_mesh", "Tel örgü", [("mesh_wire", 1)], "workbench", 1, "iz2_defense_wire_fence"),
    ]:
        short = mid[3:]
        for sid, sname, pattern, discount in [("block", "blok", [[0, 0, 0]], 1.0), ("wall2", "duvar 2×2", _box(2, 2, 1, 0), 0.95),
                                              ("wall3", "duvar 3×3", _box(3, 3, 1), 0.9)]:
            piece(f"{short}_{sid}", f"{mname} {sname}", f"{mname}: görüş açık; " +
                  {"pb_glass_reinforced": "mermiye ve zombiye dayanıklı cam.",
                   "pb_bars": "mermi aradan geçer, zombi geçemez.",
                   "pb_mesh": "ucuz çit; ok ve mermi geçer, zombi geçemez."}[mid],
                  pattern, mid, [(k, v * discount) for k, v in cost], station, stier, mname, model=model)
        R.upgrades[mid] = {"to": "", "cost": [], "repair": [_need(cost[0][0], 1)],
                           "salvage": [{"item": {"pb_glass_reinforced": "glass_shard", "pb_bars": "iron_bar",
                                                 "pb_mesh": "wire_steel"}[mid], "count": 1}]}

    # --- kapilar, kapaklar, garaj ---
    doors = [
        ("door_wood", "Ahşap kapı", [[0, 0, 0], [0, 1, 0]], "pb_door_wood", [("wood_plank", 3), ("hinge", 0.5), ("#fastener", 2)],
         "carpentry", 1, "Hafif kapı: çabuk kırılır.", "neighborhood/kapı_ahşap"),
        ("door_reinforced", "Takviyeli ahşap kapı", [[0, 0, 0], [0, 1, 0]], "pb_door_reinforced",
         [("plywood", 1), ("metal_bracket", 1), ("hinge_heavy", 0.5)], "carpentry", 2, "Köşebentli kapı.", "neighborhood/kapı_dar"),
        ("door_metal", "Sac kapı", [[0, 0, 0], [0, 1, 0]], "pb_door_metal", [("metal_plate", 2), ("hinge_heavy", 0.5), ("rivets", 3)],
         "forge", 2, "Sac kaplı kapı.", "door_entrance_metal"),
        ("door_steel", "Çelik kapı", [[0, 0, 0], [0, 1, 0]], "pb_door_steel", [("steel_sheet", 2), ("hinge_heavy", 1), ("rivets", 4)],
         "forge", 3, "Ağır çelik kapı: sürüye uzun dayanır.", "door_entrance_metal"),
        ("gate_wood", "Ahşap avlu kapısı", _box(2, 2, 1, 0), "pb_door_wood", [("wood_plank", 2), ("hinge", 0.5), ("#fastener", 2)],
         "carpentry", 1, "2×2 çift kanat: el arabası ve kalabalık geçer.", "military/gate_01"),
        ("gate_steel", "Çelik bahçe kapısı", _box(2, 2, 1, 0), "pb_door_steel", [("steel_sheet", 1.5), ("hinge_heavy", 0.5), ("rivets", 3)],
         "forge", 3, "2×2 çelik kapı.", "military/gate_02"),
        ("garage_door", "Çelik garaj kapısı", _box(3, 3, 1), "pb_door_steel", [("steel_sheet", 1.2), ("hinge_heavy", 0.3), ("rivets", 3)],
         "forge", 3, "3×3: araç girer, kapanınca kale.", "rolling_shutter"),
        ("hatch_wood", "Ahşap kapak", [[0, 0, 0]], "pb_door_wood", [("wood_plank", 3), ("hinge", 1)], "carpentry", 1,
         "Döşemeye takılan kapak: çatı ve bodrum girişi.", "iz2_roof_hatch"),
        ("hatch_steel", "Çelik kapak", [[0, 0, 0]], "pb_door_steel", [("steel_sheet", 1), ("hinge_heavy", 1)], "forge", 3,
         "Çelik döşeme kapağı.", "iz2_roof_hatch"),
        ("shutter_steel", "Çelik kepenk", [[0, 0, 0]], "pb_door_steel", [("steel_sheet", 1), ("hinge_heavy", 1)], "forge", 2,
         "Pencereye takılan açılır kepenk.", "iz2_defense_shutter_reinforced"),
    ]
    for pid, name, cells, mat, cost, station, stier, desc, model in doors:
        piece(pid, name, desc + " E ile açılıp kapanır.", cells, mat, cost, station, stier, "Kapı", cat="kapi", door=True,
              model=model)
    for mid, salvage in [("pb_door_wood", "wood_plank"), ("pb_door_reinforced", "wood_plank"), ("pb_door_metal", "metal_plate"),
                         ("pb_door_steel", "scrap_metal")]:
        R.upgrades[mid] = {"to": "", "cost": [], "repair": [_need(salvage, 1)], "salvage": [{"item": salvage, "count": 1}]}

    # --- catilar ---
    for mid, mname, cost, station, stier, model in [
        ("pb_roof_tile", "Kiremit çatı", [("roof_tile_item", 3), ("wood_plank", 1)], "masonry", 1, "iz2_roof_tile_slope"),
        ("pb_roof_sheet", "Sac çatı", [("sheet_aluminum", 2), ("#fastener", 2)], "workbench", 1, "iz2_roof_flat_parapet"),
        ("pb_roof_shingle", "Ahşap kiremit çatı", [("wood_shingle", 4), ("nail", 2)], "carpentry", 1, "iz2_roof_hip_corner"),
    ]:
        for sid, sname, pattern in [("roof2", "2×2", _floor(2, 2)), ("roof3", "3×3", _floor(3, 3))]:
            piece(f"{mid[3:]}_{sid}", f"{mname} {sname}", f"{mname}: yağmuru keser, yukarıdan geleni durdurur.", pattern, mid,
                  cost, station, stier, "Çatı", cat="cati", model=model)
        R.upgrades[mid] = {"to": "", "cost": [], "repair": [_need(cost[0][0], 1)],
                           "salvage": [{"item": cost[0][0] if not cost[0][0].startswith("#") else "scrap_metal", "count": 1}]}

    # --- tirmanma merdivenleri ---
    for pid, name, mat, n, cost, station, stier in [
        ("ladder_wood3", "Ahşap merdiven (3 m)", "pb_ladder_wood", 3, [("wood_plank", 1), ("nail", 2)], "carpentry", 1),
        ("ladder_wood5", "Ahşap merdiven (5 m)", "pb_ladder_wood", 5, [("wood_plank", 1), ("nail", 2)], "carpentry", 1),
        ("ladder_steel3", "Çelik merdiven (3 m)", "pb_ladder_steel", 3, [("iron_bar", 1), ("rivets", 2)], "forge", 2),
        ("ladder_steel5", "Çelik merdiven (5 m)", "pb_ladder_steel", 5, [("iron_bar", 1), ("rivets", 2)], "forge", 2),
    ]:
        piece(pid, name, "Dikey tırmanma merdiveni: çatıya ya da kuleye.", [[0, y, 0] for y in range(n)], mat, cost,
              station, stier, "Merdiven", cat="cati", model="iz2_ladder_roof")
    R.upgrades["pb_ladder_wood"] = {"to": "", "cost": [], "repair": [_need("wood_plank", 1)],
                                    "salvage": [{"item": "wood_plank", "count": 1}]}
    R.upgrades["pb_ladder_steel"] = {"to": "", "cost": [], "repair": [_need("iron_bar", 1)],
                                     "salvage": [{"item": "scrap_metal", "count": 1}]}

    # --- ozel yapilar ---
    platform = [[x, 3, z] for x in range(-1, 2) for z in range(0, 3)]
    platform += [[-1, y, 0] for y in range(3)] + [[1, y, 0] for y in range(3)] + [[-1, y, 2] for y in range(3)] + [[1, y, 2] for y in range(3)]
    piece("watch_platform", "Gözetleme platformu", "Dört kolonlu 3×3 yüksek platform: kuşatmada ateş noktası.", platform,
          "pb_woodr", [("wood_plank", 1.4), ("metal_bracket", 0.4), ("#fastener", 1)], "carpentry", 2, "Özel", model="military/watchtower_01")
    piece("plank_bridge", "Kalas köprü (4 m)", "4 m kalas geçit: iki çatı arası köprü.", [[0, 0, z] for z in range(4)], "pb_wood",
          [("wood_plank", 2), ("nail", 1)], "carpentry", 1, "Özel", model="pallet")
    arch = [c for c in _box(3, 3, 1) if not (c[0] == 0 and c[1] < 2)]
    for tid in ("brick", "stone"):
        cost, station, stier, *_ = TIER_COST[tid]
        piece(f"{tid}_arch", f"{tier_names[tid]} kemer", "Tarihî kemerli geçit: kapı boşluğu gibi, daha sağlam taç.",
              arch, tier_mat[tid], [(k, v * 1.0) for k, v in cost], station, stier + 1, tier_names[tid],
              model="neighborhood/kemer_taş")
    piece("railing_steel", "Çelik korkuluk 3 m", "Çatı ve platform kenarı: düşmeyi önler, mermi geçer.",
          [[x, 0, 0, "pb_bars"] for x in range(-1, 2)], "pb_bars", [("iron_bar", 1)], "forge", 1, "Özel", model="coastal_railing")


def _need(key, count):
    if key.startswith("#"):
        return {"tag": key[1:], "count": count}
    return {"item": key, "count": count}
