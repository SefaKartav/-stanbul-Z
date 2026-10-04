"""Saglik ve hayatta kalma ailesi: ilaclar, tibbi sarf, koruyucu ekipman."""
from lib import Registry, I, T

F = "items/gen_health.json"
FAM = "health"


def build(R: Registry) -> None:
    R.category("tibbi", "Tıbbi")
    R.category("zirh", "Zırh ve koruyucu")
    R.category("giyim", "Giyim")
    R.tag("gauze", "gazlı bez")

    def med(iid, name, tier, value, effects, desc, model, inputs, station, stier, count=1, learn="", nutrition=None, stack=10):
        R.item(F, iid, name, "consumable", tier, 0.1, value, ["medical", "healing"], desc, stack=stack, model=R.model(model),
               effects=effects)
        if nutrition:
            R.nutrition[iid] = nutrition
        R.recipe(FAM, "r_" + iid, name, iid, count, inputs, station, stier, 6 + tier * 3, "tibbi", "İlaç", desc, learn=learn)

    R.item(F, "gauze", "Gazlı Bez", "component", 1, 0.02, 4, ["gauze", "medical", "sterile", "soft"],
           "Steril gazlı bez: sargı ve pansuman tabanı.", stack=40, model=R.model("bandage"))
    R.recipe(FAM, "r_gauze", "Gazlı bez", "gauze", 4, [I("cloth_rag", 2), T("antiseptic_base", 1)], "workbench", 1, 6, "tibbi",
             "Sarf", "Bez kaynatılıp dezenfekte edilir.")
    R.recipe(FAM, "r_bandage_boil", "Sargı kaynatma", "bandage_clean", 2, [I("bandage_dirty", 2), I("water_bottle", 1), T("cook_fuel", 1)],
             "cooking", 1, 8, "tibbi", "Sarf", "Kirli sargı kaynatılıp yeniden kullanılır.")
    R.recipe(FAM, "r_painkiller_herbal", "Bitkisel ağrı kesici", "painkiller", 2, [I("herbs", 2), T("solvent", 1), T("tool_mortar", 1, tool=True)],
             "chemistry", 2, 10, "tibbi", "İlaç", "Söğüt kabuğu ve ot: hafif ağrı kesici.")

    meds = [
        ("herbal_poultice", "Bitkisel Lapa", 1, 20, {"heal": 10, "regen": 0.4, "duration": 40}, "Şifalı ot lapası: yavaş iyileşme.",
         "bandage", [I("herbs", 2), I("plant_fiber", 1)], "hands", 1, 2),
        ("splint", "Atel", 1, 30, {"cure_fracture": 1, "heal": 5}, "Kırığı sabitler: hızın geri gelir.",
         "bandage", [I("wood_plank", 1), I("twine", 2), I("gauze", 1)], "hands", 1, 1),
        ("tourniquet", "Turnike", 1, 25, {"cure_bleed": 1}, "Kanamayı anında keser.",
         "iz2_item_tourniquet", [I("leather_strap", 1), I("gauze", 1)], "hands", 1, 2),
        ("burn_salve", "Yanık Merhemi", 2, 40, {"cure_burn": 1, "heal": 8}, "Yanığı söndürür, cildi kapatır.",
         "medicine", [I("herbs", 1), I("cooking_oil", 1), T("antiseptic_base", 1)], "chemistry", 1, 2),
        ("antibiotics", "Antibiyotik", 4, 200, {"cure_infection": 1, "heal": 10}, "Isırık enfeksiyonunu temizler (panzehirin alternatifi).",
         "medicine", [I("antiseptic", 2), I("syringe", 1), I("herbs", 3), I("ethanol", 1)], "chemistry", 3, 1, "level:12"),
        ("suture_kit", "Dikiş Kiti", 3, 120, {"heal": 35, "cure_bleed": 1}, "Açık yarayı kapatır.",
         "iz2_item_suture_kit", [I("gauze", 2), I("antiseptic", 1), T("tool_surgery", 1, tool=True)], "workbench", 2, 2),
        ("field_dressing", "Sahra Pansumanı", 3, 110, {"heal": 30, "cure_bleed": 1, "cure_infection": 1},
         "Temizler, kapatır, enfeksiyonu önler.", "bandage", [I("gauze", 2), I("antiseptic", 1), I("sterile_cloth", 1)], "workbench", 2, 1),
        ("iv_drip", "Serum Seti", 3, 160, {"regen": 1.2, "duration": 60}, "Bir dakika boyunca güçlü iyileşme.",
         "iv_stand", [I("saline_bag", 1), I("syringe", 1), I("pvc_pipe", 1)], "workbench", 2, 1),
        ("vitamin_pack", "Vitamin Tableti", 2, 50, {"regen": 0.3, "duration": 120}, "Uzun süreli hafif iyileşme.",
         "medicine", [I("dried_fruit", 2), I("herbs", 1)], "chemistry", 1, 3),
        ("energy_drink", "Enerji İçeceği", 2, 40, {"stamina": 50, "speed_boost": 0.15, "duration": 12}, "Şeker ve kafein: hızlı kaç.",
         "water_bottle", [I("sugar_pack", 1), I("coffee_beans", 1), I("water_bottle", 1)], "chemistry", 1, 2, "",
         {"water": 10}),
        ("adrenaline_shot", "Adrenalin İğnesi", 4, 180, {"speed_boost": 0.4, "heal": 10, "duration": 20}, "20 sn hız: acil kaçış.",
         "medicine", [I("stimulant", 1), I("syringe", 1)], "chemistry", 3, 1),
        ("morphine", "Morfin", 4, 240, {"heal": 45, "fortify": 0.3, "duration": 45}, "Ağrıyı keser: 45 sn %30 hasar direnci.",
         "medicine", [I("painkiller", 3), I("syringe", 1), I("ethanol", 1)], "chemistry", 4, 1, "skill:md_pharma"),
        ("charcoal_tabs", "Aktif Kömür", 1, 20, {"cure_sick": 1}, "Mide bulantısını geçirir.",
         "iz2_item_purification_tabs", [I("charcoal", 2), I("flour_sack", 1)], "chemistry", 1, 4),
        ("ors_solution", "Tuz-Şeker Çözeltisi", 1, 15, {"cure_sick": 1}, "Sıvı kaybını durdurur, susuzluğu giderir.",
         "water_bottle", [I("salt_pack", 1), I("sugar_pack", 1), I("water_bottle", 1)], "hands", 1, 2, "", {"water": 25}),
        ("focus_tonic", "Odak Toniği", 2, 60, {"focus": 0.3, "duration": 90}, "Nişan titremesini azaltır.",
         "iz2_item_thermos", [I("coffee_beans", 1), I("herbs", 2), I("sugar_pack", 1)], "chemistry", 2, 2),
        ("resist_syrup", "Direnç Şurubu", 2, 60, {"fortify": 0.15, "regen": 0.2, "duration": 90}, "Ot ve bal: 90 sn dayanıklılık.",
         "iz2_item_thermos", [I("herbs", 3), I("sugar_pack", 1), I("ethanol", 1)], "chemistry", 2, 2),
        ("first_aid_small", "Küçük Ecza Çantası", 2, 90, {"heal": 40, "cure_bleed": 1}, "Sargı ve antiseptik: yolda can kurtarır.",
         "first_aid_wall_box", [I("bandage_clean", 2), I("gauze", 1), I("antiseptic", 1)], "workbench", 1, 1),
        ("medkit_military", "Askerî İlk Yardım", 5, 400, {"heal": 80, "cure_bleed": 1, "cure_fracture": 1}, "Tam tedavi: kan, kırık, can.",
         "medkit", [I("medkit", 1), I("tourniquet", 1), I("morphine", 1)], "workbench", 3, 1, "skill:md_pharma"),
        ("wound_kit", "Yara Bakım Seti", 3, 140, {"heal": 30, "cure_infection": 1, "cure_bleed": 1}, "Temizle, kapat, koru.",
         "iz2_item_hygiene_kit", [I("soap", 1), I("gauze", 2), I("antiseptic", 1)], "workbench", 2, 1),
    ]
    for (iid, name, tier, value, effects, desc, model, inputs, station, stier, count, *rest) in meds:
        learn = rest[0] if rest else ""
        nut = rest[1] if len(rest) > 1 else None
        med(iid, name, tier, value, effects, desc, model, inputs, station, stier, count, learn, nut)

    # --- koruyucu ekipman ---
    gear = [
        # kimlik, ad, yuva, kademe, agirlik, etkiler, dayanik, aciklama, model, girdiler, istasyon, kademe
        ("leather_jacket", "Deri Ceket", "armor", 1, 2.0, {"armor": 2}, 160, "Isırığa karşı ilk kat.",
         "iz2_armor_knee_pads", [I("cured_leather", 3), I("leather_strap", 2), T("tool_sewing", 1, tool=True)], "workbench", 1),
        ("padded_vest", "Dolgulu Yelek", "armor", 2, 3.0, {"armor": 3}, 200, "Sünger ve branda.",
         "iz2_armor_plate_carrier", [I("padding_pad", 3), I("canvas_sheet", 1), T("tool_sewing", 1, tool=True)], "workbench", 1),
        ("riot_vest", "Çevik Kuvvet Yeleği", "armor", 3, 5.0, {"armor": 6}, 280, "Kalkan parçalarıyla sert kabuk.",
         "iz2_armor_plate_carrier", [I("riot_scrap", 3), I("padding_pad", 2), I("leather_strap", 3)], "workbench", 2),
        ("plate_carrier_heavy", "Ağır Plaka Taşıyıcı", "armor", 5, 11.0, {"armor": 12}, 400, "Çelik plaka + kevlar: ağır ama kale.",
         "iz2_armor_plate_carrier", [I("armor_plate_steel", 2), I("kevlar_panel", 2), I("leather_strap", 4)], "workbench", 3),
        ("scrap_helmet", "Hurda Kask", "helmet", 1, 1.2, {"armor": 1.5}, 150, "Tencere ve perçin.",
         "iz2_armor_helmet_tactical", [I("metal_plate", 1), I("rivets", 4), I("padding_pad", 1)], "workbench", 1),
        ("moto_helmet", "Motosiklet Kaskı", "helmet", 2, 1.4, {"armor": 2}, 180, "Isırığa dayanıklı kabuk.",
         "iz2_armor_helmet_tactical", [I("plastic_sheet", 3), I("padding_pad", 1), T("adhesive", 1)], "workbench", 1),
        ("riot_helmet", "Çevik Kuvvet Kaskı", "helmet", 3, 1.8, {"armor": 3}, 240, "Vizörlü kask.",
         "iz2_armor_helmet_tactical", [I("riot_scrap", 2), I("glass_pane", 1), I("padding_pad", 1)], "workbench", 2),
        ("military_helmet", "Askerî Kask", "helmet", 4, 1.6, {"armor": 4.5}, 320, "Kevlar kask.",
         "iz2_armor_helmet_tactical", [I("kevlar_panel", 1), I("padding_pad", 1), I("leather_strap", 1)], "workbench", 3),
        ("cloth_mask", "Bez Maske", "mask", 1, 0.1, {"toxin_resist": 0.2}, 80, "Toz ve spreye karşı biraz korur.",
         "iz2_gear_gas_mask", [I("cloth_rag", 2), I("charcoal", 1)], "hands", 1),
        ("respirator", "Solunum Maskesi", "mask", 2, 0.5, {"toxin_resist": 0.5}, 160, "Filtreli yarım maske.",
         "iz2_item_respirator_filter", [I("filter_housing", 1), I("rubber_sheet", 1), I("charcoal", 2)], "workbench", 2),
        ("hazmat_mask", "Tam Yüz Koruyucu", "mask", 4, 1.4, {"toxin_resist": 0.9, "armor": 0.5}, 260, "Tükürükçü asidine karşı neredeyse tam koruma.",
         "iz2_gear_gas_mask", [I("gas_mask", 1), I("filter_cartridge", 1), I("glass_pane", 1)], "workbench", 3),
        ("work_clothes", "İş Tulumu", "clothing", 1, 1.5, {"capacity": 6, "armor": 0.5}, 200, "Bol cepli tulum: +6 kg.",
         "cloth_roll", [I("cloth_bolt", 2), I("leather_strap", 1), T("tool_sewing", 1, tool=True)], "workbench", 1),
        ("field_uniform", "Arazi Üniforması", "clothing", 3, 2.0, {"capacity": 8, "stamina_bonus": 10}, 260, "+8 kg, +10 nefes.",
         "cloth_roll", [I("canvas_sheet", 2), I("padding_pad", 1), I("leather_strap", 2)], "workbench", 2),
        ("stealth_cloak", "Sessiz Pelerin", "clothing", 3, 1.2, {"noise_bonus": 0.35}, 200, "Ayak sesini %35 boğar.",
         "cloth_roll", [I("cloth_bolt", 2), I("padding_pad", 2), I("plant_fiber", 6)], "workbench", 2),
    ]
    for (iid, name, slot, tier, weight, effects, dur, desc, model, inputs, station, stier) in gear:
        R.item(F, iid, name, "tool", tier, weight, 60 * tier, ["wearable", "armor" if "armor" in effects else "gear"],
               desc + " Envanterde Kuşan.", stack=1, model=R.model(model), effects=effects, durability=dur, slot=slot)
        R.recipe(FAM, "r_" + iid, name, iid, 1, inputs, station, stier, 10 + tier * 4, "zirh" if slot in ("armor", "helmet", "mask") else "giyim",
                 {"armor": "Gövde", "helmet": "Kask", "mask": "Maske", "clothing": "Giysi"}[slot], desc)
