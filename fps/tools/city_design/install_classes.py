"""Yeni Istanbul kurum siniflari: bina sinifi, ic yerlesim, oda, mobilya ve
baglamsal container (GELISTIRME ARACI; tekrar calistirilabilir).

    python fps/tools/city_design/install_classes.py

Eklenen siniflar: school, prison, checkpoint, clinic, fortification (dolu sur/
duvar; ic mekan yok). Hastane ve askeri alan kendi yerlesimlerini alir.
Mobilyalar istanbul_z_soft_expansion (iz3_) paketinden; her kurum kendi
container turuyle kendi loot'unu verir (okul: kitap/alet/gida, hapishane:
guvenlik/metal/atolye, hastane: saglik/kimya, askeri: muhimmat/teknik).
"""
import json
import os
from collections import OrderedDict

FPS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
W = os.path.join(FPS, "data", "world")


def load(name):
    with open(os.path.join(W, name), encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=OrderedDict)


def save(name, data):
    with open(os.path.join(W, name), "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def item(asset, place, lo=1, hi=1, chance=None, **extra):
    d = OrderedDict(asset=asset, place=place, count=[lo, hi])
    if chance is not None:
        d["chance"] = chance
    d.update(extra)
    return d


def main():
    classes = load("building_classes.json")
    classes["school"] = {"label": "Okul", "tables": [["gen_school", 5.0], ["apartment_kitchen", 1.0]], "search_seconds": 7.0,
                         "max_searches": 3, "noise_radius": 260.0, "color": [196, 170, 92], "osm_tags": []}
    classes["prison"] = {"label": "Hapishane", "tables": [["gen_prison", 5.0], ["police_locker", 2.0], ["workshop", 1.0]],
                         "search_seconds": 10.0, "max_searches": 3, "noise_radius": 380.0, "color": [112, 96, 104], "osm_tags": []}
    classes["checkpoint"] = {"label": "Kontrol noktası", "tables": [["police_locker", 4.0], ["gen_military_adv", 2.0]],
                             "search_seconds": 6.0, "max_searches": 1, "noise_radius": 300.0, "color": [170, 90, 60], "osm_tags": []}
    classes["clinic"] = {"label": "Sağlık ocağı", "tables": [["pharmacy", 5.0], ["gen_medical_adv", 2.0]], "search_seconds": 6.0,
                         "max_searches": 2, "noise_radius": 240.0, "color": [196, 140, 140], "osm_tags": []}
    classes["fortification"] = {"label": "Sur ve duvar", "tables": [["street_debris", 1.0]], "search_seconds": 4.0,
                                "max_searches": 1, "noise_radius": 150.0, "color": [180, 170, 146], "osm_tags": []}
    save("building_classes.json", classes)

    it = load("interiors.json")
    it["class_layout"].update({"school": "school", "prison": "prison", "checkpoint": "security", "clinic": "clinic",
                               "hospital": "hospital", "military": "military_base"})
    it["layouts"]["school"] = {"label": "Okul", "floor": "floor_tile", "wall": "interior_plaster", "door": "door_entrance_metal",
                               "entry": "classroom", "rooms": [["classroom", "any"], ["school_lab", "small"], ["library", "any"],
                                                               ["school_canteen", "any"]],
                               "room_area": [8, 40], "stairs": True, "density": 1.0, "corridor": True,
                               "repeat": ["classroom", "library", "school_lab"]}
    it["layouts"]["prison"] = {"label": "Hapishane", "floor": "concrete", "wall": "concrete_block", "door": "door_entrance_metal",
                               "entry": "guard_room", "rooms": [["cell", "small"], ["cell", "small"], ["prison_workshop", "any"],
                                                                ["storage", "small"]],
                               "room_area": [6, 24], "stairs": True, "density": 1.0, "corridor": True,
                               "repeat": ["cell", "cell", "guard_room"]}
    it["layouts"]["hospital"] = {"label": "Hastane", "floor": "floor_tile", "wall": "interior_plaster", "door": "door_shop_glass",
                                 "entry": "clinic_room", "rooms": [["ward", "any"], ["hospital_store", "small"], ["clinic_room", "any"]],
                                 "room_area": [8, 36], "stairs": True, "density": 1.0, "corridor": True,
                                 "repeat": ["ward", "ward", "hospital_store"]}
    it["layouts"]["military_base"] = {"label": "Askerî tesis", "floor": "concrete", "wall": "concrete_block",
                                      "door": "door_entrance_metal", "entry": "office",
                                      "rooms": [["barracks", "any"], ["armory_mil", "small"], ["storage", "small"]],
                                      "room_area": [8, 40], "stairs": True, "density": 1.0, "corridor": True,
                                      "repeat": ["barracks", "armory_mil"]}
    lamp = item("fluorescent_fixture", "ceiling")
    it["rooms"].update({
        "classroom": {"label": "Sınıf", "items": [item("iz3_school_board_01", "wall"), item("iz3_school_desk_01", "center", 2, 4),
                                                  item("iz3_school_locker_01", "wall", 1, 2), item("iz3_school_bookcase_01", "wall", 0, 1, 0.6), lamp]},
        "school_lab": {"label": "Laboratuvar", "items": [item("iz3_school_labbench_01", "center", 1, 2), item("iz3_health_cabinet_01", "wall"),
                                                         item("iz3_school_bookcase_02", "wall", 1, 1, 0.7), lamp]},
        "library": {"label": "Kütüphane", "items": [item("iz3_school_bookcase_01", "wall", 2, 4), item("iz3_school_cafetable_01", "center", 1, 2), lamp]},
        "school_canteen": {"label": "Kantin", "items": [item("iz3_school_canteen_01", "wall"), item("iz3_school_cafetable_01", "center", 1, 3),
                                                        item("kitchen_pantry", "wall", 1, 1, 0.6), item("fridge_apartment", "wall", 1, 1, 0.7), lamp]},
        "cell": {"label": "Koğuş", "items": [item("iz3_prison_bunk_01", "wall", 1, 2), item("iz3_prison_toilet_01", "wall"),
                                              item("locker_single", "wall", 1, 1, 0.5)]},
        "guard_room": {"label": "Gardiyan odası", "items": [item("iz3_prison_control_01", "wall"), item("weapon_locker", "wall", 1, 1, 0.6),
                                                            item("locker_double", "wall"), item("filing_cabinet", "wall", 1, 1, 0.7), lamp]},
        "prison_workshop": {"label": "Cezaevi atölyesi", "items": [item("vise_bench", "wall"), item("tool_cabinet", "wall"),
                                                                   item("iz3_prison_bench_01", "center", 1, 2), item("workshop_shelf", "wall", 1, 1, 0.6), lamp]},
        "ward": {"label": "Servis", "items": [item("iz3_health_bed_01", "wall", 2, 3), item("iz3_health_cabinet_01", "wall"),
                                              item("iv_stand", "wall", 1, 1, 0.6), item("iz3_health_oxygen_01", "wall", 1, 1, 0.5), lamp]},
        "hospital_store": {"label": "Hastane deposu", "items": [item("iz3_health_shelf_01", "wall", 1, 2), item("iz3_health_pharmacy_01", "wall"),
                                                                item("iz3_health_cooler_01", "wall", 1, 1, 0.5), lamp]},
        "barracks": {"label": "Koğuş (asker)", "items": [item("iz3_military_bunk_01", "wall", 2, 3), item("footlocker_metal", "wall", 1, 2),
                                                          item("iz3_military_crate_01", "wall", 0, 1, 0.6), lamp]},
        "armory_mil": {"label": "Cephanelik", "items": [item("iz3_military_armory_01", "wall"), item("iz3_military_crate_01", "wall", 2, 3),
                                                        item("weapon_locker", "wall", 1, 1, 0.7), item("iz3_military_radio_01", "wall", 1, 1, 0.4), lamp]},
    })
    furn = it["furniture"]
    for asset, cont in [("iz3_school_locker_01", "school_locker"), ("iz3_school_bookcase_01", "school_shelf"),
                        ("iz3_school_bookcase_02", "school_shelf"), ("iz3_school_labbench_01", "lab_cabinet"),
                        ("iz3_school_canteen_01", "kitchen_cabinet"), ("iz3_health_cabinet_01", "hospital_cabinet"),
                        ("iz3_health_shelf_01", "hospital_cabinet"), ("iz3_health_pharmacy_01", "pharmacy_shelf"),
                        ("iz3_health_cooler_01", "fridge"), ("iz3_military_crate_01", "military_crate"),
                        ("iz3_military_armory_01", "military_crate"), ("iz3_prison_control_01", "prison_locker")]:
        furn[asset] = {"container": cont}
    for asset in ("iz3_school_desk_01", "iz3_school_cafetable_01", "iz3_prison_bunk_01", "iz3_prison_toilet_01",
                  "iz3_prison_bench_01", "iz3_health_bed_01", "iz3_health_oxygen_01", "iz3_military_bunk_01",
                  "iz3_military_radio_01"):
        furn.setdefault(asset, {})
    furn["iz3_school_board_01"] = {"solid": False}
    save("interiors.json", it)

    cont = load("containers.json")
    cont["class_budget"].update({"school": 9, "prison": 10, "checkpoint": 5, "clinic": 8})
    types = cont["types"]

    def ctype(tid, label, verb, secs, pools, share=1.0, noise=14):
        types[tid] = {"label": label, "verb": verb, "search_seconds": secs, "noise_m": noise, "share": share, "pools": pools}
    ctype("school_locker", "Okul dolabı", "Dolabı ara", 3.0, [["gen_school", 6], ["apartment_bedroom", 1]])
    ctype("school_shelf", "Kitaplık", "Rafları ara", 2.5, [["gen_school", 5], ["street_debris", 1]], share=0.8)
    ctype("lab_cabinet", "Laboratuvar tezgâhı", "Çekmeceleri ara", 4.0, [["gen_medical_adv", 3], ["gen_school", 2], ["workshop", 1]], share=1.2)
    ctype("hospital_cabinet", "Hastane dolabı", "Dolabı ara", 4.0, [["gen_medical_adv", 5], ["pharmacy", 3]], share=1.4)
    ctype("military_crate", "Askerî sandık", "Sandığı aç", 6.0, [["military_crate", 5], ["gen_military_adv", 3]], share=1.6, noise=22)
    ctype("prison_locker", "Kontrol masası", "Masayı ara", 4.0, [["gen_prison", 6], ["police_locker", 2]], share=1.2)
    save("containers.json", cont)
    print("kurum siniflari kuruldu")


if __name__ == "__main__":
    main()
