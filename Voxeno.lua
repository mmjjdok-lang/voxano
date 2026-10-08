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

		local clean = (name:gsub("^lucide[-:]", ""))
		local wind = Library.WindUI or env.WindUI or _G.WindUI

		-- 1) the official WindUI function
		if not result and type(wind) == "table" then
			local ok, res = pcall(function()
				return wind.Creator.Icons.Icon(clean, "lucide")
			end)
			if ok and res then result = parseIcon(res, nil) end
		end

		-- 2) the lucide table directly
		if not result then
			local set = Library.LucideIcons
			if not set and type(wind) == "table" then
				pcall(function() set = wind.Creator.Icons.Icons.lucide end)
			end
			if type(set) == "table" then
				local icons = type(set.Icons) == "table" and set.Icons or set
				local data = icons[name] or icons[clean] or icons[clean:lower()]
				result = parseIcon(data, set)
			end
		end

		if not result and (Library.LucideIcons or Library.WindUI) and not warned[name] then
			warned[name] = true
			warn("[SimpleUI] Lucide icon not found: " .. name)
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

--------------------------------------------------------------------
-- Dragging (returns a function telling whether a real drag happened)
--------------------------------------------------------------------
local function makeDraggable(handle, target)
	local dragging, dragStart, startPos = false, nil, nil
	local moved = false

	handle.InputBegan:Connect(function(input)
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
--------------------------------------------------------------------
local notifyHolder = new("Frame", {
	Name = "Notifications",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.new(0, 280, 1, -32),
}, gui)

new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 8),
}, notifyHolder)

local notifyCount = 0

function Library:Notify(opts)
	opts = opts or {}
	local duration = opts.Duration or 4
	local accent = opts.Color or Theme.Accent
	notifyCount += 1

	local slot = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(280, 68),
		LayoutOrder = notifyCount,
	}, notifyHolder)

	local card = new("Frame", {
		BackgroundColor3 = Theme.Background,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.new(1, 320, 0, 0),
		ClipsDescendants = true,
	}, slot)
	corner(card, 10)
	stroke(card, Theme.Stroke)

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 7),
		Size = UDim2.new(1, -24, 0, 16),
		Text = tostring(opts.Title or "Notification"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, card)

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 25),
		Size = UDim2.new(1, -24, 0, 28),
		Text = tostring(opts.Content or ""),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Theme.SubText,
	}, card)

	local track = new("Frame", {
		BackgroundColor3 = Theme.Surface,
		Position = UDim2.new(0, 10, 1, -9),
		Size = UDim2.new(1, -20, 0, 3),
		BorderSizePixel = 0,
	}, card)
	corner(track, 2)

	local fill = new("Frame", {
		BackgroundColor3 = accent,
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
	}, track)
	corner(fill, 2)

	tween(card, 0.25, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	task.delay(duration, function()
		if not slot.Parent then return end
		tween(card, 0.25, { Position = UDim2.new(1, 320, 0, 0) }, Enum.EasingStyle.Quint)
		task.wait(0.27)
		slot:Destroy()
	end)
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

	local bg = opts.Color or Theme.Background
	local accent = opts.Accent or Theme.Accent
	local fullSize = opts.Size or UDim2.new(0, 550, 0, 356)
	if opts.Icons then Library:SetIcons(opts.Icons) end
	if opts.WindUI then Library:SetWindUI(opts.WindUI) end

	local main = new("Frame", {
		Name = "Window",
		BackgroundColor3 = bg,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = fullSize,
		ClipsDescendants = true,
	}, gui)
	corner(main, 12)
	stroke(main, Theme.Stroke)

	-- Topbar
	local top = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
	}, main)

	local titleX = 14
	if opts.Icon then
		local ic = createIcon(top, opts.Icon, 22, Theme.Text)
		ic.Position = UDim2.fromOffset(14, 13)
		titleX = 44
	end

	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(titleX, opts.Description and 7 or 14),
		Size = UDim2.new(1, -(titleX + 120), 0, 18),
		Text = tostring(opts.Title or "Window"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, top)

	if opts.Description then
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(titleX, 26),
			Size = UDim2.new(1, -(titleX + 120), 0, 14),
			Text = tostring(opts.Description),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = Theme.SubText,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, top)
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
		Size = UDim2.new(1, -16, 1, opts.Logo and -52 or -16),
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, sidebar)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabList)

	if opts.Logo then
		local logo = new("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -10),
			Size = UDim2.fromOffset(28, 28),
			Image = opts.Logo,
		}, sidebar)
		corner(logo, 6)
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
	--------------------------------------------------------------
	local ob = opts.OpenButton or {}
	local openBtn = new("ImageButton", {
		Name = "OpenButton",
		BackgroundColor3 = ob.Color or Theme.Background,
		Position = ob.Position or UDim2.new(0, 20, 0.5, -24),
		Size = ob.Size or UDim2.fromOffset(48, 48),
		Image = ob.Image or "",
		AutoButtonColor = false,
		ScaleType = Enum.ScaleType.Fit,
	}, gui)
	corner(openBtn, 12)
	stroke(openBtn, Theme.Stroke)
	if not ob.Image then
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = "☰",
			Font = Enum.Font.GothamBold,
			TextSize = 20,
			TextColor3 = Theme.Text,
		}, openBtn)
	end

	local wasDragged = function() return false end
	if ob.Draggable ~= false then
		wasDragged = makeDraggable(openBtn, openBtn)
	end

	--------------------------------------------------------------
	-- Window controls
	--------------------------------------------------------------
	local minimized = false
	local savedPos = main.Position

	function Window:Show() main.Visible = true end
	function Window:Hide() main.Visible = false end
	function Window:Toggle() main.Visible = not main.Visible end

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
	local function selectTab(tab)
		if Window.Current == tab then return end
		for _, t in ipairs(Window.Tabs) do
			t._page.Visible = (t == tab)
			t._btn.BackgroundTransparency = (t == tab) and 0 or 1
		end
		Window.Current = tab
	end

	function Window:Tab(topts)
		topts = topts or {}
		local Tab = {}

		local btn = new("TextButton", {
			BackgroundColor3 = Theme.Surface,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = #Window.Tabs + 1,
		}, tabList)
		corner(btn, 8)

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

		local page = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.Stroke,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Visible = false,
		}, pages)
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		new("UIPadding", { PaddingRight = UDim.new(0, 6) }, page)

		Tab._btn = btn
		Tab._page = page
		table.insert(Window.Tabs, Tab)

		btn.Activated:Connect(function() selectTab(Tab) end)
		if #Window.Tabs == 1 then selectTab(Tab) end

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

			card.MouseEnter:Connect(function() tween(card, 0.1, { BackgroundColor3 = Theme.SurfaceHover }) end)
			card.MouseLeave:Connect(function() tween(card, 0.1, { BackgroundColor3 = Theme.Surface }) end)
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

