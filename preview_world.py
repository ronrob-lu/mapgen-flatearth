#!/usr/bin/env python3
"""
preview_world.py
Renders a top-down visual map preview of the entire Luanti Flat Earth world (61840x61840)
directly to 'world_preview.png' for instant worldwide inspection.
"""

import sys
import json
import math
from PIL import Image, ImageDraw

PREVIEW_SIZE = 1024  # Preview image resolution (1024x1024 quadratic world)

# Color mapping for each biome
BIOME_COLORS = {
    "ocean":             (28, 120, 200),
    "icesheet":          (230, 242, 255),
    "tundra":            (175, 190, 180),
    "taiga":             (45, 95, 45),
    "coniferous_forest": (35, 110, 60),
    "deciduous_forest":  (75, 155, 45),
    "grassland":         (100, 180, 55),
    "savanna":           (195, 175, 75),
    "rainforest":        (20, 110, 30),
    "desert":            (225, 195, 115),
    "cold_desert":       (175, 160, 130),
    "sandstone_desert":  (210, 160, 95),
}

def smoothstep(t):
    return t * t * (3.0 - 2.0 * t)

def main():
    print("Loading world_map.json...")
    with open("world_map.json") as f:
        map_data = json.load(f)

    w = map_data["width"]
    h = map_data["height"]
    elevations = map_data["elevations"]
    biomes = map_data["biomes"]
    palette = map_data["biome_palette"]

    bounds = map_data.get("bounds", {})
    x_min = bounds.get("x_min", -30912)
    x_max = bounds.get("x_max", 30927)
    z_min = bounds.get("z_min", -30912)
    z_max = bounds.get("z_max", 30927)

    ice_wall_r = bounds.get("ice_wall_min", 30000.0)
    winter_r = bounds.get("winter_max", 30203.0)

    print(f"Generating {PREVIEW_SIZE}x{PREVIEW_SIZE} full world preview (Luanti coordinates {x_min} to {x_max})...")
    img = Image.new("RGB", (PREVIEW_SIZE, PREVIEW_SIZE))
    pixels = img.load()

    span_x = x_max - x_min
    span_z = z_max - z_min

    for py in range(PREVIEW_SIZE):
        z = z_max - (py / (PREVIEW_SIZE - 1)) * span_z
        gz = (z_max - z) / span_z * (h - 1)
        gz0 = int(math.floor(gz))
        gz1 = min(h - 1, gz0 + 1)
        tz = gz - gz0
        sz = smoothstep(tz)

        for px in range(PREVIEW_SIZE):
            x = x_min + (px / (PREVIEW_SIZE - 1)) * span_x
            r = math.hypot(x, z)

            # 1. Ice Wall (drawn with a visible ring width in preview)
            if abs(r - ice_wall_r) <= 120.0:
                # The Great 100-block high Ice Wall (shimmering bright ice)
                pixels[px, py] = (210, 245, 255)
                continue

            # 2. Winter Biome (behind the ice wall for 200 blocks)
            if ice_wall_r < r <= winter_r + 150.0:
                # Frozen snowy tundra
                pixels[px, py] = (225, 235, 245)
                continue

            # 3. Outer Green Grasslands (stretching out to the 4 borders)
            if r > winter_r + 150.0:
                # Lush green grasslands
                pixels[px, py] = (90, 175, 50)
                continue

            # 4. Known Flat Earth map (within the ice wall)
            gx = (x - x_min) / span_x * (w - 1)
            gx0 = int(math.floor(gx))
            gx1 = min(w - 1, gx0 + 1)
            tx = gx - gx0
            sx = smoothstep(tx)

            idx00 = gz0 * w + gx0
            idx10 = gz0 * w + gx1
            idx01 = gz1 * w + gx0
            idx11 = gz1 * w + gx1

            h00 = elevations[idx00]
            h10 = elevations[idx10]
            h01 = elevations[idx01]
            h11 = elevations[idx11]

            elev = (1.0 - sx) * (1.0 - sz) * h00 \
                 + sx * (1.0 - sz) * h10 \
                 + (1.0 - sx) * sz * h01 \
                 + sx * sz * h11

            b00 = palette[biomes[idx00]]
            b10 = palette[biomes[idx10]]
            b01 = palette[biomes[idx01]]
            b11 = palette[biomes[idx11]]

            c00 = BIOME_COLORS.get(b00, (100, 100, 100))
            c10 = BIOME_COLORS.get(b10, (100, 100, 100))
            c01 = BIOME_COLORS.get(b01, (100, 100, 100))
            c11 = BIOME_COLORS.get(b11, (100, 100, 100))

            cr = (1.0 - sx) * (1.0 - sz) * c00[0] + sx * (1.0 - sz) * c10[0] + (1.0 - sx) * sz * c01[0] + sx * sz * c11[0]
            cg = (1.0 - sx) * (1.0 - sz) * c00[1] + sx * (1.0 - sz) * c10[1] + (1.0 - sx) * sz * c01[1] + sx * sz * c11[1]
            cb = (1.0 - sx) * (1.0 - sz) * c00[2] + sx * (1.0 - sz) * c10[2] + (1.0 - sx) * sz * c01[2] + sx * sz * c11[2]

            if elev <= 0.0:
                depth_factor = max(0.45, min(1.0, 1.0 + elev / 45.0))
                oc = BIOME_COLORS["ocean"]
                pixels[px, py] = (int(oc[0] * depth_factor), int(oc[1] * depth_factor), int(oc[2] * depth_factor))
            else:
                height_factor = min(1.4, 1.0 + (elev / 50.0) * 0.35)
                pixels[px, py] = (min(255, int(cr * height_factor)), min(255, int(cg * height_factor)), min(255, int(cb * height_factor)))

    # Mark New York (Spawn) with a gold/red marker
    draw = ImageDraw.Draw(img)
    spawn_x = -5450
    spawn_z = 7790
    sp_px = int((spawn_x - x_min) / span_x * (PREVIEW_SIZE - 1))
    sp_py = int((z_max - spawn_z) / span_z * (PREVIEW_SIZE - 1))
    r_mk = 5
    draw.ellipse([sp_px - r_mk, sp_py - r_mk, sp_px + r_mk, sp_py + r_mk], fill=(255, 30, 30), outline=(255, 255, 255))

    out_file = "world_preview.png"
    img.save(out_file)
    print(f"✓ Saved full world map visual preview to '{out_file}' (Spawn marked at New York: {sp_px}, {sp_py})!")

if __name__ == "__main__":
    main()
