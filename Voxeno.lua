--[[
	SimpleUI
	Default size: UDim2.new(0, 550, 0, 356)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

--------------------------------------------------------------------
-- Anti-duplicate protection
-- The check and the lock happen in the same instant (no yielding in
-- between), so even if the script is executed many times at once,
-- only the first run builds a UI. The others just get the existing one.
--------------------------------------------------------------------
local env = (getgenv and getgenv()) or _G

local existing = env.__SimpleUI
if existing then
	local stale = existing.Mounted and (not existing.Gui or not existing.Gui.Parent)
	if not stale then
		return existing.Library -- already running: build nothing, create no window / open button
	end
end

local Library = {}
local State = { Library = Library, Gui = nil, Mounted = false, Conns = {} }
env.__SimpleUI = State -- lock

Library.Window = nil
Library.LucideIcons = nil   -- lucide table: WindUI.Creator.Icons.Icons.lucide
Library.WindUI = nil        -- or the whole WindUI object (preferred, most reliable)
Library.IconResolver = nil  -- optional: function(name) return {Image=..., RectSize=..., RectOffset=...} end

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(p, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end

local function stroke(p, color, thickness)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, p)
end

local function tween(o, t, props, style)
	TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function safeCall(fn, ...)
	if type(fn) == "function" then
		local args = { ... }
		task.spawn(function()
			local ok, err = pcall(fn, table.unpack(args))
			if not ok then warn("[SimpleUI] " .. tostring(err)) end
		end)
	end
end

local Theme = {
	Background = Color3.fromRGB(18, 18, 18), -- matte black
	Surface = Color3.fromRGB(28, 28, 28),
	SurfaceHover = Color3.fromRGB(36, 36, 36),
	Stroke = Color3.fromRGB(48, 48, 48),
	Text = Color3.fromRGB(235, 235, 235),
	SubText = Color3.fromRGB(150, 150, 150),
	Accent = Color3.fromRGB(88, 135, 255),
	Danger = Color3.fromRGB(220, 70, 70),
}

--------------------------------------------------------------------
-- Color palette: pick colors by NAME (20 colors)
-- Color  = UI background color name (e.g. Color = "Navy")
-- Accent = highlight color name   (e.g. Accent = "Red")
-- Names: Matte Black, Black, Charcoal, Gray, Navy, Blue, Sky, Teal, Green,
--        Forest, Olive, Yellow, Orange, Red, Maroon, Pink, Magenta, Purple,
--        Indigo, Brown   (not case-sensitive; Library:GetColors() lists them)
--------------------------------------------------------------------
local Palette = {
	-- { name, background, accent }
	{ "Matte Black", Color3.fromRGB(18, 18, 18), Color3.fromRGB(88, 135, 255) },
	{ "Black",       Color3.fromRGB(8, 8, 8),    Color3.fromRGB(230, 230, 230) },
	{ "Charcoal",    Color3.fromRGB(30, 32, 36), Color3.fromRGB(150, 160, 175) },
	{ "Gray",        Color3.fromRGB(40, 40, 44), Color3.fromRGB(170, 170, 180) },
	{ "Navy",        Color3.fromRGB(14, 22, 44), Color3.fromRGB(60, 110, 230) },
	{ "Blue",        Color3.fromRGB(16, 32, 64), Color3.fromRGB(70, 130, 255) },
	{ "Sky",         Color3.fromRGB(14, 36, 52), Color3.fromRGB(70, 190, 240) },
	{ "Teal",        Color3.fromRGB(12, 38, 40), Color3.fromRGB(40, 200, 190) },
	{ "Green",       Color3.fromRGB(14, 36, 22), Color3.fromRGB(60, 200, 100) },
	{ "Forest",      Color3.fromRGB(16, 30, 20), Color3.fromRGB(90, 170, 90) },
	{ "Olive",       Color3.fromRGB(32, 34, 16), Color3.fromRGB(170, 180, 60) },
	{ "Yellow",      Color3.fromRGB(40, 36, 12), Color3.fromRGB(245, 200, 50) },
	{ "Orange",      Color3.fromRGB(44, 26, 12), Color3.fromRGB(250, 140, 40) },
	{ "Red",         Color3.fromRGB(44, 14, 14), Color3.fromRGB(235, 70, 70) },
	{ "Maroon",      Color3.fromRGB(36, 12, 18), Color3.fromRGB(190, 50, 80) },
	{ "Pink",        Color3.fromRGB(44, 16, 32), Color3.fromRGB(245, 110, 170) },
	{ "Magenta",     Color3.fromRGB(40, 14, 40), Color3.fromRGB(220, 70, 220) },
	{ "Purple",      Color3.fromRGB(30, 18, 46), Color3.fromRGB(150, 100, 240) },
	{ "Indigo",      Color3.fromRGB(22, 20, 52), Color3.fromRGB(110, 100, 240) },
	{ "Brown",       Color3.fromRGB(36, 24, 16), Color3.fromRGB(190, 130, 80) },
}

local function normName(s)
	return (tostring(s):lower():gsub("[^%w]", ""))
end

local PaletteMap = {}
Library.Colors = {}
for _, entry in ipairs(Palette) do
	PaletteMap[normName(entry[1])] = entry
	table.insert(Library.Colors, entry[1])
end

PaletteMap["dark"] = PaletteMap["mattblack"] or PaletteMap["matteblack"] -- alias: Color = "Dark"

function Library:GetColors()
	return table.clone(Library.Colors)
end

-- returns background, accent for a palette name (a Color3 is passed through)
local function lookupColor(v)
	if typeof(v) == "Color3" then return v, nil end
	if type(v) == "string" then
		local entry = PaletteMap[normName(v)]
		if entry then return entry[2], entry[3] end
		warn("[SimpleUI] Unknown color name '" .. v .. "'. Available: " .. table.concat(Library.Colors, ", "))
	end
	return nil, nil
end

local function applyTheme(colorOpt, accentOpt)
	if colorOpt ~= nil then
		local bgColor, accentColor = lookupColor(colorOpt)
		if bgColor then
			local white = Color3.new(1, 1, 1)
			Theme.Background = bgColor
			Theme.Surface = bgColor:Lerp(white, 0.07)
			Theme.SurfaceHover = bgColor:Lerp(white, 0.13)
			Theme.Stroke = bgColor:Lerp(white, 0.17)
			if accentColor then Theme.Accent = accentColor end
		end
	end
	if accentOpt ~= nil then
		if typeof(accentOpt) == "Color3" then
			Theme.Accent = accentOpt
		else
			local _, accentColor = lookupColor(accentOpt)
			if accentColor then Theme.Accent = accentColor end
		end
	end
end

--------------------------------------------------------------------
-- ScreenGui
-- Built un-parented and mounted once on the next frame, so the whole
-- UI appears instantly in one go.
--------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "SimpleUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
})
State.Gui = gui

local function mountGui()
	if gui.Parent then return end
	local ok = false
	if gethui then
		ok = pcall(function() gui.Parent = gethui() end) and gui.Parent ~= nil
	end
	if not ok then
		ok = pcall(function() gui.Parent = CoreGui end) and gui.Parent ~= nil
	end
	if not ok then
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end
	State.Mounted = true

	-- remove leftovers of older runs / older versions (only one SimpleUI may exist)
	local parent = gui.Parent
	if parent then
		for _, child in ipairs(parent:GetChildren()) do
			if child ~= gui and child.Name == "SimpleUI" and child:IsA("ScreenGui") then
				child:Destroy()
			end
		end
	end
end
task.defer(mountGui)

local function destroyAll()
	for _, c in ipairs(State.Conns) do
		pcall(function() c:Disconnect() end)
	end
	State.Conns = {}
	pcall(function() gui:Destroy() end)
	if env.__SimpleUI == State then env.__SimpleUI = nil end -- release the lock
	Library.Window = nil
end

function Library:Destroy() destroyAll() end

--------------------------------------------------------------------
-- Icons (Lucide / rbxassetid / Emoji)
--------------------------------------------------------------------
function Library:SetIcons(lucideTable)
	Library.LucideIcons = lucideTable
end

function Library:SetWindUI(windui)
	Library.WindUI = windui
end

local function toAsset(v)
	if type(v) == "number" then return "rbxassetid://" .. v end
	if type(v) == "string" then
		if v:match("^%d+$") then return "rbxassetid://" .. v end
		return v
	end
	return nil
end

-- Understands the different shapes WindUI uses for icon data
local function parseIcon(data, set)
	if data == nil then return nil end
	if type(data) == "string" or type(data) == "number" then
		local img = toAsset(data)
		return img and { Image = img } or nil
	end
	if type(data) ~= "table" then return nil end

	local meta = data
	if type(data[2]) == "table" then meta = data[2] end -- {sheetId, {ImageRectSize, ImageRectPosition}}

	local img = data.Image or data.Id or data.id or data[1]
	local size = meta.ImageRectSize or data.ImageRectSize or meta.RectSize or data.RectSize
	local off = meta.ImageRectPosition or meta.ImageRectOffset or data.ImageRectPosition
		or data.ImageRectOffset or meta.RectOffset or data.RectOffset

	-- Image can be an index into set.Spritesheets
	local sheets = type(set) == "table" and set.Spritesheets or nil
	if sheets and (type(img) == "number" or (type(img) == "string" and img:match("^%d+$"))) then
		local sheet = sheets[tostring(img)] or sheets[tonumber(img)]
		if sheet then img = sheet end
	end

	img = toAsset(img)
	if not img then return nil end
	return { Image = img, RectSize = size, RectOffset = off }
end

local iconCache = {}
local warned = {}

--------------------------------------------------------------------
-- Lucide registry (names + aliases + lookup helpers)
-- The registry only knows icon NAMES. To actually draw an icon you need an
-- image source, checked in this order for every icon:
--   1) Lucide.Assets / Library:SetIconAssets({ house = "rbxassetid://123" })
--   2) icons loaded from a folder:  Library:LoadIcons(folder)
--   3) WindUI:                      Library:SetWindUI(WindUI)
--------------------------------------------------------------------
local Lucide = { Names = {}, Set = {}, Compact = {}, Aliases = {}, Assets = {} }
Library.Lucide = Lucide

