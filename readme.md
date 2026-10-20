# 🧊 Luanti Flat Earth Map Generator (`flatearth_mapgen`) 🌐

> ### 📜 **Conspiracy Theory Disclaimer & Historical Context**
> **Notice**: The "Flat Earth" model is a well-known conspiracy theory and scientifically debunked concept (our real Earth is an oblate spheroid). However, historical cartographic maps based on azimuthal equidistant polar projections—such as Alexander Gleason's 1892 *New Standard Map of the World* or 20th-century "Air Age" global charts—exist as fascinating historical and artistic artifacts. Because **Luanti** (formerly Minetest) is inherently built upon a quadratic (square) coordinate space, this circular polar projection suits the voxel engine exceptionally well. **We resemble and recreate these historic flat earth maps in voxel form for creative exploration, cartographic appreciation, and fun gameplay!**

---

Ever wondered what it would be like to stand before a colossal **100-block-high Ice Wall**, voyage from **New York** to the **North Pole**, or venture beyond the known world into uncharted frozen tundras and endless green grasslands?

**`flatearth_mapgen`** transforms the entire Luanti universe into a full-scale, playable Flat Earth world spanning all **61,840 blocks** from border to border!

---

## 🌟 Key Features

### 🗺️ **Full Quadratic World Alignment (All 4 Borders)**
Unlike conventional Mercator maps that leave awkward horizontal bands, the Flat Earth map naturally fills Luanti's quadratic coordinate boundaries:
- **X Boundaries**: From `-30912` to `+30927` (61,840 blocks span).
- **Z Boundaries**: From `-30912` to `+30927` (61,840 blocks span).
- **Center `(0, 0)`**: The Arctic North Pole at the true center of the world disk.
- **All 4 Sides**: Extend completely and symmetrically to the edges of the Luanti world.

### 🧊 **The Great Ice Wall (3 Blocks Wide, 100 Blocks High)**
Circling the entire perimeter of the known continents at radius $R = 30,000$ blocks stands the legendary **Ice Wall**:
- **Width**: Exactly **3 blocks wide** ($30,000 \le r \le 30,003$).
- **Height**: A towering vertical barrier rising **100 blocks high** ($Y = 100$) made of solid `default:ice`!
- Traps the oceans and borders the known world just like in historical flat earth lore.

### ❄️ **The 200-Block Winter Biome**
Immediately behind the Great Ice Wall lies a desolate frozen expanse:
- **Span**: Exactly **200 blocks wide** ($30,003 < r \le 30,203$).
- **Biome**: Freezing winter tundra & ice sheet covered in snow blocks, ice, and dusting snow.

### 🌿 **The Endless Green Grasslands**
Beyond the winter biome ($r > 30,203$), the world blossoms into endless rolling green plains:
- **Span**: Extends outward across all 4 cardinal directions and into the distant corners of the quadratic Luanti world (over **13,500 blocks deep** in the corners!).
- **Biome**: Temperate `grassland` with lush green dirt and grass blocks (`default:dirt_with_grass`).

### 🗽 **Spawning Point: New York (USA)**
- All new and returning players safely spawn on land in **New York** (`X = -5450, Z = 7790`, Elevation $Y \approx 5$).
- If a player ever falls into the ocean or gets stuck, automatic safety hooks safely rescue and relocate them to New York.
- Instant shortcuts `/spawn` or `/newyork` bring you back home anytime.

---

## 🧭 In-Game Commands & Fast Travel

| Command | Description |
| :--- | :--- |
| `/spawn` or `/newyork` | Teleport to the default spawn point in **New York (USA)** (`X=-5450, Z=7790`) |
| `/icewall` | Teleport directly to the base of the **100-block-high Ice Wall** |
| `/winter` | Teleport to the **Winter Biome** behind the Ice Wall |
| `/grasslands` | Teleport to the **Green Grasslands** beyond the known world |
| `/northpole` | Teleport to the **North Pole** at the center of the world `(0, 0)` |
| `/flatearth [location]` | Teleport to major landmarks (`london`, `paris`, `cairo`, `tokyo`, `sydney`) |
| `/flatearth list` | Display all available destinations |
| `/flatearth info` | Display current coordinate, distance to North Pole, zone, elevation, and biome |
| `/goto <lat> <lon>` | Teleport to any real-world coordinates converted to Flat Earth polar space |
| `/fly` | Grant fly, fast, and noclip privileges (`K` to fly, `J` for fast) |
| `/flyspeed <multiplier>` | Set flying speed multiplier (e.g. `/flyspeed 10` or `/flyspeed 20`) |

---

## 🔍 Visual Preview & Validation Tools

### Top-Down Visual Preview (`preview_world.py`)
Generate a full $1024 \times 1024$ top-down rendering of the entire Luanti quadratic space:
```bash
python3 preview_world.py
```
This produces **`world_preview.png`**, displaying:
- Continents, mountain ranges, and oceans shaded by elevation and depth.
- The red spawn point marker in **New York**.
- The shimmering **Ice Wall circle**.
- The **200-block snowy winter ring**.
- The outer **green grasslands** reaching all 4 corners and borders!

### Dataset Builder (`build_world_json.py`)
Generates the preprocessed, compact **`world_map.json`** directly from `maps/flat_earth_xxl.jpg`:
```bash
python3 build_world_json.py
```

### Automated Test Suite (`test_plan.sh`)
Run the comprehensive test plan validating bounds, spawn coordinates, ice wall dimensions, winter biome thickness, grasslands, and Lua syntax:
```bash
./test_plan.sh
```

---

## 🚀 Installation & Setup

1. **Prerequisites**:
   - Luanti (formerly Minetest) 5.0+.
   - `minetest_game` (provides `default`) and `biomegen` (included in `source_mods/biomegen`).
2. **Installation**:
   - Clone or copy this folder into your Luanti `mods/` directory as `flatearth_mapgen`.
3. **Activation**:
   - In Luanti world settings, enable **`flatearth_mapgen`** (or add `load_mod_flatearth_mapgen = true` in `world.mt`).
4. **Enter & Explore**:
   - Join your world to spawn in New York, type `/flatearth info` or `/icewall`, and begin your voyage!
