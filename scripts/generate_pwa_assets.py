"""Generate platform icons from the full QuickShare Studio logo artwork."""

import os

from PIL import Image


SOURCE = "App Logo.png"
ICON_SIZE = 1024
BACKGROUND = (205, 231, 254)  # #CDE7FE


def render_icon(size: int, safe_zone: bool = False) -> Image.Image:
    """Scale the complete logo without cropping its badge or wordmark."""
    source = Image.open(SOURCE).convert("RGBA")
    source.thumbnail((size, size), Image.Resampling.LANCZOS)

    canvas = Image.new("RGB", (size, size), BACKGROUND)
    if safe_zone:
        # Keep the whole square logo inside Android's central circular safe zone.
        safe_size = int(size * 0.55)
        logo = Image.open(SOURCE).convert("RGBA")
        logo.thumbnail((safe_size, safe_size), Image.Resampling.LANCZOS)
        source = logo

    x = (size - source.width) // 2
    y = (size - source.height) // 2
    canvas.paste(source, (x, y), source)
    return canvas


def save_png(size: int, path: str, safe_zone: bool = False) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    render_icon(size, safe_zone=safe_zone).save(path, "PNG")


def generate() -> None:
    if not os.path.isfile(SOURCE):
        raise FileNotFoundError(f"Cannot find {SOURCE}")

    standard = render_icon(ICON_SIZE)
    maskable = render_icon(ICON_SIZE, safe_zone=True)

    # PWA and Flutter web icons
    for base in ("public/icons", "web/icons"):
        for size in (192, 512):
            standard.resize((size, size), Image.Resampling.LANCZOS).save(
                os.path.join(base, f"icon-{size}.png"), "PNG"
            )
        maskable.resize((512, 512), Image.Resampling.LANCZOS).save(
            os.path.join(base, "icon-512-maskable.png"), "PNG"
        )
        if base == "web/icons":
            maskable.resize((192, 192), Image.Resampling.LANCZOS).save(
                os.path.join(base, "Icon-maskable-192.png"), "PNG"
            )
        standard.resize((180, 180), Image.Resampling.LANCZOS).save(
            os.path.join(base, "apple-touch-icon.png"), "PNG"
        )
        standard.save(
            os.path.join(base, "favicon.ico"),
            format="ICO",
            sizes=[(16, 16), (32, 32), (48, 48), (64, 64)],
        )

    # Flutter also references capitalized web icon filenames.
    for size in (192, 512):
        standard.resize((size, size), Image.Resampling.LANCZOS).save(
            os.path.join("web/icons", f"Icon-{size}.png"), "PNG"
        )
    maskable.resize((512, 512), Image.Resampling.LANCZOS).save(
        "web/icons/Icon-maskable-512.png", "PNG"
    )
    standard.resize((32, 32), Image.Resampling.LANCZOS).save("web/favicon.png", "PNG")

    # Windows desktop, shortcuts, and installer
    standard.save(
        "app_icon.ico",
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    os.makedirs("windows/runner/resources", exist_ok=True)
    standard.save(
        "windows/runner/resources/app_icon.ico",
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    # Android legacy launcher images
    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in android_sizes.items():
        save_png(size, os.path.join("android/app/src/main/res", folder, "ic_launcher.png"))

    # macOS and iOS asset catalogs
    macos_sizes = {
        "app_icon_16.png": 16,
        "app_icon_32.png": 32,
        "app_icon_64.png": 64,
        "app_icon_128.png": 128,
        "app_icon_256.png": 256,
        "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }
    for name, size in macos_sizes.items():
        save_png(size, os.path.join("macos/Runner/Assets.xcassets/AppIcon.appiconset", name))

    ios_sizes = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, size in ios_sizes.items():
        save_png(size, os.path.join("ios/Runner/Assets.xcassets/AppIcon.appiconset", name))

    print("All platform icons generated from the full logo.")


if __name__ == "__main__":
    generate()
