"""Istanbul-Z icerik ureticisi -- surucu.

    python fps/tools/content_gen/main.py            # uret + yaz + dogrula
    python fps/tools/content_gen/main.py --check    # yalniz dogrula, yazma

Yazilanlar (deterministik; tekrar calistirmak ayni ciktiyi verir):
  items/gen_*.json, recipes/gen_*.json, weapons/gen_weapons.json, loot/gen_loot.json
  world/build_catalog.json   : blocks KORUNUR; pieces/upgrades yeniden; placeables mevcutla birlestirilir
  world/block_materials.json : pb_* malzemeleri eklenir/guncellenir (eski malzemeler dokunulmaz)
  world/crops.json, world/harvest.json
  world/nutrition.json       : items altina eklenir/guncellenir
  world/item_models.json     : by_id ve weapon_views eklenir/guncellenir
  world/ui_names.json        : categories ve tags eklenir/guncellenir
  world/containers.json      : gen_* havuzlari yeniden eklenir (eski havuzlar korunur)
  Mevcut elle yazilmis esyalarda YALNIZ asagidaki TAG_PATCHES etiketleri eklenir.
"""
from __future__ import annotations

import os
import sys
from collections import OrderedDict

sys.path.insert(0, os.path.dirname(__file__))

from lib import DATA, Registry, load, save  # noqa: E402
import f_materials, f_process, f_power, f_tools, f_build, f_weapons, f_defense, f_food, f_health, f_storage, f_vehicle, f_extra  # noqa: E402,E401

MODULES = [f_materials, f_process, f_power, f_tools, f_build, f_weapons, f_defense, f_food, f_health, f_storage, f_vehicle,
           f_extra]

# Mevcut esyalara eklenen etiketler: yeni tariflerin takim/girdi etiketleri
# eski esyalarla da karsilanabilsin (ornegin alet cantasi cekic sayilir).
TAG_PATCHES = {
    "toolkit": ["tool_hammer", "tool_pliers", "tool_file", "tool_wrench"],
    "soldering_iron": ["tool_solder"],
    "sugar_pack": ["sugar_source"],
    "dried_fruit": ["sugar_source", "fruit"],
    "fertilizer": ["fertilizer"],
    "rubber_strip": ["rubber_raw"],
}

FAMILY_TARGETS = {"build": 180, "process": 100, "tools": 60, "weapons": 80, "defense": 60, "power": 55,
                  "food": 85, "health": 50, "storage": 40, "vehicle": 50}


def existing_item_files() -> dict:
    out = {}
    for name in sorted(os.listdir(os.path.join(DATA, "items"))):
        if name.endswith(".json") and not name.startswith("gen_"):
            for key in load(f"items/{name}"):
                out[key] = f"items/{name}"
    return out


def patch_tags(R: Registry, check_only: bool) -> None:
    files = existing_item_files()
    touched = {}
    for item_id, tags in TAG_PATCHES.items():
        if item_id not in files:
            if item_id in R.items:
                for t in tags:
                    if t not in R.items[item_id]["tags"]:
                        R.items[item_id]["tags"].append(t)
            continue
        rel = files[item_id]
        data = touched.setdefault(rel, load(rel))
        for t in tags:
            if t not in data[item_id]["tags"]:
                data[item_id]["tags"].append(t)
        R.existing_items[item_id] = data[item_id]
    if not check_only:
        for rel, data in touched.items():
            save(rel, data)


def all_items(R: Registry) -> dict:
    d = dict(R.existing_items)
    d.update(R.items)
    return d


def all_tags(items: dict) -> set:
    out = set()
    for it in items.values():
        out.update(it.get("tags", []))
    return out


