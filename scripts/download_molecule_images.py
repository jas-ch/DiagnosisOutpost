#!/usr/bin/env python3
"""Download 2D RCSB PDB assembly images and update outbreak_intel.yaml.

For each disease with a pdbId, fetches:
    https://cdn.rcsb.org/images/structures/{pdbIdLower}_assembly-1.jpeg

If the image cannot be fetched, a placeholder is generated instead. The local
path is written back to assets/content/outbreak_intel.yaml as `molecularImage`.
"""

from __future__ import annotations

import io
import os
import re
from pathlib import Path
from typing import Optional
from urllib.request import Request, urlopen
from urllib.error import HTTPError

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError as exc:
    raise SystemExit(
        "Pillow is required. Run: cd backend && source .venv/bin/activate"
    ) from exc


ROOT = Path(__file__).resolve().parents[1]
YAML_PATH = ROOT / "assets" / "content" / "outbreak_intel.yaml"
OUT_DIR = ROOT / "assets" / "images" / "molecules"
RCSB_URL = "https://cdn.rcsb.org/images/structures/{pdb_id}_assembly-1.jpeg"


def fetch_image(pdb_id: str) -> Optional[bytes]:
    url = RCSB_URL.format(pdb_id=pdb_id.lower())
    req = Request(url, headers={"User-Agent": "DiagnosisOutpost/1.0"})
    try:
        with urlopen(req, timeout=30) as resp:
            if resp.status == 200:
                return resp.read()
    except HTTPError as exc:
        print(f"  HTTP {exc.code} for {url}")
    except Exception as exc:
        print(f"  Error fetching {url}: {exc}")
    return None


def make_placeholder(name: str, width: int = 600, height: int = 400) -> bytes:
    img = Image.new("RGB", (width, height), color=(240, 240, 240))
    draw = ImageDraw.Draw(img)

    # Try to load a reasonable font, falling back to the default bitmap font.
    font: ImageFont.FreeTypeFont | ImageFont.ImageFont
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28)
        small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
    except Exception:
        font = ImageFont.load_default()
        small = font

    title = name or "Disease"
    unavailable = "Structure image unavailable"

    # Center text manually.
    def text_size(text: str, fnt):
        bbox = draw.textbbox((0, 0), text, font=fnt)
        return bbox[2] - bbox[0], bbox[3] - bbox[1]

    tw, th = text_size(title, font)
    draw.text(((width - tw) / 2, height / 2 - th - 10), title, fill=(80, 80, 80), font=font)

    uw, uh = text_size(unavailable, small)
    draw.text(((width - uw) / 2, height / 2 + 10), unavailable, fill=(150, 150, 150), font=small)

    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def update_yaml(text: str, mappings: dict[str, str]) -> str:
    """Insert molecularImage lines after the molecularStructure line for each disease."""
    lines = text.splitlines()
    result: list[str] = []
    current_id: Optional[str] = None
    id_pattern = re.compile(r"^- id: (\S+)")

    for line in lines:
        result.append(line)
        m = id_pattern.match(line)
        if m:
            current_id = m.group(1)
        if current_id and line.strip().startswith("molecularStructure:"):
            image_path = mappings.get(current_id)
            if image_path:
                indent = line[: len(line) - len(line.lstrip())]
                result.append(f"{indent}molecularImage: {image_path}")
            current_id = None

    return "\n".join(result) + "\n"


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    text = YAML_PATH.read_text(encoding="utf-8")
    # Parse just enough YAML to get id/pdbId/name tuples.
    import yaml

    data = yaml.safe_load(text)
    items = data.get("outbreak_intel", [])

    mappings: dict[str, str] = {}
    for item in items:
        disease_id = item.get("id")
        pdb_id = item.get("pdbId", "")
        name = item.get("name", disease_id or "")
        if not disease_id:
            continue

        out_path = OUT_DIR / f"{disease_id}.jpg"
        print(f"{disease_id}: pdbId={pdb_id}")

        image_bytes: Optional[bytes] = None
        if pdb_id:
            image_bytes = fetch_image(str(pdb_id))

        if image_bytes:
            out_path.write_bytes(image_bytes)
            print(f"  -> downloaded {out_path}")
        else:
            out_path.write_bytes(make_placeholder(name))
            print(f"  -> placeholder {out_path}")

        mappings[disease_id] = f"assets/images/molecules/{disease_id}.jpg"

    updated = update_yaml(text, mappings)
    YAML_PATH.write_text(updated, encoding="utf-8")
    print(f"\nUpdated {YAML_PATH}")


if __name__ == "__main__":
    main()
