local _, ns = ...

-- The two rows between the orbs, filling Roth UI's action bar frame (Sphere.lua):
-- Action Bar 1 and Action Bar 2, our own secure action buttons (Blizzard's bar code never runs on
-- them; their look is Art.lua's copy of Blizzard's).
--   * Row 1 is Bar 1 with its pages: each button has its ID (1-12) and no action of its own,
--     so Blizzard's secure click works out the slot as for its own Bar 1 (ActionButton_
--     CalculateAction: the bar page, a vehicle's or override bar, a temporary shapeshift, a
--     druid's or warrior's bonus bar). The look follows the same rule (B.Page).
--   * Row 2 is Bar 2: slots 61-72, then Bar 8's last slot (180).
--   * Their keys: whatever Blizzard's ACTIONBUTTON1-12 and MULTIACTIONBAR1BUTTON1-12 are bound
--     to, as override bindings on our buttons (a spell fan over one of them takes its key with a
--     priority override, Ring.lua).
--   * Blizzard's bars, menu, bags and experience bars go out of sight under a hidden frame (out of
--     combat: they're protected): the rows, the rings (bars 3-8, the game menu, the bags), the
--     orbs and the frame's own experience bars (Track.lua) replace them. Blizzard's own vehicle
--     and override bars still show in vehicles, and ours hide.
--   * Your pet's buttons are ours too (0.5.286, B.Pet below), centred over the frame; the stance
--     and cast bars (Blizzard's) sit over the frame.

local A = ns.Art
local B = {}
ns.Bars = B

local ROWS = {
    { id = 1, prefix = "SpheresBar1Button", bind = "ACTIONBUTTON", first = 1, paged = true, label = "Action Bar 1" },
    { id = 2, prefix = "SpheresBar2Button", bind = "MULTIACTIONBAR1BUTTON", first = 61, label = "Action Bar 2" },
}
B.ROWS = ROWS
local VISIBILITY = "[vehicleui][overridebar][petbattle] hide; show"
local REPLACED = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
    "MultiBar5", "MultiBar6", "MultiBar7", "MicroMenuContainer", "BagsBar", "PetActionBar",
    "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "MainMenuExpBar", "ReputationWatchBar" }
-- In the frame's units (Sphere.lua): bigger than Roth's 26, filling the frame between the orbs
-- (0.4.1: "a lot of empty space"), the rows 3.5 apart, the lower one this far up
local SIZE = 31.36 -- 98% of the 32-unit buttons, keeping the same 3-unit gaps
local GAP = 3
local ROW_GAP = 3.5
local BOTTOM = 7.5 -- upper row stays fixed as the lower row moves closer to it
local COLUMNS = 13
local EXTRA_SLOT = 180 -- last slot of Action Bar 8 (Ring.BAR_PAGE[8] = 15)

local holder, ticker, bagAnchor
local hidden = {}  -- Blizzard frame -> its old parent
local pending = false
local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() end

function B.Holder() return holder end
function B.Buttons(row) return ROWS[row] and ROWS[row].buttons or {} end
function B.BagAnchor() return bagAnchor end

-------------------------------------------------------------------------------
-- Bar 1's page, as Blizzard pages its own main bar (ActionBarController_UpdateAll: a vehicle's, else an
-- override bar's, else a temporary shapeshift's, else your form's or stance's bonus bar on page 1, else
-- your page). This client's secure click (SecureActionButtonMixin:CalculateAction) knows only the
-- button's "actionpage", else GetActionBarPage: no forms. So row 1's strip has its "actionpage" set by
-- the game from those macro conditions (an attribute driver: in combat too), its buttons take it
-- (useparent-actionpage), and what shows is read from it (0.5.479, the player's: "in bear form, my
-- primary action bar looks empty but when say hit 3, it casts human form spell"; a transform's buttons
-- showed and the keys cast your own).
-------------------------------------------------------------------------------
local function call(fn, ...) if fn then return A.call(fn, ...) end end
local function index(fn, default)
    local v = call(fn)
    return type(v) == "number" and v or default
