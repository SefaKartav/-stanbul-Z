"""Silah, muhimmat ve mod ailesi."""
from lib import Registry, I, T

F = "items/gen_weapons.json"
FAM = "weapons"


def weapon(R, wid, name, category, damage, rate, spread, rng, mag, reload, ammo, noise, recoil, shake, auto, knock,
           pierce=0, pellets=1, dtype="physical", view=""):
    R.weapons[wid] = {"name": name, "category": category, "damage": damage, "damage_type": dtype, "fire_rate": rate,
                      "pellets": pellets, "spread": spread, "projectile_speed": 900 if category != "melee" else 0,
                      "range": rng, "magazine": mag, "reload_time": reload, "ammo_type": ammo, "noise_radius": noise,
                      "recoil": recoil, "shake": shake, "automatic": auto, "knockback": knock, "pierce": pierce,
                      "muzzle_offset": 12 if category != "melee" else 8}
    R.weapon_views[wid] = view
    return wid


def build(R: Registry) -> None:
    R.category("silah", "Silahlar")
    R.category("yakin_dovus", "Yakın dövüş")
    R.category("mermi", "Cephane")
    R.category("modifikasyon", "Silah modları")
    R.category("atilabilir", "Fırlatılabilir")
    R.category("silah_parcasi", "Silah parçaları")
    for tag, name in [("stock", "dipçik"), ("trigger", "tetik grubu"), ("magazine_part", "şarjör gövdesi"),
                      ("bowstring", "yay kirişi"), ("casing", "boş kovan")]:
        R.tag(tag, name)

    def item(iid, name, cat, tier, weight, value, tags, desc, model, **kw):
        return R.item(F, iid, name, cat, tier, weight, value, tags, desc, model=R.model(*model if isinstance(model, tuple) else (model,)), **kw)

    def rec(rid, name, out, count, inputs, station, tier, time, cat, sub, desc, **kw):
        return R.recipe(FAM, rid, name, out, count, inputs, station, tier, time, cat, sub, desc, **kw)

    # --- silah parcalari ---
    item("wood_stock", "Ahşap Dipçik", "component", 1, 0.8, 8, ["stock", "wood"], "Tüfek, arbalet ve dipçik modu için.",
         "wood_bundle", stack=6)
    rec("r_wood_stock", "Dipçik oyma", "wood_stock", 1, [I("wood_beam", 1)], "carpentry", 1, 8, "silah_parcasi", "Parça",
        "Kirişten yontulmuş dipçik.")
    item("trigger_group", "Tetik Grubu", "component", 2, 0.2, 30, ["trigger", "gun_part", "mechanical"],
         "Basit tetik ve horoz: atölye tabancası ve tüfek için.", "electronics", stack=10)
    rec("r_trigger_group", "Tetik grubu", "trigger_group", 1, [I("spring", 2), I("machined_part", 1)], "gunsmith", 2, 10,
        "silah_parcasi", "Parça", "Tek atış mekanizması.")
    item("magazine_blank", "Şarjör Gövdesi", "component", 2, 0.2, 20, ["magazine_part", "gun_part"],
         "Yaylı şarjör kutusu: geniş şarjör modları ve makineli.", "ammo_9mm", stack=10)
    rec("r_magazine_blank", "Şarjör gövdesi", "magazine_blank", 1, [I("metal_plate", 1), I("spring", 1)], "gunsmith", 2, 8,
        "silah_parcasi", "Parça", "Sac kutu ve besleme yayı.")
    item("bowstring", "Yay Kirişi", "component", 1, 0.05, 6, ["bowstring", "binding"], "Yay ve arbalet kirişi.", "cloth_roll",
         stack=10)
    rec("r_bowstring", "Kiriş örme", "bowstring", 1, [I("twine", 3)], "hands", 1, 5, "silah_parcasi", "Parça",
        "Sıkı örülmüş sicim.")
    rec("r_shell_casing", "Kovan çekme", "shell_casing", 20, [I("scrap_metal", 2), I("brass_stock", 1)], "gunsmith", 3, 14,
        "silah_parcasi", "Cephane", "Pirinç levhadan yeni kovan.")
    item("brass_stock", "Pirinç Levha", "component", 2, 0.5, 18, ["metal", "conductive_metal"],
         "Bakır ve çinko alaşımı: kovan ve süs.", "scrap_metal", stack=15)
    rec("r_brass_stock", "Pirinç dökme", "brass_stock", 2, [I("copper_ingot", 1), I("scrap_metal", 1), T("cook_fuel", 1)],
        "forge", 2, 10, "silah_parcasi", "Cephane", "Bakır alaşımı levhaya dökülür.")

    # --- yakin dovus ---
    melee = [
        ("bat", "Beyzbol Sopası", 1, 1.0, 20, 24, 1.8, 56, 45, 90, 150, 0, [I("wood_plank", 2)], "carpentry", 1, "demir_sopa"),
        ("nail_bat", "Çivili Sopa", 1, 1.2, 28, 32, 1.7, 56, 45, 95, 150, 0, [I("weapon_bat", 1), I("nail", 10)], "hands", 1, "demir_sopa"),
        ("spiked_club", "Dikenli Topuz", 2, 2.4, 40, 38, 1.3, 54, 45, 110, 200, 0, [I("iron_bar", 2), I("nail", 6)], "forge", 1, "demir_sopa"),
        ("machete", "Pala", 2, 0.9, 50, 30, 2.4, 50, 30, 70, 90, 0, [I("blade_blank", 1), I("tool_handle", 1)], "forge", 2, "balta"),
        ("cleaver", "Satır", 2, 1.1, 45, 34, 1.8, 46, 30, 70, 110, 0, [I("blade_blank", 1), I("leather_strap", 1)], "forge", 2, "balta"),
        ("spear_wood", "Sivri Mızrak", 1, 1.4, 12, 20, 1.5, 80, 12, 60, 90, 1, [I("wood_beam", 1), T("sharp", 2)], "hands", 1, "mizrak"),
        ("spear_steel", "Çelik Mızrak", 2, 1.8, 55, 30, 1.6, 84, 12, 60, 110, 1, [I("wood_beam", 1), I("blade_blank", 1)], "forge", 2, "mizrak"),
        ("yatagan", "Yatağan", 3, 1.2, 180, 44, 2.0, 56, 35, 70, 120, 1, [I("steel_sheet", 2), I("leather_strap", 2)], "forge", 3, "balta"),
        ("mace", "Gürz", 3, 3.2, 140, 50, 1.0, 54, 50, 120, 280, 1, [I("steel_ingot", 1), I("tool_handle", 1), I("rivets", 4)], "forge", 3, "demir_sopa"),
        ("war_hammer", "Savaş Çekici", 3, 4.0, 160, 58, 0.9, 58, 55, 130, 320, 2, [I("steel_ingot", 2), I("wood_beam", 1)], "forge", 3, "cekic"),
    ]
    for (iid, name, tier, weight, value, dmg, rate, reach, cone, noise, knock, pierce, inputs, station, stier, model) in melee:
        wid = weapon(R, "melee_" + iid, name, "melee", dmg, rate, cone, reach, 1, 0.0, "", noise, 0.0, 0.18, True, knock, pierce)
        item("weapon_" + iid, name, "weapon", tier, weight, value, ["weapon", "melee"],
             f"Yakın dövüş: {dmg} hasar, saniyede {rate:.1f} vuruş, {'uzun menzil, ' if reach > 70 else ''}sessiz sayılır.",
             "handheld/" + model, stack=1, durability=260 + tier * 120, weapon_id=wid)
        rec("r_weapon_" + iid, name, "weapon_" + iid, 1, inputs, station, stier, 8 + tier * 4, "yakin_dovus", "Yakın dövüş",
            f"{name}: {dmg} hasar.", learn="level:%d" % (tier * 4) if tier >= 3 else "")
    # Mevcut yakin dovus silahlarina tarif (eskiden yalnizca loot)
    rec("r_weapon_knife", "Mutfak bıçağı", "weapon_knife", 1, [I("blade_blank", 1), I("tool_handle", 1)], "forge", 1, 8,
        "yakin_dovus", "Yakın dövüş", "Sessiz, hızlı, yakın.")
    rec("r_weapon_pipe", "Demir boru sopa", "weapon_pipe", 1, [I("pipe_steel", 1), I("duct_tape", 1)], "hands", 1, 4,
        "yakin_dovus", "Yakın dövüş", "Sapı bantlanmış boru.")
    rec("r_weapon_axe", "İtfaiye baltası", "weapon_axe", 1, [I("blade_blank", 2), I("wood_beam", 1)], "forge", 2, 12,
        "yakin_dovus", "Yakın dövüş", "Geniş savurur; zırhı yarar.")
    rec("r_weapon_sledge", "Balyoz", "weapon_sledge", 1, [I("iron_bar", 3), I("tool_handle", 1)], "forge", 2, 12,
        "yakin_dovus", "Yakın dövüş", "Kalabalığı açar.")

    # --- atolye yapimi atesli silahlar ve yaylar ---
    ranged = [
        ("pipe_pistol", "Boru Tabanca", "pistol", "9mm", 2, 1.3, 90, 20, 2.5, 3.5, 300, 1, 2.0, 380, 1.8, 0,
         [I("pipe_steel", 1), I("trigger_group", 1), I("wood_plank", 1), T("fastener", 4)], "gunsmith", 2, "pistol", "pistol"),
        ("pipe_shotgun", "Boru Tüfek", "shotgun", "12ga", 2, 3.2, 150, 13, 1.0, 11, 200, 1, 2.6, 560, 3.8, 0,
         [I("pipe_steel", 2), I("trigger_group", 1), I("wood_stock", 1), T("fastener", 4)], "gunsmith", 2, "shotgun", "shotgun"),
        ("pipe_rifle", "Boru Karabina", "rifle", "762", 3, 3.8, 260, 44, 0.9, 1.4, 520, 1, 2.8, 640, 2.8, 1,
         [I("gun_barrel", 1), I("trigger_group", 1), I("wood_stock", 1), T("fastener", 4)], "gunsmith", 3, "marksman_rifle", "marksman_rifle"),
        ("smg_homemade", "Atölye Makinelisi", "smg", "9mm", 3, 3.0, 520, 13, 10.0, 3.2, 340, 24, 2.0, 430, 1.2, 0,
         [I("gun_barrel", 1), I("firing_mechanism", 1), I("magazine_blank", 1), I("metal_plate", 2), I("spring", 3)], "gunsmith", 3, "smg", "smg"),
        ("crossbow", "Arbalet", "rifle", "bolt", 2, 3.5, 220, 55, 0.8, 0.6, 460, 1, 2.4, 45, 1.5, 1,
         [I("wood_stock", 1), I("spring_heavy", 2), I("bowstring", 1), I("pulley", 1)], "workbench", 2, "", "handheld/yay"),
        ("bow_wood", "Ahşap Yay", "rifle", "arrow", 1, 1.0, 40, 26, 1.2, 1.4, 300, 1, 1.0, 30, 1.0, 0,
         [I("wood_plank", 2), I("bowstring", 1)], "carpentry", 1, "", "handheld/yay"),
        ("bow_compound", "Makaralı Yay", "rifle", "arrow", 3, 1.6, 200, 38, 1.3, 0.9, 400, 1, 0.9, 35, 1.0, 1,
         [I("plywood", 1), I("bowstring", 1), I("pulley", 2), I("aluminum_ingot", 1)], "workbench", 3, "", "handheld/yay"),
    ]
    for (iid, name, cat, ammo, tier, weight, value, dmg, rate, spread, rng, mag, reload, noise, recoil, pierce, inputs,
         station, stier, view, model) in ranged:
        pellets = 8 if cat == "shotgun" else 1
        wid = weapon(R, "craft_" + iid, name, cat, dmg, rate, spread, rng, mag, reload, ammo, noise, recoil, 0.2,
                     cat == "smg", 60 + dmg * 2, pierce, pellets, view=view)
        quiet = " Neredeyse sessiz." if noise < 60 else ""
        item("weapon_" + iid, name, "weapon", tier, weight, value, ["weapon", "firearm" if ammo not in ("bolt", "arrow") else "bow"],
             f"{dmg} hasar{' × %d saçma' % pellets if pellets > 1 else ''}, {mag} atımlık, {'otomatik' if cat == 'smg' else 'tek tek'}.{quiet}",
             model, stack=1, durability=240 + tier * 100, weapon_id=wid)
        rec("r_weapon_" + iid, name, "weapon_" + iid, 1, inputs, station, stier, 14 + tier * 6, "silah", "Atölye silahı",
            f"{name}.", learn="level:%d" % (tier * 3) if tier >= 3 else "")
    # Mevcut atesli silahlara tarif
    rec("r_weapon_makarov", "Makarov", "weapon_makarov", 1, [I("gun_barrel", 1), I("trigger_group", 1), I("magazine_blank", 1), I("metal_plate", 2)],
        "gunsmith", 3, 30, "silah", "Tabanca", "Basit, güvenilir tabanca.", learn="schematic")
    rec("r_weapon_revolver", ".357 Toplu", "weapon_revolver", 1, [I("gun_barrel", 1), I("firing_mechanism", 1), I("gear_small", 2), I("steel_ingot", 1)],
        "gunsmith", 4, 40, "silah", "Tabanca", "Altı atımlık toplu.", learn="schematic")
    rec("r_weapon_sawnoff", "Kırma çifte", "weapon_sawnoff", 1, [I("gun_barrel", 2), I("trigger_group", 1), I("wood_stock", 1)],
        "gunsmith", 2, 30, "silah", "Pompalı", "İki namlu, iki tetik.")
    rec("r_weapon_hunting", "Av tüfeği", "weapon_hunting", 1, [I("gun_barrel", 1), I("firing_mechanism", 1), I("wood_stock", 1)],
        "gunsmith", 3, 40, "silah", "Tüfek", "Sürgülü av tüfeği.", learn="schematic")
    rec("r_weapon_auto_rifle", "Piyade tüfeği", "weapon_auto_rifle", 1, [I("gun_barrel", 1), I("firing_mechanism", 1), I("gun_frame", 1),
        I("magazine_blank", 2), I("machined_part", 3)], "gunsmith", 4, 60, "silah", "Tüfek", "Otomatik askerî tüfek.", learn="schematic")

    # --- muhimmat ---
    def ammo(iid, name, atype, tier, value, effects, desc, model, count, inputs, station, stier, learn=""):
        item(iid, name, "ammo", tier, 0.02, value, ["ammo"], desc, model, stack=120, ammo_type=atype, effects=effects)
        rec("r_" + iid, name, iid, count, inputs, station, stier, 8 + tier * 2, "mermi", "Cephane", desc, learn=learn)

    rec("r_ammo_357", ".357 fişek", "ammo_357", 16, [I("shell_casing", 8), I("refined_powder", 2), I("primer_compound", 2), I("metal_plate", 1)],
        "gunsmith", 3, 12, "mermi", "Cephane", "Toplu tabanca fişeği.")
    ammo("ammo_9mm_ap", "9mm Zırh Delici", "9mm", 3, 6, {"damage": 0.9, "pierce": 1.0}, "Çelik uç: zırhlı zombiyi ve ince duvarı deler.",
         "ammo_9mm", 30, [I("shell_casing", 10), I("refined_powder", 2), I("primer_compound", 2), I("steel_ingot", 1)], "gunsmith", 3)
    ammo("ammo_9mm_hp", "9mm Oyuk Uçlu", "9mm", 2, 5, {"damage": 1.3}, "Açılan uç: çıplak hedefe büyük hasar, delmez.",
         "ammo_9mm", 30, [I("shell_casing", 10), I("refined_powder", 2), I("primer_compound", 2), I("metal_plate", 1)], "gunsmith", 2)
    ammo("ammo_12ga_slug", "12 Kalibre Tek Kurşun", "12ga", 3, 11, {"damage": 1.1, "spread": 0.3, "pierce": 1.0},
         "Saçma değil tek iri kurşun: uzağa isabetli.", "ammo_shells", 16,
         [I("shell_casing", 8), I("refined_powder", 3), I("primer_compound", 2), I("iron_bar", 2)], "gunsmith", 2)
    ammo("ammo_12ga_dragon", "Ejderha Nefesi", "12ga", 4, 18, {"damage": 0.8, "incendiary": 1.0},
         "Magnezyumlu saçma: vurduğu yanar.", "ammo_shells", 12,
         [I("shell_casing", 8), I("refined_powder", 2), I("primer_compound", 2), I("thermite", 1)], "gunsmith", 3, "level:14")
    ammo("ammo_762_ap", "7.62 Zırh Delici", "762", 4, 18, {"damage": 1.0, "pierce": 2.0}, "Duvarı ve arkasındakini deler.",
         "ammo_rifle", 20, [I("shell_casing", 8), I("refined_powder", 4), I("primer_compound", 2), I("steel_sheet", 1)], "gunsmith", 3)
    ammo("ammo_762_hp", "7.62 Oyuk Uçlu", "762", 3, 15, {"damage": 1.35}, "Av mermisi: tek atışta devirir.",
         "ammo_rifle", 20, [I("shell_casing", 8), I("refined_powder", 4), I("primer_compound", 2), I("metal_plate", 1)], "gunsmith", 3)
    ammo("ammo_357_hp", ".357 Oyuk Uçlu", "357", 3, 14, {"damage": 1.3}, "Toplu için ağır uç.",
         "ammo_9mm", 16, [I("shell_casing", 8), I("refined_powder", 2), I("primer_compound", 2), I("metal_plate", 1)], "gunsmith", 3)
    ammo("arrow", "Ok", "arrow", 1, 2, {"noise": 0.5}, "Sessiz. Çoğu zaman geri toplanamaz ama ucuz.", "handheld/yay", 6,
         [I("wood_plank", 1), T("sharp", 2), I("plant_fiber", 2)], "carpentry", 1)
    ammo("arrow_fire", "Ateşli Ok", "arrow", 2, 5, {"incendiary": 1.0, "noise": 0.8}, "Ucu yanar: vurduğunu tutuşturur.",
         "handheld/yay", 3, [I("arrow", 3), T("chemical_fuel", 1), I("cloth_rag", 1)], "hands", 1)
    ammo("bolt", "Arbalet Oku", "bolt", 1, 3, {"noise": 0.5}, "Kısa, ağır ok.", "handheld/yay", 8,
         [I("iron_bar", 1), I("wood_plank", 1)], "workbench", 1)
    ammo("bolt_heavy", "Çelik Arbalet Oku", "bolt", 2, 6, {"damage": 1.4, "pierce": 1.0, "noise": 0.5}, "Çelik uçlu: iki zombiyi deler.",
         "handheld/yay", 6, [I("steel_sheet", 1), I("wood_plank", 1)], "forge", 2)

    # --- firlatilabilirler ---
    throw = [
        ("smoke_grenade", "Duman Bombası", 2, 0.4, 60, ["throwable", "smoke"], {"smoke_radius": 140, "duration": 16},
         "16 sn duman: içindeyken zombiler seni göremez.", [I("smoke_compound", 1), T("tube", 1)], "chemistry", 2),
        ("shock_grenade", "Şok Bombası", 3, 0.5, 110, ["throwable", "electric"], {"shock": 5, "damage": 18, "radius": 110},
         "Elektrik şoku: çevredeki zombiler 5 sn yavaşlar.", [I("capacitor_salvaged", 2), I("battery_pack", 1), I("circuit_basic", 1)],
         "electronics", 2),
        ("frag_grenade", "El Bombası", 4, 0.6, 260, ["throwable", "explosive"], {"damage": 150, "radius": 150},
         "Askerî el bombası: geniş parça tesiri.", [I("military_explosive", 1), I("metal_plate", 1), I("primer_compound", 2)],
         "gunsmith", 3),
        ("dynamite", "Dinamit", 3, 0.5, 140, ["throwable", "explosive"], {"damage": 110, "radius": 120},
         "Nitrat çubuğu: blokları da parçalar.", [I("nitrate", 2), I("paper", 2), I("primer_compound", 1)], "chemistry", 3),
        ("napalm_bottle", "Napalm Şişesi", 3, 0.8, 120, ["throwable", "incendiary"], {"damage": 45, "radius": 120, "burn_duration": 10},
         "Sabunla koyulaşmış benzin: uzun ve geniş yangın.", [I("bottle_empty", 1), I("gasoline", 1), I("soap", 1)], "chemistry", 2),
        ("thermite_charge", "Termit Kalıbı", 4, 0.7, 150, ["throwable", "incendiary"], {"damage": 70, "radius": 60, "burn_duration": 12},
         "Yoğun ve sönmez yangın: dar alanda ölümcül.", [I("thermite", 1), T("tube", 1), I("match_heads", 2)], "chemistry", 3),
        ("tin_can_decoy", "Teneke Yem", 1, 0.3, 10, ["throwable", "utility"], {"noise_radius": 400, "delay": 2},
         "Çakıllı teneke: düştüğü yerde tıngırdar, sürüyü çeker.", [I("scrap_metal", 1), I("nail", 4)], "hands", 1),
    ]
    for (iid, name, tier, weight, value, tags, effects, desc, inputs, station, stier) in throw:
        item(iid, name, "consumable", tier, weight, value, tags, desc + " T ile fırlat.", ("iz2_mission_signal_beacon", "fuel_can"),
             stack=8, effects=effects)
        rec("r_" + iid, name, iid, 2 if tier <= 2 else 1, inputs, station, stier, 8 + tier * 2, "atilabilir", "Fırlatılabilir", desc)

    # --- modlar ---
    mods = [
        ("mod_compensator", "Kompansatör", "barrel", {"recoil": 0.7, "noise_radius": 1.1}, ["pistol", "smg", "rifle"],
         [I("machined_part", 1), I("metal_plate", 1)], "gunsmith", 2, "iz2_weapon_suppressor", "Geri tepmeyi %30 azaltır, biraz daha gürültülü."),
        ("mod_choke", "Daraltıcı (Şok)", "barrel", {"spread": 0.65, "range": 1.15}, ["shotgun"],
         [I("machined_part", 1)], "gunsmith", 2, "iz2_weapon_suppressor", "Saçma dağılımını toplar, menzil artar."),
        ("mod_muzzle_brake", "Namlu Freni", "barrel", {"recoil": 0.55, "noise_radius": 1.3}, ["rifle"],
         [I("machined_part", 1), I("steel_sheet", 1)], "gunsmith", 3, "iz2_weapon_suppressor", "Tüfekte geri tepmeyi yarıya indirir; çok gürültülü."),
        ("mod_suppressor_basic", "El Yapımı Susturucu", "barrel", {"noise_radius": 0.5, "damage": 0.95}, ["pistol", "smg"],
         [T("tube", 1), I("foam_padding", 3), I("filter_housing", 1)], "workbench", 2, "iz2_weapon_suppressor", "Sesi yarıya indirir; çabuk yıpranır."),
        ("mod_scope_4x", "4× Dürbün", "sight", {"spread": 0.5, "range": 1.4}, ["rifle"],
         [I("optic_assembly", 1), I("glass_lens", 1)], "electronics", 3, "iz2_weapon_red_dot", "Uzak atışta isabet ve menzil."),
        ("mod_holo_sight", "Holografik Nişangâh", "sight", {"spread": 0.65}, ["pistol", "smg", "rifle", "shotgun"],
         [I("led", 2), I("glass_lens", 1), I("battery_aa", 1), I("circuit_basic", 1)], "electronics", 3, "iz2_weapon_holo_sight", "Hızlı nişan."),
        ("mod_iron_sight", "Ayarlı Gez-Arpacık", "sight", {"spread": 0.85}, [],
         [I("metal_plate", 1), T("tool_file", 1, tool=True)], "gunsmith", 1, "iz2_weapon_red_dot", "Ucuz isabet artışı; her ateşli silaha."),
        ("mod_drum_mag", "Tambur Şarjör", "magazine", {"magazine": 2.2, "reload_time": 1.5}, ["smg", "rifle"],
         [I("magazine_blank", 2), I("spring_heavy", 1)], "gunsmith", 3, "ammo_9mm", "Şarjör 2,2 kat; doldurması uzun."),
        ("mod_pistol_mag", "Uzun Tabanca Şarjörü", "magazine", {"magazine": 1.5, "reload_time": 1.1}, ["pistol"],
         [I("magazine_blank", 1), I("spring", 1)], "gunsmith", 2, "ammo_9mm", "Tabancaya %50 fazla fişek."),
        ("mod_shotgun_tube", "Uzatılmış Tüp", "magazine", {"magazine": 1.5}, ["shotgun"],
         [T("tube", 1), I("spring", 2)], "gunsmith", 2, "ammo_shells", "Pompalıya fazladan fişek."),
        ("mod_foregrip", "Ön Kabza", "grip", {"recoil": 0.7, "spread": 0.9}, ["smg", "rifle", "shotgun"],
         [I("plastic_sheet", 1), I("metal_bracket", 1)], "gunsmith", 2, "iz2_weapon_foregrip", "Seri atışta kontrol."),
        ("mod_laser", "Lazer İşaretleyici", "grip", {"spread": 0.75}, ["pistol", "smg", "shotgun"],
         [I("led", 1), I("glass_lens", 1), I("battery_aa", 1)], "electronics", 2, "iz2_weapon_flashlight_mount", "Kalçadan atışta isabet."),
        ("mod_sharpened", "Bilenmiş Ağız", "edge", {"damage": 1.25}, ["melee"],
         [I("whetstone", 1)], "hands", 1, "handheld/balta", "Yakın dövüş hasarı %25 artar."),
        ("mod_weighted", "Ağırlıklı Baş", "head", {"damage": 1.15, "pierce_add": 2.0}, ["melee"],
         [I("iron_bar", 1), I("rivets", 2)], "forge", 1, "handheld/demir_sopa", "Daha ağır vuruş, bir hedef daha deler."),
        ("mod_barbed_wrap", "Dikenli Tel Sargı", "wrap", {"damage": 1.12}, ["melee"],
         [I("barbed_wire_coil", 1)], "hands", 1, "iz2_defense_wire_fence", "Sopa ve topuza diken sargısı."),
    ]
    for (iid, name, slot, stats, fits, inputs, station, stier, model, desc) in mods:
        item(iid, name, "mod", 3 if stier >= 3 else 2, 0.3, 120 + stier * 60, ["mod"], desc, model, stack=1,
             mod_slot=slot, mod_stats=stats, fits=fits, durability=0)
        rec("r_" + iid, name, iid, 1, inputs, station, stier, 10 + stier * 4, "modifikasyon", "Mod", desc)
