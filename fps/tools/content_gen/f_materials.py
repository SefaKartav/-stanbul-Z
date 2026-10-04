"""Hammaddeler, toplama (harvest) tablolari, ekinler, yeni loot tablolari."""
from lib import Registry, I, T

F = "items/gen_materials.json"


def build(R: Registry) -> None:
    m = R.item
    # --- etiketler (tarif girdisi olarak oyuncuya gosterilen Turkce adlar) ---
    for tag, name in [
        ("wood_raw", "kütük"), ("fiber", "bitki lifi (ot, lif)"), ("stone", "taş (parça, moloz)"),
        ("aggregate", "agrega (beton kırığı, taş, kum)"), ("cement", "çimento"), ("lime", "kireç"),
        ("clay", "kil"), ("brick_material", "tuğla"), ("bitumen", "zift (asfalt)"), ("pane", "sağlam cam"),
        ("rubber_raw", "kauçuk (lastik parçası, şerit)"), ("copper_source", "bakır kaynağı (kablo, radyatör)"),
        ("paper", "kâğıt"), ("resin", "reçine"), ("tea", "çay"), ("coffee", "kahve"),
        ("vegetable", "sebze (domates, biber, patates...)"), ("grain", "tahıl (buğday)"), ("fruit", "meyve"),
        ("fish", "balık"), ("bait", "yem"), ("fertilizer", "gübre / kompost"), ("seed", "tohum"),
        ("gas", "tüp gaz"), ("armor_raw", "zırh hammaddesi (kevlar, kalkan parçası)"),
        ("light_source", "ışık kaynağı (LED, ampul)"), ("solar", "güneş hücresi"),
        ("lock", "kilit"), ("syringe", "enjektör"), ("sugar_source", "şeker"),
        ("fabric", "kumaş"), ("wood", "ahşap"), ("mineral", "mineral"), ("glass", "cam"),
        ("electronic", "elektronik parça"), ("motor", "motor"), ("chemical", "kimyasal"),
        ("structural", "taşıyıcı parça"), ("organic", "organik malzeme"), ("power_source", "güç kaynağı (pil, akü)"),
        ("light_metal", "hafif metal (alüminyum)"), ("heavy", "ağır metal parça"), ("precision", "hassas parça"),
        ("logic", "mantık devresi"), ("medical", "tıbbi malzeme"), ("mechanical", "mekanik parça"),
        ("explosive_filler", "patlayıcı dolgu"), ("metal", "metal"), ("plate", "levha"),
        ("staple", "bakliyat/tahıl (pirinç, mercimek, makarna, un)"),
    ]:
        R.tag(tag, name)

    # --- toplanan (harvest) hammaddeler ---
    m(F, "wood_log", "Kütük", "material", 1, 3.0, 2, ["wood_raw", "wood", "cook_fuel", "organic"],
      "Ağaçtan baltayla kesilir. Marangozda kalas ve kirişe, ocakta kömüre dönüşür.", stack=12,
      model=R.model("wood_bundle"), quality=False)
    m(F, "resin", "Reçine", "material", 1, 0.1, 4, ["resin", "adhesive_base", "organic"],
      "Çam ve çınar kütüğünden sızar. Tutkal ve meşalede kullanılır.", stack=30, model=R.model("iz2_item_cooking_oil"),
      quality=False)
    m(F, "plant_fiber", "Bitki Lifi", "material", 1, 0.03, 1, ["fiber", "organic", "cook_fuel"],
      "Ot, sarmaşık ve yaprak lifi. İp, sicim ve kompost için.", stack=60, model=R.model("cloth_roll"), quality=False)
    m(F, "stone_chunk", "Taş Parçası", "material", 1, 1.2, 1, ["stone", "aggregate", "mineral"],
      "Kazmayla sökülen taş. Kesme taş, harç ve taş aletler için.", stack=30, model=R.model("rubble_pile"), quality=False)
    m(F, "concrete_rubble", "Beton Kırığı", "material", 1, 1.5, 1, ["aggregate", "mineral"],
      "Kırılmış beton. Yeni betona agrega olur; içinden inşaat demiri çıkabilir.", stack=30,
      model=R.model("rubble_pile"), quality=False)
    m(F, "loose_brick", "Sökülmüş Tuğla", "material", 1, 1.4, 2, ["brick_material", "mineral"],
      "Sağlam çıkmış eski tuğla. Harçla yeniden örülür.", stack=30, model=R.model("rubble_pile"), quality=False)
    m(F, "lime_powder", "Kireç", "material", 1, 0.8, 3, ["lime", "mineral"],
      "Sıva ve harcın bağlayıcısı. Dökülen sıvadan ve inşaat çuvallarından.", stack=20,
      model=R.model("iz2_item_flour_sack"), quality=False)
    m(F, "clay", "Kil", "material", 1, 1.0, 1, ["clay", "mineral"],
      "Toprağın altından kürekle çıkar. Fırında tuğla ve kiremit olur.", stack=30, model=R.model("rubble_pile"),
      quality=False)
    m(F, "asphalt_chunk", "Asfalt Parçası", "material", 1, 1.2, 1, ["bitumen", "mineral"],
      "Yol kaplaması. Isıtılınca zifte döner: çatı ve su yalıtımı.", stack=30, model=R.model("rubble_pile"),
      quality=False)
    m(F, "glass_pane", "Sağlam Cam", "material", 1, 1.0, 6, ["glass", "pane"],
      "Cam kesiciyle kırmadan sökülmüş tam levha. Pencere ve sera için.", stack=10,
      model=R.model("iz2_partition_glass", "water_bottle"), quality=False)
    m(F, "tire_scrap", "Lastik Parçası", "material", 1, 1.6, 2, ["rubber_raw", "polymer", "elastic"],
      "Araç lastiğinden kesilmiş kauçuk. Kauçuk levha, conta ve sapan lastiği.", stack=20,
      model=R.model("car_tire_spare"), quality=False)
    m(F, "radiator_core", "Radyatör Peteği", "material", 2, 2.5, 12, ["copper_source", "conductive_metal", "metal", "light_metal"],
      "Araç radyatöründen. İçinde bakır ve alüminyum var.", stack=6, model=R.model("car_radiator"), quality=False)
    m(F, "alternator", "Alternatör", "material", 2, 4.0, 40, ["electronic", "motor", "mechanical"],
      "Araçtan sökülmüş şarj dinamosu. Rüzgâr türbini ve jeneratörün kalbi.", stack=4,
      model=R.model("car_engine"), quality=False)
    m(F, "motor_large", "Büyük Motor", "material", 3, 7.0, 70, ["motor", "mechanical", "heavy", "electronic"],
      "Sanayi tipi elektrik motoru. Torna, kırıcı ve pompa için.", stack=2, model=R.model("car_engine"), quality=False)
    m(F, "gas_canister", "Tüp Gaz", "material", 2, 2.5, 25, ["chemical_fuel", "gas", "volatile", "cook_fuel"],
      "Mutfak tüpü. Ocak, kaynak şalomesi ve jeneratör yakıtı.", stack=4, model=R.model("gas_cylinder"),
      effects={"supply": 3.0}, quality=False)
    m(F, "diesel", "Mazot", "material", 2, 1.6, 26, ["chemical_fuel", "volatile"],
      "Ağır vasıta ve jeneratör yakıtı. Benzinden verimli yanar.", stack=10, model=R.model("fuel_can"),
      effects={"supply": 2.0}, quality=False)
    m(F, "solar_cell", "Güneş Hücresi", "material", 3, 0.3, 45, ["solar", "electronic"],
      "Bahçe lambalarından ve hesap makinelerinden toplanmış hücreler.", stack=20, model=R.model("solar_panel"),
      quality=False)
    m(F, "lamp_bulb", "Ampul", "material", 1, 0.1, 4, ["light_source", "electronic"],
      "Sağlam kalmış ampul. Basit lambalar için.", stack=20, model=R.model("electronics"), quality=False)
    m(F, "relay_switch", "Sökülmüş Röle", "material", 2, 0.1, 14, ["electronic", "logic"],
      "Sigorta panosundan. Anahtar ve sensör devrelerinde kullanılır.", stack=20, model=R.model("electronics"),
      quality=False)
    m(F, "paper", "Kâğıt", "material", 1, 0.05, 1, ["paper", "cook_fuel", "organic"],
      "Defter, dosya, gazete. Tutuşturucu ve harita için.", stack=50, model=R.model("binder"), quality=False)
    m(F, "kevlar_scrap", "Kevlar Parçası", "material", 3, 0.4, 40, ["armor_raw", "fabric", "tough_fabric"],
      "Askerî yelek ve kasktan sökülmüş aramid dokuma.", stack=15, model=R.model("cloth_roll"), quality=False)
    m(F, "riot_scrap", "Kalkan Parçası", "material", 2, 0.9, 18, ["armor_raw", "polymer"],
      "Çevik kuvvet kalkanı ve koruyucularından polikarbonat parça.", stack=15, model=R.model("steel_barricade"),
      quality=False)
    m(F, "military_explosive", "Askerî Patlayıcı", "material", 4, 0.5, 120, ["explosive_filler", "military", "volatile"],
      "Askerî tesis cephaneliğinden. Mayın ve güçlü bomba için; dikkatli taşı.", stack=10,
      model=R.model("iz2_mission_black_box", "ammo_rifle"), quality=False)
    m(F, "optic_scope", "Dürbün Merceği", "material", 3, 0.3, 60, ["optics", "precision", "glass"],
      "Askerî dürbünden sağlam mercek grubu.", stack=8, model=R.model("iz2_gear_binoculars"), quality=False)
    m(F, "steel_bars", "Demir Parmaklık", "material", 2, 3.0, 10, ["structural_metal", "metal", "heavy"],
      "Hapishane ve pencere parmaklığı. Eritilir ya da doğrudan kafes olur.", stack=10,
      model=R.model("prison/bars_01", "steel_barricade"), quality=False)
    m(F, "padlock", "Asma Kilit", "material", 1, 0.3, 8, ["lock", "metal", "mechanical"],
      "Kilitli depo ve kapılar için.", stack=10, model=R.model("iz2_mission_keyring_service", "toolbox"), quality=False)
    m(F, "saline_bag", "Serum Torbası", "material", 2, 0.5, 20, ["medical", "sterile"],
      "Hastane deposundan. Damar yolu serumu.", stack=10, model=R.model("medicine"), quality=False)
    m(F, "syringe", "Enjektör", "material", 1, 0.02, 6, ["syringe", "medical", "sharp"],
      "Steril paketli enjektör.", stack=30, model=R.model("medicine"), quality=False)
    m(F, "tea_leaves", "Çay", "material", 1, 0.25, 5, ["tea", "organic"],
      "Rize çayı paketi. Demlenince içilir; ayıltır ve odaklar.", stack=12, model=R.model("iz2_item_thermos"),
      quality=False)
    m(F, "coffee_beans", "Kahve", "material", 1, 0.25, 7, ["coffee", "organic"],
      "Çekilmiş Türk kahvesi. Enerji verir.", stack=12, model=R.model("iz2_item_thermos"), quality=False)
    m(F, "wheat", "Buğday", "material", 1, 0.5, 3, ["grain", "organic"],
      "Hasat edilmiş başak. Değirmende un olur.", stack=30, model=R.model("iz2_item_flour_sack"), quality=False)
    m(F, "cement_bag", "Çimento", "material", 1, 5.0, 8, ["cement", "mineral"],
      "İnşaat çuvalı. Kum, agrega ve suyla beton olur.", stack=8, model=R.model("iz2_item_flour_sack"), quality=False)

    # Okul: ders kitabi okunur (deneyim)
    m(F, "textbook", "Ders Kitabı", "consumable", 2, 0.6, 20, ["paper", "book"],
      "Fen ve teknik ders kitabı. Okumak deneyim kazandırır; kâğıdı tutuşturucu olur.", stack=5,
      model=R.model("books_stack"), effects={"xp": 60})

    # --- ekin urunleri ve tohumlar ---
    crops = [
        # tohum, ad, urun, urun adi, saat, adet, su/gun, tohum donusu, etiketler, besin, su, cig mi
        ("tomato_seeds", "Domates Tohumu", "tomato", "Domates", 48, [2, 4], 1.0, 0.6, ["vegetable", "food", "fruit"], 6, 4, False),
        ("pepper_seeds", "Biber Tohumu", "pepper", "Biber", 48, [2, 4], 1.0, 0.6, ["vegetable", "food"], 4, 2, False),
        ("bean_seeds", "Fasulye Tohumu", "beans_fresh", "Taze Fasulye", 60, [3, 5], 1.2, 0.7, ["vegetable", "food"], 10, 1, True),
        ("potato_seeds", "Tohumluk Patates", "potato", "Patates", 72, [3, 6], 1.0, 0.8, ["vegetable", "food"], 14, 0, True),
        ("wheat_seeds", "Buğday Tohumu", "wheat", "Buğday", 96, [3, 6], 0.8, 0.9, [], 0, 0, False),
        ("herb_seeds", "Şifalı Ot Tohumu", "herbs", "Şifalı Ot", 36, [2, 3], 0.8, 0.5, [], 0, 0, False),
    ]
    for seed, sname, crop, cname, hours, count, water, back, tags, food, drink, raw in crops:
        m(F, seed, sname, "consumable", 1, 0.02, 6, ["seed"],
          f"Saksıya ya da tarlaya ekilir (E). Yaklaşık {hours} oyun saatinde {cname.lower()} verir; su ister.",
          stack=40, model=R.model("seed_packet"))
        R.crops[seed] = {"yield": crop, "count": count, "hours": hours, "water_per_day": water, "seed_return": back}
        if crop in ("wheat", "herbs"):
            continue
        m(F, crop, cname, "consumable", 1, 0.3, 3, tags + ["organic"],
          f"Taze {cname.lower()}." + (" Çiğ yenmez: ocakta pişir." if raw else " Çiğ de yenir; yemekte daha doyurucu."),
          stack=20, model=R.model("iz2_district_fruit_cart" if crop in ("tomato", "pepper") else "iz2_item_lentil_bag"))
        R.nutrition[crop] = {"food": food, "water": drink, "shelf_life_h": 120, "spoils_to": "spoiled_food",
                             **({"raw": True} if raw else {})}
    # Mevcut sebze tohumu: karisik sebze
    m(F, "mixed_vegetables", "Karışık Sebze", "consumable", 1, 0.4, 4, ["vegetable", "food", "organic"],
      "Kabak, patlıcan, fasulye. Çiğ yenir; yahnide çok daha doyurucu.", stack=20, model=R.model("iz2_district_fruit_cart"))
    R.nutrition["mixed_vegetables"] = {"food": 9, "water": 3, "shelf_life_h": 96, "spoils_to": "spoiled_food"}
    R.crops["vegetable_seeds"] = {"yield": "mixed_vegetables", "count": [2, 4], "hours": 54, "water_per_day": 1.0,
                                  "seed_return": 0.5}
    m(F, "raw_fish", "Çiğ Balık", "consumable", 1, 0.5, 6, ["fish", "food", "organic"],
      "Oltayla tutulmuş istavrit, lüfer. Çiğ yenmez; ızgarada ya da çorbada pişir. Çabuk bozulur.", stack=10,
      model=R.model("iz2_district_fish_stall"))
    R.nutrition["raw_fish"] = {"raw": True, "shelf_life_h": 24, "spoils_to": "spoiled_food"}

    # --- toplama tablosu (blok malzemesi -> sinif + dusus) ---
    H = R.harvest

    def h(materials, cls, drops):
        for mat in materials:
            H[mat] = {"class": cls, "drops": [{"item": d[0], "count": d[1], "chance": d[2]} for d in drops]}

    h(["log"], "wood", [("wood_log", [1, 2], 1.0), ("resin", [1, 1], 0.25)])
    h(["leaves"], "plant", [("plant_fiber", [1, 3], 0.8), ("herbs", [1, 1], 0.08), ("herb_seeds", [1, 1], 0.04)])
    h(["wood", "wood_old", "furniture_wood", "pier_deck", "door_wood", "parquet"], "wood",
      [("wood_plank", [1, 2], 0.9), ("nail", [1, 3], 0.35)])
    h(["stone", "cobblestone", "cobble_half", "limestone", "gravestone", "stair_step", "stair_step_half"], "stone",
      [("stone_chunk", [1, 2], 1.0), ("sand", [1, 1], 0.2)])
    h(["concrete", "roof_flat", "curb_block", "sidewalk", "floor_tile"], "stone",
      [("concrete_rubble", [1, 1], 0.9), ("rebar", [1, 1], 0.12), ("sand", [1, 1], 0.25)])
    h(["brick"], "stone", [("loose_brick", [1, 1], 0.7), ("ceramic_shard", [1, 1], 0.3)])
    h(["plaster_cream", "plaster_blue", "plaster_rose", "plaster_white", "interior_plaster", "interior"], "stone",
      [("lime_powder", [1, 1], 0.4), ("sand", [1, 1], 0.3)])
    h(["roof_tile"], "stone", [("ceramic_shard", [1, 2], 0.8), ("clay", [1, 1], 0.2)])
    h(["asphalt", "asphalt_half", "asphalt_line"], "stone", [("asphalt_chunk", [1, 1], 0.9), ("sand", [1, 1], 0.2)])
    h(["rubble"], "stone", [("stone_chunk", [1, 1], 0.6), ("scrap_metal", [1, 1], 0.25), ("rebar", [1, 1], 0.1)])
    h(["dirt"], "soil", [("clay", [1, 1], 0.55), ("sand", [1, 1], 0.25)])
    h(["grass", "grass_half"], "soil", [("plant_fiber", [1, 2], 0.7), ("clay", [1, 1], 0.25), ("herb_seeds", [1, 1], 0.03)])
    h(["sand"], "soil", [("sand", [1, 2], 1.0)])
    h(["metal_sheet"], "metal", [("sheet_aluminum", [1, 2], 0.8), ("screw", [1, 3], 0.3)])
    h(["steel", "bridge_steel", "furniture_metal"], "metal", [("scrap_metal", [1, 3], 1.0), ("bolt_nut", [1, 3], 0.3)])
    h(["railing", "ladder"], "metal", [("pipe_steel", [1, 1], 0.8)])
    h(["door_metal"], "metal", [("scrap_metal", [2, 3], 1.0), ("hinge", [1, 1], 0.5)])
    h(["window_frame"], "glass", [("glass_shard", [1, 2], 0.8), ("plastic_shard", [1, 1], 0.5)])
    h(["glass", "door_glass"], "glass", [("glass_pane", [1, 1], 0.85), ("glass_shard", [1, 2], 0.4)])
    # Olta: sirayla denenir, ilk tutan cikar (son satir her zaman tutar).
    R.fishing = [
        {"item": "tire_scrap", "count": [1, 1], "chance": 0.06},
        {"item": "cloth_rag", "count": [1, 2], "chance": 0.05},
        {"item": "raw_fish", "count": [1, 2], "chance": 1.0},
    ]
    R.vehicle_salvage = [
        {"item": "scrap_metal", "count": [4, 8], "chance": 1.0},
        {"item": "tire_scrap", "count": [1, 3], "chance": 0.85},
        {"item": "copper_wire", "count": [2, 5], "chance": 0.7},
        {"item": "battery_car", "count": [1, 1], "chance": 0.45},
        {"item": "gasoline", "count": [1, 3], "chance": 0.4},
        {"item": "oil_can", "count": [1, 1], "chance": 0.5},
        {"item": "motor_small", "count": [1, 1], "chance": 0.4},
        {"item": "radiator_core", "count": [1, 1], "chance": 0.4},
        {"item": "alternator", "count": [1, 1], "chance": 0.3},
        {"item": "spring", "count": [1, 3], "chance": 0.5},
        {"item": "bearing", "count": [1, 2], "chance": 0.4},
        {"item": "glass_shard", "count": [1, 3], "chance": 0.5},
        {"item": "canvas", "count": [1, 2], "chance": 0.35},
    ]

    # --- yeni loot tablolari ve dolap/sinif baglantilari ---
    def table(tid, name, rolls, entries):
        R.loot_tables[tid] = {"name": name, "rolls": rolls,
                              "entries": [{"item": e[0], "weight": e[1], "count": e[2]} for e in entries]}

    table("gen_construction", "İnşaat malzemesi", [1, 2], [
        ("cement_bag", 5, [1, 2]), ("lime_powder", 5, [1, 3]), ("loose_brick", 4, [2, 5]), ("glass_pane", 3, [1, 2]),
        ("sand", 5, [2, 5]), ("rebar", 3, [1, 3]), ("nail", 4, [5, 15]), ("padlock", 1.5, [1, 1]),
        ("asphalt_chunk", 1, [1, 2])])
    table("gen_garden", "Bahçe ve tohum", [1, 1], [
        ("tomato_seeds", 4, [2, 5]), ("pepper_seeds", 4, [2, 5]), ("bean_seeds", 3, [2, 4]),
        ("potato_seeds", 3, [2, 4]), ("wheat_seeds", 2, [2, 5]), ("herb_seeds", 3, [1, 3]),
        ("vegetable_seeds", 3, [2, 4]), ("fertilizer", 2, [1, 2]), ("plant_fiber", 2, [2, 6])])
    table("gen_kitchen_extra", "Kiler", [1, 1], [
        ("tea_leaves", 5, [1, 2]), ("coffee_beans", 3, [1, 2]), ("gas_canister", 1.5, [1, 1]), ("paper", 2, [2, 6])])
    table("gen_electrical", "Elektrik malzemesi", [1, 2], [
        ("lamp_bulb", 5, [1, 4]), ("relay_switch", 4, [1, 3]), ("solar_cell", 1.5, [1, 3]), ("led", 3, [2, 6]),
        ("fuse", 3, [1, 4]), ("copper_wire", 3, [2, 6])])
    table("gen_medical_adv", "Hastane deposu", [1, 2], [
        ("saline_bag", 4, [1, 2]), ("syringe", 5, [2, 5]), ("antiseptic", 3, [1, 2]), ("sterile_cloth", 3, [2, 4]),
        ("painkiller", 3, [1, 3])])
    table("gen_school", "Okul malzemesi", [1, 2], [
        ("textbook", 4, [1, 1]), ("paper", 6, [3, 10]), ("battery_aa", 2, [1, 3]), ("glass_shard", 1, [1, 2]),
        ("bottle_empty", 2, [1, 3]), ("alcohol", 1.5, [1, 1]), ("canned_food", 2, [1, 2])])
    table("gen_military_adv", "Askerî cephanelik", [1, 2], [
        ("military_explosive", 2, [1, 2]), ("kevlar_scrap", 3, [1, 3]), ("optic_scope", 1.2, [1, 1]),
        ("ammo_762", 3, [10, 30]), ("ammo_9mm", 3, [10, 30]), ("ration_box", 2, [1, 2]), ("diesel", 2, [1, 3])])
    table("gen_prison", "Hapishane deposu", [1, 2], [
        ("steel_bars", 4, [1, 3]), ("padlock", 3, [1, 2]), ("riot_scrap", 3, [1, 3]), ("lockpick", 2, [1, 2]),
        ("cloth_rag", 3, [2, 5]), ("canned_food", 2, [1, 2]), ("screw", 2, [3, 8])])
    table("gen_fuel", "Yakıt ve garaj", [1, 1], [
        ("diesel", 4, [1, 2]), ("gas_canister", 2, [1, 1]), ("oil_can", 3, [1, 1]), ("tire_scrap", 3, [1, 3]),
        ("radiator_core", 1, [1, 1]), ("alternator", 0.8, [1, 1]), ("motor_large", 0.4, [1, 1])])

    for ctype, tid, weight in [
        ("tool_cabinet", "gen_construction", 1.5), ("parts_shelf", "gen_construction", 1.5),
        ("storeroom_rack", "gen_construction", 1.0), ("tool_cabinet", "gen_fuel", 1.0), ("parts_shelf", "gen_fuel", 1.2),
        ("supply_box", "gen_garden", 1.2), ("market_shelf", "gen_garden", 0.35), ("chest", "gen_garden", 0.8),
        ("supply_box", "gen_kitchen_extra", 0.6), ("market_shelf", "gen_kitchen_extra", 0.3),
        ("electronics_shelf", "gen_electrical", 2.0), ("display_cabinet", "gen_electrical", 1.0),
        ("living_cabinet", "gen_electrical", 0.6),
        ("medical_chest", "gen_medical_adv", 2.0), ("pharmacy_shelf", "gen_medical_adv", 0.6),
        ("filing_cabinet", "gen_school", 1.5), ("weapon_locker", "gen_military_adv", 0.8),
        ("footlocker", "gen_military_adv", 1.0), ("locker", "gen_prison", 1.0), ("footlocker", "gen_prison", 0.8),
    ]:
        R.container_pools.append((ctype, tid, weight))