local LUCIDE_NAMES = [==[
a-arrow-down a-arrow-up a-large-small accessibility activity ad air-vent airplay alarm-clock
alarm-clock-check alarm-clock-minus alarm-clock-off alarm-clock-plus alarm-smoke align-center-horizontal
align-center-vertical align-end-horizontal align-end-vertical align-horizontal-distribute-center
align-horizontal-distribute-end align-horizontal-distribute-start align-horizontal-justify-center
align-horizontal-justify-end align-horizontal-justify-start align-horizontal-space-around
align-horizontal-space-between align-start-horizontal align-start-vertical align-vertical-distribute-center
align-vertical-distribute-end align-vertical-distribute-start align-vertical-justify-center
align-vertical-justify-end align-vertical-justify-start align-vertical-space-around
align-vertical-space-between ambulance ampersand ampersands amphora anchor angle antenna anvil aperture
app-window app-window-mac apple archive archive-restore archive-x armchair armenian-dram arrow-big-down
arrow-big-down-dash arrow-big-left arrow-big-left-dash arrow-big-right arrow-big-right-dash arrow-big-up
arrow-big-up-dash arrow-down arrow-down-0-1 arrow-down-1-0 arrow-down-a-z arrow-down-from-line
arrow-down-left arrow-down-narrow-wide arrow-down-right arrow-down-to-dot arrow-down-to-line arrow-down-up
arrow-down-wide-narrow arrow-down-z-a arrow-left arrow-left-from-line arrow-left-right arrow-left-to-line
arrow-right arrow-right-from-line arrow-right-left arrow-right-to-line arrow-up arrow-up-0-1 arrow-up-1-0
arrow-up-a-z arrow-up-down arrow-up-from-dot arrow-up-from-line arrow-up-left arrow-up-narrow-wide
arrow-up-right arrow-up-to-line arrow-up-wide-narrow arrow-up-z-a arrows-up-from-line asterisk astroid
at-sign atom audio-lines audio-lines-off audio-lines-x audio-waveform award axe axis-3d baby backpack badge
badge-alert badge-cent badge-check badge-dollar-sign badge-euro badge-indian-rupee badge-info
badge-japanese-yen badge-minus badge-percent badge-plus badge-pound-sterling badge-question-mark
badge-russian-ruble badge-swiss-franc badge-turkish-lira badge-x baggage-claim balloon ban banana bandage
bangladeshi-taka banknote banknote-arrow-down banknote-arrow-up banknote-check banknote-x barcode barrel
baseline bath battery battery-charging battery-full battery-low battery-medium battery-plus battery-warning
beaker bean bean-off bed bed-double bed-single beef beef-off beer beer-off belarusian-ruble bell bell-check
bell-dot bell-electric bell-minus bell-off bell-plus bell-ring between-horizontal-end
between-horizontal-start between-vertical-end between-vertical-start biceps-flexed bike binary binoculars
biohazard bird birdhouse bitcoin blend blender blinds blocks bluetooth bluetooth-connected bluetooth-off
bluetooth-searching bold bolt bomb bone bone-fracture book book-a book-alert book-audio book-bookmark
book-check book-copy book-dashed book-down book-headphones book-heart book-image book-key book-lock
book-minus book-open book-open-check book-open-text book-plus book-search book-text book-type book-up
book-up-2 book-user book-x bookmark bookmark-check bookmark-minus bookmark-off bookmark-plus bookmark-x
boom-box bot bot-message-square bot-off bottle-wine bow-arrow box boxes braces brackets brain brain-circuit
brain-cog brick-wall brick-wall-fire brick-wall-shield bridge briefcase briefcase-business
briefcase-conveyor-belt briefcase-medical briefcase-plus bring-to-front broccoli broom broom-sparkles brush
brush-cleaning bubbles bug bug-off bug-play building building-complex building-complex-plus bus bus-front
cable cable-car cake cake-slice calculator calendar calendar-1 calendar-arrow-down calendar-arrow-up
calendar-check calendar-check-2 calendar-chevrons-left calendar-chevrons-right calendar-clock calendar-cog
calendar-days calendar-fold calendar-heart calendar-minus calendar-minus-2 calendar-off calendar-plus
calendar-plus-2 calendar-range calendar-search calendar-sync calendar-x calendar-x-2 calendars camera
camera-off can can-soda candy candy-cane candy-off cannabis cannabis-off captions captions-off car
car-battery car-front car-taxi-front caravan card-sim carrot carton carton-off case-lower case-sensitive
case-upper cassette-tape cast castle cat cctv cctv-off certificate chart-area chart-bar chart-bar-big
chart-bar-decreasing chart-bar-increasing chart-bar-stacked chart-candlestick chart-column chart-column-big
chart-column-decreasing chart-column-increasing chart-column-stacked chart-gantt chart-line chart-network
chart-no-axes-column chart-no-axes-column-decreasing chart-no-axes-column-increasing chart-no-axes-combined
chart-no-axes-gantt chart-pie chart-scatter chart-spline check check-check check-line chef-hat cherry
chess-bishop chess-king chess-knight chess-pawn chess-queen chess-rook chevron-down chevron-first
chevron-last chevron-left chevron-right chevron-up chevrons-down chevrons-down-up chevrons-left
chevrons-left-right chevrons-left-right-ellipsis chevrons-right chevrons-right-left chevrons-up
chevrons-up-down church cigarette cigarette-off circle circle-alert circle-arrow-down circle-arrow-left
circle-arrow-out-down-left circle-arrow-out-down-right circle-arrow-out-up-left circle-arrow-out-up-right
circle-arrow-right circle-arrow-up circle-check circle-check-big circle-chevron-down circle-chevron-left
circle-chevron-right circle-chevron-up circle-dashed circle-dashed-check circle-divide circle-dollar-sign
circle-dot circle-dot-dashed circle-ellipsis circle-equal circle-euro circle-fading-arrow-up
circle-fading-play circle-fading-plus circle-gauge circle-minus circle-off circle-parking circle-parking-off
circle-pause circle-percent circle-pile circle-play circle-plus circle-pound-sterling circle-power
circle-question-mark circle-slash circle-slash-2 circle-small circle-star circle-stop circle-user
circle-user-round circle-x circuit-board citrus clapperboard clef-alto clef-bass clef-treble clipboard
clipboard-check clipboard-clock clipboard-copy clipboard-list clipboard-minus clipboard-paste clipboard-pen
clipboard-pen-line clipboard-plus clipboard-type clipboard-x clock clock-1 clock-10 clock-11 clock-12 clock-2
clock-3 clock-4 clock-5 clock-6 clock-7 clock-8 clock-9 clock-alert clock-arrow-down clock-arrow-left
clock-arrow-right clock-arrow-up clock-check clock-fading clock-plus closed-caption cloud cloud-alert
cloud-backup cloud-check cloud-cog cloud-download cloud-drizzle cloud-fog cloud-hail cloud-lightning
cloud-moon cloud-moon-rain cloud-off cloud-rain cloud-rain-wind cloud-snow cloud-sun cloud-sun-rain
cloud-sync cloud-upload cloudy clover club code code-xml coffee cog coins columns-2 columns-3 columns-3-cog
columns-4 combine command compass component computer concierge-bell cone construction contact contact-round
container contrast cookie cooking-pot copy copy-check copy-minus copy-plus copy-slash copy-x copyleft
copyright corner-down-left corner-down-right corner-left-down corner-left-up corner-right-down
corner-right-up corner-up-left corner-up-right cpu cpu-ai creative-commons credit-card credit-card-check
credit-card-minus
]==]

for name in LUCIDE_NAMES:gmatch("%S+") do
	table.insert(Lucide.Names, name)
	Lucide.Set[name] = true
	Lucide.Compact[normName(name)] = name -- "ArrowLeft" / "arrow_left" -> "arrow-left"
end

-- renamed icons: both spellings resolve to whichever one your source has
for _, pair in ipairs({
	{ "home", "house" },
	{ "check-circle", "circle-check" },
	{ "alert-circle", "circle-alert" },
	{ "alert-triangle", "triangle-alert" },
	{ "x-circle", "circle-x" },
	{ "help-circle", "circle-question-mark" },
	{ "bar-chart", "chart-bar" },
	{ "line-chart", "chart-line" },
	{ "pie-chart", "chart-pie" },
	{ "edit", "square-pen" },
	{ "unlock", "lock-open" },
	{ "user-circle", "circle-user" },
	{ "more-horizontal", "ellipsis" },
	{ "more-vertical", "ellipsis-vertical" },
	{ "loader-2", "loader-circle" },
}) do
	Lucide.Aliases[pair[1]] = pair[2]
	Lucide.Aliases[pair[2]] = pair[1]
end

-- "Lucide-Arrow Left" / "arrow_left" -> "arrow-left"
function Lucide.Normalize(name)
	if type(name) ~= "string" then return nil end
	local n = name:lower()
	n = (n:gsub("^%s+", ""))
	n = (n:gsub("^lucide[%-:_%s]+", ""))
	n = (n:gsub("[%s_]+", "-"))
	n = (n:gsub("^%-+", ""))
	n = (n:gsub("%-+$", ""))
	return n
end

function Lucide.Canonical(name)
	local n = Lucide.Normalize(name)
	if not n or n == "" then return nil end
	if Lucide.Set[n] then return n end
	return Lucide.Compact[normName(n)] or n
end

function Lucide.Has(name)
	local c = Lucide.Canonical(name)
	return c ~= nil and Lucide.Set[c] == true
end

function Lucide.Get(name)
	local c = Lucide.Canonical(name)
	return c and Lucide.Assets[c] or nil
end

function Lucide.Count()
	return #Lucide.Names
end

function Lucide.Search(query, limit)
	local q = Lucide.Normalize(query) or ""
	local out = {}
	limit = limit or 10
	if q == "" then return out end
	for _, n in ipairs(Lucide.Names) do
		if n:find(q, 1, true) then
			table.insert(out, n)
			if #out >= limit then break end
		end
	end
	return out
