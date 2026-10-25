local _, ns = ...

-- Rings: one button (the hub) that fans its slots out round it. Action Ring's rings
-- (copied: Ring.lua there), their buttons docked round the spheres instead:
--   * action rings: one of Blizzard's action bars (3-8), 12 slots
--   * the game menu ring: Blizzard's menu buttons (Character, Spellbook, Guild, ...), each slot
--     a secure click on Blizzard's own button; the game menu's slot holds Blizzard's button
--     itself (R.NATIVE)
--   * the bags ring: its hub occupies the last upper row position; Blizzard's own bag buttons
--     (backpack, bags, keyring) occupy its fan: click
--     one to open it, drop a bag on one to swap it; right-click its hub for the backpack
--   * spell fans (Spells.lua): a group of spells (a Paladin's Seals, Blessings, Auras or Druid Forms), over the
--     action slot that holds the group's macro (taking its key), or docked by a sphere
-- A docked hub sits round a sphere at an angle (db.rings[id].dock = { side, angle }); drag it
-- round it or over to the other sphere. Its slots open in an arc round its sphere, on its side
-- and above it, turned until they're all on the screen and above the action bar frame.
--
-- Everything that must work in combat is secure. Hubs and slots are SecureActionButtonTemplate
-- buttons; each ring is a SecureHandlerShowHideTemplate frame whose snippets (Blizzard's
-- restricted environment) open it, close the other rings, bind Esc and the number keys while
-- it's open, close it after a slot fired and remember that slot for the hub's right-click.
-- Addon code only sets attributes and positions, out of combat. Looks are on button.art and
-- button.mini (Art.lua).

local A = ns.Art
local R = {}
ns.Ring = R

R.KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }
-- Blizzard's action bars by their number -> the page of slots they show (Action Bar 3 is
-- MultiBarBottomRight, page 5, slots 49-60)
R.BAR_PAGE = { [1] = 1, [2] = 6, [3] = 5, [4] = 3, [5] = 4, [6] = 13, [7] = 14, [8] = 15 }
-- Blizzard's menu buttons in their order, less Housing, the Adventure Guide and the Shop
-- (the client shows them, Forever has none), and the minimap header's calendar, tracking and
-- add-on compartment (its header is out of sight with the minimap in a sphere, the player's call)
R.MICRO = ns.Retail and ns.Retail.MicroButtons and ns.Retail.MicroButtons() or {
    "CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton", "TalentMicroButton",
    "LegacyMicroButton", "QuestLogMicroButton", "GuildMicroButton", "LFDMicroButton",
    "CollectionsMicroButton", "GameTimeFrame", "SpheresDiel", "MinimapTracking", "AddonCompartmentFrame",
    "HelpMicroButton", "MainMenuMicroButton" }
-- Blizzard's bag buttons, backpack first
R.BAGS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }
-- Blizzard's game menu button opens the menu only with the mouse really over it, and opening
-- it from addon code would build its buttons (Log Out, Exit) tainted: its slot holds the button
-- itself. So the menu's gear can't open the Game Menu on right-click: a click passed on to the
-- button does nothing (0.5.343), and the button over the gear (0.5.344) lost the fan in combat,
-- where the secure handlers skip a wrap on an unprotected frame (IsWrapEligible). The bags ring's slots hold Blizzard's bag buttons the same way, and the menu ring's
-- the minimap header's: "round" ones on a minimap button's disc at their own size; "menu" ones
-- (dropdowns) too, but their menu closes when they hide (Blizzard_Menu checks its owner), so
-- the ring folds when the menu closes, not on the click.
R.NATIVE = { MainMenuMicroButton = "micro", GameTimeFrame = "round", MinimapTracking = "menu",
    AddonCompartmentFrame = "menu", SpheresDiel = "show" }
-- on a minimap button's disc, at their own size ("show": ours, nothing to click)
local function onDisc(kind) return kind == "round" or kind == "menu" or kind == "show" end
-- The tracking and add-on buttons draw a bronze square round their logo (Forever's minimap header
-- art): on a disc inside our brass ring, a frame in a frame (0.5.432, the player's: "frames in their
-- logo, which doesn't look nice remove their inner frames"). A square mask keeps the art inside
-- the square's inner edge (left, top, right, bottom insets in the art's own pixels, measured on
-- ui-hud-minimap-tracking-button and -addon-indicator), and the button 1.25 times its size fills
-- the disc as the calendar does. The calendar keeps its frame: its icon covers most of it.
R.FRAME_CUT = { MinimapTracking = { 4, 4.5, 4, 4.5 }, AddonCompartmentFrame = { 5.5, 5, 5, 6 } }
R.FRAME_CUT_SCALE = 1.25
-- Day or night (0.5.433, the player's: "The sun/moon sphere should be in the game menu ring, like
-- others, for example the addons button"; 0.5.432 put it on the map sphere's rim). Forever's minimap
-- shows it on its rim (Blizzard_Minimap Camelot `Diel.lua`: `MinimapCluster.DielFrame`, out of sight
-- with the cluster; its atlases, `DIEL_CYCLE_CHANGED` with the answer, `C_DateAndTime.IsDayTime`).
-- Ours is the icon alone, the size of a minimap button's (Art.lua), a native of the menu ring's on
-- its disc and brass ring, in a hidden frame while not in the ring; none where the game can't say.
-- No click; hovered, Blizzard's clock tooltip: realm (server) and local time, again each second.
local DIEL = { day = "UI-HUD-Minimap-DayCycle", night = "UI-HUD-Minimap-NightCycle" }
local diel -- the button; false: the game has no answer

-- `isDay` from the game's event, else asked
function R.UpdateDiel(isDay)
    if not diel then return end
    if isDay == nil then
        local C = C_DateAndTime
        isDay = C and A.call(C.IsDayTime)
    end
    local atlas = isDay == true and DIEL.day or isDay == false and DIEL.night or nil
    if not (atlas and A.AtlasOK(atlas)) then
        diel:Hide()
        return
    end
    if diel.atlas ~= atlas then
        diel.atlas = atlas
        diel.icon:SetAtlas(atlas)
    end
    diel:Show()
end

local function clockLine(label, time)
    local n, h = NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR
    GameTooltip:AddDoubleLine(label, time, n and n.r or 1, n and n.g or 0.82, n and n.b or 0,
        h and h.r or 1, h and h.g or 1, h and h.b or 1)
end
-- Blizzard's clock tooltip (GameTime_UpdateTooltip's lines: realm time, then yours, in your 12 or
-- 24 hour setting); the server's hours and minutes alone where the game has no such helpers
local function dielTooltip(self)
    if not GameTooltip then return end
    if GameTooltip:IsOwned(self) then GameTooltip:ClearLines()
    else GameTooltip:SetOwner(self, A.TooltipAnchor(self)) end
    GameTooltip:AddLine(TIMEMANAGER_TOOLTIP_TITLE or "Time", 1, 1, 1)
    local realm = GameTime_GetGameTime and A.call(GameTime_GetGameTime, true)
    if type(realm) ~= "string" then
        local hour, minute = A.call(GetGameTime)
        realm = type(hour) == "number" and type(minute) == "number" and not A.secret(hour)
            and not A.secret(minute) and string.format("%02d:%02d", hour, minute) or "?"
    end
    clockLine(TIMEMANAGER_TOOLTIP_REALMTIME or "Server time:", realm)
    local here = GameTime_GetLocalTime and A.call(GameTime_GetLocalTime, true)
    if type(here) == "string" then clockLine(TIMEMANAGER_TOOLTIP_LOCALTIME or "Local time:", here) end
    GameTooltip:Show()
end
local function dielTick(self, elapsed)
    self.tipElapsed = (self.tipElapsed or 0) + (elapsed or 0)
    if self.tipElapsed < 1 then return end
    self.tipElapsed = 0
    if GameTooltip and GameTooltip:IsOwned(self) then dielTooltip(self) end
end

local function dielButton()
    if diel ~= nil then return diel or nil end
    local C = C_DateAndTime
    if not (C and C.IsDayTime) then
        diel = false
        return nil
    end
    local holder = CreateFrame("Frame")
    holder:Hide()
    diel = CreateFrame("Frame", nil, holder)
    local size = 22.5 * A.MINIMAP_SIZE / 31
    diel:SetSize(size, size)
    diel:EnableMouse(true)
    diel.icon = diel:CreateTexture(nil, "ARTWORK")
    diel.icon:SetAllPoints()
    if diel.CreateMaskTexture then
        local mask = diel:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(diel.icon)
        diel.icon:AddMaskTexture(mask)
    end
    diel:SetScript("OnEnter", function(self)
        self.tipElapsed = 0
        dielTooltip(self)
        self:SetScript("OnUpdate", dielTick)
    end)
    diel:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    -- DIEL_CYCLE_CHANGED is supplied by Forever, not Retail.
    pcall(diel.RegisterEvent, diel, "DIEL_CYCLE_CHANGED")
    pcall(diel.RegisterEvent, diel, "PLAYER_ENTERING_WORLD")
    diel:SetScript("OnEvent", A.Timed("day and night", function(_, event, isDay)
        if event == "DIEL_CYCLE_CHANGED" and type(isDay) == "boolean" then R.UpdateDiel(isDay)
        else R.UpdateDiel() end
    end, true))
    R.UpdateDiel()
    return diel
