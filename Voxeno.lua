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
local Lucide = { Names = {}, Set = {}, Compact = {}, Aliases = {}, Assets = {}, AssetsByKey = {} }
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

-- Library:SetIconAssets({ house = "rbxassetid://123", ["arrow-left"] = 456, ... }) -> number of ids loaded
-- * keys can be written any way: "arrow-left", "ArrowLeft", "arrowleft"
-- * values: asset id (number / "rbxassetid://..") or { Image = "...", RectSize = V2, RectOffset = V2 }
-- * also accepts a module that has exportTable() (like the IconIDs module)
-- * empty values (0 / "" / nil) are skipped, so a template full of zeros loads nothing and breaks nothing
function Library:SetIconAssets(tbl)
	if type(tbl) == "table" and type(tbl.exportTable) == "function" then
		local ok, exported = pcall(tbl.exportTable)
		tbl = ok and exported or {}
	end

	local count = 0
	for k, v in pairs(tbl or {}) do
		local empty = v == nil or v == false or v == 0 or v == "" or v == "0"
		if not empty then
			local c = Lucide.Canonical(k)
			if c then Lucide.Assets[c] = v end
			Lucide.AssetsByKey[normName(k)] = v
			count += 1
		end
	end

	iconCache = {}
	warned = {}
	return count
end

