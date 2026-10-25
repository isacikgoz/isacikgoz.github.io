local _, ns = ...

-- Your buffs and debuffs: Blizzard's own frames (so a right-click still cancels a buff, the
-- tooltips and timers are Blizzard's), moved while Edit Mode has them in their default place.
--
-- Above the action bars (the default, 0.5.24, Diablo's way): centred over the frame on the icons
-- they show (Blizzard sizes its buff frame for a full row of icons, so the frame isn't centred,
-- what it shows is), one stack over the frame's top, bottom to top:
--   * your pet's buttons (Bars.lua) or Blizzard's stance or possess bar, when one shows
--   * your buffs, then your debuffs
--   * your cast bar (Bars.lua asks U.CastBottom)
--   * Blizzard's bottom container (extra ability buttons, the alternate power bar, the cooldown
--     viewer): out of combat (it holds protected buttons)
-- The stack follows your auras (hooks on the frames' layout), in combat too: the buff and debuff
-- frames and the cast bar aren't protected (checked: IsProtected). The rings keep out of its
-- column (U.Blocks, Ring.lua).
--
-- In the top right corner (the setting off, 0.5.1-0.5.23's place): while the minimap is in a
-- sphere, where its header was; the buff frame flush with the screen's edge, its collapse arrow
-- the margin, the debuffs under them with Blizzard's own spacing (its defaults: buffs at -255,
-- -10, debuffs at -270, -155).
--
-- Nothing of Blizzard's is written but frame positions, its collapse arrow's alpha and mouse.

local U = {}
ns.Auras = U

local GAP = 4        -- between the pieces of the stack (UIParent units)
local CAST_GAP = 6   -- under the cast bar
local RESERVE = 110  -- the stack's column the rings keep out of, at least this tall over the frame
local TOP = -12      -- the corner
local DEBUFF_X, DEBUFF_Y = -15, -145

local moved = {}    -- frame -> true while it's ours
local hooked = {}
local placing = false
local pending = false
local stackTop      -- the stack's top under the cast bar (UIParent units), centre mode
local reserved      -- the column's top the rings were laid out round
local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() end
-- Our pet bar has no Edit Mode place: it is always over the frame (Bars.lua).
local function inDefault(f)
    return f == ns.Bars.PetBar() or not f.IsInDefaultPosition or f:IsInDefaultPosition()
end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
local function num(v) return v ~= nil and not secret(v) end
local function ui(f) return f:GetEffectiveScale() / UIParent:GetEffectiveScale() end
local function protectedNow(f) return inCombat() and f.IsProtected ~= nil and f:IsProtected() end

function U.Centred() return not ns.db or ns.db.aurasAbove ~= false end

-------------------------------------------------------------------------------
-- Above the action bars
-------------------------------------------------------------------------------
-- The icons a frame shows: their box in UIParent units (nil: none).
local function shownBox(f)
    local l, r, b, t
    for _, btn in ipairs(f.auraFrames or {}) do
        if btn:IsShown() then
            local bl, bb, bw, bh = btn:GetLeft(), btn:GetBottom(), btn:GetWidth(), btn:GetHeight()
            if num(bl) and num(bb) and num(bw) and num(bh) then
                local k = ui(btn)
                bl, bb, bw, bh = bl * k, bb * k, bw * k, bh * k
                l = l and math.min(l, bl) or bl
                b = b and math.min(b, bb) or bb
                r = r and math.max(r, bl + bw) or bl + bw
                t = t and math.max(t, bb + bh) or bb + bh
            end
        end
    end
    return l, r, b, t
end

-- The frame moved so the icons it shows sit centred on cx, their bottom at y (UIParent units).
-- How tall they are (0: none).
local function centre(f, cx, y)
    local l, r, b, t = shownBox(f)
    if not l then return 0 end
    local fl, fb = f:GetLeft(), f:GetBottom()
    if num(fl) and num(fb) and not protectedNow(f) then
        local k = ui(f)
        placing = true
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (fl * k + cx - (l + r) / 2) / k, (fb * k + y - b) / k)
        placing = false
        moved[f] = true
    end
    return t - b
end

-- Its collapse arrow stands off at the frame's far end: out of sight while it's centred.
local function arrow(f, on)
    local a = f and f.CollapseAndExpandButton
    if not a then return end
    a:SetAlpha(on and 1 or 0)
    a:EnableMouse(on and true or false)
end

local SMALL = { "SpheresPetBar", "StanceBar", "PossessActionBar" }
local function smallBarsTop()
    local top
    for _, name in ipairs(SMALL) do
        local f = _G[name]
        if f and f:IsVisible() and inDefault(f) then
            local t = f:GetTop()
            if num(t) then
                t = t * ui(f)
                top = top and math.max(top, t) or t
            end
        end
    end
    return top
end

local function container()
    if GetBottomManagedFrameContainer then
        local ok, c = pcall(GetBottomManagedFrameContainer)
        if ok and c then return c end
    end
    return BottomManagedFrameContainer
end

-- Blizzard's bottom container over the cast bar (out of combat: it holds protected buttons).
local function placeContainer(over)
    local c = container()
    if not c or protectedNow(c) then return end
    local k = ui(c)
    placing = true
    c:ClearAllPoints()
    c:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, over / k)
    placing = false
    moved[c] = true
end

-- The column's top: the stack and room for a cast bar over it, at least RESERVE over the frame.
local function columnTop(base)
    return math.max(base + RESERVE, (stackTop or base) + CAST_GAP + 24)
