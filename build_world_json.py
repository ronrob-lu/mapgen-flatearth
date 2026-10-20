#!/usr/bin/env python3
"""
build_world_json.py
Generates an anti-aliased, continuous world_map.json from maps/flat_earth_xxl.jpg
for the Luanti Flat Earth mapgen mod (flatearth_mapgen).

World Geometry:
- Quadratic Luanti world: X and Z span from -30912 to +30927 (61840 x 61840 blocks)
- Center is (0, 0) (North Pole)
- The Flat Earth circular map occupies r < 30000 blocks
- The Great Ice Wall: 3 blocks width (30000 <= r <= 30003), 100 blocks high
- Winter Biome: 200 blocks width behind the ice wall (30003 < r <= 30203)
- Green Grasslands: r > 30203 extending all the way to the 4 borders of the quadratic Luanti map
- Spawn Point: New York (USA) at X = -5450, Z = +7790
"""

import sys
import os
import time
import json
import math
import colorsys
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

INPUT_IMAGE = "maps/flat_earth_xxl.jpg"
OUTPUT_JSON = "world_map.json"

GRID_W = 1024
GRID_H = 1024

LUANTI_X_MIN = -30912
LUANTI_X_MAX = 30927
LUANTI_Z_MIN = -30912
LUANTI_Z_MAX = 30927

ICE_WALL_R_MIN = 30000.0
ICE_WALL_R_MAX = 30003.0
WINTER_R_MAX   = 30203.0

BIOME_PALETTE = [
    "ocean",               # 0
    "icesheet",            # 1
    "tundra",              # 2
    "taiga",               # 3
    "coniferous_forest",   # 4
    "deciduous_forest",    # 5
    "grassland",           # 6
    "savanna",             # 7
    "rainforest",          # 8
    "desert",              # 9
    "cold_desert",         # 10
    "sandstone_desert"     # 11
]

BIOME_INDEX = {name: i for i, name in enumerate(BIOME_PALETTE)}

def is_land_pixel(r, g, b, px, py, cx, cy):
    """Accurately identify land vs ocean water in the Flat Earth map."""
    dx = px - cx
    dy = py - cy
    dist = math.hypot(dx, dy)

    # Inset diagram in bottom-left corner of Gleason's map (dark astronomical chart)
    # Geographically this is open South Pacific Ocean
    if dx < -200 and dy > 300 and r < 40 and g < 40 and b < 40:
        return False

    # Outer Antarctica ice ring in Gleason's map (r > 2550)
    if dist >= 2600.0:
        return True

    # Warm hues / colored country tints on land:
    # Yellow / orange / tan / ochre (e.g. North America, Africa, Australia, Asia)
    if r > 175 and g > 135 and b < 125:
        return True
    # Red / terracotta / brown land
    if r > 140 and g < 120 and b < 115:
        return True
    # Green land (vegetation/forests)
    if g > r + 12 and g > b + 10:
        return True
    # Pale tan / beige land
    if r > 190 and g > 165 and b > 110 and (r - b > 35):
        return True
    # Pink / mauve country tints
    if r > 160 and b > 130 and g < r - 15 and g < b - 10:
        return True

    return False

