"""Istanbul-Z icerik ureticisi: ortak kayit defteri ve yardimcilar.

Uretici GELISTIRME ARACIDIR: data/ altina sabit JSON yazar; oyun acilisinda
hicbir sey uretilmez. Her calistirma ayni ciktiyi verir (deterministik).
Uretilen dosyalar `gen_` onekiyle ayrilir; elle yazilmis eski dosyalar
yalnizca acikca belirtilen alanlarda guncellenir (bkz. write_all).
"""
from __future__ import annotations

import json
import os
from collections import OrderedDict

FPS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(FPS, "data")
ASSETS = os.path.join(FPS, "assets")


def load(rel: str):
    with open(os.path.join(DATA, rel), encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=OrderedDict)


def save(rel: str, data, compact: bool = False) -> None:
    path = os.path.join(DATA, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        if compact:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        else:
            json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")


class Registry:
    def __init__(self) -> None:
        self.items: "OrderedDict[str, dict]" = OrderedDict()
        self.item_file: dict[str, str] = {}
        self.recipes: "OrderedDict[str, dict]" = OrderedDict()
        self.recipe_file: dict[str, str] = {}
        self.placeables: "OrderedDict[str, dict]" = OrderedDict()
        self.pieces: "OrderedDict[str, dict]" = OrderedDict()
        self.upgrades: "OrderedDict[str, dict]" = OrderedDict()
        self.weapons: "OrderedDict[str, dict]" = OrderedDict()
        self.nutrition: "OrderedDict[str, dict]" = OrderedDict()
        self.crops: "OrderedDict[str, dict]" = OrderedDict()
        self.harvest: "OrderedDict[str, dict]" = OrderedDict()
        self.vehicle_salvage: list = []
        self.fishing: list = []              # olta av tablosu (ilk tutan)
        self.blocks: "OrderedDict[str, dict]" = OrderedDict()
        self.models: dict[str, str] = {}
        self.weapon_views: dict[str, str] = {}
        self.loot_tables: "OrderedDict[str, dict]" = OrderedDict()
        self.container_pools: list = []     # (container_type, table_id, weight)
        self.class_tables: list = []        # (building_class, table_id, weight)
        self.categories: dict[str, str] = {}
        self.tags: dict[str, str] = {}
        self.existing_items = self._existing("items")
        self.existing_recipes = self._existing("recipes")
        self.existing_weapons = self._existing("weapons")
        self.asset_ids = self._asset_ids()
        im = load("world/item_models.json")
        self.existing_models = dict(im.get("by_id", {}))
        # Mevcut esyanin modeli oyundaki sirayla: by_id, by_tag, by_category.
        for iid, it in self.existing_items.items():
            if iid in self.existing_models:
                continue
            for tag in it.get("tags", []):
                if tag in im.get("by_tag", {}):
                    self.existing_models[iid] = im["by_tag"][tag]
                    break
            else:
                if it.get("category") in im.get("by_category", {}):
                    self.existing_models[iid] = im["by_category"][it["category"]]

    # --- mevcut veri ---
    @staticmethod
    def _existing(folder: str) -> dict:
        out = {}
        for name in sorted(os.listdir(os.path.join(DATA, folder))):
            if not name.endswith(".json") or name.startswith("gen_"):
                continue
            data = load(f"{folder}/{name}")
            for key, value in data.items():
                out[key] = value
        return out

    @staticmethod
    def _asset_ids() -> set:
        ids = set()
        for pack, files in [("istanbul_z_v1", ["manifest.json", "manifest_additions.json", "manifest_expansion_600.json"]),
                            ("istanbul_z_soft_expansion", ["manifest_soft_expansion.json"])]:
            for fname in files:
                path = os.path.join(ASSETS, pack, fname)
                if os.path.exists(path):
                    with open(path, encoding="utf-8") as f:
                        for a in json.load(f).get("assets", []):
                            ids.add(a["id"])
        return ids

    def model(self, *candidates: str) -> str:
        """Ilk VAR OLAN asset kimligi. iz3 kisa adlari (\"production/workbench_01\") cozulur."""
        for c in candidates:
            if c in self.asset_ids:
                return c
            # Esya kimligi verildiyse o esyanin modeli kullanilir.
            if c in self.models:
                return self.models[c]
            if c in self.existing_models and self.existing_models[c] in self.asset_ids:
                return self.existing_models[c]
            if "/" in c:
                cat, suffix = c.split("/", 1)
                # "handheld/<ad>": el aletleri ve ekipman iz3_tool_/iz3_gear_ altinda.
                prefixes = ["iz3_tool_", "iz3_gear_"] if cat == "handheld" else ["iz3_" + cat + "_"]
                for p in prefixes:
                    if p + suffix in self.asset_ids:
                        return p + suffix
                for aid in sorted(self.asset_ids):
                    if aid.startswith("iz3_" + cat) and aid.endswith("_" + suffix):
                        return aid
        raise KeyError(f"asset bulunamadi: {candidates}")

    def has_item(self, item_id: str) -> bool:
        return item_id in self.items or item_id in self.existing_items

    def item_tags(self, item_id: str) -> list:
        src = self.items.get(item_id) or self.existing_items.get(item_id) or {}
        return list(src.get("tags", []))

    # --- kayit ---
    def item(self, file: str, item_id: str, name: str, category: str, tier: int, weight: float, value: float,
             tags: list, desc: str, stack: int = 1, model: str = "", **extra) -> str:
        if item_id in self.items or item_id in self.existing_items:
            raise ValueError(f"esya kimligi cakisiyor: {item_id}")
        data = OrderedDict(name=name, category=category, tier=tier, stack=stack, weight=weight, value=value,
                           tags=list(tags), description=desc)
        for k, v in extra.items():
            if v is None or v == {} or v == []:
                continue
            data[k] = v
        self.items[item_id] = data
        self.item_file[item_id] = file
        if model:
            self.models[item_id] = model
        return item_id

    def recipe(self, family: str, recipe_id: str, name: str, output: str, count: int, inputs: list,
               station: str, tier: int, time: float, category: str, sub: str, desc: str,
               learn: str = "", power: float = 0.0, failure: float = 0.0, quality_bonus: float = 0.0,
               byproducts: dict | None = None, max_batch: int = 0) -> str:
        if recipe_id in self.recipes or recipe_id in self.existing_recipes:
            raise ValueError(f"tarif kimligi cakisiyor: {recipe_id}")
        data = OrderedDict(name=name, output=output, count=count, station=station)
        if station != "hands":
            data["station_tier"] = tier
        data["time"] = time
        data["category"] = category
        data["family"] = family
        data["subcategory"] = sub
        data["inputs"] = inputs
        data["description"] = desc
        if learn:
            data["learn"] = learn
        if power:
            data["power"] = power
        if failure:
            data["failure_chance"] = failure
        if quality_bonus:
            data["quality_bonus"] = quality_bonus
        if byproducts:
            data["byproducts"] = byproducts
        if max_batch:
            data["max_batch"] = max_batch
        self.recipes[recipe_id] = data
        self.recipe_file[recipe_id] = f"recipes/gen_{family}.json"
        return recipe_id

    def category(self, cat_id: str, name: str) -> str:
        self.categories[cat_id] = name
        return cat_id

    def tag(self, tag: str, name: str) -> str:
        self.tags[tag] = name
        return tag


def I(item: str, count: int = 1, q: float = 0, tool: bool = False) -> dict:
    d = OrderedDict(item=item, count=count)
    if q:
        d["min_quality"] = q
    if tool:
        d["consumed"] = False
    return d


def T(tag: str, count: int = 1, q: float = 0, tool: bool = False) -> dict:
    d = OrderedDict(tag=tag, count=count)
    if q:
        d["min_quality"] = q
    if tool:
        d["consumed"] = False
    return d
