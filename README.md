# Matcha UI

UI library for Matcha. Everything is drawn with the Drawing API, so it doesn't need any instances.

`library.lua` is the library. `demo.lua` is an example menu that loads it.

## Loading it

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/xposn/Matcha-UI/main/library.lua"))()
local library = _G.InterceptionUI
```

Matcha's loadstring doesn't hand back return values, so grab the library from `_G` after it loads.

## Example

```lua
local window = library:window({ name = "my menu", size = UDim2.new(0, 500, 0, 450) })
local main = window:tab({ name = "main" })
local aim = main:section({ name = "aimbot", side = "left" })

aim:toggle({ name = "enabled", flag = "aim_enabled" })
aim:keybind({ flag = "aim_key", key = Enum.KeyCode.E, mode = "hold" })
aim:colorpicker({ flag = "aim_color", color = Color3.fromRGB(255, 255, 255) })
aim:slider({ name = "fov", flag = "aim_fov", min = 0, max = 500, default = 120, suffix = "px" })
aim:dropdown({ name = "hitpart", flag = "aim_part", items = { "head", "torso" }, default = "head" })
aim:button({ name = "test", callback = function()
    library:notification({ text = "it works" })
end })
```

The keybind and colorpicker there have no name, so they sit on the right side of the toggle above them. A slider or dropdown with no name goes under that toggle instead.

Double-click a slider to type a value. Enter or clicking somewhere else sets it, and Escape cancels.

Every element keeps its value in `library.flags` under its flag, so you can check things like `library.flags.aim_enabled` from anywhere. Keybinds store a table with `key`, `mode` and `active`.

A keybind can have more than one key. Pass `keys` instead of `key`:

```lua
aim:keybind({ flag = "aim_key", keys = { Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2 }, mode = "hold" })
```

That shows `[mb1] [mb2]` on the row. Click either box to rebind just that one (Escape or Backspace clears it, and `"..."` in the list starts a box empty). The bind is active while any of its keys is held, or any of them toggles it in press mode. Its flag also gets a `keys` list, and configs save every key.

A section can have sub tabs. Call `subtab` on it and add elements to what that returns:

```lua
local prediction = aim:subtab({ name = "prediction" })
prediction:toggle({ name = "bullet drop", flag = "pred_drop" })
```

The panel's title then shows both names side by side. Clicking a name switches what the panel shows. Elements on the hidden sub tab keep working, so their keybinds and flags stay live.

Give the section `subtab_style = "bar"` to get a row of tabs across the top of the panel instead. The first tab is the section's own name:

```lua
local enemies = main:section({ name = "enemies", side = "right", subtab_style = "bar" })
local friendlies = enemies:subtab({ name = "friendlies" })
local client = enemies:subtab({ name = "client" })
```

## Widgets

A widget is a small panel on the screen, like the info list, that shows whatever rows you give it:

```lua
local status = window:widget({ name = "prediction", title = "prediction status" })
status.set_lines({
    { label = "status", value = "tracking", color = Color3.fromRGB(120, 255, 120) },
    { label = "target", value = "someone" },
    { label = "distance", value = "212m" },
    { separator = true },
    { label = "confidence", bar = 0.72, text = "72%" },
    "plain text works too",
})
```

Rows can be:

- a plain string, or `{ text = "...", color = ..., align = "left" | "center" | "right" }`
- `{ label = "name", value = "text" }` with an optional value `color`, `label_color`, `align = "right"` to push the value to the right edge, and a `list` of extra lines shown under the value
- `{ label = "name", bar = 0.5, text = "50%" }`, a bar from 0 to 1 with an optional `color`. All bars in a widget line up, even when their labels or texts are different lengths
- `{ separator = true }`, a thin line

Call `set_lines` again whenever the data changes. The widget also has `set_title(text)`, `set_visible(bool)` (or `toggle`), `dock(bool)`, `is_docked()`, `set_position(x, y)` and `remove()`.

Pass `visible = false` to start it hidden, `docked = true` to stack it beside the menu, `x`/`y` for a starting spot, and `min_width` to keep it from getting narrower. A widget with no `x` stays against the right edge of the screen even when it gets wider, and widgets with no `y` stack down the middle of the right side without covering each other. With the menu open you can drag any widget, which undocks it. Positions are saved in configs by widget name, so give each widget its own name.

The info list is a widget too. `window.set_info(title, lines)` and `window.toggle_info_list(bool)` still work, and `window.info_widget` gives you the widget itself.

## Other stuff

- The menu, watermark, keybind list, ESP preview, widgets and popups always stay on screen, even when dragged, resized or after the game window shrinks
- `window.toggle_watermark(true)` and `window.set_watermark_position("top right")`
- `window.set_watermark_info({ "user", "display", "game", "ping", "fps" })` picks what the watermark shows
- `window.toggle_list(true)` shows the keybind list
- `window.toggle_notification_preview(true)` shows a sample notification that stays up and can be dragged with the menu open, and `window.set_notification_preview_text(text)` changes what it says
- `window.set_info(title, lines)` and `window.toggle_info_list(true)` for the info box
- `window.set_menu_visibility(false)` hides the menu
- `library:get_config()` and `library:load_config(text)` for saving and loading
- `library:config_path(name)` gives the file path for a config name

Configs go in `Pepsi UI/configs` in your Matcha workspace. Give the window a game name and they go in that game's folder instead:

```lua
local window = library:window({ name = "my menu", game = "Apocalypse Rising 2" })
```

That saves to `Pepsi UI/Apocalypse Rising 2`, and the game name also shows in the watermark after your username and display name, followed by your ping.

Run `demo.lua` to see all of it. Insert opens and closes the menu.