end
local function pageConditions()
    local AB = C_ActionBar or {}
    local vehicle = index(AB.GetVehicleBarIndex or GetVehicleBarIndex, 12)
    local override = index(AB.GetOverrideBarIndex or GetOverrideBarIndex, 14)
    local temp = index(AB.GetTempShapeshiftBarIndex or GetTempShapeshiftBarIndex, 13)
    return string.format("[vehicleui][possessbar] %d; [overridebar] %d; [shapeshift] %d; [bar:2] 2; [bar:3] 3; "
        .. "[bar:4] 4; [bar:5] 5; [bar:6] 6; [bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; "
        .. "[bonusbar:5] 11; 1", vehicle, override, temp)
end
function B.Page()
    local strip = ROWS[1].strip
    local driven = strip and tonumber(strip:GetAttribute("actionpage"))
    if driven then return driven end -- the game's, as the keys use it
    local page = call(GetActionBarPage) or 1
    if call(HasVehicleActionBar) then page = call(GetVehicleBarIndex) or page
    elseif call(HasOverrideActionBar) then page = call(GetOverrideBarIndex) or page
    elseif call(HasTempShapeshiftActionBar) then page = call(GetTempShapeshiftBarIndex) or page
    elseif call(HasBonusActionBar) and page == 1 then page = call(GetBonusBarIndex) or page end
    return page
end

function B.Slot(row, i)
    if row.id == 2 and i == COLUMNS then return EXTRA_SLOT end
    if row.paged then return i + (B.Page() - 1) * 12 end
    return row.first + i - 1
end

local function commandFor(row, i)
    if row.id == 2 and i == COLUMNS then return "CLICK SpheresBar2Button13:LeftButton" end
    return row.bind .. i
end
local function keyFor(row, i) return GetBindingKey and GetBindingKey(commandFor(row, i)) or nil end

-------------------------------------------------------------------------------
-- Your pet's buttons (0.5.286). Blizzard's pet bar is an Edit Mode bar: in combat, when any bottom
-- bar shows or hides, Edit Mode stacks it on the main bar, and being protected it couldn't be put
-- back until the fight was over ("in combat, the pet controls go in a different position"). So
-- ours, as the rows are, centred over the frame where nothing else moves them, Blizzard's under
-- the hidden frame: ten secure buttons on the pet's slots, left-click casting (type "pet":
-- CastPetAction), right-click clicking Blizzard's own button for the slot, whose right-click
-- toggles autocast (TogglePetAutocast is protected; a delegated click stays secure, in combat
-- too), its keys (BONUSACTIONBUTTON1-10), dragging (PickupPetAction), Blizzard's look
-- (PetActionButtonMixin:UpdateButtonState) and autocast glow. A state driver shows them with a pet.
-------------------------------------------------------------------------------
local PET = { count = 10, size = 26, gap = 3, up = 2, bind = "BONUSACTIONBUTTON",
    visibility = "[petbattle][vehicleui][overridebar][possessbar] hide; [pet] show; hide" }
local petBar
B.Pet = PET

function B.PetBar() return petBar end

-- Blizzard's button for pet slot i (its right-click toggles autocast).
local function blizzardPet(i)
    local own = PetActionBar and PetActionBar.actionButtons
    return own and own[i] or _G["PetActionButton" .. i]
end

local function plain(v) return not A.secret(v) and v end

