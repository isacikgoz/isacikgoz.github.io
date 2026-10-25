local ADDON, ns = ...

--[[
Spheres: Diablo's two orbs at the bottom of the screen, on Roth UI's art and layout (its frame,
the winged lion and griffin in front of the orbs). The left orb is two pieces of glass, your health
(60%) and mana (40%), the right one your minimap; two rows of action buttons in the frame between them, your experience along its top;
every other bar, the game menu, the bags, Paladin spell fans and Druid Forms as rings
whose buttons sit round the orbs.

  * Sphere.lua: the orbs, Roth's art, the minimap (its header out of sight), the player frame
  * Auras.lua: your buffs and debuffs centred above the action bars (or top right), the stack over
    the frame (pet bar, buffs, debuffs, cast bar, Blizzard's bottom container)
  * Chat.lua, Tracker.lua: Action Ring's quieter chat and objectives folded at login
  * Track.lua: the experience and reputation bars in the frame's slots
  * Bars.lua: the two rows (Bar 1 with its pages, Bar 2), Blizzard's bars out of sight
  * Ring.lua: the rings (Action Ring's, docked round the orbs)

An alternative to Action Ring, built from its code: both draw the bottom of the screen, so
Spheres stays off while Action Ring is enabled.
]]

local VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"
ns.VERSION = VERSION

local R, B, S, T, K, U, Chat = ns.Ring, ns.Bars, ns.Sphere, ns.Target, ns.Track, ns.Auras, ns.Chat
local A = ns.Art

local DEFAULTS = {
    scale = 1,             -- the whole bottom of the screen (Roth UI's size at 1)
    size = 40,             -- a ring's slots
    radius = 84,           -- a spell fan over a slot: how far its spells sit
    numberKeys = true,     -- while a ring is open, 1-9, 0, -, = use its slots 1-12
    hideEmpty = true,      -- an action ring shows its filled slots only (all while dragging)
    locked = false,        -- no dragging rings round the orbs
    minimap = true,        -- Blizzard's minimap in the right orb
    sphereValuesAlways = false, -- show health, mana and map coordinates without hovering
    slosh = "on",          -- the liquids slosh as you turn, move and fall ("off": still)
    crackedGlass = false,  -- a big blow cracks your health's glass, and your pet's (opt-in)
    hidePlayerFrame = true, -- Blizzard's player frame hidden (the left orb shows your health)
    statueFinish = "modern", -- none: hidden statues; otherwise matching frame and statue finishes
    statueLayout = { x = 0, y = 0, scale = 1 }, -- shared mirrored offsets; vertical zero is the previous -7 slider position
    questArrow = true,     -- the minimap's quest arrow drawn again over the griffin, its head solid; off: see-through
    hideStanceBar = true,  -- Blizzard's aura or form buttons hidden while their fan is in use
    targetCard = true,     -- the target as a card top centre (Blizzard's target frame hidden)
    targetStyle = "nameplate", -- the card's look: "nameplate" (on its nameplate; the default since 0.5.502), "card" or "sphere" (experimental: a sphere as yours, its portrait in the centre)
    chatButtons = false,   -- the buttons beside the chat (menu, channels, voice, friends): Action Ring's chat
    chatBackground = false, -- the chat window's background tint
    combatLog = false,     -- the Combat Log tab
    chatScrollLeft = true, -- the chat's scroll bar on its left, where the buttons were
    shortChannels = true,  -- [1] for [1. General - Durotar]
    chatTyping = true,     -- the chat's input box only while typing (Blizzard's Classic chat style)
    chatTopToBottom = true, -- new chat lines appear at the top and older lines flow down
    chatTabsOnHover = true, -- the chat's tabs (General ...) only while the mouse is over it
    foldObjectives = true, -- the objectives list starts folded at login and /reload
    objectivesIcon = true, -- folded, it's an icon the size of a buff (its own fold button)
    aurasAbove = true,     -- your buffs and debuffs centred above the action bars (off: top right)
    target = {},           -- { point } once dragged
    hudPoint = { x = 0, y = 0 }, -- the whole HUD's bottom-center position, movable in Edit Mode
    rings = {},            -- by ring id: { shown, dock = { side, angle }, lastSlot, current, collar }
}
ns.DEFAULTS = DEFAULTS
local SCHEMA = 11
ns.SCHEMA = SCHEMA

-- Saved before this version's layout (schema 1, 0.1-0.3: a halo round each sphere): the rings'
-- places were in the halos, the backdrop band and the button size are gone.
local function migrate(db)
    db.targetDirectionLine = nil -- removed experiment: client positioning restrictions prevent its use
    if (db.schema or 1) < 2 then
        for _, c in pairs(db.rings or {}) do
            if type(c) == "table" then c.dock = nil end
        end
        db.backdrop, db.buttonSize = nil, nil
    end
    if (db.schema or 1) < 3 then
        db.statues = false -- hide existing installations too; the setting can turn them back on
    end
    if (db.schema or 1) < 4 then
        db.statues = true -- restore the original statues after the temporary hidden preview
    end
    if (db.schema or 1) < 5 then
        if db.statues == false then db.statueFinish = "none" end
        db.statues = nil
    end
    if (db.schema or 1) < 6 and db.targetStyle == "card" then
        db.targetStyle = "nameplate" -- the default now (0.5.502, the player's: "let's use nameplate as the default target frame")
    end
    if (db.schema or 1) < 7 and type(db.hudPoint) == "table" then
        -- 0.5.551-0.5.553 stored GetCenter's screen coordinate as a center-relative x offset.
        local width = UIParent and UIParent.GetWidth and UIParent:GetWidth()
        local x = tonumber(db.hudPoint.x)
        if x and x > 0 and width and width > 0 then db.hudPoint.x = x - width / 2 end
    end
    if (db.schema or 1) < 8 then
        local old = db.statueLayout
        local left, right = type(old) == "table" and old.left, type(old) == "table" and old.right
        if type(left) == "table" or type(right) == "table" then
            local lx, ly, ls = tonumber(left and left.x) or 0, tonumber(left and left.y) or 0,
                tonumber(left and left.scale) or 1
            local rx, ry, rs = tonumber(right and right.x) or 0, tonumber(right and right.y) or 0,
                tonumber(right and right.scale) or 1
            local adjusted = lx ~= 0 or ly ~= 0 or ls ~= 1 or rx ~= 0 or ry ~= 0 or rs ~= 1
            db.statueLayout = {
                x = (rx - lx) / 2,
                y = adjusted and (ly + ry) / 2 or 4,
                scale = (ls + rs) / 2,
            }
        elseif type(old) ~= "table" or old.y == nil then
            db.statueLayout = { x = 0, y = 4, scale = 1 } -- converted to vertical zero below
        end
    end
    if (db.schema or 1) < 9 then
        local layout = db.statueLayout
        if type(layout) == "table" then
            layout.y = (tonumber(layout.y) or 4) - 4 -- +4 is now the neutral vertical alignment
        end
        local point = db.hudPoint
        if type(point) == "table" and tonumber(point.y) == -10 then
            point.y = 0 -- the previous default left a gap under the frame
        end
    end
    if (db.schema or 1) < 10 and type(db.statueLayout) == "table" then
        db.statueLayout.y = (tonumber(db.statueLayout.y) or 0) + 7 -- old -7 is the new zero position
    end
    if (db.schema or 1) < 11 and db.statueFinish == "brass" then
        db.statueFinish = "charcoal" -- Brass is deprecated; retain the current muted finish
    end
end
ns.migrate = migrate
-- Shown from the start: Action Bar 3's ring, the game menu, the bags, the spell fans (a fan in a
-- slot shows once its macro is there).
local SHOWN_FIRST = { bar3 = true, menu = true, bags = true, seals = true, blessings = true, auras = true, forms = true }

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then dst[k] = {} copyDefaults(dst[k], v) else dst[k] = v end
        end
    end
end
ns.copyDefaults = copyDefaults

function ns.FillRings(db)
    for _, def in ipairs(R.DEFS) do
        local c = db.rings[def.id]
        if not c then
            c = {}
            db.rings[def.id] = c
        end
        if c.shown == nil then c.shown = SHOWN_FIRST[def.id] or false end
        if def.kind == "spells" and c.collar == nil then c.collar = def.group.collar or false end
    end
end

local function say(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff4fd1c5Spheres|r " .. msg) end
end
ns.Say = say

-- Action Ring draws the same part of the screen: one of them at a time.
local function actionRingOn()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded("ActionRing") and true or false
end

-- Everything in place (after the fight, when in one): the rows, the orbs and the art, the
-- experience bars (they pick the frame, whose top the rings open above), the rings docked round
-- the orbs.
function ns.Apply()
    if not ns.db or not ns.active then return end
    A.UpdateBezelStyle()
    local okBars = B.Layout()
    local okSphere = S.Layout()
    K.Update() -- the experience bars pick the frame, whose top the stack stands on
    local okAuras = U.Layout()
    local okRings = R.Layout()
    local okTarget = T.Layout()
    local okChat = Chat.Apply()
    ns.Tracker.Apply()
    if okBars == false or okSphere == false or okAuras == false or okRings == false or okTarget == false or okChat == false then
        say("changes apply when combat ends.")
    end
    if ns.Settings then ns.Settings.Refresh() end
end

function ns.SetRingShown(id, on)
    local c = ns.db.rings[id]
    if not c then return false end
    c.shown = on and true or false
    ns.Apply()
    return true
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE",
    "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_BINDINGS",
    "CURSOR_CHANGED", "PLAYER_TARGET_CHANGED", "BAG_UPDATE_DELAYED", "UNIT_PORTRAIT_UPDATE",
    "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "UPDATE_MACROS", "SPELLS_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
    "VARIABLES_LOADED", "QUEST_WATCH_LIST_CHANGED", "ACTION_RANGE_CHECK_UPDATE", "ACTION_USABLE_CHANGED",
}
for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
-- the events after which the rows' cooldowns are painted again (each asks the game for a new
-- duration object per button: Bars.lua B.Update)
local COOLDOWN_EVENTS = { ACTIONBAR_UPDATE_COOLDOWN = true, SPELL_UPDATE_CHARGES = true,
    PLAYER_EQUIPMENT_CHANGED = true, BAG_UPDATE_DELAYED = true, VARIABLES_LOADED = true }
-- your health and power: the left sphere (in combat too)
local unit = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_COMBAT", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_LEVEL" }) do
    if unit.RegisterUnitEvent then pcall(unit.RegisterUnitEvent, unit, e, "player") else pcall(unit.RegisterEvent, unit, e) end