--------------------------------------------------------------------
-- Example
--------------------------------------------------------------------
-- Lucide icons: pass your WindUI object (best) and icons resolve through
-- WindUI.Creator.Icons.Icon(name, "lucide"), falling back to the table
-- WindUI.Creator.Icons.Icons.lucide.
--
-- If WindUI is a local in your script, add this line BEFORE CreateWindow:
--     Library:SetWindUI(WindUI)
-- (a global WindUI / getgenv().WindUI is detected automatically)

local Window = Library:CreateWindow({
	Title = "My Hub",
	Description = "Simple, fast and clean",
	Icon = "home",
	Logo = "rbxassetid://0", -- replace with your logo asset id
	-- WindUI = WindUI,      -- or pass it here
	-- Color = Color3.fromRGB(18, 18, 18),
	OpenButton = {
		Size = UDim2.fromOffset(48, 48),
		Image = "",
		Color = Color3.fromRGB(18, 18, 18),
		Position = UDim2.new(0, 20, 0.5, -24),
		Draggable = true,
	},
})

local Main = Window:Tab({ Title = "Main", Icon = "home" })
local Settings = Window:Tab({ Title = "Settings", Icon = "settings" })

Main:Label("Welcome! This is a label.")

Main:Note({
	Title = "Dark note",
	Text = "This is a dark note for general information.",
	Style = "Dark",
})

Main:Note({
	Title = "Blue note",
	Text = "This is a blue note for important information.",
	Style = "Blue",
})

Main:Button({
	Title = "Test Button",
	Desc = "Shows a notification when clicked",
	Callback = function()
		Library:Notify({
			Title = "Success",
			Content = "The button was clicked successfully.",
			Duration = 4,
		})
	end,
})

Main:Toggle({
	Title = "Enable Feature",
	Desc = "Turn this feature on or off",
	Default = false,
	Callback = function(state)
		print("Toggle:", state)
	end,
})

Settings:Slider({
	Title = "Walk Speed",
	Desc = "Drag to change the value",
	Min = 16,
	Max = 100,
	Default = 16,
	Step = 1,
	Suffix = "",
	Callback = function(value)
		print("Slider:", value)
	end,
})

Settings:Toggle({
	Title = "Another Option",
	Callback = function(state) print("Option:", state) end,
})

return Library