-- The pet API is called as Blizzard's bar calls it (A.call keeps two answers; this has nine).
local function paintPet(b)
    if not GetPetActionInfo then return end
    local a, i = b.art, b.index
    local _, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, _, checksRange, inRange =
        GetPetActionInfo(i)
    if plain(isToken) and texture then texture = _G[texture] end
    local has = texture ~= nil
    a.icon:SetShown(has)
    a.empty:SetShown(not has)
    a.cooldown:SetShown(has)
    a.count:SetText("")
    a.name:SetText("")
    a.border:Hide()
    a.checked:SetShown(has and plain(isActive) and true or false)
    -- attack, while attacking: Blizzard's half-strength check ("looks like an extra ability selected")
    a.checked:SetAlpha(plain(IsPetAttackAction(i)) and 0.5 or 1)
    a.hotkey:SetTextColor(0.6, 0.6, 0.6)
    local text = A.KeyText(GetBindingKey and GetBindingKey(PET.bind .. i))
    if has then
        a.icon:SetTexture(texture)
        local usable = GetPetActionSlotUsable(i)
        if A.secret(usable) or usable then a.icon:SetVertexColor(1, 1, 1)
        else a.icon:SetVertexColor(0.4, 0.4, 0.4) end
        local start, duration, enable = GetPetActionCooldown(i)
        if A.secret(start) or A.secret(duration) or A.secret(enable) then
            pcall(a.cooldown.SetCooldown, a.cooldown, start, duration)
        elseif enable and enable ~= 0 and duration and duration > 0 then
            a.cooldown:SetCooldown(start, duration)
        else
            a.cooldown:Clear()
        end
        local out = plain(checksRange) and not A.secret(inRange) and inRange == false
        if text == "" and out then text = RANGE_INDICATOR or "●" end
        if out then a.hotkey:SetTextColor(1, 0.1, 0.1) end
    end
    a.hotkey:SetText(text)
    if b.autocast then
        b.autocast:SetShown(has and plain(autoCastAllowed) and true or false)
        if b.autocast.ShowAutoCastEnabled then b.autocast:ShowAutoCastEnabled(plain(autoCastEnabled) and true or false) end
    end
end

function B.UpdatePet()
    if not petBar then return end
    for _, b in ipairs(petBar.buttons) do paintPet(b) end
end

-- The rows are painted from the game's events, none on a timer (0.5.422: a full repaint five
-- times a second, about a millisecond each, made Spheres most of the add-ons' time). Range comes
-- with ACTION_RANGE_CHECK_UPDATE for each slot shown (C_ActionBar.EnableActionRangeCheck, as
-- Blizzard's own buttons), usable with ACTIONBAR_UPDATE_USABLE / ACTION_USABLE_CHANGED (B.UpdateUsable).
-- `keepCooldowns`: everything else again, the cooldowns as last painted (the game's events other
-- than cooldown ones: Core.lua COOLDOWN_EVENTS). Each button keeps its own opts table (0.5.419: a
-- new one per button, with a closure and a cooldown duration object each, made the add-on's memory
-- climb some 30 KB a second).
local NONE = {}
local ranged = {} -- slots whose range the game tells us about
local function watchRange(slot)
    if ranged[slot] or not (C_ActionBar and C_ActionBar.EnableActionRangeCheck) then return end
    ranged[slot] = true
    pcall(C_ActionBar.EnableActionRangeCheck, slot, true)
end
function B.Update(keepCooldowns)
    for _, row in ipairs(ROWS) do
        for i, b in ipairs(row.buttons or NONE) do
            local slot = B.Slot(row, i)
            b.action = slot -- what Encounter Coach and dragging read
            local paint = b.paint
            if not paint then paint = {}; b.paint = paint end
            paint.key, paint.keepCooldown = keyFor(row, i), keepCooldowns and true or nil
            A.PaintAction(b, slot, paint)
            if slot then watchRange(slot) end
        end
    end
    B.UpdatePet()
end

-- The game's usable event: just the icons' colour (all of them, or the slots it names).
function B.UpdateUsable(changes)
    for _, row in ipairs(ROWS) do
        for _, b in ipairs(row.buttons or NONE) do
            if b.action and A.HasAction(b.action) then
                if type(changes) ~= "table" then A.PaintUsable(b, b.action)
                else
                    for _, c in ipairs(changes) do
                        if not A.secret(c.slot) and c.slot == b.action then
                            A.PaintUsable(b, b.action, c.usable, c.noMana)
                        end
                    end
                end
            end
        end
    end
end

-- The game's range event for a slot: the key of each button showing it.
function B.OnRangeCheck(slot, inRange, checksRange)
    if A.secret(slot) then return end
    local out = not A.secret(checksRange) and checksRange and not A.secret(inRange) and inRange == false
    for _, row in ipairs(ROWS) do
        for _, b in ipairs(row.buttons or NONE) do
            if b.action == slot then A.PaintRange(b, out and true or false) end
        end
    end
end

-------------------------------------------------------------------------------
-- Building (once)
-------------------------------------------------------------------------------
local function tooltip(b)
    b:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, A.TooltipAnchor(self))
        local slot = self.action
        if not (slot and A.HasAction(slot) and GameTooltip.SetAction and GameTooltip:SetAction(slot)) then
            GameTooltip:SetText("Empty slot " .. self.index .. " of " .. self.row.label, 1, 1, 1)
            GameTooltip:AddLine("Drag a spell, item or macro here.", 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- Blizzard's rules for dragging actions on and off (Art.lua), on the slot the button shows now
local function drag(b)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        if not A.BarsLocked() or IsModifiedClick("PICKUPACTION") then
            PickupAction(self.action)
            B.Update()
        end
    end)
    b:SetScript("OnReceiveDrag", function(self)
        PlaceAction(self.action)
        B.Update()
    end)