end
-- your pet's blows too: a big one cracks its glass (Sphere.lua CRACK)
if unit.RegisterUnitEvent then pcall(unit.RegisterUnitEvent, unit, "UNIT_COMBAT", "player", "pet") end
unit:SetScript("OnEvent", A.Timed("health and power events", function(_, event, who, action, _, amount)
    if not ns.active then return end
    if event == "UNIT_COMBAT" and who == "pet" then
        if action == "WOUND" then S.Wound("pet", amount) end
        return
    end
    if who ~= nil and who ~= "player" then return end
    -- what was spent and what changed: only what comes in lifts a liquid (Sphere.lua SURGE)
    if event == "UNIT_COMBAT" then
        if action == "HEAL" then
            S.LiquidHealed()
            S.ShowHeal(amount)
        elseif action == "WOUND" then
            S.LiquidSpent("health")
            S.ShowDamage(amount)
            S.Wound("player", amount)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        S.LiquidSpent("power")
    elseif event == "UNIT_LEVEL" then
        S.UpdateLevel() -- the game's own level has caught up with PLAYER_LEVEL_UP
    else
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
            S.LiquidChanged("power")
            S.UpdatePower() -- as it regenerates, several times a second: the power alone
            return
        end
        if event == "UNIT_HEALTH" then S.LiquidChanged("health") end
        S.UpdateLeft()
    end
end, true))

