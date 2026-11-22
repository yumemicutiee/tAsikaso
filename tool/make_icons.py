"""Makes tAsikaso's launcher and web icons from the logo in assets/brand.

The logo (a plus and an "A") is drawn in the default Navy & Sky colors: the
letters filled sky blue with a navy outline, on a transparent background.
Where a background can't be transparent (Android's adaptive icon, the web's
maskable icons, which iOS uses for the home screen) it is white.

    python3 tool/make_icons.py

Needs Pillow. Writes tool/android_icon/res (copied into the Android project by
tool/setup_android.dart), android/app/src/main/res/mipmap-*/ic_launcher.png
and web/ (favicon and icons).
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SKY = (0x9F, 0xCB, 0xF5, 255)  # Palette.navy's fill
NAVY = (0x1E, 0x3A, 0x6E, 255)  # Palette.navy's deep shade
WHITE = (255, 255, 255, 255)

DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def _tint(mask: Image.Image, color) -> Image.Image:
    out = Image.new('RGBA', mask.size, color)
    out.putalpha(mask.getchannel('A'))
    return out


def logo(fill=SKY, outline=NAVY) -> Image.Image:
    """The logo cropped to its own edges, on transparent."""
    brand = ROOT / 'assets' / 'brand'
    shape = Image.open(brand / 'logo_fill.png').convert('RGBA')
    line = Image.open(brand / 'logo_outline.png').convert('RGBA')
    out = Image.new('RGBA', shape.size, (0, 0, 0, 0))
    if fill is not None:
        out.alpha_composite(_tint(shape, fill))
    out.alpha_composite(_tint(line, outline))
    return out.crop(out.getbbox())


def place(size: int, share: float, background=None, art=None) -> Image.Image:
    """The logo centred on a [size] square, its longer side [share] of it."""
    art = art or logo()
    scale = size * share / max(art.size)
    w, h = round(art.width * scale), round(art.height * scale)
    canvas = Image.new('RGBA', (size, size), background or (0, 0, 0, 0))
    canvas.alpha_composite(art.resize((w, h), Image.LANCZOS),
                           ((size - w) // 2, (size - h) // 2))
    return canvas


def main() -> None:
    res = ROOT / 'tool' / 'android_icon' / 'res'
    # Android 13's themed icons use only the shape: the outline.
    white_mono = logo(fill=None, outline=WHITE)
    for name, k in DENSITIES.items():
        legacy = place(round(48 * k), 0.92)
        for folder in (res, ROOT / 'android' / 'app' / 'src' / 'main' / 'res'):
            (folder / f'mipmap-{name}').mkdir(parents=True, exist_ok=True)
            legacy.save(folder / f'mipmap-{name}' / 'ic_launcher.png')
        # Adaptive icon layers are 108 dp; the launcher shows the middle 66
        # (72 on some), so the logo stays well inside the middle 66 (the safe circle).
        fg = round(108 * k)
        place(fg, 0.46).save(res / f'mipmap-{name}' / 'ic_launcher_foreground.png')
        place(fg, 0.46, art=white_mono).save(
            res / f'mipmap-{name}' / 'ic_launcher_monochrome.png')

    web = ROOT / 'web'
    place(32, 0.96).save(web / 'favicon.png')
    for size in (192, 512):
        place(size, 0.9).save(web / 'icons' / f'Icon-{size}.png')
        # Maskable: full bleed, with the logo inside the 80% safe circle.
        place(size, 0.62, background=WHITE).save(
            web / 'icons' / f'Icon-maskable-{size}.png')


if __name__ == '__main__':
    main()
