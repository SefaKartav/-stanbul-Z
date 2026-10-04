"""Kaynak isleme ve bilesen ailesi: metal, ahsap, tas/beton, kumas, kimya, mekanik."""
from lib import Registry, I, T

F = "items/gen_components.json"
FAM = "process"


def build(R: Registry) -> None:
    c = R.category
    c("metal", "Metal işleri")
    c("ahsap", "Ahşap işleri")
    c("yapi_malzemesi", "Taş ve beton")
    c("kumas", "Kumaş ve deri")
    c("kimya", "Kimya")
    c("mekanik", "Mekanik")
    for tag, name in [("bar", "demir çubuk"), ("ingot", "külçe"), ("bracket", "köşebent"), ("blade", "bıçak taslağı"),
                      ("fitting", "boru bağlantısı"), ("mesh", "tel örgü"), ("barbed", "dikenli tel"),
                      ("beam", "ahşap kiriş"), ("panel", "ahşap panel"), ("frame", "ahşap çerçeve"),
                      ("handle", "alet sapı"), ("roofing", "çatı kaplaması"), ("mortar", "harç"), ("concrete", "beton harcı"),
                      ("stone_block", "kesme taş"), ("rebar_mesh", "hasır çelik"), ("block_material", "briket"),
                      ("sealant", "zift / yalıtım"), ("twine", "sicim"), ("rope", "halat"), ("textile", "kumaş top"),
                      ("padding", "dolgu pedi"), ("strap", "deri kayış"), ("tarp", "branda"), ("rubber_sheet", "kauçuk levha"),
                      ("plastic_sheet", "plastik levha"), ("nitrate", "nitrat"), ("lye", "kostik"), ("soap", "sabun"),
                      ("electrolyte", "akü asidi"), ("incendiary_filler", "termit"), ("smoke_filler", "duman karışımı"),
                      ("pulley", "makara"), ("engine_part", "motor parçası"), ("pump", "pompa ünitesi"),
                      ("filter_part", "filtre gövdesi"), ("ceramic_filter", "seramik filtre"), ("lens", "mercek"),
                      ("welding", "kaynak çubuğu"), ("rivet", "perçin"), ("chain", "zincir"), ("abrasive", "aşındırıcı (kum)"),
                      ("hard", "sert parça (seramik, cam)"), ("sharp", "keskin parça (çivi, cam kırığı)"),
                      ("adhesive", "yapıştırıcı (bant, epoksi, tutkal)"), ("chemical_fuel", "yakıcı sıvı (ispirto, benzin, yağ)"),
                      ("cook_fuel", "yakıt (odun, kömür, alkol, yağ)"), ("water_raw", "kirli su"), ("solvent", "çözücü (ispirto, etanol)"),
                      ("antiseptic_base", "antiseptik taban (ispirto, etanol, sabun)"), ("tube", "boru"),
                      ("structural_metal", "yapısal metal (hurda, boru, levha)"), ("fastener", "bağlantı parçası (çivi, vida, perçin)"),
                      ("polymer", "plastik/kauçuk"), ("tough_fabric", "sağlam kumaş (branda, deri)"),
                      ("conductive_metal", "iletken metal (kablo, tel)"), ("elastic", "esnek parça (yay, lastik)"),
                      ("binding", "bağlama malzemesi (tel, bant, sicim)"), ("chemical_oxidizer", "oksitleyici (çamaşır suyu, gübre, nitrat)"),
                      ("filter_medium", "filtre maddesi (kömür)"), ("optics", "optik cam (mercek, ayna)"),
                      ("wire", "tel/kablo"), ("insulator", "yalıtkan (plastik, kauçuk, sünger)"), ("soft", "yumuşak kumaş (bez, sünger)"),
                      ("lubricant", "yağlayıcı")]:
        R.tag(tag, name)

    def comp(item_id, name, cat, tier, weight, value, tags, desc, stack=20, model="electronics", **kw):
        return R.item(F, item_id, name, cat, tier, weight, value, tags, desc, stack=stack, model=R.model(model), **kw)

    def rec(rid, name, out, count, inputs, station, tier, time, cat, sub, desc, **kw):
        return R.recipe(FAM, rid, name, out, count, inputs, station, tier, time, cat, sub, desc, **kw)

    # ------------------------------------------------------------- metal
    comp("iron_bar", "Demir Çubuk", "component", 2, 0.8, 8, ["bar", "structural_metal", "metal"],
         "Hurdadan dövülmüş çubuk. Çivi, sap, kazma ve köşebentin hammaddesi.", model="scrap_metal")
    rec("r_iron_bar", "Demir çubuk dövme", "iron_bar", 2, [I("scrap_metal", 3), T("cook_fuel", 1)], "forge", 1, 6,
        "metal", "Dövme", "Hurda metali ocakta ısıtıp çubuğa çekersin.")
    rec("r_iron_bar_bars", "Parmaklık eritme", "iron_bar", 3, [I("steel_bars", 1), T("cook_fuel", 1)], "forge", 1, 6,
        "metal", "Dövme", "Hapishane parmaklığı temiz demirdir: hurdadan verimli.")
    rec("r_steel_from_rebar", "İnşaat demirinden çelik", "steel_ingot", 1, [I("rebar", 3), I("charcoal", 2)],
        "forge", 2, 12, "metal", "Eritme", "Kömürle karbonlanan demir çeliğe döner.")
    comp("aluminum_ingot", "Alüminyum Külçe", "component", 2, 0.6, 12, ["ingot", "light_metal", "metal"],
         "Levha ve kutulardan eritilmiş hafif metal.", model="scrap_metal")
    rec("r_aluminum_ingot", "Alüminyum eritme", "aluminum_ingot", 1, [I("sheet_aluminum", 3), T("cook_fuel", 1)],
        "forge", 1, 8, "metal", "Eritme", "Alüminyum düşük ısıda erir; hafif parçalar için.")
    comp("copper_ingot", "Bakır Külçe", "component", 2, 0.9, 16, ["ingot", "conductive_metal", "metal"],
         "Kablo ve radyatörden. Bobin ve elektrik tesisatı için.", model="scrap_metal")
    rec("r_copper_ingot", "Bakır eritme (kablo)", "copper_ingot", 1, [I("copper_wire", 6), T("cook_fuel", 1)],
        "forge", 2, 8, "metal", "Eritme", "Kabloların yalıtımı yanar, bakır kalır.")
    rec("r_copper_radiator", "Radyatör sökme", "copper_ingot", 2, [I("radiator_core", 1), T("cook_fuel", 1)],
        "forge", 2, 10, "metal", "Eritme", "Radyatör peteğinden bakır ve alüminyum ayrılır.",
        byproducts={"aluminum_ingot": 1})
    comp("steel_sheet", "Çelik Sac", "component", 3, 1.1, 30, ["plate", "structural_metal", "metal"],
         "Dövülüp düzlenmiş çelik. Çelik duvar, zırh ve alet bıçağı.", model="steel_barricade")
    rec("r_steel_sheet", "Çelik sac haddeleme", "steel_sheet", 2, [I("steel_ingot", 1)], "forge", 3, 10,
        "metal", "Dövme", "Külçeyi ince levhaya çekersin.")
    comp("rivets", "Perçin", "material", 1, 0.01, 1, ["fastener", "rivet", "metal"],
         "Sac birleştirmenin en sağlam yolu.", stack=99, model="scrap_metal", quality=False)
    rec("r_rivets", "Perçin dövme", "rivets", 12, [I("iron_bar", 1)], "forge", 1, 5, "metal", "Bağlantı",
        "Bir çubuktan bir avuç perçin.")
    rec("r_nails_forge", "Çivi dövme", "nail", 20, [I("iron_bar", 1)], "forge", 1, 5, "metal", "Bağlantı",
        "Duvar ve barikat için çivi.")
    rec("r_screws_lathe", "Vida açma", "screw", 15, [I("iron_bar", 1)], "mechanic", 1, 6, "metal", "Bağlantı",
        "Torna ile diş açılmış vida.")
    rec("r_bolts_lathe", "Cıvata ve somun", "bolt_nut", 10, [I("iron_bar", 1)], "mechanic", 1, 6, "metal", "Bağlantı",
        "Ağır parçaları tutturan cıvata.")
    comp("metal_bracket", "Metal Köşebent", "component", 2, 0.3, 6, ["bracket", "structural", "metal"],
         "Ahşabı güçlendiren, rafı taşıyan köşe parçası.", model="scrap_metal")
    rec("r_metal_bracket", "Köşebent bükme", "metal_bracket", 3, [I("iron_bar", 1), T("fastener", 2)], "workbench", 2, 4,
        "metal", "Parça", "Güçlendirilmiş ahşabın sırrı.")
    comp("hinge_heavy", "Ağır Menteşe", "component", 2, 0.4, 10, ["mechanical", "metal"],
         "Çelik kapı ve kepenk taşıyabilir.", model="scrap_metal")
    rec("r_hinge_heavy", "Ağır menteşe", "hinge_heavy", 2, [I("iron_bar", 1), I("hinge", 1)], "forge", 2, 6,
        "metal", "Parça", "Kapı ve kapaklar için.")
    comp("gear_large", "Büyük Dişli", "component", 3, 0.7, 25, ["mechanical", "precision"],
         "Güç aktarımı: türbin, kırıcı ve araç şanzımanı.", model="scrap_metal")
    rec("r_gear_large", "Büyük dişli işleme", "gear_large", 2, [I("steel_ingot", 1)], "mechanic", 2, 10,
        "mekanik", "İşleme", "Çelikten dişli kesersin.")
    rec("r_gear_small_alu", "Küçük dişli (alüminyum)", "gear_small", 4, [I("aluminum_ingot", 1)], "mechanic", 1, 6,
        "mekanik", "İşleme", "Hafif mekanizmalar için dişli.")
    comp("axle", "Aks", "component", 3, 2.0, 30, ["mechanical", "heavy"], "Rulmanlı mil. Türbin ve kırıcıda döner.",
         model="car_engine")
    rec("r_axle", "Aks yapımı", "axle", 1, [I("steel_ingot", 1), I("bearing", 2)], "mechanic", 2, 10, "mekanik",
        "İşleme", "Dönen her şeyin mili.")
    comp("spring_heavy", "Ağır Yay", "component", 2, 0.3, 12, ["elastic", "mechanical"],
         "Kapan, kapı kapatıcı ve kalın silah yayı.", model="scrap_metal")
    rec("r_spring_heavy", "Ağır yay sarma", "spring_heavy", 2, [I("wire_steel", 2), I("iron_bar", 1)], "forge", 2, 6,
        "mekanik", "Yay", "Isıl işlemli çelik yay.")
    rec("r_spring_coil", "Yay sarma", "spring", 3, [I("wire_steel", 2)], "forge", 1, 4, "mekanik", "Yay",
        "Telden küçük yay.")
    comp("blade_blank", "Bıçak Taslağı", "component", 3, 0.4, 20, ["blade", "sharp", "metal"],
         "Balta, testere, orak ve bıçağın çeliği.", model="scrap_metal")
    rec("r_blade_blank", "Bıçak dövme", "blade_blank", 2, [I("steel_sheet", 1)], "forge", 2, 8, "metal", "Dövme",
        "Çelik sacı keskin bir ağıza çekersin.")
    comp("pipe_fitting", "Boru Bağlantısı", "component", 1, 0.2, 4, ["fitting", "tube"],
         "Dirsek, manşon, rakor. Su ve gaz tesisatı.", model="iz2_water_pipe_manifold")
    rec("r_pipe_fitting", "Boru bağlantısı", "pipe_fitting", 3, [I("pipe_steel", 1), T("fastener", 2)], "workbench", 1, 4,
        "mekanik", "Tesisat", "Boruyu kesip diş açarsın.")
    comp("valve", "Vana", "component", 2, 0.4, 14, ["mechanical", "fitting"], "Su ve gazı açıp kapatır.",
         model="pipe_valve")
    rec("r_valve", "Vana yapımı", "valve", 1, [I("pipe_fitting", 2), I("spring", 1)], "mechanic", 1, 6, "mekanik",
        "Tesisat", "Şalome ve pompa için.")
    comp("chain", "Zincir", "component", 2, 1.2, 12, ["chain", "binding", "metal"], "Kapı, kapan ve testere zinciri.",
         model="scrap_metal")
    rec("r_chain", "Zincir dövme", "chain", 1, [I("iron_bar", 2)], "forge", 2, 8, "metal", "Dövme", "Halka halka zincir.")
    comp("welding_rod", "Kaynak Çubuğu", "component", 2, 0.05, 3, ["welding", "metal"],
         "Kaynak makinesiyle metal birleştirme ve araç tamiri.", stack=40, model="scrap_metal")
    rec("r_welding_rod", "Kaynak çubuğu", "welding_rod", 6, [I("iron_bar", 1), T("cook_fuel", 1)], "forge", 1, 5,
        "metal", "Bağlantı", "Dekapan kaplı çubuk.")
    comp("mesh_wire", "Tel Örgü", "component", 1, 1.0, 8, ["mesh", "binding"], "Çit, filtre ve takviyeli cam.",
         model="iz2_defense_wire_fence")
    rec("r_mesh_wire", "Tel örme", "mesh_wire", 1, [I("wire_steel", 6)], "workbench", 1, 6, "metal", "Tel",
        "Telleri eşkenar dörtgen örersin.")
    comp("barbed_wire_coil", "Dikenli Tel Rulosu", "component", 2, 1.4, 12, ["barbed", "binding"],
         "Dikenli tel tuzağının ve çitin hammaddesi.", model="iz2_defense_wire_fence")
    rec("r_barbed_wire", "Dikenli tel", "barbed_wire_coil", 1, [I("wire_steel", 4), T("sharp", 4)], "workbench", 1, 6,
        "metal", "Tel", "Tele diken sarılır.")
    comp("armor_plate_steel", "Çelik Zırh Plakası", "component", 3, 2.2, 55, ["armor_layer", "plate", "heavy"],
         "Araç zırhı ve ağır yelek için.", model="steel_barricade")
    rec("r_armor_plate_steel", "Zırh plakası", "armor_plate_steel", 1, [I("steel_sheet", 2), I("rivets", 6)], "forge", 3, 12,
        "metal", "Zırh", "Çift kat çelik, perçinli.")
    comp("reinforced_plate", "Takviyeli Plaka", "component", 2, 1.4, 24, ["plate", "structural_metal"],
         "Araç revizyonu ve sac kapı için.", model="steel_barricade")
    rec("r_reinforced_plate", "Takviyeli plaka", "reinforced_plate", 1, [I("metal_plate", 2), I("iron_bar", 1), I("rivets", 4)],
        "forge", 2, 8, "metal", "Zırh", "Levhaya çubuk kaynatılır.")

    # ------------------------------------------------------------- ahsap
    rec("r_planks_from_log", "Kütük biçme", "wood_plank", 4, [I("wood_log", 1)], "carpentry", 1, 5, "ahsap", "Kereste",
        "Marangoz tezgâhında kütükten dört kalas.")
    rec("r_planks_hand", "Elde kalas biçme", "wood_plank", 2, [I("wood_log", 1), T("tool_saw", 1, tool=True)], "hands", 1, 8,
        "ahsap", "Kereste", "El testeresiyle: yavaş ve fireli.")
    comp("wood_beam", "Ahşap Kiriş", "component", 1, 2.5, 5, ["beam", "wood", "structural"],
         "Kalın taşıyıcı. Kule, iskele ve palisat.", model="wood_bundle")
    rec("r_wood_beam", "Kiriş kesme", "wood_beam", 2, [I("wood_log", 1)], "carpentry", 1, 6, "ahsap", "Kereste",
        "Kütükten kare kiriş.")
    comp("plywood", "Kontrplak", "component", 2, 1.2, 8, ["panel", "wood"], "Katmanlı levha: dolap, raf, kepenk.",
         model="wood_bundle")
    rec("r_plywood", "Kontrplak presleme", "plywood", 2, [I("wood_plank", 3), T("adhesive", 1)], "carpentry", 2, 8,
        "ahsap", "Levha", "İnce kalaslar yapıştırılıp preslenir.")
    comp("wooden_frame", "Ahşap Çerçeve", "component", 1, 1.5, 6, ["frame", "wood"], "Yatak, raf ve saksının iskeleti.",
         model="pallet")
    rec("r_wooden_frame", "Çerçeve çakma", "wooden_frame", 1, [I("wood_plank", 2), I("nail", 4)], "carpentry", 1, 5,
        "ahsap", "Çatkı", "Dört kalas, köşeleri çivili.")
    comp("dowels", "Kavela", "material", 1, 0.01, 1, ["fastener", "wood"], "Ahşap geçme çivisi: metalsiz birleştirme.",
         stack=99, model="wood_bundle", quality=False)
    rec("r_dowels", "Kavela yontma", "dowels", 12, [I("wood_plank", 1)], "carpentry", 1, 4, "ahsap", "Bağlantı",
        "Çivi bitince ahşap kavela.")
    comp("tool_handle", "Alet Sapı", "component", 1, 0.4, 3, ["handle", "wood"], "Balta, kazma, çekiç ve kürek sapı.",
         model="wood_bundle")
    rec("r_tool_handle", "Sap yontma", "tool_handle", 2, [I("wood_plank", 1)], "hands", 1, 4, "ahsap", "Alet parçası",
        "Bıçakla yontulmuş sap.")
    rec("r_charcoal_kiln", "Odun kömürü", "charcoal", 4, [I("wood_log", 2)], "forge", 1, 12, "ahsap", "Yakıt",
        "Havasız yakılan kütük kömüre döner: ocak yakıtı ve filtre.")
    comp("wood_shingle", "Ahşap Kiremit", "component", 1, 0.2, 1, ["roofing", "wood"], "Ahşap çatı kaplaması.",
         stack=40, model="wood_bundle")
    rec("r_wood_shingle", "Ahşap kiremit", "wood_shingle", 6, [I("wood_plank", 2)], "carpentry", 1, 5, "ahsap", "Çatı",
        "İnce yarılmış kalas.")

    # ------------------------------------------------------------- tas ve beton
    comp("mortar", "Harç", "material", 1, 1.0, 3, ["mortar", "mineral"], "Tuğla ve taşı birbirine bağlar.", stack=20,
         model="iz2_item_flour_sack", quality=False)
    rec("r_mortar", "Harç karma", "mortar", 3, [T("lime", 1), I("sand", 2), T("water_raw", 1)], "masonry", 1, 5,
        "yapi_malzemesi", "Harç", "Kireç, kum ve su.")
    comp("concrete_mix", "Beton Harcı", "material", 2, 2.0, 6, ["concrete", "mineral"],
         "Çimento, agrega ve su. Beton ve betonarme duvar için.", stack=12, model="iz2_item_flour_sack", quality=False)
    rec("r_concrete_mix", "Beton karma", "concrete_mix", 4, [I("cement_bag", 1), T("aggregate", 2), I("sand", 2), T("water_raw", 1)],
        "masonry", 1, 8, "yapi_malzemesi", "Beton", "Bir çuval çimentodan dört kova beton.")
    rec("r_cement_kiln", "Ev yapımı çimento", "cement_bag", 1, [I("lime_powder", 2), I("clay", 2), T("cook_fuel", 2)],
        "forge", 3, 16, "yapi_malzemesi", "Beton", "Kireç ve kil yüksek ısıda pişirilir.")
    comp("fired_brick", "Pişmiş Tuğla", "material", 1, 1.3, 2, ["brick_material", "mineral"], "Fırında pişmiş kil tuğla.",
         stack=30, model="rubble_pile", quality=False)
    rec("r_fired_brick", "Tuğla pişirme", "fired_brick", 4, [I("clay", 3), T("cook_fuel", 1)], "forge", 1, 10,
        "yapi_malzemesi", "Tuğla", "Kil kalıplanıp pişirilir.")
    comp("stone_block", "Kesme Taş", "material", 1, 3.0, 4, ["stone_block", "stone"], "Keskiyle düzgün kesilmiş taş.",
         stack=16, model="rubble_pile", quality=False)
    rec("r_stone_block", "Taş kesme", "stone_block", 1, [I("stone_chunk", 3), T("tool_chisel", 1, tool=True)], "masonry", 1, 8,
        "yapi_malzemesi", "Taş", "Sur taşı gibi köşeli blok.")
    comp("rebar_mesh", "Hasır Çelik", "component", 2, 3.0, 14, ["rebar_mesh", "structural_metal"],
         "Betonarmenin iskeleti.", stack=10, model="iz2_defense_wire_fence")
    rec("r_rebar_mesh", "Hasır çelik bağlama", "rebar_mesh", 1, [I("rebar", 3), I("wire_steel", 2)], "forge", 2, 8,
        "yapi_malzemesi", "Beton", "İnşaat demirleri telle bağlanır.")
    comp("cinder_block", "Briket", "material", 1, 2.0, 3, ["block_material", "mineral"], "Beton harcından dökme blok.",
         stack=20, model="rubble_pile", quality=False)
    rec("r_cinder_block", "Briket dökme", "cinder_block", 2, [I("concrete_mix", 1), T("aggregate", 1)], "masonry", 1, 6,
        "yapi_malzemesi", "Beton", "Kalıba dökülüp kurutulur.")
    comp("roof_tile_item", "Kiremit", "material", 1, 0.6, 2, ["roofing", "ceramic"], "Pişmiş kil kiremit.", stack=40,
         model="rubble_pile", quality=False)
    rec("r_roof_tile", "Kiremit pişirme", "roof_tile_item", 4, [I("clay", 2), T("cook_fuel", 1)], "forge", 1, 8,
        "yapi_malzemesi", "Çatı", "Oluklu kalıpta pişmiş kil.")
    rec("r_glass_cast", "Cam dökme", "glass_pane", 1, [I("sand", 4), T("lime", 1), T("cook_fuel", 2)], "forge", 3, 14,
        "yapi_malzemesi", "Cam", "Kum ve kireç çok yüksek ısıda cama döner.")
    comp("tar", "Zift", "material", 1, 1.0, 4, ["sealant", "bitumen"], "Isıtılmış asfalt: çatı ve depo yalıtımı.",
         stack=20, model="fuel_can", quality=False)
    rec("r_tar", "Zift kaynatma", "tar", 1, [I("asphalt_chunk", 2), T("cook_fuel", 1)], "forge", 1, 6, "yapi_malzemesi",
        "Yalıtım", "Asfalt eritilip süzülür.")

    # ------------------------------------------------------------- kumas ve deri
    comp("twine", "Sicim", "material", 1, 0.05, 1, ["binding", "twine", "fiber"], "Bitki lifinden bükülmüş sicim.",
         stack=60, model="cloth_roll", quality=False)
    rec("r_twine", "Sicim bükme", "twine", 2, [I("plant_fiber", 3)], "hands", 1, 3, "kumas", "İp", "Lifleri elde bükersin.")
    comp("rope", "Halat", "component", 1, 0.5, 5, ["binding", "rope"], "Sicimlerin örülmüşü. Merdiven, tuzak, iskele.",
         model="cloth_roll")
    rec("r_rope", "Halat örme", "rope", 1, [I("twine", 3)], "hands", 1, 5, "kumas", "İp", "Üç kat sicim.")
    comp("cloth_bolt", "Kumaş Top", "component", 1, 0.6, 6, ["fabric", "textile"], "Dikilmiş, birleştirilmiş kumaş.",
         model="cloth_roll")
    rec("r_cloth_bolt", "Kumaş dikme", "cloth_bolt", 1, [I("cloth_rag", 4), T("tool_sewing", 1, tool=True)], "workbench", 1, 6,
        "kumas", "Kumaş", "Bezler dikilip top olur.")
    comp("padding_pad", "Dolgu Pedi", "component", 1, 0.2, 5, ["padding", "soft", "insulator"],
         "Zırh astarı ve yatak dolgusu.", model="cloth_roll")
    rec("r_padding_pad", "Dolgu pedi", "padding_pad", 1, [I("foam_padding", 2), I("cloth_rag", 1)], "workbench", 1, 4,
        "kumas", "Dolgu", "Sünger bez içine dikilir.")
    comp("leather_strap", "Deri Kayış", "component", 1, 0.1, 5, ["strap", "binding", "leather"],
         "Kemer, askı, kabza sargısı.", stack=30, model="cloth_roll")
    rec("r_leather_strap", "Kayış kesme", "leather_strap", 3, [I("cured_leather", 1)], "workbench", 1, 4, "kumas", "Deri",
        "İşlenmiş deriden şerit.")
    comp("canvas_sheet", "Branda", "component", 2, 1.0, 12, ["tough_fabric", "tarp", "fabric"],
         "Su geçirmez örtü: yağmur toplayıcı, çadır, çatı.", model="cloth_roll")
    rec("r_canvas_sheet", "Branda dikme", "canvas_sheet", 1, [I("canvas", 3), T("adhesive", 1), T("tool_sewing", 1, tool=True)],
        "workbench", 1, 8, "kumas", "Kumaş", "Kat kat dikilip yapıştırılır.")
    comp("kevlar_panel", "Kevlar Panel", "component", 3, 0.6, 70, ["armor_layer", "ballistic"],
         "Katmanlı aramid: mermi ve ısırık geçirmez.", model="cloth_roll")
    rec("r_kevlar_panel", "Kevlar panel", "kevlar_panel", 1, [I("kevlar_scrap", 3), T("adhesive", 1), T("tool_sewing", 1, tool=True)],
        "workbench", 3, 12, "kumas", "Zırh", "Askerî yelek parçaları yeniden katlanır.")
    comp("rubber_sheet", "Kauçuk Levha", "component", 1, 0.5, 6, ["polymer", "elastic", "rubber_sheet", "insulator"],
         "Conta, yalıtım ve sapan için.", model="car_tire_spare")
    rec("r_rubber_sheet", "Kauçuk levha", "rubber_sheet", 1, [T("rubber_raw", 2)], "forge", 1, 6, "kumas", "Kauçuk",
        "Lastik ısıtılıp düzlenir.")
    comp("plastic_sheet", "Plastik Levha", "component", 1, 0.3, 4, ["polymer", "plastic_sheet", "insulator"],
         "Eritilmiş plastik: gövde, kasa, filtre.", model="electronics")
    rec("r_plastic_sheet", "Plastik eritme", "plastic_sheet", 1, [I("plastic_shard", 6), T("cook_fuel", 1)], "forge", 1, 6,
        "kumas", "Plastik", "Kırık plastik levhaya dökülür.")
    rec("r_insulated_rubber", "Kablo kaplama", "insulated_wire", 3, [I("copper_wire", 2), I("rubber_sheet", 1)], "hands", 1, 5,
        "kumas", "Kauçuk", "Kauçukla kaplanmış bakır: güvenli tesisat.")

    # ------------------------------------------------------------- kimya
    comp("nitrate", "Nitrat", "component", 2, 0.2, 10, ["nitrate", "chemical_oxidizer", "chemical"],
         "Gübreden süzülmüş tuz: barut ve duman karışımı.", model="fertilizer")
    rec("r_nitrate", "Nitrat süzme", "nitrate", 3, [I("fertilizer", 2), T("water_raw", 1)], "chemistry", 2, 10, "kimya",
        "Tuz", "Gübre suda çözülüp kristallenir.")
    rec("r_black_powder", "Kara barut", "refined_powder", 6, [I("nitrate", 2), I("charcoal", 1)], "chemistry", 3, 12,
        "kimya", "Barut", "Klasik barut: nitrat ve kömür.")
    rec("r_loose_powder", "Dökme barut", "gunpowder_loose", 3, [I("nitrate", 1), I("charcoal", 1)], "chemistry", 2, 8,
        "kimya", "Barut", "Kaba barut: bomba ve kapsül için yeterli.")
    comp("ethanol", "Etanol", "material", 2, 0.5, 12, ["chemical_fuel", "solvent", "antiseptic_base", "cook_fuel", "chemical"],
         "Mayalanmış şekerden damıtılmış alkol: yakıt, antiseptik, çözücü.", model="water_bottle", effects={"supply": 1.5},
         quality=False)
    rec("r_ethanol", "Etanol damıtma", "ethanol", 2, [T("sugar_source", 3), T("water_raw", 2)], "chemistry", 2, 16,
        "kimya", "Alkol", "Mayalanır, damıtılır.")
    comp("lye", "Kostik", "component", 1, 0.4, 6, ["lye", "chemical", "corrosive"], "Kül suyundan: sabun ve biyodizel.",
         model="iz2_item_purification_tabs")
    rec("r_lye", "Kül suyu", "lye", 2, [I("charcoal", 2), T("water_raw", 1)], "chemistry", 1, 8, "kimya", "Baz",
        "Kül suyu kaynatılıp koyulaştırılır.")
    comp("soap", "Sabun", "component", 1, 0.2, 5, ["soap", "antiseptic_base", "hygiene"],
         "Yara temizliği ve antiseptik tabanı.", model="soap_dispenser")
    rec("r_soap", "Sabun kaynatma", "soap", 3, [I("cooking_oil", 1), I("lye", 1)], "chemistry", 1, 10, "kimya", "Temizlik",
        "Yağ ve kostik.")
    comp("glue", "Tutkal", "material", 1, 0.2, 4, ["adhesive", "resin"], "Reçineden kaynatılmış doğal yapıştırıcı.",
         stack=20, model="iz2_item_cooking_oil", quality=False)
    rec("r_glue", "Tutkal kaynatma", "glue", 2, [I("resin", 2), T("water_raw", 1)], "cooking", 1, 6, "kimya", "Yapıştırıcı",
        "Reçine suyla eritilir.")
    rec("r_epoxy_resin", "Epoksi karışımı", "epoxy_resin", 2, [I("resin", 2), I("acid_concentrate", 1)], "chemistry", 3, 10,
        "kimya", "Yapıştırıcı", "Sertleştiricili reçine.")
    comp("battery_acid", "Akü Asidi", "component", 2, 0.6, 12, ["electrolyte", "chemical", "corrosive"],
         "Kurşun akü ve akü şarjı için elektrolit.", model="iz2_item_dirty_water_jar")
    rec("r_battery_acid", "Asit seyreltme", "battery_acid", 2, [I("acid_concentrate", 1), T("water_raw", 2)], "chemistry", 2, 6,
        "kimya", "Asit", "Derişik asit dikkatle sulandırılır.")
    rec("r_acid_from_battery", "Akü boşaltma", "acid_concentrate", 2, [I("battery_car", 1)], "chemistry", 2, 10, "kimya",
        "Asit", "Eski aküden asit ve kurşun.", byproducts={"scrap_metal": 2})
    comp("thermite", "Termit", "component", 3, 0.4, 40, ["incendiary_filler", "chemical"],
         "Alüminyum ve pas karışımı: çeliği eritir, suyla sönmez.", model="fuel_can")
    rec("r_thermite", "Termit karışımı", "thermite", 2, [I("aluminum_ingot", 1), I("scrap_metal", 2)], "chemistry", 3, 10,
        "kimya", "Yanıcı", "Alüminyum toz, pas tozu.", failure=0.05)
    comp("smoke_compound", "Duman Karışımı", "component", 2, 0.3, 14, ["smoke_filler", "chemical"],
         "Şeker ve nitrat: yoğun beyaz duman.", model="fertilizer")
    rec("r_smoke_compound", "Duman karışımı", "smoke_compound", 2, [I("sugar_pack", 1), I("nitrate", 1)], "chemistry", 2, 8,
        "kimya", "Yanıcı", "Yavaş yanan karışım.")
    rec("r_chlorine_tabs", "Klor tableti", "purification_tabs", 6, [I("bleach", 1)], "chemistry", 1, 8, "kimya", "Su",
        "Çamaşır suyu kurutulup tabletlenir.")
    rec("r_antiseptic_ethanol", "Etanollü antiseptik", "antiseptic", 2, [I("ethanol", 1), I("herbs", 1)], "chemistry", 2, 8,
        "kimya", "Tıbbi", "Etanol ve şifalı ot.")

    # ------------------------------------------------------------- mekanik
    comp("pulley", "Makara", "component", 2, 0.6, 12, ["mechanical", "pulley"], "Kapan, asansör ve vinç için.",
         model="scrap_metal")
    rec("r_pulley", "Makara", "pulley", 1, [I("iron_bar", 1), I("bearing", 1)], "mechanic", 1, 6, "mekanik", "Parça",
        "Rulmanlı makara.")
    comp("piston", "Piston", "component", 3, 0.8, 30, ["mechanical", "engine_part"], "Kırıcı ve motor için.",
         model="car_engine")
    rec("r_piston", "Piston işleme", "piston", 1, [I("steel_ingot", 1), I("spring_heavy", 1)], "mechanic", 2, 12, "mekanik",
        "Motor", "Silindire oturan çelik piston.")
    comp("pump_unit", "Pompa Ünitesi", "component", 3, 3.0, 45, ["pump", "mechanical"],
         "Elektrikli arıtıcı ve sulama için.", model="iz2_water_pressure_pump")
    rec("r_pump_unit", "Pompa kurma", "pump_unit", 1, [I("motor_small", 1), I("pipe_fitting", 2), I("valve", 1), I("rubber_sheet", 1)],
        "mechanic", 2, 14, "mekanik", "Tesisat", "Motora çark ve conta.")
    comp("crank_shaft", "Krank Mili", "component", 3, 2.4, 40, ["mechanical", "engine_part"],
         "Motor ayarı ve jeneratör için.", model="car_engine")
    rec("r_crank_shaft", "Krank mili", "crank_shaft", 1, [I("axle", 1), I("gear_large", 1)], "mechanic", 3, 14, "mekanik",
        "Motor", "Aks ve dişli birleşir.")
    rec("r_bearing_lathe", "Rulman işleme", "bearing", 3, [I("steel_ingot", 1)], "mechanic", 3, 12, "mekanik", "İşleme",
        "Bilyalı rulman.")
    comp("filter_housing", "Filtre Gövdesi", "component", 1, 0.4, 6, ["filter_part"], "Arıtıcı ve maske filtresi gövdesi.",
         model="iz2_item_filter_cartridge")
    rec("r_filter_housing", "Filtre gövdesi", "filter_housing", 1, [I("pvc_pipe", 1), I("plastic_sheet", 1), T("adhesive", 1)],
        "workbench", 1, 6, "mekanik", "Filtre", "Boru içine yuva.")
    comp("ceramic_filter", "Seramik Filtre Mumu", "component", 2, 0.4, 14, ["ceramic_filter", "filter"],
         "Pişmiş kil filtre: bakteriyi tutar.", model="iz2_item_filter_cartridge")
    rec("r_ceramic_filter", "Seramik filtre", "ceramic_filter", 2, [I("clay", 2), I("charcoal", 1)], "forge", 2, 10,
        "mekanik", "Filtre", "Kömür tozlu kil pişirilir.")
    comp("sand_filter_pack", "Kum Filtre Paketi", "component", 1, 1.0, 4, ["filter"], "Kum ve kömür katmanı.",
         model="iz2_item_filter_cartridge")
    rec("r_sand_filter_pack", "Kum filtre paketi", "sand_filter_pack", 2, [I("sand", 3), I("charcoal", 2), I("cloth_rag", 1)],
        "workbench", 1, 6, "mekanik", "Filtre", "Bez torbaya katman katman.")
    comp("glass_lens", "Mercek", "component", 2, 0.1, 18, ["optics", "lens"], "Zımparalanmış cam: dürbün ve nişangâh.",
         model="iz2_gear_binoculars")
    rec("r_glass_lens", "Mercek taşlama", "glass_lens", 1, [I("glass_pane", 1), I("sand", 1)], "electronics", 2, 10,
        "mekanik", "Optik", "Cam kum ile saatlerce taşlanır.")