-- Your form and Bar 1's page, for UPDATE_SHAPESHIFT_FORM: whether either changed since it last came.
local lastForm, lastPage
local function formOrPageChanged()
    local form, page = A.call(GetShapeshiftForm), B.Page()
    if A.secret(form) or A.secret(page) then return true end
    if form == lastForm and page == lastPage then return false end
    lastForm, lastPage = form, page
    return true
end

ev:SetScript("OnEvent", A.Timed("game events", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then
            if ns.active then
                if arg1 == "Blizzard_CombatLog" then Chat.Apply() end -- the Combat Log tab arrives
                ns.Tracker.OnAddOnLoaded(arg1)
            end
            return
        end
        SpheresDB = SpheresDB or {}
        local db = SpheresDB
        migrate(db)
        copyDefaults(db, DEFAULTS)
        db.schema = SCHEMA
        ns.FillRings(db)
        ns.db = db
        if not actionRingOn() then Chat.ApplyStyle() end -- before Blizzard applies the chat style
    elseif event == "VARIABLES_LOADED" then
        if ns.db and not actionRingOn() then Chat.ApplyStyle() end -- the account's settings may have put chatStyle back
    elseif event == "PLAYER_LOGIN" then
        if actionRingOn() then
            say("is off while Action Ring is enabled: both draw the bottom of the screen. Disable one of them in the AddOns list.")
            return
        end
        ns.active = true
        ns.Spells.Scan()
        S.Create()
        K.Create()
        B.Create()
        R.CreateAll()
        T.Create()
        Chat.Create()
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("EditMode.Enter", function()
                S.SetEditMode(true)
                T.SetEditMode(true)
            end, ns)
            -- Restore the target unit watch and normal visibility when Edit Mode closes.
            EventRegistry:RegisterCallback("EditMode.Exit", function()
                S.SetEditMode(false)
                T.SetEditMode(false)
                ns.Apply()
            end, ns)
        end
        ns.Apply()
        S.UpdateCombat()
        if ns.Settings then ns.Settings.Create() end
    elseif not ns.active then
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.Apply()
        S.UpdateCombat()
        S.UpdateMagic()
        ns.Tracker.OnEnteringWorld(arg1, arg2) -- login, reload
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        S.UpdateLeft()
    elseif event == "PLAYER_LEVEL_UP" then
        S.UpdateLevel(arg1) -- the new level: UnitLevel still answers the old one now
    elseif event == "PLAYER_UPDATE_RESTING" then
        S.UpdateCombat()
    elseif event == "PLAYER_REGEN_DISABLED" then
        S.UpdateCombat(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        S.UpdateCombat(false)
        B.OnCombatEnd()
        if S.Pending() then S.Layout() end
        if U.Pending() then U.Layout() end
        R.OnCombatEnd()
        T.Layout()
        Chat.OnCombatEnd()
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        R.OnSlotChanged(arg1)
        B.Update()
    elseif event == "CURSOR_CHANGED" then
        R.OnCursorChanged()
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        ns.Apply()
    elseif event == "UPDATE_MACROS" or event == "SPELLS_CHANGED" then
        if event == "SPELLS_CHANGED" then ns.Spells.Scan() end
        if R.HasSpellFans() then R.LayoutSoon() end
        B.Update(true) -- a macro's name or a spell's icon on the rows (no timer repaints them)
    elseif event == "UPDATE_SHAPESHIFT_FORM" and not formOrPageChanged() then
        return -- the game sends it again and again with neither changed: a layout is ~14 KB of garbage
    elseif event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" or event == "UPDATE_VEHICLE_ACTIONBAR"
        or event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "UPDATE_SHAPESHIFT_FORM" then
        B.Update() -- Bar 1's page
        if R.HasSpellFans() then R.LayoutSoon() end -- a fan's macro may be on that page
    elseif event == "QUEST_WATCH_LIST_CHANGED" then
        ns.Tracker.Style() -- the number on the folded icon
    elseif event == "UPDATE_BINDINGS" then
        B.BindKeys()
        R.LayoutSoon()
    elseif event == "ACTION_RANGE_CHECK_UPDATE" then
        B.OnRangeCheck(arg1, arg2, arg3)
    elseif event == "ACTION_USABLE_CHANGED" or event == "ACTIONBAR_UPDATE_USABLE" or event == "SPELL_UPDATE_USABLE" then
        B.UpdateUsable(event == "ACTION_USABLE_CHANGED" and arg1 or nil)
        R.UpdateAll(true)
    else
        local keep = not COOLDOWN_EVENTS[event] -- state, target: the cooldowns stay as painted
        R.UpdateAll(keep)
        B.Update(keep)
    end
end, true))

-------------------------------------------------------------------------------
-- Key bindings (Bindings.xml), the AddOns menu button, slash commands
-------------------------------------------------------------------------------
BINDING_HEADER_SPHERES = "Spheres"
for _, def in ipairs(R.DEFS) do
    _G["BINDING_NAME_" .. R.ToggleBinding(def)] = "Open / close the " .. def.label .. " ring"
    if def.kind == "spells" then
        _G["BINDING_NAME_" .. R.CastBinding(def)] = "Cast your " .. def.label .. " pick (by a sphere)"
    end
end

function Spheres_OnAddonCompartmentClick()
    if ns.Settings then ns.Settings.Open() end
end

-- What Spheres costs: the game's own add-on profiler (C_AddOnProfiler, milliseconds a frame; its
-- "recent" is the last 60 frames), and the memory Lua holds for it (garbage until collected).
local function metric(get, ...)
    local ok, v = pcall(get, ...)
    return ok and type(v) == "number" and v or nil
