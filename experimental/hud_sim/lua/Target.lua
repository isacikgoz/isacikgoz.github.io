local ADDON, ns = ...

-- Your target, top centre (under a laptop's camera notch), standing free (0.5.0: no plate or
-- border, "unnecessary"): a round portrait in a gold ring, its level in a badge, the name
-- (coloured by how it feels about you) and what it is (Elite, Rare, Boss), then its health and
-- power bars, and Blizzard's own target cast bar under them. Blizzard's target frame goes out of
-- sight.
--
-- Its auras under the bars, as Blizzard's target frame filters them (harmful ones, those only
-- nameplates show too, first; then helpful ones), in centred rows. Forever may hide an aura's
-- details from add-ons ("SecretWhenUnitAuraRestricted"): its icon and count go into their
-- widgets as they are; its time only through the aura's duration object; a hidden aura ID can't
-- be handed back to the API (add-on code may not pass hidden values on), so such an aura shows
-- its icon only. Blizzard's own aura container is forbidden to add-ons: it can't be moved here.
--
-- Target Style "Sphere" (0.5.468, experimental; the targetStyle setting, "card" by default): the bars
-- give way to a sphere as your own (Sphere.lua S.TargetSphere: its health and power as liquids in
-- two glass pieces) with the portrait, ring and badge in its very centre; name, kind, auras and cast
-- bar under it.
--
-- The card is a secure unit button (SecureUnitButtonTemplate, unit "target"): a click targets,
-- a right-click opens Blizzard's unit menu, and a unit watch shows it only while you have a
-- target, in combat too. Health and power may be hidden values: they go straight into the
-- status bars and font strings (allowed), never into Lua (Sphere.lua `given`).

local A = ns.Art
local T = {}
ns.Target = T

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local W, PORTRAIT, BAR_W, HEALTH_H, POWER_H = 156, 74, 148, 18, 11 -- bars were 136 x 14 and 8 (0.5.9: bigger);
                                                                   -- their files are drawn at these (make_media.py BARS)
local RIM_PAD = 2.5 -- the bars' rim files reach this far round them (make_media.py BAR_RIM_PAD)
local HEALTH_FRIENDLY = { 0.15, 0.62, 0.12 }
local HEALTH_HOSTILE = { 0.78, 0.07, 0.045 }
local HEALTH_NEUTRAL = { 0.72, 0.38, 0.055 }
local TAPPED_COLOR = { 0.5, 0.5, 0.5 } -- Blizzard's: someone else got to it first
local MANA_COLOR = { 0.045, 0.22, 0.82 } -- deep, saturated blue, like the mana sphere
-- near the top (0.5.476, the player's: "default top position is better than the current low. It gets in
-- the way"; 220 down before, below the top announcement lane and a MacBook's notch); Blizzard's breath
-- bars move under it (T.PlaceTimers)
local TOP = -24
local GOLD_RING = "Azerite-GoldRing-Rank3"
local RING_IN = 26 / 758
local RANK_RINGS = {
    elite = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold",
    rareelite = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver",
    worldboss = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged",
}
local REACTION = { [1] = { 1, 0.2, 0.2 }, [2] = { 1, 0.2, 0.2 }, [3] = { 1, 0.5, 0.25 }, [4] = { 1, 0.85, 0.2 },
    [5] = { 0.3, 1, 0.3 }, [6] = { 0.3, 1, 0.3 }, [7] = { 0.3, 1, 0.3 }, [8] = { 0.3, 1, 0.3 } }
local KIND = { elite = "Elite", rareelite = "Rare Elite", rare = "Rare", worldboss = "Boss" }
local NAME_GOLD, NAME_PLAYER = { 1, 0.82, 0 }, { 1, 1, 1 }
-- What each of the target's events changes, alone (0.5.433: every hit on it, UNIT_HEALTH, painted
-- the whole card again, its portrait and every aura read anew: ~1.6 KB of garbage each time);
-- its name, level, class and reaction: the whole card (T.Update).
local PARTS = { UNIT_HEALTH = "UpdateHealth", UNIT_MAXHEALTH = "UpdateHealth", UNIT_POWER_UPDATE = "UpdatePower",
    UNIT_MAXPOWER = "UpdatePower", UNIT_DISPLAYPOWER = "UpdatePower", UNIT_AURA = "UpdateAuras",
    UNIT_PORTRAIT_UPDATE = "UpdatePortrait" }
local AURA, AURA_GAP, PER_ROW = 22, 3, 6
local ROW_W = PER_ROW * AURA + (PER_ROW - 1) * AURA_GAP -- a row's width: known, not asked (on the nameplate card a
                                                        -- frame's size reads hidden: it hangs from a plate)
local AURA_KINDS = {
    { key = "debuff", filter = "HARMFUL|INCLUDE_NAME_PLATE_ONLY", max = 12 },
    { key = "buff", filter = "HELPFUL", max = 12 },
}

local card
local targetParent, targetHolder
local castParent
local placingCast = false
local editing = false
local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() end
local function secret(v) return A.secret(v) end
local function given(v) return secret(v) or v ~= nil end
local function pick(v, default) -- an if, not `v or default`: a hidden value can't be tested
    if given(v) then return v end
    return default
end
local function call(fn, ...)
    if not fn then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local function num(v) return v ~= nil and not secret(v) end

function T.Card() return card end

