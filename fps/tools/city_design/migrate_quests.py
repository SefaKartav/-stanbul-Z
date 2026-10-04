"""Gorevleri gercek Istanbul yer adlarindan yeni sabit POI kimliklerine tasir
(GELISTIRME ARACI; tekrar calistirilabilir -- zaten tasinmis metne dokunmaz).

    python fps/tools/city_design/migrate_quests.py

  * Capalar: "place:Kadikoy iskele meydani" -> "place:rihtim_iskele" (class:,
    roof:, water: bicimlerindeki yer adi da).
  * Metinler: kurgusal semt adlari (Rıhtım, Feneraltı, Çarşıbaşı...).
  * data/quests/place_roles.json: ESKI haritalar (maltepe_besiktas, kadikoy)
    icin kimlik -> eski yer adi ve metin geri cevirisi. Eski kayitlar kendi
    haritasinda ayni gorev zinciriyle oynanmaya devam eder.
"""
import json
import os
from collections import OrderedDict

FPS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
Q = os.path.join(FPS, "data", "quests", "quests.json")
ROLES = os.path.join(FPS, "data", "quests", "place_roles.json")

PLACES = OrderedDict([
    ("Kadikoy iskele meydani", "rihtim_iskele"), ("Moda burnu", "feneralti_burnu"), ("Haydarpasa gari", "liman_gari"),
    ("Uskudar meydan", "carsibasi_meydan"), ("Besiktas iskele", "saraykapi_iskele"), ("Caddebostan", "bademlik_sahil"),
    ("Bostanci sahil", "kalebend_sahil"), ("Maltepe sahil", "martikoy_sahil"),
])
TEXT = [
    ("15 Temmuz Sehitler Koprusu", "Martı Köprüsü"), ("Kadikoy'un", "Rıhtım'ın"), ("Moda'daki", "Feneraltı'ndaki"),
    ("Moda'da", "Feneraltı'nda"), ("Caddebostan'da", "Bademlik'te"), ("Uskudar'da", "Çarşıbaşı'nda"),
    ("Besiktas'taki", "Saraykapı'daki"), ("Bostanci'nin adi bostandan gelir.", "Kalebend'in bostanları eskiden bütün yakayı doyururdu."),
    ("Bostanci karakolunun", "Kalebend karakolunun"), ("Bostanci bostani", "Kalebend bostanı"),
    ("Avrupa yakasina", "batı yakasına"), ("Avrupa yakasinda", "batı yakasında"), ("ISKI'de", "Su İdaresi'nde"),
    ("Kadikoy iskele meydani", "Rıhtım İskele Meydanı"), ("Maltepe sahil", "Martıköy sahili"),
    ("Bostanci sahil", "Kalebend sahili"), ("Uskudar meydan", "Çarşıbaşı meydanı"),
    ("Haydarpasa", "Liman"), ("Besiktas", "Saraykapı"), ("Uskudar", "Çarşıbaşı"), ("Caddebostan", "Bademlik"),
    ("Moda", "Feneraltı"), ("Kadikoy", "Rıhtım"), ("Bostanci", "Kalebend"), ("Maltepe", "Martıköy"),
]
ANCHOR_KEYS = ("anchor",)


def fix_anchor(spec: str) -> str:
    parts = spec.split(":")
    return ":".join(PLACES.get(p, p) for p in parts)


def fix_text(text: str) -> str:
    for old, new in TEXT:
        text = text.replace(old, new)
    return text


def walk(node, key=""):
    if isinstance(node, dict):
        return OrderedDict((k, walk(v, k)) for k, v in node.items())
    if isinstance(node, list):
        return [walk(v, key) for v in node]
    if isinstance(node, str):
        if key in ANCHOR_KEYS:
            return fix_anchor(node)
        if key in ("id", "event", "item", "flag", "requires", "stage", "type", "profile", "recipe"):
            return node
        return fix_text(node)
    return node


def main():
    with open(Q, encoding="utf-8") as f:
        q = json.load(f, object_pairs_hook=OrderedDict)
    q = walk(q)
    with open(Q, "w", encoding="utf-8", newline="\n") as f:
        json.dump(q, f, ensure_ascii=False, indent=1)
        f.write("\n")
    legacy = {"places": {v: k for k, v in PLACES.items()}, "text": [[new, old] for old, new in TEXT]}
    roles = OrderedDict([
        ("_aciklama", "Gorev yer kimlikleri yeni sabit haritanin (yeni_istanbul) POI kimlikleridir. Eski haritalar "
                      "icin: kimlik -> eski yer adi (places) ve gosterilen metnin geri cevirisi (text: [yeni, eski])."),
        ("maltepe_besiktas", legacy), ("kadikoy", legacy),
    ])
    with open(ROLES, "w", encoding="utf-8", newline="\n") as f:
        json.dump(roles, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("gorevler tasindi")


if __name__ == "__main__":
    main()