def validate(R: Registry) -> list:
    errs = []
    items = all_items(R)
    tags = all_tags(items)
    ui = load("world/ui_names.json")
    tag_names = dict(ui.get("tags", {}))
    tag_names.update(R.tags)
    cat_names = dict(ui.get("categories", {}))
    cat_names.update(R.categories)
    blocks = load("world/block_materials.json")
    block_ids = {k for k in blocks if not k.startswith("_")} | set(R.blocks)
    indices = {}
    for k, v in list(blocks.items()) + list(R.blocks.items()):
        if k.startswith("_"):
            continue
        idx = v["index"]
        if idx in indices and indices[idx] != k:
            errs.append(f"blok indeksi cakisiyor: {idx} {indices[idx]} / {k}")
        indices[idx] = k
        if not 1 <= idx <= 254:
            errs.append(f"blok indeksi aralik disi: {k}={idx}")
    weapons = dict(R.existing_weapons)
    weapons.update(R.weapons)

    def need_ok(where, n):
        if "item" in n:
            if n["item"] not in items:
                errs.append(f"{where}: bilinmeyen esya {n['item']}")
        elif "tag" in n:
            if n["tag"] not in tags:
                errs.append(f"{where}: hicbir esyada olmayan etiket {n['tag']}")
            if n["tag"] not in tag_names:
                errs.append(f"{where}: etiketin Turkce adi yok {n['tag']}")
        else:
            errs.append(f"{where}: girdi ne esya ne etiket {n}")

    for rid, r in R.recipes.items():
        if r["output"] not in items:
            errs.append(f"tarif {rid}: cikti yok {r['output']}")
        if r["category"] not in cat_names:
            errs.append(f"tarif {rid}: kategori adi yok {r['category']}")
        for n in r["inputs"]:
            need_ok(f"tarif {rid}", n)
        for b in (r.get("byproducts") or {}):
            if b not in items:
                errs.append(f"tarif {rid}: yan urun yok {b}")
        if r["output"] in [n.get("item") for n in r["inputs"] if n.get("consumed", True)] and r["count"] <= 1:
            errs.append(f"tarif {rid}: cikti kendi girdisi (dongu)")
    for iid, it in R.items.items():
        wid = it.get("weapon_id", "")
        if wid and wid not in weapons:
            errs.append(f"esya {iid}: silah tanimi yok {wid}")
        if it.get("build") and it["build"] not in R.pieces:
            errs.append(f"esya {iid}: yapi parcasi yok {it['build']}")
    for pid, p in R.pieces.items():
        if p["material"] not in block_ids:
            errs.append(f"parca {pid}: malzeme yok {p['material']}")
        for c in p.get("cells", []):
            if len(c) >= 4 and c[3] not in block_ids:
                errs.append(f"parca {pid}: hucre malzemesi yok {c[3]}")
    for mid, up in R.upgrades.items():
        if mid not in block_ids or (up.get("to") and up["to"] not in block_ids):
            errs.append(f"yukseltme {mid}: malzeme yok")
        for part in ("cost", "repair", "salvage"):
            for n in up.get(part, []):
                need_ok(f"yukseltme {mid}.{part}", n)
    for pid, p in R.placeables.items():
        if pid not in items:
            errs.append(f"yerlestirilebilir {pid}: esya yok")
        if p.get("model") not in R.asset_ids:
            errs.append(f"yerlestirilebilir {pid}: model yok {p.get('model')}")
    for iid, m in R.models.items():
        if m not in R.asset_ids:
            errs.append(f"esya modeli yok: {iid} -> {m}")
    for seed, c in R.crops.items():
        if seed not in items or c["yield"] not in items:
            errs.append(f"ekin {seed}: tohum/urun yok")
    for mat, h in R.harvest.items():
        if mat not in block_ids:
            errs.append(f"toplama: malzeme yok {mat}")
        for d in h["drops"]:
            if d["item"] not in items:
                errs.append(f"toplama {mat}: esya yok {d['item']}")
    for d in R.vehicle_salvage + R.fishing:
        if d["item"] not in items:
            errs.append(f"arac sokumu/balik: esya yok {d['item']}")
    for tid, t in R.loot_tables.items():
        for e in t["entries"]:
            if e["item"] not in items:
                errs.append(f"loot {tid}: esya yok {e['item']}")
    ctypes = load("world/containers.json").get("types", {})
    for ctype, tid, _w in R.container_pools:
        if ctype not in ctypes:
            errs.append(f"container tipi yok: {ctype} ({tid})")
    for nid in R.nutrition:
        if nid not in items:
            errs.append(f"besin: esya yok {nid}")
    for it_id, it in R.items.items():
        if it["category"] not in ("material", "component", "assembly", "consumable", "weapon", "ammo", "mod", "tool",
                                  "station", "building", "vehicle_part"):
            errs.append(f"esya {it_id}: gecersiz kategori {it['category']}")
    return errs