-- A bar with round ends (0.5.11: square ones were "too boxy"): its shape is drawn into its files
-- at its size (tools/make_media.py BARS), no mask (a masked status bar fill never drew in
-- Forever). A dark track, the fill (round at its start; its end cut straight at the value), glass
-- over it, a brass rim round it.
local function bar(parent, h, kind)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetSize(BAR_W, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(MEDIA .. "BarShape" .. kind)
    b.bg:SetVertexColor(0, 0, 0, 0.75)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetTexture(MEDIA .. "BarFill" .. kind) -- Roth's liquid, the spheres' (0.5.13: flat was "inorganic")
    b:SetStatusBarTexture(b.fill) -- a texture object: the way that draws in Forever (DPS Meter's)
    b:SetMinMaxValues(0, 1)
    b:SetValue(1)
    -- Dark fluid wisps follow the same hidden value above the liquid, like the large spheres.
    b.flow = CreateFrame("StatusBar", nil, b)
    b.flow:SetAllPoints(b)
    b.flow:SetFrameLevel(b:GetFrameLevel() + 1)
    b.flow:EnableMouse(false)
    b.flow:SetStatusBarTexture(MEDIA .. "FluidFlow")
    b.flow:SetMinMaxValues(0, 1)
    b.flow:SetValue(1)
    b.flow:SetStatusBarColor(0.12, 0.12, 0.12, 0.34)
    b.flow.texture = b.flow:GetStatusBarTexture()
    if b.flow.texture and b.flow.texture.SetHorizTile then b.flow.texture:SetHorizTile(true) end
    if b.flow.texture and b.flow.texture.AddMaskTexture and b.CreateMaskTexture then
        b.flow.mask = b:CreateMaskTexture()
        b.flow.mask:SetTexture(MEDIA .. "BarShape" .. kind, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        b.flow.mask:SetAllPoints(b)
        b.flow.texture:AddMaskTexture(b.flow.mask)
    end
    -- Keep the glass, rim and text above the moving fluid layer.
    b.surface = CreateFrame("Frame", nil, b)
    b.surface:SetAllPoints(b)
    b.surface:SetFrameLevel(b:GetFrameLevel() + 2)
    b.surface:EnableMouse(false)
    b.gloss = b.surface:CreateTexture(nil, "ARTWORK", nil, 7)
    b.gloss:SetTexture(MEDIA .. "BarGloss" .. kind)
    b.gloss:SetAllPoints(b)
    b.rim = b.surface:CreateTexture(nil, "OVERLAY")
    b.rim:SetTexture(MEDIA .. "BarRim" .. kind)
    b.rim:SetPoint("TOPLEFT", -RIM_PAD, RIM_PAD)
    b.rim:SetPoint("BOTTOMRIGHT", RIM_PAD, -RIM_PAD)
    return b
end

-------------------------------------------------------------------------------
-- Target Style "Nameplate" (0.5.495, the player's: "replace only Target nameplate in the game ... our own target
-- card, but not use spheres, instead let's use horizontal bars. If target goes off camera replace it to middle of the
-- screen ... Only boss targets should be static"). A small card (`follow`: name, health, power) anchored to the
-- target's nameplate, so the game moves it (where a plate is drawn is hidden from add-ons); Blizzard's own plate for
-- the target made invisible (nameplateSelectedAlpha 0); off camera the game keeps the target's plate at the screen's
-- edge toward it (nameplateTargetRadialPosition, nameplateTargetBehindMaxDistance), the card with it; no plate at all
-- (too far, or its kind's nameplates off): the screen's middle. Every target but a boss (NPCs, players, friends:
-- 0.5.497, the player's: "this should work for npcs, friendly players etc like all possible targets"); a boss keeps
-- the card at the top. Its portrait in a gold ring at its left (0.5.497: "add avatar to the target"). The
-- CVars are the game's secure ones: set out of combat while the style is on, the player's own put back after. The
-- following card is a plain frame (a secure one can't move in combat): clicks go to the plate under it.
-------------------------------------------------------------------------------
local PLATE_CVARS = { nameplateSelectedAlpha = "0", nameplateTargetRadialPosition = "1", nameplateTargetBehindMaxDistance = "30" }
local MIDDLE_Y = 140 -- the card in the screen's middle (no plate): this far over its centre
local PLATE_CHECK = 0.2 -- seconds: the plate it follows looked up again (plates are pooled: one can change units)
local PLATE_FACE = 60 -- its portrait (0.5.499, the player's: "the avatar can be 50% bigger"; 40 before)
local PLATE_SCALE = 0.8
local PLATE_COLUMN = 18 + 3 + HEALTH_H + 4 + POWER_H
local PLATE_HEIGHT = math.max(PLATE_FACE, PLATE_COLUMN)
-- A target that dies is cleared from sight (0.5.504, the player's: "when target is dead. just clear target. And if people
-- tries to target then show the card on top"): its card and the card at the top go; the game still has it targeted
-- (ClearTarget is protected: no add-on may call it). A corpse you target yourself shows in the card at the top
-- (`targetedDead`, set on PLAYER_TARGET_CHANGED). 0.5.505, the player's: "we can place the target to where mouse clicked
-- (like how body loot get's opened) so it will eventually somewhere the dead target is": a click on the corpse (the mouse
-- over the target as a button comes up: GLOBAL_MOUSE_UP, UnitIsUnit("mouseover", "target")) puts its card where you
-- clicked, a little over it (`follow.cursor`), the corpse already targeted too; one targeted otherwise (Tab), or where the
-- game hides who's under the mouse (instances), the card at the top.
local CLICK_UP = 34 -- the card this far over a click on a corpse (its bars clear of the cursor and the loot window)
local follow
local function plateStyle() return card ~= nil and ns.db.targetCard and ns.db.targetStyle == "nameplate" end
local function isBoss()
    local boss = call(UnitIsBossMob, "target")
    if num(boss) and boss then return true end
    local class = call(UnitClassification, "target")
    if num(class) and class == "worldboss" then return true end
    local level = call(UnitLevel, "target")
    return num(level) and level < 0
end
local function getCVar(name)
    if C_CVar and C_CVar.GetCVar then return call(C_CVar.GetCVar, name) end
    return call(GetCVar, name)
end
local function getCVarDefault(name)
    if C_CVar and C_CVar.GetCVarDefault then return call(C_CVar.GetCVarDefault, name) end
    return call(GetCVarDefault, name)
end
local function setCVar(name, value)
    if C_CVar and C_CVar.SetCVar then call(C_CVar.SetCVar, name, value) else call(SetCVar, name, value) end
end
local function targetHudBottomInset()
    -- Forever's target radial clamp respects this screen-percentage inset. Reserve the
    -- Spheres HUD's full width, plus half the following card and a gap, as a no-go strip.
    if getCVarDefault("nameplateBottomInset") == nil then return nil end
    local hud = _G.SpheresHUD
    if not (hud and hud.GetTop and UIParent and UIParent.GetHeight) then return nil end
    local top, screenHeight = call(hud.GetTop, hud), call(UIParent.GetHeight, UIParent)
    if not (num(top) and num(screenHeight) and screenHeight > 0) then return nil end
    local hudScale, uiScale = call(hud.GetEffectiveScale, hud), call(UIParent.GetEffectiveScale, UIParent)
    if num(hudScale) and num(uiScale) and uiScale > 0 then top = top * hudScale / uiScale end
    -- Once attached to a nameplate, even our own frame's dimensions can be hidden.
    -- Its fixed layout is known; only the clearance belongs to the HUD's scale.
    local cardHalf = PLATE_HEIGHT * PLATE_SCALE / 2
    local margin = 18 * ns.Sphere.HudScale()
    local inset = math.min(0.94, math.max(0, (top + cardHalf + margin) / screenHeight))
    return inset
end
local function updateTargetHudBottomInset(saved)
    local inset = targetHudBottomInset()
    if not inset then return end
    local name = "nameplateBottomInset"
    if saved.cvars[name] == nil then saved.cvars[name] = getCVar(name) or false end
    local prior = tonumber(saved.cvars[name])
    if prior and prior >= 0 then inset = math.max(inset, prior) end
    setCVar(name, tostring(inset))
end
local function unitPlateCVars(unit)
    local wanted = {}
    local exists = call(UnitExists, unit)
    if not (num(exists) and exists) then return wanted end
    local player = call(UnitIsPlayer, unit)
    if num(player) and player then
        -- Respect the player's own visibility choices. Enabling both categories or
        -- nameplateShowAll just to catch a selected player changes every player's plates.
        return wanted
    end
    local friend = call(UnitIsFriend, "player", unit)
    if num(friend) and friend then
        wanted.nameplateShowFriendlyNpcs = "1"
    else
        -- Blizzard classifies nameplates by friend status. A nonfriend stays in the
        -- enemy category even when UnitIsEnemy/UnitCanAttack both return false.
        wanted.nameplateShowEnemies = "1"
        local controlled = call(UnitPlayerControlled, unit)
        if num(controlled) and controlled then
            wanted.nameplateShowEnemyMinions = "1"
            wanted.nameplateShowEnemyPets = "1"
            wanted.nameplateShowEnemyGuardians = "1"
            wanted.nameplateShowEnemyTotems = "1"
        end
        local classification = call(UnitClassification, unit)
        if num(classification) and classification == "minus" then wanted.nameplateShowEnemyMinus = "1" end
    end
    return wanted
end

local plateAlphaHomes = {}
local function unitIsTarget(unit)
    local same = call(UnitIsUnit, unit, "target")
    if num(same) and same then return true end
    -- Match stable unit identity when two unit tokens refer to the same active plate.
    local guid, targetGUID = call(UnitGUID, unit), call(UnitGUID, "target")
    if num(guid) and num(targetGUID) and guid ~= nil and targetGUID ~= nil and guid == targetGUID then return true end
    return unit == "target"
end
local function shouldHidePlate(unit, forced)
    if unitIsTarget(unit) then return false end
    if forced.nameplateShowAll then return true end
    for name in pairs(unitPlateCVars(unit)) do if forced[name] then return true end end
    return false
end
local function restorePlateAlpha(frame)
    local alpha = plateAlphaHomes[frame]
    if alpha ~= nil then
        if frame.SetAlpha then pcall(frame.SetAlpha, frame, alpha) end
        plateAlphaHomes[frame] = nil
    end
end
local function setPlateAlpha(frame, alpha)
    if not frame then return end
    if alpha == 0 then
        if plateAlphaHomes[frame] == nil then
            local old = frame.GetAlpha and call(frame.GetAlpha, frame)
            plateAlphaHomes[frame] = num(old) and old or 1
        end
        if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
    else
        restorePlateAlpha(frame)
    end
end
local function plateUnit(plate)
    local unit = plate.GetUnit and call(plate.GetUnit, plate)
    if unit then return unit end
    local unitFrame = plate.UnitFrame
    return unitFrame and unitFrame.unit
end
local function targetNamePlate()
    local getPlates = C_NamePlate and C_NamePlate.GetNamePlates
    local plates = getPlates and call(getPlates)
    if type(plates) ~= "table" then return nil end
    for _, plate in pairs(plates) do
        local unit = plateUnit(plate)
        if unit and unitIsTarget(unit) then return plate end
    end
end
local function syncOtherPlates(addedUnit)
    local saved = ns.db.target
    local forced = saved.forcedTargetTypeCvars or {}
    local playerTarget = call(UnitIsPlayer, "target")
    if num(playerTarget) and playerTarget then forced = {} end
    local getPlates = C_NamePlate and C_NamePlate.GetNamePlates
    if not getPlates then return end
    local ok, plates = pcall(getPlates)
    if not ok or type(plates) ~= "table" then return end
    local seen = {}
    local function apply(plate, unit)
        if not plate then return end
        seen[plate] = true
        local unitFrame = plate.UnitFrame
        if unitFrame then seen[unitFrame] = true end
        local hide = unit and shouldHidePlate(unit, forced)
        setPlateAlpha(plate, hide and 0 or 1)
        if unitFrame then setPlateAlpha(unitFrame, hide and 0 or 1) end
    end
    -- The event token is the reliable unit lookup while Blizzard is adding a pooled plate.
    if addedUnit and C_NamePlate.GetNamePlateForUnit then
        local plate = call(C_NamePlate.GetNamePlateForUnit, addedUnit)
        apply(plate, addedUnit)
    end
    for _, plate in pairs(plates) do
        apply(plate, plateUnit(plate))
    end
    -- Plates are pooled. Restore an alpha if its frame left the active pool so it cannot
    -- remain transparent when Blizzard assigns it to another unit later.
    for plate in pairs(plateAlphaHomes) do
        if not seen[plate] then restorePlateAlpha(plate) end
    end
end

local function updateTargetPlateCVars()
    local saved = ns.db.target
    if not saved.cvars then return end
    local wanted = unitPlateCVars("target")
    -- The per-type switches can be on while the client still withholds every plate
    -- outside combat. If no active target plate exists, temporarily use Always Show.
    if next(wanted) and not isBoss() and not targetNamePlate() then wanted.nameplateShowAll = "1" end
    local active = saved.targetTypeCvars or {}
    for name in pairs(active) do
        if not wanted[name] then
            local old = saved.cvars[name]
            if old then setCVar(name, old) end
            saved.cvars[name] = nil
        end
    end
    local forced = {}
    for name, value in pairs(wanted) do
        if saved.cvars[name] == nil then saved.cvars[name] = getCVar(name) or false end
        local previous = saved.cvars[name]
        if previous == "0" or previous == 0 then forced[name] = true end
        setCVar(name, value)
    end
    saved.targetTypeCvars = wanted
    saved.forcedTargetTypeCvars = forced
    syncOtherPlates()
end

local function plateCVars(on) -- out of combat (T.Layout): the style's, or the player's own back
    local saved = ns.db.target
    if on then
        saved.cvars = saved.cvars or {}
        for name, value in pairs(PLATE_CVARS) do
            if saved.cvars[name] == nil then saved.cvars[name] = getCVar(name) or false end
            setCVar(name, value)
        end
        updateTargetHudBottomInset(saved)
        updateTargetPlateCVars()
    elseif saved.cvars then
        for name, old in pairs(saved.cvars) do if old then setCVar(name, old) end end
        saved.cvars, saved.targetTypeCvars, saved.forcedTargetTypeCvars = nil, nil, nil
        syncOtherPlates()
    end
end
-- where the target's card is now: on its plate, in the middle, or the card at the top (its alpha: the card stays
-- registered for the target as before; only shown or not)
local function placeFollow()
    if not follow then return end
    if not (plateStyle() and ns.active and call(UnitExists, "target")) then
        follow:Hide()
        follow.plate, follow.cursor = nil, nil
        return
    end
    local dead = call(UnitIsDead, "target")
    dead = num(dead) and dead and true or false
    if dead and follow.cursor then -- a corpse you clicked: its card where you clicked (placed then: it lies still)
        card:SetAlpha(0)
        follow:Show()
        return
    end
    if dead and not follow.targetedDead then -- it died while targeted: out of sight, as if no target
        follow:Hide()
        follow.plate = nil
        card:SetAlpha(0)
        return
    end
    local static = isBoss() or dead
    card:SetAlpha(static and 1 or 0)
    if static then
        follow:Hide()
        follow.plate = nil
        return
    end
    local plate = targetNamePlate()
    if plate ~= follow.plate or not follow:IsShown() then
        follow.plate = plate
        follow:ClearAllPoints()
        if plate then follow:SetPoint("CENTER", plate, "CENTER", 0, 0)
        else follow:SetPoint("CENTER", UIParent, "CENTER", 0, MIDDLE_Y) end
    end
    follow:Show()
end
-- the target's menu, as Blizzard's togglemenu picks and opens it (SecureTemplates.lua: UnitPopup_OpenMenu), from the
-- card's portrait: a plain button (a secure one would make the card it moves with protected: no moving in combat), so
-- what the game protects in that menu (Set Focus) may be refused; Whisper, Inspect, Invite, Trade are not
local function targetMenu(owner)
    if not UnitPopup_OpenMenu then return end
    local function is(fn, ...) local v = call(fn, ...); return num(v) and v and true or false end
    local which = "TARGET"
    if is(UnitIsUnit, "target", "player") then which = "SELF"
    elseif is(UnitIsUnit, "target", "pet") then which = "PET"
    elseif is(UnitIsPlayer, "target") then
        which = is(UnitInRaid, "target") and "RAID_PLAYER" or is(UnitInParty, "target") and "PARTY" or "PLAYER"
    end
    call(UnitPopup_OpenMenu, which, { ownerFrame = owner, unit = "target" })
end
-- a texture turned over left to right within its own coordinates (an atlas's region)
local function mirror(tex)
    if not tex.GetTexCoord then return end
    local ulx, uly, llx, lly, urx, ury, lrx, lry = tex:GetTexCoord()
    if lrx then tex:SetTexCoord(urx, ury, lrx, lry, ulx, uly, llx, lly) end
end
-- the mouse over the target (a click on it): the game's answer, or false where it's hidden (instances)
local function mouseOnTarget()
    local same = call(UnitIsUnit, "mouseover", "target")
    return num(same) and same and true or false
end
-- the card where the cursor is, a little over it (a click on a corpse)
local function followCursor()
    local x, y = call(GetCursorPosition)
    if not (num(x) and num(y)) then return false end
    local scale = follow:GetEffectiveScale()
    follow.cursor, follow.plate = true, nil
    follow:ClearAllPoints()
    follow:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x / scale, y / scale + CLICK_UP)
    return true
end
local function buildFollow()
    follow = CreateFrame("Frame", nil, UIParent)
    follow:SetFrameStrata("MEDIUM")
    local column = PLATE_COLUMN -- its name over its bars, by the portrait's middle
    follow:SetSize(PLATE_FACE + 6 + BAR_W, PLATE_HEIGHT)
    follow:SetScale(PLATE_SCALE) -- a nameplate's size
    follow:SetClampedToScreen(true) -- at the screen's edge (a plate there is clamped by its middle): all of it seen
    follow:EnableMouse(false)
    follow:Hide()
    -- its portrait at its left: the target's face in a circle on a dark disc, in the card's gold ring
    local face = CreateFrame("Button", nil, follow) -- a click: the target's menu (0.5.500, the player's: "when I click on
    face:SetSize(PLATE_FACE, PLATE_FACE)          -- the target avatar usual target menu should open"); its tooltip on hover
    face:SetPoint("LEFT", 0, 0)
    face:RegisterForClicks("AnyUp")
    face:SetScript("OnClick", function(self) targetMenu(self) end)
    face:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetUnit then call(GameTooltip.SetUnit, GameTooltip, "target") end
        GameTooltip:Show()
    end)
    face:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    face.disc = face:CreateTexture(nil, "BACKGROUND")
    face.disc:SetAllPoints()
    face.disc:SetColorTexture(0.02, 0.015, 0.03, 1)
    face.portrait = face:CreateTexture(nil, "ARTWORK")
    face.portrait:SetPoint("TOPLEFT", 2, -2)
    face.portrait:SetPoint("BOTTOMRIGHT", -2, 2)
    if face.CreateMaskTexture then
        for _, t in ipairs({ face.disc, face.portrait }) do
            local m = face:CreateMaskTexture()
            m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(t)
            t:AddMaskTexture(m)
        end
    end
    face.ring = face:CreateTexture(nil, "OVERLAY")
    A.SetArt(face.ring, GOLD_RING, nil)
    local rs = (PLATE_FACE + 2) / (1 - 2 * RING_IN)
    face.ring:SetSize(rs, rs)
    face.ring:SetPoint("CENTER")
    -- an elite's or rare's dragon round it, as the card's, turned over: its wing out to the left, where the portrait is
    -- (0.5.500, the player's: "add elite indicator too (need to mirror because portrait is now on the left side)")
    face.rankRing = face:CreateTexture(nil, "OVERLAY", nil, 1)
    face.rankRing:SetPoint("CENTER")
    face.rankRing:SetSize(PLATE_FACE + 38 * PLATE_FACE / PORTRAIT, PLATE_FACE + 38 * PLATE_FACE / PORTRAIT)
    face.rankRing:Hide()
    follow.face = face
    -- its name over its bars, at the portrait's right
    follow.name = follow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 0.5.500: "name should be bigger"
    follow.name:SetPoint("TOPLEFT", face, "TOPRIGHT", 6, (column - PLATE_FACE) / 2)
    follow.name:SetWidth(BAR_W)
    follow.name:SetJustifyH("LEFT")
    follow.name:SetWordWrap(false)
    follow.health = bar(follow, HEALTH_H, "Health")
    follow.health:SetPoint("TOPLEFT", follow.name, "BOTTOMLEFT", 0, -3)
    follow.power = bar(follow, POWER_H, "Power")
    follow.power:SetPoint("TOPLEFT", follow.health, "BOTTOMLEFT", 0, -4)
    -- its buffs and debuffs over its name, rows growing up, as the game's plates show them (0.5.500, the player's: "I
    -- should be able to see target buffs debuffs from their nameplate"): the card's own (T.UpdateAuras), laid out twice
    follow.auras = CreateFrame("Frame", nil, follow)
    follow.auras:SetSize(ROW_W, 1)
    follow.auras:SetPoint("BOTTOMLEFT", follow.name, "TOPLEFT", (BAR_W - ROW_W) / 2, 3)
    follow.auras.buttons = {}
    local since = 0
    follow:SetScript("OnUpdate", A.Timed("target nameplate card", function(_, elapsed)
        since = since + (elapsed or 0)
        if since < PLATE_CHECK then return end
        since = 0
        placeFollow()
    end))
end
function T.Follow() return follow end -- the card on its plate (the harness, /spheres debug)
-- a status bar of the card and its twin on the following card, painted alike
local function paintBar(b, r, g, bl)
    b:SetStatusBarColor(r, g, bl)
    b.flow:SetStatusBarColor(r * 0.30, g * 0.30, bl * 0.30, 0.42)
end
local function fillBar(b, v, max)
    if given(max) then b:SetMinMaxValues(0, max); b.flow:SetMinMaxValues(0, max) end
    if given(v) then b:SetValue(v); b.flow:SetValue(v) end
end

function T.Create()
    if card then return end
    card = CreateFrame("Button", "SpheresTarget", UIParent, "SecureUnitButtonTemplate")
    -- Blizzard's TargetSpellBarMixin calls this when a cast begins. Since its parent is
    -- SpheresTarget rather than TargetFrame, skip the TargetFrame-only aura-container path.
    card.ShouldAnchorSpellBarToAuraContainer = function() return false end
    card:SetFrameStrata("MEDIUM")
    card:SetSize(W, 10 + PORTRAIT + 8 + 16 + 14 + 6 + HEALTH_H + 6 + POWER_H + 10)
    card:SetAttribute("unit", "target")
    card:SetAttribute("type1", "target")
    card:SetAttribute("type2", "togglemenu")
    card:RegisterForClicks("AnyUp")
    card:SetMovable(true)
    card:SetClampedToScreen(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", function(f)
        if not inCombat() and (editing or (IsShiftKeyDown() and not ns.db.locked)) then
            f.moving = true
            f:ClearAllPoints()
            local p = ns.db.target.point
            if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, TOP) end
            f:StartMoving()
        end
    end)
    card:SetScript("OnDragStop", function(f)
        if not f.moving then return end
        f:StopMovingOrSizing()
        f.moving = false
        local p, _, rp, x, y = f:GetPoint(1)
        if p and not secret(x) and not secret(y) then ns.db.target.point = { p, rp, x, y } end
    end)
    -- the portrait: a dark disc, the target's face in a circle, with a rank ring when needed
    local face = CreateFrame("Frame", nil, card)
    face:SetSize(PORTRAIT, PORTRAIT)
    face:SetPoint("TOP", 0, -10)
    face.disc = face:CreateTexture(nil, "BACKGROUND")
    face.disc:SetAllPoints()
    face.disc:SetColorTexture(0.02, 0.015, 0.03, 1)
    face.portrait = face:CreateTexture(nil, "ARTWORK")
    face.portrait:SetPoint("TOPLEFT", 3, -3)
    face.portrait:SetPoint("BOTTOMRIGHT", -3, 3)
    if face.CreateMaskTexture then
        for _, t in ipairs({ face.disc, face.portrait }) do
            local m = face:CreateMaskTexture()
            m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(t)
            t:AddMaskTexture(m)
        end
    end
    face.ring = face:CreateTexture(nil, "OVERLAY")
    A.SetArt(face.ring, GOLD_RING, nil)
    local rs = (PORTRAIT + 2) / (1 - 2 * RING_IN)
    face.ring:SetSize(rs, rs)
    face.ring:SetPoint("CENTER")
    face.rankRing = face:CreateTexture(nil, "OVERLAY", nil, 1)
    face.rankRing:SetPoint("CENTER")
    face.rankRing:SetSize(PORTRAIT + 38, PORTRAIT + 38)
    face.rankRing:Hide()
    -- its level, in a badge on the ring (Blizzard's look: a dark disc with a gold number)
    face.badge = CreateFrame("Frame", nil, face)
    face.badge:SetSize(26, 26)
    face.badge:SetPoint("CENTER", face, "BOTTOMRIGHT", -8, 8)
    face.badge:SetFrameLevel(face:GetFrameLevel() + 3)
    face.badge.bg = face.badge:CreateTexture(nil, "BACKGROUND")
    face.badge.bg:SetAllPoints()
    face.badge.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    face.badge.border = face.badge:CreateTexture(nil, "BORDER")
    A.SetBezel(face.badge.border, "Hub") -- match the round hub's current finish
    face.badge.border:SetSize(13 / A.HUB_FRAME_INNER, 13 / A.HUB_FRAME_INNER)
    face.badge.border:SetPoint("CENTER")
    face.badge.number = face.badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    face.badge.number:SetPoint("CENTER", 0, 0)
    card.face = face
    -- name and what it is
    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.name:SetPoint("TOP", face, "BOTTOM", 0, -8)
    card.name:SetWidth(W - 12)
    card.name:SetWordWrap(false)
    card.kind = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.kind:SetPoint("TOP", card.name, "BOTTOM", 0, -2)
    -- health, then power
    card.health = bar(card, HEALTH_H, "Health")
    card.health:SetPoint("TOP", card.kind, "BOTTOM", 0, -6)
    card.health:SetStatusBarColor(HEALTH_FRIENDLY[1], HEALTH_FRIENDLY[2], HEALTH_FRIENDLY[3])
    card.health.text = card.health.surface:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    card.health.text:SetPoint("CENTER")
    card.power = bar(card, POWER_H, "Power")
    card.power:SetPoint("TOP", card.health, "BOTTOM", 0, -6) -- their rims a little apart
    -- its auras, under the bars (T.UpdateAuras); Blizzard's cast bar under them
    card.auras = CreateFrame("Frame", nil, card)
    card.auras:SetSize(PER_ROW * AURA + (PER_ROW - 1) * AURA_GAP, 1)
    card.auras:SetPoint("TOP", card.power, "BOTTOM", 0, -6)
    card.auras:EnableMouse(false)
    card.auras.buttons = {}
    buildFollow() -- Target Style "Nameplate": the card that follows its nameplate
    -- the target's sphere (Target Style "Sphere", experimental): shown by shape()
    if ns.Sphere and ns.Sphere.TargetSphere then
        card.sphere = ns.Sphere.TargetSphere(card)
        card.sphere:Hide()
    end
    card:HookScript("OnEnter", function(f)
        if GameTooltip and GameTooltip.SetUnit then
            GameTooltip:SetOwner(f, A.TooltipAnchor(f))
            GameTooltip:SetUnit("target")
            GameTooltip:Show()
        end
    end)
    card:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local flowElapsed, flowTime = 0, 0
    local flowing = { card.health, card.power }
    card:SetScript("OnUpdate", A.Timed("target card flow", function(_, elapsed)
        flowElapsed = flowElapsed + (elapsed or 0)
        if flowElapsed >= 0.12 then
            flowTime = (flowTime + flowElapsed) % 36
            flowElapsed = 0
            local offset = flowTime / 36
            for _, b in ipairs(flowing) do
                if b.flow and b.flow.texture then
                    b.flow.texture:SetRotation(flowTime * (2 * math.pi / 36))
                    if b.flow.texture.SetTexCoord then b.flow.texture:SetTexCoord(offset, offset + 1, 0, 1) end
                end
            end
        end
    end))

    local ev = CreateFrame("Frame", nil, card)
    pcall(ev.RegisterEvent, ev, "PLAYER_TARGET_CHANGED")
    pcall(ev.RegisterEvent, ev, "NAME_PLATE_UNIT_ADDED") -- the target's plate: the card follows it (Target Style "Nameplate")
    pcall(ev.RegisterEvent, ev, "NAME_PLATE_UNIT_REMOVED")
    pcall(ev.RegisterEvent, ev, "GLOBAL_MOUSE_UP") -- a click on a dead target's body: its card there (Target Style "Nameplate")
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
        "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_PORTRAIT_UPDATE", "UNIT_CLASSIFICATION_CHANGED", "UNIT_FACTION",
        "UNIT_AURA" }) do
        if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, e, "target") else pcall(ev.RegisterEvent, ev, e) end
    end
    ev:SetScript("OnEvent", A.Timed("target card events", function(_, event, who)
        if not ns.active or not ns.db.targetCard then return end
        if event == "PLAYER_TARGET_CHANGED" then
            if follow then -- a new target: its own card; a corpse you click, its card there; one you Tab to, at the top
                follow:Hide()
                follow.cursor = nil
                local dead = call(UnitIsDead, "target")
                follow.targetedDead = num(dead) and dead and true or false
                if follow.targetedDead and plateStyle() and mouseOnTarget() then followCursor() end
            end
            T.Update()
            if not inCombat() and plateStyle() then updateTargetPlateCVars()
            elseif plateStyle() then syncOtherPlates() end
            return
        end
        if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
            -- Blizzard can create plates for the newly enabled category after the target
            -- change, so apply the target-only visibility as each pooled plate appears.
            syncOtherPlates(event == "NAME_PLATE_UNIT_ADDED" and who or nil)
            return placeFollow()
        end
        if event == "GLOBAL_MOUSE_UP" then -- on a dead target's body: its card where you clicked
            if follow and plateStyle() and mouseOnTarget() then
                local dead = call(UnitIsDead, "target")
                if num(dead) and dead and followCursor() then placeFollow() end
            end
            return
        end
        if who ~= "target" then return end
        local part = PARTS[event]
        if part then T[part]() else T.Update() end
        if event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED" then
            if not inCombat() and plateStyle() then updateTargetPlateCVars() end
        end
    end, true))
end

-- Its shape for its style (T.Layout, out of combat: the card is protected): today's card, or the
-- target's sphere with the portrait in its centre (Target Style "Sphere", experimental).
local function sphereStyle() return card ~= nil and card.sphere ~= nil and ns.db.targetStyle == "sphere" end
local function shape()
    local sphere, face = sphereStyle(), card.face
    local size = sphere and card.sphere.avatarSize or PORTRAIT
    face:ClearAllPoints()
    card.name:ClearAllPoints()
    card.auras:ClearAllPoints()
    if sphere then
        local s = card.sphere
        s:ClearAllPoints()
        s:SetPoint("TOP", card, "TOP", 0, 0)
        s:Show()
        face:SetPoint("CENTER", s, "CENTER")
        face:SetFrameLevel(s.avatarLevel)
        card.name:SetPoint("TOP", s, "BOTTOM", 0, 2)
        card.auras:SetPoint("TOP", card.kind, "BOTTOM", 0, -6)
        card.health:Hide()
        card.power:Hide()
        card:SetSize(math.max(W, s:GetWidth()), s:GetHeight() + 2 + 16 + 14 + 6)
    else
        if card.sphere then card.sphere:Hide() end
        face:SetPoint("TOP", 0, -10)
        face:SetFrameLevel(card:GetFrameLevel() + 1)
        card.name:SetPoint("TOP", face, "BOTTOM", 0, -8)
        card.auras:SetPoint("TOP", card.power, "BOTTOM", 0, -6)
        card.health:Show()
        card.power:Show()
        card:SetSize(W, 10 + PORTRAIT + 8 + 16 + 14 + 6 + HEALTH_H + 6 + POWER_H + 10)
    end
    face:SetSize(size, size)
    local k = size / PORTRAIT
    local rs = (size + 2) / (1 - 2 * RING_IN)
    face.ring:SetSize(rs, rs)
    face.rankRing:SetSize(size + 38 * k, size + 38 * k)
    face.badge:ClearAllPoints()
    face.badge:SetPoint("CENTER", face, "BOTTOMRIGHT", -8 * k, 8 * k)
    face.badge:SetFrameLevel(face:GetFrameLevel() + 3)
end

-------------------------------------------------------------------------------
-- What it shows (in combat too: plain frames and status bars)
-------------------------------------------------------------------------------
function T.UpdatePortrait()
    if card and SetPortraitTexture then pcall(SetPortraitTexture, card.face.portrait, "target") end
    if follow and SetPortraitTexture then pcall(SetPortraitTexture, follow.face.portrait, "target") end
end

function T.Update()
    if not card or not call(UnitExists, "target") then return end
    card.editPreview = nil
    local face = card.face
    T.UpdatePortrait()
    local level = call(UnitLevel, "target")
    if given(level) and not secret(level) and level < 0 then level = "??" end
    face.badge.number:SetText(pick(level, ""))
    card.name:SetText(pick(call(UnitName, "target"), ""))
    local reaction = call(UnitReaction, "target", "player")
    local c = (not secret(reaction) and reaction and REACTION[reaction]) or NAME_GOLD
    local isPlayer = call(UnitIsPlayer, "target")
    if not secret(isPlayer) and isPlayer then c = NAME_PLAYER end
    card.name:SetTextColor(c[1], c[2], c[3])
    follow.name:SetText(pick(call(UnitName, "target"), ""))
    follow.name:SetTextColor(c[1], c[2], c[3])
    local class = call(UnitClassification, "target")
    card.kind:SetText((not secret(class) and KIND[class]) or "")
    local rankAtlas = not secret(class) and RANK_RINGS[class]
    if rankAtlas and A.AtlasOK(rankAtlas) then
        face.rankRing:SetAtlas(rankAtlas)
        face.rankRing:Show()
        follow.face.rankRing:SetAtlas(rankAtlas)
        mirror(follow.face.rankRing)
        follow.face.rankRing:Show()
    else
        face.rankRing:Hide()
        follow.face.rankRing:Hide()
    end
    -- grey once someone else has tagged it (Blizzard's rule: not a player's, and tap-denied)
    local tapped = call(UnitIsTapDenied, "target")
    local controlled = call(UnitPlayerControlled, "target")
    local hc
    if not secret(tapped) and tapped and not (not secret(controlled) and controlled) then
        hc = TAPPED_COLOR
    elseif not secret(reaction) and reaction and reaction <= 3 then
        hc = HEALTH_HOSTILE
    elseif not secret(reaction) and reaction == 4 then
        hc = HEALTH_NEUTRAL
    else
        hc = HEALTH_FRIENDLY
    end
    paintBar(card.health, hc[1], hc[2], hc[3])
    paintBar(follow.health, hc[1], hc[2], hc[3])
    card.health.tapped = hc == TAPPED_COLOR
    if sphereStyle() then -- its health red, as yours; what it is to you: its name's colour (0.5.470)
        local dead = call(UnitIsDead, "target")
        ns.Sphere.TargetSphereDead(card.sphere, not secret(dead) and dead or false)
    end
    T.UpdateHealth()
    T.UpdatePower()
    T.UpdateAuras()
    placeFollow()
end

-- health and power: hidden or not, straight in
function T.UpdateHealth()
    if not card then return end
    local hp, hpMax = call(UnitHealth, "target"), call(UnitHealthMax, "target")
    fillBar(card.health, hp, hpMax)
    fillBar(follow.health, hp, hpMax)
    card.health.text:SetText(pick(hp, ""))
    if sphereStyle() then ns.Sphere.TargetSphereHealth(card.sphere, hp, hpMax) end
end

function T.UpdatePower()
    if not card then return end
    local pt, token = call(UnitPowerType, "target")
    if secret(pt) then pt = nil end
    if secret(token) then token = nil end
    local pc = token and PowerBarColor and PowerBarColor[token]
    local r, g, b = MANA_COLOR[1], MANA_COLOR[2], MANA_COLOR[3]
    if token ~= "MANA" and pc then r, g, b = pc.r, pc.g, pc.b end
    paintBar(card.power, r, g, b)
    paintBar(follow.power, r, g, b)
    local p, pMax = call(UnitPower, "target", pt), call(UnitPowerMax, "target", pt)
    fillBar(card.power, p, pMax)
    fillBar(follow.power, p, pMax)
    if sphereStyle() then ns.Sphere.TargetSpherePower(card.sphere, p, pMax, pt, token) end
end

-- In Edit Mode, keep a draggable preview visible even when there is no current target.
function T.SetEditMode(active)
    editing = active and true or false
    if not card or not ns.db or not ns.db.targetCard then return end
    if editing then
        if UnregisterUnitWatch then UnregisterUnitWatch(card) end
        if call(UnitExists, "target") then
            T.Update()
        else
            card.editPreview = true
            if SetPortraitTexture then pcall(SetPortraitTexture, card.face.portrait, "player") end
            card.face.badge.number:SetText("")
            card.face.rankRing:Hide()
            card.name:SetText("Target Preview")
            card.name:SetTextColor(0.85, 0.82, 0.72)
            card.kind:SetText("Drag in Edit Mode")
            card.health:SetMinMaxValues(0, 1)
            card.health:SetValue(0.72)
            card.health.flow:SetMinMaxValues(0, 1)
            card.health.flow:SetValue(0.72)
            card.power:SetMinMaxValues(0, 1)
            card.power:SetValue(0.55)
            card.power.flow:SetMinMaxValues(0, 1)
            card.power.flow:SetValue(0.55)
            if sphereStyle() then
                ns.Sphere.TargetSphereDead(card.sphere, false)
                ns.Sphere.TargetSphereHealth(card.sphere, 0.72, 1)
                ns.Sphere.TargetSpherePower(card.sphere, 0.55, 1, false, "MANA")
            end
            card:Show()
        end
    else
        card.editPreview = nil
    end
end

-------------------------------------------------------------------------------
-- Its auras
-------------------------------------------------------------------------------
local function auraButton(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(AURA, AURA)
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetPoint("TOPLEFT", -1, 1)
    b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    if b.cd.SetReverse then b.cd:SetReverse(true) end
    if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 2, -1)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if not (GameTooltip.SetUnitAura and call(GameTooltip.SetUnitAura, GameTooltip, "target", self.index, self.filter) ~= false) then
            GameTooltip:SetText(self.key == "debuff" and "Debuff" or "Buff", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:Hide()
    return b
end

-- One aura into its button: what's hidden goes straight into widgets, or is left out.
local BUFF_EDGE, DEBUFF_EDGE, NO_TYPES = { r = 0, g = 0, b = 0 }, { r = 0.8, g = 0, b = 0 }, {}
local function paintAura(b, a, key)
    pcall(b.icon.SetTexture, b.icon, a.icon) -- hidden or not
    local id = a.auraInstanceID
    local U = C_UnitAuras
    local count
    if num(id) and U.GetAuraApplicationDisplayCount then
        count = call(U.GetAuraApplicationDisplayCount, "target", id, 2)
    elseif num(a.applications) and a.applications > 1 then
        count = a.applications
    end
    b.count:SetText(pick(count, ""))
    local timed = false
    if num(id) and U.GetAuraDuration and b.cd.SetCooldownFromDurationObject then
        local d = call(U.GetAuraDuration, "target", id)
        if d then timed = pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) end
    end
    if not timed and num(a.duration) and num(a.expirationTime) and a.duration > 0 then
        b.cd:SetCooldown(a.expirationTime - a.duration, a.duration)
        timed = true
    end
    if not timed then b.cd:Clear() end
    local c = BUFF_EDGE
    if key == "debuff" then
        local types = DebuffTypeColor or NO_TYPES
        c = (num(a.dispelName) and types[a.dispelName]) or types.none or DEBUFF_EDGE
    end
    b.edge:SetColorTexture(c.r, c.g, c.b, 1)
end

local shownAuras = { debuff = 0, buff = 0 }
-- kept between updates (UNIT_AURA comes often in a fight): each aura's entry, and each row's count
local entries, rowCounts = {}, {}
-- the auras read into a box's buttons, rows of PER_ROW centred: down from its top (the card), or up from its bottom
-- (the card on the nameplate: over its name)
local function layAuras(box, count, rows, up)
    for k = 1, count do
        local e = entries[k]
        local b = box.buttons[k] or auraButton(box)
        box.buttons[k] = b
        b.index, b.filter, b.key = e.index, e.filter, e.key
        paintAura(b, e.a, e.key)
        local inRow = rowCounts[e.row + 1]
        local x = (ROW_W - (inRow * AURA + (inRow - 1) * AURA_GAP)) / 2 + e.col * (AURA + AURA_GAP)
        b:ClearAllPoints()
        if up then b:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", x, e.row * (AURA + AURA_GAP))
        else b:SetPoint("TOPLEFT", box, "TOPLEFT", x, -e.row * (AURA + AURA_GAP)) end
        b:Show()
    end
    for k = count + 1, #box.buttons do box.buttons[k]:Hide() end
    box:SetHeight(math.max(1, rows * (AURA + AURA_GAP) - (rows > 0 and AURA_GAP or 0)))
end
function T.UpdateAuras()
    local box = card and card.auras
    if not box then return end
    local U = C_UnitAuras
    local count = 0
    for _, kind in ipairs(AURA_KINDS) do
        local n = 0
        if U and U.GetAuraDataByIndex and call(UnitExists, "target") then
            for i = 1, 40 do
                if n >= kind.max then break end
                local a = call(U.GetAuraDataByIndex, "target", i, kind.filter)
                if type(a) ~= "table" then break end
                n, count = n + 1, count + 1
                local e = entries[count]
                if not e then e = {}; entries[count] = e end
                e.a, e.key, e.index, e.filter, e.first = a, kind.key, i, kind.filter, n == 1
            end
        end
        shownAuras[kind.key] = n
    end
    -- rows of PER_ROW, centred; the buffs start a row of their own
    for r = #rowCounts, 1, -1 do rowCounts[r] = nil end
    local x, y = 0, 0
    for k = 1, count do
        local e = entries[k]
        if k > 1 and (x >= PER_ROW or (e.first and e.key == "buff")) then
            x, y = 0, y + 1
        end
        rowCounts[y + 1] = (rowCounts[y + 1] or 0) + 1
        e.col, e.row = x, y
        x = x + 1
    end
    local rows = count > 0 and (y + 1) or 0
    layAuras(box, count, rows, false)
    if follow then layAuras(follow.auras, count, rows, true) end
    for k = 1, count do entries[k].a = nil end -- the game's tables: not kept past this update
end

-------------------------------------------------------------------------------
-- Blizzard's target frame out of sight; its cast bar under ours (out of combat)
-------------------------------------------------------------------------------
local function castBar()
    local retail = ns.Retail
    if retail and retail.TargetCastBar then return retail.TargetCastBar() end
    return TargetFrameSpellBar or (TargetFrame and TargetFrame.spellbar)
end

function T.PlaceCastBar()
    local cb = castBar()
    if not (cb and card) or inCombat() then return end
    placingCast = true
    if not castParent then castParent = cb:GetParent() end
    cb:SetParent(card)
    cb:ClearAllPoints()
    cb:SetPoint("TOP", card.auras, "BOTTOM", 0, -8) -- under the auras (none: just under the bars)
    if cb.SetWidth then cb:SetWidth(BAR_W) end
    placingCast = false
    if not cb.spheresHooked and hooksecurefunc then
        cb.spheresHooked = true
        -- Blizzard moves it under the target's auras now and then: back under the card
        hooksecurefunc(cb, "SetPoint", function()
            if not placingCast and castParent and ns.db.targetCard then T.PlaceCastBar() end
        end)
    end
end

-- Blizzard's breath, fatigue and feign-death bars (MirrorTimerContainer, Edit Mode's timer bars, 100
-- down at the top centre: 0.5.476, with the card up there, the card's name stood under the Breath bar)
-- under the card's cast bar while Edit Mode has them in their default place; back with the card off.
-- Not protected: in combat too, Blizzard placing them again (a SetPoint hook).
local timersHome, placingTimers
function T.PlaceTimers()
    local c = MirrorTimerContainer
    if not (c and card) or (inCombat() and c:IsProtected()) then return end
    if c.IsInDefaultPosition and not c:IsInDefaultPosition() then return end -- moved in Edit Mode: theirs
    if not timersHome then timersHome = { c:GetPoint(1) } end
    placingTimers = true
    c:ClearAllPoints()
    local cb = castBar()
    if cb and cb:GetParent() == card then c:SetPoint("TOP", cb, "BOTTOM", 0, -10)
    else c:SetPoint("TOP", card.auras, "BOTTOM", 0, -10) end
    placingTimers = false
    if not c.spheresHooked and hooksecurefunc then
        c.spheresHooked = true
        hooksecurefunc(c, "SetPoint", function()
            if not placingTimers and ns.db.targetCard then T.PlaceTimers() end
        end)
    end
end
local function timersBack()
    local c = MirrorTimerContainer
    if not (c and timersHome) then return end
    placingTimers = true
    c:ClearAllPoints()
    if c.ApplySystemAnchor then c:ApplySystemAnchor() -- Edit Mode's own place
    else c:SetPoint(timersHome[1], timersHome[2], timersHome[3], timersHome[4], timersHome[5]) end
    placingTimers = false
    timersHome = nil
end

function T.Layout()
    if not card then return true end
    if inCombat() then return false end
    local db = ns.db
    local on = db.targetCard
    local f = TargetFrame
    if f then
        if on and not targetParent then
            targetHolder = targetHolder or CreateFrame("Frame")
            targetHolder:Hide()
            targetParent = f:GetParent()
            f:SetParent(targetHolder)
        elseif not on and targetParent then
            f:SetParent(targetParent)
            targetParent = nil
        end
    end
    if on then
        shape()
        local plates = db.targetStyle == "nameplate"
        plateCVars(plates)
        card:EnableMouse(not plates) -- the card at the top is often invisible then: no clicks where nothing shows
        if not plates then card:SetAlpha(1) end
        placeFollow()
        card:ClearAllPoints()
        local pt = db.target.point
        if pt then card:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else card:SetPoint("TOP", UIParent, "TOP", 0, TOP) end
        if editing then
            if UnregisterUnitWatch then UnregisterUnitWatch(card) end
        elseif RegisterUnitWatch then
            RegisterUnitWatch(card)
        end
        T.PlaceCastBar()
        T.PlaceTimers()
        if editing then T.SetEditMode(true) else T.Update() end
    else
        if UnregisterUnitWatch then UnregisterUnitWatch(card) end
        card:Hide()
        plateCVars(false)
        card:SetAlpha(1)
        placeFollow()
        timersBack()
        local cb = castBar()
        if cb and castParent then
            placingCast = true
            cb:SetParent(castParent)
            placingCast = false
            castParent = nil
        end
    end
    return true
end

function T.Hidden() return targetParent ~= nil end

function T.Debug()
    local cb = castBar()
    -- the auras read, and drawn: buttons showing, the row's frame visible, how far under the card's top
    local drawn, below = 0, "?"
    if card then
        for _, b in ipairs(card.auras.buttons) do if b:IsVisible() then drawn = drawn + 1 end end
        local top, rowTop = card:GetTop(), card.auras:GetTop()
        if top and rowTop and not secret(top) and not secret(rowTop) then below = string.format("%.0f", top - rowTop) end
    end
    return string.format("target card: %s (%s), Blizzard's target frame %s, cast bar %s, %s, %d debuffs and %d buffs read,"
        .. " %d aura buttons drawn, their row %s, %s under the card's top",
        ns.db.targetCard and "on" or "off", sphereStyle() and "sphere, experimental" or plateStyle() and ("nameplate: "
            .. (follow:IsShown() and (follow.plate and "on its plate" or "in the middle") or "the card at the top")) or "card",
        T.Hidden() and "hidden" or "shown",
        cb and (cb:GetParent() == card and "under the card" or "Blizzard's") or "none",
        card and (card:IsShown() and "showing a target" or "no target") or "not built",
        shownAuras.debuff, shownAuras.buff, drawn, card and (card.auras:IsVisible() and "visible" or "hidden") or "none", below)
end
