"""600 modelin oyunda nerede kullanildigini (veri + kod) listeler.

Kullanim: python fps/tools/asset_usage.py  ->  fps/docs/reports/asset_kullanim.md
Kullanilmayan modeller durustce "kullanilmiyor" olarak yazilir.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "assets" / "istanbul_z_v1"


def main() -> None:
    entries = []
    for name in ("manifest.json", "manifest_additions.json", "manifest_expansion_600.json"):
        data = json.loads((PACK / name).read_text(encoding="utf-8"))
        for e in data["assets"]:
            entries.append((e["id"], e.get("category", "?"), name))
    corpus = {}
    for path in list((ROOT / "data").rglob("*.json")) + list((ROOT / "src").rglob("*.gd")):
        if "map" in path.parts:
            continue
        corpus[path.relative_to(ROOT).as_posix()] = path.read_text(encoding="utf-8")
    used, unused = {}, {}
    for ident, cat, source in entries:
        pat = re.compile(r'["\']' + re.escape(ident) + r'["\']')
        where = [p for p, text in corpus.items() if pat.search(text)]
        (used if where else unused).setdefault(cat, []).append((ident, where, source))
    lines = ["# 600 model kullanim listesi", "",
             f"Toplam {len(entries)} kimlik; veri/kodda adi gecen: {sum(len(v) for v in used.values())}; "
             f"gecmeyen: {sum(len(v) for v in unused.values())}.",
             "Not: ic mekan mobilyalari `interiors.json`, esya modelleri `item_models.json`, zombi/karakter modelleri "
             "kodda ve `colony.json`'da eslenir. Adi gecmeyen model sahnede kullanilmiyor (katalogda var).", "",
             "| Kategori | Kullanilan | Kullanilmayan |", "|---|---:|---:|"]
    for cat in sorted(set(used) | set(unused)):
        lines.append(f"| {cat} | {len(used.get(cat, []))} | {len(unused.get(cat, []))} |")
    lines += ["", "## Kullanilan (yeni 300)", ""]
    for cat in sorted(used):
        for ident, where, source in used[cat]:
            if source == "manifest_expansion_600.json":
                lines.append(f"- `{ident}` ({cat}): {', '.join(where[:3])}")
    lines += ["", "## Kullanilmayan", ""]
    for cat in sorted(unused):
        lines.append(f"- **{cat}**: " + ", ".join(i for i, _, _ in unused[cat]))
    out = ROOT / "docs" / "reports" / "asset_kullanim.md"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(out, sum(len(v) for v in used.values()), "kullaniliyor")


if __name__ == "__main__":
    main()
