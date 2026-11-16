#!/usr/bin/env python3
"""Draws the tvOS brand assets (layered icon, App Store icon, top shelf art)."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "BackWhenTV" / "Assets.xcassets"
BRAND = ASSETS / "App Icon & Top Shelf Image.brandassets"
FONT = "/System/Library/Fonts/HelveticaNeue.ttc"
CONDENSED_BLACK = 9
CONDENSED_BOLD = 4

BLUE = "#1230b8"
BLUE_DARK = "#0a1c6b"
PANEL = "#0b0f4a"
YELLOW = "#ffd21f"
ORANGE = "#ff9a1f"
ICE = "#b8c6ff"


def font(size: int, index: int = CONDENSED_BLACK) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, max(1, int(size)), index=index)


def color_bars(draw: ImageDraw.ImageDraw, x: int, y: int, width: int, height: int) -> None:
    colors = ["#c0c0c0", "#c0c000", "#00c0c0", "#00c000", "#c000c0", "#c00000", "#0000c0"]
    bar = width / len(colors)
    for i, color in enumerate(colors):
        draw.rectangle([x + i * bar, y, x + (i + 1) * bar, y + height], fill=color)


def back_layer(width: int, height: int) -> Image.Image:
    image = Image.new("RGB", (width, height), BLUE)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(1, height - 1)
        r = int(0x0A + (0x17 - 0x0A) * t)
        g = int(0x1C + (0x38 - 0x1C) * t)
        b = int(0x6B + (0xC8 - 0x6B) * t)
        draw.line([(0, y), (width, y)], fill=(r, g, b))
    return image


def middle_layer(width: int, height: int) -> Image.Image:
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    margin = int(height * 0.065)
    radius = int(height * 0.055)
    border = max(2, int(height * 0.014))
    draw.rounded_rectangle(
        [margin, margin, width - margin, height - margin],
        radius=radius,
        fill=PANEL,
        outline=ORANGE,
        width=border,
    )
    return image


def front_layer(width: int, height: int) -> Image.Image:
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    draw.text(
        (width / 2, height * 0.395),
        "BW",
        font=font(height * 0.46),
        fill=YELLOW,
        anchor="mm",
    )
    draw.text(
        (width / 2, height * 0.675),
        "BACKWHENTV",
        font=font(height * 0.086),
        fill=YELLOW,
        anchor="mm",
    )
    if height >= 320:
        draw.text(
            (width / 2, height * 0.785),
            "CABLE TV, THE WAY YOU REMEMBER IT",
            font=font(height * 0.040, CONDENSED_BOLD),
            fill=ICE,
            anchor="mm",
        )
    color_bars(
        draw,
        int(width * 0.10),
        int(height * 0.885),
        int(width * 0.80),
        max(3, int(height * 0.018)),
    )
    return image


def top_shelf(width: int, height: int) -> Image.Image:
    image = Image.new("RGB", (width, height), "#050b2b")
    draw = ImageDraw.Draw(image)

    for i in range(height):
        t = i / max(1, height - 1)
        r = int(0x05 + (0x12 - 0x05) * t)
        g = int(0x0b + (0x30 - 0x0b) * t)
        b = int(0x2b + (0xb8 - 0x2b) * t)
        draw.line([(0, i), (width, i)], fill=(r, g, b))

    draw.rounded_rectangle(
        [int(width * 0.04), int(height * 0.12), int(width * 0.96), int(height * 0.88)],
        radius=int(height * 0.06),
        outline=ORANGE,
        width=max(4, int(height * 0.012)),
    )

    logo_font = font(int(height * 0.34))
    back, tv = "BackWhen", "TV"
    back_width = draw.textlength(back, font=logo_font)
    tv_width = draw.textlength(tv, font=logo_font)
    logo_x = (width - (back_width + tv_width)) / 2
    logo_y = int(height * 0.42)
    draw.text((logo_x, logo_y), back, font=logo_font, fill="white", anchor="lm")
    draw.text((logo_x + back_width, logo_y), tv, font=logo_font, fill=YELLOW, anchor="lm")

    draw.text(
        (width / 2, int(height * 0.66)),
        "CABLE TV, THE WAY YOU REMEMBER IT",
        font=font(int(height * 0.072), CONDENSED_BOLD),
        fill=ICE,
        anchor="mm",
    )
    color_bars(
        draw,
        int(width * 0.34),
        int(height * 0.76),
        int(width * 0.32),
        max(6, int(height * 0.022)),
    )
    return image


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")
    print(f"wrote {path.relative_to(ROOT)}")


def write_image(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)
    print(f"wrote {path.relative_to(ROOT)} ({image.width}x{image.height})")


def write_stack(name: str, sizes: list[tuple[str, int, int]]) -> None:
    stack = BRAND / f"{name}.imagestack"
    write_json(stack / "Contents.json", {
        "layers": [
            {"filename": "Front.imagestacklayer"},
            {"filename": "Middle.imagestacklayer"},
            {"filename": "Back.imagestacklayer"},
        ],
        "info": {"author": "xcode", "version": 1},
    })

    for layer_name, render in [
        ("Back", back_layer),
        ("Middle", middle_layer),
        ("Front", front_layer),
    ]:
        layer = stack / f"{layer_name}.imagestacklayer"
        write_json(layer / "Contents.json", {
            "content": {"filename": "Content.imageset"},
            "info": {"author": "xcode", "version": 1},
        })
        images = []
        for scale, w, h in sizes:
            filename = f"{layer_name}-{w}x{h}.png"
            write_image(layer / "Content.imageset" / filename, render(w, h))
            images.append({"filename": filename, "idiom": "tv", "scale": scale})
        write_json(layer / "Content.imageset" / "Contents.json", {
            "images": images,
            "info": {"author": "xcode", "version": 1},
        })


def main() -> None:
    write_json(BRAND / "Contents.json", {
        "assets": [
            {
                "filename": "App Icon - App Store.imagestack",
                "idiom": "tv",
                "role": "primary-app-icon",
                "size": "1280x768",
            },
            {
                "filename": "App Icon.imagestack",
                "idiom": "tv",
                "role": "primary-app-icon",
                "size": "400x240",
            },
            {
                "filename": "Top Shelf Image Wide.imageset",
                "idiom": "tv",
                "role": "top-shelf-image-wide",
                "size": "2320x720",
            },
            {
                "filename": "Top Shelf Image.imageset",
                "idiom": "tv",
                "role": "top-shelf-image",
                "size": "1920x720",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    })

    write_stack("App Icon", [("1x", 400, 240), ("2x", 800, 480)])
    write_stack("App Icon - App Store", [("1x", 1280, 768)])

    shelf = BRAND / "Top Shelf Image.imageset"
    write_image(shelf / "TopShelf-1920x720.png", top_shelf(1920, 720))
    write_image(shelf / "TopShelf-3840x1440.png", top_shelf(3840, 1440))
    write_json(shelf / "Contents.json", {
        "images": [
            {"filename": "TopShelf-1920x720.png", "idiom": "tv", "scale": "1x"},
            {"filename": "TopShelf-3840x1440.png", "idiom": "tv", "scale": "2x"},
        ],
        "info": {"author": "xcode", "version": 1},
    })

    wide = BRAND / "Top Shelf Image Wide.imageset"
    write_image(wide / "TopShelfWide-2320x720.png", top_shelf(2320, 720))
    write_image(wide / "TopShelfWide-4640x1440.png", top_shelf(4640, 1440))
    write_json(wide / "Contents.json", {
        "images": [
            {"filename": "TopShelfWide-2320x720.png", "idiom": "tv", "scale": "1x"},
            {"filename": "TopShelfWide-4640x1440.png", "idiom": "tv", "scale": "2x"},
        ],
        "info": {"author": "xcode", "version": 1},
    })


if __name__ == "__main__":
    main()