end

-- the ones without a global name
local UNNAMED = {
    MinimapTracking = function()
        local c = MinimapCluster
        return c and c.Tracking and c.Tracking.Button
    end,
    SpheresDiel = dielButton,
}
function R.Micro(name)
    local retail = ns.Retail
    local frame = retail and retail.Micro and retail.Micro(name)
    if frame then return frame end
    if UNNAMED[name] then return UNNAMED[name]() end
    return _G[name]
end

R.DEFS = {}
-- First places round the spheres (0 = right, counter-clockwise), over their rims: over each
-- one's top, inner side first (left 64-148, right 116-32, 28 degrees apart; the inner ones just
-- clear the frame's corners), then the hidden ones over the statues.
local BAR_DOCK = { [3] = { "left", 92 }, [4] = { "right", 60 }, [5] = { "right", 32 }, [6] = { "left", 176 },
    [7] = { "right", 4 }, [8] = { "left", 204 } }
for bar = 3, 8 do
    R.DEFS[#R.DEFS + 1] = { id = "bar" .. bar, kind = "action", bar = bar, frame = "Bar" .. bar, label = "Action Bar " .. bar,
        dock = BAR_DOCK[bar] }
end
R.DEFS[#R.DEFS + 1] = { id = "menu", kind = "menu", frame = "Menu", label = "Game Menu", dock = { "right", 88 } }
R.DEFS[#R.DEFS + 1] = { id = "bags", kind = "bags", frame = "Bags", label = "Bags" }
do -- spell fans, for their class only (CreateAll)
    local classes = {}
    for class in pairs(ns.Spells.GROUPS) do classes[#classes + 1] = class end
    table.sort(classes)
    for _, class in ipairs(classes) do
        for _, g in ipairs(ns.Spells.GROUPS[class]) do
            R.DEFS[#R.DEFS + 1] = { id = g.id, kind = "spells", class = class, frame = g.frame, label = g.label,
                macro = g.macro, legacy = g.legacy, group = g, dock = g.dock }
        end
    end
end

local RING_ICON = "Interface\\Icons\\INV_Jewelry_Ring_14"
local MENU_ICON = "Interface\\Icons\\INV_Misc_Gear_01" -- where Blizzard's own isn't there
-- The Game Menu hub shows the original button's question mark (0.5.426, the player's: "could be
-- the question mark as the original, may feel more accurate"; a gear before): the atlas on
-- Blizzard's MainMenuMicroButton, this one if it has none. MENU_GLYPH: its height on the hub.
local MENU_ATLAS, MENU_GLYPH = "UI-HUD-MicroMenu-GameMenu-Up", 22 -- 26 px at the player's 1.2 HUD
local function menuAtlas()
    local b = MainMenuMicroButton
    local normal = b and b.GetNormalTexture and b:GetNormalTexture()
    local atlas = normal and normal.GetAtlas and normal:GetAtlas()
    if type(atlas) == "string" and A.AtlasOK(atlas) then return atlas end
    if A.AtlasOK(MENU_ATLAS) then return MENU_ATLAS end
end
local MENU_SIZE = 46 -- a modest increase over Blizzard's 32x40 micro buttons
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local FAN_TIME = 0.14

local VISIBILITY = "[vehicleui][overridebar][possessbar][petbattle] hide; show"
local LINK = { 1, 0.82, 0.35 }

local rings, list = {}, {}
local pending = false
local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() end

function R.Get(id) return rings[id] end
function R.List() return list end
function R.HubName(def) return "Spheres" .. def.frame .. "Hub" end
function R.ToggleBinding(def) return "CLICK " .. R.HubName(def) .. ":LeftButton" end
function R.CastBinding(def) return "CLICK " .. R.HubName(def) .. ":RightButton" end

local function hubKey(def)
    if not GetBindingKey then return nil end
    if def.kind == "bags" then
        return GetBindingKey("TOGGLEBACKPACK") or GetBindingKey(R.ToggleBinding(def))
    end
    return GetBindingKey(R.ToggleBinding(def))
end

local Ring = {}
Ring.__index = Ring
local NO_SLOTS = {}
local MENU_ALERTS = {
    { "CollectionsMicroButtonAlert", { CollectionsMicroButton = true } },
    { "TalentMicroButtonAlert", { TalentMicroButton = true, PlayerSpellsMicroButton = true } },
    { "EJMicroButtonAlert", { EJMicroButton = true } },
}
local placingMenuAlert = false

-- Blizzard parents the micro-button callouts to MicroMenuContainer, which Spheres stows.
-- Let those callouts live independently and follow their button in the menu fan. When the
-- fan is closed, keep the notification attached to its visible hub instead of the hidden bar.
local function updateMenuAlerts(o)
    if not (o and o.def.kind == "menu" and o.hub) then return end
    local fanOpen = o.ring and o.ring:IsShown()
    local function slotAnchor(target)
        if fanOpen and target then
            local targetName = target.GetName and target:GetName()
            for i, name in ipairs(R.MICRO) do
                if (name == targetName or R.Micro(name) == target) and o.slots[i] then
                    return o.slots[i].art or o.slots[i]
                end
            end
        end
        return o.hub
    end

    -- Forever's older micro menu uses named alert frames. Retail's current menu instead
    -- creates a HelpTip targeted at the Blizzard button passed to HelpTip:Show.
    for _, pair in ipairs(MENU_ALERTS) do
        local alert, buttonNames = _G[pair[1]], pair[2]
        if alert and alert.ClearAllPoints and alert.SetPoint then
            local anchor = o.hub
            if fanOpen then
                for i, name in ipairs(R.MICRO) do
                    if buttonNames[name] and o.slots[i] then anchor = o.slots[i].art or o.slots[i]; break end
                end
            end
            local point, relativeTo, relativePoint, x, y
            if alert.GetPoint then point, relativeTo, relativePoint, x, y = alert:GetPoint(1) end
            local moved = alert:GetParent() ~= UIParent or point ~= "BOTTOM" or relativeTo ~= anchor
                or relativePoint ~= "TOP" or x ~= 0 or y ~= 8
                or (alert.GetNumPoints and alert:GetNumPoints() ~= 1)
            if moved then
                placingMenuAlert = true
                if alert:GetParent() ~= UIParent then alert:SetParent(UIParent) end
                alert:ClearAllPoints()
                alert:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
                if alert.SetFrameStrata then alert:SetFrameStrata("DIALOG") end
                placingMenuAlert = false
            end
            if not alert.spheresPositionHooked and hooksecurefunc then
                alert.spheresPositionHooked = true
                local reanchor = function()
                    if not placingMenuAlert then updateMenuAlerts(o) end
                end
                hooksecurefunc(alert, "SetPoint", reanchor)
                if alert.SetAllPoints then hooksecurefunc(alert, "SetAllPoints", reanchor) end
                hooksecurefunc(alert, "SetParent", reanchor)
            end
        end
    end

    local helpTip = HelpTip
    local pool = helpTip and helpTip.framePool
    if pool and pool.EnumerateActive then
        for tip in pool:EnumerateActive() do
            local info = tip.info
            if info and info.system == "MicroButtons" then
                local anchor = slotAnchor(info.callbackArg or tip.relativeRegion)
                if tip.relativeRegion ~= anchor then
                    tip.relativeRegion = anchor
                    -- HelpTip's Layout only sizes its text. AnchorAndRotate caches the
                    -- edge/alignment, so invalidate that cache when only its target changes.
                    tip.appliedTargetPoint, tip.appliedAlignment = nil, nil
                    if tip.AnchorAndRotate then tip:AnchorAndRotate() end
                end
            end
        end
    end
end

function Ring:Config() return ns.db.rings[self.id] end
function Ring:FirstSlot() return ((R.BAR_PAGE[self.def.bar] or 5) - 1) * 12 + 1 end
function Ring:Dock()
    if self.def.kind == "menu" then return "right", 88 end -- the menu lives in the right frame well
    local d = self:Config().dock or self.def.dock or { "left", 270 }
    return d[1], d[2]
end
local function natives(def)
    if def.kind == "bags" then return R.BAGS end
    if def.kind == "menu" then return R.MICRO end
end

-------------------------------------------------------------------------------
-- Restricted snippets. owner = the ring; self = the button clicked. (Action Ring's.)
-------------------------------------------------------------------------------
local HUB_CLICK = [[
    if button == "RightButton" then
        if owner:IsShown() then owner:Hide() end
        return
    end
    if owner:IsShown() then
        owner:Hide()
        return false
    end
    for i = 1, owner:GetAttribute("peers") or 0 do
        local p = owner:GetFrameRef("peer" .. i)
        if p and p:IsShown() then p:Hide() end
    end
    owner:Show()
    return false
]]
-- A spell fan's button: a click (released) or Shift opens the fan; otherwise (its key, a
-- right-click) it casts the current pick (type2 spell), closing the fan if open.
local SPELL_HUB = [[
    if button == "LeftButton" or (IsShiftKeyDown() and not self:GetAttribute("keyshift")) then
        if down then return false end
        if owner:IsShown() then
            owner:Hide()
            return false
        end
        for i = 1, owner:GetAttribute("peers") or 0 do
            local p = owner:GetFrameRef("peer" .. i)
            if p and p:IsShown() then p:Hide() end
        end
        owner:Show()
        return false
    end
    if owner:IsShown() then owner:Hide() end
    return nil, "cast"
]]
-- After its cast: a one-shot spell armed for the key (revert) gives way to the pick again, on
-- the release (keys cast on the press, the mouse on the release).
local SPELL_HUB_POST = [[
    if message == "cast" and not down then
        local back = self:GetAttribute("revert")
        if back then
            self:SetAttribute("spell", back)
            self:SetAttribute("revert", nil)
        end
    end
]]
local SPELL_POST = [[
    owner:Hide()
    if not self:GetAttribute("oneshot") then
        local hub = owner:GetFrameRef("hub")
        hub:SetAttribute("spell", self:GetAttribute("spell"))
        hub:SetAttribute("revert", nil)
    end
]]
local SLOT_PRE = [[ return nil, true ]]
local NATIVE_POST = [[ owner:Hide() ]]
local SLOT_POST = [[
    owner:Hide()
    local a = self:GetAttribute("action")
    if a then owner:GetFrameRef("hub"):SetAttribute("action2", a) end
]]
local RING_SHOW = [[
    self:ClearBindings()
    self:SetBindingClick(true, "ESCAPE", self:GetFrameRef("hub"), "LeftButton")
    if self:GetAttribute("numberkeys") then
        for i = 1, self:GetAttribute("count") or 0 do
            local b = self:GetFrameRef("slot" .. i)
            local key = self:GetAttribute("key" .. i)
            if key and b and b:IsShown() and not b:GetAttribute("nokey") then self:SetBindingClick(true, key, b) end
        end
    end
]]
local RING_HIDE = [[ self:ClearBindings() ]]
R.SNIPPETS = { hub = HUB_CLICK, slotPre = SLOT_PRE, slotPost = SLOT_POST, nativePost = NATIVE_POST, show = RING_SHOW, hide = RING_HIDE,
    spellHub = SPELL_HUB, spellHubPost = SPELL_HUB_POST, spellPost = SPELL_POST }

-------------------------------------------------------------------------------
-- Building (once, out of combat)
-------------------------------------------------------------------------------
local ticker

local function makeLink(parent, slot)
    local ok, line = pcall(parent.CreateLine, parent, nil, "BACKGROUND")
    if not (ok and line) then return nil end
    line:SetTexture("Interface\\Buttons\\WHITE8x8")
    pcall(line.SetThickness, line, 2)
    pcall(line.SetBlendMode, line, "ADD")
    if CreateColor and line.SetGradient then
        pcall(line.SetGradient, line, "HORIZONTAL", CreateColor(LINK[1], LINK[2], LINK[3], 0.5),
            CreateColor(LINK[1], LINK[2], LINK[3], 0.12))
    end
    line:SetEndPoint("CENTER", slot)
    return line
end

function Ring:HubSlot()
    local first = self:FirstSlot()
    local last = self:Config().lastSlot
    if last and last >= first and last < first + 12 and A.HasAction(last) then return last end
    for i = 0, 11 do if A.HasAction(first + i) then return first + i end end
end

local function addPerformance()
    local _, _, home, world = GetNetStats()
    local fps = GetFramerate()
    if not (home and world and fps) or A.secret(home) or A.secret(world) or A.secret(fps) then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format(MAINMENUBAR_LATENCY_LABEL or "Latency:\n%.0f ms (home)\n%.0f ms (world)", home, world), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format(MAINMENUBAR_FPS_LABEL or "Framerate: %.0f fps", fps), 1, 1, 1)
end

local MOVE_TIP = "Drag: move round the sphere, or over to the other one"

function Ring:SpellTooltip()
    local cur, key = self.armed or self.current, self.keys and self.keys[1]
    if not (cur and GameTooltip.SetSpellByID and GameTooltip:SetSpellByID(cur.id) ~= false) then
        GameTooltip:SetText(cur and cur.name or self.def.label, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    local once = self.armed and self.current and (" once, then " .. self.current.name) or ""
    GameTooltip:AddLine((key and (A.KeyText(key) .. " or right-click") or "Right-click") .. ": cast it" .. once, 1, 0.82, 0, true)
    GameTooltip:AddLine("Click" .. (key and (" or Shift-" .. A.KeyText(key)) or "") .. ": pick from your " .. self.def.label,
        1, 0.82, 0, true)
    if self.docked and not ns.db.locked then GameTooltip:AddLine(MOVE_TIP, 0.6, 0.6, 0.6) end
end

function Ring:HubTooltip()
    local def = self.def
    if def.kind == "spells" then return self:SpellTooltip() end
    GameTooltip:SetText(def.label .. " Ring", 1, 1, 1)
    local key = hubKey(def)
    local open = def.kind == "menu" and "Character, Spellbook, Guild and the rest"
        or def.kind == "bags" and "your backpack and bags (drop a bag on one to swap it)" or (def.label .. "'s slots")
    if def.kind == "bags" then
        GameTooltip:AddLine("Click: open your bag fan", 1, 0.82, 0, true)
        if key then GameTooltip:AddLine(A.KeyText(key) .. ": open your backpack", 1, 0.82, 0, true) end
    else
        GameTooltip:AddLine("Click" .. (key and (" or " .. A.KeyText(key)) or "") .. ": " .. open .. " around it", 1, 0.82, 0, true)
    end
    if def.kind == "action" and self:HubSlot() then
        GameTooltip:AddLine("Right-click: the last one used, again", 1, 0.82, 0, true)
    elseif def.kind == "bags" then
        GameTooltip:AddLine("Right-click: open your backpack", 1, 0.82, 0, true)
    end
    if def.kind ~= "bags" and not ns.db.locked then GameTooltip:AddLine(MOVE_TIP, 0.6, 0.6, 0.6) end
    if def.kind == "menu" and GetNetStats and GetFramerate then addPerformance() end
end

local function showHubTooltip(o, hub)
    if o.def.kind == "menu" and MainMenuBarPerformanceBarFrame_OnEnter and MainMenuMicroButton then
        hub.tooltipText = MicroButtonTooltipText and MicroButtonTooltipText(MAINMENU_BUTTON, "TOGGLEGAMEMENU")
            or MainMenuMicroButton.tooltipText
        hub.newbieText = MainMenuMicroButton.newbieText
        MainMenuBarPerformanceBarFrame_OnEnter(hub)
        return
    end
    GameTooltip:SetOwner(hub, A.TooltipAnchor(hub))
    o:HubTooltip()
    GameTooltip:Show()
end

-- Match Blizzard's Game Menu performance bar: use the slower of home and world latency.
function Ring:UpdateMenuLatency()
    if not GetNetStats then return end
    local _, _, home, world = GetNetStats()
    if A.secret(home) or A.secret(world) or type(home) ~= "number" or type(world) ~= "number" then return end
    local latency = math.max(home, world)
    local border = self.hub.mini.border
    if latency > 600 then border:SetVertexColor(1, 0, 0)
    elseif latency > 300 then border:SetVertexColor(1, 1, 0)
    else border:SetVertexColor(0, 1, 0) end
end

function Ring:Build()
    local def, pre = self.def, "Spheres" .. self.def.frame
    local spells = def.kind == "spells"
    local hub = CreateFrame("Button", pre .. "Hub", UIParent, "SecureActionButtonTemplate")
    hub:SetFrameStrata("MEDIUM")
    hub:SetFrameLevel(40)
    if spells then
        hub:RegisterForClicks("AnyUp", "AnyDown") -- its key casts on press, like Blizzard's
        hub:SetAttribute("type2", "spell")
    else
        hub:RegisterForClicks("AnyUp")         -- act on release: a ring closes only after a slot fired
        hub:SetAttribute("useOnKeyDown", false)
    end
    if def.kind == "action" then hub:SetAttribute("type2", "action") end -- right-click: the last slot used
    if def.kind == "bags" then
        -- The sphere's bag icon opens Blizzard's backpack directly on right-click.
        -- A secure click also works in combat; the left-click still opens the fan.
        -- Not the menu's gear for the Game Menu: see R.NATIVE.
        hub:SetAttribute("type2", "click")
        hub:SetAttribute("clickbutton2", R.Micro(R.BAGS[1]))
    end
    hub:RegisterForDrag("LeftButton")
    A.BuildAction(hub)
    A.BuildMinimapButton(hub, A.HUB_SIZE)
    hub:SetScript("OnDragStart", function(b)
        if self.docked then
            if def.kind ~= "menu" and def.kind ~= "bags" and not ns.db.locked and not inCombat() then self:DockDrag(true) end
        elseif spells and (not A.BarsLocked() or IsModifiedClick("PICKUPACTION")) then
            PickupAction(b:GetAttribute("action")) -- a fan over a slot: picked up like the slot
            R.LayoutSoon()
        end
    end)
    hub:SetScript("OnDragStop", function()
        if self.dragging then
            self:DockDrag(false)
            R.Layout()
        end
    end)
    if spells then
        hub:SetScript("OnReceiveDrag", function(b)
            if self.docked then return end
            PlaceAction(b:GetAttribute("action"))
            R.LayoutSoon()
        end)
    end
    hub:HookScript("OnEnter", function(b) if GameTooltip then showHubTooltip(self, b) end end)
    hub:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if def.kind == "menu" then
        local since = 0
        for _, pair in ipairs(MENU_ALERTS) do
            local alert = _G[pair[1]]
            if alert and alert.HookScript then
                alert:HookScript("OnShow", function() updateMenuAlerts(self) end)
            end
        end
        hub:HookScript("OnUpdate", A.Timed("menu latency", function(b, elapsed)
            since = since + (elapsed or 0)
            if since < 1 then return end
            since = 0
            updateMenuAlerts(self)
            self:UpdateMenuLatency()
            if GameTooltip and GameTooltip:IsOwned(b) then showHubTooltip(self, b) end
        end))
    end

    local ring = CreateFrame("Frame", pre .. "Ring", hub, "SecureHandlerShowHideTemplate")
    ring:SetFrameStrata("HIGH")
    ring:SetSize(1, 1)
    ring:SetPoint("CENTER", hub, "CENTER")
    ring:Hide()
    SecureHandlerSetFrameRef(ring, "hub", hub)
    ring:SetAttribute("_onshow", RING_SHOW)
    ring:SetAttribute("_onhide", RING_HIDE)
    for i, key in ipairs(R.KEYS) do ring:SetAttribute("key" .. i, key) end
    if spells then
        SecureHandlerWrapScript(hub, "OnClick", ring, SPELL_HUB, SPELL_HUB_POST)
        hub:SetScript("PostClick", function(b)
            if self.armed and b:GetAttribute("spell") ~= self.armed.name then self.armed = nil end
            R.UpdateAll()
        end)
        local links = CreateFrame("Frame", nil, ring)
        links:SetAllPoints()
        local ag = links:CreateAnimationGroup()
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(0)
        fade:SetToAlpha(1)
        fade:SetStartDelay(FAN_TIME * 0.7)
        fade:SetDuration(0.18)
        if ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
        links.fade = ag
        ring.links = links
    else
        SecureHandlerWrapScript(hub, "OnClick", ring, HUB_CLICK)
    end

    local names = natives(def)
    local n = names and #names or spells and #def.group.spells or 12
    for i = 1, n do
        local b = CreateFrame("Button", pre .. "Slot" .. i, ring, "SecureActionButtonTemplate")
        b.index = i
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("useOnKeyDown", false)
        local nativeName = names and names[i]
        local found = nativeName and R.Micro(nativeName)
        local native = found and (def.kind == "bags" or R.NATIVE[nativeName])
        if def.kind == "action" then
            b:SetAttribute("type", "action")
            A.BuildAction(b)
            A.SetupDrag(b, function() R.UpdateAll() end)
            A.ActionTooltip(b, function(s) return "Empty slot " .. s.index .. " of " .. def.label end)
        elseif spells then
            b:SetAttribute("type", "spell")
            A.BuildAction(b)
            b.link = makeLink(ring.links, b)
            b:HookScript("OnEnter", function(s)
                if not (GameTooltip and s.entry) then return end
                GameTooltip:SetOwner(s, A.TooltipAnchor(s))
                if not (GameTooltip.SetSpellByID and GameTooltip:SetSpellByID(s.entry.id) ~= false) then
                    GameTooltip:SetText(s.entry.name, 1, 1, 1)
                end
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        elseif native then
            -- a place for Blizzard's own button: no action, no key, no art of ours (a round
            -- one: a minimap button's disc under it)
            b:SetAttribute("nokey", true)
            b:EnableMouse(false)
            b.native = found
            b.nativeKind = def.kind == "menu" and R.NATIVE[nativeName] or nil
            b.frameCut = def.kind == "menu" and R.FRAME_CUT[nativeName] or nil
            b.art = CreateFrame("Frame", nil, b)
            b.art:SetAllPoints()
            b.art:EnableMouse(false)
            if onDisc(b.nativeKind) then A.BuildMinimapButton(b.art):Show() end
            if b.nativeKind == "show" then
                b.art.mini.hover:SetAlpha(0) -- Blizzard's has no hover look either
            elseif b.nativeKind == "menu" then
                if type(found.OnMenuClosed) == "function" and hooksecurefunc then
                    hooksecurefunc(found, "OnMenuClosed", function()
                        if not inCombat() and ring:IsShown() and found:GetParent() == b.art then ring:Hide() end
                    end)
                end
            else
                SecureHandlerWrapScript(b.native, "OnClick", ring, SLOT_PRE, NATIVE_POST)
                -- The wrap's snippets run only for a frame with a secure handle (SecureHandlers.lua:
                -- GetFrameHandle(self, true)), and Blizzard's calendar, game menu and bag buttons
                -- aren't protected: the ring stayed open (0.5.433, the player's: "it doesn't do the
                -- same for calendar and game menu"). Out of combat their click folds it from here.
                found:HookScript("OnClick", function()
                    if not inCombat() and ring:IsShown() and found:GetParent() == b.art then ring:Hide() end
                end)
            end
        elseif def.kind == "menu" then
            b:SetAttribute("type", "click") -- a secure click on Blizzard's own menu button
            A.BuildMenu(b)
            b:HookScript("OnEnter", function(s)
                local micro = s.micro
                if not (GameTooltip and micro) then return end
                GameTooltip:SetOwner(s, A.TooltipAnchor(s))
                GameTooltip:SetText(micro.tooltipText or micro.newbieText or micro:GetName(), 1, 1, 1)
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        else
            b.art = CreateFrame("Frame", nil, b) -- a bag slot this client doesn't have
            b.missing = true
        end
        SecureHandlerSetFrameRef(ring, "slot" .. i, b)
        if not native and not b.missing then
            SecureHandlerWrapScript(b, "OnClick", ring, SLOT_PRE, spells and SPELL_POST or SLOT_POST)
        end
        b:SetScript("PostClick", function(s)
            if def.kind == "action" then self:Config().lastSlot = s:GetAttribute("action") end
            if spells and s.entry and not s.entry.oneShot then
                self:Config().current, self.current, self.armed = s.entry.key, s.entry, nil
            end
            R.UpdateAll()
        end)
        self.slots[i] = b
    end
    ring:SetAttribute("count", n)
    ring:HookScript("OnShow", function()
        self:Update()
        self:FanOut()
        updateMenuAlerts(self)
        ticker:Show()
    end)
    ring:HookScript("OnHide", function()
        self:Update()
        updateMenuAlerts(self)
        local any = false
        for _, o in ipairs(list) do if o.ring:IsShown() then any = true end end
        if not any then ticker:Hide() end
    end)
    if def.kind == "bags" then
        -- The secure native click handler above closes the fan even in combat. Also
        -- follow Blizzard's bag-open event so opening a bag elsewhere dismisses it.
        pcall(ring.RegisterEvent, ring, "BAG_OPEN")
        ring:SetScript("OnEvent", function(frame)
            if not inCombat() and frame:IsShown() then frame:Hide() end
        end)
    end
    self.hub, self.ring = hub, ring
    if def.kind == "menu" then updateMenuAlerts(self) end
end

function R.CreateAll()
    if #list > 0 then return end
    ticker = CreateFrame("Frame", nil, UIParent)
    ticker:Hide()
    local since = 0
    ticker:SetScript("OnUpdate", A.Timed("open rings", function(_, elapsed)
        since = since + (elapsed or 0)
        if since >= 0.2 then since = 0; R.UpdateAll(true) end
    end))
    R.ticker = ticker
    local class = UnitClass and select(2, UnitClass("player"))
    for _, def in ipairs(R.DEFS) do
        if not def.class or def.class == class then
            local o = setmetatable({ def = def, id = def.id, slots = {} }, Ring)
            o:Build()
            rings[def.id] = o
            list[#list + 1] = o
        end
    end
    for _, o in ipairs(list) do
        local n = 0
        for _, p in ipairs(list) do
            if p ~= o then
                n = n + 1
                SecureHandlerSetFrameRef(o.ring, "peer" .. n, p.ring)
            end
        end
        o.ring:SetAttribute("peers", n)
    end
    if HelpTip and HelpTip.Show and hooksecurefunc and not R.helpTipHooked then
        R.helpTipHooked = true
        hooksecurefunc(HelpTip, "Show", function(_, _, info)
            if info and info.system == "MicroButtons" then updateMenuAlerts(rings.menu) end
        end)
    end
end

-------------------------------------------------------------------------------
-- Looks
-------------------------------------------------------------------------------
function Ring:HubIcon()
    local kind = self.def.kind
    if kind == "spells" then
        local now = self.armed or self.current
        return now and A.call(C_Spell and C_Spell.GetSpellTexture, now.id) or RING_ICON
    elseif kind == "menu" then return menuAtlas() or MENU_ICON
    elseif kind == "bags" then return BAG_ICON end
    local slot = self:HubSlot()
    return slot and A.ActionTexture(slot) or RING_ICON
end

-- `keepCooldowns`: the open ring's ticker and the game's non-cooldown events (Core.lua).
-- A closed ring paints its hub alone: its slots are painted as it opens (its OnShow), not on every
-- usable or state event while out of sight (0.5.425: the menu ring's nine buttons, your portrait
-- with them, on each one).
function Ring:Update(keepCooldowns)
    if not self:Config().shown then return end
    keepCooldowns = keepCooldowns and true or nil
    local keyed = ns.db.numberKeys
    local open = self.ring:IsShown()
    for i, b in ipairs(open and self.slots or NO_SLOTS) do
        if b:IsShown() and not b.native and not b.missing then
            local key = keyed and R.KEYS[i] or nil
            local paint = b.paint -- one per slot: an open ring repaints five times a second
            if not paint then paint = {}; b.paint = paint end
            paint.key, paint.keepCooldown = key, keepCooldowns
            if self.def.kind == "action" then A.PaintAction(b, b:GetAttribute("action"), paint)
            elseif self.def.kind == "spells" then A.PaintSpell(b, b.entry, paint)
            else A.PaintMenu(b, b.micro, key) end
        end
    end
    if self.def.kind == "bags" then
        local art = self.hub.art
        art.icon:SetTexture(BAG_ICON)
        art.icon:Show()
        art.empty:Hide()
        art.hotkey:SetText(A.KeyText(hubKey(self.def)))
        art.checked:SetShown(open)
        return
    end
    if self.docked then return A.PaintMinimapButton(self.hub.mini, self:HubIcon(), open) end
    if self.def.kind == "spells" then
        local paint = self.hubPaint
        if not paint then paint = {}; self.hubPaint = paint end
        paint.key, paint.lit, paint.keepCooldown = self.keys and self.keys[1], open, keepCooldowns
        A.PaintSpell(self.hub, self.armed or self.current, paint)
    end
end

function R.UpdateAll(keepCooldowns)
    for _, o in ipairs(list) do o:Update(keepCooldowns) end
end

function Ring:FanOut()
    local links = self.ring.links
    if links then
        links.fade:Stop()
        links:SetAlpha(0)
        links.fade:Play()
    end
    for _, b in ipairs(self.slots) do
        if b:IsShown() and b.dx then
            local a = b.art
            local ag = a.fan
            if not ag then
                ag = a:CreateAnimationGroup()
                ag.jump = ag:CreateAnimation("Translation")
                ag.jump:SetOrder(1)
                ag.jump:SetDuration(0)
                ag.move = ag:CreateAnimation("Translation")
                ag.move:SetOrder(2)
                ag.move:SetDuration(FAN_TIME)
                ag.move:SetSmoothing("OUT")
                local fade = ag:CreateAnimation("Alpha")
                fade:SetOrder(2)
                fade:SetDuration(FAN_TIME)
                fade:SetFromAlpha(0)
                fade:SetToAlpha(1)
                local grow = ag:CreateAnimation("Scale")
                grow:SetOrder(2)
                grow:SetDuration(FAN_TIME)
                if grow.SetScaleFrom then grow:SetScaleFrom(0.4, 0.4); grow:SetScaleTo(1, 1) end
                a.fan = ag
            end
            ag:Stop()
            ag.jump:SetOffset(-b.dx, -b.dy)
            ag.move:SetOffset(b.dx, b.dy)
            ag:Play()
        end
    end
end

-------------------------------------------------------------------------------
-- Blizzard's own buttons in a ring (the game menu's, the bags)
-------------------------------------------------------------------------------
local placingNative = false
local function points(f)
    local pts = {}
    for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) do pts[i] = { f:GetPoint(i) } end
    return pts
end

-- R.FRAME_CUT: a square mask over the button's art (its normal and hover textures) inside the
-- frame's inner edge, and the button scaled up; `on` false takes the mask off (its scale goes
-- back with the rest, giveBackNative).
local CUT_MASK = "Interface\\Buttons\\WHITE8X8"
local function cutFrame(b, on)
    local f, cut = b.native, b.frameCut
    local art, add = f.StateTexture, f.AddTexture
    if not (art and art.AddMaskTexture and f.CreateMaskTexture) then return end -- framed, own size
    if on then f:SetScale(R.FRAME_CUT_SCALE) end
    if on == (b.cutOn or false) then return end
    if not b.cutMask then
        local m = f:CreateMaskTexture()
        m:SetTexture(CUT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetPoint("TOPLEFT", art, "TOPLEFT", cut[1], -cut[2])
        m:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -cut[3], cut[4])
        b.cutMask = m
    end
    b.cutOn = on
    if on then
        art:AddMaskTexture(b.cutMask)
        if add and add.AddMaskTexture then add:AddMaskTexture(b.cutMask) end
    else
        art:RemoveMaskTexture(b.cutMask)
        if add and add.RemoveMaskTexture then add:RemoveMaskTexture(b.cutMask) end
    end
end

local function takeNative(b)
    local f = b.native
    placingNative = true
    if f:GetParent() ~= b.art then
        b.home, b.homePoints = f:GetParent(), points(f)
        if b.nativeKind == "micro" or b.frameCut then b.homeScale = f:GetScale() end
        if b.owner.def.kind == "bags" then
            b.homeSize = { f:GetSize() }
            b.homeIconPoints = f.icon and points(f.icon)
            b.homeIconSize = f.icon and { f.icon:GetSize() }
            b.homeMaskSize = f.SquareMask and { f.SquareMask:GetSize() }
            b.homeTrimSize = { f.normalAndPushedTextureWidth, f.normalAndPushedTextureHeight }
        end
        f:SetParent(b.art)
        if f == MainMenuMicroButton and MicroMenu and MicroMenu.MarkDirty then MicroMenu:MarkDirty() end
    end
    f:ClearAllPoints()
    if b.frameCut then
        f:SetPoint("CENTER", b.art, "CENTER", 0, 0)
        cutFrame(b, true)
    elseif onDisc(b.nativeKind) then
        f:SetPoint("CENTER", b.art, "CENTER", 0, 0) -- its own size, on the disc
    elseif b.nativeKind == "micro" then
        f:SetPoint("CENTER", b.art, "CENTER", 0, 0)
        f:SetScale(b:GetHeight() / 40)
    elseif b.owner.def.kind == "bags" then
        local size = b:GetWidth()
        f:SetSize(size, size)
        f:SetPoint("CENTER", b.art, "CENTER")
        if f.icon then
            f.icon:ClearAllPoints()
            f.icon:SetAllPoints(f)
        end
        if f.SquareMask and b.homeMaskSize and b.homeSize[1] > 0 and b.homeSize[2] > 0 then
            f.SquareMask:SetSize(b.homeMaskSize[1] * size / b.homeSize[1],
                b.homeMaskSize[2] * size / b.homeSize[2])
        end
        f.normalAndPushedTextureWidth = size * 46 / 45
        f.normalAndPushedTextureHeight = size
        if f.UpdateTextures then f:UpdateTextures() end
    else
        f:SetAllPoints(b.art)
    end
    f:SetFrameLevel(b.art:GetFrameLevel() + 2)
    if f.Show then f:Show() end
    placingNative = false
    if not b.hooked and hooksecurefunc then
        -- Blizzard lays its bag bar out again now and then: back into the ring
        b.hooked = true
        hooksecurefunc(f, "SetPoint", function()
            if not placingNative and b.owner and b.owner:Config().shown and not inCombat() then takeNative(b) end
        end)
    end
end

local function giveBackNative(b)
    local f = b.native
    if not f then return end
    local home = b.home or (f == MainMenuMicroButton and MicroMenu or BagsBar)
    if home and f:GetParent() ~= home then
        placingNative = true
        f:SetParent(home)
        if b.frameCut then cutFrame(b, false) end
        if b.homeScale then f:SetScale(b.homeScale) end
        if b.homeSize then
            f:SetSize(unpack(b.homeSize))
            if f.icon and b.homeIconPoints then
                f.icon:ClearAllPoints()
                f.icon:SetSize(unpack(b.homeIconSize))
                for _, p in ipairs(b.homeIconPoints) do f.icon:SetPoint(unpack(p)) end
            end
            if f.SquareMask and b.homeMaskSize then f.SquareMask:SetSize(unpack(b.homeMaskSize)) end
            f.normalAndPushedTextureWidth, f.normalAndPushedTextureHeight = unpack(b.homeTrimSize)
            if f.UpdateTextures then f:UpdateTextures() end
        end
        if b.homePoints and #b.homePoints > 0 then
            f:ClearAllPoints()
            for _, p in ipairs(b.homePoints) do f:SetPoint(unpack(p)) end
        end
        placingNative = false
        if home.MarkDirty then home:MarkDirty() end
        if home.Layout then pcall(home.Layout, home) end
    end
end

-------------------------------------------------------------------------------
-- Docked round a sphere
-------------------------------------------------------------------------------

function Ring:PlaceHub()
    if self.def.kind == "bags" then
        local anchor = ns.Bars.BagAnchor()
        if not anchor then return false end
        self.hub:ClearAllPoints()
        self.hub:SetPoint("CENTER", anchor, "CENTER")
        return true
    end
    if self.def.kind == "menu" then
        self.hx, self.hy = ns.Sphere.SocketPosition("right")
        if not self.hx then return false end
        local k = self.hubScale or 1 -- its points are in its own (scaled) units
        self.hub:ClearAllPoints()
        self.hub:SetPoint("CENTER", UIParent, "BOTTOMLEFT", self.hx / k, self.hy / k)
        return true
    end
    local side, angle = self:Dock()
    local cx, cy, r = ns.Sphere.Geometry(side)
    if not cx then return false end
    local a = math.rad(angle)
    self.hx, self.hy = cx + r * math.cos(a), cy + r * math.sin(a)
    local k = self.hubScale or 1
    self.hub:ClearAllPoints()
    self.hub:SetPoint("CENTER", UIParent, "BOTTOMLEFT", self.hx / k, self.hy / k)
    return true
end

-- Dragged: it follows the cursor round the nearer sphere (out of combat; it's secure).
local dragger
function Ring:DockDrag(on)
    if not dragger then
        dragger = CreateFrame("Frame", nil, UIParent)
        dragger:Hide()
        dragger:SetScript("OnUpdate", function(f)
            local o = f.ring
            if not o or inCombat() then f:Hide(); return end
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            if not (x and y) or A.secret(x) or A.secret(y) then return end
            x, y = x / s, y / s
            local side = ns.Sphere.Nearest(x, y)
            local cx, cy = ns.Sphere.Geometry(side or "left")
            if not cx then return end
            o:Config().dock = { side, math.deg(math.atan2(y - cy, x - cx)) % 360 }
            o:PlaceHub()
        end)
    end
    self.dragging = on or nil
    dragger.ring = on and self or nil
    dragger:SetShown(on and true or false)
end

-- The slots in an arc round the hub's sphere, outside the hub, on its side and up (its angle
-- mirrored to the top half, kept 30 degrees off the horizontal), turned 10 degrees at a time
-- until every slot is on the screen and above the action bar frame; no turn will do: a wider arc.
function Ring:Orbit(shown, size)
    local side, angle = self:Dock()
    local cx, cy, r, _, k = ns.Sphere.Geometry(side)
    local n = #shown
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local known = W and H and not A.secret(W) and not A.secret(H) and W > 0 and H > 0
    local floor = ns.Sphere.ArtTop() or 0
    local a0 = angle <= 180 and angle or 360 - angle
    local start = math.rad(math.max(30, math.min(150, a0)))
    local ro = r + A.HUB_SIZE / 2 * k + 6 + size / 2 -- outside the hub (the HUD's size)
    local gap = 6
    local function step() return (size + gap) / ro end
    local function angleOf(mid, k) return mid + (k - (n + 1) / 2) * step() end
    local function fits(mid)
        for k = 1, n do
            local a = angleOf(mid, k)
            local x, y = cx + ro * math.cos(a), cy + ro * math.sin(a)
            if x < size / 2 or x > W - size / 2 or y > H - size / 2 or y - size / 2 < floor + 4 then return false end
            if ns.Auras.Blocks(x, y, size) then return false end -- the buffs' and cast bar's column
        end
        return true
    end
    local function turn()
        for j = 0, 18 do
            local d = math.rad(10 * j)
            if fits(start + d) then return start + d end
            if fits(start - d) then return start - d end
        end
    end
    local mid = known and turn()
    -- a big ring (the game menu's 14) clears the buffs' column only well out: wider until past the
    -- screen's diagonal, where nothing is on it (24 steps at most before 0.5.440: a narrow screen's
    -- menu fitted on the last, and off it once the hubs came in 3.6 units)
    local reach = known and math.sqrt(W * W + H * H) or 0
    while not mid and ro < reach do
        ro = ro + 10
        mid = turn()
    end
    mid = mid or start
    for k, b in ipairs(shown) do
        local a = angleOf(mid, k)
        b.dx, b.dy = cx + ro * math.cos(a) - self.hx, cy + ro * math.sin(a) - self.hy
        b:ClearAllPoints()
        b:SetPoint("CENTER", self.ring, "CENTER", b.dx, b.dy)
    end
    self.radius, self.shape = ro, "round " .. side
end

-- The Bag hub lives in the action row, but its buttons belong around the map sphere. Search
-- from an arc just outside the other minimap hubs; the arc can grow or turn when the buff
-- stack, a pet bar, a moved hub, or the screen edge needs more room. Its targets are in
-- UIParent units, then converted to the Bag hub's scaled local coordinates.
function Ring:OrbitBags(shown, size)
    local cx, cy, hubRadius, _, k = ns.Sphere.Geometry("right")
    if not cx then return end
    local hx, hy = self.hub:GetCenter()
    local scale = self.hub:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local slotSize = size * scale
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local known = w and h and not A.secret(w) and not A.secret(h) and w > 0 and h > 0
    local floor = ns.Sphere.ArtTop() or 0
    local count = #shown
    local gap = 12
    local firstRadius = math.max(hubRadius + A.HUB_SIZE / 2 * k + slotSize / 2 + 12, 150)
    local angle, radius
    local function fits(mid, rr)
        for k = 1, count do
            local a = mid + ((count + 1) / 2 - k) * (slotSize + gap) / rr
            local x, y = cx + rr * math.cos(a), cy + rr * math.sin(a)
            if y - slotSize / 2 < floor + 4 then return false end
            if known and (x - slotSize / 2 < 0 or x + slotSize / 2 > w
                    or y + slotSize / 2 > h) then return false end
            if ns.Auras.Blocks(x, y, slotSize + 16) then return false end
            for _, other in ipairs(list) do
                if other ~= self and other:Config().shown and other.hub:IsShown() then
                    local ox, oy = other.hub:GetCenter()
                    if ox and oy and not A.secret(ox) and not A.secret(oy) then
                        local otherScale = other.hub:GetEffectiveScale() / UIParent:GetEffectiveScale()
                        ox, oy = ox * otherScale, oy * otherScale
                        local clear = (slotSize + other.hub:GetWidth() * otherScale) / 2 + 10
                        if math.abs(x - ox) < clear and math.abs(y - oy) < clear then return false end
                    end
                end
            end
        end
        return true
    end
    for rr = firstRadius, firstRadius + 200, 8 do
        for offset = 0, 12 do
            local turn = math.rad(5 * offset)
            for _, mid in ipairs({ math.rad(65) + turn, math.rad(65) - turn }) do
                if fits(mid, rr) then angle, radius = mid, rr; break end
            end
            if angle then break end
        end
        if angle then break end
    end
    -- On a very narrow screen, keep the same map-centred arc even if no complete clearance
    -- exists. The smaller radius is still attached to the sphere rather than the Bag button.
    angle, radius = angle or math.rad(65), radius or firstRadius
    for k, button in ipairs(shown) do
        local a = angle + ((count + 1) / 2 - k) * (slotSize + gap) / radius
        button.dx, button.dy = (cx + radius * math.cos(a)) / scale - hx,
            (cy + radius * math.sin(a)) / scale - hy
        button:ClearAllPoints()
        button:SetPoint("CENTER", self.ring, "CENTER", button.dx, button.dy)
    end
    self.radius, self.shape = radius, "round the map"
end

-- A docked hub: the minimap-button look, its place, no slot keys.
function Ring:DockHub()
    local hub = self.hub
    self.docked = true
    hub.art:SetShown(self.def.kind == "bags")
    hub.mini:SetShown(self.def.kind ~= "bags")
    hub.mini.border:Show()
    if self.def.kind == "menu" then
        hub.mini.bg:Hide()
        local border = hub.mini.border
        border:SetTexture("Interface\\AddOns\\Spheres\\Media\\MenuLatencyRing")
        border:SetBlendMode("BLEND")
        border:SetAlpha(0.28)
        border:SetSize(26, 26) -- the level well's ring (Sphere.lua levelRing), at the HUD's scale as it
        border:ClearAllPoints()
        border:SetPoint("CENTER", hub.mini, "CENTER")
        border:SetDrawLayer("BACKGROUND", 1)
        self:UpdateMenuLatency()
        local atlas = menuAtlas()
        if atlas then -- the question mark, at the atlas's own proportions (the micro buttons' 32 x 40)
            local info = C_Texture.GetAtlasInfo(atlas)
            local w, h = info and info.width, info and info.height
            local aspect = (type(w) == "number" and type(h) == "number" and h > 0) and w / h or 0.8
            hub.mini.icon:SetSize(MENU_GLYPH * aspect, MENU_GLYPH)
            hub.mini.icon:SetBlendMode("BLEND")
            -- hovered: the question mark highlighted as on Blizzard's button (its Mouseover art in
            -- its place), not the minimap buttons' blue glow (0.5.427, the player's: "just maybe
            -- highlight the question mark, like the original")
            local over = atlas:gsub("%-Up$", "-Mouseover")
            if over ~= atlas and A.AtlasOK(over) then
                local hover = hub.mini.hover
                hover:SetAtlas(over)
                hover:SetBlendMode("BLEND")
                hover:ClearAllPoints()
                hover:SetAllPoints(hub.mini.icon)
                hub.mini.swapHover = true
            else
                hub.mini.hover:SetAlpha(0) -- no glow either way
            end
        else
            hub.mini.icon:SetSize(12.5, 12.5)
            hub.mini.icon:SetTexCoord(0, 1, 0, 1) -- show the whole gear, including its teeth
            hub.mini.icon:SetBlendMode("ADD") -- the gear icon's dark square vanishes into the well
        end
        hub.mini.icon:SetAlpha(1)
    end
    -- The HUD's scale, as everything round it (0.5.434, the player's: "the stance ring button doesn't
    -- scale with the overall spheres scaling where others do"; 1 before, the Bag hub the row's).
    -- Its fan keeps UIParent's size (`Orbit` places it in UIParent's units): the ring undoes it.
    local hubScale = ns.Sphere.HudScale()
    if self.def.kind == "bags" then
        local anchor = ns.Bars.BagAnchor()
        if anchor and anchor.GetEffectiveScale then
            hubScale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
        end
    end
    self.hubScale = hubScale
    hub:SetScale(hubScale)
    self.ring:SetScale(self.def.kind == "bags" and 1 or 1 / hubScale) -- the Bag ring's fan: the row's size
    local hubSize = self.def.kind == "menu" and 27 or self.def.kind == "bags" and 32 or A.HUB_SIZE
    if self.def.kind == "bags" and ns.db.statueFinish == "modern" then
        hubSize = ns.Bars.BagAnchor():GetWidth() -- the same border and lattice inset as the action slots
    end
    hub:SetSize(hubSize, hubSize)
    if self.def.kind == "bags" then A.SizeAction(hub.art, hubSize) end
    hub:SetFrameStrata("MEDIUM")
    hub:SetFrameLevel(self.def.kind == "bags" and ns.Bars.Holder():GetFrameLevel() + 5 or 40)
    return self:PlaceHub()
