"""Su, yemek ve tarim ailesi."""
from lib import Registry, I, T

F = "items/gen_food.json"
FAM = "food"


def build(R: Registry) -> None:
    R.category("yemek", "Yemek")
    R.category("saklama", "Saklama ve konserve")
    R.category("su", "Su")
    R.category("tarim", "Tarım")
    R.category("hayatta_kalma", "Hayatta kalma")
    for tag, name in [("condiment", "salça / sos"), ("vinegar", "sirke"), ("compost", "kompost")]:
        R.tag(tag, name)

    def food(iid, name, food_v, water_v, shelf, desc, model, inputs, station, stier, count, effects=None, sub="Yemek",
             cat="yemek", tier=2, learn="", power=0.0, weight=0.5, tags=None):
        tags = tags or ["food", "cooked"]
        R.item(F, iid, name, "consumable", tier, weight, 4 + food_v // 3, tags, desc, stack=8,
               model=R.model(*model) if isinstance(model, tuple) else R.model(model), effects=effects or {})
        n = {"food": food_v, "water": water_v}
        if shelf:
            n.update({"shelf_life_h": shelf, "spoils_to": "spoiled_food"})
        R.nutrition[iid] = n
        R.recipe(FAM, "r_" + iid, name, iid, count, inputs, station, stier, 8 + stier * 2, cat, sub, desc,
                 learn=learn, power=power)

    fuel = T("cook_fuel", 1)
    water = I("water_bottle", 1)
    stew = "iz2_item_cooked_stew"
    dishes = [
        ("lentil_soup", "Mercimek Çorbası", 22, 14, 36, "Sıcak, doyurucu, bol su.", stew, [I("lentil_bag", 1), water, fuel], 1, 3, None),
        ("rice_pilaf", "Pirinç Pilavı", 30, 0, 36, "Tereyağsız ama doyurucu pilav.", stew, [I("rice_bag", 1), I("cooking_oil", 1), water, fuel], 1, 3, None),
        ("bulgur_pilaf", "Domatesli Bulgur Pilavı", 28, 4, 36, "Bulgur ve taze domates.", stew, [I("dry_goods", 2), I("tomato", 1), water, fuel], 1, 3, None),
        ("pasta_sauce", "Salçalı Makarna", 30, 2, 30, "Salça ve makarna: klasik.", stew, [I("pasta_pack", 1), I("tomato_paste", 1), water, fuel], 1, 3, None),
        ("flatbread", "Bazlama", 18, 0, 72, "Sacda pişmiş ekmek: yolda yenir.", "bread", [I("flour_sack", 1), water, I("salt_pack", 1), fuel], 1, 4, None),
        ("bread_loaf", "Somun Ekmek", 20, 0, 96, "Fırında somun: uzun dayanır.", "bread", [I("flour_sack", 1), water, I("salt_pack", 1), fuel], 2, 5, None),
        ("bean_stew", "Kuru Fasulye", 36, 6, 36, "Fasulye, salça, yağ: en doyurucu tencere.", stew,
         [I("beans_fresh", 3), I("tomato_paste", 1), I("cooking_oil", 1), fuel], 1, 3, None),
        ("potato_saute", "Patates Kavurma", 30, 0, 24, "Yağda kızarmış patates.", stew, [I("potato", 3), I("cooking_oil", 1), fuel], 1, 2, None),
        ("baked_potato", "Közde Patates", 22, 2, 24, "Ateşin külünde pişer.", stew, [I("potato", 2), fuel], 1, 2, None),
        ("pepper_saute", "Biberli Domates Sote", 22, 10, 24, "Menemenin yumurtasız hali.", stew,
         [I("tomato", 2), I("pepper", 2), I("cooking_oil", 1), fuel], 1, 2, None),
        ("stuffed_pepper", "Zeytinyağlı Biber Dolması", 32, 4, 48, "Pirinç dolgulu biber: soğuk da yenir.", stew,
         [I("pepper", 3), I("rice_bag", 1), I("cooking_oil", 1), fuel], 2, 3, None),
        ("veg_stew", "Sebze Yahnisi", 34, 12, 36, "Sebze ve patates: iyileştirir.", stew,
         [I("mixed_vegetables", 2), I("potato", 1), water, fuel], 1, 3, {"regen": 0.2, "duration": 60}),
        ("tomato_soup", "Domates Çorbası", 16, 18, 30, "Hafif, bol sulu çorba.", stew, [I("tomato", 3), I("flour_sack", 1), water, fuel], 1, 4, None),
        ("fish_grilled", "Izgara Balık", 26, 2, 12, "Tuzlu, közde.", "iz2_district_fish_stall", [I("raw_fish", 1), fuel], 1, 1, None),
        ("fish_bread", "Balık Ekmek", 40, 2, 12, "İskele usulü: ekmek arası balık. Moral verir.", "iz2_district_fish_stall",
         [I("raw_fish", 1), I("flatbread", 1), fuel], 1, 1, {"focus": 0.1, "duration": 90}),
        ("fish_soup", "Balık Çorbası", 24, 16, 18, "Balık, patates, su.", stew, [I("raw_fish", 1), I("potato", 1), water, fuel], 1, 2, None),
        ("helva", "Un Helvası", 20, 0, 96, "Şekerli, yağlı: hızlı toparlar.", "bread", [I("flour_sack", 1), I("sugar_pack", 1), I("cooking_oil", 1), fuel],
         1, 4, {"regen": 0.3, "duration": 40}),
        ("compote", "Hoşaf", 8, 22, 72, "Kuru meyve şurubu.", "iz2_item_thermos", [I("dried_fruit", 2), I("sugar_pack", 1), water, fuel], 1, 3, None),
        ("tea_brewed", "Demli Çay", 0, 12, 24, "İnce belli bardakta: ayıltır, odaklar.", "iz2_item_thermos", [I("tea_leaves", 1), water, fuel],
         1, 3, {"focus": 0.12, "duration": 90}),
        ("turkish_coffee", "Türk Kahvesi", 0, 5, 24, "Enerji ve odak.", "iz2_item_thermos", [I("coffee_beans", 1), water, fuel], 1, 3,
         {"stamina": 30, "focus": 0.2, "duration": 60}),
        ("gozleme", "Patatesli Gözleme", 34, 0, 36, "Hamur arası patates.", "bread", [I("flour_sack", 1), I("potato", 2), I("cooking_oil", 1), fuel], 1, 3, None),
        ("chickpea_stew", "Nohut Yemeği", 30, 6, 36, "Salçalı nohut.", stew, [I("chickpea_can", 2), I("tomato_paste", 1), fuel], 1, 3, None),
        ("tarhana", "Tarhana Çorbası", 16, 14, 48, "Un ve salça: kış çorbası.", stew, [I("flour_sack", 1), I("tomato_paste", 1), water, fuel], 1, 4, None),
        ("grilled_veg", "Közlenmiş Sebze", 20, 6, 24, "Közlenmiş sebze ve biber.", stew, [I("mixed_vegetables", 2), I("pepper", 1), fuel], 1, 2, None),
        ("potato_soup", "Patates Çorbası", 20, 14, 30, "Sade, sıcak, tok tutar.", stew, [I("potato", 3), water, I("salt_pack", 1), fuel], 1, 3, None),
        ("rice_soup", "Yayla Çorbası", 18, 14, 30, "Pirinçli, naneli çorba: mideyi yatıştırır.", stew,
         [I("rice_bag", 1), I("herbs", 1), water, fuel], 2, 3, {"cure_sick": 1}),
    ]
    for (iid, name, fv, wv, shelf, desc, model, inputs, stier, count, effects) in dishes:
        food(iid, name, fv, wv, shelf, desc + f" (+{fv} tokluk, +{wv} su)", model, inputs, "cooking", stier, count, effects)

    food("field_ration", "Sahra Kumanyası", 55, 5, 0, "Bazlama, kuru meyve, kavurma: bozulmaz, tam bir öğün.",
         "iz2_item_ration_box", [I("flatbread", 2), I("dried_fruit", 1), I("preserved_meat", 1)], "hands", 1, 1, tier=3,
         sub="Kumanya", weight=0.8, tags=["food", "supply"])
    R.recipe(FAM, "r_energy_bar_home", "Ev yapımı enerji barı", "energy_bar", 4, [I("dried_fruit", 2), I("sugar_pack", 1), I("flour_sack", 1)],
             "cooking", 1, 10, "yemek", "Kumanya", "Kuru meyve, şeker ve un preslenir.")

    # --- saklama ---
    R.item(F, "tomato_paste", "Salça", "material", 1, 0.4, 5, ["condiment", "organic"], "Domatesten koyulaştırılmış salça: yemek tabanı.",
           stack=12, model=R.model("iz2_item_cooking_oil"), quality=False)
    R.recipe(FAM, "r_tomato_paste", "Salça kaynatma", "tomato_paste", 2, [I("tomato", 4), I("salt_pack", 1), fuel], "cooking", 1, 12,
             "saklama", "Konserve", "Domates güneşte ya da ocakta koyulaşır.")
    R.item(F, "vinegar", "Sirke", "material", 1, 0.6, 4, ["vinegar", "antiseptic_base", "organic"],
           "Mayalanmış meyve: turşu ve yara temizliği.", stack=12, model=R.model("water_bottle"), quality=False)
    R.recipe(FAM, "r_vinegar", "Sirke mayalama", "vinegar", 2, [I("dried_fruit", 2), T("water_raw", 2)], "farming", 1, 16,
             "saklama", "Fermente", "Kuru meyve suyla mayalanır.")
    food("pickles", "Turşu", 8, 2, 0, "Tuz ve sirkeyle kurulmuş sebze: bozulmaz.", "iz2_food_fermentation_crock",
         [I("mixed_vegetables", 2), I("salt_pack", 1), I("vinegar", 1)], "farming", 1, 3, sub="Konserve", cat="saklama")
    food("jam", "Reçel", 14, 0, 0, "Şekerli meyve: bozulmaz, enerji verir.", "iz2_food_preserving_table",
         [I("dried_fruit", 2), I("sugar_pack", 1), fuel], "cooking", 1, 3, sub="Konserve", cat="saklama", effects={"stamina": 15})
    food("dried_tomato", "Kuru Domates", 10, 0, 0, "Güneşte kurutulmuş: hafif ve bozulmaz.", "iz2_food_dehydrator",
         [I("tomato", 3), I("salt_pack", 1)], "farming", 1, 2, sub="Kurutma", cat="saklama", weight=0.2)
    food("smoked_fish", "Tütsülenmiş Balık", 22, 0, 0, "Tuz ve dumanla korunmuş balık.", "iz2_food_smoking_cabinet",
         [I("raw_fish", 2), I("salt_pack", 1), fuel], "farming", 2, 2, sub="Kurutma", cat="saklama")
    R.recipe(FAM, "r_home_canning", "Kavanoz konserve", "canned_food", 2, [I("veg_stew", 2), I("bottle_empty", 1), fuel], "farming", 2, 14,
             "saklama", "Konserve", "Sıcak yahni kavanozlanır: yıllarca dayanır.")

    # --- su ---
    R.recipe(FAM, "r_water_ceramic", "Seramik filtreyle arıtma", "water_bottle", 4, [I("water_dirty", 4), I("ceramic_filter", 1)],
             "water", 2, 12, "su", "Arıtma", "Seramik mum bakteriyi tutar; mum tükenir.")
    R.recipe(FAM, "r_water_sand", "Kum filtresiyle arıtma", "water_bottle", 3, [I("water_dirty", 3), I("sand_filter_pack", 1)],
             "water", 1, 10, "su", "Arıtma", "Kum ve kömür katmanı.")
    R.recipe(FAM, "r_sea_salt", "Deniz tuzu", "salt_pack", 1, [I("water_dirty", 4), T("cook_fuel", 2)], "cooking", 1, 16, "su", "Tuz",
             "Deniz suyu kaynatılıp kristallenir.")
    R.recipe(FAM, "r_water_pouch_fill", "Su kesesi doldurma", "water_pouch", 4, [I("water_bottle", 1), I("plastic_sheet", 1)], "hands", 1, 6,
             "su", "Taşıma", "Temiz su hafif keselere bölünür.")
    R.recipe(FAM, "r_canister_fill", "Bidon doldurma", "water_canister", 1, [I("water_bottle", 5), I("plastic_sheet", 2)], "workbench", 1, 8,
             "su", "Taşıma", "Beş şişe tek bidonda: depo için.")

    # --- tarim ---
    R.item(F, "compost", "Kompost", "material", 1, 1.0, 3, ["fertilizer", "compost", "organic"],
           "Çürümüş yemek ve ottan gübre: saksıda büyümeyi %50 hızlandırır (E ile ver).", stack=20, model=R.model("fertilizer"),
           quality=False)
    R.recipe(FAM, "r_compost", "Kompost yapma", "compost", 2, [I("spoiled_food", 3), I("plant_fiber", 2)], "farming", 1, 12, "tarim", "Gübre",
             "Bozuk yemek boşa gitmez.")
    R.recipe(FAM, "r_fertilizer_mix", "Gübre karışımı", "fertilizer", 3, [I("compost", 2), I("nitrate", 1)], "farming", 2, 10, "tarim", "Gübre",
             "Kompost ve nitrat: kimyada da kullanılır.")
    R.item(F, "bait", "Balık Yemi", "material", 1, 0.05, 1, ["bait", "organic"], "Oltada şansı büyük ölçüde artırır.", stack=40,
           model=R.model("iz2_district_fishing_rod_rack"), quality=False)
    R.recipe(FAM, "r_bait", "Yem hazırlama", "bait", 4, [I("spoiled_food", 1)], "hands", 1, 3, "tarim", "Balıkçılık",
             "Bozuk yemek balığın sevdiği şeydir.")
    R.recipe(FAM, "r_bait_bread", "Hamur yemi", "bait", 6, [I("flour_sack", 1), T("water_raw", 1)], "hands", 1, 4, "tarim", "Balıkçılık",
             "Un ve su topaklanır.")
    for crop, seed, n_in, n_out in [("tomato", "tomato_seeds", 1, 3), ("pepper", "pepper_seeds", 1, 3), ("beans_fresh", "bean_seeds", 2, 4),
                                    ("potato", "potato_seeds", 1, 2), ("wheat", "wheat_seeds", 3, 4), ("herbs", "herb_seeds", 2, 3)]:
        R.recipe(FAM, "r_seeds_" + seed, "Tohum ayıklama: " + R.items.get(seed, {}).get("name", seed), seed, n_out, [I(crop, n_in)],
                 "farming", 1, 6, "tarim", "Tohum", "Hasattan tohum ayırıp yeniden ekersin.")
    R.recipe(FAM, "r_flour_mill", "Un öğütme", "flour_sack", 1, [I("wheat", 4)], "farming", 1, 12, "tarim", "Değirmen",
             "Buğday taşta öğütülür.")

    def place(iid, name, tier, weight, desc, catalog, model, inputs, station, stier, sub, learn=""):
        m = R.model(*model) if isinstance(model, tuple) else R.model(model)
        R.item(F, iid, name, "station", tier, weight, 20 * tier, ["placeable"], desc + " İnşa kipinde (B) kurulur.", stack=2, model=m)
        R.placeables[iid] = {"label": name, "model": m, **catalog}
        R.recipe(FAM, "r_" + iid, name, iid, 1, inputs, station, stier, 10 + tier * 4, "tarim" if catalog["kind"] == "planter" else "su",
                 sub, desc, learn=learn)

    place("planter_box", "Saksı", 1, 6.0, "Tek ekimlik saksı: tohum ek, sula, hasat et (E).",
          {"kind": "planter", "growth": 1.0, "solid": False}, ("production/planter_01", "crop_bed"),
          [I("wooden_frame", 1), I("clay", 2)], "carpentry", 1, "Ekim")
    place("raised_bed", "Yükseltilmiş Yatak", 2, 20.0, "Gübreli toprak: %25 hızlı büyür.",
          {"kind": "planter", "growth": 1.25, "solid": False}, ("production/planter_02", "crop_bed"),
          [I("wood_plank", 4), I("clay", 4), I("compost", 2)], "carpentry", 1, "Ekim")
    place("farm_plot", "Tarla Parseli", 1, 10.0, "Toprağa açılmış parsel: %10 hızlı.",
          {"kind": "planter", "growth": 1.1, "solid": False}, "iz2_farm_seedling_tray", [I("clay", 6), I("fertilizer", 1)], "hands", 1, "Ekim")
    place("greenhouse_bed", "Sera Yatağı", 3, 30.0, "Cam örtülü yatak: %50 hızlı büyür.",
          {"kind": "planter", "growth": 1.5, "solid": False}, ("iz2_farm_greenhouse_frame", "crop_bed"),
          [I("glass_pane", 2), I("wooden_frame", 2), I("clay", 4), I("compost", 2)], "carpentry", 2, "Ekim", learn="level:8")
    place("rain_tarp", "Brandalı Toplayıcı", 1, 4.0, "Üste kurulur: her gün 1-3 şişe kirli su toplar.",
          {"kind": "rain_collector", "daily": [1, 3], "solid": False}, ("production/collector_01", "rain_collector"),
          [I("canvas_sheet", 1), I("pvc_pipe", 1), I("wooden_frame", 1)], "workbench", 1, "Toplama")
    place("rain_cistern", "Katlanır Sarnıç", 3, 20.0, "Her gün 3-7 şişe kirli su.",
          {"kind": "rain_collector", "daily": [3, 7]}, ("iz2_water_cistern_collapsible", "water_tank"),
          [I("canvas_sheet", 2), I("tar", 2), I("pipe_fitting", 2), I("wood_beam", 2)], "workbench", 2, "Toplama")
    place("solar_still", "Güneş Damıtıcı", 2, 8.0, "Elektriksiz: üs deposundaki kirli sudan her gün 2 şişe temizler.",
          {"kind": "purifier", "daily": 2}, ("iz2_water_distiller", "iz2_water_boiling_rig"),
          [I("glass_pane", 2), I("plastic_sheet", 2), I("pipe_fitting", 1)], "workbench", 1, "Arıtma")
    place("sand_filter_barrel", "Kum Filtreli Varil", 2, 16.0, "Her gün 4 şişe temizler; günde 1 kum filtre paketi harcar.",
          {"kind": "purifier", "daily": 4, "consumes": "sand_filter_pack"}, ("production/filter_01", "iz2_water_purifier_gravity"),
          [I("water_tank_part", 1), I("sand_filter_pack", 2), I("pipe_fitting", 2)], "workbench", 2, "Arıtma")
    R.item(F, "water_tank_part", "Su Tankı Gövdesi", "component", 1, 4.0, 10, ["container"], "Plastik tank: arıtıcı ve toplayıcı gövdesi.",
           stack=4, model=R.model("water_tank"))
    R.recipe(FAM, "r_water_tank_part", "Tank gövdesi", "water_tank_part", 1, [I("plastic_sheet", 4), T("adhesive", 1)], "workbench", 1, 8,
             "su", "Parça", "Plastik levhalar kaynatılır.")
    place("compost_bin", "Kompost Kutusu", 1, 8.0, "Her gün üs deposundaki 3 bozuk yemeği komposta çevirir.",
          {"kind": "purifier", "daily": 3, "from": "spoiled_food", "to": "compost"}, ("production/compost_01", "iz2_food_compost_tumbler"),
          [I("wood_plank", 4), I("nail", 6)], "carpentry", 1, "Gübre")