end

function B.Create()
    if holder then return end
    local hud = ns.Sphere.HUD()
    holder = CreateFrame("Frame", "SpheresBars", hud)
    holder:SetFrameLevel(hud:GetFrameLevel() + 20)
    holder:EnableMouse(false)
    bagAnchor = CreateFrame("Frame", "SpheresBagAnchor", holder)
    bagAnchor:EnableMouse(false)
    for _, row in ipairs(ROWS) do
        local strip = CreateFrame("Frame", "SpheresBar" .. row.id, holder)
        strip:EnableMouse(true) -- the gaps between buttons don't click through to the world
        row.strip, row.buttons = strip, {}
        for i = 1, row.id == 1 and 12 or COLUMNS do
            local b = CreateFrame("Button", row.prefix .. i, strip, "SecureActionButtonTemplate")
            b.index, b.row = i, row
            -- like Blizzard's bars: keys on press or release as ActionButtonUseKeyDown says, the mouse on release
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetAttribute("type", "action")
            if row.paged then
                b:SetID(i)
                b:SetAttribute("useparent-actionpage", true) -- the strip's page (pageConditions)
            else
                b:SetAttribute("action", B.Slot(row, i))
            end
            A.BuildAction(b)
            drag(b)
            tooltip(b)
            b:SetScript("PostClick", function() B.Update() end)
            row.buttons[i] = b
        end
    end
    -- row 1's page from the game (in combat too), and its buttons painted when it turns
    local paged = ROWS[1].strip
    if RegisterAttributeDriver then RegisterAttributeDriver(paged, "actionpage", pageConditions()) end
    paged:HookScript("OnAttributeChanged", function(_, name)
        if name == "actionpage" then B.Update() end
    end)
    petBar = CreateFrame("Frame", "SpheresPetBar", holder)
    petBar.buttons = {}
    for i = 1, PET.count do
        local b = CreateFrame("Button", "SpheresPetButton" .. i, petBar, "SecureActionButtonTemplate")
        b.index = i
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "pet")
        b:SetAttribute("action", i)
        b:SetAttribute("type2", "click") -- autocast: Blizzard's button (blizzardPet)
        b:SetAttribute("clickbutton2", blizzardPet(i))
        A.BuildAction(b)
        local ok, glow = pcall(CreateFrame, "Frame", nil, b.art.top, "AutoCastOverlayTemplate")
        if ok and glow then -- Blizzard's autocast ants (Blizzard_UIPanelTemplates), at a 45 button's size
            glow:SetSize(45, 45)
            glow:SetPoint("CENTER", b)
            glow:Hide()
            b.autocast = glow
        end
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            if not A.BarsLocked() or IsModifiedClick("PICKUPACTION") then
                PickupPetAction(self.index)
                B.UpdatePet()
            end
        end)
        b:SetScript("OnReceiveDrag", function(self)
            if GetCursorInfo and GetCursorInfo() == "petaction" then
                PickupPetAction(self.index)
                B.UpdatePet()
            end
        end)
        b:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, A.TooltipAnchor(self))
            if GameTooltip.SetPetAction and GameTooltip:SetPetAction(self.index) then GameTooltip:Show()
            else GameTooltip:Hide() end -- an empty slot or a command: Blizzard shows none either
        end)
        b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:SetScript("PostClick", function() B.UpdatePet() end)
        petBar.buttons[i] = b
    end
    petBar:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_PET" and unit ~= "player" then return end
        B.UpdatePet()
    end)
    for _, e in ipairs({ "PET_BAR_UPDATE", "PET_BAR_UPDATE_COOLDOWN", "PET_BAR_UPDATE_USABLE", "PET_UI_UPDATE",
            "UNIT_PET", "PLAYER_TARGET_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
        pcall(petBar.RegisterEvent, petBar, e)
    end
    -- your pet's range has no event (Blizzard's pet bar checks it on a timer too): a few times a
    -- second, only while its buttons show
    ticker = CreateFrame("Frame", nil, petBar)
    local since = 0
    ticker:SetScript("OnUpdate", A.Timed("pet bar range", function(_, elapsed)
        since = since + (elapsed or 0)
        if since >= 0.2 then since = 0; B.UpdatePet() end
    end))
end

-------------------------------------------------------------------------------
-- Blizzard's frames out of sight (out of combat)
-------------------------------------------------------------------------------
local stash
local function stow(f)
    if not f or hidden[f] then return end
    stash = stash or CreateFrame("Frame")
    stash:Hide()
    hidden[f] = f:GetParent() or UIParent
    f:SetParent(stash)
end

function B.StowBlizzard()
    for _, name in ipairs(REPLACED) do stow(_G[name]) end
    local retail = ns.Retail
    local extra = retail and retail.AdditionalStowFrames and retail.AdditionalStowFrames()
    for _, name in ipairs(extra or {}) do stow(_G[name]) end
end
function B.Stowed() local n = 0; for _ in pairs(hidden) do n = n + 1 end; return n end

-- Blizzard's stance bar hangs off Bar 1 by default: over the frame instead (its top edge,
-- Sphere.lua); the pet's buttons are ours (B.Pet), there too. Your cast bar over the buffs and debuffs stacked there (Auras.lua; in the
-- corner setting, CAST_UP over the frame): Blizzard places it again when a cast starts and after
-- Edit Mode, so a hook puts it back, in combat too (it isn't protected; checked).
local CAST_UP = 40 -- over the frame: room for a pet or stance bar between
local function castBar() return PlayerCastingBarFrame or CastingBarFrame end
local placingCast = false
local function placeCastBar()
    local cb = castBar()
    if not cb or (cb.IsInDefaultPosition and not cb:IsInDefaultPosition()) then return nil end
    if inCombat() and cb.IsProtected and cb:IsProtected() then return cb end
    placingCast = true
    cb:ClearAllPoints()
    local bottom = ns.Auras and ns.Auras.CastBottom()
    if bottom then
        cb:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, bottom * UIParent:GetEffectiveScale() / cb:GetEffectiveScale())
    else
        cb:SetPoint("BOTTOM", ns.Sphere.TopAnchor(), "TOP", 0, CAST_UP)
    end
    placingCast = false
    if not cb.spheresHooked and hooksecurefunc then
        cb.spheresHooked = true
        hooksecurefunc(cb, "SetPoint", function()
            if not placingCast and holder and holder:IsShown() then placeCastBar() end
        end)
    end
    return cb