end

-------------------------------------------------------------------------------
-- Spell fans: over the action slot that holds the group's macro, or docked
-------------------------------------------------------------------------------
local function holdsMacro(slot, def)
    if not slot then return false end
    local text = A.call(C_ActionBar and C_ActionBar.GetActionText or GetActionText, slot)
    return text ~= nil and not A.secret(text) and (text == def.macro or text == def.legacy) -- a macro's action text is its name
end

-- The shown row button whose slot holds the macro: returns it, its slot and its binding command.
function Ring:FindHome()
    for _, row in ipairs(ns.Bars.ROWS) do
        for i, b in ipairs(row.buttons or {}) do
            local slot = ns.Bars.Slot(row, i)
            if b:IsVisible() and holdsMacro(slot, self.def) then return b, slot, row.bind .. i end
        end
    end
end

-- The button under the fan's own goes invisible (its macro icon and name would show at the edges).
function Ring:Cover(btn)
    if self.covered == btn then return end
    if self.covered then self.covered:SetAlpha(1) end
    self.covered = btn
    if btn then btn:SetAlpha(0) end
end

function Ring:LayoutSpells()
    local db, c, hub, ring = ns.db, self:Config(), self.hub, self.ring
    local docked = c.collar and ns.Sphere.Geometry((self:Dock())) ~= nil
    local btn, slot, command
    if not docked then btn, slot, command = self:FindHome() end
    ClearOverrideBindings(hub)
    self.active = c.shown and (docked or btn ~= nil) or false
    if not self.active then
        self:Cover(nil)
        if UnregisterStateDriver then UnregisterStateDriver(hub, "visibility") end
        ring:Hide()
        hub:Hide()
        self.home, self.keys, self.docked = nil, nil, false
        return
    end
    if docked then
        self:Cover(nil)
        self.home = nil
        self:DockHub()
        hub:SetAttribute("action", nil)
        hub:SetAttribute("keyshift", false)
        -- its own key binding (Key Bindings -> Spheres): casts the pick
        self.keys = { GetBindingKey and GetBindingKey(R.CastBinding(self.def)) }
    else
        self.docked = false
        hub.art:Show()
        hub.mini:Hide()
        self.home = { button = btn, slot = slot, command = command }
        self:Cover(btn)
        hub:SetScale(btn:GetEffectiveScale() / UIParent:GetEffectiveScale())
        self.hubScale = nil
        ring:SetScale(1) -- over a row's slot: its fan the row's size, as before
        local w = btn:GetWidth()
        hub:SetSize(w, w)
        A.SizeAction(hub.art, w)
        hub:ClearAllPoints()
        hub:SetPoint("CENTER", btn, "CENTER")
        hub:SetFrameStrata(btn:GetFrameStrata() or "MEDIUM")
        hub:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
        hub:SetAttribute("action", slot)
        -- the slot's keys cast it (priority: over the rows' own key overrides); Shift + key: the fan
        self.keys = { GetBindingKey(command) }
        local shifted = false
        for _, key in ipairs(self.keys) do
            SetOverrideBindingClick(hub, true, key, hub:GetName(), "RightButton")
            if key:find("SHIFT%-") then shifted = true end
        end
        hub:SetAttribute("keyshift", shifted)
    end
    ring:SetFrameStrata("HIGH")

    local known, size, shown = ns.Spells.Known(self.def.group), db.size, {}
    for _, b in ipairs(self.slots) do
        local e = known[b.index]
        b.entry = e
        b:SetAttribute("spell", e and e.name or nil)
        if e then
            b:SetSize(size, size)
            A.SizeAction(b.art, size)
            shown[#shown + 1] = b
        end
        b:SetShown(e ~= nil)
        if b.link then b.link:SetShown(e ~= nil and not docked) end
    end
    local current
    for _, e in ipairs(known) do
        if not current and not e.oneShot then current = e end
        if e.key == c.current and not e.oneShot then current = e end
    end
    self.current = current or known[1]
    for _, b in ipairs(self.slots) do b:SetAttribute("oneshot", b.entry and b.entry.oneShot or nil) end
    local armed = self.armed
    if armed then
        local still = false
        for _, e in ipairs(known) do if e.key == armed.key then armed, still = e, true end end
        if not still then armed = nil end
        self.armed = armed
    end
    hub:SetAttribute("spell", (armed or self.current) and (armed or self.current).name or nil)
    hub:SetAttribute("revert", armed and self.current and self.current.name or nil)

    if docked then self:Orbit(shown, size) else self:FanFromSlot(shown, size) end
    ring:SetAttribute("numberkeys", db.numberKeys and true or false)
    if RegisterStateDriver then RegisterStateDriver(hub, "visibility", VISIBILITY) end
    hub:Show()
end

-- Over a slot near the bottom of the screen the fan opens up like a hand of cards: an arc
-- over the slot, clear of its row, turned 5 degrees at a time (and widened) to stay on screen.
function Ring:FanFromSlot(shown, size)
    local hub, ring, n = self.hub, self.ring, #shown
    local need = hub:GetHeight() / 2 + 8 + size / 2
    local step = size + 6
    local r = math.max(ns.db.radius, need + 12)
    local function half(rr) return (n - 1) * step / (2 * rr) end
    while half(r) >= math.pi / 2 - 0.05 or r * math.cos(half(r)) < need do r = r + 4 end
    local function angleOf(mid, k) return mid + (half(r) - (k - 1) * step / r) end
    local hx, hy = hub:GetCenter()
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local known = hx and hy and W and H and not A.secret(hx) and not A.secret(hy) and not A.secret(W) and not A.secret(H)
    local sc = known and hub:GetEffectiveScale() / UIParent:GetEffectiveScale() or 1
    local function fits(mid)
        for k = 1, n do
            local a = angleOf(mid, k)
            local x, y = r * math.cos(a), r * math.sin(a)
            if y < need then return false end
            if known then
                local sx, sy, m = (hx + x) * sc, (hy + y) * sc, size / 2 * sc
                if sx < m or sx > W - m or sy < m or sy > H - m then return false end
            end
        end
        return true
    end
    local base = math.pi / 2
    local function turn()
        for j = 0, 12 do
            local d = math.rad(5 * j)
            if fits(base + d) then return base + d end
            if fits(base - d) then return base - d end
        end
    end
    local mid = turn()
    for _ = 1, 20 do
        if mid then break end
        r = r + 8
        mid = turn()
    end
    mid = mid or base
    for k, b in ipairs(shown) do
        local a = angleOf(mid, k)
        b.dx, b.dy = r * math.cos(a), r * math.sin(a)
        b:ClearAllPoints()
        b:SetPoint("CENTER", ring, "CENTER", b.dx, b.dy)
        if b.link then b.link:SetStartPoint("TOP", hub, 0, -2) end
    end
    self.radius, self.shape = r, "above its slot"
end

-------------------------------------------------------------------------------
-- For other add-ons (Encounter Coach): where a spell sits in a fan, and making it the pick
-------------------------------------------------------------------------------
local function fanEntry(spell)
    for _, o in ipairs(list) do
        if o.def.kind == "spells" and o.active and o.hub:IsShown() then
            for i, b in ipairs(o.slots) do
                local e = b.entry
                if e and (e.name == spell or e.id == spell or e.key == spell) then return o, e, i end
            end
        end
    end
end

-- Action Ring's ActionRing_FanFor: the fan holding a spell (its local name, ID or English
-- name), or nil: { fan, button (to glow), key (casts the pick), openKey, index, numberKey, current }.
-- One table per spell, refreshed each call (Encounter Coach asks on every tick: a new one each
-- time was garbage; 0.5.430): two spells asked together still get two tables.
local fanInfo = setmetatable({}, { __mode = "k" })
function Spheres_FanFor(spell)
    local o, e, i = fanEntry(spell)
    if not o then return nil end
    local key = o.keys and o.keys[1]
    local toggle = GetBindingKey and GetBindingKey(R.ToggleBinding(o.def))
    local info = fanInfo[e]
    if not info then info = {}; fanInfo[e] = info end
    info.fan, info.button, info.key, info.index = o.def.id, o.hub, key, i
    info.openKey = toggle or (key and not o.docked and not key:find("SHIFT%-") and ("SHIFT-" .. key)) or nil
    info.numberKey = ns.db.numberKeys and R.KEYS[i] or nil
    info.current = (o.armed or o.current) == e
    return info