--------------------------------------------------------------------
-- ICONS: Tree Hub + Solar (merged)
--------------------------------------------------------------------
local IconIDs = {
	["abbr-api"] = "rbxassetid://135442589868056",
	["abbr-ml"] = "rbxassetid://137903102602332",
	["abbr-ql"] = "rbxassetid://110049046211149",
	["abbr-sql"] = "rbxassetid://103476362200814",
	["abbr-zip"] = "rbxassetid://120035177960621",
	["alarm"] = "rbxassetid://103714651740365",
	["alarm-fill"] = "rbxassetid://134908962222196",
	["almost-equal"] = "rbxassetid://137719956647405",
	["antenna-signal"] = "rbxassetid://104559571857549",
	["aperture"] = "rbxassetid://71507557113696",
	["archive"] = "rbxassetid://138648712889342",
	["arrow-chevron-down"] = "rbxassetid://90698670707878",
	["arrow-chevron-left"] = "rbxassetid://97609998912425",
	["arrow-chevron-right"] = "rbxassetid://108948582252594",
	["arrow-chevron-up"] = "rbxassetid://115419992736798",
	["arrow-down"] = "rbxassetid://123939608472713",
	["arrow-down-from-line"] = "rbxassetid://99325768084725",
	["arrow-down-left"] = "rbxassetid://121587236109837",
	["arrow-down-right"] = "rbxassetid://115685270562753",
	["arrow-down-to-line"] = "rbxassetid://135415490774542",
	["arrow-down-to-square"] = "rbxassetid://120848266158193",
	["arrow-left"] = "rbxassetid://88189557452621",
	["arrow-left-from-line"] = "rbxassetid://116154200261474",
	["arrow-left-to-line"] = "rbxassetid://105416504042116",
	["arrow-right"] = "rbxassetid://95123964581528",
	["arrow-right-arrow-left"] = "rbxassetid://95237050232611",
	["arrow-right-from-line"] = "rbxassetid://73250388679868",
	["arrow-right-from-square"] = "rbxassetid://138630384007334",
	["arrow-right-to-line"] = "rbxassetid://101169643700290",
	["arrow-right-to-square"] = "rbxassetid://84589002276353",
	["arrow-rotate-left"] = "rbxassetid://74661102290864",
	["arrow-rotate-left-number-5"] = "rbxassetid://128917736449941",
	["arrow-rotate-right"] = "rbxassetid://127787397790437",
	["arrow-rotate-right-number-5"] = "rbxassetid://86653279618055",
	["arrow-shape-down"] = "rbxassetid://72218786566992",
	["arrow-shape-down-from-line"] = "rbxassetid://86427289862341",
	["arrow-shape-down-to-line"] = "rbxassetid://91327159930160",
	["arrow-shape-left"] = "rbxassetid://89941924562574",
	["arrow-shape-left-from-line"] = "rbxassetid://108670324374670",
	["arrow-shape-left-to-line"] = "rbxassetid://109558157057198",
	["arrow-shape-right"] = "rbxassetid://100458021003226",
	["arrow-shape-right-from-line"] = "rbxassetid://84964570689486",
	["arrow-shape-right-to-line"] = "rbxassetid://115960328054212",
	["arrow-shape-turn-up-left"] = "rbxassetid://132996249289474",
	["arrow-shape-turn-up-right"] = "rbxassetid://119618287119462",
	["arrow-shape-up"] = "rbxassetid://124602193050386",
	["arrow-shape-up-from-line"] = "rbxassetid://117424691508865",
	["arrow-shape-up-to-line"] = "rbxassetid://96133419760114",
	["arrow-up"] = "rbxassetid://100806733672183",
	["arrow-up-arrow-down"] = "rbxassetid://140168473463286",
	["arrow-up-from-line"] = "rbxassetid://95503719226933",
	["arrow-up-from-square"] = "rbxassetid://72403202160720",
	["arrow-up-from-square-slash"] = "rbxassetid://108335176349985",
	["arrow-up-left"] = "rbxassetid://134676894387453",
	["arrow-up-right"] = "rbxassetid://107224539026693",
	["arrow-up-right-from-square"] = "rbxassetid://92937384604050",
	["arrow-up-to-line"] = "rbxassetid://110555587066032",
	["arrow-uturn-ccw-down"] = "rbxassetid://105699476132562",
	["arrow-uturn-ccw-left"] = "rbxassetid://115664707371307",
	["arrow-uturn-ccw-right"] = "rbxassetid://126380726894011",
	["arrow-uturn-cw-down"] = "rbxassetid://134787361730075",
	["arrow-uturn-cw-left"] = "rbxassetid://139071077829245",
	["arrow-uturn-cw-right"] = "rbxassetid://91889095232886",
	["arrows-3-rotate-left"] = "rbxassetid://137959578609474",
	["arrows-3-rotate-left-letter-a"] = "rbxassetid://120991923936761",
	["arrows-3-rotate-right"] = "rbxassetid://84915394441695",
	["arrows-expand"] = "rbxassetid://122410949695631",
	["arrows-expand-horizontal"] = "rbxassetid://133458600060285",
	["arrows-expand-vertical"] = "rbxassetid://126477345242638",
	["arrows-opposite-to-dots"] = "rbxassetid://109943465092674",
	["arrows-rotate-left"] = "rbxassetid://119636631750077",
	["arrows-rotate-left-slash"] = "rbxassetid://83953788137425",
	["arrows-rotate-right"] = "rbxassetid://71163834754608",
	["arrows-rotate-right-slash"] = "rbxassetid://71635699550719",
	["at"] = "rbxassetid://71604977143985",
	["backward-step"] = "rbxassetid://115416356295964",
	["backward-step-fill"] = "rbxassetid://73165472334476",
	["ban"] = "rbxassetid://81039427320809",
	["bars"] = "rbxassetid://78693767420779",
	["bars-ascending-align-center"] = "rbxassetid://84484070067864",
	["bars-ascending-align-left"] = "rbxassetid://139158749201798",
	["bars-ascending-align-left-arrow-down"] = "rbxassetid://128006052892634",
	["bars-ascending-align-left-arrow-up"] = "rbxassetid://96654587441659",
	["bars-ascending-align-right"] = "rbxassetid://123301249654664",
	["bars-descending-align-center"] = "rbxassetid://99351433688614",
	["bars-descending-align-left"] = "rbxassetid://118174229311920",
	["bars-descending-align-left-arrow-down"] = "rbxassetid://104541816646102",
	["bars-descending-align-left-arrow-up"] = "rbxassetid://115635127737647",
	["bars-descending-align-right"] = "rbxassetid://87267446493492",
	["bars-play"] = "rbxassetid://108518006095531",
	["bars-unaligned"] = "rbxassetid://100960781217209",
	["bell"] = "rbxassetid://78246583582436",
	["bell-dot"] = "rbxassetid://136008595824222",
	["bell-fill"] = "rbxassetid://86681986971272",
	["bell-slash"] = "rbxassetid://117431958262965",
	["binoculars"] = "rbxassetid://79600106885790",
	["bold"] = "rbxassetid://72536284189901",
	["book"] = "rbxassetid://81445376833998",
	["book-open"] = "rbxassetid://70499214384560",
	["bookmark"] = "rbxassetid://92062140569721",
	["bookmark-fill"] = "rbxassetid://102864828026385",
	["books"] = "rbxassetid://94122657588748",
	["box"] = "rbxassetid://75012424452065",
	["boxes-3"] = "rbxassetid://87626327475239",
	["branches-down"] = "rbxassetid://130945471079494",
	["branches-right"] = "rbxassetid://85923853676231",
	["branches-right-arrow-right"] = "rbxassetid://112215804244328",
	["briefcase"] = "rbxassetid://71551404712337",
	["briefcase-fill"] = "rbxassetid://85257920743453",
	["broadcast-signal"] = "rbxassetid://102816146091577",
	["broom-motion"] = "rbxassetid://76078843644229",
	["broom-motion-fill"] = "rbxassetid://124943679507818",
	["brush"] = "rbxassetid://107845488140370",
	["bucket"] = "rbxassetid://121417289879029",
	["bucket-paint"] = "rbxassetid://99596953231201",
	["bug"] = "rbxassetid://98670706168887",
	["bulb"] = "rbxassetid://93108336233221",
	["calculator"] = "rbxassetid://137475273962332",
	["calendar"] = "rbxassetid://116377708026056",
	["calendar-xmark"] = "rbxassetid://104770084996807",
	["camera"] = "rbxassetid://81803093224716",
	["car"] = "rbxassetid://120604577353177",
	["card-club"] = "rbxassetid://127117910964137",
	["card-diamond"] = "rbxassetid://80236056413008",
	["card-heart"] = "rbxassetid://120906275097794",
	["card-spade"] = "rbxassetid://115590808323293",
	["caret-down"] = "rbxassetid://79701968834514",
	["caret-left"] = "rbxassetid://89316921568167",
	["caret-right"] = "rbxassetid://139321289081149",
	["caret-up"] = "rbxassetid://83059411586095",
	["carets-expand-vertical"] = "rbxassetid://133896897248826",
	["chart-area-stacked"] = "rbxassetid://130180931327397",
	["chart-area-stacked-normalized"] = "rbxassetid://103830652069922",
	["chart-bar"] = "rbxassetid://135127077453879",
	["chart-bar-stacked"] = "rbxassetid://122493586521135",
	["chart-column"] = "rbxassetid://94234923490933",
	["chart-column-stacked"] = "rbxassetid://84907763465405",
	["chart-donut"] = "rbxassetid://70741662222470",
	["chart-line"] = "rbxassetid://75770898321861",
	["chart-line-arrow-up"] = "rbxassetid://128755383700684",
	["chart-line-label"] = "rbxassetid://78343344318924",
	["chart-line-points"] = "rbxassetid://71936816563951",
	["chart-mixed"] = "rbxassetid://129003368317817",
	["chart-pie"] = "rbxassetid://133652199723190",
	["chart-treemap"] = "rbxassetid://121384142935035",
	["check"] = "rbxassetid://103056138350584",
	["check-double"] = "rbxassetid://88408199250132",
	["check-shape"] = "rbxassetid://90791112302147",
	["check-shape-fill"] = "rbxassetid://106578333608881",
	["cherry"] = "rbxassetid://131117375627466",
	["chevron-down"] = "rbxassetid://101196795066767",
	["chevron-down-wide"] = "rbxassetid://98214643270970",
	["chevron-left"] = "rbxassetid://96477998975284",
	["chevron-right"] = "rbxassetid://133716111451411",
	["chevron-up"] = "rbxassetid://81099149547925",
	["chevron-up-wide"] = "rbxassetid://114214751384551",
	["chevrons-collapse-from-lines"] = "rbxassetid://117887712595429",
	["chevrons-collapse-horizontal"] = "rbxassetid://132606049984534",
	["chevrons-collapse-to-line"] = "rbxassetid://139365137473627",
	["chevrons-collapse-up-right"] = "rbxassetid://114550385026285",
	["chevrons-collapse-vertical"] = "rbxassetid://88863993031023",
	["chevrons-down"] = "rbxassetid://123759343294827",
	["chevrons-down-wide"] = "rbxassetid://126852609626773",
	["chevrons-expand-from-line"] = "rbxassetid://81584080383503",
	["chevrons-expand-horizontal"] = "rbxassetid://100945919368709",
	["chevrons-expand-to-lines"] = "rbxassetid://87651107148342",
	["chevrons-expand-up-right"] = "rbxassetid://94174346416829",
	["chevrons-expand-vertical"] = "rbxassetid://93809445072743",
	["chevrons-left"] = "rbxassetid://102534065706809",
	["chevrons-right"] = "rbxassetid://96202292878843",
	["chevrons-up"] = "rbxassetid://78078270586609",
	["chevrons-up-wide"] = "rbxassetid://131005459829839",
	["circle"] = "rbxassetid://137383572905673",
	["circle-arrow-down"] = "rbxassetid://120314249950202",
	["circle-arrow-down-fill"] = "rbxassetid://91451793265769",
	["circle-arrow-left"] = "rbxassetid://123388016121218",
	["circle-arrow-left-fill"] = "rbxassetid://120596831742130",
	["circle-arrow-right"] = "rbxassetid://101229493655480",
	["circle-arrow-right-fill"] = "rbxassetid://113087947378891",
	["circle-arrow-up"] = "rbxassetid://121237631084166",
	["circle-arrow-up-fill"] = "rbxassetid://124180379825426",
	["circle-check"] = "rbxassetid://84441736605020",
	["circle-check-fill"] = "rbxassetid://136945651864502",
	["circle-chevron-down"] = "rbxassetid://122051087562651",
	["circle-chevron-down-fill"] = "rbxassetid://113557422611978",
	["circle-chevron-left"] = "rbxassetid://89977279697563",
	["circle-chevron-left-fill"] = "rbxassetid://119025519682054",
	["circle-chevron-right"] = "rbxassetid://73607483249296",
	["circle-chevron-right-fill"] = "rbxassetid://95916652600208",
	["circle-chevron-up"] = "rbxassetid://97772187879743",
	["circle-chevron-up-fill"] = "rbxassetid://120393306329974",
	["circle-chevrons-down"] = "rbxassetid://85496131237752",
	["circle-chevrons-left"] = "rbxassetid://98715112437146",
	["circle-chevrons-right"] = "rbxassetid://79444813576823",
	["circle-chevrons-up"] = "rbxassetid://101477927637665",
	["circle-dashed"] = "rbxassetid://122858665756800",
	["circle-dollar"] = "rbxassetid://82400975917075",
	["circle-exclamation"] = "rbxassetid://82169163218994",
	["circle-exclamation-fill"] = "rbxassetid://97043397618250",
	["circle-fill"] = "rbxassetid://94990574750335",
	["circle-info"] = "rbxassetid://94896614951723",
	["circle-info-fill"] = "rbxassetid://104842691994208",
	["circle-letter-a"] = "rbxassetid://110682804507256",
	["circle-letter-b"] = "rbxassetid://131915066352114",
	["circle-letter-c"] = "rbxassetid://120338087811400",
	["circle-letter-d"] = "rbxassetid://130741771880107",
	["circle-letter-e"] = "rbxassetid://138887757846336",
	["circle-letter-f"] = "rbxassetid://100273312746183",
	["circle-letter-g"] = "rbxassetid://138724669470541",
	["circle-letter-h"] = "rbxassetid://108122906545875",
	["circle-letter-i"] = "rbxassetid://115119050404830",
	["circle-letter-j"] = "rbxassetid://114756737367727",
	["circle-letter-k"] = "rbxassetid://76746119020732",
	["circle-letter-l"] = "rbxassetid://121394965902583",
	["circle-letter-m"] = "rbxassetid://94265144812900",
	["circle-letter-n"] = "rbxassetid://78178247320190",
	["circle-letter-o"] = "rbxassetid://132976570923110",
	["circle-letter-p"] = "rbxassetid://108919995898285",
	["circle-letter-q"] = "rbxassetid://108843487550689",
	["circle-letter-r"] = "rbxassetid://98326067563194",
	["circle-letter-s"] = "rbxassetid://103894277089244",
	["circle-letter-t"] = "rbxassetid://131148273820031",
	["circle-letter-u"] = "rbxassetid://127458231439418",
	["circle-letter-v"] = "rbxassetid://101002192432518",
	["circle-letter-w"] = "rbxassetid://77310450045931",
	["circle-letter-x"] = "rbxassetid://135153805304501",
	["circle-letter-y"] = "rbxassetid://128644240416254",
	["circle-letter-z"] = "rbxassetid://77875031623708",
	["circle-link"] = "rbxassetid://70534705255826",
	["circle-minus"] = "rbxassetid://109230493518470",
	["circle-minus-fill"] = "rbxassetid://82217360639927",
	["circle-number-0"] = "rbxassetid://139948957580308",
	["circle-number-1"] = "rbxassetid://109640039151570",
	["circle-number-2"] = "rbxassetid://92480552098950",
	["circle-number-3"] = "rbxassetid://103817768553696",
	["circle-number-4"] = "rbxassetid://94141847254472",
	["circle-number-5"] = "rbxassetid://129276854981437",
	["circle-number-6"] = "rbxassetid://80118979117292",
	["circle-number-7"] = "rbxassetid://135668138548066",
	["circle-number-8"] = "rbxassetid://138966720517801",
	["circle-number-9"] = "rbxassetid://88336496960699",
	["circle-pause"] = "rbxassetid://125456661498548",
	["circle-pause-fill"] = "rbxassetid://119839378934874",
	["circle-play"] = "rbxassetid://131885354857527",
	["circle-play-fill"] = "rbxassetid://116647054855820",
	["circle-plus"] = "rbxassetid://129360492879939",
	["circle-plus-fill"] = "rbxassetid://78315607252810",
	["circle-question"] = "rbxassetid://93356247795233",
	["circle-question-dot"] = "rbxassetid://77195781813589",
	["circle-question-fill"] = "rbxassetid://109914335358349",
	["circle-ruble"] = "rbxassetid://99021046363225",
	["circle-stop"] = "rbxassetid://130063510431342",
	["circle-stop-fill"] = "rbxassetid://100877093103614",
	["circle-tree"] = "rbxassetid://85080090742001",
	["circle-xmark"] = "rbxassetid://130360653653495",
	["circle-xmark-fill"] = "rbxassetid://101136893109914",
	["circles-3-plus"] = "rbxassetid://112285424384524",
	["circles-4-diamond"] = "rbxassetid://124361523430952",
	["circles-4-square"] = "rbxassetid://96622207131032",
	["circles-5-random"] = "rbxassetid://104341448925971",
	["circles-concentric"] = "rbxassetid://112364968682650",
	["circles-intersection"] = "rbxassetid://73334375522049",
	["clock"] = "rbxassetid://95091173743042",
	["clock-arrow-rotate-left"] = "rbxassetid://127310177043478",
	["clock-fill"] = "rbxassetid://117237925777447",
	["cloud"] = "rbxassetid://101918816626609",
	["cloud-arrow-up-in"] = "rbxassetid://137117278628772",
	["cloud-check"] = "rbxassetid://103059266691426",
	["cloud-gear"] = "rbxassetid://110509558530780",
	["cloud-nut-hex"] = "rbxassetid://125304015018252",
	["cloud-slash"] = "rbxassetid://88532364599721",
	["clouds"] = "rbxassetid://79789514014401",
	["code"] = "rbxassetid://127032800584061",
	["code-commit"] = "rbxassetid://111643949198037",
	["code-commit-horizontal"] = "rbxassetid://127576006316043",
	["code-commits"] = "rbxassetid://91309338263007",
	["code-compare"] = "rbxassetid://138656697539302",
	["code-fork"] = "rbxassetid://104298384240721",
	["code-merge"] = "rbxassetid://104709907415001",
	["code-pull-request"] = "rbxassetid://108743032859939",
	["code-pull-request-arrow-left"] = "rbxassetid://98599280503024",
	["code-pull-request-arrow-right"] = "rbxassetid://129705050027475",
	["code-pull-request-check"] = "rbxassetid://103378571731120",
	["code-pull-request-xmark"] = "rbxassetid://78829301966639",
	["code-trunk"] = "rbxassetid://103810952923597",
	["comment"] = "rbxassetid://109466230642253",
	["comment-dot"] = "rbxassetid://134629650483759",
	["comment-fill"] = "rbxassetid://112831725085208",
	["comment-plus"] = "rbxassetid://98359578614408",
	["comment-slash"] = "rbxassetid://138995689318032",
	["comments"] = "rbxassetid://112347681716575",
	["compass"] = "rbxassetid://111538538589488",
	["copy"] = "rbxassetid://122456870046625",
	["copy-arrow-right"] = "rbxassetid://104912869060624",
	["copy-check"] = "rbxassetid://76642966313268",
	["copy-check-xmark"] = "rbxassetid://122253044982865",
	["copy-chevron-right"] = "rbxassetid://114153241555814",
	["copy-minus"] = "rbxassetid://96922644771240",
	["copy-picture"] = "rbxassetid://72428819718946",
	["copy-plus"] = "rbxassetid://137867936354461",
	["copy-transparent"] = "rbxassetid://124327837016861",
	["copy-xmark"] = "rbxassetid://127865292095709",
	["cpu"] = "rbxassetid://85871203780132",
	["cpus"] = "rbxassetid://70602536224036",
	["credit-card"] = "rbxassetid://119980351960932",
	["crop"] = "rbxassetid://92000335381082",
	["crown-diamond"] = "rbxassetid://137870034022669",
	["cube"] = "rbxassetid://127347610823511",
	["cubes-3"] = "rbxassetid://78370998312932",
	["cubes-3-overlap"] = "rbxassetid://86277627995457",
	["cup"] = "rbxassetid://101351327561915",
	["curly-brackets"] = "rbxassetid://109276236803255",
	["curly-brackets-function"] = "rbxassetid://112157245376014",
	["curly-brackets-lock"] = "rbxassetid://134432768252956",
	["database"] = "rbxassetid://70527848574090",
	["database-arrow-right"] = "rbxassetid://101415863987351",
	["database-fill"] = "rbxassetid://133484249821797",
	["database-magnifier"] = "rbxassetid://125148893054496",
	["databases"] = "rbxassetid://90706490669456",
	["databases-fill"] = "rbxassetid://124304495065051",
	["delete"] = "rbxassetid://81915416250149",
	["diamond"] = "rbxassetid://104594307062320",
	["diamond-exclamation"] = "rbxassetid://72475760887740",
	["diamond-exclamation-fill"] = "rbxassetid://92750439068579",
	["diamond-fill"] = "rbxassetid://96228419948263",
	["dice-1"] = "rbxassetid://103689239525832",
	["dice-2"] = "rbxassetid://96389219075812",
	["dice-3"] = "rbxassetid://70621804370506",
	["dice-4"] = "rbxassetid://89218365690474",
	["dice-5"] = "rbxassetid://131630624927476",
	["dice-6"] = "rbxassetid://138833379439041",
	["display"] = "rbxassetid://80550180662275",
	["display-pulse"] = "rbxassetid://138647930249888",
	["dots-9"] = "rbxassetid://122077000646371",
	["droplet"] = "rbxassetid://85217490213932",
	["ear"] = "rbxassetid://135065014224646",
	["ellipsis"] = "rbxassetid://108825746682489",
	["ellipsis-vertical"] = "rbxassetid://97426157363170",
	["envelope"] = "rbxassetid://109118565314106",
	["envelope-open"] = "rbxassetid://105358726132066",
	["envelope-open-xmark"] = "rbxassetid://80866920799385",
	["equal"] = "rbxassetid://93419050665965",
	["eraser"] = "rbxassetid://106523014738195",
	["exclamation-shape"] = "rbxassetid://77426370164778",
	["exclamation-shape-fill"] = "rbxassetid://93650541968093",
	["eye"] = "rbxassetid://120707831495409",
	["eye-closed"] = "rbxassetid://72035002941128",
	["eye-dashed"] = "rbxassetid://94920104462212",
	["eye-slash"] = "rbxassetid://74632388395769",
	["eyes-look-left"] = "rbxassetid://135888127006421",
	["eyes-look-right"] = "rbxassetid://115523274237362",
	["face-alien"] = "rbxassetid://122493985129489",
	["face-angry"] = "rbxassetid://105657465280044",
	["face-fun"] = "rbxassetid://125279182467038",
	["face-neutral"] = "rbxassetid://71086502634377",
	["face-neutral-dashed"] = "rbxassetid://78798054777773",
	["face-robot"] = "rbxassetid://105302404019498",
	["face-robot-smile"] = "rbxassetid://74419780881388",
	["face-sad"] = "rbxassetid://119695487707918",
	["face-smile"] = "rbxassetid://79817174074777",
	["face-surprise"] = "rbxassetid://94214134808069",
	["factory"] = "rbxassetid://84085474112768",
	["file"] = "rbxassetid://107833047300916",
	["file-arrow-down"] = "rbxassetid://110456463755544",
	["file-arrow-left"] = "rbxassetid://91953364759480",
	["file-arrow-right"] = "rbxassetid://75382423167566",
	["file-arrow-right-out"] = "rbxassetid://91570928055045",
	["file-arrow-up"] = "rbxassetid://103734210881903",
	["file-check"] = "rbxassetid://85119975202211",
	["file-code"] = "rbxassetid://126119599889094",
	["file-dollar"] = "rbxassetid://88995968130496",
	["file-exclamation"] = "rbxassetid://137422014587320",
	["file-letter-p"] = "rbxassetid://117140793705373",
	["file-letter-w"] = "rbxassetid://72104258718446",
	["file-letter-x"] = "rbxassetid://73195755082293",
	["file-magnifier"] = "rbxassetid://126110080855699",
	["file-minus"] = "rbxassetid://95479115601838",
	["file-plus"] = "rbxassetid://105240495106677",
	["file-question"] = "rbxassetid://100446629151131",
	["file-ruble"] = "rbxassetid://74637291969088",
	["file-text"] = "rbxassetid://133376156175387",
	["file-xmark"] = "rbxassetid://139863878410957",
	["file-zipper"] = "rbxassetid://71253058147459",
	["files"] = "rbxassetid://83062861217187",
	["filmstrip"] = "rbxassetid://98311073132457",
	["fingerprint"] = "rbxassetid://109038457478113",
	["firewall"] = "rbxassetid://119509701461101",
	["flag"] = "rbxassetid://123555524822059",
	["flame"] = "rbxassetid://118156841707888",
	["flask"] = "rbxassetid://100829678702990",
	["floppy-disk"] = "rbxassetid://123778614731407",
	["folder"] = "rbxassetid://121178377882882",
	["folder-arrow-down"] = "rbxassetid://97468473569904",
	["folder-arrow-left"] = "rbxassetid://105044315724840",
	["folder-arrow-right"] = "rbxassetid://134579629548406",
	["folder-arrow-up"] = "rbxassetid://107063036939545",
	["folder-arrow-up-in"] = "rbxassetid://117563761638574",
	["folder-check"] = "rbxassetid://104012006265308",
	["folder-code"] = "rbxassetid://107125298152045",
	["folder-exclamation"] = "rbxassetid://76140673562587",
	["folder-fill"] = "rbxassetid://101900623025419",
	["folder-flows"] = "rbxassetid://137790120021992",
	["folder-house"] = "rbxassetid://94345069309317",
	["folder-keyhole"] = "rbxassetid://120770116606982",
	["folder-lock"] = "rbxassetid://105884426146404",
	["folder-magnifier"] = "rbxassetid://122954171576076",
	["folder-open"] = "rbxassetid://116588458323209",
	["folder-open-fill"] = "rbxassetid://102372531181401",
	["folder-plus"] = "rbxassetid://121839906515471",
	["folder-tree"] = "rbxassetid://84827525485024",
	["folders"] = "rbxassetid://78596087518530",
	["font"] = "rbxassetid://113737577046086",
	["font-case"] = "rbxassetid://109181669437944",
	["font-cursor"] = "rbxassetid://79018629030822",
	["forward-step"] = "rbxassetid://76735557633834",
	["forward-step-fill"] = "rbxassetid://131398028156993",
	["frame"] = "rbxassetid://121828062350954",
	["frames"] = "rbxassetid://71233848128981",
	["function"] = "rbxassetid://84386313846201",
	["funnel"] = "rbxassetid://95476072665064",
	["funnel-xmark"] = "rbxassetid://106950038809874",
	["gear"] = "rbxassetid://130653350850377",
	["gear-branches"] = "rbxassetid://124635609929435",
	["gear-dot"] = "rbxassetid://94678631000745",
	["gear-play"] = "rbxassetid://132051405025286",
	["gem"] = "rbxassetid://123582791292356",
	["geo"] = "rbxassetid://112530836084262",
	["geo-dots"] = "rbxassetid://125473964555170",
	["geo-fill"] = "rbxassetid://125270420058642",
	["geo-pin"] = "rbxassetid://77931214242710",
	["geo-polygons"] = "rbxassetid://86291018663554",
	["ghost"] = "rbxassetid://106544313918701",
	["gift"] = "rbxassetid://88942366605587",
	["globe"] = "rbxassetid://124472253147461",
	["gpu"] = "rbxassetid://80435443421528",
	["graduation-cap"] = "rbxassetid://72291379767367",
	["graph-node"] = "rbxassetid://121418203381727",
	["grip"] = "rbxassetid://77797757994986",
	["grip-horizontal"] = "rbxassetid://103457330094853",
	["hammer"] = "rbxassetid://96934135124621",
	["hand"] = "rbxassetid://88875046551218",
	["hand-ok"] = "rbxassetid://73421195330990",
	["hand-point-down"] = "rbxassetid://133449559362454",
	["hand-point-left"] = "rbxassetid://75545630547214",
	["hand-point-right"] = "rbxassetid://96326952803878",
	["hand-point-up"] = "rbxassetid://76992889322585",
	["hand-stop"] = "rbxassetid://95261381545988",
	["handset"] = "rbxassetid://94749731410407",
	["handset-arrow-in"] = "rbxassetid://127330216639355",
	["handset-arrow-out"] = "rbxassetid://136244597857388",
	["hard-drive"] = "rbxassetid://134209413192545",
	["hashtag"] = "rbxassetid://104931068902382",
	["heading"] = "rbxassetid://114958398586380",
	["heading-1"] = "rbxassetid://83778976927134",
	["heading-2"] = "rbxassetid://133304878410887",
	["heading-3"] = "rbxassetid://73341928217597",
	["heading-4"] = "rbxassetid://77755375432268",
	["heading-5"] = "rbxassetid://78067061590164",
	["heading-6"] = "rbxassetid://139894519888639",
	["headphones"] = "rbxassetid://103286933144222",
	["heart"] = "rbxassetid://113973336125121",
	["heart-crack"] = "rbxassetid://114161017562451",
	["heart-fill"] = "rbxassetid://113631886629502",
	["heart-pulse"] = "rbxassetid://94559254303679",
	["hierarchy"] = "rbxassetid://87193001404534",
	["house"] = "rbxassetid://84017953453024",
	["house-fill"] = "rbxassetid://71433571410756",
	["italic"] = "rbxassetid://81115641708810",
	["key"] = "rbxassetid://103889368375394",
	["keyboard"] = "rbxassetid://130539369569844",
	["layers"] = "rbxassetid://129316465231678",
	["layers-3-diagonal"] = "rbxassetid://120377297652057",
	["layers-vertical"] = "rbxassetid://110354922373224",
	["layout-cells"] = "rbxassetid://98696521748547",
	["layout-cells-large"] = "rbxassetid://100255098354000",
	["layout-columns"] = "rbxassetid://84427832581937",
	["layout-columns-3"] = "rbxassetid://71735447854881",
	["layout-footer"] = "rbxassetid://113622765670575",
	["layout-header"] = "rbxassetid://105610307834609",
	["layout-header-cells"] = "rbxassetid://131170467534038",
	["layout-header-cells-large"] = "rbxassetid://137791004130120",
	["layout-header-cells-large-fill"] = "rbxassetid://70589884836899",
	["layout-header-cells-large-letter-d"] = "rbxassetid://117150888842613",
	["layout-header-cells-large-thunderbolt"] = "rbxassetid://70539880056080",
	["layout-header-columns"] = "rbxassetid://127466539759012",
	["layout-header-cursor"] = "rbxassetid://94950003069391",
	["layout-header-side-content"] = "rbxassetid://111700822607720",
	["layout-list"] = "rbxassetid://93047942420928",
	["layout-rows"] = "rbxassetid://100647663038001",
	["layout-rows-3"] = "rbxassetid://90425482127526",
	["layout-side-content"] = "rbxassetid://112944931847823",
	["layout-side-content-left"] = "rbxassetid://82393275916629",
	["layout-side-content-right"] = "rbxassetid://106198598011193",
	["layout-split-columns"] = "rbxassetid://81956652547064",
	["layout-split-columns-3"] = "rbxassetid://135156385761292",
	["layout-split-rows"] = "rbxassetid://120184403763480",
	["layout-split-side-content-left"] = "rbxassetid://115583962402116",
	["layout-split-side-content-right"] = "rbxassetid://125684182014400",
	["layout-tabs"] = "rbxassetid://123109511030647",
	["letter-a-underline"] = "rbxassetid://137318351668255",
	["letter-group"] = "rbxassetid://134098861018996",
	["letter-m"] = "rbxassetid://124776688403365",
	["life-ring"] = "rbxassetid://124114396162528",
	["link"] = "rbxassetid://127654461623913",
	["link-slash"] = "rbxassetid://86714437340868",
	["list-check"] = "rbxassetid://72975481210972",
	["list-check-lock"] = "rbxassetid://95781063192246",
	["list-ol"] = "rbxassetid://123831960497637",
	["list-timeline"] = "rbxassetid://75879925920734",
	["list-ul"] = "rbxassetid://123133222715096",
	["location-arrow"] = "rbxassetid://71897095805613",
	["location-arrow-fill"] = "rbxassetid://94565046462607",
	["lock"] = "rbxassetid://132362477716273",
	["lock-fill"] = "rbxassetid://78340628553221",
	["lock-open"] = "rbxassetid://81326871090745",
	["lock-open-fill"] = "rbxassetid://131243965606901",
	["logo-acrobat"] = "rbxassetid://77758480016386",
	["logo-android"] = "rbxassetid://85377374331361",
	["logo-debian"] = "rbxassetid://93074623442525",
	["logo-docker"] = "rbxassetid://112115815862225",
	["logo-draw-io"] = "rbxassetid://96320557568840",
	["logo-facebook"] = "rbxassetid://91676718976544",
	["logo-figma"] = "rbxassetid://127053693352358",
	["logo-github"] = "rbxassetid://109140464637712",
	["logo-gitlab"] = "rbxassetid://112942421350236",
	["logo-linkedin"] = "rbxassetid://137058953014556",
	["logo-linux"] = "rbxassetid://112716255017277",
	["logo-macos"] = "rbxassetid://115977192058220",
	["logo-markdown"] = "rbxassetid://94192304735756",
	["logo-mcp"] = "rbxassetid://99978388756048",
	["logo-mermaid"] = "rbxassetid://113773127670999",
	["logo-microsoft-office"] = "rbxassetid://72281287708367",
	["logo-nodejs"] = "rbxassetid://85662644955233",
	["logo-notion"] = "rbxassetid://112104007451593",
	["logo-osi"] = "rbxassetid://129020182333515",
	["logo-python"] = "rbxassetid://108546719377285",
	["logo-slack"] = "rbxassetid://96956955585721",
	["logo-stack-overflow"] = "rbxassetid://108294339893412",
	["logo-telegram"] = "rbxassetid://78021764535568",
	["logo-ubuntu"] = "rbxassetid://87355948774846",
	["logo-windows"] = "rbxassetid://103987175937231",
	["logo-yandex"] = "rbxassetid://85363542282523",
	["logo-yandex-cloud"] = "rbxassetid://70811487120976",
	["logo-yandex-messenger"] = "rbxassetid://101194358875111",
	["logo-yandex-tracker"] = "rbxassetid://118664096172733",
	["magic-wand"] = "rbxassetid://117815236842546",
	["magnet"] = "rbxassetid://87480686988492",
	["magnifier"] = "rbxassetid://122754210010897",
	["magnifier-minus"] = "rbxassetid://84516692474671",
	["magnifier-plus"] = "rbxassetid://94022624784789",
	["map-pin"] = "rbxassetid://88496867972782",
	["map-pin-minus"] = "rbxassetid://127988204475002",
	["map-pin-plus"] = "rbxassetid://105808264416140",
	["math-intersection-shape"] = "rbxassetid://106794166770550",
	["math-operations"] = "rbxassetid://103226134327086",
	["math-union-shape"] = "rbxassetid://125633228072117",
	["medal"] = "rbxassetid://77629794806774",
	["megaphone"] = "rbxassetid://100616565190065",
	["microphone"] = "rbxassetid://139538522148314",
	["microphone-slash"] = "rbxassetid://103601475520943",
	["microscope"] = "rbxassetid://82196704162955",
	["minus"] = "rbxassetid://108872870188126",
	["minus-shape"] = "rbxassetid://126969485042490",
	["minus-shape-fill"] = "rbxassetid://85672016158837",
	["molecule"] = "rbxassetid://83213930150159",
	["moon"] = "rbxassetid://133378404835359",
	["mug"] = "rbxassetid://133596134867753",
	["music-note"] = "rbxassetid://118344544185512",
	["nodes-down"] = "rbxassetid://78959155873218",
	["nodes-left"] = "rbxassetid://128423983338128",
	["nodes-right"] = "rbxassetid://118544021258370",
	["nodes-up"] = "rbxassetid://92522278145067",
	["nut-hex"] = "rbxassetid://81847321109216",
	["object-align-bottom"] = "rbxassetid://103798951610656",
	["object-align-center-horizontal"] = "rbxassetid://97416331490032",
	["object-align-center-vertical"] = "rbxassetid://120211347778371",
	["object-align-justify-horizontal"] = "rbxassetid://79979775646576",
	["object-align-justify-vertical"] = "rbxassetid://110854565778147",
	["object-align-left"] = "rbxassetid://105346144625665",
	["object-align-right"] = "rbxassetid://103097923432348",
	["object-align-top"] = "rbxassetid://98079578772618",
	["objects-align-bottom"] = "rbxassetid://95388778271651",
	["objects-align-center-horizontal"] = "rbxassetid://110438134614711",
	["objects-align-center-vertical"] = "rbxassetid://79198463408501",
	["objects-align-justify-horizontal"] = "rbxassetid://122875167898478",
	["objects-align-justify-vertical"] = "rbxassetid://78441673968689",
	["objects-align-left"] = "rbxassetid://120648874528302",
	["objects-align-right"] = "rbxassetid://83569867209815",
	["objects-align-top"] = "rbxassetid://138094321995396",
	["octagon-xmark"] = "rbxassetid://139784898655656",
	["office-badge"] = "rbxassetid://105708603646268",
	["paintbrush"] = "rbxassetid://116170048634161",
	["palette"] = "rbxassetid://91973234300212",
	["paper-plane"] = "rbxassetid://84096293617435",
	["paperclip"] = "rbxassetid://104675861538941",
	["passport"] = "rbxassetid://112257954225409",
	["pause"] = "rbxassetid://121534471795622",
	["pause-fill"] = "rbxassetid://103348022852527",
	["pencil"] = "rbxassetid://132145192304391",
	["pencil-to-line"] = "rbxassetid://86977727845037",
	["pencil-to-square"] = "rbxassetid://138949256779509",
	["percent"] = "rbxassetid://72754559570110",
	["person"] = "rbxassetid://135548958804125",
	["person-fill"] = "rbxassetid://93649699513763",
	["person-gear"] = "rbxassetid://105283855461666",
	["person-magnifier"] = "rbxassetid://126714669722336",
	["person-nut-hex"] = "rbxassetid://127185374454347",
	["person-pencil"] = "rbxassetid://88660023708396",
	["person-planet-earth"] = "rbxassetid://112713297610152",
	["person-plus"] = "rbxassetid://126802984104475",
	["person-speaker"] = "rbxassetid://118694133626529",
	["person-worker"] = "rbxassetid://72283067948452",
	["person-xmark"] = "rbxassetid://100514977902172",
	["persons"] = "rbxassetid://70469668008783",
	["persons-lock"] = "rbxassetid://125295333446575",
	["picture"] = "rbxassetid://121179811894958",
	["pill"] = "rbxassetid://95053376969510",
	["pin"] = "rbxassetid://98714172077933",
	["pin-fill"] = "rbxassetid://135455996455542",
	["pin-slash"] = "rbxassetid://106760998399458",
	["pin-slash-fill"] = "rbxassetid://135561989808725",
	["pipeline"] = "rbxassetid://127156532534466",
	["plane"] = "rbxassetid://111442137230748",
	["plane-fill"] = "rbxassetid://106514623588033",
	["planet-earth"] = "rbxassetid://109328327555253",
	["play"] = "rbxassetid://87316717636842",
	["play-fill"] = "rbxassetid://81944593209262",
	["plug-connection"] = "rbxassetid://135837147660701",
	["plug-wire"] = "rbxassetid://97698299546425",
	["plus"] = "rbxassetid://80662775071567",
	["plus-shape"] = "rbxassetid://76944214577840",
	["plus-shape-fill"] = "rbxassetid://139105857222301",
	["power"] = "rbxassetid://138353101694958",
	["printer"] = "rbxassetid://131123146569579",
	["pulse"] = "rbxassetid://77126153989476",
	["puzzle"] = "rbxassetid://95674201006671",
	["qr-code"] = "rbxassetid://130769619091887",
	["quote-close"] = "rbxassetid://88565840976359",
	["quote-open"] = "rbxassetid://70929167034922",
	["receipt"] = "rbxassetid://131474240985462",
	["rectangle-pulse"] = "rbxassetid://111711523683961",
	["rectangles-4"] = "rbxassetid://120618780846189",
	["rocket"] = "rbxassetid://72732501782164",
	["round-brackets"] = "rbxassetid://101689273727463",
	["route"] = "rbxassetid://123758427507398",
	["sack"] = "rbxassetid://79102076460844",
	["scales-balanced"] = "rbxassetid://84869600023351",
	["scales-unbalanced"] = "rbxassetid://125351393561428",
	["scissors"] = "rbxassetid://83891508648427",
	["seal-check"] = "rbxassetid://114383699967547",
	["seal-percent"] = "rbxassetid://81252577691087",
	["server"] = "rbxassetid://103032027904546",
	["shapes-3"] = "rbxassetid://126934895067024",
	["shapes-4"] = "rbxassetid://94346755009249",
	["shield"] = "rbxassetid://126492969629387",
	["shield-check"] = "rbxassetid://130212494205207",
	["shield-exclamation"] = "rbxassetid://106149755930805",
	["shield-keyhole"] = "rbxassetid://132765890698199",
	["shopping-bag"] = "rbxassetid://119045069462549",
	["shopping-basket"] = "rbxassetid://75353938654634",
	["shopping-cart"] = "rbxassetid://124870886755485",
	["shuffle"] = "rbxassetid://73102173859910",
	["signal"] = "rbxassetid://90913466131390",
	["skull"] = "rbxassetid://83420758450923",
	["sliders"] = "rbxassetid://122721161727239",
	["sliders-vertical"] = "rbxassetid://76400438334805",
	["smartphone"] = "rbxassetid://86886555582618",
	["snail"] = "rbxassetid://115576237784392",
	["snowflake"] = "rbxassetid://110909689744928",
	["sparkles"] = "rbxassetid://128421724798018",
	["sparkles-fill"] = "rbxassetid://78549168418570",
	["speedometer"] = "rbxassetid://110143476875973",
	["sphere"] = "rbxassetid://130283294594898",
	["square"] = "rbxassetid://122997226258883",
	["square-article"] = "rbxassetid://118698086520012",
	["square-bars"] = "rbxassetid://134764451469323",
	["square-bars-vertical"] = "rbxassetid://85407882752366",
	["square-brackets"] = "rbxassetid://135215679548914",
	["square-brackets-bars-vertical"] = "rbxassetid://131077560251497",
	["square-brackets-letter-a"] = "rbxassetid://73723438286165",
	["square-chart-bar"] = "rbxassetid://71015029807443",
	["square-chart-column"] = "rbxassetid://108233991388760",
	["square-check"] = "rbxassetid://129517577270214",
	["square-dashed"] = "rbxassetid://92148931490321",
	["square-dashed-circle"] = "rbxassetid://134346520018636",
	["square-dashed-letter-a"] = "rbxassetid://131729372968637",
	["square-dashed-letter-t"] = "rbxassetid://136241753535397",
	["square-dashed-text"] = "rbxassetid://89082306894894",
	["square-dot"] = "rbxassetid://76761544648980",
	["square-exclamation"] = "rbxassetid://89733968105684",
	["square-fill"] = "rbxassetid://114726013880233",
	["square-hashtag"] = "rbxassetid://96174044824758",
	["square-letter-p"] = "rbxassetid://80311910925439",
	["square-letter-t"] = "rbxassetid://104779586576361",
	["square-line-horizontal"] = "rbxassetid://103870626448212",
	["square-line-vertical"] = "rbxassetid://138681242128568",
	["square-list-ul"] = "rbxassetid://121934696651725",
	["square-minus"] = "rbxassetid://137380824267207",
	["square-plus"] = "rbxassetid://73319794514420",
	["square-xmark"] = "rbxassetid://119167539843240",
	["star"] = "rbxassetid://82714530610376",
	["star-fill"] = "rbxassetid://112908772848069",
	["stethoscope"] = "rbxassetid://119209664784890",
	["sticker"] = "rbxassetid://74654761442741",
	["stop"] = "rbxassetid://74753225999323",
	["stop-fill"] = "rbxassetid://129724408640217",
	["stopwatch"] = "rbxassetid://74070793986442",
	["strikethrough"] = "rbxassetid://122272460020631",
	["suitcase"] = "rbxassetid://85738170275917",
	["sun"] = "rbxassetid://73708402464015",
	["superscript"] = "rbxassetid://83205898623495",
	["t-shirt"] = "rbxassetid://126587578410655",
	["tachometer"] = "rbxassetid://75978178969685",
	["tag"] = "rbxassetid://73313248079703",
	["tag-dollar"] = "rbxassetid://123305928004312",
	["tag-ruble"] = "rbxassetid://138522126576318",
	["tags"] = "rbxassetid://115994346321994",
	["target"] = "rbxassetid://83246673249608",
	["target-dart"] = "rbxassetid://77322579126050",
	["terminal"] = "rbxassetid://82516228510416",
	["terminal-line"] = "rbxassetid://109543607242216",
	["text"] = "rbxassetid://100102832947962",
	["text-align-center"] = "rbxassetid://100721831476135",
	["text-align-justify"] = "rbxassetid://85225101337173",
	["text-align-left"] = "rbxassetid://110886200281818",
	["text-align-right"] = "rbxassetid://84289940846927",
	["text-indent"] = "rbxassetid://88989450737244",
	["text-outdent"] = "rbxassetid://105177909864797",
	["thumbs-down"] = "rbxassetid://81293559344920",
	["thumbs-down-fill"] = "rbxassetid://136111475904802",
	["thumbs-up"] = "rbxassetid://95381074098952",
	["thumbs-up-2"] = "rbxassetid://88066568102248",
	["thumbs-up-fill"] = "rbxassetid://76753866435892",
	["thunderbolt"] = "rbxassetid://72414364939300",
	["thunderbolt-fill"] = "rbxassetid://108407820702676",
	["ticket"] = "rbxassetid://133508781907204",
	["timeline"] = "rbxassetid://72053264904498",
	["timestamps"] = "rbxassetid://87694590140038",
	["toggle-off"] = "rbxassetid://72859661230887",
	["toggle-on"] = "rbxassetid://86779165441121",
	["traffic-light"] = "rbxassetid://114478626716752",
	["trapezoid-left-line-horizontal"] = "rbxassetid://115336243014706",
	["trapezoid-up-line-vertical"] = "rbxassetid://77563309671286",
	["trash-bin"] = "rbxassetid://103767256411949",
	["tray"] = "rbxassetid://126858057212120",
	["triangle-down"] = "rbxassetid://82238326686665",
	["triangle-down-fill"] = "rbxassetid://73294647242721",
	["triangle-exclamation"] = "rbxassetid://75884953438553",
	["triangle-exclamation-fill"] = "rbxassetid://126758384179031",
	["triangle-left"] = "rbxassetid://80006508286559",
	["triangle-left-fill"] = "rbxassetid://118587504462189",
	["triangle-right"] = "rbxassetid://105983229462016",
	["triangle-right-fill"] = "rbxassetid://105532309942682",
	["triangle-thunderbolt"] = "rbxassetid://116364993642883",
	["triangle-up"] = "rbxassetid://75462475600328",
	["triangle-up-fill"] = "rbxassetid://98393490832027",
	["trolley"] = "rbxassetid://124134039113349",
	["tv"] = "rbxassetid://89593768065837",
	["tv-retro"] = "rbxassetid://121138629350895",
	["umbrella"] = "rbxassetid://136855445429009",
	["underline"] = "rbxassetid://111037385861002",
	["universal-access"] = "rbxassetid://129578549178419",
	["vault"] = "rbxassetid://93600999120652",
	["vector-circle"] = "rbxassetid://121395907084692",
	["vector-square"] = "rbxassetid://88721655919497",
	["video"] = "rbxassetid://94409367676512",
	["volume"] = "rbxassetid://77672150892068",
	["volume-fill"] = "rbxassetid://78065739687252",
	["volume-low"] = "rbxassetid://83196721920754",
	["volume-low-fill"] = "rbxassetid://103130247429745",
	["volume-off"] = "rbxassetid://128835255389731",
	["volume-off-fill"] = "rbxassetid://95683800715478",
	["volume-slash"] = "rbxassetid://113444931410054",
	["volume-slash-fill"] = "rbxassetid://80072301093738",
	["volume-xmark"] = "rbxassetid://131964141919250",
	["volume-xmark-fill"] = "rbxassetid://110913274367125",
	["weight-hanging"] = "rbxassetid://133001442287715",
	["wrench"] = "rbxassetid://124105097858234",
	["xmark"] = "rbxassetid://116696831480300",
	["xmark-shape"] = "rbxassetid://113332623964226",
	["xmark-shape-fill"] = "rbxassetid://102835594333260",
}

