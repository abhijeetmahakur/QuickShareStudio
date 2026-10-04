import os
import cv2
import numpy as np
from PIL import Image

def generate():
    logo_path = 'App Logo.png'
    if not os.path.exists(logo_path):
        raise FileNotFoundError(f"Cannot find {logo_path}")

    img = cv2.imread(logo_path)
    
    # Crop around the symbol
    y0, y1, x0, x1 = 170, 840, 220, 1060
    crop = img[y0:y1, x0:x1].copy()
    h, w = crop.shape[:2]

    # Initialize GrabCut mask
    mask = np.full((h, w), cv2.GC_PR_BGD, dtype=np.uint8)
    mask[:12, :] = cv2.GC_BGD
    mask[-12:, :] = cv2.GC_BGD
    mask[:, :12] = cv2.GC_BGD
    mask[:, -12:] = cv2.GC_BGD

    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    strong_orange = (hsv[:,:,0] >= 8) & (hsv[:,:,0] <= 30) & (hsv[:,:,1] > 90) & (hsv[:,:,2] > 100)
    strong_blue = (hsv[:,:,0] >= 90) & (hsv[:,:,0] <= 130) & (hsv[:,:,1] > 90) & (hsv[:,:,2] > 80)
    strong_dark = (hsv[:,:,2] < 60)
    strong_cyan = (hsv[:,:,0] >= 90) & (hsv[:,:,0] <= 115) & (hsv[:,:,1] > 90) & (hsv[:,:,2] > 140)
    mask[strong_orange | strong_blue | strong_dark | strong_cyan] = cv2.GC_FGD

    # Flood fill outer background
    bg_seeds = (hsv[:,:,1] < 35) & (hsv[:,:,2] > 235)
    bg_conn = np.zeros((h, w), dtype=np.uint8)
    bg_conn[bg_seeds] = 255
    flood = bg_conn.copy()
    cv2.floodFill(flood, None, (0, 0), 128)
    mask[flood == 128] = cv2.GC_BGD

    bgdModel = np.zeros((1, 65), np.float64)
    fgdModel = np.zeros((1, 65), np.float64)
    cv2.grabCut(crop, mask, None, bgdModel, fgdModel, 6, cv2.GC_INIT_WITH_MASK)

    raw_fg = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype('uint8')

    # Remove shadow patch below dark blue curve using color threshold
    sub_shadow = crop[615:645, 200:320]
    shadow_pixels = (sub_shadow[:,:,2] > 22) | (sub_shadow[:,:,1] > 75)
    raw_fg[615:645, 200:320][shadow_pixels] = 0
    raw_fg[630:, 200:320] = 0

    # Filter connected components to remove border glass reflections
    num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(raw_fg)
    clean_mask = np.zeros((h, w), dtype=np.uint8)
    for i in range(1, num_labels):
        area = stats[i, cv2.CC_STAT_AREA]
        bx, by, bw, bh = stats[i, 0], stats[i, 1], stats[i, 2], stats[i, 3]
        if bx == 0 or by == 0 or (bx + bw) >= w or (by + bh) >= h:
            continue
        if area < 100:
            continue
        clean_mask[labels == i] = 255

    # Crop to symbol bounding box
    pts = cv2.findNonZero(clean_mask)
    sx, sy, sw, sh = cv2.boundingRect(pts)
    pad = 4
    sx0, sy0 = max(0, sx - pad), max(0, sy - pad)
    sx1, sy1 = min(w, sx + sw + pad), min(h, sy + sh + pad)

    cropped_rgb = cv2.cvtColor(crop[sy0:sy1, sx0:sx1], cv2.COLOR_BGR2RGB)
    cropped_mask = clean_mask[sy0:sy1, sx0:sx1]

    # Soft Gaussian blur on alpha for anti-aliasing
    alpha = cv2.GaussianBlur(cropped_mask.astype(float), (5, 5), 0.8) / 255.0
    rgba = np.zeros((cropped_rgb.shape[0], cropped_rgb.shape[1], 4), dtype=np.uint8)
    rgba[:, :, :3] = cropped_rgb
    rgba[:, :, 3] = np.clip(alpha * 255, 0, 255).astype(np.uint8)

    sym_pil = Image.fromarray(rgba, 'RGBA')

    # --- 1. Master 1024x1024 Standard Icon with Full-Bleed Gradient ---
    # Centered inside middle 70% (size <= 716 px)
    target_w = 670
    scale = target_w / sym_pil.width
    target_h = int(round(sym_pil.height * scale))
    sym_standard = sym_pil.resize((target_w, target_h), Image.Resampling.LANCZOS)

    top_color = np.array([255, 255, 255], dtype=float)
    bottom_color = np.array([205, 231, 254], dtype=float) # #CDE7FE
    gradient_arr = np.zeros((1024, 1024, 3), dtype=np.uint8)
    for row in range(1024):
        ratio = row / 1023.0
        ease_ratio = ratio ** 1.1
        c = top_color * (1.0 - ease_ratio) + bottom_color * ease_ratio
        gradient_arr[row, :] = np.clip(c, 0, 255).astype(np.uint8)

    master_standard = Image.fromarray(gradient_arr, 'RGB')
    pos_x = (1024 - target_w) // 2
    pos_y = (1024 - target_h) // 2
    master_standard.paste(sym_standard, (pos_x, pos_y), sym_standard)

    # --- 2. Master 1024x1024 Maskable Icon with Solid Background & Safe Zone ---
    # Android maskable safe zone is 80% circle (radius 409.6 px in 1024).
    # Scaled to width 630 px (height ~ 509 px), maximum corner radius is ~ 405 px <= 409.6 px.
    maskable_w = 630
    m_scale = maskable_w / sym_pil.width
    maskable_h = int(round(sym_pil.height * m_scale))
    sym_maskable = sym_pil.resize((maskable_w, maskable_h), Image.Resampling.LANCZOS)

    # Solid light blue background matching the gradient bottom
    solid_bg = Image.new('RGB', (1024, 1024), (205, 231, 254))
    m_pos_x = (1024 - maskable_w) // 2
    m_pos_y = (1024 - maskable_h) // 2
    solid_bg.paste(sym_maskable, (m_pos_x, m_pos_y), sym_maskable)

    # Output directories
    public_icons_dir = os.path.join('public', 'icons')
    web_icons_dir = os.path.join('web', 'icons')
    os.makedirs(public_icons_dir, exist_ok=True)
    os.makedirs(web_icons_dir, exist_ok=True)

    # Export sizes
    # icon-512.png (512x512)
    icon_512 = master_standard.resize((512, 512), Image.Resampling.LANCZOS)
    icon_512.save(os.path.join(public_icons_dir, 'icon-512.png'), 'PNG')
    icon_512.save(os.path.join(web_icons_dir, 'icon-512.png'), 'PNG')
    icon_512.save(os.path.join(web_icons_dir, 'Icon-512.png'), 'PNG')

    # icon-192.png (192x192)
    icon_192 = master_standard.resize((192, 192), Image.Resampling.LANCZOS)
    icon_192.save(os.path.join(public_icons_dir, 'icon-192.png'), 'PNG')
    icon_192.save(os.path.join(web_icons_dir, 'icon-192.png'), 'PNG')
    icon_192.save(os.path.join(web_icons_dir, 'Icon-192.png'), 'PNG')

    # icon-512-maskable.png (512x512)
    icon_512_maskable = solid_bg.resize((512, 512), Image.Resampling.LANCZOS)
    icon_512_maskable.save(os.path.join(public_icons_dir, 'icon-512-maskable.png'), 'PNG')
    icon_512_maskable.save(os.path.join(web_icons_dir, 'icon-512-maskable.png'), 'PNG')
    icon_512_maskable.save(os.path.join(web_icons_dir, 'Icon-maskable-512.png'), 'PNG')

    # icon-maskable-192.png (for Flutter web consistency)
    icon_192_maskable = solid_bg.resize((192, 192), Image.Resampling.LANCZOS)
    icon_192_maskable.save(os.path.join(web_icons_dir, 'Icon-maskable-192.png'), 'PNG')

    # apple-touch-icon.png (180x180)
    apple_touch_icon = master_standard.resize((180, 180), Image.Resampling.LANCZOS)
    apple_touch_icon.save(os.path.join(public_icons_dir, 'apple-touch-icon.png'), 'PNG')
    apple_touch_icon.save(os.path.join(web_icons_dir, 'apple-touch-icon.png'), 'PNG')

    # favicon.ico (multi-resolution ICO: 16, 32, 48, 64)
    ico_sizes = [(16, 16), (32, 32), (48, 48), (64, 64)]
    master_standard.save(os.path.join(public_icons_dir, 'favicon.ico'), format='ICO', sizes=ico_sizes)
    master_standard.save(os.path.join(web_icons_dir, 'favicon.ico'), format='ICO', sizes=ico_sizes)

    # favicon.png in web/
    favicon_png = master_standard.resize((32, 32), Image.Resampling.LANCZOS)
    favicon_png.save(os.path.join('web', 'favicon.png'), 'PNG')

    print("All icon assets generated successfully!")

if __name__ == '__main__':
    generate()
