local _, ns = ...

-- Your experience and reputation, Roth UI's way: our own thin bars under the action bar frame,
-- seen through the slots along its top (Sphere.lua draws the frame with as many slots as bars
-- show: none, one or two).
--   * Leveling: experience in purple, blue while rested, and the rest's reach in brighter blue
--     behind it, with a tick at the point where the rested bonus runs out.
--   * A watched faction (Reputation: "Show as Experience Bar"): its reputation, coloured by
--     standing, over the experience bar (alone at the top level).
--   * While resting, the XP fill breathes gently.
--   * Hover one for the numbers.
-- Blizzard's own bars go under a hidden frame (Bars.lua REPLACED). Not secure: in combat too.

local A = ns.Art
local K = {}
ns.Track = K

local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local XP_COLOR = { 0.78, 0.04, 0.76 }
local RESTED_COLOR = { 0.08, 0.52, 1.00 }
local REP_COLOR = { 0, 0.6, 0.1 }

local bars = {}
local shown = {} -- the kinds showing, bottom slot first
local function num(v) return v ~= nil and not A.secret(v) end
local function call(fn, ...) if fn then return A.call(fn, ...) end end

-------------------------------------------------------------------------------
-- What there is to show
-------------------------------------------------------------------------------
local function atMaxLevel()
    if IsPlayerAtEffectiveMaxLevel then return call(IsPlayerAtEffectiveMaxLevel) and true or false end
    local level = call(UnitLevel, "player")
    local top = call(GetMaxLevelForPlayerExpansion) or call(GetMaxPlayerLevel) or MAX_PLAYER_LEVEL
    return num(level) and num(top) and level >= top or false
end

-- cur, max, rested (nil: no experience bar)
function K.XP()
    if call(IsXPUserDisabled) or atMaxLevel() then return nil end
    local cur, max = call(UnitXP, "player"), call(UnitXPMax, "player")
    if not (num(cur) and num(max)) or max <= 0 then return nil end
    local rested = call(GetXPExhaustion)
    return cur, max, num(rested) and rested or nil
end

-- name, standing (1-8), cur, max within the standing (nil: no faction watched)
function K.Rep()
    local R = C_Reputation
    local d = R and R.GetWatchedFactionData and call(R.GetWatchedFactionData)
    local name, standing, lo, hi, v
    if type(d) == "table" and d.name then
        name, standing, lo, hi, v = d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
    elseif GetWatchedFactionInfo then
        local ok, n, s, l, h, val = pcall(GetWatchedFactionInfo)
        if ok then name, standing, lo, hi, v = n, s, l, h, val end
    end
    if not (num(name) and name ~= "" and num(lo) and num(hi) and num(v)) then return nil end
    if hi <= lo then return name, standing, 1, 1 end -- the top standing: full
    return name, standing, v - lo, hi - lo
end

