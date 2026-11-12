"""Build the app's static fonts from the variable web fonts in Fonts/source.

The Kairos desktop app ships Jost and Cormorant Garamond Italic as variable
WOFF2 files (both under the SIL Open Font License, texts beside them). iOS
wants plain TTF files with one weight each, so this script cuts the weights
the app uses and writes them to KairosAgents/Resources/Fonts.

Needs: fonttools and brotli (the workflow installs pinned versions).
"""
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Fonts" / "source"
OUT = ROOT / "KairosAgents" / "Resources" / "Fonts"

# (source file, family, style name, PostScript name, weight)
CUTS = [
    ("Jost-Variable.woff2", "Jost", "Regular", "Jost-Regular", 400),
    ("Jost-Variable.woff2", "Jost", "Medium", "Jost-Medium", 500),
    ("Jost-Variable.woff2", "Jost", "SemiBold", "Jost-SemiBold", 600),
    ("CormorantGaramond-Italic-Variable.woff2", "Cormorant Garamond", "Medium Italic",
     "CormorantGaramond-MediumItalic", 500),
    ("CormorantGaramond-Italic-Variable.woff2", "Cormorant Garamond", "SemiBold Italic",
     "CormorantGaramond-SemiBoldItalic", 600),
]


def set_name(font, name_id, value):
    table = font["name"]
    table.setName(value, name_id, 3, 1, 0x409)  # Windows, Unicode, US English
    table.setName(value, name_id, 1, 0, 0)      # Mac, Roman, English


def cut(source, family, style, ps_name, weight):
    font = TTFont(SOURCE / source)
    font.flavor = None
    if "fvar" in font:
        axes = {axis.axisTag: axis for axis in font["fvar"].axes}
        pins = {}
        for tag, axis in axes.items():
            if tag == "wght":
                pins[tag] = max(axis.minValue, min(axis.maxValue, weight))
            else:
                pins[tag] = axis.defaultValue
        font = instantiateVariableFont(font, pins, inplace=False)
    # One family name per file keeps each cut addressable by its PostScript name.
    full = f"{family} {style}"
    for name_id in (16, 17, 21, 22, 25):
        font["name"].removeNames(nameID=name_id)
    set_name(font, 1, full)
    set_name(font, 2, "Italic" if "Italic" in style else "Regular")
    set_name(font, 3, f"{ps_name};Kairos")
    set_name(font, 4, full)
    set_name(font, 6, ps_name)
    font["OS/2"].usWeightClass = weight
    target = OUT / f"{ps_name}.ttf"
    font.save(target)
    print(f"{target.name}: {target.stat().st_size} bytes")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for row in CUTS:
        cut(*row)


if __name__ == "__main__":
    main()