def classify_biome(r, g, b, x, z, r_dist):
    """Classify land pixel into Luanti biome based on true image color and polar geography."""
    lon_deg = math.degrees(math.atan2(x, z))
    lat = 90.0 - (r_dist / 30000.0) * 160.0

    # 1. Outer ice rim & polar caps
    if r_dist >= 26500 or lat < -62.0:
        return "icesheet"
    if r_dist <= 2500 or lat > 78.0:
        return "icesheet"
    if lat > 65.0:
        return "tundra"

    # 2. Deserts (Sahara, Arabia, Australia Outback)
    if 14.0 <= lat <= 34.0 and -15.0 <= lon_deg <= 55.0 and r > 160 and g > 130 and b < 130:
        return "desert"
    if -36.0 <= lat <= -18.0 and 115.0 <= lon_deg <= 145.0:
        return "desert"

    # 3. Rainforests (Equatorial: Amazon, Congo, SE Asia)
    if -15.0 <= lat <= 12.0:
        if -80.0 <= lon_deg <= -35.0:
            return "rainforest"
        if 5.0 <= lon_deg <= 45.0:
            return "rainforest"
        if 95.0 <= lon_deg <= 150.0:
            return "rainforest"

    # 4. Boreal forests / Taiga (Canada, Scandinavia, Siberia)
    if 52.0 <= lat <= 68.0:
        return "taiga"

    # 5. Temperate forests (Eastern North America, Western Europe, East Asia)
    if 30.0 <= lat <= 55.0:
        # Eastern North America (including New York at lat ~40N, lon_deg ~-35)
        if -55.0 <= lon_deg <= -20.0:
            return "deciduous_forest"
        # Western Europe
        if -10.0 <= lon_deg <= 30.0:
            return "deciduous_forest"
        # East Asia
        if 85.0 <= lon_deg <= 135.0:
            return "deciduous_forest"

    # 6. Default by latitude
    if lat < -40.0:
        return "tundra"
    if abs(lat) < 25.0:
        return "savanna"
    return "grassland"

