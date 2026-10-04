"""Arac gerec ve bakim ailesi: uretim takimlari, toplama aletleri, onarim kitleri."""
from lib import Registry, I, T

F = "items/gen_tools.json"
FAM = "tools"


def melee_weapon(R: Registry, wid: str, name: str, damage: float, rate: float, reach: float, cone: float,
                 noise: float, knockback: float, pierce: int = 0) -> str:
    R.weapons[wid] = {"name": name, "category": "melee", "damage": damage, "damage_type": "physical",
                      "fire_rate": rate, "pellets": 1, "spread": cone, "projectile_speed": 0, "range": reach,
                      "magazine": 1, "reload_time": 0.0, "ammo_type": "", "noise_radius": noise, "recoil": 0.0,
                      "shake": 0.15, "automatic": True, "knockback": knockback, "pierce": pierce, "muzzle_offset": 8}
    R.weapon_views[wid] = ""
    return wid


def build(R: Registry) -> None:
    R.category("alet", "Aletler")
    R.category("toplama", "Toplama aletleri")
    R.category("bakim", "Bakım ve onarım")
    for tag, name in [("tool_hammer", "çekiç"), ("tool_saw", "el testeresi"), ("tool_hacksaw", "demir testeresi"),
                      ("tool_drill", "matkap"), ("tool_welder", "kaynak makinesi"), ("tool_multimeter", "multimetre"),
                      ("tool_sewing", "dikiş seti"), ("tool_chisel", "keski"), ("tool_trowel", "mala"),
                      ("tool_pliers", "pense"), ("tool_file", "eğe"), ("tool_fire", "çakmak / çakmaktaşı"),
                      ("tool_pot", "tencere"), ("tool_mortar", "havan"), ("tool_surgery", "cerrahi set"),
                      ("tool_solder", "havya")]:
        R.tag(tag, name)

    def tool(item_id, name, tier, weight, value, tags, desc, durability, model, effects=None, weapon_id="", **kw):
        return R.item(F, item_id, name, "tool", tier, weight, value, tags, desc, stack=1, model=R.model(model),
                      durability=durability, effects=effects or {}, weapon_id=weapon_id, **kw)

    def rec(rid, name, out, count, inputs, station, tier, time, cat, sub, desc, **kw):
        return R.recipe(FAM, rid, name, out, count, inputs, station, tier, time, cat, sub, desc, **kw)

    # ------------------------------------------------ uretim takimlari (tuketilmez girdi)
    craft_tools = [
        ("claw_hammer", "Çekiç", 1, 0.8, 30, ["tool_hammer", "crafting_tool", "tool"], "Çivi çakar, söker. İnşa ve tamir takımı.",
         400, "handheld/cekic", "r_claw_hammer", [I("iron_bar", 1), I("tool_handle", 1)], "workbench", 1),
        ("hand_saw", "El Testeresi", 1, 0.7, 30, ["tool_saw", "crafting_tool", "tool"], "Kütük ve kalas keser.",
         300, "handheld/el_testeresi", "r_hand_saw", [I("blade_blank", 1), I("tool_handle", 1)], "workbench", 1),
        ("hacksaw", "Demir Testeresi", 2, 0.6, 35, ["tool_hacksaw", "crafting_tool", "tool"], "Boru ve demir keser.",
         300, "handheld/el_testeresi", "r_hacksaw", [I("blade_blank", 1), I("iron_bar", 1)], "workbench", 2),
        ("hand_drill", "El Matkabı", 2, 1.2, 40, ["tool_drill", "crafting_tool", "tool"], "Kranklı matkap: delik, vida yuvası.",
         350, "handheld/el_matkabi", "r_hand_drill", [I("gear_small", 2), I("iron_bar", 1), I("tool_handle", 1)], "mechanic", 1),
        ("power_drill", "Akülü Matkap", 3, 1.6, 120, ["tool_drill", "crafting_tool", "tool"], "Hızlı delme; akü şarjlı.",
         700, "handheld/el_matkabi", "r_power_drill", [I("motor_small", 1), I("battery_pack", 1), I("gear_small", 2)], "electronics", 2),
        ("welder", "Kaynak Makinesi", 3, 6.0, 180, ["tool_welder", "crafting_tool", "tool"],
         "Çelik birleştirir; araç revizyonu ve çelik yapı için şart.",
         600, "welder_cart", "r_welder", [I("transformer_coil", 1), I("insulated_wire", 3), I("metal_plate", 2)], "electronics", 3),
        ("multimeter", "Multimetre", 2, 0.3, 60, ["tool_multimeter", "crafting_tool", "tool"],
         "Devre ölçer: sensör, röle ve güç devresi kurarken.",
         400, "handheld/tornavida", "r_multimeter", [I("circuit_basic", 1), I("battery_aa", 1), I("plastic_sheet", 1)], "electronics", 1),
        ("sewing_kit", "Dikiş Seti", 1, 0.2, 18, ["tool_sewing", "crafting_tool", "tool"], "İğne, sicim, makas.",
         200, "sewing_machine", "r_sewing_kit", [I("twine", 2), T("sharp", 1), I("cloth_rag", 1)], "hands", 1),
        ("chisel_set", "Keski Takımı", 1, 0.9, 25, ["tool_chisel", "crafting_tool", "tool"], "Taş ve ahşap oyar.",
         400, "handheld/tornavida", "r_chisel_set", [I("iron_bar", 2), I("tool_handle", 1)], "forge", 1),
        ("trowel", "Mala", 1, 0.5, 15, ["tool_trowel", "crafting_tool", "tool"], "Harç sürer: tuğla ve taş duvar.",
         400, "handheld/kurek", "r_trowel", [I("metal_plate", 1), I("tool_handle", 1)], "forge", 1),
        ("pliers", "Pense", 2, 0.3, 20, ["tool_pliers", "crafting_tool", "tool"], "Tel büker, keser.",
         400, "handheld/pense", "r_pliers", [I("iron_bar", 1), I("spring", 1)], "forge", 2),
        ("file_set", "Eğe Takımı", 2, 0.5, 25, ["tool_file", "crafting_tool", "tool"], "Silah ve mekanik parça tesviyesi.",
         500, "handheld/tornavida", "r_file_set", [I("steel_ingot", 1)], "forge", 2),
        ("lighter", "Benzinli Çakmak", 1, 0.1, 15, ["tool_fire", "crafting_tool", "tool"], "Ateş yakar: sahada pişirme ve sterilizasyon.",
         120, "handheld/el_feneri", "r_lighter", [I("metal_plate", 1), T("chemical_fuel", 1), I("cloth_rag", 1)], "workbench", 1),
        ("fire_striker", "Çakmaktaşı", 1, 0.2, 6, ["tool_fire", "crafting_tool", "tool"], "Yakıtsız ateş: yavaş ama bitmez.",
         400, "rubble_pile", "r_fire_striker", [I("stone_chunk", 1), I("iron_bar", 1)], "hands", 1),
        ("cooking_pot", "Tencere", 1, 1.2, 20, ["tool_pot", "crafting_tool", "tool"], "Kaynatma ve pişirme kabı.",
         600, "cooking_pot", "r_cooking_pot", [I("metal_plate", 2)], "forge", 1),
        ("mortar_pestle", "Havan", 1, 1.5, 12, ["tool_mortar", "crafting_tool", "tool"], "Ot ve ilaç döver.",
         600, "bowl", "r_mortar_pestle", [I("stone_chunk", 2)], "masonry", 1),
        ("surgical_kit", "Cerrahi Set", 3, 0.8, 140, ["tool_surgery", "crafting_tool", "tool", "medical"],
         "Neşter, pens, dikiş: ileri tıbbi üretim.",
         250, "medical_trolley", "r_surgical_kit", [I("blade_blank", 1), I("syringe", 2), I("antiseptic", 1), I("pliers", 1)], "workbench", 3),
    ]
    for (iid, name, tier, weight, value, tags, desc, dur, model, rid, inputs, station, stier) in craft_tools:
        tool(iid, name, tier, weight, value, tags, desc, dur, model)
        rec(rid, name, iid, 1, inputs, station, stier, 8 + tier * 4, "alet", "Üretim takımı",
            desc + " Üretimde tüketilmez (takım).")

    # ------------------------------------------------ toplama aletleri (yakin dovus + harvest_*)
    harvest = [
        # kimlik, ad, kademe, agirlik, deger, etkiler, dayanik, hasar, hiz, menzil, koni, gurultu, model, tarif, girdiler, istasyon, kademe
        ("stone_axe", "Taş Balta", 1, 1.6, 12, {"harvest_wood": 1.0, "harvest_plant": 1.0, "stamina_cost": 8.0},
         150, 20, 1.1, 50, 40, 120, "handheld/balta",
         [I("stone_chunk", 2), I("tool_handle", 1), I("twine", 2)], "hands", 1),
        ("iron_hatchet", "Demir Nacak", 2, 1.4, 35, {"harvest_wood": 1.8, "harvest_plant": 1.2, "stamina_cost": 7.0},
         350, 30, 1.4, 50, 40, 130, "handheld/balta", [I("iron_bar", 1), I("tool_handle", 1)], "forge", 1),
        ("steel_axe", "Çelik Balta", 3, 2.2, 90, {"harvest_wood": 2.8, "harvest_plant": 1.4, "stamina_cost": 7.0},
         700, 44, 1.3, 56, 45, 140, "handheld/balta", [I("blade_blank", 1), I("steel_ingot", 1), I("tool_handle", 1)], "forge", 3),
        ("chainsaw", "Motorlu Testere", 4, 5.5, 260, {"harvest_wood": 5.0, "harvest_plant": 3.0, "stamina_cost": 3.0},
         600, 38, 6.0, 46, 25, 520, "handheld/el_testeresi",
         [I("motor_small", 1), I("chain", 1), I("blade_blank", 1), T("chemical_fuel", 2)], "mechanic", 3),
        ("stone_pickaxe", "Taş Kazma", 1, 2.0, 12, {"harvest_stone": 0.8, "harvest_soil": 0.6, "stamina_cost": 9.0},
         150, 18, 0.9, 50, 30, 150, "handheld/kazma", [I("stone_chunk", 2), I("tool_handle", 1), I("twine", 2)], "hands", 1),
        ("iron_pickaxe", "Demir Kazma", 2, 2.6, 40, {"harvest_stone": 1.8, "harvest_soil": 1.0, "stamina_cost": 8.0},
         400, 28, 1.0, 54, 30, 170, "handheld/kazma", [I("iron_bar", 2), I("tool_handle", 1)], "forge", 1),
        ("steel_pickaxe", "Çelik Kazma", 3, 3.0, 95, {"harvest_stone": 3.0, "harvest_soil": 1.4, "stamina_cost": 8.0},
         800, 40, 1.0, 56, 30, 180, "handheld/kazma", [I("steel_ingot", 1), I("blade_blank", 1), I("tool_handle", 1)], "forge", 3),
        ("jackhammer", "Kırıcı", 4, 9.0, 300, {"harvest_stone": 6.0, "harvest_soil": 3.0, "stamina_cost": 3.0},
         700, 30, 5.0, 40, 20, 620, "handheld/el_matkabi",
         [I("motor_large", 1), I("piston", 1), I("steel_ingot", 1), I("battery_pack", 1)], "mechanic", 3),
        ("wooden_shovel", "Tahta Kürek", 1, 1.5, 8, {"harvest_soil": 1.2, "stamina_cost": 6.0},
         180, 12, 1.2, 52, 35, 100, "handheld/kurek", [I("wood_plank", 2), I("nail", 2)], "carpentry", 1),
        ("steel_shovel", "Çelik Kürek", 2, 2.0, 35, {"harvest_soil": 2.4, "harvest_plant": 0.6, "stamina_cost": 6.0},
         600, 22, 1.2, 54, 35, 110, "handheld/kurek", [I("steel_sheet", 1), I("tool_handle", 1)], "forge", 2),
        ("crowbar", "Levye", 1, 1.8, 20, {"harvest_metal": 1.2, "harvest_vehicle": 0.6, "harvest_glass": 0.6, "stamina_cost": 7.0},
         600, 26, 1.6, 54, 40, 140, "handheld/levye", [I("iron_bar", 2)], "forge", 1),
        ("wrench_set", "Anahtar Takımı", 2, 2.0, 45, {"harvest_metal": 1.0, "harvest_vehicle": 1.0, "stamina_cost": 5.0},
         500, 16, 1.8, 46, 30, 90, "handheld/boru_anahtari", [I("iron_bar", 2), T("fastener", 4)], "mechanic", 1),
        ("impact_wrench", "Havalı Anahtar", 3, 2.4, 140, {"harvest_vehicle": 1.6, "harvest_metal": 1.4, "stamina_cost": 3.0},
         600, 14, 3.0, 44, 25, 300, "handheld/tamir_anahtari",
         [I("motor_small", 1), I("battery_pack", 1), I("wrench_set", 1)], "electronics", 2),
        ("angle_grinder", "Spiral Taşlama", 3, 2.6, 150, {"harvest_metal": 3.0, "harvest_stone": 1.2, "stamina_cost": 3.0},
         500, 22, 4.0, 42, 20, 420, "handheld/el_matkabi",
         [I("motor_small", 1), I("battery_pack", 1), I("sand", 3), I("metal_plate", 1)], "electronics", 3),
        ("cutting_torch", "Kesme Şalomesi", 4, 4.0, 200, {"harvest_metal": 4.5, "harvest_vehicle": 1.2, "harvest_glass": 0.5,
                                                         "stamina_cost": 2.0},
         400, 18, 3.0, 40, 15, 200, "gas_cylinder", [I("gas_canister", 1), I("valve", 1), I("pipe_fitting", 2)], "mechanic", 3),
        ("glass_cutter", "Cam Kesici", 2, 0.2, 30, {"harvest_glass": 2.0, "stamina_cost": 2.0},
         250, 6, 2.0, 40, 20, 40, "handheld/tornavida", [I("blade_blank", 1), T("hard", 1)], "workbench", 2),
        ("sickle", "Orak", 1, 0.6, 15, {"harvest_plant": 2.0, "stamina_cost": 4.0},
         300, 18, 2.0, 46, 50, 70, "handheld/balta", [I("blade_blank", 1), I("tool_handle", 1)], "forge", 1),
        ("scythe", "Tırpan", 2, 2.2, 35, {"harvest_plant": 3.2, "stamina_cost": 5.0},
         450, 30, 1.2, 64, 70, 90, "handheld/mizrak", [I("blade_blank", 2), I("wood_beam", 1)], "forge", 2),
        ("hoe", "Çapa", 1, 1.4, 14, {"harvest_soil": 1.5, "harvest_plant": 0.8, "stamina_cost": 6.0},
         350, 16, 1.3, 52, 40, 90, "handheld/kurek", [I("metal_plate", 1), I("tool_handle", 1)], "forge", 1),
    ]
    for (iid, name, tier, weight, value, effects, dur, dmg, rate, reach, cone, noise, model, inputs, station, stier) in harvest:
        wid = melee_weapon(R, "tool_" + iid, name, dmg, rate, reach, cone, noise, dmg * 3.0)
        classes = [k[8:] for k in effects if k.startswith("harvest_") and k != "harvest_yield"]
        cls_tr = {"wood": "ahşap", "stone": "taş", "metal": "metal", "soil": "toprak", "glass": "cam", "plant": "bitki",
                  "vehicle": "araç sökümü"}
        best = max(classes, key=lambda k: effects["harvest_" + k])
        desc = "Toplama aleti: %s. Yuvaya al (1-4) ve bak-vur; her vuruş nefes harcar ve ses çıkarır." % \
               ", ".join(f"{cls_tr[k]} ×{effects['harvest_' + k]:.1f}" for k in classes)
        tool(iid, name, tier, weight, value, ["harvest_tool", "tool", "weapon"], desc, dur, model, effects=effects,
             weapon_id=wid)
        rec("r_" + iid, name, iid, 1, inputs, station, stier, 8 + tier * 4, "toplama", cls_tr[best].capitalize(),
            desc)

    # Olta ve yem
    tool("fishing_rod", "Olta", 1, 0.8, 12, ["fishing_tool", "tool"],
         "Kıyıda ya da iskelede suya bakıp E: balık tutar. Yem şansı artırır.", 120, "iz2_district_fishing_rod_rack",
         effects={"fishing": 1.0})
    rec("r_fishing_rod", "Olta", "fishing_rod", 1, [I("wood_plank", 1), I("twine", 2), T("sharp", 1)], "hands", 1, 6,
        "alet", "Balıkçılık", "Kıyıda yiyecek bulmanın sessiz yolu.")
    tool("fishing_rod_pro", "Makaralı Olta", 2, 1.0, 45, ["fishing_tool", "tool"],
         "Makaralı olta: iki kat şans, daha dayanıklı.", 300, "iz2_district_fishing_rod_rack", effects={"fishing": 1.8})
    rec("r_fishing_rod_pro", "Makaralı olta", "fishing_rod_pro", 1, [I("pvc_pipe", 1), I("gear_small", 1), I("twine", 3), T("sharp", 1)],
        "workbench", 2, 10, "alet", "Balıkçılık", "Dişli makara uzun atış sağlar.")

    # ------------------------------------------------ onarim kitleri
    kits = [
        ("whetstone", "Bileği Taşı", 1, 0.5, 8, {"repair_tool": 60}, "Alet ve bıçak ağzını açar.", "rubble_pile",
         [I("stone_chunk", 1), I("sand", 1)], "masonry", 1),
        ("gun_cleaning_kit", "Silah Bakım Kiti", 1, 0.3, 25, {"repair_weapon": 80}, "Temizlik ve yağlama: silah ömrünü uzatır.",
         "iz2_weapon_cleaning_roll", [I("cloth_rag", 1), I("oil_can", 1), T("tube", 1)], "workbench", 1),
        ("gun_repair_kit", "Silah Tamir Kiti", 3, 0.6, 90, {"repair_weapon": 220}, "Yedek yay ve pim: bozuk silahı ayağa kaldırır.",
         "iz2_weapon_cleaning_roll", [I("machined_part", 1), I("spring", 2), I("gun_cleaning_kit", 1)], "gunsmith", 2),
        ("armor_patch_kit", "Zırh Yama Kiti", 1, 0.4, 20, {"repair_armor": 60}, "Yırtık yeleği yamar.",
         "cloth_roll", [T("tough_fabric", 2), T("adhesive", 1), T("tool_sewing", 1, tool=True)], "workbench", 1),
        ("armor_repair_kit", "Zırh Tamir Kiti", 3, 1.0, 80, {"repair_armor": 180}, "Kevlar ve perçinle ciddi onarım.",
         "cloth_roll", [I("kevlar_panel", 1), I("rivets", 4), I("armor_patch_kit", 1)], "workbench", 3),
        ("tool_repair_kit", "Alet Tamir Kiti", 2, 0.8, 40, {"repair_tool": 200}, "Sap, perçin, bileği taşı.",
         "toolbox", [I("iron_bar", 1), I("whetstone", 1), T("fastener", 3)], "workbench", 2),
        ("vehicle_repair_basic", "Araç Tamir Seti", 2, 3.0, 45, {"repair_vehicle": 35}, "Sac yama ve bant: araca +35 sağlamlık.",
         "toolbox", [I("metal_plate", 2), T("fastener", 4), I("duct_tape", 1)], "mechanic", 1),
        ("vehicle_repair_adv", "Araç Revizyon Seti", 3, 5.0, 120, {"repair_vehicle": 90}, "Kaynaklı plaka ve conta: araca +90.",
         "toolbox", [I("reinforced_plate", 1), I("welding_rod", 4), I("rubber_sheet", 1), T("tool_welder", 1, tool=True)], "mechanic", 3),
        ("field_patch", "Bantlı Yama", 1, 0.2, 8, {"repair_armor": 25, "repair_tool": 25}, "Sahada hızlı yama: zırh ya da alet.",
         "cloth_roll", [I("duct_tape", 2), T("fabric", 1)], "hands", 1),
        ("welding_patch", "Kaynak Yaması", 2, 2.0, 50, {"repair_vehicle": 55}, "Araç şasesine kaynak: +55 sağlamlık.",
         "toolbox", [I("welding_rod", 2), I("metal_plate", 1), T("tool_welder", 1, tool=True)], "mechanic", 2),
    ]
    for (iid, name, tier, weight, value, effects, desc, model, inputs, station, stier) in kits:
        R.item(F, iid, name, "consumable", tier, weight, value, ["repair_kit"], desc + " Envanterde Onar ile kullanılır.",
               stack=5, model=R.model(model), effects=effects)
        rec("r_" + iid, name, iid, 1, inputs, station, stier, 6 + tier * 3, "bakim", "Onarım kiti", desc)

    # Civata makasi: kilitli dolap acar (beceri gerekmez, alet asinir)
    tool("bolt_cutters", "Cıvata Makası", 2, 2.0, 60, ["lockpick_tool", "tool"],
         "Kilitli kasa ve dolabı beceri olmadan açar (her seferinde aşınır, gürültülü).", 150, "handheld/civata_kesici")
    rec("r_bolt_cutters", "Cıvata makası", "bolt_cutters", 1, [I("blade_blank", 2), I("tool_handle", 2), I("spring_heavy", 1)],
        "forge", 2, 12, "alet", "Kilit", "Uzun kollu makas: asma kilit ve zincir keser.")
