-- DungeonSwitch: two addon modes per character.
--   Normal  = your usual addons.
--   Dungeon = the addons on the shared list are turned off for this character.
-- Switching changes the per-character enable state and reloads the UI (WoW only
-- loads or unloads addons on a reload). Only addons that DungeonSwitch itself
-- turned off are turned back on, so anything you had disabled stays disabled.
-- Nothing runs between zone changes: no timers, no OnUpdate (except while the
-- minimap button is being dragged).

local ADDON, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Key_03"
local COLOR = "|cff66ccff"

local A = C_AddOns
local Reload = (C_UI and C_UI.Reload) or ReloadUI

local db, cdb, me
local skipKey, skipLeave, waitCombat = nil, false, false

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(COLOR .. "DungeonSwitch:|r " .. msg)
end

---------------------------------------------------------------------------
-- Addon state helpers
---------------------------------------------------------------------------

local function Exists(name)
	if A.DoesAddOnExist then return A.DoesAddOnExist(name) end
	return A.GetAddOnInfo(name) ~= nil
end

local function EnabledHere(name)
	local s = A.GetAddOnEnableState(name, me)
	return s == true or (type(s) == "number" and s > 0)
end

local function Title(name)
	local _, title = A.GetAddOnInfo(name)
	title = title or name
	return (title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Addons on the list that are installed and currently on for this character.
local function ToDisable()
	local out = {}
	for name, on in pairs(db.list) do
		if on and name ~= ADDON and Exists(name) and EnabledHere(name) then
			out[#out + 1] = name
		end
	end
	table.sort(out)
	return out
end

local function Names(list)
	local t = {}
	for i, name in ipairs(list) do t[i] = Title(name) end
	return #t > 0 and table.concat(t, ", ") or "nothing"
end

local function InDungeon()
	local inside, kind = IsInInstance()
	return inside and (kind == "party" or kind == "raid")
end

local function InstanceKey()
	local name, _, _, _, _, _, _, id = GetInstanceInfo()
	return tostring(id or name)
end

---------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------

function ns.Switch(target)
	if InCombatLockdown() then
		Print("can't switch during combat. Try again when the fight is over.")
		return
	end
	if target == "dungeon" then
		local list = ToDisable()
		wipe(cdb.disabled)
		for _, name in ipairs(list) do
			A.DisableAddOn(name, me)
			cdb.disabled[#cdb.disabled + 1] = name
		end
		cdb.mode = "dungeon"
	else
		for _, name in ipairs(cdb.disabled) do
			if Exists(name) then A.EnableAddOn(name, me) end
		end
		wipe(cdb.disabled)
		cdb.mode = "normal"
	end
	if A.SaveAddOns then A.SaveAddOns() end
	Reload()
end

local function Other()
	return cdb.mode == "dungeon" and "normal" or "dungeon"
end

local function ModeName(mode)
	return mode == "dungeon" and "Dungeon" or "Normal"
end

-- Manual switch (minimap button, /ds): always asks first, since it reloads.
function ns.AskSwitch()
	local target = Other()
	local dialog = StaticPopup_Show("DUNGEONSWITCH_CONFIRM", ModeName(target), nil, target)
	if dialog and dialog.data == nil then dialog.data = target end
end

---------------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------------

StaticPopupDialogs["DUNGEONSWITCH_TO_DUNGEON"] = {
	text = COLOR .. "DungeonSwitch|r\n\nSwitch to Dungeon mode?\nYour UI will reload.",
	button1 = "Switch",
	button2 = "Not now",
	OnAccept = function() ns.Switch("dungeon") end,
	OnCancel = function() skipKey = InstanceKey() end,
	timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

StaticPopupDialogs["DUNGEONSWITCH_TO_NORMAL"] = {
	text = COLOR .. "DungeonSwitch|r\n\nYou left the dungeon. Switch back to Normal mode?\nYour UI will reload.",
	button1 = "Switch back",
	button2 = "Not now",
	OnAccept = function() ns.Switch("normal") end,
	OnCancel = function() skipLeave = true end,
	timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

StaticPopupDialogs["DUNGEONSWITCH_CONFIRM"] = {
	text = COLOR .. "DungeonSwitch|r\n\nSwitch to %s mode?\nYour UI will reload.",
	button1 = "Switch",
	button2 = "Cancel",
	OnAccept = function(self, data) ns.Switch(data or (self and self.data)) end,
	timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Automatic check on zone changes
---------------------------------------------------------------------------

local function Check()
	if not cdb then return end
	if InCombatLockdown() then waitCombat = true; return end

	if InDungeon() then
		skipLeave = false
		StaticPopup_Hide("DUNGEONSWITCH_TO_NORMAL")
		if db.popup and cdb.mode == "normal" and skipKey ~= InstanceKey() then
			local list = ToDisable()
			if #list > 0 then
				StaticPopup_Show("DUNGEONSWITCH_TO_DUNGEON")
			end
		end
	else
		StaticPopup_Hide("DUNGEONSWITCH_TO_DUNGEON")
		-- A ghost on a corpse run is outside for a moment: don't ask then.
		if UnitIsDeadOrGhost("player") then return end
		skipKey = nil
		if cdb.mode == "dungeon" then
			if #cdb.disabled == 0 then
				cdb.mode = "normal" -- nothing to turn back on, no reload needed
			elseif db.popup and not skipLeave then
				StaticPopup_Show("DUNGEONSWITCH_TO_NORMAL")
			end
		end
	end
	if ns.UpdateButton then ns.UpdateButton() end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local button

local function PlaceButton()
	local a = math.rad(db.minimap.angle or 200)
	local r = (Minimap:GetWidth() / 2) + 8
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function CreateButton()
	if button or not Minimap then return end
	local b = CreateFrame("Button", "DungeonSwitchMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")

	local overlay = b:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(19, 19)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint("TOPLEFT", 6, -5)
	b.icon = icon
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	b:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then ns.OpenSettings() else ns.AskSwitch() end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			db.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
			PlaceButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("DungeonSwitch", 0.4, 0.8, 1)
		GameTooltip:AddLine("Mode: " .. ModeName(cdb.mode), 1, 1, 1)
		if cdb.mode == "dungeon" then
			GameTooltip:AddLine("Off: " .. Names(cdb.disabled), 0.8, 0.8, 0.8, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click: switch to " .. ModeName(Other()) .. " mode", 1, 1, 1)
		GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
		GameTooltip:AddLine("Drag: move button", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button = b
	PlaceButton()
end

function ns.UpdateButton()
	if not button then CreateButton() end
	if not button then return end
	button:SetShown(not db.minimap.hide)
	-- Coloured key in Dungeon mode, grey key in Normal mode.
	button.icon:SetDesaturated(cdb.mode ~= "dungeon")
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = "DungeonSwitch"
local category

local function Checkbox(parent, label, onClick)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	fs:SetText(label)
	cb.label = fs
	cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return cb
end

local function BuildPanel()
	if panel.built then return end
	panel.built = true

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("DungeonSwitch")

	local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	intro:SetJustifyH("LEFT")
	intro:SetText("Ticked addons are turned off while a character is in Dungeon mode. "
		.. "The list is shared by all characters. Switching reloads the UI.")

	local mode = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	mode:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
	panel.modeText = mode

	local switch = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	switch:SetSize(150, 22)
	switch:SetPoint("LEFT", mode, "RIGHT", 12, 0)
	switch:SetScript("OnClick", function() ns.AskSwitch() end)
	panel.switchButton = switch

	local popup = Checkbox(panel, "Ask automatically when entering or leaving a dungeon or raid",
		function(v) db.popup = v end)
	popup:SetPoint("TOPLEFT", mode, "BOTTOMLEFT", -4, -12)
	panel.popupBox = popup

	local mm = Checkbox(panel, "Show minimap button", function(v)
		db.minimap.hide = not v
		ns.UpdateButton()
	end)
	mm:SetPoint("TOPLEFT", popup, "BOTTOMLEFT", 0, -2)
	panel.minimapBox = mm

	local head = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	head:SetPoint("TOPLEFT", mm, "BOTTOMLEFT", 4, -14)
	head:SetText("Turn off in Dungeon mode:")

	panel.boxes = ns.AddonList(panel, head, -30, 12)
end

-- A scrolling list with a checkbox per installed addon (except this one),
-- placed under `top` and stretched to the parent's bottom-right corner.
function ns.AddonList(parent, top, right, bottom)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", top, "BOTTOMLEFT", -4, -6)
	scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", right, bottom)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(400, 10)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)

	local names = {}
	for i = 1, A.GetNumAddOns() do
		local name = A.GetAddOnInfo(i)
		if name and name ~= ADDON then names[#names + 1] = name end
	end
	table.sort(names, function(a, b) return Title(a):lower() < Title(b):lower() end)

	local boxes = {}
	for i, name in ipairs(names) do
		local label = Title(name)
		if label ~= name then label = label .. " |cff888888(" .. name .. ")|r" end
		local cb = Checkbox(content, label, function(v) db.list[name] = v or nil end)
		cb:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
		cb:SetChecked(db.list[name] and true or false)
		cb.addon = name
		boxes[#boxes + 1] = cb
	end
	content:SetHeight(math.max(10, #names * 24))
	return boxes
end

---------------------------------------------------------------------------
-- Welcome screen: shown once, the first time DungeonSwitch is installed.
---------------------------------------------------------------------------

local welcome
function ns.ShowWelcome()
	if welcome then welcome:Show(); return end
	local w = CreateFrame("Frame", "DungeonSwitchWelcome", UIParent, "BackdropTemplate")
	w:SetSize(440, 500)
	w:SetPoint("CENTER")
	w:SetFrameStrata("DIALOG")
	w:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	w:EnableMouse(true)
	w:SetMovable(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", w.StartMoving)
	w:SetScript("OnDragStop", w.StopMovingOrSizing)

	local title = w:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -22)
	title:SetText("Welcome to DungeonSwitch")

	local text = w:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 24, -52)
	text:SetPoint("RIGHT", w, "RIGHT", -24, 0)
	text:SetJustifyH("LEFT")
	text:SetText("Tick the addons you don't need inside dungeons and raids. "
		.. "When you enter one, DungeonSwitch offers to turn them off (with a UI reload), "
		.. "and turns them back on when you leave.\n\n"
		.. "You can change this list any time: /ds config or right-click the minimap key.")

	local head = w:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	head:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
	head:SetText("Turn off in Dungeon mode:")

	ns.AddonList(w, head, -40, 56)

	local done = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
	done:SetSize(120, 24)
	done:SetPoint("BOTTOM", 0, 20)
	done:SetText("Done")
	done:SetScript("OnClick", function() w:Hide() end)

	w:SetScript("OnHide", function()
		db.welcomed = true
		local n = 0
		for _, on in pairs(db.list) do if on then n = n + 1 end end
		Print(n .. " addon(s) on your dungeon list. /ds config to change it.")
	end)
	welcome = w
end

local function RefreshPanel()
	BuildPanel()
	panel.modeText:SetText(me .. ": " .. ModeName(cdb.mode) .. " mode")
	panel.switchButton:SetText("Switch to " .. ModeName(Other()))
	panel.popupBox:SetChecked(db.popup)
	panel.minimapBox:SetChecked(not db.minimap.hide)
	for _, cb in ipairs(panel.boxes) do cb:SetChecked(db.list[cb.addon] and true or false) end
end

panel:SetScript("OnShow", RefreshPanel)

local function RegisterPanel()
	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, "DungeonSwitch")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function ns.OpenSettings()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_DUNGEONSWITCH1 = "/ds"
SLASH_DUNGEONSWITCH2 = "/dungeonswitch"
SlashCmdList.DUNGEONSWITCH = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "config" or msg == "settings" or msg == "options" then
		ns.OpenSettings()
	elseif msg == "status" then
		Print(me .. " is in " .. ModeName(cdb.mode) .. " mode.")
		if cdb.mode == "dungeon" then Print("Turned off: " .. Names(cdb.disabled)) end
		Print("Dungeon list: " .. Names(ToDisable()))
	elseif msg == "minimap" then
		db.minimap.hide = not db.minimap.hide
		ns.UpdateButton()
		Print("minimap button " .. (db.minimap.hide and "hidden" or "shown") .. ".")
	elseif msg == "" then
		ns.AskSwitch()
	else
		Print("/ds — switch mode,  /ds config — settings,  /ds status,  /ds minimap")
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		self:UnregisterEvent("ADDON_LOADED")
		me = UnitName("player")

		DungeonSwitchDB = DungeonSwitchDB or {}
		db = DungeonSwitchDB
		if db.list == nil then
			db.list = {} -- first install: the welcome screen asks what to add
		elseif db.welcomed == nil then
			db.welcomed = true -- set up before the welcome screen existed
		end
		if db.popup == nil then db.popup = true end
		db.minimap = db.minimap or { angle = 200 }

		DungeonSwitchCharDB = DungeonSwitchCharDB or {}
		cdb = DungeonSwitchCharDB
		cdb.mode = cdb.mode or "normal"
		cdb.disabled = cdb.disabled or {}

		RegisterPanel()
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PLAYER_UNGHOST")
	elseif event == "PLAYER_ENTERING_WORLD" then
		ns.UpdateButton()
		C_Timer.After(3, function()
			if not db.welcomed and not InCombatLockdown() then
				ns.ShowWelcome()
			else
				Check()
			end
		end)
	elseif event == "PLAYER_UNGHOST" then
		C_Timer.After(2, Check)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if waitCombat then
			waitCombat = false
			C_Timer.After(1, Check)
		end
	end
end)