end

-- names to try for one requested icon: the canonical name, then its alias
function Lucide.Candidates(name)
	local c = Lucide.Canonical(name)
	if not c then return {} end
	local list = { c }
	local alt = Lucide.Aliases[c]
	if alt then table.insert(list, alt) end
	return list
end

-- Library:SetIconAssets({ house = "rbxassetid://123", ["arrow-left"] = { Image = "...", RectSize = V2, RectOffset = V2 } })
function Library:SetIconAssets(tbl)
	for k, v in pairs(tbl or {}) do
		local c = Lucide.Canonical(k)
		if c then Lucide.Assets[c] = v end
	end
	iconCache = {}
	warned = {}
end

-- Lucide icons taken from a folder in the game (ImageLabels / Decals named after the icon)
local folderIcons = {}

local function iconKey(name)
	return (normName(name):gsub("^lucide", ""))
end

local function getAllLucideIcons(folder)
	local result = {}
	for _, child in ipairs(folder:GetDescendants()) do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then
			table.insert(result, { name = child.Name, image = child.Image, instance = child })
		elseif child:IsA("Decal") or child:IsA("Texture") then
			table.insert(result, { name = child.Name, image = child.Texture, instance = child })
		end
	end
	return result
end
Library.getAllLucideIcons = getAllLucideIcons

local genericNames = {
	icon = true, image = true, imagelabel = true, imagebutton = true, decal = true, texture = true,
}

-- Library:LoadIcons(folder) -> number of icons loaded
-- After this, Icon = "house" (or "House", "lucide-house", or the old name "home") works for tabs and everything else.
function Library:LoadIcons(folder)
	if typeof(folder) ~= "Instance" then
		warn("[SimpleUI] LoadIcons expects a Folder instance.")
		return 0
	end

	local count = 0
	for _, item in ipairs(getAllLucideIcons(folder)) do
		local inst = item.instance
		local name = item.name
		-- if the image is inside a container (e.g. Frame "home" > ImageLabel "Icon"), use the container name
		if genericNames[name:lower()] and inst.Parent and inst.Parent ~= folder then
			name = inst.Parent.Name
		end

		local key = iconKey(name)
		local img = item.image
		if key ~= "" and type(img) == "string" and img ~= "" and not folderIcons[key] then
			local data = { Image = img }
			if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
				if inst.ImageRectSize ~= Vector2.zero then
					data.RectSize = inst.ImageRectSize
					data.RectOffset = inst.ImageRectOffset
				end
			end
			folderIcons[key] = data
			count += 1
		end
	end

	iconCache = {}
	warned = {}
	return count
end

-- WindUI as an image source (official function first, then its lucide table)
local function windIcon(clean)
	local wind = Library.WindUI or env.WindUI or _G.WindUI
	local result

	if type(wind) == "table" then
		local ok, res = pcall(function()
			return wind.Creator.Icons.Icon(clean, "lucide")
		end)
		if ok and res then result = parseIcon(res, nil) end
	end

	if not result then
		local set = Library.LucideIcons
		if not set and type(wind) == "table" then
			pcall(function() set = wind.Creator.Icons.Icons.lucide end)
		end
		if type(set) == "table" then
			local icons = type(set.Icons) == "table" and set.Icons or set
			result = parseIcon(icons[clean], set)
		end
	end

	return result
end

local function hasIconSource()
	return Library.IconResolver ~= nil
		or Library.LucideIcons ~= nil
		or Library.WindUI ~= nil
		or env.WindUI ~= nil
		or _G.WindUI ~= nil
		or next(folderIcons) ~= nil
		or next(Lucide.Assets) ~= nil
end

local noSourceWarned = false

local function resolveIcon(name)
	if type(name) ~= "string" or name == "" then return nil end
	if iconCache[name] ~= nil then return iconCache[name] or nil end

	local result

	if name:find("^rbxassetid://") or name:find("^rbxasset://") then
		result = { Image = name }
	else
		-- custom resolver
		if Library.IconResolver then
			local ok, res = pcall(Library.IconResolver, name)
			if ok and res then result = res end
		end

		-- registry: canonical name + alias, each checked against every image source
		if not result then
			for _, cand in ipairs(Lucide.Candidates(name)) do
				local asset = Lucide.Assets[cand]
				if asset ~= nil then result = parseIcon(asset, nil) end   -- 1) your asset ids
				if not result then result = folderIcons[iconKey(cand)] end -- 2) folder
				if not result then result = windIcon(cand) end            -- 3) WindUI
				if result then break end
			end
		end

		-- helpful one-time warnings (never for emoji / plain text glyphs)
		if not result and name:match("^[%w%-_:%s]+$") then
			if not hasIconSource() then
				if not noSourceWarned then
					noSourceWarned = true
					warn("[SimpleUI] Icon names alone can't be drawn - no image source is loaded. "
						.. "Use Library:LoadIcons(folder), Library:SetWindUI(WindUI) or Library:SetIconAssets({ house = 'rbxassetid://...' }).")
				end
			elseif not warned[name] then
				warned[name] = true
				local canon = Lucide.Canonical(name)
				if canon and Lucide.Has(canon) then
					warn("[SimpleUI] '" .. name .. "' is a valid Lucide name but none of your icon sources has an image for it.")
				else
					local similar = Lucide.Search(canon or name, 3)
					warn("[SimpleUI] Icon not found: '" .. name .. "'"
						.. (#similar > 0 and (" - did you mean: " .. table.concat(similar, ", ") .. "?") or ""))
				end
			end
		end
	end

	iconCache[name] = result or false
	return result
end

-- fallbackGlyph is shown when the icon can't be resolved
local function createIcon(parent, icon, size, color, fallbackGlyph)
	local data = resolveIcon(icon)
	if data and data.Image then
		local img = new("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
			Image = data.Image,
			ImageColor3 = color or Theme.Text,
		}, parent)
		if data.RectSize then img.ImageRectSize = data.RectSize end
		if data.RectOffset then img.ImageRectOffset = data.RectOffset end
		return img
	end

	local text = fallbackGlyph
	if not text then
		text = tostring(icon or "•")
		if text:match("^[%w%-_]+$") and #text > 1 then text = "•" end
	end
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Text = text,
		TextSize = size - 2,
		Font = Enum.Font.GothamBold,
		TextColor3 = color or Theme.Text,
	}, parent)
end

-- Public helpers
-- Library:Icon(parent, "house", 18, color) -> the icon instance (ImageLabel, or a glyph if no image)
function Library:Icon(parent, name, size, color)
	return createIcon(parent, name, size or 18, color or Theme.Text)
end

-- Library:HasIcon("house") -> true only if an image can really be drawn for it
function Library:HasIcon(name)
	return resolveIcon(name) ~= nil
end

--------------------------------------------------------------------
-- Dragging (returns a function telling whether a real drag happened)
--------------------------------------------------------------------
local function makeDraggable(handle, target, isEnabled)
	local dragging, dragStart, startPos = false, nil, nil
	local moved = false

	handle.InputBegan:Connect(function(input)
		if isEnabled and not isEnabled() then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)

	table.insert(State.Conns, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			if d.Magnitude > 5 then moved = true end
			if moved then
				target.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y
				)
			end
		end
	end))

	return function() return moved end
end

--------------------------------------------------------------------
-- Notify (bottom right)
-- Library:Notify({ Title, Content, Duration, Type = "info"|"success"|"warning"|"error", Icon, Color })
-- Click a notification to dismiss it early.
--------------------------------------------------------------------
local TextService = game:GetService("TextService")

local notifyHolder = new("Frame", {
	Name = "Notifications",
	ZIndex = 100,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.new(0, 300, 1, -32),
}, gui)

new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 8),
}, notifyHolder)

local notifyCount = 0

local NotifyTypes = {
	info = { color = nil, icon = "info", glyph = "i" }, -- nil = theme accent
	success = { color = Color3.fromRGB(60, 200, 100), icon = "check", glyph = "✓" },
	warning = { color = Color3.fromRGB(245, 180, 50), icon = "triangle-alert", glyph = "!" },
	error = { color = Color3.fromRGB(235, 70, 70), icon = "x", glyph = "✕" },
}

function Library:Notify(opts)
	opts = opts or {}
	local duration = opts.Duration or 4
	local kind = NotifyTypes[tostring(opts.Type or "info"):lower()] or NotifyTypes.info
	local accent = opts.Color or kind.color or Theme.Accent
	notifyCount += 1

	local WIDTH = 300
	local content = tostring(opts.Content or "")

	-- measure the message so the card fits it exactly
	local textH = 0
	if content ~= "" then
		local ok, size = pcall(function()
			return TextService:GetTextSize(content, 12, Enum.Font.Gotham, Vector2.new(WIDTH - 54 - 14, 10000))
		end)
		textH = ok and size.Y or 16
	end
	local height = math.max(58, 30 + textH + 18)

	local slot = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(WIDTH, height),
		LayoutOrder = notifyCount,
	}, notifyHolder)

	local card = new("CanvasGroup", {
		BackgroundColor3 = Theme.Surface,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(70, 0),
		GroupTransparency = 1,
	}, slot)
	corner(card, 10)
	stroke(card, Theme.Stroke)

	-- colored edge
	new("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
	}, card)

	-- icon badge
	local badge = new("Frame", {
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.82,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.fromOffset(28, 28),
	}, card)
	corner(badge, 14)
	local ic = createIcon(badge, opts.Icon or kind.icon, 16, accent, kind.glyph)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(54, 9),
		Size = UDim2.new(1, -68, 0, 18),
		Text = tostring(opts.Title or "Notification"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, card)

	if content ~= "" then
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(54, 28),
			Size = UDim2.new(1, -68, 0, textH),
			Text = content,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = Theme.SubText,
		}, card)
	end

	-- progress bar (shrinks until the notification disappears)
	local track = new("Frame", {
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 3, 1, -3),
		Size = UDim2.new(1, -3, 0, 3),
	}, card)
	local fill = new("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, track)

	local click = new("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 5,
	}, card)

	-- slide in + fade in
	tween(card, 0.3, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, Enum.EasingStyle.Quint)
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		if not slot.Parent then return end
		-- slide out + fade out, then the stack collapses smoothly
		tween(card, 0.22, { Position = UDim2.fromOffset(70, 0), GroupTransparency = 1 })
		task.wait(0.23)
		if not slot.Parent then return end
		tween(slot, 0.15, { Size = UDim2.fromOffset(WIDTH, 0) })
		task.wait(0.16)
		slot:Destroy()
	end

	click.Activated:Connect(function() task.spawn(dismiss) end)
	task.delay(duration, dismiss)

	return { Dismiss = function() task.spawn(dismiss) end }