-- Lucide-style names -> Tree Hub icons.
-- The library asks for names like "settings", "x", "eye-off", "menu"...
-- but this icon set calls them "gear", "xmark", "eye-slash", "bars"...
-- so each Lucide name below points to the matching icon id.
local IconAliases = {
	["settings"] = "gear",
	["cog"] = "gear",
	["x"] = "xmark",
	["close"] = "xmark",
	["eye-off"] = "eye-slash",
	["minimize-2"] = "chevrons-collapse-up-right",
	["maximize-2"] = "chevrons-expand-up-right",
	["menu"] = "bars",
	["info"] = "circle-info",
	["triangle-alert"] = "triangle-exclamation",
	["alert-triangle"] = "triangle-exclamation",
	["circle-alert"] = "circle-exclamation",
	["alert-circle"] = "circle-exclamation",
	["x-circle"] = "circle-xmark",
	["circle-x"] = "circle-xmark",
	["check-circle"] = "circle-check",
	["help-circle"] = "circle-question",
	["circle-question-mark"] = "circle-question",
	["search"] = "magnifier",
	["user"] = "person",
	["users"] = "persons",
	["user-plus"] = "person-plus",
	["trash"] = "trash-bin",
	["trash-2"] = "trash-bin",
	["edit"] = "pencil-to-square",
	["square-pen"] = "pencil-to-square",
	["save"] = "floppy-disk",
	["download"] = "arrow-down-to-line",
	["upload"] = "arrow-up-from-line",
	["zap"] = "thunderbolt",
	["crosshair"] = "target",
	["unlock"] = "lock-open",
	["mail"] = "envelope",
	["refresh-cw"] = "arrows-rotate-right",
	["refresh-ccw"] = "arrows-rotate-left",
	["rotate-cw"] = "arrow-rotate-right",
	["rotate-ccw"] = "arrow-rotate-left",
	["bot"] = "face-robot",
	["crown"] = "crown-diamond",
	["volume-2"] = "volume",
	["volume-x"] = "volume-xmark",
	["bar-chart"] = "chart-bar",
	["line-chart"] = "chart-line",
	["pie-chart"] = "chart-pie",
	["more-horizontal"] = "ellipsis",
	["more-vertical"] = "ellipsis-vertical",
	["layout-dashboard"] = "layout-cells",
	["sliders-horizontal"] = "sliders",
	["map"] = "geo",
	["pointer"] = "hand-point-up",
	["lightbulb"] = "bulb",
	["gauge"] = "speedometer",
	["shield-alert"] = "shield-exclamation",
	["monitor"] = "display",
	["smile"] = "face-smile",
	["frown"] = "face-sad",
	["lock-keyhole"] = "folder-keyhole",
	["file-text"] = "file-text",
	["globe-2"] = "planet-earth",
}

