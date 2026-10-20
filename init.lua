--[[
    Flat Earth Map Generator for Luanti (flatearth_mapgen)
    Generates a full-scale Flat Earth map in Luanti from preprocessed world_map.json.

    World Geometry:
    - Quadratic Luanti world: X and Z span from -30912 to +30927 (61840 x 61840 blocks)
    - Center (0, 0) is the North Pole.
    - Inside the circle (r < 30000 blocks): The known continents and oceans of Earth,
      modeled after historical azimuthal equidistant polar maps (e.g. Gleason's 1892 map).
    - The Great Ice Wall (30000 <= r <= 30003): Exactly 3 blocks wide and 100 blocks high,
      surrounding the known world in a towering ring of solid ice.
    - The Winter Biome (30003 < r <= 30203): A frozen expanse of snow and ice stretching
      for 200 blocks behind the ice wall.
    - Green Grasslands (r > 30203): Endless lush green plains extending out to all 4
      borders of the quadratic Luanti world (-30912 to +30927).
    - Default Spawn Point: New York (USA) at X = -5450, Z = +7790.
--]]

-- Set v7 mapgen settings so biomes and decorations are properly registered
minetest.set_mapgen_setting("mg_name", "v7", true)
minetest.set_mapgen_setting("mg_flags", "nocaves, nodungeons, nodecorations, nolight", true)
minetest.set_mapgen_setting("water_level", "0", true)

local modname = minetest.get_current_modname() or "flatearth_mapgen"
local modpath = minetest.get_modpath(modname) or "."

-- Luanti world bounds (all 4 sides span the full square map)
local LUANTI_X_MIN = -30912
local LUANTI_X_MAX = 30927
local LUANTI_Z_MIN = -30912
local LUANTI_Z_MAX = 30927

local ICE_WALL_R_MIN = 30000
local ICE_WALL_R_MAX = 30003   -- Exactly 3 blocks wide
local ICE_WALL_HEIGHT = 100    -- Exactly 100 blocks high
local WINTER_R_MAX   = 30203   -- Exactly 200 blocks wide behind the ice wall

local SEA_LEVEL = 0
local SEA_FLOOR = -30

-- Biome climate baseline palette
local biome_climate_palette = {
    [0]  = {heat = 50, humid = 50, name = "ocean"},
    [1]  = {heat = 0,  humid = 73, name = "icesheet"},
    [2]  = {heat = 0,  humid = 40, name = "tundra"},
    [3]  = {heat = 25, humid = 70, name = "taiga"},
    [4]  = {heat = 45, humid = 70, name = "coniferous_forest"},
    [5]  = {heat = 60, humid = 68, name = "deciduous_forest"},
    [6]  = {heat = 50, humid = 35, name = "grassland"},
    [7]  = {heat = 89, humid = 42, name = "savanna"},
    [8]  = {heat = 86, humid = 65, name = "rainforest"},
    [9]  = {heat = 92, humid = 16, name = "desert"},
    [10] = {heat = 40, humid = 0,  name = "cold_desert"},
    [11] = {heat = 60, humid = 0,  name = "sandstone_desert"},
}

-- Load preprocessed world_map.json
minetest.log("action", "[" .. modname .. "] Loading world_map.json...")
local json_path = modpath .. "/world_map.json"
local json_file = io.open(json_path, "r")
if not json_file then
    error("[" .. modname .. "] CRITICAL: Could not find '" .. json_path .. "'. Run 'python3 build_world_json.py' first!")
end

local json_content = json_file:read("*a")
json_file:close()

local map_data = minetest.parse_json(json_content)
if not map_data then
    error("[" .. modname .. "] CRITICAL: Failed to parse '" .. json_path .. "'!")
end

local MAP_W = map_data.width or 1024
local MAP_H = map_data.height or 1024
local MAP_W_M1 = MAP_W - 1
local MAP_H_M1 = MAP_H - 1

local elevations = map_data.elevations
local biomes = map_data.biomes
local biome_palette = map_data.biome_palette

local MAP_SCALE_X = MAP_W_M1 / (LUANTI_X_MAX - LUANTI_X_MIN)
local MAP_SCALE_Z = MAP_H_M1 / (LUANTI_Z_MAX - LUANTI_Z_MIN)

minetest.log("action", string.format("[%s] Loaded Flat Earth map grid: %dx%d cells (%d total points)",
    modname, MAP_W, MAP_H, #elevations))

-- Domain Warping noise to give coastlines organic, fractal, natural curves
local np_warp_x = {
    offset = 0,
    scale = 35.0,
    spread = {x = 180, y = 180, z = 180},
    seed = 52719,
    octaves = 3,
    persist = 0.5,
    lacunarity = 2.0,
}
local np_warp_z = {
    offset = 0,
    scale = 35.0,
    spread = {x = 180, y = 180, z = 180},
    seed = 98124,
    octaves = 3,
    persist = 0.5,
    lacunarity = 2.0,
}

local np_fine_relief = {
    offset = 0,
    scale = 2.0,
    spread = {x = 32, y = 32, z = 32},
    seed = 44210,
    octaves = 3,
    persist = 0.55,
    lacunarity = 2.0,
}

local nobj_warp_x, nobj_warp_z, nobj_fine_relief = nil, nil, nil
local pnoise_warp_x, pnoise_warp_z = nil, nil
local nvals_warp_x = {}
local nvals_warp_z = {}
local nvals_fine_relief = {}

local function smoothstep(t)
    return t * t * (3.0 - 2.0 * t)
end

-- Interpolates terrain elevation, heat, and humidity with continuous cubic Hermite blending
local function get_smooth_terrain_info(raw_x, raw_z)
    local r = math.sqrt(raw_x * raw_x + raw_z * raw_z)

    -- 1. The Great Ice Wall: 100 blocks high
    if r >= ICE_WALL_R_MIN and r <= ICE_WALL_R_MAX then
        return ICE_WALL_HEIGHT, 0, 75, "icesheet"
    end

    -- 2. Winter Biome behind the Ice Wall (200 blocks wide)
    if r > ICE_WALL_R_MAX and r <= WINTER_R_MAX then
        return 4.0, 0, 75, "tundra"
    end

    -- 3. Green Grasslands out to the 4 borders of the Luanti map
    if r > WINTER_R_MAX then
        return 3.0, 55, 60, "grassland"
    end

    -- 4. Inside the Known Flat Earth World (r < 30000): query grid with Hermite smoothing
    local gx = (raw_x - LUANTI_X_MIN) * MAP_SCALE_X
    local gz = (LUANTI_Z_MAX - raw_z) * MAP_SCALE_Z

    if gx < 0 then gx = 0 elseif gx > MAP_W_M1 then gx = MAP_W_M1 end
    if gz < 0 then gz = 0 elseif gz > MAP_H_M1 then gz = MAP_H_M1 end

    local gx0 = math.floor(gx)
    local gz0 = math.floor(gz)
    local gx1 = (gx0 < MAP_W_M1) and (gx0 + 1) or gx0
    local gz1 = (gz0 < MAP_H_M1) and (gz0 + 1) or gz0

    local tx = gx - gx0
    local tz = gz - gz0

    local sx = smoothstep(tx)
    local sz = smoothstep(tz)

    local idx00 = gz0 * MAP_W + gx0 + 1
    local idx10 = gz0 * MAP_W + gx1 + 1
    local idx01 = gz1 * MAP_W + gx0 + 1
    local idx11 = gz1 * MAP_W + gx1 + 1

    local h00 = elevations[idx00] or 0
    local h10 = elevations[idx10] or 0
    local h01 = elevations[idx01] or 0
    local h11 = elevations[idx11] or 0

    local h = (1.0 - sx) * (1.0 - sz) * h00
            + sx * (1.0 - sz) * h10
            + (1.0 - sx) * sz * h01
            + sx * sz * h11

    local b00 = biomes[idx00] or 0
    local b10 = biomes[idx10] or 0
    local b01 = biomes[idx01] or 0
    local b11 = biomes[idx11] or 0

    local c00 = biome_climate_palette[b00] or biome_climate_palette[0]
    local c10 = biome_climate_palette[b10] or biome_climate_palette[0]
    local c01 = biome_climate_palette[b01] or biome_climate_palette[0]
    local c11 = biome_climate_palette[b11] or biome_climate_palette[0]

    local heat = (1.0 - sx) * (1.0 - sz) * c00.heat
               + sx * (1.0 - sz) * c10.heat
               + (1.0 - sx) * sz * c01.heat
               + sx * sz * c11.heat

    local humid = (1.0 - sx) * (1.0 - sz) * c00.humid
                + sx * (1.0 - sz) * c10.humid
                + (1.0 - sx) * sz * c01.humid
                + sx * sz * c11.humid

    local dom_idx = (tx < 0.5) and ((tz < 0.5) and idx00 or idx01)
                               or ((tz < 0.5) and idx10 or idx11)
    local b_id = biomes[dom_idx] or 0
    local b_name = biome_palette[b_id + 1] or "ocean"

    return h, heat, humid, b_name
end

-- Content IDs
local c_stone, c_water, c_air
local c_ice, c_snowblock, c_snow
local c_dirt, c_dirt_with_grass

minetest.register_on_mods_loaded(function()
    c_stone = minetest.get_content_id("mapgen_stone")
    c_water = minetest.get_content_id("mapgen_water_source")
    c_air   = minetest.get_content_id("air")

    c_ice             = minetest.get_content_id("default:ice")
    c_snowblock       = minetest.get_content_id("default:snowblock")
    c_snow            = minetest.get_content_id("default:snow")
    c_dirt            = minetest.get_content_id("default:dirt")
    c_dirt_with_grass = minetest.get_content_id("default:dirt_with_grass")

    if PerlinNoise then
        pnoise_warp_x = PerlinNoise(np_warp_x)
        pnoise_warp_z = PerlinNoise(np_warp_z)
    end

    if biomegen then
        local orig_calc = biomegen.calc_biome_from_noise
        biomegen.calc_biome_from_noise = function(heat, humid, pos)
            local r = math.sqrt(pos.x * pos.x + pos.z * pos.z)
            if r >= ICE_WALL_R_MIN and r <= ICE_WALL_R_MAX then
                return "icesheet"
            elseif r > ICE_WALL_R_MAX and r <= WINTER_R_MAX then
                return "tundra"
            elseif r > WINTER_R_MAX then
                return "grassland"
            end

            local wx, wz = 0, 0
            if pnoise_warp_x and pnoise_warp_z then
                wx = pnoise_warp_x:get_2d({x = pos.x, y = pos.z})
                wz = pnoise_warp_z:get_2d({x = pos.x, y = pos.z})
            end
            local _, c_heat, c_humid, _ = get_smooth_terrain_info(pos.x + wx, pos.z + wz)
            return orig_calc(c_heat, c_humid, pos)
        end

        if debug and debug.getupvalue and debug.setupvalue and biomegen.get_biome_at_index then
            local i = 1
            while true do
                local n, _ = debug.getupvalue(biomegen.get_biome_at_index, i)
                if not n then break end
                if n == "calc_biome_from_noise" then
                    debug.setupvalue(biomegen.get_biome_at_index, i, function(heat, humid, pos)
                        return biomegen.calc_biome_from_noise(heat, humid, pos)
                    end)
                    break
                end
                i = i + 1
            end
        end
        minetest.log("action", "[" .. modname .. "] Hooked into biomegen for living Flat Earth biomes!")
    end
end)

-- Reusable voxel data buffer
local data = {}

-- Mapgen chunk generation
minetest.register_on_generated(function(minp, maxp, seed)
    -- Allow chunks up to Y = 110 so the 100-block high Ice Wall generates completely!
    if minp.y > 110 then
        return
    end

    local voxelmanip, emin, emax = minetest.get_mapgen_object("voxelmanip")
    local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
    voxelmanip:get_data(data)

    -- Quick check: chunk completely deep underground
    if maxp.y < SEA_FLOOR - 2 then
        local vi_start = area:index(minp.x, minp.y, minp.z)
        local vi_end = area:index(maxp.x, maxp.y, maxp.z)
        for vi = vi_start, vi_end do
            data[vi] = c_stone
        end
        voxelmanip:set_data(data)
        voxelmanip:set_lighting({day = 0, night = 0})
        voxelmanip:write_to_map()
        return
    end

    local sidelen_x = maxp.x - minp.x + 1
    local sidelen_z = maxp.z - minp.z + 1
    local permapdims2d = {x = sidelen_x, y = sidelen_z, z = 1}
    local minp2d = {x = minp.x, y = minp.z}

    nobj_warp_x = nobj_warp_x or minetest.get_perlin_map(np_warp_x, permapdims2d)
    nobj_warp_z = nobj_warp_z or minetest.get_perlin_map(np_warp_z, permapdims2d)
    nobj_fine_relief = nobj_fine_relief or minetest.get_perlin_map(np_fine_relief, permapdims2d)

    nobj_warp_x:get_2d_map_flat(minp2d, nvals_warp_x)
    nobj_warp_z:get_2d_map_flat(minp2d, nvals_warp_z)
    nobj_fine_relief:get_2d_map_flat(minp2d, nvals_fine_relief)

    local noise_idx = 1
    local ystride = area.ystride

    for z = minp.z, maxp.z do
        for x = minp.x, maxp.x do
            local r = math.sqrt(x * x + z * z)
            local vi = area:index(x, minp.y, z)

            if r >= ICE_WALL_R_MIN and r <= ICE_WALL_R_MAX then
                -- 1. THE GREAT ICE WALL: 3 blocks width, 100 blocks high!
                for y = minp.y, maxp.y do
                    if y <= ICE_WALL_HEIGHT then
                        data[vi] = c_ice
                    else
                        data[vi] = c_air
                    end
                    vi = vi + ystride
                end

            elseif r > ICE_WALL_R_MAX and r <= WINTER_R_MAX then
                -- 2. WINTER BIOME BEHIND THE CIRCLE: 200 blocks width
                local surface_y = 4
                for y = minp.y, maxp.y do
                    if y <= SEA_FLOOR then
                        data[vi] = c_stone
                    elseif y <= surface_y - 2 then
                        data[vi] = c_ice
                    elseif y <= surface_y - 1 then
                        data[vi] = c_snowblock
                    elseif y <= surface_y then
                        data[vi] = c_snow
                    else
                        data[vi] = c_air
                    end
                    vi = vi + ystride
                end

            elseif r > WINTER_R_MAX then
                -- 3. AFTERWARDS GREEN GRASSLANDS OUT TO THE 4 BORDERS
                local surface_y = 3
                for y = minp.y, maxp.y do
                    if y <= SEA_FLOOR then
                        data[vi] = c_stone
                    elseif y <= surface_y - 2 then
                        data[vi] = c_stone
                    elseif y <= surface_y - 1 then
                        data[vi] = c_dirt
                    elseif y <= surface_y then
                        data[vi] = c_dirt_with_grass
                    else
                        data[vi] = c_air
                    end
                    vi = vi + ystride
                end

            else
                -- 4. INSIDE THE KNOWN FLAT EARTH MAP (r < 30000)
                local wx = nvals_warp_x[noise_idx] or 0
                local wz = nvals_warp_z[noise_idx] or 0
                local warped_x = x + wx
                local warped_z = z + wz

                local base_h, _, _, _ = get_smooth_terrain_info(warped_x, warped_z)
                local relief = nvals_fine_relief[noise_idx] or 0
                local final_h = base_h + relief

                if final_h <= 0 then
                    -- Ocean water: natural seabed sloping down from beach
                    local seabed = math.max(SEA_FLOOR, math.floor(final_h))
                    for y = minp.y, maxp.y do
                        if y <= seabed then
                            data[vi] = c_stone
                        elseif y <= SEA_LEVEL then
                            data[vi] = c_water
                        else
                            data[vi] = c_air
                        end
                        vi = vi + ystride
                    end
                else
                    -- Land column: solid stone up to smoothly curved surface
                    local surface_y = math.max(1, math.floor(final_h + 0.5))
                    for y = minp.y, maxp.y do
                        if y <= surface_y then
                            data[vi] = c_stone
                        else
                            data[vi] = c_air
                        end
                        vi = vi + ystride
                    end
                end
            end

            noise_idx = noise_idx + 1
        end
    end

    -- Biomegen populates surfaces with native flora, trees, and ores
    if biomegen then
        biomegen.generate_all(data, area, voxelmanip, minp, maxp, seed)
    else
        voxelmanip:set_data(data)
    end

    voxelmanip:set_lighting({day = 15, night = 0})
    voxelmanip:write_to_map()
    voxelmanip:update_liquids()
    voxelmanip:update_map()
end)

-- Spawning Point: New York (USA)
local SPAWN_POS = {x = -5450, y = 5, z = 7790, name = "New York (USA) [Spawn]"}
minetest.set_mapgen_setting("static_spawnpoint", string.format("%d,%d,%d", SPAWN_POS.x, SPAWN_POS.y, SPAWN_POS.z), true)

-- Flat Earth landmark destinations
local major_locations = {
    ["newyork"]    = {x = -5450,  z = 7790,   name = "New York (USA) [Spawn]"},
    ["northpole"]  = {x = 0,      z = 0,      name = "North Pole (Center of Flat Earth)"},
    ["london"]     = {x = 0,      z = 13500,  name = "London / Greenwich (UK)"},
    ["paris"]      = {x = 500,    z = 12900,  name = "Paris (France)"},
    ["cairo"]      = {x = 5800,   z = 9200,   name = "Cairo (Egypt)"},
    ["tokyo"]      = {x = 14500,  z = 2800,   name = "Tokyo (Japan)"},
    ["sydney"]     = {x = 15200,  z = -16500, name = "Sydney (Australia)"},
    ["icewall"]    = {x = 0,      z = 30001,  name = "The Great Ice Wall (100 blocks high!)"},
    ["winter"]     = {x = 0,      z = 30100,  name = "Winter Biome (Beyond the Ice Wall)"},
    ["grasslands"] = {x = 0,      z = 30500,  name = "Green Grasslands (Edge of Known World)"},
    ["border"]     = {x = 0,      z = 30927,  name = "Luanti World Border"},
}

local function teleport_player_to(player, loc)
    local r = math.sqrt(loc.x * loc.x + loc.z * loc.z)
    local y_target = 5
    if r >= ICE_WALL_R_MIN and r <= ICE_WALL_R_MAX then
        y_target = ICE_WALL_HEIGHT + 2
    else
        local h, _, _, _ = get_smooth_terrain_info(loc.x, loc.z)
        y_target = math.max(2, math.floor(h + 2))
    end
    player:set_pos({x = loc.x, y = y_target, z = loc.z})
end

-- Main chatcommand: /flatearth (with /worldmap as alias)
local function handle_flatearth_cmd(name, param)
    local player = minetest.get_player_by_name(name)
    if not player then return false, "Player not found." end

    param = param:trim():lower()

    if param == "" or param == "info" then
        local p = player:get_pos()
        local r = math.sqrt(p.x * p.x + p.z * p.z)
        local h, _, _, b_name = get_smooth_terrain_info(p.x, p.z)
        local zone_desc = "Inside Known Earth"
        if r >= ICE_WALL_R_MIN and r <= ICE_WALL_R_MAX then
            zone_desc = "The Great Ice Wall (100 blocks high, 3 blocks width)"
        elseif r > ICE_WALL_R_MAX and r <= WINTER_R_MAX then
            zone_desc = "Winter Biome (200 blocks width)"
        elseif r > WINTER_R_MAX then
            zone_desc = "Outer Green Grasslands (Reaching the Borders)"
        end

        return true, string.format(
            "Flat Earth Map Status:\n" ..
            "• Position: X=%.0f, Y=%.0f, Z=%.0f\n" ..
            "• Distance from Center (North Pole): %.0f blocks\n" ..
            "• Zone: %s\n" ..
            "• Biome: %s (Base Elevation: %.1f)\n" ..
            "Type '/flatearth list' or '/goto <lat> <lon>' to navigate.",
            p.x, p.y, p.z, r, zone_desc, b_name, h
        )
    elseif param == "list" then
        local list = "Available Flat Earth locations:\n"
        for key, loc in pairs(major_locations) do
            list = list .. string.format("• %s -> %s\n", key, loc.name)
        end
        return true, list .. "Usage: /flatearth <location> (or shortcuts: /spawn, /newyork, /icewall, /winter, /grasslands, /northpole)"
    elseif major_locations[param] then
        local loc = major_locations[param]
        teleport_player_to(player, loc)
        return true, "Teleported to " .. loc.name .. "!"
    else
        return false, "Unknown location '" .. param .. "'. Type '/flatearth list' for available locations."
    end
end

minetest.register_chatcommand("flatearth", {
    params = "[location / list / info]",
    description = "Teleport to Flat Earth landmarks, Ice Wall, or view current coordinates",
    func = handle_flatearth_cmd,
})

minetest.register_chatcommand("worldmap", {
    params = "[location / list / info]",
    description = "Alias for /flatearth",
    func = handle_flatearth_cmd,
})

-- /goto <lat> <lon> converts real-world latitude and longitude to Flat Earth coordinates
minetest.register_chatcommand("goto", {
    params = "<latitude> <longitude>",
    description = "Teleport to real-world coordinates on the Flat Earth map (e.g. /goto 40.71 -74.01 for New York)",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end

        local parts = param:split()
        local lat = tonumber(parts[1])
        local lon = tonumber(parts[2])

        if not (lat and lon) then
            return false, "Usage: /goto <latitude> <longitude> (e.g. /goto 40.71 -74.01 for New York)"
        end

        local lat_dist = 90.0 - math.max(-70.0, math.min(90.0, lat))
        local r = (lat_dist / 160.0) * ICE_WALL_R_MIN
        local rad = math.rad(lon)

        local x = r * math.sin(rad)
        local z = r * math.cos(rad)

        local h, _, _, b_name = get_smooth_terrain_info(x, z)
        local y_target = math.max(2, math.floor(h + 2))
        player:set_pos({x = x, y = y_target, z = z})

        return true, string.format("Teleported to %.2f°%s, %.2f°%s -> Flat Earth (X=%.0f, Z=%.0f) | Biome: %s, Elevation: %.1f",
            math.abs(lat), (lat >= 0 and "N" or "S"),
            math.abs(lon), (lon >= 0 and "E" or "W"),
            x, z, b_name, h)
    end
})

-- Flying and inspection tools
minetest.register_chatcommand("fly", {
    description = "Grant fast flying and noclip privileges to inspect the Flat Earth quickly",
    func = function(name)
        local privs = minetest.get_player_privs(name)
        privs.fly = true
        privs.fast = true
        privs.noclip = true
        minetest.set_player_privs(name, privs)
        return true, "Granted fly, fast, and noclip privileges! Press 'K' to fly, 'J' for high speed."
    end
})

minetest.register_chatcommand("flyspeed", {
    params = "[speed_multiplier]",
    description = "Set flying movement speed (e.g. /flyspeed 10 or /flyspeed 20)",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end
        local spd = tonumber(param) or 5.0
        player:set_physics_override({speed = spd, jump = 1.5, gravity = 1.0})
        return true, string.format("Movement speed multiplier set to %.1fx! (Default is 1.0)", spd)
    end
})

-- Landmark shortcuts
minetest.register_chatcommand("spawn", {
    description = "Teleport back to New York (USA) spawn",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, SPAWN_POS)
            return true, "Teleported to New York (Spawn)!"
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("newyork", {
    description = "Teleport to New York (USA)",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, SPAWN_POS)
            return true, "Teleported to New York (USA)!"
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("icewall", {
    description = "Teleport to the Great Ice Wall (100 blocks high)",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, major_locations["icewall"])
            return true, "Teleported to the Great Ice Wall!"
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("winter", {
    description = "Teleport to the Winter Biome behind the Ice Wall",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, major_locations["winter"])
            return true, "Teleported to the Winter Biome!"
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("grasslands", {
    description = "Teleport to the outer Green Grasslands",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, major_locations["grasslands"])
            return true, "Teleported to the Green Grasslands!"
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("northpole", {
    description = "Teleport to the North Pole center",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            teleport_player_to(player, major_locations["northpole"])
            return true, "Teleported to the North Pole (Center of Flat Earth)!"
        end
        return false, "Player not found."
    end
})

-- Player spawn handlers: Spawning point is New York
minetest.register_on_newplayer(function(player)
    teleport_player_to(player, SPAWN_POS)
    player:get_meta():set_string("spawned_in_newyork", "true")
    minetest.chat_send_player(player:get_player_name(),
        "Welcome to the Flat Earth in Luanti! You have spawned in New York (USA). Type '/flatearth list' or '/icewall' to explore.")
end)

minetest.register_on_respawnplayer(function(player)
    teleport_player_to(player, SPAWN_POS)
    return true
end)

minetest.register_on_joinplayer(function(player)
    local p = player:get_pos()
    local meta = player:get_meta()

    if p.y <= 0 or meta:get_string("spawned_in_newyork") ~= "true" then
        teleport_player_to(player, SPAWN_POS)
        meta:set_string("spawned_in_newyork", "true")
        minetest.chat_send_player(player:get_player_name(),
            "Welcome to New York (USA)! Type '/flatearth list' for fast travel (e.g. /icewall, /winter, /grasslands, /northpole).")
    end
end)
