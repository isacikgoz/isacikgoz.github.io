-- The liquid simulator's Lua side (tools/slosh_sim.html, `make sim`): Spheres' own Art.lua,
-- Sphere.lua, Track.lua and Motion.lua, loaded as the game loads them, on a HUD standing on the
-- screen's bottom edge as the game's (flush with it). The frame and the statues are the game's
-- (buildArt, finished by paintArt for the Statues setting: S.Liquids.art), the experience bar seen
-- through the frame's slot too (Track.lua K.Create, K.Update). The left orb is the game's (buildLeft
-- through S.Liquids.left), laid out by the game's S.UpdateLeft and S.UpdatePet from the unit data
-- the page picks (mana or rage, a pet or none, the levels); the map sphere's layers are the game's
-- (buildMapLayers through S.Liquids.map). Every frame runs their OnUpdate scripts: the liquids
-- (animateLiquids, with the slosh) and the map's smoke. What the code sets on its frames and
-- textures is recorded by a small stand-in for the game's frames (anchors laid out, clips, masks,
-- texture coordinates and rotations, colours, show and hide, draw order); the page draws those
-- textures and nothing of its own but the minimap's terrain (the game draws that).
--
--   lua5.1 tools/sim_bridge.lua <Spheres folder>             one request a line on stdin, one JSON reply a line
--   lua5.1 tools/sim_bridge.lua <Spheres folder> --selftest  `make test`: every layout, a fast turn, checks
-- The page runs it in its own Lua 5.1 (tools/vendor/lua51.wasm, built from tools/sim_lua.c): with SIM_EMBEDDED
-- set it defines SimAsk(request), the JSON reply, instead of reading stdin.
--
-- Requests:  init
--            frame dt=<s> turn=<°/s, + right> fwd=<yd/s> lat=<yd/s, + right> air=0|1 jump=0|1 hp=<0-1>
--                  pp=<0-1> power=mana|rage|energy pet=none|beast|demon php=<0-1> pmp=<0-1> regen=0|1
--                  statues=modern|charcoal|none xp=<0-1> rested=<0-1> resting=0|1 level=<1-60>
--                  class=paladin|priest|mage (the mana's magic: S.UpdateMagic)
--                  target=none|hostile|neutral|friendly|tapped thp=<0-1> tpp=<0-1> tpower=mana|rage|none (the
--                  target's sphere, Target Style "Sphere": S.TargetSphere) top=<units> (the screen's top over
--                  its bottom: the target card hangs 24 under it, as Target.lua TOP)
--                  hit=player|pet size=<0-1> hidden=0|1 (a blow for `size` of the maximum, into S.Wound as
--                  UNIT_COMBAT's WOUND; hidden: boxed as Forever's hidden values, so the crack's gate judges it)
--            set <SLOSH key> <number>      reset      adopt (the current SLOSH as the game's, after an export)
--            eval <Lua>   the harness's: run in here (S, M, L, K, ns, me, hud at hand), its result as JSON
-- Not the game's: no action rows, rings or target card, no text (the level, the values), the map
-- sphere sits in
-- its place without the minimap's own pins, labels and arrows, status bars fill at once (the game
-- eases them), and unit watches are played by showing the pet's orb when there is a pet.

local dir = arg[1] or "."
local selftest = arg[2] == "--selftest"
-- each crack its own (the game seeds its own random); SIM_SEED: the same cracks every run, to compare looks
math.randomseed(selftest and 1 or tonumber(os.getenv("SIM_SEED") or "") or os.time())
local MEDIA = "Interface\\AddOns\\Spheres\\Media\\"

-------------------------------------------------------------------------------
-- JSON out
-------------------------------------------------------------------------------
local function json(v)
    local t = type(v)
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local parts = {}
            for i = 1, #v do parts[i] = json(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. json(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return string.format("%.6g", v)
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
    elseif t == "boolean" then return tostring(v) end
    return "null"
end

-------------------------------------------------------------------------------
-- The game's frames, as far as the orbs use them: regions that remember what is set on them
-------------------------------------------------------------------------------
local regions = {}
local Region = {}
local function nothing() end
Region.__index = function(_, k) -- any other of the game's methods (they start with a capital): does nothing
    local method = Region[k]
    if method ~= nil then return method end
    if type(k) == "string" and k:match("^%u") then return nothing end
end
local FRAMES = { Frame = true, StatusBar = true, Button = true, Cooldown = true, ScrollFrame = true, EditBox = true }
local function newRegion(kind, parent)
    local r = setmetatable({ kind = kind, parent = parent, points = {}, shown = true, alpha = 1, masks = {},
        layer = "ARTWORK", sublevel = 0, index = #regions + 1, scripts = {} }, Region)
    regions[#regions + 1] = r
    if FRAMES[kind] then
        r.frame = true
        r.level = parent and parent.level and parent.level + 1 or 0
    end
    return r
end
function CreateFrame(kind, _, parent) return newRegion(FRAMES[kind] and kind or "Frame", parent) end
function Region:CreateTexture(_, layer, _, sublevel)
    local t = newRegion("Texture", self)
    t.layer, t.sublevel = layer or "ARTWORK", sublevel or 0
    return t
end
function Region:CreateMaskTexture() return newRegion("Mask", self) end
-- Text as the game's FontStrings (the page draws it): the font a template gave (the game's font objects the add-on
-- uses: size, colour) or SetFont's size and flags; measured by a stand-in for Friz Quadrata's widths, since the
-- add-on lays curved text out glyph by glyph by GetStringWidth.
local FONTS = {
    GameFontHighlightSmall = { 10, { 1, 1, 1 } }, GameFontNormalSmall = { 10, { 1, 0.82, 0 } },
    GameFontNormal = { 12, { 1, 0.82, 0 } }, GameFontHighlight = { 12, { 1, 1, 1 } }, GameFontNormalLarge = { 16, { 1, 0.82, 0 } },
    GameFontDisableSmall = { 10, { 0.5, 0.5, 0.5 } }, NumberFontNormalSmall = { 12, { 1, 1, 1 } }, TextStatusBarText = { 10, { 1, 1, 1 } },
}
local WIDE, NARROW = "MWmw@%", "il.,:;'|!I"
local function advance(ch) -- an advance in ems
    if ch == " " then return 0.28 end
    if NARROW:find(ch, 1, true) then return 0.3 end
    if WIDE:find(ch, 1, true) then return 0.86 end
    if ch:match("^%d$") then return 0.56 end
    if ch:match("^%u$") then return 0.68 end
    return 0.52
end
local function plainText(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function textWidth(r)
    local w = 0
    for ch in plainText(r.text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do w = w + advance(ch) end
    return w * (r.fontSize or 10)
end
function Region:CreateFontString(_, layer, template)
    local f = newRegion("FontString", self)
    f.layer = layer or "ARTWORK"
    local font = FONTS[template] or FONTS.GameFontHighlightSmall
    f.fontSize, f.fontFlags, f.textColor = font[1], "", { font[2][1], font[2][2], font[2][3], 1 }
    return f
end
function Region:GetParent() return self.parent end
function Region:SetParent(p) self.parent = p end
function Region:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "number" then rel, relPoint, x, y = self.parent, point, a, b
    else
        rel = a or self.parent
        if type(b) == "string" then relPoint, x, y = b, c, d else relPoint, x, y = point, b, c end
    end
    self.all = nil
    self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
end
function Region:ClearAllPoints() self.points, self.all = {}, nil end
function Region:SetAllPoints(rel) self.points, self.all = {}, rel or self.parent end
function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetWidth() return self.w or 0 end
function Region:GetHeight() return self.h or 0 end
function Region:GetSize() return self.w or 0, self.h or 0 end
function Region:GetScale() return 1 end
function Region:GetEffectiveScale() return 1 end
function Region:IsShown() return self.shown end
function Region:IsVisible()
    local r = self
    while r do if not r.shown then return false end r = r.parent end
    return true
end
-- shown or hidden: a frame's OnShow / OnHide, as the game runs them
function Region:SetShown(on)
    on = on and true or false
    if on == self.shown then return end
    self.shown = on
    local script = self.scripts[on and "OnShow" or "OnHide"]
    if script then script(self) end
end
function Region:Show() self:SetShown(true) end
function Region:Hide() self:SetShown(false) end
function Region:SetScript(name, fn) self.scripts[name] = fn end
-- the game's events, as far as the bridge fires them (your death and coming back): each frame registered
-- for one has its OnEvent called
local listeners = {}
function Region:RegisterEvent(event)
    listeners[event] = listeners[event] or {}
    listeners[event][self] = true
end
function Region:UnregisterEvent(event) if listeners[event] then listeners[event][self] = nil end end
local function fire(event, ...)
    for r in pairs(listeners[event] or {}) do
        local script = r.scripts.OnEvent
        if script then script(r, event, ...) end
    end
end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript(name, fn)
    local before = self.scripts[name]
    self.scripts[name] = before and function(...) before(...); fn(...) end or fn
end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetAlpha() return self.alpha end
function Region:SetTexture(file, wrapH, wrapV) self.file, self.wrapH, self.wrapV, self.atlas = file, wrapH, wrapV or wrapH, nil end
function Region:GetTexture() return self.file end
function Region:SetAtlas(name) self.atlas, self.file = name, nil end -- Blizzard's atlases: not drawn here
function Region:SetTexCoord(...)
    local n = select("#", ...)
    if n == 4 then
        local l, r, t, b = ...
        self.texcoord = { l, t, l, b, r, t, r, b }
    else
        self.texcoord = { ... }
    end
end
function Region:SetRotation(angle) self.rotation = angle end
function Region:SetColorTexture(r, g, b, a)
    self.file, self.color, self.colorAlpha, self.atlas = "Interface\\Buttons\\WHITE8x8", { r, g, b }, a or 1, nil
end
function Region:SetVertexColor(r, g, b) self.color = { r, g, b } end
function Region:SetBlendMode(mode) self.blend = mode end
function Region:AddMaskTexture(m) self.masks[#self.masks + 1] = m end
function Region:RemoveMaskTexture(m)
    for i, x in ipairs(self.masks) do if x == m then table.remove(self.masks, i) return end end
end
function Region:GetNumMaskTextures() return #self.masks end
function Region:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel or 0 end
function Region:SetFrameLevel(level) self.level = level end
function Region:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel()) or 0 end
function Region:SetClipsChildren(on) self.clips = on and true or false end
function Region:GetNumPoints() return #self.points end
function Region:SetText(t) self.text = t end
function Region:GetText() return self.text end
function Region:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function Region:GetFont() return "Fonts\\FRIZQT__.TTF", self.fontSize or 10, self.fontFlags or "" end
function Region:SetFont(_, size, flags) self.fontSize, self.fontFlags = size, flags or "" end
function Region:SetFontObject(obj)
    local font = FONTS[obj]
    if font then self.fontSize, self.textColor = font[1], { font[2][1], font[2][2], font[2][3], 1 } end
end
function Region:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
function Region:GetTextColor() local c = self.textColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Region:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a or 1 } end
function Region:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
function Region:SetJustifyH(j) self.justifyH = j end
function Region:GetStringWidth() return textWidth(self) end
function Region:GetUnboundedStringWidth() return textWidth(self) end
function Region:GetStringHeight() return (self.fontSize or 10) * 1.2 end
-- a status bar: its fill a texture from its bottom up to the value's share of it (vertical)
function Region:SetStatusBarTexture(file)
    if not self.fill then
        self.fill = self:CreateTexture(nil, "ARTWORK")
        self.fill.fillOf = self
    end
    self.fill.file = file
end
function Region:GetStatusBarTexture() return self.fill end
function Region:SetOrientation(o) self.orientation = o end
-- how much of a status bar its value fills (0-1)
-- Forever's hidden values, for the page's hidden blows: a box Lua can't read (A.secret sees one),
-- opened by the status bars, as the game's take hidden values
local HIDDEN = {}
function issecretvalue(v) return type(v) == "table" and rawget(v, HIDDEN) ~= nil end
local function hidden(v) return setmetatable({ [HIDDEN] = v }, { __index = function() error("a hidden value read", 2) end }) end
local function open(v) if issecretvalue(v) then return rawget(v, HIDDEN) end return v end
local function share(bar)
    local lo, hi, v = open(bar.min or 0), open(bar.max or 1), open(bar.value or 0)
    return hi > lo and math.max(0, math.min(1, (v - lo) / (hi - lo))) or 0
end
function Region:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function Region:GetMinMaxValues() return self.min or 0, self.max or 1 end
function Region:SetValue(v) self.value = v end
function Region:GetValue() return self.value or 0 end
function Region:SetStatusBarColor(r, g, b, a)
    if self.fill then self.fill.color, self.fill.colorAlpha = { r, g, b }, a or 1 end
end

-------------------------------------------------------------------------------
-- Where everything is: the anchors laid out (HUD units, y up)
-------------------------------------------------------------------------------
local ANCHOR = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 } }
local laid = {}
local function sizeOf(r) -- a FontString's, unless set, is its text's
    if r.kind == "FontString" and not r.w then return textWidth(r), (r.fontSize or 10) * 1.2 end
    return r.w or 0, r.h or 0
end
local function rectOf(r)
    if laid[r] then return laid[r] end
    local box
    if r.root then -- the HUD: its bottom `bottom` from the screen's (y 0), centred
        box = { -r.w / 2, r.bottom, r.w / 2, r.bottom + r.h }
    elseif r.fillOf then -- vertical, from the bottom up (the orbs' bars); else from the left
        local b, bar = rectOf(r.fillOf), r.fillOf
        local f = share(bar)
        if bar.orientation == "VERTICAL" then box = { b[1], b[2], b[3], b[2] + f * (b[4] - b[2]) }
        else box = { b[1], b[2], b[1] + f * (b[3] - b[1]), b[4] } end
    elseif r.all then
        local b = rectOf(r.all)
        box = { b[1], b[2], b[3], b[4] }
    elseif #r.points == 0 then
        local b = r.parent and rectOf(r.parent) or { 0, 0, 0, 0 }
        local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
        local w, h = sizeOf(r)
        box = { cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2 }
    else
        local x0, x1, xc, y0, y1, yc
        for _, p in ipairs(r.points) do
            local b, a, m = rectOf(p.rel), ANCHOR[p.relPoint] or ANCHOR.CENTER, ANCHOR[p.point] or ANCHOR.CENTER
            local px, py = b[1] + a[1] * (b[3] - b[1]) + p.x, b[2] + a[2] * (b[4] - b[2]) + p.y
            if m[1] == 0 then x0 = px elseif m[1] == 1 then x1 = px else xc = px end
            if m[2] == 0 then y0 = py elseif m[2] == 1 then y1 = py else yc = py end
        end
        local w, h = sizeOf(r)
        if not (x0 and x1) then
            if x0 and xc then x1 = 2 * xc - x0 elseif x1 and xc then x0 = 2 * xc - x1
            elseif x0 then x1 = x0 + w elseif x1 then x0 = x1 - w
            elseif xc then x0, x1 = xc - w / 2, xc + w / 2 else x0, x1 = -w / 2, w / 2 end
        end
        if not (y0 and y1) then
            if y0 and yc then y1 = 2 * yc - y0 elseif y1 and yc then y0 = 2 * yc - y1
            elseif y0 then y1 = y0 + h elseif y1 then y0 = y1 - h
            elseif yc then y0, y1 = yc - h / 2, yc + h / 2 else y0, y1 = -h / 2, h / 2 end
        end
        box = { x0, y0, x1, y1 }
    end
    laid[r] = box
    return box
end

-------------------------------------------------------------------------------
-- The game functions the orbs read: your character (played by the page) and your pet
-------------------------------------------------------------------------------
local me = { clock = 0, facing = 1, north = 0, west = 0, falling = false, hp = 0.7, pp = 0.55, power = "mana",
    pet = "none", php = 0.6, pmp = 0.4, xp = 0.46, rested = 0.2, resting = true, statues = "modern",
    class = "paladin", target = "none", targetNpc = "none", targetName = "", targetReaction = "", targetLevel = 30,
    thp = 0.64, tpp = 0.7, tpower = "mana", level = 30,
    life = "alive", corpse = nil, view = 233, hover = "none", combat = false }
local POWER = { mana = { 0, "MANA" }, rage = { 1, "RAGE" }, focus = { 2, "FOCUS" }, energy = { 3, "ENERGY" },
    none = { 0, "MANA" } }
local MAX = 1000
function GetPlayerFacing() return me.facing end
function UnitPosition(unit) if unit == "player" then return me.north, me.west, 0, 1 end end
function GetUnitSpeed() return 0 end
function IsFalling() return me.falling end
function IsSwimming() return false end
function InCombatLockdown() return false end
function GetTime() return me.clock end
function JumpOrAscendStart() end
function hooksecurefunc(a, b, c)
    if type(a) == "string" then
        local orig = _G[a]
        _G[a] = function(...) orig(...); b(...) end
    else
        local orig = a[b]
        a[b] = function(...) orig(...); c(...) end
    end
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function RegisterUnitWatch() end
local function isPet(unit) return unit == "pet" and me.pet ~= "none" end
function UnitExists(unit) return unit == "player" or isPet(unit) or unit == "target" and me.targetNpc ~= "none" end
function UnitName(unit)
    if unit == "target" and me.targetNpc ~= "none" then return (me.targetName or ""):gsub("_", " ") end
end
function UnitReaction(unit)
    if unit ~= "target" then return nil end
    return me.targetReaction == "friendly" and 5 or me.targetReaction == "neutral" and 4 or me.target ~= "none" and 2 or nil
end
function UnitIsPlayer(unit) return unit == "player" end
function UnitClassification(unit) return unit == "target" and "normal" or "normal" end
function UnitIsBossMob() return false end
function UnitIsTapDenied() return false end
function UnitPlayerControlled(unit) return unit == "player" end
-- dead (lying where you fell) or a ghost (released, your corpse left behind): the page plays it (`life`)
function UnitIsDeadOrGhost(unit) return unit == "player" and me.life ~= "alive" or unit == "target" and me.targetNpc ~= "none" and me.thp <= 0.0001 end
function UnitIsDead(unit) return unit == "player" and me.life == "dead" or unit == "target" and me.targetNpc ~= "none" and me.thp <= 0.0001 end
function UnitIsGhost(unit) return unit == "player" and me.life == "ghost" end
-- One map over the world the page plays in (the minimap's stand-in, north up, never turning): MAP_SPAN yards
-- across, you starting at MAP_AT on it; a corpse found on it (C_DeathInfo), the minimap showing `view` yards
-- round you. The add-on finds your corpse and judges its arrow with these, as it does with the game's.
local MAP_SPAN, MAP_AT = 4000, { 0.58, 0.44 } -- yards across (about a zone's); where you start on it
local function vector(x, y)
    return { x = x, y = y, GetXY = function(v) return v.x, v.y end, SetXY = function(v, a, b) v.x, v.y = a, b end }
end
function CreateVector2D(x, y) return vector(x, y) end
C_Map = {
    GetBestMapForUnit = function() return 1 end,
    GetMapInfo = function() return { parentMapID = 0 } end,
    GetWorldPosFromMapPos = function(_, pos) -- the continent (UnitPosition's instance), yards north and west
        local x, y = pos:GetXY()
        return 1, vector((MAP_AT[2] - y) * MAP_SPAN, (MAP_AT[1] - x) * MAP_SPAN)
    end,
}
C_DeathInfo = {
    GetCorpseMapPosition = function()
        local c = me.life == "ghost" and me.corpse
        if c then return vector(MAP_AT[1] - c[2] / MAP_SPAN, MAP_AT[2] - c[1] / MAP_SPAN) end
    end,
}
C_Minimap = { GetViewRadius = function() return me.view end, IsRotateMinimapIgnored = function() return false end }
function GetCVarBool() return false end -- nothing the add-on asks is on here (rotateMinimap: north up)
function UnitHealth(unit) return unit == "target" and me.thp * MAX or unit == "pet" and me.php * MAX or me.hp * MAX end
function UnitHealthMax() return MAX end
-- the game's curves (C_CurveUtil, linear) and a health share through one: where a crack breaks (rimCurve)
local CURVE = {}
CURVE.__index = CURVE
function CURVE:SetType() end
function CURVE:AddPoint(x, y) self.pts[#self.pts + 1] = { x, y } end
function CURVE:Evaluate(x)
    local pts = self.pts
    if x <= pts[1][1] then return pts[1][2] end
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
    end
    return pts[#pts][2]
end
C_CurveUtil = { CreateCurve = function() return setmetatable({ pts = {} }, CURVE) end }
Enum = { LuaCurveType = { Linear = 0, Step = 1 } }
function UnitHealthPercent(unit, _, curve)
    local f = unit == "target" and me.thp or unit == "pet" and me.php or me.hp
    return curve and curve:Evaluate(f) or f
end
function UnitPowerType(unit)
    local p = POWER[unit == "target" and me.tpower or unit == "pet" and (me.pet == "demon" and "mana" or "focus") or me.power]
    return p[1], p[2]
end
function UnitPower(unit) return unit == "target" and me.tpp * MAX or unit == "pet" and me.pmp * MAX or me.pp * MAX end
function UnitPowerMax(unit) return unit == "target" and me.tpower == "none" and 0 or MAX end
function UnitGetIncomingHeals() return 0 end
function HasPetUI() return isPet("pet"), me.pet == "beast" end
function AbbreviateNumbers(n, opts) -- the game's, by the breakpoints given (the add-on's lower-case k and m)
    if type(n) ~= "number" then return tostring(n) end
    for _, b in ipairs(opts and opts.breakpointData or {}) do
        if n >= b.breakpoint then return tostring(math.floor(n / b.significandDivisor) / b.fractionDivisor) .. b.abbreviation end
    end
    return tostring(math.floor(n + 0.5))
end
-- where you are: Teldrassil's Shadowglen, the start (the map sphere's zone name)
function GetMinimapZoneText() return "Shadowglen" end
function GetZoneText() return "Teldrassil" end
function GetSubZoneText() return "Shadowglen" end
local XP_MAX = 11400
function UnitLevel(unit) return unit == "target" and me.targetLevel or me.level end
function GetMaxPlayerLevel() return 60 end
function IsXPUserDisabled() return false end
function UnitXP() return me.xp * XP_MAX end
function UnitXPMax() return XP_MAX end
function GetXPExhaustion() return me.rested > 0 and me.rested * XP_MAX or nil end
function IsResting() return me.resting end
function UnitAffectingCombat(unit) return unit == "player" and me.combat end
-- your class (S.UpdateMagic reads it)
local CLASS = { mage = { "Mage", "MAGE" }, paladin = { "Paladin", "PALADIN" }, priest = { "Priest", "PRIEST" },
    druid = { "Druid", "DRUID" }, shaman = { "Shaman", "SHAMAN" } }
function UnitClass() return CLASS[me.class][1], CLASS[me.class][2] end

-------------------------------------------------------------------------------
-- Spheres' files, as the game loads them (their prints to stderr: stdout is the page's)
-------------------------------------------------------------------------------
local ns = {}
local env = setmetatable({ print = function(...) io.stderr:write(table.concat({ ... }, " "), "\n") end },
    { __index = _G, __newindex = _G })
for _, file in ipairs({ "Art.lua", "Sphere.lua", "Track.lua", "Motion.lua" }) do
    local chunk = assert(loadfile(dir .. "/" .. file))
    setfenv(chunk, env)
    chunk("Spheres", ns)
end
local S, M, L, K = ns.Sphere, ns.Motion, ns.Sphere.Liquids, ns.Track
function S.MapTaken() return true end -- the minimap stands in the map sphere here (S.PlaceMinimap in game)
ns.db = { statueFinish = me.statues, questArrow = true, crackedGlass = true } -- the settings the art reads (cracks: on, to try them)
local GAME_SLOSH = {}
for k, v in pairs(M.SLOSH) do GAME_SLOSH[k] = v end

-------------------------------------------------------------------------------
-- The two orbs on a HUD of their own (Sphere.lua S.Create's, without the art and the rows)
-------------------------------------------------------------------------------
local hud = newRegion("Frame", nil)
hud.root, hud.w, hud.h, hud.level, hud.bottom = true, 966, 260, 2, -L.SINK
local left, right, target
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local function build()
    regions, laid = { hud }, {}
    for event in pairs(listeners) do listeners[event] = nil end
    L.reset(hud)
    M.ROOM = M.SLOSH.climb + M.K.room -- set once at load in the game
    left = L.left(hud)
    S.UpdateCombat(me.combat) -- the level well, as PLAYER_ENTERING_WORLD fills it
    L.art()
    K.Create()
    S.UpdateMagic()
    -- the map sphere where orbFrame("right") puts it; the minimap in it as S.PlaceMinimap puts it
    right = CreateFrame("Frame", nil, hud)
    right:SetSize(L.D, L.D)
    right:SetFrameLevel(hud.level + 5)
    right:SetPoint("CENTER", hud, "BOTTOM", S.OrbOffset(), L.ORB_Y)
    L.map(right)
    local minimap = CreateFrame("Frame", nil, right.mapHolder)
    minimap:SetPoint("CENTER", right, "CENTER", 0, 0)
    minimap:SetSize(L.mapSize, L.mapSize)
    local terrain = minimap:CreateTexture(nil, "ARTWORK")
    terrain.file = "@map" -- the game draws the terrain; the page has a stand-in
    terrain:SetAllPoints()
    local mask = minimap:CreateMaskTexture()
    mask:SetTexture(L.mapMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    terrain:AddMaskTexture(mask)
    right.mapDissolve:Show()
    right.clouds:Show()
    -- the target's sphere (Target Style "Sphere", experimental: Target.lua's card holds it in game),
    -- over the HUD's middle where the card would be; its portrait a stand-in (the game draws portraits):
    -- a dark disc in the hubs' brass ring
    -- (built on a holder over the HUD's art: its frames take their levels from it as they're made)
    local holder = CreateFrame("Frame", nil, hud)
    holder:SetFrameLevel(hud.level + 20)
    holder:SetAllPoints(hud)
    target = S.TargetSphere(holder)
    target:SetPoint("TOP", hud, "BOTTOM", 0, 470) -- (frame(): the screen's top, `top`)
    local face = CreateFrame("Frame", nil, target)
    face:SetFrameLevel(target.avatarLevel)
    face:SetSize(target.avatarSize, target.avatarSize)
    face:SetPoint("CENTER", target, "CENTER")
    local disc = face:CreateTexture(nil, "ARTWORK")
    disc:SetTexture("@avatar-gnarlpine")
    target.avatar = disc
    disc:SetAllPoints()
    local round = face:CreateMaskTexture()
    round:SetTexture(L.mapMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    round:SetAllPoints()
    disc:AddMaskTexture(round)
    -- the gold ring's size as Target.lua's shape() makes it; the hubs' ring drawn to reach as far
    -- (its art ends at 0.89 of its size)
    local rs = (target.avatarSize + 2) / (1 - 2 * 26 / 758)
    local ring = face:CreateTexture(nil, "OVERLAY")
    ns.Art.SetBezel(ring, "Hub")
    ring:SetSize(rs / 0.89, rs / 0.89)
    ring:SetPoint("CENTER")
    target:Hide()
end

-- What to draw, in the game's order: frame level, layer, sublevel, creation. Files by their name in
-- Spheres/Media ("WHITE": Blizzard's plain white; "@map": the minimap's terrain); masks and clips
-- with their rectangles; a rotation turned into texture coordinates (counter-clockwise, about the
-- middle, as Texture:SetRotation).
local BLIZZARD = { -- Blizzard's own textures the HUD uses, as near as the page has them
    ["interface\\buttons\\white8x8"] = "WHITE",
    ["interface\\targetingframe\\ui-statusbar"] = "WHITE", -- the experience bar: its sheen not drawn
    ["interface\\minimap\\minimap-deadarrow"] = "@deadarrow", -- the minimap's corpse arrow: the page draws one
    ["interface\\characterframe\\ui-stateicon"] = "@rest", -- the level well's rest bubble: the page draws one
    ["interface\\minimap\\minimap-questarrow"] = "@questarrow",
}
local ATLAS = { -- Blizzard's atlases the HUD uses: the page's stand-ins
    ["UI-HUD-UnitFrame-Player-CombatIcon"] = "@combat", -- the level well's crossed swords in combat
}
local function short(file)
    if type(file) ~= "string" then return nil end
    if file:sub(1, 1) == "@" then return file end
    if file:sub(1, #MEDIA) == MEDIA then return file:sub(#MEDIA + 1) end
    return BLIZZARD[file:lower()]
end
local function turned(uv, angle)
    if not angle or angle == 0 then return uv end
    local cu, cv = (uv[1] + uv[7]) / 2, (uv[2] + uv[8]) / 2
    local c, s = math.cos(angle), math.sin(angle)
    local out = {}
    for i = 1, 7, 2 do
        local du, dv = uv[i] - cu, uv[i + 1] - cv
        out[i], out[i + 1] = cu + du * c - dv * s, cv + du * s + dv * c
    end
    return out
end
local unknown = {}
local function drawList()
    laid = {}
    local items = {}
    for _, r in ipairs(regions) do
        if r.kind == "Texture" and r:IsVisible() then
            local file = short(r.file) or (r.atlas and ATLAS[r.atlas])
            if not file and r.file then unknown[r.file] = true end
            local alpha, p = r.alpha * (r.colorAlpha or 1), r.parent
            while p do alpha = alpha * (p.alpha or 1); p = p.parent end
            if file and file ~= "FillNone" and alpha > 0.001 then
                local clip
                p = r.parent
                while p do
                    if p.clips then
                        local b = rectOf(p)
                        clip = clip and { math.max(clip[1], b[1]), math.max(clip[2], b[2]), math.min(clip[3], b[3]),
                            math.min(clip[4], b[4]) } or { b[1], b[2], b[3], b[4] }
                    end
                    p = p.parent
                end
                local masks = {}
                for _, m in ipairs(r.masks) do
                    local mf = short(m.file)
                    if mf and mf ~= "WHITE" then masks[#masks + 1] = { f = mf, r = rectOf(m) } end
                end
                local uv = r.texcoord or { 0, 0, 0, 1, 1, 0, 1, 1 }
                if r.fillOf then -- a status bar's fill shows the part of its texture it covers (cropped, not squeezed)
                    local f = share(r.fillOf)
                    uv = r.fillOf.orientation == "VERTICAL" and { 0, 1 - f, 0, 1, 1, 1 - f, 1, 1 } or { 0, 0, 0, 1, f, 0, f, 1 }
                end
                items[#items + 1] = { f = file, r = rectOf(r), uv = turned(uv, r.rotation),
                    c = r.color or { 1, 1, 1 }, a = alpha, add = r.blend == "ADD", rh = r.wrapH == "REPEAT",
                    rv = r.wrapV == "REPEAT",
                    m = masks, k = clip, order = { r.parent:GetFrameLevel(), LAYER[r.layer] or 3, r.sublevel or 0, r.index } }
            end
        end
    end
    for _, r in ipairs(regions) do -- text: its words, font, colour, box and turn (the page draws it)
        if r.kind == "FontString" and r.text and r.text ~= "" and r:IsVisible() then
            local c = r.textColor or { 1, 1, 1, 1 }
            local alpha, p = r.alpha * (c[4] or 1), r.parent
            while p do alpha = alpha * (p.alpha or 1); p = p.parent end
            local text = plainText(r.text)
            if alpha > 0.001 and text ~= "" then
                items[#items + 1] = { t = text, size = r.fontSize or 10, outline = (r.fontFlags or ""):find("OUTLINE") and true or false,
                    c = { c[1], c[2], c[3] }, a = alpha, r = rectOf(r), rot = r.rotation or 0, jh = r.justifyH or "CENTER",
                    sh = r.shadowColor and { r.shadowColor, r.shadowOffset or { 1, -1 } } or nil, m = {},
                    order = { r.parent:GetFrameLevel(), LAYER[r.layer] or 3, r.sublevel or 0, r.index } }
            end
        end
    end
    table.sort(items, function(a, b)
        for i = 1, 4 do if a.order[i] ~= b.order[i] then return a.order[i] < b.order[i] end end
        return false
    end)
    for _, it in ipairs(items) do it.order = nil end
    return items
end

local function frame(q)
    local dt = math.max(0, math.min(0.1, tonumber(q.dt) or 0))
    -- the character: turning (+ right: the facing goes down), moving along it, in the air or not
    local turn, fwd, lat = tonumber(q.turn) or 0, tonumber(q.fwd) or 0, tonumber(q.lat) or 0
    me.facing = (me.facing - math.rad(turn) * dt) % (2 * math.pi)
    local c, s = math.cos(me.facing), math.sin(me.facing)
    me.north = me.north + (fwd * c + lat * s) * dt
    me.west = me.west + (fwd * s - lat * c) * dt
    if q.jump == "1" then JumpOrAscendStart() end -- the jump key, before you leave the ground
    me.falling = q.air == "1"
    me.clock = me.clock + dt
    local north, west = (q.at or ""):match("^(%-?[%d.]+),(%-?[%d.]+)$") -- moved at once (a release, a spirit healer)
    if north then me.north, me.west = tonumber(north), tonumber(west) end
    north, west = (q.corpse or ""):match("^(%-?[%d.]+),(%-?[%d.]+)$")
    me.corpse = north and { tonumber(north), tonumber(west) } or nil
    me.view = tonumber(q.view) or me.view
    -- the mouse over a sphere: its OnEnter / OnLeave, as the game calls them (the values, the coordinates and zone name)
    local hover = (q.hover == "left" or q.hover == "pet" or q.hover == "map") and q.hover or "none"
    if hover ~= me.hover then
        local function leave(f) if f and f.scripts.OnLeave then f.scripts.OnLeave(f) end end
        local function enter(f) if f and f.scripts.OnEnter then f.scripts.OnEnter(f) end end
        if me.hover == "left" then leave(left) elseif me.hover == "pet" then leave(left.pet) end
        right.coordsHover = hover == "map" -- the minimap's OnEnter hook (S.PlaceMinimap's)
        if hover == "left" then enter(left) elseif hover == "pet" then enter(left.pet) end
        me.hover = hover
        S.UpdateValueVisibility()
    end
    local always = q.always == "1"
    if always ~= (ns.db.sphereValuesAlways == true) then -- the sphereValuesAlways setting
        ns.db.sphereValuesAlways = always
        S.UpdateValueVisibility()
    end
    local life = (q.life == "dead" or q.life == "ghost") and q.life or "alive"
    if life ~= me.life then -- the game's events: died, released (alive as a ghost), back to life
        local was = me.life
        me.life = life
        if life == "dead" then fire("PLAYER_DEAD")
        elseif life == "ghost" then fire("PLAYER_ALIVE")
        elseif was == "ghost" then fire("PLAYER_UNGHOST") else fire("PLAYER_ALIVE") end
    end
    me.hp, me.pp = tonumber(q.hp) or me.hp, tonumber(q.pp) or me.pp
    me.php, me.pmp = tonumber(q.php) or me.php, tonumber(q.pmp) or me.pmp
    me.power = POWER[q.power] and q.power or me.power
    me.pet = (q.pet == "beast" or q.pet == "demon") and q.pet or "none"
    me.xp, me.rested = tonumber(q.xp) or me.xp, tonumber(q.rested) or me.rested
    local level, resting, combat = me.level, me.resting, me.combat
    me.level = tonumber(q.level) or me.level -- at the top (GetMaxPlayerLevel) Track.lua gives the experience bar up
    if q.resting then me.resting = q.resting == "1" end
    me.combat = q.combat == "1"
    if me.level ~= level or me.resting ~= resting or me.combat ~= combat then
        S.UpdateCombat(me.combat) -- the level well: the level, the rest bubble and glow, or the swords in a fight (the game's events')
    end
    local statues = (q.statues == "modern" or q.statues == "charcoal" or q.statues == "none") and q.statues or me.statues
    if statues ~= me.statues then -- the Statues setting changed: S.Layout's paintArt
        me.statues, ns.db.statueFinish = statues, statues
        L.art()
        ns.Art.UpdateBezelStyle()
        right:ClearAllPoints()
        right:SetPoint("CENTER", hud, "BOTTOM", S.OrbOffset(), L.ORB_Y)
    end
    K.Update() -- the experience bar in the frame's slot
    if CLASS[q.class] and q.class ~= me.class then -- another class: the mana's magic
        me.class = q.class
        S.UpdateMagic()
    end
    -- the game's events: the pet's unit watch, then the left orb laid out and filled
    left.pet:SetShown(me.pet ~= "none")
    S.UpdateLeft()
    S.UpdatePet()
    if q.regen == "1" then S.LiquidChanged("health"); S.LiquidChanged("power") end
    -- the target's sphere: none, or what it is to you, its levels
    local looks = { hostile = true, neutral = true, friendly = true, tapped = true }
    me.target = (looks[q.target] or q.target == "none") and q.target or me.target
    me.thp, me.tpp = tonumber(q.thp) or me.thp, tonumber(q.tpp) or me.tpp
    me.tpower = POWER[q.tpower] and q.tpower or me.tpower
    local oldTarget = me.targetNpc
    me.targetNpc = q.targetNpc or (me.target ~= "none" and "manual" or "none")
    local npcSelected = me.targetNpc ~= "none" and me.targetNpc ~= "manual"
    me.targetName = q.targetName or (npcSelected and me.targetName or "")
    me.targetReaction = q.targetReaction or (npcSelected and me.targetReaction or "")
    me.targetLevel = tonumber(q.targetLevel) or me.targetLevel
    if oldTarget ~= me.targetNpc then fire("PLAYER_TARGET_CHANGED") end
    -- where the card hangs: 24 under the screen's top (Target.lua TOP), the HUD's bottom baseline
    local top = tonumber(q.top)
    if top and top ~= me.top then
        me.top = top
        target:ClearAllPoints()
        target:SetPoint("TOP", hud, "BOTTOM", 0, top - 24 + L.SINK)
    end
    target:SetShown(me.target ~= "none")
    if me.target ~= "none" then
        local reaction = me.targetReaction ~= "" and me.targetReaction or me.target
        target.avatar:SetTexture("@avatar-" .. (reaction == "friendly" and "sentinel"
            or reaction == "neutral" and "nightsaber" or "gnarlpine"))
        local p = POWER[me.tpower]
        S.TargetSphereDead(target, me.thp <= 0.0001) -- at 0: dead (its liquids gone)
        S.TargetSphereHealth(target, me.thp * MAX, MAX)
        local pmax = me.tpower == "none" and 0 or MAX -- none: no power, the whole sphere its health
        S.TargetSpherePower(target, me.tpp * pmax, pmax, p[1], p[2])
    end
    if q.hit == "player" or q.hit == "pet" then
        local amount = (tonumber(q.size) or 0.6) * MAX
        S.Wound(q.hit, q.hidden == "1" and hidden(amount) or amount)
    end
    for _, r in ipairs(regions) do -- every shown frame's OnUpdate: the liquids, the smoke
        local script = r.scripts.OnUpdate
        if script and r:IsVisible() then script(r, dt) end
    end
end

-------------------------------------------------------------------------------
-- Requests
-------------------------------------------------------------------------------
build()
local function bounds() -- the HUD: what the page frames, its bottom on the screen's
    local a = rectOf(hud)
    return { a[1], 0, a[3], a[4] }
end
-- a value as JSON can hold it: tables copied this deep (frames link back to their parents), functions named
local function plain(v, depth)
    local t = type(v)
    if t == "table" then
        if depth <= 0 then return "<table>" end
        local out, n = {}, 0
        for k, x in pairs(v) do
            n = n + 1
            if n > 64 then out["..."] = "more"; break end
            out[type(k) == "number" and k or tostring(k)] = plain(x, depth - 1)
        end
        return out
    elseif t == "function" or t == "userdata" or t == "thread" then return "<" .. t .. ">" end
    return v
end
local function handle(line)
    local cmd, rest = line:match("^(%S+)%s*(.*)$")
    if cmd == "init" then
        local keys = {}
        for key in pairs(GAME_SLOSH) do keys[#keys + 1] = key end
        table.sort(keys)
        laid = {}
        return { D = L.D, view = bounds(), slosh = M.SLOSH, game = GAME_SLOSH, keys = keys,
            rings = { orb = { S.OrbOffset(), L.ORB_Y }, ball = L.BALL, overlap = L.OVERLAP, hub = ns.Art.HUB_SIZE, socket = { S.SocketOffset("right") },
                sink = L.SINK } }
    elseif cmd == "frame" then
        local q = {}
        for k, v in rest:gmatch("(%w+)=(%S+)") do q[k] = v end
        frame(q)
        local list = {}
        for f in pairs(unknown) do list[#list + 1] = f end
        return { items = drawList(), unknown = list, frameTop = L.frameTop(), orbX = S.OrbOffset() }
    elseif cmd == "set" then
        local key, value = rest:match("^(%S+)%s+(%S+)")
        value = tonumber(value)
        if key and value and GAME_SLOSH[key] ~= nil then
            M.SLOSH[key] = value
            if key == "climb" then build() end -- its room is laid out when the liquids are built
            return { ok = true }
        end
        return { error = "no SLOSH value " .. tostring(key) }
    elseif cmd == "reset" then
        for k, v in pairs(GAME_SLOSH) do M.SLOSH[k] = v end
        build()
        return { ok = true }
    elseif cmd == "eval" then -- the harness (tools/sim_mcp.py): Lua run in here, with the add-on's tables at hand
        local chunk, err = loadstring("return " .. rest)
        if not chunk then chunk, err = loadstring(rest) end
        if not chunk then return { error = err } end
        setfenv(chunk, setmetatable({ S = S, M = M, L = L, K = K, ns = ns, me = me, hud = hud }, { __index = _G }))
        local ok, result = pcall(chunk)
        if not ok then return { error = tostring(result) } end
        return { result = plain(result, 3) }
    elseif cmd == "adopt" then -- exported into Motion.lua: the game's values now
        for k, v in pairs(M.SLOSH) do GAME_SLOSH[k] = v end
        return { ok = true }
    end
    return { error = "unknown request: " .. tostring(line) }
end

if selftest then
    local function fail(msg) io.stderr:write("sim bridge: FAIL: ", msg, "\n"); os.exit(1) end
    local function files(q)
        local items = handle("frame dt=0.016 " .. q).items
        local seen = {}
        for _, it in ipairs(items) do
            if it.f then seen[it.f] = true else seen["text " .. it.t] = true end -- a texture, or text
            for _, m in ipairs(it.m) do seen["mask " .. m.f] = true end
        end
        return seen, items
    end
    local seen, items = files("hp=0.7 pp=0.55 power=mana pet=none")
    for _, f in ipairs({ "OrbBack", "FillHealth", "FillMana", "LiquidCloud", "SurfaceCrest", "GlassHealth", "GlassMana",
        "@map", "MapDissolve", "MapCloud1", "MapCloud5", "GlassMap" }) do
        if not seen[f] then fail("health and mana: no " .. f .. " drawn") end
    end
    local at = {}
    for i, it in ipairs(items) do if it.f then at[it.f] = at[it.f] or i end end
    if not (at.WHITE < at.Frame1Modern and at.GlassHealth < at.Frame1Modern and at.Frame1Modern < at.StatueLeftModern) then
        fail("draw order: the experience bar and the glass under the frame, the statues over it")
    end
    for _, f in ipairs({ "Frame1Modern", "StatueLeftModern", "StatueRightModern", "WHITE" }) do
        if not seen[f] then fail("the default frame and statues (Modern): no " .. f .. " drawn") end
    end
    seen = files("statues=none")
    if seen.StatueLeft or seen.StatueLeftCharcoal or not seen.Frame1Charcoal then fail("no statues: still drawn") end
    seen = files("statues=modern")
    if not (seen.StatueLeftModern and seen.StatueRightModern and seen.Frame1Modern) then
        fail("modern: no modern statues and frame")
    end
    files("statues=charcoal")
    local function gold()
        local _, list = files("class=" .. me.class)
        for _, it in ipairs(list) do
            if it.f == "LiquidStream" and it.c[1] > 0.9 and it.c[3] < 0.4 and it.add then return true end
        end
    end
    if not gold() then fail("a paladin's mana: no golden currents") end
    files("class=mage")
    if gold() then fail("a mage's mana: golden currents") end
    files("class=priest")
    if not gold() then fail("a priest's mana: no golden current") end
    local function green()
        local _, list = files("class=" .. me.class)
        for _, it in ipairs(list) do
            if it.f == "LiquidStream" and it.c[2] > 0.9 and it.c[1] < 0.5 and it.add then return true end
        end
    end
    files("class=druid")
    if not green() or gold() then fail("a druid's mana: no green current") end
    local _, list = files("class=druid")
    for _, it in ipairs(list) do -- no purple swirl left (0.5.474)
        if it.f == "LiquidStream" and it.add and it.c[3] > it.c[2] and it.c[1] > it.c[2] then fail("a druid's mana: still purple") end
    end
    files("class=paladin")
    seen = files("power=rage pet=none")
    if not (seen.OrbBackWhole and seen.FillWhole and seen.FillPet and seen.GlassWhole) or seen.FillMana then
        fail("rage: not the whole sphere with the inner power")
    end
    files("level=60") -- the top level: Track.lua gives the experience bar up, the frame its slot (a frame on)
    seen = files("level=60")
    if not (seen.Frame0 or seen.Frame0Charcoal) or seen.Frame1 or seen.Frame1Charcoal then fail("level 60: the frame still has an experience slot") end
    files("level=30")
    seen = files("level=30")
    if not (seen.Frame1 or seen.Frame1Charcoal) then fail("level 30: no experience slot") end
    seen = files("power=energy pet=none") -- a druid's cat form
    if not (seen.FillWhole and seen.FillPet) or seen.FillMana then fail("energy: not the whole sphere with the inner power") end
    files("power=mana pet=none")
    seen = files("power=mana pet=demon")
    if not (seen.FillPetHealth and seen.FillPetMana and seen.PetBowl and seen["mask PetCavity"]) then
        fail("a pet with mana: no split pet orb in the scoop")
    end
    local list
    seen, list = files("power=mana pet=beast php=0.6")
    if not seen.FillPet or seen.FillPetMana then fail("a beast: no whole pet orb") end
    for _, it in ipairs(list) do -- its contact shadow: the ring's lower 60% shown, not the whole ring squeezed
        if it.f == "PetContactShadow" and math.abs(it.uv[2] - 0.4) > 1e-6 then fail("a status bar's fill squeezed, not cropped") end
    end
    local climbed, turnedCloud, first = false, false, nil
    for i = 1, 60 do
        local _, list = files(string.format("turn=%d power=mana pet=none", i <= 20 and 720 or 0))
        for _, it in ipairs(list) do
            if it.f == "SloshEdge" then climbed = true end
            if it.f == "MapCloud1" then
                first = first or it.uv[1]
                if math.abs(it.uv[1] - first) > 1e-4 then turnedCloud = true end
            end
        end
    end
    if not climbed then fail("a fast turn: no climb up the wall") end
    -- the target's sphere: its liquids cut round the portrait in its centre
    seen = files("target=hostile thp=0.5 tpp=0.6 power=mana pet=none")
    if not (seen["mask TargetCavity"] and seen.GlassHealth and seen.HubFrame) then fail("the target's sphere: not drawn") end
    -- split or whole, picked by the game: the other clipped away (its clip's width none)
    local function drawn(q, file)
        local _, list = files(q)
        for _, it in ipairs(list) do
            if it.f == file then return not it.k or it.k[3] - it.k[1] > 1 end
        end
        return false
    end
    if not (drawn("target=hostile tpower=none", "GlassTargetWhole") and not drawn("target=hostile tpower=none", "GlassTargetMana")) then
        fail("a target without power: not the whole sphere")
    end
    if not (drawn("target=hostile tpower=mana", "GlassTargetMana") and not drawn("target=hostile tpower=mana", "GlassTargetWhole")) then
        fail("a target with power: not split")
    end
    seen = files("target=none")
    if seen["mask TargetCavity"] then fail("no target: its sphere still drawn") end
    -- a big hit: a crack in your health's glass, cut to its piece, gone again after it mends
    local function cracked(q, mask)
        local lines, cut = 0, false
        local _, list = files(q)
        for _, it in ipairs(list) do
            if it.f == "CrackLine" then
                lines = lines + 1
                for _, m in ipairs(it.m) do cut = cut or m.f == mask end
            end
        end
        return lines, cut
    end
    handle("frame dt=0.016 hit=player power=mana pet=none")
    for _ = 1, 20 do files("power=mana pet=none") end
    local lines, cut = cracked("power=mana pet=none", "MaskHealth")
    if lines < 12 or not cut then fail("a big hit: no crack cut to the health piece (" .. lines .. " lines)") end
    for _ = 1, 60 * 6 do handle("frame dt=0.0167 power=mana pet=none") end
    if cracked("power=mana pet=none", "MaskHealth") > 0 then fail("a crack still shows after it mended") end
    handle("frame dt=0.016 hit=pet power=mana pet=demon")
    for _ = 1, 40 do files("power=mana pet=demon") end
    lines, cut = cracked("power=mana pet=demon", "MaskPetHealth")
    if lines < 8 or not cut then fail("a big hit on a demon: no crack in its health (" .. lines .. " lines)") end
    -- hidden blows: the gates show the small crack over 25%, the large over 40%, the huge over 60%, one at a time
    local function inGlass(q)
        local _, list = files(q)
        local n, all = 0, 0
        for _, it in ipairs(list) do
            if it.f == "CrackLine" then
                all = all + 1
                if it.k and it.k[3] >= it.r[3] and it.k[1] <= it.r[1] then n = n + 1 end
            end
        end
        return n, all
    end
    local function blow(size)
        for _ = 1, 60 * 6 do handle("frame dt=0.0167 power=mana pet=none") end
        handle("frame dt=0.016 hit=player hidden=1 power=mana pet=none size=" .. size)
        for _ = 1, 40 do files("power=mana pet=none") end
        return inGlass("power=mana pet=none")
    end
    if blow(0.2) > 0 then fail("a hidden blow of 20%: a crack not clipped away") end
    local small, allS = blow(0.3)
    local large, allL = blow(0.5)
    local huge, allH = blow(0.7)
    if not (small > 0 and small < allS) then fail("a hidden blow of 30%: not the small crack alone") end
    if not (large > 0 and large < allL) then fail("a hidden blow of 50%: not the large crack alone") end
    if not (huge >= 12 and huge < allH) then fail("a hidden blow of 70%: not the huge crack alone") end
    if not turnedCloud then fail("the map's smoke doesn't turn") end
    -- dying: both liquids empty (UnitIsDeadOrGhost). Released, a ghost gets the add-on's red arrow over the griffin
    -- toward its corpse only when that's past the minimap's reach behind the griffin (lower right: 400 yards to the
    -- south east here); not within reach, nor where the minimap's own arrow shows; none back to life.
    local function liquid(q)
        local _, list = files(q)
        for _, it in ipairs(list) do if it.f == "FillHealth" or it.f == "FillMana" then return true end end
    end
    if not liquid("life=alive hp=0.7 pp=0.55 power=mana pet=none at=0,0") then fail("alive: no liquid drawn") end
    if liquid("life=dead hp=0.7 pp=0.55 power=mana pet=none") then fail("dead: the liquids still drawn") end
    local function arrowFor(corpse)
        files("life=alive at=0,0")
        files("life=ghost at=0,0 corpse=" .. corpse)
        local seen
        for _ = 1, 10 do seen = files("life=ghost corpse=" .. corpse) end -- the arrow's checks, every 0.1 s
        return seen["@deadarrow"]
    end
    if not arrowFor("-346,-200") then fail("a ghost, its corpse far behind the griffin: no corpse arrow over it") end
    if arrowFor("-87,-50") then fail("a ghost, its corpse within the minimap's reach: a corpse arrow over the griffin") end
    if arrowFor("400,0") then fail("a ghost, its corpse far to the north: a corpse arrow over the griffin") end
    if files("life=alive")["@deadarrow"] then fail("back to life: the corpse arrow still shown") end
    -- text: the values on the spheres' curves while one's hovered (or always), the coordinates and the zone name glyph by
    -- glyph over the map while it is (the add-on's own OnEnter, layout and GetStringWidth)
    local function texts(q) -- the text drawn, but the level in its well
        local out = {}
        for _, it in ipairs(handle("frame dt=0.016 " .. q).items) do
            if it.t and not (it.size == 11 and it.t == tostring(me.level)) then out[#out + 1] = it end
        end
        return out
    end
    -- the level well (S.UpdateCombat, S.UpdateLevel, as the game's events call them): the level, the rest bubble and
    -- glow while resting; in a fight the swords with their beating outline instead of the level
    local level, swords, rest = false, 0, false
    for _, it in ipairs(handle("frame dt=0.016 level=27 resting=1 combat=0").items) do
        if it.t == "27" then level = true end
        if it.f == "@rest" then rest = true end
    end
    if not (level and rest) then fail("the level well: no level 27 and rest bubble while resting") end
    level = false
    for _, it in ipairs(handle("frame dt=0.016 level=27 resting=0 combat=1").items) do
        if it.t == "27" then level = true end
        if it.f == "@combat" then swords = swords + 1 end
    end
    if level or swords ~= 9 then fail("in a fight: the level still shown, or not the swords and their eight-copy outline") end
    handle("frame dt=0.016 level=30 resting=1 combat=0")
    if #texts("hover=none always=0") > 0 then fail("nothing hovered: text drawn") end
    local values = texts("hover=left")
    if #values ~= 6 or not values[2].t:find("/") or math.abs(values[1].rot) < 0.1 then
        fail("the left orb hovered: not its health and power values turned along its curve")
    end
    local map = texts("hover=map")
    local glyphs = {}
    for _, it in ipairs(map) do if it.size == 10 then glyphs[#glyphs + 1] = it.t end end
    if not table.concat(glyphs):find("Shadowglen") or #map < 20 then fail("the map hovered: no zone name and coordinates") end
    if #texts("hover=none always=1") < 26 then fail("values always shown: not all of them") end
    texts("hover=none always=0")
    if not json(handle("init")):find('"threshold"', 1, true) then fail("init: no SLOSH values") end
    io.stdout:write("sim bridge: ok (", #items, " textures a frame; mana, rage, energy, pets, level 60, death)\n")
    os.exit(0)
end

local function answer(line) -- one request's reply, as JSON
    local ok, reply = pcall(handle, line)
    if not ok then reply = { error = tostring(reply) } end
    return json(reply)
end
if SIM_EMBEDDED then -- in the page (tools/sim_lua.c): it asks a request at a time
    SimAsk = answer
    return
end
for line in io.lines() do
    io.stdout:write(answer(line), "\n")
    io.stdout:flush()
end