end

--------------------------------------------------------------------
-- Key system (separate from the window)
-- local passed = Library:KeySystem({ Title, Key, Link, Callback })
-- Yields until the key is correct (returns true) or the window is closed
-- (returns false). Pass Wait = false to not yield.
--------------------------------------------------------------------
local function copyToClipboard(text)
	local fn = setclipboard or toclipboard or set_clipboard
	if not fn and Clipboard and type(Clipboard.set) == "function" then
		fn = Clipboard.set
	end
	if not fn then return false end
	return (pcall(fn, text))
end

function Library:KeySystem(opts)
	opts = opts or {}

	if Library.KeyFrame and Library.KeyFrame.Parent then
		warn("[SimpleUI] The key window is already open.")
		return false
	end

	applyTheme(opts.Color, opts.Accent)
	local bg, accent = Theme.Background, Theme.Accent

	-- accepted keys: a string, a number, or a table of them
	local validKeys = {}
	if type(opts.Key) == "table" then
		for _, v in ipairs(opts.Key) do validKeys[tostring(v)] = true end
	elseif opts.Key ~= nil then
		validKeys[tostring(opts.Key)] = true
	end

	local link = opts.Link and tostring(opts.Link) or ""
	local hasLink = link ~= ""
	local checkY = hasLink and 174 or 126

	local done = Instance.new("BindableEvent")
	local finished = false

	local overlay = new("TextButton", {
		Name = "KeySystem",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 40,
	}, gui)
	Library.KeyFrame = overlay

	local function finish(result)
		if finished then return end
		finished = true
		Library.KeyFrame = nil
		pcall(function() overlay:Destroy() end)
		if result then safeCall(opts.Callback) end
		done:Fire(result)
	end
	overlay.Destroying:Connect(function() finish(false) end)

	local box = new("Frame", {
		BackgroundColor3 = bg,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, checkY + 38 + 24),
		ClipsDescendants = true,
	}, overlay)
	corner(box, 12)
	stroke(box, Theme.Stroke)

	-- header: icon + key page title + close
	local keyIcon = opts.Icon or "rbxassetid://97389060854402" -- default key window image
	local keyIconIsAsset = type(keyIcon) == "string" and keyIcon:find("^rbxasset") ~= nil
	local ic = createIcon(box, keyIcon, 24, keyIconIsAsset and Color3.new(1, 1, 1) or Theme.Text, "🔑")
	ic.Position = UDim2.fromOffset(14, 10)
	if ic:IsA("ImageLabel") then corner(ic, 6) end

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -90, 0, 44),
		Text = tostring(opts.Title or "Key System"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, box)

	local closeKey = new("TextButton", {
		BackgroundColor3 = Theme.Surface,
		Position = UDim2.new(1, -38, 0, 8),
		Size = UDim2.fromOffset(28, 28),
		Text = "✕",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Theme.SubText,
		AutoButtonColor = false,
	}, box)
	corner(closeKey, 8)

	new("Frame", {
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 1),
	}, box)

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 54),
		Size = UDim2.new(1, -32, 0, 16),
		Text = tostring(opts.Description or "Enter your key to continue."),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Theme.SubText,
	}, box)

	-- key input
	local input = new("TextBox", {
		BackgroundColor3 = Theme.Surface,
		Position = UDim2.fromOffset(16, 78),
		Size = UDim2.new(1, -32, 0, 38),
		Text = "",
		PlaceholderText = "Enter key...",
		PlaceholderColor3 = Theme.SubText,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		ClearTextOnFocus = false,
	}, box)
	corner(input, 8)
	local inputStroke = stroke(input, Theme.Stroke)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, input)

	-- key link + copy button
	if hasLink then
		local linkBox = new("Frame", {
			BackgroundColor3 = Theme.Surface,
			Position = UDim2.fromOffset(16, 126),
			Size = UDim2.new(1, -124, 0, 34),
		}, box)
		corner(linkBox, 8)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			Text = link,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = Theme.SubText,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, linkBox)

		local copyBtn = new("TextButton", {
			BackgroundColor3 = Theme.SurfaceHover,
			Position = UDim2.new(1, -100, 0, 126),
			Size = UDim2.fromOffset(84, 34),
			Text = "Copy Link",
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = Theme.Text,
			AutoButtonColor = false,
		}, box)
		corner(copyBtn, 8)

		copyBtn.Activated:Connect(function()
			local ok = copyToClipboard(link)
			copyBtn.Text = ok and "Copied!" or "Failed"
			Library:Notify({
				Title = "Key Link",
				Content = ok and "Link copied to clipboard." or ("Clipboard not supported. Link: " .. link),
				Duration = 3,
			})
			task.delay(1.5, function()
				if copyBtn.Parent then copyBtn.Text = "Copy Link" end
			end)
		end)
	end

	-- check button
	local checkBtn = new("TextButton", {
		BackgroundColor3 = accent,
		Position = UDim2.fromOffset(16, checkY),
		Size = UDim2.new(1, -32, 0, 38),
		Text = "Check Key",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
	}, box)
	corner(checkBtn, 8)

	local function check()
		local entered = (input.Text:gsub("^%s+", ""))
		entered = (entered:gsub("%s+$", ""))

		local ok
		if type(opts.Validate) == "function" then
			local s, res = pcall(opts.Validate, entered)
			ok = s and res == true
		else
			ok = validKeys[entered] == true
		end

		if ok then
			Library:Notify({
				Title = "Key System",
				Content = "Key accepted. Welcome!",
				Duration = 3,
				Color = Color3.fromRGB(60, 200, 100),
			})
			finish(true)
		else
			Library:Notify({
				Title = "Key System",
				Content = entered == "" and "Please enter a key." or "Invalid key. Please try again.",
				Duration = 3,
				Color = Theme.Danger,
			})
			inputStroke.Color = Theme.Danger
			task.delay(0.8, function()
				if inputStroke.Parent then inputStroke.Color = Theme.Stroke end
			end)
		end
	end

	checkBtn.Activated:Connect(check)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then check() end
	end)
	closeKey.Activated:Connect(function() finish(false) end)

	if opts.Wait == false then return end
	return done.Event:Wait()
end