-- Merge: Tree Hub set (local) + Solar set (7330 icons, loaded from GitHub)
local SOLAR_URL = "https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/solar/dist/Icons.lua"

do
	local all = {}
	-- 1) local Tree Hub icons (always available, even offline)
	for k, v in pairs(IconIDs) do all[k] = v end
	-- 2) Lucide-style aliases -> Tree Hub icons
	for alias, real in pairs(IconAliases) do
		if all[alias] == nil and IconIDs[real] then
			all[alias] = IconIDs[real]
		end
	end
	-- 3) Solar icons (needs HttpGet; if it fails the Tree Hub icons still work)
	local okSolar, solar = pcall(function()
		return loadstring(game:HttpGet(SOLAR_URL))()
	end)
	if okSolar and type(solar) == "table" then
		-- full names, e.g. "home-bold", "home-linear", "home-bold-duotone"
		for k, v in pairs(solar) do
			if all[k] == nil then all[k] = v end
		end
		-- short names, e.g. "home" (style priority: linear > outline > bold)
		for _, suffix in ipairs({ "-linear", "-outline", "-bold" }) do
			for k, v in pairs(solar) do
				if k:sub(-#suffix) == suffix then
					local base = k:sub(1, #k - #suffix)
					if all[base] == nil then all[base] = v end
				end
			end
		end
	else
		warn("[SimpleUI] Solar icons failed to load, using the Tree Hub set only.")
	end
	Library:SetIconAssets(all)
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
		or next(Lucide.AssetsByKey) ~= nil
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
				if asset == nil then asset = Lucide.AssetsByKey[normName(cand)] end
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

-- Library:DebugIcons("house") -> prints which icon sources are loaded and what each one returns
function Library:DebugIcons(name)
	name = name or "house"
	local function count(t)
		local n = 0
		for _ in pairs(t) do n += 1 end
		return n
	end

	print("---- SimpleUI icon debug ----")
	print("registry names:", Lucide.Count())
	print("ids from SetIconAssets:", count(Lucide.AssetsByKey))
	print("icons from folder:", count(folderIcons))

	local wind = Library.WindUI or env.WindUI or _G.WindUI
	print("WindUI found:", wind ~= nil)
	if type(wind) == "table" then
		local ok, res = pcall(function() return wind.Creator.Icons.Icon(name, "lucide") end)
		print("wind.Creator.Icons.Icon('" .. name .. "', 'lucide') ->", ok, typeof(res))
		if ok and type(res) == "table" then
			for k, v in pairs(res) do print("   [" .. tostring(k) .. "]", typeof(v), tostring(v)) end
		end
		local ok2, set = pcall(function() return wind.Creator.Icons.Icons.lucide end)
		print("wind.Creator.Icons.Icons.lucide ->", ok2, typeof(set), type(set) == "table" and (count(set) .. " keys") or "")
		if ok2 and type(set) == "table" then
			local shown = 0
			for k, v in pairs(set) do
				print("   sample key:", tostring(k), typeof(v))
				shown += 1
				if shown >= 3 then break end
			end
		end
	end

	iconCache[name] = nil
	local r = resolveIcon(name)
	print("resolve('" .. name .. "') ->", r and tostring(r.Image) or "NOT FOUND")
	print("-----------------------------")
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

--------------------------------------------------------------------
-- Live style: font family + font size
-- Used by the window (Interface tab) and by notifications.
--------------------------------------------------------------------
local function enumFont(name)
	local ok, f = pcall(function() return Enum.Font[name] end)
	if ok and typeof(f) == "EnumItem" then return f end
	return nil
end

-- { display name, regular, medium, bold }
local FontFamilies = {
	{ "Gotham", "Gotham", "GothamMedium", "GothamBold" },
	{ "Source Sans", "SourceSans", "SourceSansSemibold", "SourceSansBold" },
	{ "Arial", "Arial", "Arial", "ArialBold" },
	{ "Ubuntu", "Ubuntu", "Ubuntu", "Ubuntu" },
	{ "Nunito", "Nunito", "Nunito", "Nunito" },
	{ "Roboto", "Roboto", "Roboto", "Roboto" },
	{ "Oswald", "Oswald", "Oswald", "Oswald" },
	{ "Jura", "Jura", "Jura", "Jura" },
	{ "Titillium", "TitilliumWeb", "TitilliumWeb", "TitilliumWeb" },
	{ "Code", "Code", "Code", "Code" },
}

local FontMap, FontNames = {}, {}
for _, fam in ipairs(FontFamilies) do
	local r, m, b = enumFont(fam[2]), enumFont(fam[3]), enumFont(fam[4])
	if r and m and b then
		FontMap[fam[1]] = { regular = r, medium = m, bold = b }
		table.insert(FontNames, fam[1])
	end
end

local UIStyle = { Font = "Gotham", FontScale = 1 }

-- applies the current font (and font size) to one text object.
-- The original size / weight are remembered in attributes, so changes are never cumulative.
local function styleText(obj, withSize)
	if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then return end
	local weight = obj:GetAttribute("SUI_W")
	if not weight then
		local n = obj.Font.Name
		if n:find("Bold") or n:find("Black") then
			weight = "bold"
		elseif n:find("Medium") or n:find("Semibold") then
			weight = "medium"
		else
			weight = "regular"
		end
		obj:SetAttribute("SUI_W", weight)
		obj:SetAttribute("SUI_S", obj.TextSize)
	end
	local fam = FontMap[UIStyle.Font] or FontMap.Gotham
	obj.Font = fam[weight]
	if withSize ~= false then
		local base = obj:GetAttribute("SUI_S") or obj.TextSize
		obj.TextSize = math.clamp(math.floor(base * UIStyle.FontScale + 0.5), 6, 40)
	end
end

--------------------------------------------------------------------
-- Notification settings (internal)
-- Library:Notify reads them; they are changed from the built-in Settings tab.
--------------------------------------------------------------------
local NotifySettings = { Size = 100, Position = "Bottom Right", Icon = nil, Transparency = 0 }

local HA, VA = Enum.HorizontalAlignment, Enum.VerticalAlignment
-- { anchor X, anchor Y, list horizontal alignment, list vertical alignment }
local NotifyPositions = {
	["Top Left"] = { 0, 0, HA.Left, VA.Top },
	["Top Center"] = { 0.5, 0, HA.Center, VA.Top },
	["Top Right"] = { 1, 0, HA.Right, VA.Top },
	["Middle Left"] = { 0, 0.5, HA.Left, VA.Center },
	["Middle Right"] = { 1, 0.5, HA.Right, VA.Center },
	["Bottom Left"] = { 0, 1, HA.Left, VA.Bottom },
	["Bottom Center"] = { 0.5, 1, HA.Center, VA.Bottom },
	["Bottom Right"] = { 1, 1, HA.Right, VA.Bottom },
}
local NotifyPositionNames = {
	"Top Left", "Top Center", "Top Right", "Middle Left", "Middle Right",
	"Bottom Left", "Bottom Center", "Bottom Right",
}

local notifyHolder = new("Frame", {
	Name = "Notifications",
	ZIndex = 100,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.new(0, 480, 1, -32), -- wide enough for 150% notifications
}, gui)

local notifyLayout = new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 8),
}, notifyHolder)