def main():
    start_time = time.time()
    print("=== Luanti Flat Earth Map Generator (flatearth_mapgen) ===")
    print(f"Loading '{INPUT_IMAGE}'...")

    if not os.path.exists(INPUT_IMAGE):
        print(f"Error: {INPUT_IMAGE} not found!", file=sys.stderr)
        sys.exit(1)

    im_orig = Image.open(INPUT_IMAGE)
    orig_w, orig_h = im_orig.size
    print(f"Loaded image: {orig_w}x{orig_h}")
    cx = orig_w / 2.0
    cy = orig_h / 2.0
    r_img_circle = 3000.0  # Image radius corresponding to ICE_WALL_R_MIN (30000 blocks)

    print(f"Building {GRID_W}x{GRID_H} world grid...")
    is_land = [[False] * GRID_W for _ in range(GRID_H)]
    is_special_zone = [[None] * GRID_W for _ in range(GRID_H)]
    pixel_colors = [[(0, 0, 0)] * GRID_W for _ in range(GRID_H)]
    coord_x = [[0.0] * GRID_W for _ in range(GRID_H)]
    coord_z = [[0.0] * GRID_W for _ in range(GRID_H)]
    r_dists = [[0.0] * GRID_W for _ in range(GRID_H)]

    for gy in range(GRID_H):
        z = LUANTI_Z_MAX - (gy / (GRID_H - 1)) * (LUANTI_Z_MAX - LUANTI_Z_MIN)
        for gx in range(GRID_W):
            x = LUANTI_X_MIN + (gx / (GRID_W - 1)) * (LUANTI_X_MAX - LUANTI_X_MIN)
            r = math.hypot(x, z)
            r_dists[gy][gx] = r
            coord_x[gy][gx] = x
            coord_z[gy][gx] = z

            if r >= ICE_WALL_R_MIN and r <= ICE_WALL_R_MAX:
                # 3 blocks width Ice Wall!
                is_special_zone[gy][gx] = "icewall"
                is_land[gy][gx] = True
            elif r > ICE_WALL_R_MAX and r <= WINTER_R_MAX:
                # 200 blocks width Winter Biome behind the Ice Wall!
                is_special_zone[gy][gx] = "winter"
                is_land[gy][gx] = True
            elif r > WINTER_R_MAX:
                # Green grasslands out to the borders!
                is_special_zone[gy][gx] = "grasslands"
                is_land[gy][gx] = True
            else:
                # Inside the known world: sample flat_earth_xxl.jpg
                # Scaling: 10.0 blocks per image pixel
                px = int(cx + (x / ICE_WALL_R_MIN) * r_img_circle)
                py = int(cy - (z / ICE_WALL_R_MIN) * r_img_circle)
                px = max(0, min(orig_w - 1, px))
                py = max(0, min(orig_h - 1, py))

                rgb = im_orig.getpixel((px, py))[:3]
                pixel_colors[gy][gx] = rgb
                is_land[gy][gx] = is_land_pixel(rgb[0], rgb[1], rgb[2], px, py, cx, cy)

    # 8-connected Euclidean Chamfer distance transform for organic smooth coastlines
    print("Computing 8-connected Euclidean Chamfer distance transforms...")
    INF = 9999.0
    SQRT2 = 1.4142

    dist_land = [[INF if is_land[y][x] else 0.0 for x in range(GRID_W)] for y in range(GRID_H)]
    dist_water = [[0.0 if is_land[y][x] else INF for x in range(GRID_W)] for y in range(GRID_H)]

    # Forward pass
    for y in range(GRID_H):
        for x in range(GRID_W):
            if dist_land[y][x] != 0.0:
                d = dist_land[y][x]
                if x > 0: d = min(d, dist_land[y][x - 1] + 1.0)
                if y > 0:
                    d = min(d, dist_land[y - 1][x] + 1.0)
                    if x > 0: d = min(d, dist_land[y - 1][x - 1] + SQRT2)
                    if x < GRID_W - 1: d = min(d, dist_land[y - 1][x + 1] + SQRT2)
                dist_land[y][x] = d

            if dist_water[y][x] != 0.0:
                d = dist_water[y][x]
                if x > 0: d = min(d, dist_water[y][x - 1] + 1.0)
                if y > 0:
                    d = min(d, dist_water[y - 1][x] + 1.0)
                    if x > 0: d = min(d, dist_water[y - 1][x - 1] + SQRT2)
                    if x < GRID_W - 1: d = min(d, dist_water[y - 1][x + 1] + SQRT2)
                dist_water[y][x] = d

    # Backward pass
    for y in range(GRID_H - 1, -1, -1):
        for x in range(GRID_W - 1, -1, -1):
            if dist_land[y][x] != 0.0:
                d = dist_land[y][x]
                if x < GRID_W - 1: d = min(d, dist_land[y][x + 1] + 1.0)
                if y < GRID_H - 1:
                    d = min(d, dist_land[y + 1][x] + 1.0)
                    if x > 0: d = min(d, dist_land[y + 1][x - 1] + SQRT2)
                    if x < GRID_W - 1: d = min(d, dist_land[y + 1][x + 1] + SQRT2)
                dist_land[y][x] = d

            if dist_water[y][x] != 0.0:
                d = dist_water[y][x]
                if x < GRID_W - 1: d = min(d, dist_water[y][x + 1] + 1.0)
                if y < GRID_H - 1:
                    d = min(d, dist_water[y + 1][x] + 1.0)
                    if x > 0: d = min(d, dist_water[y + 1][x - 1] + SQRT2)
                    if x < GRID_W - 1: d = min(d, dist_water[y + 1][x + 1] + SQRT2)
                dist_water[y][x] = d

    print("Classifying biomes and generating continuous signed elevations...")
    raw_elev = [[0.0] * GRID_W for _ in range(GRID_H)]
    biomes = [0] * (GRID_W * GRID_H)

    for y in range(GRID_H):
        row_offset = y * GRID_W
        for x in range(GRID_W):
            idx = row_offset + x
            zone = is_special_zone[y][x]
            r_dist = r_dists[y][x]

            if zone == "icewall":
                # The Great Ice Wall: 100 blocks high!
                raw_elev[y][x] = 100.0
                biomes[idx] = BIOME_INDEX["icesheet"]
            elif zone == "winter":
                # Winter biome for 200 blocks behind the ice wall
                raw_elev[y][x] = 4.0
                biomes[idx] = BIOME_INDEX["tundra"]
            elif zone == "grasslands":
                # Green grasslands afterwards extending to the borders
                raw_elev[y][x] = 3.0
                biomes[idx] = BIOME_INDEX["grassland"]
            elif not is_land[y][x]:
                # Ocean water: continuous signed depth
                d_w = dist_water[y][x]
                depth = -(1.0 + math.log1p(d_w) * 6.5)
                raw_elev[y][x] = max(-30.0, depth)
                biomes[idx] = BIOME_INDEX["ocean"]
            else:
                # Land within the Flat Earth circle
                d_l = dist_land[y][x]
                base_h = 1.0 + math.log1p(d_l) * 2.8
                rgb = pixel_colors[y][x]

                # Outer Antarctica rim: elevated ice plateau
                if r_dist >= 26500:
                    base_h = max(base_h, 8.0)
                    raw_elev[y][x] = min(base_h, 25.0)
                    biomes[idx] = BIOME_INDEX["icesheet"]
                else:
                    raw_elev[y][x] = max(1.0, min(base_h, 55.0))
                    b_name = classify_biome(rgb[0], rgb[1], rgb[2], coord_x[y][x], coord_z[y][x], r_dist)
                    biomes[idx] = BIOME_INDEX[b_name]

    # Gaussian smoothing filter (preserves the sharp ice wall elevation)
    print("Applying anti-aliasing spatial filter...")
    smoothed_elev = [0.0] * (GRID_W * GRID_H)
    kernel = [
        [1.0/16.0, 2.0/16.0, 1.0/16.0],
        [2.0/16.0, 4.0/16.0, 2.0/16.0],
        [1.0/16.0, 2.0/16.0, 1.0/16.0]
    ]

    for y in range(GRID_H):
        row_offset = y * GRID_W
        ym1 = max(0, y - 1)
        yp1 = min(GRID_H - 1, y + 1)
        for x in range(GRID_W):
            idx = row_offset + x
            zone = is_special_zone[y][x]
            if zone == "icewall":
                smoothed_elev[idx] = 100.0
            elif zone == "winter":
                smoothed_elev[idx] = 4.0
            elif zone == "grasslands":
                smoothed_elev[idx] = 3.0
            else:
                xm1 = max(0, x - 1)
                xp1 = min(GRID_W - 1, x + 1)
                val = (kernel[0][0] * raw_elev[ym1][xm1] + kernel[0][1] * raw_elev[ym1][x] + kernel[0][2] * raw_elev[ym1][xp1] +
                       kernel[1][0] * raw_elev[y][xm1]   + kernel[1][1] * raw_elev[y][x]   + kernel[1][2] * raw_elev[y][xp1] +
                       kernel[2][0] * raw_elev[yp1][xm1] + kernel[2][1] * raw_elev[yp1][x] + kernel[2][2] * raw_elev[yp1][xp1])
                smoothed_elev[idx] = round(val, 1)

    print(f"Writing '{OUTPUT_JSON}'...")
    data_dict = {
        "width": GRID_W,
        "height": GRID_H,
        "bounds": {
            "x_min": LUANTI_X_MIN,
            "x_max": LUANTI_X_MAX,
            "z_min": LUANTI_Z_MIN,
            "z_max": LUANTI_Z_MAX,
            "ice_wall_min": ICE_WALL_R_MIN,
            "ice_wall_max": ICE_WALL_R_MAX,
            "winter_max": WINTER_R_MAX
        },
        "spawn": {
            "name": "New York (USA)",
            "x": -5450,
            "y": 5,
            "z": 7790
        },
        "water_level": 0,
        "sea_floor": -30,
        "biome_palette": BIOME_PALETTE,
        "elevations": smoothed_elev,
        "biomes": biomes
    }

    with open(OUTPUT_JSON, "w") as f:
        json.dump(data_dict, f, separators=(",", ":"))

    file_size_mb = os.path.getsize(OUTPUT_JSON) / (1024 * 1024)
    print(f"✓ Successfully generated '{OUTPUT_JSON}' ({file_size_mb:.2f} MB) in {time.time() - start_time:.2f}s total.")

if __name__ == "__main__":
    main()
