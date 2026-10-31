loadstring(game:HttpGet("https://raw.githubusercontent.com/xposn/Matcha-UI/main/library.lua"))()

local library = _G.InterceptionUI
local flags = library.flags
local themes = library.themes
local dim2, rgb = UDim2.new, Color3.fromRGB

local window = library:window({ name = "interception", size = dim2(0, 500, 0, 450) })

local combat = window:tab({ name = "combat" })
local visuals = window:tab({ name = "visuals" })
local settings = window:tab({ name = "settings" })

local aimbot = combat:section({ name = "aimbot", side = "left" })
aimbot:toggle({ name = "enabled", flag = "aim_enabled" })
aimbot:keybind({ flag = "aim_key", key = Enum.KeyCode.E, mode = "hold", display = "aimbot" })
aimbot:colorpicker({ flag = "aim_fov_color", color = rgb(255, 255, 255) })
aimbot:slider({ flag = "aim_fov", min = 0, max = 500, default = 120, suffix = "px" })
aimbot:slider({ name = "smoothness", flag = "aim_smooth", min = 1, max = 20, default = 5, interval = 0.5 })
aimbot:dropdown({ name = "hitpart", flag = "aim_hitpart", items = { "head", "torso", "closest" }, default = "head" })
aimbot:toggle({ name = "team check", flag = "aim_team" })
local visibleMode
aimbot:toggle({ name = "visible only", flag = "aim_visible", callback = function(on)
    if visibleMode and visibleMode.set_shown then
        visibleMode.set_shown(on)
    end
end })
visibleMode = aimbot:dropdown({ flag = "aim_visible_mode", items = { "raycast", "occlusion" } })
if visibleMode.set_shown then
    visibleMode.set_shown(flags.aim_visible)
end

local trigger = combat:section({ name = "triggerbot", side = "right" })
trigger:toggle({ name = "enabled", flag = "trigger_enabled" })
trigger:keybind({ flag = "trigger_key", key = Enum.UserInputType.MouseButton2, mode = "hold", display = "triggerbot" })
trigger:slider({ name = "delay", flag = "trigger_delay", min = 0, max = 300, default = 40, suffix = "ms" })
trigger:button({ name = "test notification", callback = function()
    library:notification({ text = "triggerbot armed", time = 3 })
end })

local player = visuals:section({ name = "player", side = "left" })
player:toggle({ name = "enable", flag = "player_enable" })
player:keybind({ flag = "player_key", key = Enum.KeyCode.F, mode = "toggle", display = "Player ESP" })
player:toggle({ name = "name", flag = "player_name", default = true })
player:colorpicker({ flag = "player_name_color", color = rgb(255, 255, 255) })
player:toggle({ name = "distance", flag = "player_distance", default = true })
player:colorpicker({ flag = "player_distance_color", color = rgb(255, 255, 255) })
player:toggle({ name = "equipped", flag = "player_equipped", default = true })
player:colorpicker({ flag = "player_equipped_color", color = rgb(255, 255, 255) })
player:toggle({ name = "show players on map", flag = "player_map" })
player:dropdown({ flag = "player_map_info", items = { "name", "equipped" }, multi = true, default = { "name", "equipped" } })
player:toggle({ name = "info list", flag = "player_info_list", default = true, callback = function(bool)
    window.toggle_info_list(bool)
end })
player:slider({ name = "max distance", flag = "player_max_distance", min = 0, max = 1000, default = 1000, suffix = "m" })
window.set_info("XxQueen_ALPHAXX2018", {
    { label = "Backpack", value = "Daypack Black" },
    { label = "Item", value = "Ruger Model 44 Carbine", list = { "Red Dot", "Suppressor", "Grip" } },
    { label = "Ammo", value = ".44 Magnum" },
})

local world = visuals:section({ name = "world", side = "right" })
world:toggle({ name = "enable", flag = "world_enable" })
world:toggle({ name = "vehicle", flag = "world_vehicle", default = true })
world:colorpicker({ flag = "world_vehicle_color", color = rgb(0, 255, 0) })
world:slider({ name = "vehicle distance", flag = "world_vehicle_distance", min = 0, max = 1000, default = 1000, suffix = "m" })
world:toggle({ name = "corpse", flag = "world_corpse", default = true })
world:colorpicker({ flag = "world_corpse_color", color = rgb(255, 0, 0) })
world:slider({ name = "corpse distance", flag = "world_corpse_distance", min = 0, max = 1000, default = 1000, suffix = "m" })
world:toggle({ name = "show events on map", flag = "world_events_map" })
world:colorpicker({ flag = "world_events_map_color", color = rgb(255, 255, 0) })

local menu = settings:section({ name = "menu", side = "left" })
menu:colorpicker({ name = "accent", flag = "accent", color = themes.preset.accent, callback = function(color)
    library:update_theme("accent", color)
end })
menu:keybind({ name = "menu key", flag = "menu_key", default = Enum.KeyCode.Insert, mode = "toggle", show_in_list = false, callback = function(bool)
    window.set_menu_visibility(bool)
end })
menu:toggle({ name = "watermark", flag = "watermark", default = true, callback = function(bool)
    window.toggle_watermark(bool)
end })
menu:dropdown({ flag = "watermark_position", items = { "top left", "top right", "top center", "bottom left", "bottom right", "bottom center", "draggable" }, default = "top left", callback = function(position)
    window.set_watermark_position(position)
end })
menu:toggle({ name = "keybind list", flag = "keybind_list", default = true, callback = function(bool)
    window.toggle_list(bool)
end })

local configs = settings:section({ name = "configs", side = "right" })
library.config_holder = configs:dropdown({ name = "configs", flag = "config_selected", items = {} })
configs:textbox({ placeholder = "config name...", flag = "config_name" })
configs:button({ name = "save", callback = function()
    local name = flags["config_name"]
    if type(name) ~= "string" or name == "" then
        library:notification({ text = "enter a config name first" })
        return
    end
    writefile(library:config_path(name), library:get_config())
    library:config_list_update()
    library:notification({ text = "saved " .. name })
end })
configs:button({ name = "load", callback = function()
    local name = flags["config_selected"]
    local path = name and library:config_path(name)
    if path and isfile(path) then
        library:load_config(readfile(path))
        library:notification({ text = "loaded " .. name })
    end
end })
configs:button({ name = "delete", confirm = true, callback = function()
    local name = flags["config_selected"]
    local path = name and library:config_path(name)
    if path and isfile(path) then
        delfile(path)
        library:config_list_update()
        library.config_holder.set("")
        library:notification({ text = "deleted " .. name })
    end
end })
library:config_list_update()

combat.open_tab()
library:notification({ text = "interception loaded", time = 4 })