local function applyNotifyPosition()
	local p = NotifyPositions[NotifySettings.Position] or NotifyPositions["Bottom Right"]
	local ax, ay = p[1], p[2]
	notifyHolder.AnchorPoint = Vector2.new(ax, ay)
	notifyHolder.Position = UDim2.new(
		ax, ax == 0 and 16 or (ax == 1 and -16 or 0),
		ay, ay == 0 and 16 or (ay == 1 and -16 or 0)
	)
	notifyLayout.HorizontalAlignment = p[3]
	notifyLayout.VerticalAlignment = p[4]
end
applyNotifyPosition()

-- the direction a notification slides in from (depends on the position)
local function slideOffset()
	local p = NotifyPositions[NotifySettings.Position] or NotifyPositions["Bottom Right"]
	if p[1] == 0 then return Vector2.new(-70, 0) end
	if p[1] == 1 then return Vector2.new(70, 0) end
	return Vector2.new(0, p[2] == 0 and -30 or 30)
end

local liveCards = {} -- cards currently on screen (so transparency can change live)

local function setNotifySize(pct)
	NotifySettings.Size = math.clamp(tonumber(pct) or 100, 50, 200)
end

local function setNotifyPosition(name)
	if NotifyPositions[name] then
		NotifySettings.Position = name
		applyNotifyPosition()
	end