--------------------------------------------------------------------
-- Window
--------------------------------------------------------------------
function Library:CreateWindow(opts)
	-- Only one window is ever allowed
	if Library.Window then
		warn("[SimpleUI] A window already exists, returning the existing one.")
		return Library.Window
	end

	opts = opts or {}
	local Window = { Tabs = {}, Current = nil }
	Library.Window = Window -- set immediately (before anything can yield)

	-- Only 4 options: Title, Description, Color (by name), Size
	applyTheme(opts.Color) -- e.g. Color = "Red" / "Dark" / "Blue" / "Purple" / "Green"
	local bg = Theme.Background
	local accent = Theme.Accent

	local fullSize = opts.Size or UDim2.new(0, 550, 0, 356)
	pcall(function()
		-- keep the window inside small screens
		local vp = workspace.CurrentCamera.ViewportSize
		if fullSize.X.Scale == 0 and fullSize.Y.Scale == 0 then
			fullSize = UDim2.fromOffset(
				math.min(fullSize.X.Offset, vp.X - 24),
				math.min(fullSize.Y.Offset, vp.Y - 24)
			)
		end
	end)

	-- CanvasGroup so the whole window can fade (GroupTransparency) and scale (UIScale)
	local main = new("CanvasGroup", {
		Name = "Window",
		BackgroundColor3 = bg,
		GroupTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = fullSize,
	}, gui)
	corner(main, 12)
	stroke(main, Theme.Stroke)
	local mainScale = new("UIScale", { Scale = 1 }, main)

	-- Topbar
	local top = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
	}, main)

	local hasDesc = opts.Description ~= nil and opts.Description ~= ""

	-- script name (big title)
	local titleLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, hasDesc and 6 or 13),
		Size = UDim2.new(1, -134, 0, 20),
		Text = tostring(opts.Title or "Script Name"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextColor3 = Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, top)

	-- description directly under the title
	local descLabel
	if hasDesc then
		descLabel = new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 27),
			Size = UDim2.new(1, -134, 0, 14),
			Text = tostring(opts.Description),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextColor3 = Theme.SubText,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, top)
	end

	-- Tags: framed words next to the title (version, status, ...)  ->  Window:Tag({ Text, Color, Size, Rounded })
	local titleX = 14
	local tagHolder = new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
	}, top)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tagHolder)

	-- keeps the tags right after the title text (also after SetIcon moves the title)
	local function layoutTags()
		local w = 0
		pcall(function()
			w = TextService:GetTextSize(titleLabel.Text, titleLabel.TextSize, titleLabel.Font, Vector2.new(1000, 24)).X
		end)
		tagHolder.Position = UDim2.fromOffset(titleX + w + 10, hasDesc and 16 or 23)
	end
	layoutTags()

	-- optional: icon at the left of the title -> Window:SetIcon("house")
	local iconObj
	function Window:SetIcon(icon)
		if iconObj then iconObj:Destroy(); iconObj = nil end
		local x = 14
		if icon then
			iconObj = createIcon(top, icon, 22, Theme.Text)
			iconObj.Position = UDim2.fromOffset(14, 13)
			x = 44
		end
		titleX = x
		titleLabel.Position = UDim2.fromOffset(x, hasDesc and 6 or 13)
		titleLabel.Size = UDim2.new(1, -(x + 120), 0, 20)
		if descLabel then
			descLabel.Position = UDim2.fromOffset(x, 27)
			descLabel.Size = UDim2.new(1, -(x + 120), 0, 14)
		end
		layoutTags()
	end
	if opts.Icon then Window:SetIcon(opts.Icon) end -- icon at the left of the title

	local tagCount = 0
	function Window:Tag(topts)
		topts = topts or {}
		tagCount += 1
		local Tag = {}
		local text = tostring(topts.Text or "Tag")
		local rounded = topts.Rounded ~= false -- soft corners by default

		local function pick(c)
			local bgColor, accentColor = lookupColor(c) -- color NAME (or Color3)
			return accentColor or bgColor or accent
		end
		local color = pick(topts.Color)

		local function autoSize()
			local w = 30
			pcall(function()
				w = TextService:GetTextSize(text, 11, Enum.Font.GothamBold, Vector2.new(400, 20)).X
			end)
			return UDim2.fromOffset(w + 18, 18)
		end

		local frame = new("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = 0.82,
			Size = topts.Size or autoSize(),
			LayoutOrder = tagCount,
		}, tagHolder)
		local frameCorner = new("UICorner", {
			CornerRadius = rounded and UDim.new(0.5, 0) or UDim.new(0, 0),
		}, frame)
		local frameStroke = stroke(frame, color)
		frameStroke.Transparency = 0.5

		local label = new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = text,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2),
		}, frame)

		function Tag:SetText(t)
			text = tostring(t)
			label.Text = text
			if not topts.Size then frame.Size = autoSize() end
		end
		function Tag:SetColor(c)
			color = pick(c)
			frame.BackgroundColor3 = color
			frameStroke.Color = color
			label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2)
		end
		function Tag:SetRounded(r)
			frameCorner.CornerRadius = r and UDim.new(0.5, 0) or UDim.new(0, 0)
		end
		function Tag:Destroy() frame:Destroy() end
		return Tag
	end

	-- Title bar buttons: [Hide] [Minimize] [Close]
	local function topButton(xOffset, iconName, glyph, hoverColor)
		local b = new("TextButton", {
			BackgroundColor3 = Theme.Surface,
			Position = UDim2.new(1, xOffset, 0, 10),
			Size = UDim2.fromOffset(28, 28),
			Text = "",
			AutoButtonColor = false,
		}, top)
		corner(b, 8)
		local ic = createIcon(b, iconName, 14, Theme.SubText, glyph)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		b.MouseEnter:Connect(function()
			tween(b, 0.1, { BackgroundColor3 = hoverColor or Theme.SurfaceHover })
		end)
		b.MouseLeave:Connect(function()
			tween(b, 0.1, { BackgroundColor3 = Theme.Surface })
		end)
		return b
	end

	local hideBtn = topButton(-106, "eye-off", "–")
	local minBtn = topButton(-72, "minimize-2", "▭")
	local closeBtn = topButton(-38, "x", "✕", Theme.Danger)

	local divider = new("Frame", {
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 47),
		Size = UDim2.new(1, 0, 0, 1),
	}, main)

	makeDraggable(top, main)

	-- Body (sidebar + pages), hidden while minimized
	local body = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
	}, main)

	local sidebar = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 140, 1, 0),
	}, body)

	local tabList = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, sidebar)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabList)

	-- optional: logo at the bottom of the sidebar -> Window:SetLogo("rbxassetid://123")
	local logoObj
	function Window:SetLogo(image)
		if logoObj then logoObj:Destroy(); logoObj = nil end
		if image then
			logoObj = new("ImageLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 14, 1, -10),
				Size = UDim2.fromOffset(28, 28),
				Image = image,
			}, sidebar)
			corner(logoObj, 6)
		end
		tabList.Size = UDim2.new(1, -16, 1, image and -52 or -16)
	end

	new("Frame", {
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -1, 0, 8),
		Size = UDim2.new(0, 1, 1, -16),
	}, sidebar)

	local pages = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(148, 8),
		Size = UDim2.new(1, -156, 1, -16),
	}, body)

	--------------------------------------------------------------
	-- Open Button
	-- Window:OpenButton({ Name, Size, Image, Color (name), Position, Draggable })
	--------------------------------------------------------------
	local openBtn = new("TextButton", {
		Name = "OpenButton",
		BackgroundColor3 = Theme.Background,
		Position = UDim2.new(0, 20, 0.5, -24),
		Size = UDim2.fromOffset(48, 48),
		Text = "",
		AutoButtonColor = false,
	}, gui)
	corner(openBtn, 12)
	local openStroke = stroke(openBtn, Theme.Stroke)
	local openScale = new("UIScale", { Scale = 1 }, openBtn)

	local openContent = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, openBtn)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, openContent)

	local openCfg = { Image = nil, Name = nil }

	local function refreshOpenButton()
		for _, c in ipairs(openContent:GetChildren()) do
			if not c:IsA("UIListLayout") then c:Destroy() end
		end

		local h = openBtn.Size.Y.Offset
		if h <= 0 then h = 48 end
		local hasImage = openCfg.Image ~= nil and openCfg.Image ~= ""
		local hasName = openCfg.Name ~= nil and openCfg.Name ~= ""

		-- image / icon (or the default menu glyph when nothing is set)
		if hasImage or not hasName then
			local size = math.floor(h * (hasName and 0.45 or 0.55))
			local isAsset = type(openCfg.Image) == "string" and openCfg.Image:find("^rbxasset") ~= nil
			local ic = createIcon(openContent, hasImage and openCfg.Image or "menu", size,
				isAsset and Color3.new(1, 1, 1) or Theme.Text, "☰")
			ic.LayoutOrder = 1
		end

		-- name
		if hasName then
			local ts = math.clamp(math.floor(h * 0.22), 9, 14)
			new("TextLabel", {
				BackgroundTransparency = 1,
				Size = hasImage and UDim2.new(1, -6, 0, ts + 2) or UDim2.new(1, -8, 1, 0),
				LayoutOrder = 2,
				Text = tostring(openCfg.Name),
				Font = Enum.Font.GothamBold,
				TextSize = hasImage and ts or math.clamp(math.floor(h * 0.28), 10, 16),
				TextColor3 = Theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, openContent)
		end
	end
	refreshOpenButton()

	-- hover / press animation
	openBtn.MouseEnter:Connect(function()
		tween(openScale, 0.12, { Scale = 1.07 })
		tween(openStroke, 0.12, { Color = accent })
	end)
	openBtn.MouseLeave:Connect(function()
		tween(openScale, 0.12, { Scale = 1 })
		tween(openStroke, 0.12, { Color = Theme.Stroke })
	end)
	openBtn.MouseButton1Down:Connect(function() tween(openScale, 0.08, { Scale = 0.92 }) end)
	openBtn.MouseButton1Up:Connect(function() tween(openScale, 0.12, { Scale = 1 }) end)

	local openDraggable = true
	local wasDragged = makeDraggable(openBtn, openBtn, function() return openDraggable end)

	function Window:OpenButton(cfg)
		cfg = cfg or {}
		if cfg.Size then openBtn.Size = cfg.Size end
		if cfg.Position then openBtn.Position = cfg.Position end
		if cfg.Color then
			local c = (lookupColor(cfg.Color))
			if c then openBtn.BackgroundColor3 = c end
		end
		if cfg.Image ~= nil then openCfg.Image = cfg.Image end
		if cfg.Name ~= nil then openCfg.Name = cfg.Name end
		if cfg.Draggable ~= nil then openDraggable = cfg.Draggable end
		refreshOpenButton()
	end

	--------------------------------------------------------------
	-- Window controls
	--------------------------------------------------------------
	local minimized = false
	local savedPos = main.Position

	local visible = true
	local animToken = 0

	-- page transition: the new page slides up + fades in
	local function showPage(tab, animate)
		local wrap = tab._page
		wrap.Visible = true
		if animate then
			wrap.GroupTransparency = 1
			wrap.Position = UDim2.fromOffset(0, 14)
			tween(wrap, 0.22, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
		else
			wrap.GroupTransparency = 0
			wrap.Position = UDim2.fromOffset(0, 0)
		end
	end

	-- tab buttons slide in / out of the sidebar, one after another
	local function animateTabs(showing, token)
		for i, t in ipairs(Window.Tabs) do
			local b = t._btn
			if showing then b.Position = UDim2.new(-1, 0, 0, 0) end
			task.delay((i - 1) * 0.04, function()
				if token ~= animToken then return end
				tween(b, 0.22, {
					Position = showing and UDim2.new(0, 0, 0, 0) or UDim2.new(-1, 0, 0, 0),
				}, Enum.EasingStyle.Quint)
			end)
		end
	end

	function Window:Hide()
		if not visible then return end
		visible = false
		animToken += 1
		local token = animToken
		animateTabs(false, token)
		tween(main, 0.2, { GroupTransparency = 1 })
		tween(mainScale, 0.2, { Scale = 0.9 })
		task.delay(0.22, function()
			if token == animToken and not visible then main.Visible = false end
		end)
	end

	function Window:Show()
		if visible then return end
		visible = true
		animToken += 1
		local token = animToken
		main.Visible = true
		main.GroupTransparency = 1
		mainScale.Scale = 0.9
		tween(main, 0.22, { GroupTransparency = 0 })
		tween(mainScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
		animateTabs(true, token)
		if Window.Current then showPage(Window.Current, true) end
	end

	function Window:Toggle()
		if visible then Window:Hide() else Window:Show() end
	end

	function Window:SetMinimized(v)
		if v == minimized then return end
		minimized = v
		if v then
			-- collapse to the title bar only, centered on screen
			savedPos = main.Position
			body.Visible = false
			divider.Visible = false
			tween(main, 0.15, {
				Size = UDim2.new(fullSize.X.Scale, fullSize.X.Offset, 0, 48),
				Position = UDim2.fromScale(0.5, 0.5),
			})
		else
			-- restore the frame; the title bar goes back up to where it was
			body.Visible = true
			divider.Visible = true
			tween(main, 0.15, { Size = fullSize, Position = savedPos })
		end
	end

	function Window:Destroy()
		destroyAll()
	end

	local confirmOpen = false
	local function confirmDelete()
		if confirmOpen then return end
		confirmOpen = true

		local overlay = new("TextButton", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			Size = UDim2.fromScale(1, 1),
			Text = "",
			AutoButtonColor = false,
			ZIndex = 50,
		}, gui)

		local box = new("Frame", {
			BackgroundColor3 = bg,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(280, 132),
		}, overlay)
		corner(box, 12)
		stroke(box, Theme.Stroke)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 20),
			Text = "Delete UI",
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = Theme.Text,
		}, box)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 36),
			Size = UDim2.new(1, -32, 0, 36),
			Text = "Are you sure you want to delete this UI? This action cannot be undone.",
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = Theme.SubText,
		}, box)

		local function dialogButton(text, x, color, textColor)
			local b = new("TextButton", {
				BackgroundColor3 = color,
				Position = UDim2.new(0, x, 1, -44),
				Size = UDim2.new(0.5, -22, 0, 32),
				Text = text,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = textColor,
				AutoButtonColor = false,
			}, box)
			corner(b, 8)
			return b
		end

		local cancel = dialogButton("Cancel", 16, Theme.Surface, Theme.Text)
		local delete = dialogButton("Delete", 150, Theme.Danger, Color3.new(1, 1, 1))

		cancel.Activated:Connect(function()
			confirmOpen = false
			overlay:Destroy()
		end)
		delete.Activated:Connect(function()
			Window:Destroy()
		end)
	end

	openBtn.Activated:Connect(function()
		if not wasDragged() then Window:Toggle() end
	end)
	hideBtn.Activated:Connect(function() Window:Hide() end)
	minBtn.Activated:Connect(function() Window:SetMinimized(not minimized) end)
	closeBtn.Activated:Connect(confirmDelete)

	--------------------------------------------------------------
	-- Tabs
	-- NOTE: internal fields are named _btn / _page on purpose.
	-- (Tab.Button would collide with the Tab:Button() method.)
	--------------------------------------------------------------
	local function setActive(t, active, instant)
		local bgT = active and 0 or 1
		local barSize = UDim2.fromOffset(3, active and 16 or 0)
		if instant then
			t._btn.BackgroundTransparency = bgT
			t._bar.Size = barSize
		else
			tween(t._btn, 0.15, { BackgroundTransparency = bgT })
			tween(t._bar, 0.18, { Size = barSize })
		end
	end

	local function selectTab(tab, instant)
		if Window.Current == tab then return end
		local previous = Window.Current
		Window.Current = tab

		for _, t in ipairs(Window.Tabs) do
			setActive(t, t == tab, instant)
		end

		if instant then
			showPage(tab, false)
			return
		end

		-- exit animation for the old page, then enter animation for the new one
		if previous then
			local old = previous._page
			tween(old, 0.12, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -10) })
			task.delay(0.13, function()
				if Window.Current ~= previous then old.Visible = false end
			end)
		end

		local wrap = tab._page
		wrap.Visible = true
		wrap.GroupTransparency = 1
		wrap.Position = UDim2.fromOffset(0, 14)
		task.delay(previous and 0.08 or 0, function()
			if Window.Current == tab then
				tween(wrap, 0.22, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
			end
		end)
	end

	function Window:Tab(topts)
		topts = topts or {}
		local Tab = {}

		-- slot clips the button so it can slide in from the left
		local slot = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			ClipsDescendants = true,
			LayoutOrder = #Window.Tabs + 1,
		}, tabList)

		local btn = new("TextButton", {
			BackgroundColor3 = Theme.Surface,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = "",
			AutoButtonColor = false,
		}, slot)
		corner(btn, 8)

		-- accent bar shown on the active tab
		local bar = new("Frame", {
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(3, 0),
		}, btn)
		corner(bar, 2)

		local ic = createIcon(btn, topts.Icon, 18, Theme.Text)
		ic.Position = UDim2.new(0, 10, 0.5, -9)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(36, 0),
			Size = UDim2.new(1, -42, 1, 0),
			Text = tostring(topts.Title or "Tab"),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = Theme.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, btn)

		-- wrapper (CanvasGroup) is what fades/slides; `page` is the scrolling content
		local wrap = new("CanvasGroup", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
		}, pages)

		local page = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.Stroke,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
		}, wrap)
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		new("UIPadding", { PaddingRight = UDim.new(0, 6) }, page)

		Tab._btn = btn
		Tab._bar = bar
		Tab._page = wrap
		table.insert(Window.Tabs, Tab)

		btn.Activated:Connect(function() selectTab(Tab) end)
		if #Window.Tabs == 1 then selectTab(Tab, true) end

		-- Shared card for Button / Toggle
		local function makeCard(o)
			local hasDesc = o.Desc and o.Desc ~= ""
			local card = new("TextButton", {
				BackgroundColor3 = Theme.Surface,
				Size = UDim2.new(1, 0, 0, hasDesc and 52 or 38),
				Text = "",
				AutoButtonColor = false,
			}, page)
			corner(card, 8)
			stroke(card, Theme.Stroke)

			new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, hasDesc and 8 or 0),
				Size = UDim2.new(1, -70, 0, hasDesc and 18 or 38),
				Text = tostring(o.Title or "Item"),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = Theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)

			if hasDesc then
				new("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 27),
					Size = UDim2.new(1, -70, 0, 16),
					Text = tostring(o.Desc),
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextColor3 = Theme.SubText,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}, card)
			end

			-- hover + press animation
			local cardScale = new("UIScale", { Scale = 1 }, card)
			card.MouseEnter:Connect(function() tween(card, 0.1, { BackgroundColor3 = Theme.SurfaceHover }) end)
			card.MouseLeave:Connect(function()
				tween(card, 0.1, { BackgroundColor3 = Theme.Surface })
				tween(cardScale, 0.1, { Scale = 1 })
			end)
			card.MouseButton1Down:Connect(function() tween(cardScale, 0.08, { Scale = 0.975 }) end)
			card.MouseButton1Up:Connect(function() tween(cardScale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back) end)
			return card
		end

		-- Button
		function Tab:Button(o)
			o = o or {}
			local card = makeCard(o)
			new("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(16, 16),
				Text = "›",
				Font = Enum.Font.GothamBold,
				TextSize = 18,
				TextColor3 = Theme.SubText,
			}, card)
			card.Activated:Connect(function() safeCall(o.Callback) end)
			return card
		end

		-- Toggle
		function Tab:Toggle(o)
			o = o or {}
			local state = o.Default == true
			local card = makeCard(o)

			local track = new("Frame", {
				BackgroundColor3 = state and accent or Theme.Stroke,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(38, 20),
			}, card)
			corner(track, 10)

			local knob = new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				Position = state and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3),
				Size = UDim2.fromOffset(14, 14),
			}, track)
			corner(knob, 7)

			local Toggle = {}
			local function apply(v, silent)
				state = v
				tween(track, 0.12, { BackgroundColor3 = state and accent or Theme.Stroke })
				tween(knob, 0.12, { Position = state and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3) })
				if not silent then safeCall(o.Callback, state) end
			end

			function Toggle:Set(v) apply(v == true) end
			function Toggle:Get() return state end

			card.Activated:Connect(function() apply(not state) end)
			if state then safeCall(o.Callback, true) end
			return Toggle
		end

		-- Dropdown: Tab:Dropdown({ Title, Desc, Options, Default, Multi, Callback })
		-- The list opens inside the window (the card expands smoothly).
		-- Single: Callback(value)   |   Multi = true: Callback({ values })
		function Tab:Dropdown(o)
			o = o or {}
			local options = o.Options or o.Values or {}
			local multi = o.Multi == true
			local hasDesc = o.Desc and o.Desc ~= ""
			local headerH = hasDesc and 52 or 38
			local ITEM_H, GAP, MAX_H = 28, 3, 140

			local container = new("Frame", {
				BackgroundColor3 = Theme.Surface,
				Size = UDim2.new(1, 0, 0, headerH),
				ClipsDescendants = true,
			}, page)
			corner(container, 8)
			stroke(container, Theme.Stroke)

			local header = new("TextButton", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, headerH),
				Text = "",
				AutoButtonColor = false,
			}, container)

			new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, hasDesc and 8 or 0),
				Size = UDim2.new(1, -150, 0, hasDesc and 18 or headerH),
				Text = tostring(o.Title or "Dropdown"),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = Theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, header)

			if hasDesc then
				new("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 27),
					Size = UDim2.new(1, -150, 0, 16),
					Text = tostring(o.Desc),
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextColor3 = Theme.SubText,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}, header)
			end

			local valueLabel = new("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -34, 0, headerH / 2),
				Size = UDim2.fromOffset(110, 18),
				Text = "None",
				TextXAlignment = Enum.TextXAlignment.Right,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = Theme.SubText,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, header)

			local arrow = new("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -18, 0, headerH / 2),
				Size = UDim2.fromOffset(16, 16),
				Text = "▾",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Theme.SubText,
			}, header)

			local panel = new("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(6, headerH),
				Size = UDim2.new(1, -12, 0, 0),
				ScrollBarThickness = 2,
				ScrollBarImageColor3 = Theme.Stroke,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
			}, container)
			new("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

			-- state
			local selected = {} -- multi: set of names
			local single = nil  -- single: chosen name
			if multi then
				if type(o.Default) == "table" then
					for _, v in ipairs(o.Default) do selected[tostring(v)] = true end
				end
			elseif o.Default ~= nil then
				single = tostring(o.Default)
			end

			local buttons = {}
			local panelH = 0
			local open = false

			local function isOn(name)
				if multi then return selected[name] == true end
				return single == name
			end

			local function getValue()
				if multi then
					local list = {}
					for _, opt in ipairs(options) do
						if selected[tostring(opt)] then table.insert(list, tostring(opt)) end
					end
					return list
				end
				return single
			end

			local function paint()
				for name, b in pairs(buttons) do
					local on = isOn(name)
					tween(b.btn, 0.12, { BackgroundTransparency = on and 0.72 or 1 })
					b.check.Visible = on
				end
				if multi then
					local list = getValue()
					valueLabel.Text = #list > 0 and table.concat(list, ", ") or "None"
				else
					valueLabel.Text = single or "None"
				end
			end

			local function fire()
				safeCall(o.Callback, getValue())
			end

			local function setOpen(v)
				open = v
				local target = headerH + (v and (panelH + 8) or 0)
				tween(container, 0.2, { Size = UDim2.new(1, 0, 0, target) }, Enum.EasingStyle.Quint)
				tween(arrow, 0.2, { Rotation = v and 180 or 0 })
			end

			local function choose(name)
				if multi then
					selected[name] = (not selected[name]) or nil
				else
					single = name
				end
				paint()
				fire()
				if not multi then setOpen(false) end
			end

			local function build()
				for _, c in ipairs(panel:GetChildren()) do
					if c:IsA("TextButton") then c:Destroy() end
				end
				buttons = {}

				for i, opt in ipairs(options) do
					local name = tostring(opt)
					local b = new("TextButton", {
						BackgroundColor3 = accent,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, ITEM_H),
						Text = "",
						AutoButtonColor = false,
						LayoutOrder = i,
					}, panel)
					corner(b, 6)

					new("TextLabel", {
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(10, 0),
						Size = UDim2.new(1, -36, 1, 0),
						Text = name,
						TextXAlignment = Enum.TextXAlignment.Left,
						Font = Enum.Font.GothamMedium,
						TextSize = 12,
						TextColor3 = Theme.Text,
						TextTruncate = Enum.TextTruncate.AtEnd,
					}, b)

					local check = new("TextLabel", {
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -10, 0.5, 0),
						Size = UDim2.fromOffset(14, 14),
						Text = "✓",
						Font = Enum.Font.GothamBold,
						TextSize = 12,
						TextColor3 = Theme.Text,
						Visible = false,
					}, b)

					b.MouseEnter:Connect(function()
						if not isOn(name) then tween(b, 0.1, { BackgroundTransparency = 0.9 }) end
					end)
					b.MouseLeave:Connect(function()
						if not isOn(name) then tween(b, 0.1, { BackgroundTransparency = 1 }) end
					end)
					b.Activated:Connect(function() choose(name) end)

					buttons[name] = { btn = b, check = check }
				end

				panelH = math.min(#options * (ITEM_H + GAP), MAX_H)
				panel.Size = UDim2.new(1, -12, 0, panelH)
				paint()
				if open then
					container.Size = UDim2.new(1, 0, 0, headerH + panelH + 8)
				end
			end

			header.Activated:Connect(function() setOpen(not open) end)
			header.MouseEnter:Connect(function() tween(container, 0.1, { BackgroundColor3 = Theme.SurfaceHover }) end)
			header.MouseLeave:Connect(function() tween(container, 0.1, { BackgroundColor3 = Theme.Surface }) end)

			build()

			local Dropdown = {}
			function Dropdown:Get() return getValue() end
			function Dropdown:Set(v, silent)
				if multi then
					selected = {}
					if type(v) == "table" then
						for _, x in ipairs(v) do selected[tostring(x)] = true end
					end
				else
					single = v ~= nil and tostring(v) or nil
				end
				paint()
				if not silent then fire() end
			end
			function Dropdown:Refresh(newOptions)
				options = newOptions or {}
				local valid = {}
				for _, opt in ipairs(options) do valid[tostring(opt)] = true end
				for name in pairs(selected) do
					if not valid[name] then selected[name] = nil end
				end
				if single and not valid[single] then single = nil end
				build()
			end
			function Dropdown:Open() setOpen(true) end
			function Dropdown:Close() setOpen(false) end
			return Dropdown
		end

		-- Input (text box): Tab:Input({ Title, Desc, Placeholder, Default, Numeric, ClearOnFocus, Callback })
		-- Callback(text, enterPressed) fires when the box loses focus (Enter or tapping away).
		function Tab:Input(o)
			o = o or {}
			local hasDesc = o.Desc and o.Desc ~= ""

			local card = new("Frame", {
				BackgroundColor3 = Theme.Surface,
				Size = UDim2.new(1, 0, 0, hasDesc and 52 or 42),
			}, page)
			corner(card, 8)
			stroke(card, Theme.Stroke)

			new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, hasDesc and 8 or 0),
				Size = UDim2.new(1, -170, 0, hasDesc and 18 or 42),
				Text = tostring(o.Title or "Input"),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = Theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)

			if hasDesc then
				new("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 27),
					Size = UDim2.new(1, -170, 0, 16),
					Text = tostring(o.Desc),
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextColor3 = Theme.SubText,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}, card)
			end

			local boxFrame = new("Frame", {
				BackgroundColor3 = Theme.Background,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(140, 28),
			}, card)
			corner(boxFrame, 6)
			local boxStroke = stroke(boxFrame, Theme.Stroke)

			local box = new("TextBox", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(1, -16, 1, 0),
				Text = tostring(o.Default or ""),
				PlaceholderText = tostring(o.Placeholder or "Type here..."),
				PlaceholderColor3 = Theme.SubText,
				TextColor3 = Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				ClearTextOnFocus = o.ClearOnFocus == true,
			}, boxFrame)

			-- focus animation: the box grows a little and the border lights up
			box.Focused:Connect(function()
				tween(boxStroke, 0.15, { Color = accent })
				tween(boxFrame, 0.18, { Size = UDim2.fromOffset(165, 28) }, Enum.EasingStyle.Quint)
			end)
			box.FocusLost:Connect(function(enterPressed)
				tween(boxStroke, 0.15, { Color = Theme.Stroke })
				tween(boxFrame, 0.18, { Size = UDim2.fromOffset(140, 28) }, Enum.EasingStyle.Quint)
				safeCall(o.Callback, box.Text, enterPressed)
			end)

			if o.Numeric then
				box:GetPropertyChangedSignal("Text"):Connect(function()
					local clean = box.Text:gsub("[^%d%.%-]", "")
					if clean ~= box.Text then box.Text = clean end
				end)
			end

			local Input = {}
			function Input:Set(t) box.Text = tostring(t) end
			function Input:Get() return box.Text end
			return Input
		end

		function Tab:Textbox(o) return Tab:Input(o) end

		-- Section: Tab:Section("Title")  - a small heading that groups the elements below it
		function Tab:Section(title)
			if type(title) == "table" then title = title.Title end
			local frame = new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 24),
			}, page)
			new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(1, -8, 1, -4),
				Text = string.upper(tostring(title or "")),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = Theme.SubText,
			}, frame)
			return frame
		end

		-- ColorPicker: Tab:ColorPicker({ Title, Desc, Default (Color3), Callback })
		-- Click the card: the picker opens inside the window (saturation/value square, hue bar, hex box).
		-- Callback(Color3) fires while you drag. Methods: :Get() :Set(color) :Open() :Close()
		function Tab:ColorPicker(o)
			o = o or {}
			local hasDesc = o.Desc and o.Desc ~= ""
			local headerH = hasDesc and 52 or 38
			local SV_H = 110
			local panelH = 8 + SV_H + 8 + 26 + 10

			local startColor = typeof(o.Default) == "Color3" and o.Default or accent
			local h, s, v = startColor:ToHSV()

			local container = new("Frame", {
				BackgroundColor3 = Theme.Surface,
				Size = UDim2.new(1, 0, 0, headerH),
				ClipsDescendants = true,
			}, page)
			corner(container, 8)
			stroke(container, Theme.Stroke)

			local header = new("TextButton", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, headerH),
				Text = "",
				AutoButtonColor = false,
			}, container)

			new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, hasDesc and 8 or 0),
				Size = UDim2.new(1, -110, 0, hasDesc and 18 or headerH),
				Text = tostring(o.Title or "Color"),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = Theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, header)

			if hasDesc then
				new("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 27),
					Size = UDim2.new(1, -110, 0, 16),
					Text = tostring(o.Desc),
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextColor3 = Theme.SubText,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}, header)
			end

			local swatch = new("Frame", {
				BackgroundColor3 = startColor,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -36, 0, headerH / 2),
				Size = UDim2.fromOffset(36, 20),
			}, header)
			corner(swatch, 6)
			stroke(swatch, Theme.Stroke)

			local arrow = new("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -18, 0, headerH / 2),
				Size = UDim2.fromOffset(16, 16),
				Text = "▾",
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextColor3 = Theme.SubText,
			}, header)

			-- saturation / value square (hue color + white->clear + clear->black overlays)
			local svFrame = new("Frame", {
				BackgroundColor3 = Color3.fromHSV(h, 1, 1),
				Position = UDim2.fromOffset(12, headerH + 8),
				Size = UDim2.new(1, -52, 0, SV_H),
				BorderSizePixel = 0,
			}, container)
			corner(svFrame, 6)

			local whiteOverlay = new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				Size = UDim2.fromScale(1, 1),
				BorderSizePixel = 0,
			}, svFrame)
			corner(whiteOverlay, 6)
			new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}, whiteOverlay)

			local blackOverlay = new("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				Size = UDim2.fromScale(1, 1),
				BorderSizePixel = 0,
			}, svFrame)
			corner(blackOverlay, 6)
			new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(1, 0),
				}),
			}, blackOverlay)

			local svKnob = new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(s, 1 - v),
				Size = UDim2.fromOffset(12, 12),
			}, svFrame)
			corner(svKnob, 6)
			stroke(svKnob, Color3.new(0, 0, 0), 1.5)

			-- hue bar
			local hueBar = new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				Position = UDim2.new(1, -32, 0, headerH + 8),
				Size = UDim2.fromOffset(18, SV_H),
				BorderSizePixel = 0,
			}, container)
			corner(hueBar, 6)
			new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
					ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
					ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)),
					ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
					ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)),
					ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1)),
				}),
			}, hueBar)

			local hueKnob = new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, h),
				Size = UDim2.fromOffset(22, 8),
			}, hueBar)
			corner(hueKnob, 4)
			stroke(hueKnob, Color3.new(0, 0, 0), 1.5)

			-- hex box + rgb readout
			local hexY = headerH + 8 + SV_H + 8
			local hexBox = new("TextBox", {
				BackgroundColor3 = Theme.Background,
				Position = UDim2.fromOffset(12, hexY),
				Size = UDim2.fromOffset(100, 26),
				Text = "",
				PlaceholderText = "#FFFFFF",
				PlaceholderColor3 = Theme.SubText,
				TextColor3 = Theme.Text,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				ClearTextOnFocus = false,
			}, container)
			corner(hexBox, 6)
			local hexStroke = stroke(hexBox, Theme.Stroke)

			local rgbLabel = new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(122, hexY),
				Size = UDim2.new(1, -134, 0, 26),
				Text = "",
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = Theme.SubText,
			}, container)

			local function currentColor() return Color3.fromHSV(h, s, v) end

			local function render()
				local c = currentColor()
				local r = math.floor(c.R * 255 + 0.5)
				local g = math.floor(c.G * 255 + 0.5)
				local b = math.floor(c.B * 255 + 0.5)
				svFrame.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
				svKnob.Position = UDim2.fromScale(s, 1 - v)
				hueKnob.Position = UDim2.fromScale(0.5, h)
				swatch.BackgroundColor3 = c
				hexBox.Text = string.format("#%02X%02X%02X", r, g, b)
				rgbLabel.Text = string.format("R %d   G %d   B %d", r, g, b)
			end

			local function fire() safeCall(o.Callback, currentColor()) end

			local function applySV(pos)
				local abs, size = svFrame.AbsolutePosition, svFrame.AbsoluteSize
				if size.X <= 0 or size.Y <= 0 then return end
				s = math.clamp((pos.X - abs.X) / size.X, 0, 1)
				v = 1 - math.clamp((pos.Y - abs.Y) / size.Y, 0, 1)
				render()
				fire()
			end

			local function applyHue(pos)
				local abs, size = hueBar.AbsolutePosition, hueBar.AbsoluteSize
				if size.Y <= 0 then return end
				h = math.clamp((pos.Y - abs.Y) / size.Y, 0, 1)
				render()
				fire()
			end

			-- dragging (page scrolling is paused while you drag)
			local dragging = nil
			local function bind(obj, mode, apply)
				obj.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = mode
						page.ScrollingEnabled = false
						apply(input.Position)
						input.Changed:Connect(function()
							if input.UserInputState == Enum.UserInputState.End then
								if dragging == mode then dragging = nil end
								page.ScrollingEnabled = true
							end
						end)
					end
				end)
			end
			bind(svFrame, "sv", applySV)
			bind(hueBar, "hue", applyHue)

			table.insert(State.Conns, UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					if dragging == "sv" then applySV(input.Position) else applyHue(input.Position) end
				end
			end))

			-- hex input
			hexBox.Focused:Connect(function() tween(hexStroke, 0.15, { Color = accent }) end)
			hexBox.FocusLost:Connect(function()
				tween(hexStroke, 0.15, { Color = Theme.Stroke })
				local txt = hexBox.Text:gsub("#", "")
				local r, g, b = txt:match("^(%x%x)(%x%x)(%x%x)$")
				if r then
					h, s, v = Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)):ToHSV()
					render()
					fire()
				else
					render() -- invalid text: restore the real value
				end
			end)

			-- open / close
			local open = false
			local function setOpen(state)
				open = state
				tween(container, 0.22, { Size = UDim2.new(1, 0, 0, headerH + (state and panelH or 0)) }, Enum.EasingStyle.Quint)
				tween(arrow, 0.2, { Rotation = state and 180 or 0 })
			end
			header.Activated:Connect(function() setOpen(not open) end)
			header.MouseEnter:Connect(function() tween(container, 0.1, { BackgroundColor3 = Theme.SurfaceHover }) end)
			header.MouseLeave:Connect(function() tween(container, 0.1, { BackgroundColor3 = Theme.Surface }) end)

			render()

			local Picker = {}
			function Picker:Get() return currentColor() end
			function Picker:Set(color, silent)
				if typeof(color) ~= "Color3" then return end
				h, s, v = color:ToHSV()
				render()
				if not silent then fire() end
			end
			function Picker:Open() setOpen(true) end
			function Picker:Close() setOpen(false) end
			return Picker
		end

		-- Slider: Tab:Slider({ Title, Desc, Min, Max, Default, Step, Suffix, Callback })
		function Tab:Slider(o)
			o = o or {}
			local min = o.Min or 0
			local max = o.Max or 100
			if max <= min then max = min + 1 end
			local step = o.Step or o.Increment or 1
			if step <= 0 then step = 1 end
			local suffix = o.Suffix and tostring(o.Suffix) or ""
			local hasDesc = o.Desc and o.Desc ~= ""
			local height = hasDesc and 68 or 54

			local card = new("Frame", {
				BackgroundColor3 = Theme.Surface,
				Size = UDim2.new(1, 0, 0, height),
			}, page)
			corner(card, 8)
			stroke(card, Theme.Stroke)

			new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 8),
				Size = UDim2.new(1, -100, 0, 18),
				Text = tostring(o.Title or "Slider"),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = Theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)

			if hasDesc then
				new("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 26),
					Size = UDim2.new(1, -24, 0, 16),
					Text = tostring(o.Desc),
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextColor3 = Theme.SubText,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}, card)
			end

			local valueLabel = new("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 8),
				Size = UDim2.fromOffset(80, 18),
				TextXAlignment = Enum.TextXAlignment.Right,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = Theme.SubText,
			}, card)

			-- hit area (bigger than the visible track so it's easy to grab on mobile)
			local hit = new("TextButton", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 12, 1, -24),
				Size = UDim2.new(1, -24, 0, 18),
				Text = "",
				AutoButtonColor = false,
			}, card)

			local track = new("Frame", {
				BackgroundColor3 = Theme.Stroke,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, 0, 0, 6),
				BorderSizePixel = 0,
			}, hit)
			corner(track, 3)

			local fill = new("Frame", {
				BackgroundColor3 = accent,
				Size = UDim2.fromScale(0, 1),
				BorderSizePixel = 0,
			}, track)
			corner(fill, 3)

			local knob = new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromOffset(14, 14),
			}, track)
			corner(knob, 7)

			local function snap(v)
				v = math.floor((v - min) / step + 0.5) * step + min
				v = math.clamp(v, min, max)
				return math.floor(v * 1e6 + 0.5) / 1e6 -- remove float noise
			end

			local value = snap(o.Default or min)
			local Slider = {}

			local function render()
				local ratio = (value - min) / (max - min)
				fill.Size = UDim2.fromScale(ratio, 1)
				knob.Position = UDim2.fromScale(ratio, 0.5)
				valueLabel.Text = tostring(value) .. suffix
			end

			local function setValue(v, silent)
				v = snap(v)
				if v == value then return end
				value = v
				render()
				if not silent then safeCall(o.Callback, value) end
			end

			local function updateFromX(x)
				local w = track.AbsoluteSize.X
				if w <= 0 then return end
				local ratio = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
				setValue(min + ratio * (max - min))
			end

			local dragging = false
			hit.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					page.ScrollingEnabled = false -- don't scroll the page while sliding
					updateFromX(input.Position.X)
					input.Changed:Connect(function()
						if input.UserInputState == Enum.UserInputState.End then
							dragging = false
							page.ScrollingEnabled = true
						end
					end)
				end
			end)

			table.insert(State.Conns, UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					updateFromX(input.Position.X)
				end
			end))

			render()

			function Slider:Set(v) setValue(v) end
			function Slider:Get() return value end
			return Slider
		end

		-- Label: Tab:Label("text")  or  Tab:Label({ Text = "text" })
		function Tab:Label(o)
			if type(o) == "string" then o = { Text = o } end
			o = o or {}

			local frame = new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			}, page)
			new("UIPadding", {
				PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
			}, frame)

			local text = new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = tostring(o.Text or "Label"),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = o.Color or Theme.Text,
			}, frame)

			local Label = {}
			function Label:Set(t) text.Text = tostring(t) end
			function Label:Get() return text.Text end
			return Label
		end

		-- Note: Tab:Note({ Title = "...", Text = "...", Style = "Dark" | "Blue" })
		function Tab:Note(o)
			o = o or {}
			local blue = tostring(o.Style or "Dark"):lower() == "blue"

			local fillColor = blue and Color3.fromRGB(20, 40, 82) or Color3.fromRGB(12, 12, 12)
			local lineColor = blue and Color3.fromRGB(60, 110, 230) or Color3.fromRGB(60, 60, 60)
			local barColor = blue and Theme.Accent or Color3.fromRGB(110, 110, 110)
			local titleColor = blue and Color3.fromRGB(225, 236, 255) or Theme.Text
			local textColor = blue and Color3.fromRGB(165, 190, 240) or Theme.SubText

			local frame = new("Frame", {
				BackgroundColor3 = fillColor,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				ClipsDescendants = true,
			}, page)
			corner(frame, 8)
			stroke(frame, lineColor)

			new("Frame", {
				BackgroundColor3 = barColor,
				BorderSizePixel = 0,
				Size = UDim2.new(0, 3, 1, 0),
			}, frame)

			local content = new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			}, frame)
			new("UIPadding", {
				PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 10),
			}, content)
			new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, content)

			local titleLabel
			if o.Title and o.Title ~= "" then
				titleLabel = new("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = tostring(o.Title),
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.GothamBold,
					TextSize = 13,
					TextColor3 = titleColor,
					LayoutOrder = 1,
				}, content)
			end

			local textLabel = new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = tostring(o.Text or ""),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextColor3 = textColor,
				LayoutOrder = 2,
			}, content)

			local Note = {}
			function Note:SetText(t) textLabel.Text = tostring(t) end
			function Note:SetTitle(t) if titleLabel then titleLabel.Text = tostring(t) end end
			return Note
		end

		return Tab
	end

	return Window
end


return Library
 