end

function U.Stack()
    if not (ns.active and U.Centred()) then return end
    local base = ns.Sphere.ArtTop()
    if not base then return end
    local small = smallBarsTop()
    if small and small > base then base = small end
    local cx = UIParent:GetWidth() / 2
    local y = base + GAP
    for _, f in ipairs({ BuffFrame, DebuffFrame }) do
        if f and inDefault(f) then
            arrow(f, false)
            local h = centre(f, cx, y)
            if h > 0 then y = y + h + GAP end
        end
    end
    stackTop = y
    local cb = ns.Bars.PlaceCastBar()
    local over = y + CAST_GAP
    if cb then
        local t = cb:GetTop()
        if num(t) then over = math.max(over, t * ui(cb) + GAP) end
    end
    placeContainer(over)
    -- the rings were laid out round a shorter column (a pet's buttons came, more buffs): again
    -- (they're secure: in combat, Ring waits for the fight's end)
    if reserved and columnTop(ns.Sphere.ArtTop()) > reserved and ns.Ring.LayoutSoon then
        ns.Ring.LayoutSoon()
    end
end

local soon = false
function U.StackSoon()
    if soon then return end
    soon = true
    local function run() soon = false; U.Stack() end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

-- The cast bar's bottom (UIParent units) over the stack; nil in the corner (Bars.lua's own place).
function U.CastBottom()
    if not (U.Centred() and stackTop) then return nil end
    return stackTop + CAST_GAP - GAP
end

-- The stack's column, which the rings' slots keep out of (UIParent units): the rows' width, from
-- the frame's top up to the stack's top and a cast bar, at least RESERVE tall.
function U.KeepOut()
    if not U.Centred() then return nil end
    local base = ns.Sphere.ArtTop()
    local h = ns.Bars.Holder()
    if not (base and h) then return nil end
    local l, r = h:GetLeft(), h:GetRight()
    if not (num(l) and num(r)) then return nil end
    local k = ui(h)
    local top = columnTop(base)
    reserved = top
    return l * k, r * k, base, top
end

function U.Blocks(x, y, size)
    local l, r, b, t = U.KeepOut()
    if not l then return false end
    local half = (size or 0) / 2
    return x + half > l and x - half < r and y + half > b and y - half < t
end

-------------------------------------------------------------------------------
-- In the top right corner
-------------------------------------------------------------------------------
local function corner()
    local on = ns.Sphere.MapTaken()
    for _, p in ipairs({ { BuffFrame, 0, TOP }, { DebuffFrame, DEBUFF_X, TOP + DEBUFF_Y } }) do
        local f, x, y = p[1], p[2], p[3]
        if f and inDefault(f) then
            arrow(f, true)
            placing = true
            if on then
                f:ClearAllPoints()
                f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, y)
                moved[f] = true
            elseif moved[f] then
                moved[f] = nil
                if f.ApplySystemAnchor then pcall(f.ApplySystemAnchor, f) end
            end
            placing = false
        end
    end
end

-------------------------------------------------------------------------------
-- Layout (out of combat), hooks
-------------------------------------------------------------------------------
local function hook(f, method, fn)
    if not (f and f[method] and hooksecurefunc) or (hooked[f] and hooked[f][method]) then return end
    hooked[f] = hooked[f] or {}
    hooked[f][method] = true
    hooksecurefunc(f, method, fn)
end

local function hookAll()
    for _, f in ipairs({ BuffFrame, DebuffFrame }) do
        -- Edit Mode puts them back: ours again; their icons change: the stack again
        hook(f, "SetPoint", function()
            if not placing and moved[f] then U.LayoutSoon() end
        end)
        hook(f, "UpdateGridLayout", function() if U.Centred() then U.StackSoon() end end)
    end
    for _, name in ipairs(SMALL) do
        local f = _G[name]
        if f and f.HookScript and not (hooked[f] and hooked[f].shown) then
            hooked[f] = hooked[f] or {}
            hooked[f].shown = true
            f:HookScript("OnShow", function() U.StackSoon() end)
            f:HookScript("OnHide", function() U.StackSoon() end)
        end
    end
    local c = container()
    hook(c, "SetPoint", function()
        if not placing and moved[c] and U.Centred() then U.StackSoon() end
    end)
end

function U.Layout()
    if inCombat() then pending = true; return false end
    pending = false
    hookAll()
    if U.Centred() then
        U.Stack()
    else
        stackTop = nil
        local c = container()
        if c and moved[c] then
            moved[c] = nil
            if ManageFramePositions then pcall(ManageFramePositions) end -- Blizzard places it again
        end
        corner()
    end
    return true
end

local later = false
function U.LayoutSoon()
    if later then return end
    later = true
    local function run() later = false; U.Layout() end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

function U.Pending() return pending end

function U.Debug()
    local function state(f)
        if not f then return "none" end
        if not inDefault(f) then return "moved in Edit Mode" end
        if not moved[f] then return "Blizzard's" end
        local l, r = shownBox(f)
        return U.Centred() and (l and string.format("centred (%.0f wide)", r - l) or "centred, none shown") or "top right"
    end
    return string.format("auras: %s; buffs %s, debuffs %s, stack top %s",
        U.Centred() and "above the action bars" or "top right corner", state(BuffFrame), state(DebuffFrame),
        stackTop and string.format("%.0f", stackTop) or "-")
end