end
B.CastBar = castBar
B.PlaceCastBar = placeCastBar

-- The stance and possess bars while Edit Mode has them in their default place.
local function placeSmallBars()
    local top = ns.Sphere.TopAnchor()
    for _, name in ipairs({ "StanceBar", "PossessActionBar" }) do
        local f = _G[name]
        if f and (not f.IsInDefaultPosition or f:IsInDefaultPosition())
                and not (f == StanceBar and ns.Ring.StanceBarHidden()) then
            f:ClearAllPoints()
            f:SetPoint("BOTTOM", top, "TOP", 0, 2)
        end
    end
    -- ours: centred over the frame, only ever placed by us
    local w = PET.count * PET.size + (PET.count - 1) * PET.gap
    petBar:SetSize(w, PET.size)
    petBar:ClearAllPoints()
    petBar:SetPoint("BOTTOM", top, "TOP", 0, PET.up)
    for i, b in ipairs(petBar.buttons) do
        b:SetSize(PET.size, PET.size)
        A.SizeAction(b.art, PET.size)
        if b.autocast then b.autocast:SetScale(PET.size / 45) end
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", petBar, "BOTTOMLEFT", (i - 1) * (PET.size + PET.gap), 0)
    end
    if RegisterStateDriver then RegisterStateDriver(petBar, "visibility", PET.visibility) end
    placeCastBar()