end

-- Action Ring's ActionRing_SetFanPick: make a spell its fan's pick (a one-shot is armed for one
-- cast). Out of combat only: false then, or if no fan holds it.
function Spheres_SetFanPick(spell)
    if inCombat() then return false end
    local o, e = fanEntry(spell)
    if not o then return false end
    if e.oneShot then
        if o.armed ~= e then
            o.armed = e
            o.hub:SetAttribute("spell", e.name)
            o.hub:SetAttribute("revert", o.current and o.current.name or nil)
            o:Update()
        end
    elseif o.current ~= e or o.armed then
        o:Config().current, o.current, o.armed = e.key, e, nil
        o.hub:SetAttribute("spell", e.name)
        o.hub:SetAttribute("revert", nil)
        o:Update()
    end
    return true
end

-- Put the group's macro on the cursor (made first, per character): drop it in a slot of the rows.
function R.PickupMacro(id)
    local o = rings[id]
    if not o or o.def.kind ~= "spells" then return false, "no such fan" end
    if inCombat() then return false, "not in combat" end
    local index = GetMacroIndexByName and GetMacroIndexByName(o.def.macro) or 0
    if index == 0 then
        local _, perCharacter = GetNumMacros()
        if (perCharacter or 0) >= (MAX_CHARACTER_MACROS or 18) then
            return false, "your character's macros are full (" .. (MAX_CHARACTER_MACROS or 18) .. ")"
        end
        local first = ns.Spells.Known(o.def.group)[1]
        local icon = first and A.call(C_Spell and C_Spell.GetSpellTexture, first.id) or 134400
        index = CreateMacro(o.def.macro, icon, "/click " .. o.hub:GetName() .. " RightButton", true)
    end
    if not index or index == 0 then return false, "the game didn't make the macro" end
    PickupMacro(index)
    return true