def write_all(R: Registry) -> None:
    # --- esya / tarif / silah dosyalari (gen_ onekli; tamamen yeniden yazilir) ---
    for folder in ("items", "recipes", "weapons", "loot"):
        for name in os.listdir(os.path.join(DATA, folder)):
            if name.startswith("gen_") and name.endswith(".json"):
                os.remove(os.path.join(DATA, folder, name))
    by_file: dict[str, OrderedDict] = {}
    for iid, data in R.items.items():
        by_file.setdefault(R.item_file[iid], OrderedDict())[iid] = data
    for rid, data in R.recipes.items():
        by_file.setdefault(R.recipe_file[rid], OrderedDict())[rid] = data
    if R.weapons:
        by_file["weapons/gen_weapons.json"] = OrderedDict(R.weapons)
    if R.loot_tables:
        by_file["loot/gen_loot.json"] = OrderedDict(R.loot_tables)
    for rel, data in by_file.items():
        save(rel, data)

    # --- insa katalogu ---
    cat = load("world/build_catalog.json")
    cat["_readme"] = ("Insa kipi (B) katalogu. 'blocks': dogrudan maliyetli eski bloklar. 'pieces': uretilmis yapi parcasi "
                      "esyasi -> malzeme + hucreler. 'upgrades': malzeme -> ust kademe (cost), onarim (repair), sokum "
                      "iadesi (salvage). 'placeables': esya -> yerlestirilebilir (kind, station/tier, guc...). pieces/upgrades "
                      "ve gen placeables tools/content_gen ile uretilir.")
    cat["pieces"] = OrderedDict(R.pieces)
    cat["upgrades"] = OrderedDict(R.upgrades)
    placeables = OrderedDict((k, v) for k, v in cat.get("placeables", {}).items() if k not in R.placeables)
    placeables.update(R.placeables)
    cat["placeables"] = placeables
    save("world/build_catalog.json", cat)

    blocks = load("world/block_materials.json")
    for mid, b in R.blocks.items():
        blocks[mid] = b
    save("world/block_materials.json", blocks)

    save("world/crops.json", OrderedDict([("_aciklama", "Tohum -> ekin: yield (urun), count [min,max], hours (buyume oyun saati), "
                                           "water_per_day, seed_return (tohum geri donme olasiligi). tools/content_gen uretir.")]
                                         + list(R.crops.items())))
    save("world/harvest.json", OrderedDict([("_aciklama", "Toplama: blok malzemesi -> class (alet sinifi) + drops. Yalniz DUNYA "
                                             "bloklarindan duser (oyuncunun koydugundan degil). vehicle_salvage: hurda arac sokumu."),
                                            ("materials", OrderedDict(R.harvest)),
                                            ("vehicle_salvage", R.vehicle_salvage),
                                            ("fishing", R.fishing)]))

    nut = load("world/nutrition.json")
    for k, v in R.nutrition.items():
        nut["items"][k] = v
    save("world/nutrition.json", nut)

    models = load("world/item_models.json")
    for k, v in R.models.items():
        models["by_id"][k] = v
    for k, v in R.weapon_views.items():
        models["weapon_views"][k] = v
    save("world/item_models.json", models)

    ui = load("world/ui_names.json")
    for k, v in R.categories.items():
        ui["categories"][k] = v
    for k, v in R.tags.items():
        ui["tags"][k] = v
    save("world/ui_names.json", ui)

    cont = load("world/containers.json")
    # Yalniz BU uretecin ekledigi (tip, tablo) ciftleri yenilenir; baska
    # araclarin (city_design/install_classes.py) gen_ havuzlari korunur.
    ours = {(c, t) for c, t, _w in R.container_pools}
    for ctype, tdef in cont["types"].items():
        tdef["pools"] = [p for p in tdef.get("pools", []) if (ctype, str(p[0])) not in ours]
    for ctype, tid, w in R.container_pools:
        cont["types"][ctype]["pools"].append([tid, w])
    save("world/containers.json", cont)


def main() -> int:
    check_only = "--check" in sys.argv
    R = Registry()
    for mod in MODULES:
        mod.build(R)
    patch_tags(R, check_only)
    errs = validate(R)
    # Aile sayimi mevcut tarifleri de kapsar (oyun eski tarifi kategorisinden
    # aileye esler: RecipeDef.CATEGORY_FAMILY).
    cat_family = {"mermi": "weapons", "silah": "weapons", "modifikasyon": "weapons", "atilabilir": "weapons",
                  "elektrik": "process", "elektronik": "process", "metal": "process", "mekanik": "process",
                  "kimya": "process", "kumas": "process", "tibbi": "health", "zirh": "health", "alet": "tools",
                  "insaat": "defense", "istasyon": "storage", "hayatta_kalma": "food"}
    fam = {}
    for r in list(R.recipes.values()) + list(R.existing_recipes.values()):
        f = r.get("family") or cat_family.get(r.get("category", ""), "process")
        fam[f] = fam.get(f, 0) + 1
    total_existing = len(R.existing_recipes)
    print(f"esya: {len(R.items)} yeni (+{len(R.existing_items)} mevcut)  tarif: {len(R.recipes)} yeni "
          f"(+{total_existing} mevcut = {len(R.recipes) + total_existing})")
    for f, target in FAMILY_TARGETS.items():
        print(f"  {f:8s} {fam.get(f, 0):4d} / hedef {target}")
    print(f"  parca {len(R.pieces)}, yukseltme {len(R.upgrades)}, yerlestirilebilir {len(R.placeables)}, "
          f"blok {len(R.blocks)}, ekin {len(R.crops)}, loot {len(R.loot_tables)}")
    if errs:
        print(f"\n{len(errs)} HATA:")
        for e in errs[:200]:
            print("  -", e)
        return 1
    if not check_only:
        write_all(R)
        print("yazildi.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