end
local function costDebug()
    local P, M = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    local text = "cost: no profiler"
    if P and P.GetAddOnMetric and M then
        local recent = metric(P.GetAddOnMetric, ADDON, M.RecentAverageTime)
        if recent then
            text = string.format("cost: %.3f ms a frame lately (all add-ons %.3f, the whole frame %.2f), peak %.2f ms, "
                .. "frames over 1 ms %d, over 5 ms %d", recent,
                metric(P.GetOverallMetric, M.RecentAverageTime) or -1, metric(P.GetApplicationMetric, M.RecentAverageTime) or -1,
                metric(P.GetAddOnMetric, ADDON, M.PeakTime) or -1, metric(P.GetAddOnMetric, ADDON, M.CountTimeOver1Ms) or -1,
                metric(P.GetAddOnMetric, ADDON, M.CountTimeOver5Ms) or -1)
        end
    end
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
        local kb = metric(GetAddOnMemoryUsage, ADDON)
        if kb then text = text .. string.format("; memory %.0f KB", kb) end
    end
    return text
end

-- The report in a window to copy from (0.5.421, the player's: "the debug should show in a modal so
-- that i can copy paste"): a read-only box, all of it selected, so Ctrl+C takes it; Escape or the
-- cross closes it. The look is the tooltip's, as Settings' boxes. Made the first time it's asked for.
local report
local showReport
local function reportWindow()
    if report then return report end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(760, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.92)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText("Spheres debug")
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("LEFT", f.title, "RIGHT", 12, 0)
    f.hint:SetText("all selected: Ctrl+C copies, Escape closes")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, f, "ScrollFrameTemplate")
    if not ok or not scroll then ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, f, "UIPanelScrollFrameTemplate") end
    if not ok or not scroll then scroll = CreateFrame("ScrollFrame", nil, f) end
    scroll:SetPoint("TOPLEFT", 14, -36)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    box:SetWidth(700)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    -- read-only: typing puts the report back, selected again
    box:SetScript("OnTextChanged", function(self, typed)
        if typed then
            self:SetText(f.text or "")
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(box)
    f.box = box
    f:Hide()
    report = f
    return f
end
function ns.DebugWindow() return report end
showReport = function(title, text)
    local f = reportWindow()
    f.title:SetText(title)
    f.text = text
    f:Show()
    f.box:SetText(text)
    f.box:SetCursorPosition(0)
    f.box:HighlightText()
    f.box:SetFocus()
end

function ns.Debug()
    local lines = { "Spheres v" .. VERSION .. (InCombatLockdown() and " (in combat)" or "")
        .. (ns.active and "" or "  OFF (Action Ring is enabled)") }
    if ns.active then
        local function add(text) lines[#lines + 1] = "  " .. text end
        add(costDebug())
        add(S.Debug())
        add(S.LiquidDebug())
        add(K.Debug())
        add(U.Debug())
        add(B.Debug())
        add(B.PetDebug())
        add(T.Debug())
        add(Chat.Debug())
        add(ns.Tracker.Debug())
        add(ns.Motion.Debug())
        for _, o in ipairs(R.List()) do
            if o:Config().shown then add(o:Debug()) end
        end
        local d = ns.db
        add(string.format("rings shown: %s  ·  only filled slots %s, number keys %s, slot size %d, locked %s",
            table.concat(R.ShownLabels(), ", "), tostring(d.hideEmpty), tostring(d.numberKeys), d.size, tostring(d.locked)))
    end
    showReport("Spheres debug", table.concat(lines, "\n"))
    say("debug report open: Ctrl+C copies it")
end

-- /spheres profile: each busy part of Spheres timed for PROFILE_SECONDS (Art.lua A.Timed; by event for
-- an OnEvent handler), the
-- parts by their cost, in the report window. The profiler's cost line beside it covers all of
-- Spheres: what the parts don't add up to is the rest (hooks, layout, settings).
local PROFILE_DEFAULT = 10
local profiling
local function profile(seconds) -- `/spheres profile 60`: a whole fight
    if profiling then return say("already measuring") end
    local PROFILE_SECONDS = math.max(5, math.min(600, math.floor(tonumber(seconds) or PROFILE_DEFAULT)))
    if not (debugprofilestop and C_Timer and C_Timer.After) then return say("nothing to measure with here") end
    profiling = true
    local frames, counter = 0, CreateFrame("Frame")
    counter:SetScript("OnUpdate", function() frames = frames + 1 end)
    local function memory()
        if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return nil end
        pcall(UpdateAddOnMemoryUsage)
        return metric(GetAddOnMemoryUsage, ADDON)
    end
    local before = memory()
    A.StartTiming()
    say(string.format("measuring each part for %d seconds: play as usual", PROFILE_SECONDS))
    C_Timer.After(PROFILE_SECONDS, function()
        profiling = false
        counter:SetScript("OnUpdate", nil)
        local after = memory()
        local timing = A.StopTiming() or { events = {} }
        local parts, total, allocated = {}, 0, 0
        for name, t in pairs(timing) do
            if name ~= "events" then
                parts[#parts + 1] = { name = name, ms = t.ms, calls = t.calls, kb = t.kb }
                total, allocated = total + t.ms, allocated + t.kb
            end
        end
        table.sort(parts, function(a, b) return a.ms > b.ms end)
        frames = math.max(frames, 1)
        local lines = { string.format("Spheres v%s profile: %d s, %d frames, its timed parts %.3f ms a frame, allocating %.1f KB a second",
            VERSION, PROFILE_SECONDS, frames, total / frames, allocated / PROFILE_SECONDS), "  " .. costDebug() }
        if before and after then
            lines[#lines + 1] = string.format("  Spheres' memory %.0f KB -> %.0f KB (%+.1f KB a second; a drop is the game collecting)",
                before, after, (after - before) / PROFILE_SECONDS)
        end
        for _, p in ipairs(parts) do
            lines[#lines + 1] = string.format("  %s: %.4f ms a frame (%.0f%%), %.2f KB a second, %d calls, %.4f ms a call",
                p.name, p.ms / frames, total > 0 and 100 * p.ms / total or 0, p.kb / PROFILE_SECONDS, p.calls, p.ms / p.calls)
        end
        table.sort(parts, function(a, b) return a.kb > b.kb end)
        local most = {}
        for i = 1, math.min(5, #parts) do
            if parts[i].kb > 0 then
                most[#most + 1] = string.format("%s %.1f KB (%.2f KB a call)", parts[i].name, parts[i].kb,
                    parts[i].kb / math.max(1, parts[i].calls))
            end
        end
        if #most > 0 then lines[#lines + 1] = "  most garbage: " .. table.concat(most, ", ") end
        local events = {}
        for name, n in pairs(timing.events) do events[#events + 1] = { name = name, n = n } end
        table.sort(events, function(a, b) return a.n > b.n end)
        for i, e in ipairs(events) do
            if i > 12 then break end
            lines[#lines + 1] = string.format("  event %s: %.1f a second", tostring(e.name), e.n / PROFILE_SECONDS)
        end
        showReport("Spheres profile", table.concat(lines, "\n"))
        say("profile open: Ctrl+C copies it")
    end)
end

local function help()
    say("commands:")
    print("  /spheres <bar3-bar8 | menu | bags> - show or hide that ring   ·   /spheres minimap - the minimap in the right sphere on/off")
    if R.HasSpellFans() then print("  spell fans: /spheres config -> Spell Fans (by a sphere, or put their macro on your cursor)") end
    print("  /spheres config - settings   ·   /spheres reset - rings back to their first places   ·   /spheres debug   ·   /spheres profile [seconds] - what each part costs (10 s, or a fight: 60)   ·   /spheres slosh on | off - liquid motion   ·   /spheres motion - live turn and mouse speed   ·   /spheres test - the left sphere at 70% / 40%   ·   /spheres crack on | off - big blows crack the glass   ·   /spheres crack [small | large] [pet] [gate] - crack it now, to see it")
end

SLASH_SPHERES1 = "/spheres"
SlashCmdList.SPHERES = function(msg)
    if not ns.db then return end
    local cmd = strtrim(msg or ""):match("^(%S*)")
    cmd = (cmd or ""):lower()
    if cmd == "debug" then return ns.Debug() end
    if cmd == "profile" then return profile((msg or ""):match("^%s*%S+%s+(%d+)")) end
    if cmd == "slosh" then
        local kind = ((msg or ""):match("^%s*%S+%s+(%S+)") or ""):lower()
        if kind ~= "on" and kind ~= "off" then
            return say("liquid motion is " .. (ns.db.slosh == "off" and "off" or "on") .. ": /spheres slosh on | off")
        end
        ns.db.slosh = kind
        ns.Apply()
        return say(kind == "on" and "liquids slosh as you turn, move and fall." or "liquids keep still.")
    end
    if cmd == "motion" then
        return say(ns.Motion.Toggle() and "motion panel open: drag the camera, turn and run, then /spheres debug keeps the peaks"
            or "motion panel closed: /spheres debug has its peaks")
    end
    if not ns.active then return say("is off while Action Ring is enabled.") end
    if cmd:match("^%d$") then cmd = "bar" .. cmd end
    if ns.db.rings[cmd] then
        ns.SetRingShown(cmd, not ns.db.rings[cmd].shown)
        local o = R.Get(cmd)
        say(o.def.label .. " ring " .. (ns.db.rings[cmd].shown and "shown." or "hidden."))
    elseif cmd == "minimap" then
        ns.db.minimap = not ns.db.minimap
        ns.Apply()
        say(ns.db.minimap and "the minimap is in the right sphere." or "the minimap is back in Blizzard's place.")
    elseif cmd == "reset" then
        R.ResetDocks()
        say("rings back to their first places.")
    elseif cmd == "test" then
        S.test = not S.test
        S.UpdateLeft()
        S.UpdatePet()
        say(S.test and "test: health at 70%, mana at 40% (plain numbers). /spheres test again for your own."
            or "back to your own health and mana.")
    elseif cmd == "crack" then
        -- to see a crack without a big blow: the huge one (a blow of 100%), "small" (30%), "large" (50%),
        -- "pet" on your pet's glass; "gate": a blow the size of your hidden maximum, so judged with
        -- hidden values as in combat (the huge crack should show; nothing: the gates fail in this client)
        local words = (msg or ""):lower()
        local who = words:find("pet") and "pet" or "player"
        local onOff = words:match("^%s*%S+%s+(o[nf]f?)%s*$")
        if onOff == "on" or onOff == "off" then
            ns.db.crackedGlass = onOff == "on"
            return say(onOff == "on" and "a blow over 25% of your health (or your pet's) cracks its glass, over 40% and 60% more."
                or "cracked glass off: blows don't crack the glass.")
        end
        if not ns.db.crackedGlass then say("cracked glass is off (/spheres crack on, or Options): here is one to see.") end
        if words:find("gate") then
            local max = UnitHealthMax(who)
            S.Crack(who, max, max)
            say("a crack judged by the game with your hidden maximum (a blow of 100%): the huge crack should show.")
        else
            local size = words:find("small") and "small" or words:find("large") and "large" or "huge"
            S.Crack(who, size == "small" and 0.3 or size == "large" and 0.5 or 1, 1)
            say("the " .. size .. " crack" .. (who == "pet" and " on your pet's glass (needs a pet)." or "."))
        end
    elseif cmd == "config" or cmd == "options" or cmd == "settings" then
        if not (ns.Settings and ns.Settings.Open()) then say("no settings window in this client.") end
    else
        help()
    end
end