end

-------------------------------------------------------------------------------
-- Layout (out of combat only)
-------------------------------------------------------------------------------
local function bindKeys()
    ClearOverrideBindings(holder)
    for _, row in ipairs(ROWS) do
        for i, b in ipairs(row.buttons) do
            for _, key in ipairs({ GetBindingKey(commandFor(row, i)) }) do
                SetOverrideBindingClick(holder, false, key, b:GetName(), "LeftButton")
            end
        end
    end
    for i, b in ipairs(petBar.buttons) do -- your pet's keys onto ours
        for _, key in ipairs({ GetBindingKey(PET.bind .. i) }) do
            SetOverrideBindingClick(holder, false, key, b:GetName(), "LeftButton")
        end
    end
end

function B.BindKeys()
    if not holder then return true end
    if inCombat() then pending = true; return false end
    bindKeys()
    B.Update()
    return true
end

function B.Layout()
    if not holder then return true end
    if inCombat() then pending = true; return false end
    pending = false
    local size = SIZE
    local width = COLUMNS * size + (COLUMNS - 1) * GAP
    holder:SetSize(width, 2 * size + ROW_GAP)
    holder:ClearAllPoints()
    holder:SetPoint("BOTTOM", ns.Sphere.FrameAnchor(), "BOTTOM", 0, BOTTOM)
    for r, row in ipairs(ROWS) do
        row.strip:SetSize(width, size)
        row.strip:ClearAllPoints()
        row.strip:SetPoint("BOTTOM", holder, "BOTTOM", 0, (2 - r) * (size + ROW_GAP))
        for i, b in ipairs(row.buttons) do
            b:SetSize(size, size)
            A.SizeAction(b.art, size)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", row.strip, "BOTTOMLEFT", (i - 1) * (size + GAP), 0)
        end
    end
    bagAnchor:SetSize(size, size)
    bagAnchor:ClearAllPoints()
    bagAnchor:SetPoint("BOTTOMLEFT", ROWS[1].strip, "BOTTOMLEFT", 12 * (size + GAP), 0)
    B.StowBlizzard()
    if RegisterStateDriver then RegisterStateDriver(holder, "visibility", VISIBILITY) end
    holder:Show()
    placeSmallBars()
    bindKeys()
    B.Update()
    return true
end

function B.Pending() return pending end
function B.OnCombatEnd() if pending then B.Layout() end end

function B.Debug()
    local filled = { 0, 0 }
    for r, row in ipairs(ROWS) do
        for i = 1, #row.buttons do if A.HasAction(B.Slot(row, i)) then filled[r] = filled[r] + 1 end end
    end
    local b1 = ROWS[1].buttons and ROWS[1].buttons[1]
    local there = 0
    for _, name in ipairs(REPLACED) do if _G[name] then there = there + 1 end end
    return string.format("rows: Bar 1 page %d (button 1 -> slot %d, %d filled), Bar 2 slots 61-72 and 180 (%d filled), key 1: %s, Blizzard frames stowed %d of %d",
        B.Page(), b1 and b1.action or 0, filled[1], filled[2], tostring(keyFor(ROWS[1], 1)), B.Stowed(), there)
end

-- In game: whether the pet's buttons show, what they hold, and if right-click reaches Blizzard's.
function B.PetDebug()
    if not petBar then return "pet bar: not built" end
    local filled, delegated = 0, 0
    for i, b in ipairs(petBar.buttons) do
        if GetPetActionInfo and GetPetActionInfo(i) ~= nil then filled = filled + 1 end
        if b:GetAttribute("clickbutton2") then delegated = delegated + 1 end
    end
    return string.format("pet bar: %s, %d of %d slots filled, autocast by right-click on %d, autocast glow %s, key 1: %s",
        petBar:IsShown() and "shown" or "hidden", filled, PET.count, delegated,
        petBar.buttons[1].autocast and "yes" or "no", tostring(GetBindingKey and GetBindingKey(PET.bind .. 1)))
end
