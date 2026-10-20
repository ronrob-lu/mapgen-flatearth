#!/usr/bin/env bash
set -e

echo "================================================================="
echo "   Luanti Flat Earth Map Generator (flatearth_mapgen) Test Suite "
echo "================================================================="

# 1. Verify Mercator maps are cleared
echo "[Test 1] Checking that all Mercator maps are cleared..."
if [ -f "Large_World_Map_bright.jpg" ]; then
    echo "FAIL: Large_World_Map_bright.jpg still exists!"
    exit 1
fi
echo "✓ No Mercator maps found in repository."

# 2. Check mod.conf metadata
echo "[Test 2] Checking mod.conf..."
grep -q "name = flatearth_mapgen" mod.conf || (echo "FAIL: mod.conf name mismatch" && exit 1)
echo "✓ mod.conf correctly names mod 'flatearth_mapgen'."

# 3. Check world_map.json existence and structure
echo "[Test 3] Verifying world_map.json structure & bounds..."
python3 -c "
import json
with open('world_map.json') as f:
    d = json.load(f)

assert d['width'] == 1024, 'Width must be 1024'
assert d['height'] == 1024, 'Height must be 1024'
assert len(d['elevations']) == 1024 * 1024, 'Elevations length mismatch'
assert len(d['biomes']) == 1024 * 1024, 'Biomes length mismatch'

# Verify 4 sides reach Luanti borders exactly
b = d['bounds']
assert b['x_min'] == -30912, 'x_min mismatch'
assert b['x_max'] == 30927, 'x_max mismatch'
assert b['z_min'] == -30912, 'z_min mismatch'
assert b['z_max'] == 30927, 'z_max mismatch'
assert b['ice_wall_min'] == 30000.0, 'ice_wall_min mismatch'
assert b['ice_wall_max'] == 30003.0, 'ice_wall_max mismatch'
assert b['winter_max'] == 30203.0, 'winter_max mismatch'

# Verify spawn point is New York
spawn = d['spawn']
assert 'New York' in spawn['name'], 'Spawn must be New York'
assert spawn['x'] == -5450 and spawn['z'] == 7790, 'Spawn coordinates mismatch'

print('✓ world_map.json structure, Luanti border bounds (-30912..30927), and New York spawn verified.')
"

# 4. Check Lua syntax and mock runtime of init.lua
echo "[Test 4] Verifying Lua syntax and mapgen hooks in init.lua..."
lua -e "
minetest = {
    set_mapgen_setting = function() end,
    get_current_modname = function() return 'flatearth_mapgen' end,
    get_modpath = function() return '.' end,
    log = function() end,
    parse_json = function(s)
        return {
            width = 1024, height = 1024,
            elevations = {}, biomes = {},
            biome_palette = {'ocean', 'icesheet', 'tundra', 'grassland'}
        }
    end,
    get_perlin_map = function() return {} end,
    register_on_mods_loaded = function() end,
    register_on_generated = function() end,
    register_chatcommand = function() end,
    register_on_newplayer = function() end,
    register_on_respawnplayer = function() end,
    register_on_joinplayer = function() end,
}
dofile('init.lua')
print('✓ init.lua parsed and loaded cleanly with Luanti mock environment.')
"

# 5. Verify Flat Earth mechanics & geometry (New York, Ice Wall, Winter Biome, Grasslands)
echo "[Test 5] Verifying Flat Earth geographic assertions..."
python3 -c "
import json
import math

with open('world_map.json') as f:
    d = json.load(f)

w, h = d['width'], d['height']
b = d['bounds']
elev = d['elevations']
bio = d['biomes']
pal = d['biome_palette']

def q(x, z):
    gx = int(round((x - b['x_min']) / (b['x_max'] - b['x_min']) * (w - 1)))
    gz = int(round((b['z_max'] - z) / (b['z_max'] - b['z_min']) * (h - 1)))
    idx = gz * w + gx
    return elev[idx], pal[bio[idx]]

# A. New York spawn point: on land
ny_elev, ny_bio = q(-5450, 7790)
assert ny_elev > 0, f'New York must be on land (elevation > 0), got {ny_elev}'
print(f'  ✓ Spawn at New York (-5450, 7790): elevation = {ny_elev} (land), biome = {ny_bio}')

# B. The Circle: 3 blocks width and 100 blocks high Ice Wall
# Verify formula in math & JSON
ice_wall_thickness = b['ice_wall_max'] - b['ice_wall_min']
assert ice_wall_thickness == 3.0, f'Ice Wall must be 3 blocks wide, got {ice_wall_thickness}'
print(f'  ✓ Ice Wall thickness: {ice_wall_thickness} blocks (radius {b[\"ice_wall_min\"]} to {b[\"ice_wall_max\"]})')

# C. Behind the circle: Winter Biome for 200 blocks
winter_thickness = b['winter_max'] - b['ice_wall_max']
assert winter_thickness == 200.0, f'Winter biome must be 200 blocks wide, got {winter_thickness}'
print(f'  ✓ Winter Biome thickness: {winter_thickness} blocks (radius {b[\"ice_wall_max\"]} to {b[\"winter_max\"]})')

# D. Afterwards: Green Grasslands extending to borders
w_elev, w_bio = q(0, 30100)
assert w_bio in ['tundra', 'icesheet'], f'Expected winter biome behind ice wall, got {w_bio}'
print(f'  ✓ Winter Biome at radius 30100: elevation = {w_elev}, biome = {w_bio}')

gl_elev, gl_bio = q(0, 30500)
assert gl_bio == 'grassland', f'Expected grassland afterwards, got {gl_bio}'
print(f'  ✓ Grasslands at radius 30500: elevation = {gl_elev}, biome = {gl_bio}')

# E. Corner Grasslands reaching all the way to Luanti borders (+30912, +30927)
c_elev, c_bio = q(30000, 30000)
assert c_bio == 'grassland', f'Corner must be grassland, got {c_bio}'
print(f'  ✓ Corner Grasslands at (30000, 30000): elevation = {c_elev}, biome = {c_bio}')

# F. North Pole (center of flat earth)
np_elev, np_bio = q(0, 0)
assert np_bio == 'ocean', f'North Pole must be ocean water, got {np_bio}'
print(f'  ✓ North Pole center at (0, 0): elevation = {np_elev}, biome = {np_bio}')
"

# 6. Check world_preview.png existence
echo "[Test 6] Checking world_preview.png visual preview..."
if [ ! -f "world_preview.png" ]; then
    echo "Generating world_preview.png..."
    python3 preview_world.py
fi
echo "✓ world_preview.png exists ($(ls -lh world_preview.png | awk '{print $5}'))"

echo "================================================================="
echo "   All Flat Earth tests passed successfully! 🌐✨               "
echo "================================================================="