-------------------------------------------------------------------------------
-- The bars
-------------------------------------------------------------------------------
local function tooltip(bar)
    bar:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.kind == "xp" then
            local cur, max, rested = K.XP()
            GameTooltip:SetText(COMBAT_XP_GAIN or "Experience", 1, 1, 1)
            if cur then
                GameTooltip:AddDoubleLine((LEVEL or "Level") .. " " .. tostring(call(UnitLevel, "player") or ""),
                    string.format("%d / %d (%.1f%%)", cur, max, cur / max * 100), 1, 0.82, 0, 1, 1, 1)
                if rested then
                    GameTooltip:AddDoubleLine(TUTORIAL_TITLE26 or "Rested", string.format("%d (%.1f%%)", rested, rested / max * 100),
                        RESTED_COLOR[1], RESTED_COLOR[2] + 0.2, RESTED_COLOR[3], 1, 1, 1)
                end
            end
            if self.resting then
                GameTooltip:AddLine("Resting: rested XP builds while logged out here", 0.55, 0.78, 1)
            end
        else
            local name, standing, cur, max = K.Rep()
            GameTooltip:SetText(name or (REPUTATION or "Reputation"), 1, 1, 1)
            if name then
                local label = standing and _G["FACTION_STANDING_LABEL" .. standing] or ""
                GameTooltip:AddDoubleLine(label, string.format("%d / %d (%.1f%%)", cur, max, cur / max * 100), 1, 0.82, 0, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- A frame holding the dark track and the fill (and, for experience, how far rest reaches, under
-- the fill), all under Roth's frame (Sphere.lua: strata LOW, level 10): only its slots show them.
local function statusBar(parent, level)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetAllPoints()
    b:SetFrameLevel(level)
    b:SetStatusBarTexture(TEXTURE)
    b.fill = b:GetStatusBarTexture()
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    b:EnableMouse(false)
    return b
end

local function makeBar(kind)
    local bar = CreateFrame("Frame", nil, ns.Sphere.HUD())
    bar:SetFrameStrata("LOW")
    bar:SetFrameLevel(1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bar.bg:SetColorTexture(0, 0, 0, 0.40)
    bar.bg:SetAllPoints()
    if kind == "xp" then
        bar.rest = statusBar(bar, 2)
        bar.rest:SetStatusBarColor(RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3], 0.78)
    end
    bar.main = statusBar(bar, 3)
    bar.kind = kind
    if kind == "xp" then
        -- Marks the exact point at which the rested XP pool is exhausted. A child frame keeps
        -- the marker above both status bars regardless of their texture draw layers.
        bar.restTick = CreateFrame("Frame", nil, bar)
        bar.restTick:SetFrameLevel(bar.main:GetFrameLevel() + 1)
        bar.restTick:SetSize(1, 8)
        bar.restTick:EnableMouse(false)
        bar.restTick.texture = bar.restTick:CreateTexture(nil, "OVERLAY")
        bar.restTick.texture:SetAllPoints()
        bar.restTick.texture:SetColorTexture(0.12, 0.58, 1, 0.95)
        bar.restTick:Hide()

        bar.pulseElapsed = 0
        bar:SetScript("OnUpdate", A.Timed("rested experience pulse", function(self, elapsed)
            if not self.resting then return end
            self.pulseElapsed = (self.pulseElapsed + elapsed) % 4.8
            local wave = (1 + math.cos(self.pulseElapsed * (2 * math.pi / 4.8))) / 2
            local alpha = 0.58 + 0.42 * wave
            self.main.fill:SetAlpha(alpha)
            self.rest.fill:SetAlpha(alpha)
        end))
    end
    bar:EnableMouse(true)
    tooltip(bar)
    bar:Hide()
    return bar
end

function K.Create()
    if bars.xp then return end
    bars.xp = makeBar("xp")
    bars.rep = makeBar("rep")
end

local function paintXP(bar, cur, max, rested)
    bar.main:SetMinMaxValues(0, max)
    bar.main:SetValue(cur)
    local color = rested and RESTED_COLOR or XP_COLOR
    bar.main:SetStatusBarColor(color[1], color[2], color[3])
    local restedEnd = rested and cur + rested
    local width = bar:GetWidth()
    -- On Retail, rested XP can cover all the remaining progress and make the track look
    -- complete. Keep its boundary tick, but show only earned XP in the bar itself.
    if not ns.Retail and rested and rested > 0 and restedEnd > cur and cur < max then
        restedEnd = math.min(max, restedEnd)
        local left = width * cur / max
        local right = width * (max - restedEnd) / max
        bar.rest:ClearAllPoints()
        bar.rest:SetPoint("TOPLEFT", bar, "TOPLEFT", left, 0)
        bar.rest:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -right, 0)
        bar.rest:SetMinMaxValues(0, 1)
        bar.rest:SetValue(1)
        bar.rest:Show()
    else
        bar.rest:Hide()
    end
    if rested and rested > 0 and restedEnd < max and cur < max then
        bar.restTick:ClearAllPoints()
        bar.restTick:SetPoint("CENTER", bar, "LEFT", width * restedEnd / max, 0)
        bar.restTick:Show()
    else
        bar.restTick:Hide()
    end
    local resting = call(IsResting) and true or false
    bar.resting = resting
    if not resting then
        bar.main.fill:SetAlpha(1)
        bar.rest.fill:SetAlpha(1)
    end
end

local function paintRep(bar, standing, cur, max)
    bar.main:SetMinMaxValues(0, max)
    bar.main:SetValue(cur)
    local c = FACTION_BAR_COLORS and standing and FACTION_BAR_COLORS[standing]
    if type(c) == "table" and num(c.r) then
        bar.main:SetStatusBarColor(c.r, c.g, c.b)
    else
        bar.main:SetStatusBarColor(REP_COLOR[1], REP_COLOR[2], REP_COLOR[3])
    end
end

-- What shows, the frame with as many slots, each bar in its slot.
function K.Update()
    if not bars.xp then return end
    local S = ns.Sphere
    wipe(shown)
    local cur, max, rested = K.XP()
    if cur then shown[#shown + 1] = "xp" end
    local name, standing, rcur, rmax = K.Rep()
    if name then shown[#shown + 1] = "rep" end
    local changed = S.SetSlots(#shown)
    for _, bar in pairs(bars) do bar:Hide() end
    local hud = S.HUD()
    for i, kind in ipairs(shown) do
        local bar, slot = bars[kind], S.Slot(i)
        if slot then
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", S.FrameAnchor(), "BOTTOM", 0, slot[1])
            bar:SetSize(slot[2], slot[3])
            if kind == "xp" then paintXP(bar, cur, max, rested) else paintRep(bar, standing, rcur, rmax) end
            bar:Show()
        end
    end
    -- the frame's top moved: the stack on it and the open rings over it follow
    if changed and ns.Auras then ns.Auras.StackSoon() end
    if changed and ns.Ring and ns.Ring.LayoutSoon then ns.Ring.LayoutSoon() end
end

function K.Shown() return shown end
function K.Bar(kind) return bars[kind] end

function K.Debug()
    local cur, max = K.XP()
    local name = K.Rep()
    return string.format("tracking: %s; experience %s, reputation %s, resting %s",
        #shown > 0 and table.concat(shown, " + ") or "none",
        cur and string.format("%d / %d", cur, max) or "off", name or "none watched",
        call(IsResting) and "yes" or "no")
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING",
    "UPDATE_FACTION", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function()
    if ns.active then K.Update() end
end)