end

local function setNotifyIcon(icon)
	if icon == nil or tostring(icon) == "" then
		NotifySettings.Icon = nil
	else
		NotifySettings.Icon = tostring(icon)
	end
end

local function setNotifyTransparency(pct)
	pct = math.clamp(tonumber(pct) or 0, 0, 100)
	NotifySettings.Transparency = pct
	for card in pairs(liveCards) do
		if card.Parent then card.GroupTransparency = pct / 100 end
	end
end

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

	local scale = NotifySettings.Size / 100
	local alpha = NotifySettings.Transparency / 100
	local from = slideOffset()
	local fam = FontMap[UIStyle.Font] or FontMap.Gotham

	local WIDTH = 300 -- base width; the card is scaled with UIScale
	local content = tostring(opts.Content or "")

	-- measure the message so the card fits it exactly
	local textH = 0
	if content ~= "" then
		local ok, size = pcall(function()
			return TextService:GetTextSize(content, 12, fam.regular, Vector2.new(WIDTH - 54 - 14, 10000))
		end)
		textH = ok and size.Y or 16
	end
	local height = math.max(58, 30 + textH + 18)

	local slotW = math.floor(WIDTH * scale + 0.5)
	local slot = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(slotW, math.floor(height * scale + 0.5)),
		LayoutOrder = notifyCount,
	}, notifyHolder)

	local card = new("CanvasGroup", {
		BackgroundColor3 = Theme.Surface,
		Size = UDim2.fromOffset(WIDTH, height),
		Position = UDim2.fromOffset(from.X, from.Y),
		GroupTransparency = 1,
	}, slot)
	new("UIScale", { Scale = scale }, card)
	corner(card, 10)
	stroke(card, Theme.Stroke)
	liveCards[card] = true

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
	local ic = createIcon(badge, opts.Icon or NotifySettings.Icon or kind.icon, 16, accent, kind.glyph)
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

	-- the notification uses the window font (the size is handled by the size setting)
	for _, d in ipairs(card:GetDescendants()) do styleText(d, false) end

	-- slide in + fade in (to the chosen transparency)
	tween(card, 0.3, { Position = UDim2.fromOffset(0, 0), GroupTransparency = alpha }, Enum.EasingStyle.Quint)
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		liveCards[card] = nil
		if not slot.Parent then return end
		-- slide out + fade out, then the stack collapses smoothly
		tween(card, 0.22, { Position = UDim2.fromOffset(from.X, from.Y), GroupTransparency = 1 })
		task.wait(0.23)
		if not slot.Parent then return end
		tween(slot, 0.15, { Size = UDim2.fromOffset(slotW, 0) })
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

	local FOOTER = 48 -- bottom area of the sidebar: the Settings tab is pinned there

	local tabList = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -(16 + FOOTER)),
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, sidebar)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabList)

	-- line above the pinned Settings tab
	new("Frame", {
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 14, 1, -(FOOTER - 2)),
		Size = UDim2.new(1, -28, 0, 1),
	}, sidebar)

	-- optional: logo at the bottom of the sidebar -> Window:SetLogo("rbxassetid://123")
	local logoObj
	function Window:SetLogo(image)
		if logoObj then logoObj:Destroy(); logoObj = nil end
		if image then
			logoObj = new("ImageLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 14, 1, -(FOOTER + 8)),
				Size = UDim2.fromOffset(28, 28),
				Image = image,
			}, sidebar)
			corner(logoObj, 6)
		end
		tabList.Size = UDim2.new(1, -16, 1, -(16 + FOOTER + (image and 36 or 0)))
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
		if cfg.Position then
			openBtn.AnchorPoint = cfg.AnchorPoint or Vector2.new(0, 0)
			openBtn.Position = cfg.Position
		end
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

	-- every tab (the pinned Settings tab is always last)
	local function allTabs()
		local list = table.clone(Window.Tabs)
		if Window._pinned then table.insert(list, Window._pinned) end
		return list
	end

	-- loading bar at the top of the pages (sweeps across when a tab opens)
	local loadBar = new("Frame", {
		BackgroundColor3 = accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 0, 2),
		ZIndex = 10,
	}, pages)
	corner(loadBar, 1)
	local loadToken = 0
	local function playLoadBar()
		loadToken += 1
		local my = loadToken
		loadBar.Size = UDim2.new(0, 0, 0, 2)
		loadBar.BackgroundTransparency = 0
		tween(loadBar, 0.6, { Size = UDim2.new(1, 0, 0, 2) }, Enum.EasingStyle.Quint)
		task.delay(0.6, function()
			if my == loadToken then tween(loadBar, 0.3, { BackgroundTransparency = 1 }) end
		end)
	end

	-- "loading" effect: every button / element of the tab shows a shimmering
	-- placeholder that fades away one after another
	local function playLoad(tab)
		local scroll = tab._scroll
		if not scroll then return end
		local n = 0
		for _, e in ipairs(scroll:GetChildren()) do
			if e:IsA("GuiObject") and e.BackgroundTransparency < 1 then
				n += 1
				local cover = new("Frame", {
					Name = "SUI_Load",
					BackgroundColor3 = Theme.SurfaceHover,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 20,
				}, e)
				local cr = e:FindFirstChildOfClass("UICorner")
				corner(cover, cr and cr.CornerRadius.Offset or 8)
				local grad = new("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Theme.SurfaceHover),
						ColorSequenceKeypoint.new(0.5, Theme.Stroke),
						ColorSequenceKeypoint.new(1, Theme.SurfaceHover),
					}),
					Offset = Vector2.new(-1, 0),
				}, cover)
				tween(grad, 0.6, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine)
				task.delay(0.3 + math.min(n, 9) * 0.07, function()
					if cover.Parent then
						tween(cover, 0.32, { BackgroundTransparency = 1 })
						task.delay(0.34, function() cover:Destroy() end)
					end
				end)
			end
		end
	end

	-- page transition: the new page slides up + fades in, then its buttons "load"
	local function showPage(tab, animate)
		local wrap = tab._page
		wrap.Visible = true
		if animate then
			wrap.GroupTransparency = 1
			wrap.Position = UDim2.fromOffset(0, 14)
			tween(wrap, 0.38, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
			playLoadBar()
			playLoad(tab)
		else
			wrap.GroupTransparency = 0
			wrap.Position = UDim2.fromOffset(0, 0)
		end
	end

	-- tab buttons slide in / out of the sidebar, one after another
	local function animateTabs(showing, token)
		for i, t in ipairs(allTabs()) do
			local b = t._btn
			if showing then b.Position = UDim2.new(-1, 0, 0, 0) end
			task.delay((i - 1) * 0.07, function()
				if token ~= animToken then return end
				tween(b, 0.4, {
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
			BackgroundColor3 = Theme.Background,
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
			tween(t._btn, 0.25, { BackgroundTransparency = bgT })
			tween(t._bar, 0.3, { Size = barSize }, Enum.EasingStyle.Back)
			if t._pinned then
				-- the gear turns when the Settings tab is opened / closed
				tween(t._ic, 0.6, { Rotation = active and 180 or 0 }, Enum.EasingStyle.Quint)
			end
		end
	end

	local function selectTab(tab, instant)
		if Window.Current == tab then return end
		local previous = Window.Current
		Window.Current = tab

		for _, t in ipairs(allTabs()) do
			setActive(t, t == tab, instant)
		end

		if instant then
			showPage(tab, false)
			return
		end

		-- exit animation for the old page, then enter animation for the new one
		if previous then
			local old = previous._page
			tween(old, 0.2, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -10) })
			task.delay(0.21, function()
				if Window.Current ~= previous then old.Visible = false end
			end)
		end

		local wrap = tab._page
		wrap.Visible = true
		wrap.GroupTransparency = 1
		wrap.Position = UDim2.fromOffset(0, 14)
		task.delay(previous and 0.14 or 0, function()
			if Window.Current == tab then
				tween(wrap, 0.38, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
				playLoadBar()
				playLoad(tab)
			end
		end)
	end

	function Window:Tab(topts)
		topts = topts or {}
		local Tab = {}

		-- slot clips the button so it can slide in from the left
		-- _Pinned (internal): the built-in Settings tab lives in the sidebar footer, under every tab
		local pinned = topts._Pinned == true
		local slot = new("Frame", {
			BackgroundTransparency = 1,
			Size = pinned and UDim2.new(1, -16, 0, 34) or UDim2.new(1, 0, 0, 34),
			Position = pinned and UDim2.new(0, 8, 1, -42) or UDim2.new(),
			ClipsDescendants = true,
			LayoutOrder = #Window.Tabs + 1,
		}, pinned and sidebar or tabList)

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
		ic.AnchorPoint = Vector2.new(0.5, 0.5) -- so the icon can turn around its center
		ic.Position = UDim2.new(0, 19, 0.5, 0)

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

		-- hover / press effects: the icon nudges, the button dips when pressed
		local pressScale = new("UIScale", { Scale = 1 }, btn)
		btn.MouseEnter:Connect(function()
			if Window.Current ~= Tab then tween(btn, 0.2, { BackgroundTransparency = 0.6 }) end
			tween(ic, 0.25, { Position = UDim2.new(0, 22, 0.5, 0) }, Enum.EasingStyle.Back)
			if pinned and Window.Current ~= Tab then tween(ic, 0.5, { Rotation = 90 }, Enum.EasingStyle.Quint) end
		end)
		btn.MouseLeave:Connect(function()
			if Window.Current ~= Tab then tween(btn, 0.2, { BackgroundTransparency = 1 }) end
			tween(ic, 0.25, { Position = UDim2.new(0, 19, 0.5, 0) })
			if pinned and Window.Current ~= Tab then tween(ic, 0.5, { Rotation = 0 }, Enum.EasingStyle.Quint) end
		end)
		btn.MouseButton1Down:Connect(function() tween(pressScale, 0.08, { Scale = 0.95 }) end)
		btn.MouseButton1Up:Connect(function() tween(pressScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back) end)

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
		Tab._scroll = page
		Tab._ic = ic
		Tab._pinned = pinned
		if pinned then
			Window._pinned = Tab
		else
			table.insert(Window.Tabs, Tab)
		end

		btn.Activated:Connect(function() selectTab(Tab) end)
		if not pinned and #Window.Tabs == 1 then selectTab(Tab, true) end

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

	--------------------------------------------------------------
	-- Built-in Settings tab (default system)
	-- Created automatically with every window. It is pinned to the bottom of
	-- the sidebar, so it always stays under all the tabs you add.
	-- It holds the window settings, the open button settings and the
	-- notification settings. Everything here changes the real UI live.
	--------------------------------------------------------------
	local baseSize = fullSize
	local ui = { Transparency = 0, SizePct = 100, FontPct = 100, Font = "Gotham" }

	-- keep text styled (font + size) for everything added to the window later
	table.insert(State.Conns, main.DescendantAdded:Connect(function(d) styleText(d) end))

	-- recolor everything that still has an old theme color
	local function recolorAll(old)
		local fills = {
			{ old.Background, Theme.Background },
			{ old.Surface, Theme.Surface },
			{ old.SurfaceHover, Theme.SurfaceHover },
			{ old.Stroke, Theme.Stroke },
		}
		local texts = {
			{ old.Text, Theme.Text },
			{ old.SubText, Theme.SubText },
		}
		local function map(list, c)
			for _, p in ipairs(list) do
				if c == p[1] then return p[2] end
			end
			return nil
		end
		for _, o in ipairs(gui:GetDescendants()) do
			if o:IsA("GuiObject") then
				local n = map(fills, o.BackgroundColor3)
				if n then o.BackgroundColor3 = n end
				if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
					local t = map(texts, o.TextColor3)
					if t then o.TextColor3 = t end
					if o:IsA("TextBox") then
						local pc = map(texts, o.PlaceholderColor3)
						if pc then o.PlaceholderColor3 = pc end
					end
				elseif o:IsA("ImageLabel") or o:IsA("ImageButton") then
					local t = map(texts, o.ImageColor3)
					if t then o.ImageColor3 = t end
				end
				if o:IsA("ScrollingFrame") then
					local s = map(fills, o.ScrollBarImageColor3)
					if s then o.ScrollBarImageColor3 = s end
				end
			elseif o:IsA("UIStroke") then
				local s = map(fills, o.Color)
				if s then o.Color = s end
			end
		end
	end

	-- window color (background, cards, borders; the text turns dark on light colors)
	local function setColor(c)
		if typeof(c) ~= "Color3" then return end
		local old = {
			Background = Theme.Background, Surface = Theme.Surface, SurfaceHover = Theme.SurfaceHover,
			Stroke = Theme.Stroke, Text = Theme.Text, SubText = Theme.SubText,
		}
		applyTheme(c)
		local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
		if lum > 0.6 then
			Theme.Text = Color3.fromRGB(24, 24, 28)
			Theme.SubText = Color3.fromRGB(95, 95, 105)
		else
			Theme.Text = Color3.fromRGB(235, 235, 235)
			Theme.SubText = Color3.fromRGB(150, 150, 150)
		end
		recolorAll(old)
		ui.Color = c
	end

	-- window transparency: only the window background fades,
	-- the tabs, buttons and texts stay fully visible
	local function setTransparency(pct)
		pct = math.clamp(tonumber(pct) or 0, 0, 100)
		ui.Transparency = pct
		main.BackgroundTransparency = pct / 100
	end

	-- window size in percent of the size it was created with
	local function setSize(pct)
		pct = math.clamp(tonumber(pct) or 100, 70, 140)
		ui.SizePct = pct
		local k = pct / 100
		local w = math.floor(baseSize.X.Offset * k + 0.5)
		local h = math.floor(baseSize.Y.Offset * k + 0.5)
		pcall(function()
			local vp = workspace.CurrentCamera.ViewportSize
			if baseSize.X.Scale == 0 then w = math.min(w, vp.X - 24) end
			if baseSize.Y.Scale == 0 then h = math.min(h, vp.Y - 24) end
		end)
		fullSize = UDim2.new(baseSize.X.Scale, w, baseSize.Y.Scale, h)
		if minimized then
			tween(main, 0.1, { Size = UDim2.new(fullSize.X.Scale, fullSize.X.Offset, 0, 48) })
		else
			tween(main, 0.1, { Size = fullSize })
		end
	end

	-- font size of the whole window in percent
	local function setFontSize(pct)
		pct = math.clamp(tonumber(pct) or 100, 80, 125)
		ui.FontPct = pct
		UIStyle.FontScale = pct / 100
		for _, d in ipairs(main:GetDescendants()) do styleText(d) end
	end

	-- font family of the whole window
	local function setFont(name)
		if not FontMap[name] then return end
		ui.Font = name
		UIStyle.Font = name
		for _, d in ipairs(main:GetDescendants()) do styleText(d) end
	end

	-- open button
	local function setButtonSize(px)
		px = math.clamp(tonumber(px) or 56, 28, 120)
		openBtn.Size = UDim2.fromOffset(px, px)
		refreshOpenButton()
	end

	local function setButtonColor(c)
		if typeof(c) == "Color3" then openBtn.BackgroundColor3 = c end
	end

	local function setButtonName(text)
		text = text ~= nil and tostring(text) or ""
		openCfg.Name = text ~= "" and text or nil
		refreshOpenButton()
	end

	local function setButtonIcon(icon)
		icon = icon ~= nil and tostring(icon) or ""
		openCfg.Image = icon ~= "" and icon or nil
		refreshOpenButton()
	end

	local function setButtonTransparency(pct)
		pct = math.clamp(tonumber(pct) or 0, 0, 100)
		openBtn.BackgroundTransparency = pct / 100
		openStroke.Transparency = pct / 100
	end

	-- { anchor X, anchor Y }
	local ButtonPositions = {
		["Left"] = { 0, 0.5 }, ["Right"] = { 1, 0.5 },
		["Top"] = { 0.5, 0 }, ["Bottom"] = { 0.5, 1 },
		["Top Left"] = { 0, 0 }, ["Top Right"] = { 1, 0 },
		["Bottom Left"] = { 0, 1 }, ["Bottom Right"] = { 1, 1 },
		["Center"] = { 0.5, 0.5 },
	}
	local ButtonPositionNames = {
		"Left", "Right", "Top", "Bottom", "Top Left", "Top Right", "Bottom Left", "Bottom Right", "Center",
	}

	local function setButtonPosition(name)
		local p = ButtonPositions[name]
		if not p then return end
		local ax, ay = p[1], p[2]
		openBtn.AnchorPoint = Vector2.new(ax, ay)
		openBtn.Position = UDim2.new(
			ax, ax == 0 and 20 or (ax == 1 and -20 or 0),
			ay, ay == 0 and 20 or (ay == 1 and -20 or 0)
		)
	end

	-- the tab itself
	do
		local Tab = Window:Tab({ Title = "Settings", Icon = "settings", _Pinned = true })

		Tab:Section("Window")

		Tab:Slider({
			Title = "Window Transparency",
			Desc = "Only the background fades, the tabs stay visible",
			Min = 0, Max = 100, Default = ui.Transparency, Step = 1, Suffix = "%",
			Callback = setTransparency,
		})

		Tab:ColorPicker({
			Title = "Window Color",
			Desc = "Background, cards and borders",
			Default = Theme.Background,
			Callback = setColor,
		})

		Tab:Slider({
			Title = "Window Size",
			Desc = "Scale the window",
			Min = 70, Max = 140, Default = ui.SizePct, Step = 5, Suffix = "%",
			Callback = setSize,
		})

		Tab:Slider({
			Title = "Font Size",
			Desc = "Text size of the whole window",
			Min = 80, Max = 125, Default = ui.FontPct, Step = 5, Suffix = "%",
			Callback = setFontSize,
		})

		Tab:Dropdown({
			Title = "Font",
			Desc = "Font of the whole window",
			Options = FontNames,
			Default = ui.Font,
			Callback = setFont,
		})

		Tab:Section("Open Button")

		Tab:Slider({
			Title = "Button Size",
			Min = 28, Max = 120, Default = math.max(28, openBtn.Size.Y.Offset), Step = 2, Suffix = " px",
			Callback = setButtonSize,
		})

		Tab:ColorPicker({
			Title = "Button Color",
			Default = openBtn.BackgroundColor3,
			Callback = setButtonColor,
		})

		Tab:Input({
			Title = "Button Name",
			Desc = "Text on the button (empty = icon only)",
			Placeholder = "Name...",
			Default = openCfg.Name or "",
			Callback = setButtonName,
		})

		Tab:Input({
			Title = "Button Icon",
			Desc = "Icon name or rbxassetid (empty = default)",
			Placeholder = "house",
			Default = type(openCfg.Image) == "string" and openCfg.Image or "",
			Callback = setButtonIcon,
		})

		Tab:Slider({
			Title = "Button Transparency",
			Min = 0, Max = 100, Default = math.floor(openBtn.BackgroundTransparency * 100 + 0.5), Step = 1, Suffix = "%",
			Callback = setButtonTransparency,
		})

		Tab:Dropdown({
			Title = "Button Position",
			Desc = "You can also drag the button",
			Options = ButtonPositionNames,
			Callback = setButtonPosition,
		})

		Tab:Section("Notifications")

		Tab:Slider({
			Title = "Notification Size",
			Desc = "Applies to new notifications",
			Min = 70, Max = 150, Default = NotifySettings.Size, Step = 5, Suffix = "%",
			Callback = setNotifySize,
		})

		Tab:Dropdown({
			Title = "Notification Position",
			Options = NotifyPositionNames,
			Default = NotifySettings.Position,
			Callback = setNotifyPosition,
		})

		Tab:Input({
			Title = "Notification Icon",
			Desc = "Icon name or rbxassetid (empty = default)",
			Placeholder = "bell",
			Default = NotifySettings.Icon or "",
			Callback = setNotifyIcon,
		})

		Tab:Slider({
			Title = "Notification Transparency",
			Min = 0, Max = 100, Default = NotifySettings.Transparency, Step = 1, Suffix = "%",
			Callback = setNotifyTransparency,
		})

		Tab:Button({
			Title = "Test Notification",
			Desc = "Preview with the current settings",
			Callback = function()
				Library:Notify({ Title = "Preview", Content = "This is how notifications look.", Type = "info", Duration = 3 })
			end,
		})
	end

	return Window
end


return Library
 