end

-------------------------------------------------------------------------------
-- Layout (out of combat only)
-------------------------------------------------------------------------------
function Ring:Layout()
    if self.def.kind == "spells" then return self:LayoutSpells() end
    local db, c = ns.db, self:Config()
    local hub, ring = self.hub, self.ring
    if self.def.kind == "bags" then ClearOverrideBindings(hub) end
    local size = self.def.kind == "bags" and ns.Bars.BagAnchor():GetWidth()
        or self.def.kind == "menu" and math.max(db.size * 1.15, MENU_SIZE) or db.size
    local screenWidth = UIParent:GetWidth()
    if self.def.kind == "menu" and screenWidth and not A.secret(screenWidth) and screenWidth > 0 then
        -- 25 shares of the width for its 14 buttons; each more needs one more share (0.5.433:
        -- day or night made 15, and on an 800-wide screen its arc found no place on it)
        size = math.min(size, screenWidth / (#R.MICRO + 11))
    end
    if not c.shown or not self:DockHub() then
        if UnregisterStateDriver then UnregisterStateDriver(hub, "visibility") end
        ring:Hide()
        hub:Hide()
        self.docked = false
        for _, b in ipairs(self.slots) do if b.native then giveBackNative(b) end end
        return
    end
    if self.def.kind == "bags" and GetBindingKey then
        for _, key in ipairs({ GetBindingKey("TOGGLEBACKPACK") }) do
            -- Keep the icon's left click for the fan. The backpack key invokes its
            -- secure right-click action so it opens the bag directly, even in combat.
            SetOverrideBindingClick(hub, false, key, hub:GetName(), "RightButton")
        end
    end
    local shown = {}
    local showAll = not db.hideEmpty or A.CursorHoldsAction()
    for i, b in ipairs(self.slots) do
        local on
        b.owner = self
        if self.def.kind == "action" then
            local slot = self:FirstSlot() + i - 1
            b:SetAttribute("action", slot)
            on = showAll or A.HasAction(slot)
            b:SetSize(size, size)
            A.SizeAction(b.art, size)
        elseif b.missing then
            on = false
        elseif self.def.kind == "bags" then
            on = b.native ~= nil
            b:SetSize(size, size)
            if b.native then takeNative(b) end
        else
            local micro = R.Micro(R.MICRO[i])
            b.micro = micro
            if not b.native then b:SetAttribute("clickbutton", micro) end
            on = micro ~= nil and micro:IsShown()
            if onDisc(b.nativeKind) then
                b:SetSize(A.MINIMAP_SIZE, A.MINIMAP_SIZE) -- Blizzard's header controls keep their own proportions
            else
                b:SetSize(size * 0.8, size) -- the menu buttons' shape (32x40)
                if not b.native then A.SizeMenu(b.art, size * 0.8, size) end
            end
            if b.native then takeNative(b) end
        end
        b:SetShown(on)
        if on then shown[#shown + 1] = b end
    end
    if self.def.kind == "bags" then self:OrbitBags(shown, size) else self:Orbit(shown, size) end
    ring:SetAttribute("numberkeys", db.numberKeys and true or false)
    if self.def.kind == "action" then hub:SetAttribute("action2", self:HubSlot()) end
    if RegisterStateDriver then RegisterStateDriver(hub, "visibility", VISIBILITY) end
    hub:Show()
end

-- Blizzard's Stance Bar (a Paladin's aura buttons or a Druid's form buttons) out of sight while
-- the matching spell fan is in use.
local stanceParent, stanceHolder
function R.UpdateStanceBar()
    local bar, auras, forms = StanceBar, rings.auras, rings.forms
    if not bar or inCombat() then return end
    local want = ((auras ~= nil and auras.active) or (forms ~= nil and forms.active))
        and ns.db.hideStanceBar ~= false
    if want and not stanceParent then
        stanceHolder = stanceHolder or CreateFrame("Frame")
        stanceHolder:Hide()
        stanceParent = bar:GetParent()
        bar:SetParent(stanceHolder)
    elseif not want and stanceParent then
        bar:SetParent(stanceParent)
        stanceParent = nil
    end
end
function R.StanceBarHidden() return stanceParent ~= nil end

function R.Layout()
    if #list == 0 then return true end
    if inCombat() then
        pending = true
        return false
    end
    pending = false
    for _, o in ipairs(list) do o:Layout() end
    R.UpdateStanceBar()
    R.UpdateAll()
    return true
end

function R.Pending() return pending end
function R.OnCombatEnd() if pending then R.Layout() end end

function R.ResetDocks()
    for _, o in ipairs(list) do o:Config().dock = nil end
    return R.Layout()
end

local soon = false
function R.LayoutSoon()
    if soon then return end
    soon = true
    local function run()
        soon = false
        if not R.Layout() then R.UpdateAll() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

function R.HasSpellFans()
    for _, o in ipairs(list) do if o.def.kind == "spells" then return true end end
    return false
end

function R.OnSlotChanged(slot)
    if R.HasSpellFans() then return R.LayoutSoon() end
    for _, o in ipairs(list) do
        if o.def.kind == "action" and o:Config().shown then
            local first = o:FirstSlot()
            if slot == nil or slot == 0 or (slot >= first and slot < first + 12) then
                if not R.Layout() then R.UpdateAll() end
                return
            end
        end
    end
end

-- Empty slots show while the cursor holds something to drop on them (`hideEmpty`): a new layout
-- only when that changes. The game sends CURSOR_CHANGED for every change of the cursor, and a
-- layout each time was ~14 KB of garbage (0.5.433, the player's 32 MB: the harness's garbage run).
local cursorHolds = false
function R.OnCursorChanged()
    local holds = A.CursorHoldsAction()
    if holds == cursorHolds then return end
    cursorHolds = holds
    if ns.db.hideEmpty then R.Layout() end
end

-------------------------------------------------------------------------------
-- Status and debug
-------------------------------------------------------------------------------
function R.ShownLabels()
    local t = {}
    for _, o in ipairs(list) do if o:Config().shown then t[#t + 1] = o.def.label end end
    return t
end

function Ring:Debug()
    local shownN = 0
    for _, b in ipairs(self.slots) do if b:IsShown() then shownN = shownN + 1 end end
    local side, angle = self:Dock()
    local where = self.def.kind == "bags" and "in the upper action row"
        or self.docked and string.format("by the %s sphere at %.0f degrees", side, angle) or "not docked"
    if self.def.kind == "spells" then
        local home = self.home
        if home then
            where = string.format("over slot %d (%s, key %s)", home.slot, tostring(home.command),
                self.keys and self.keys[1] and A.KeyText(self.keys[1]) or "none")
        elseif not self.docked then
            where = "not on a bar (place \"" .. self.def.macro .. "\")"
        end
        return string.format("%s: %s, %d known, picks %s, %s", self.def.label, where, shownN,
            (self.current and self.current.name or "-") .. (self.armed and (", armed: " .. self.armed.name .. " once") or ""),
            self.ring:IsShown() and "open" or "closed")
    end
    local extra = ""
    if self.def.kind ~= "action" then
        local inRing = 0
        for _, b in ipairs(self.slots) do
            if b.native and b.nativeKind ~= "show" and b.native:GetParent() == b.art then inRing = inRing + 1 end
        end
        extra = string.format(", %d of Blizzard's buttons in it", inRing)
        if self.def.kind == "menu" then
            extra = extra .. ", day or night: " .. (not diel and "the game has no answer"
                or not diel:IsShown() and "hidden" or diel.atlas == DIEL.day and "day" or "night")
        end
    end
    return string.format("%s: %s, %d shown%s, %s", self.def.label, where, shownN, extra, self.ring:IsShown() and "open" or "closed")
end
