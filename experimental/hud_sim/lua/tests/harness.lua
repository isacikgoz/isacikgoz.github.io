-- Mocked WoW API plus scenario tests for Spheres. Run from the add-on folder:
--   lua5.1 tests/harness.lua .
-- Action Ring's harness, adapted: secure frames refuse addon calls in combat (the game's
-- ADDON_ACTION_BLOCKED), the rings' snippets run in a stand-in for Blizzard's restricted
-- environment, hidden values refuse every Lua operation. Frames know where they are (a small
-- layout of their anchors), so docking on the collars is checked in screen coordinates.
-- It checks behaviour, not looks.
local dir = arg[1] or "."
local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.stdout:write("FAIL: " .. name .. "\n") end
end
local function near(a, b, tol) return a ~= nil and b ~= nil and math.abs(a - b) < (tol or 0.01) end

local T = 1000
function GetTime() return T end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- hidden values: refuse every Lua operation, like Forever's
local SECRET_MT = {}
local function refuse() error("attempt to use a secret value", 2) end
for _, m in ipairs({ "__eq", "__lt", "__le", "__concat", "__add", "__sub", "__mul", "__div", "__mod", "__pow",
    "__unm", "__len", "__tostring", "__call" }) do SECRET_MT[m] = refuse end
SECRET_MT.__index = function(t, k) if k == "__secret" or k == "v" then return rawget(t, k) end refuse() end
leanMode = false
HIDDEN_CACHE = {}
local function hide(v)
    if leanMode and v ~= nil then
        local h = HIDDEN_CACHE[v]
        if not h then h = setmetatable({ __secret = true, v = v }, SECRET_MT); HIDDEN_CACHE[v] = h end
        return h
    end
    return setmetatable({ __secret = true, v = v }, SECRET_MT)
end
function issecretvalue(v) return type(v) == "table" and rawget(v, "__secret") == true end
local function reveal(v) return issecretvalue(v) and rawget(v, "v") or v end

local printed = {}
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(t, " ")
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
local function saidSince(from, text)
    for i = from + 1, #printed do if printed[i]:find(text, 1, true) then return true end end
    return false
end

-------------------------------------------------------------------------------
-- combat lockdown, protected frames
-------------------------------------------------------------------------------
local combat = false
function InCombatLockdown() return combat end
local blocked = {}
local insideSecure = false
local PROTECTED_METHODS = { SetAttribute = true, SetPoint = true, ClearAllPoints = true, Show = true, Hide = true,
    SetShown = true, SetSize = true, SetWidth = true, SetHeight = true, StartMoving = true, RegisterForClicks = true,
    SetScale = true, EnableMouse = true, SetParent = true, SetID = true }

-------------------------------------------------------------------------------
-- frames, with a small layout: where a frame is follows from its first anchor
-------------------------------------------------------------------------------
local frames = {}
local runShowHide
LEAN_NOOP = function() end
LEAN = {}
UIParent = nil

NO_HOOKS = {} -- (not a new table a call: the game's Show and Hide make no garbage)
local function fireScript(self, name, ...)
    local fn = self.scripts[name]
    if fn then fn(self, ...) end
    for _, h in ipairs(self.hooks[name] or NO_HOOKS) do h(self, ...) end
end

local function setShown(self, on)
    on = on and true or false
    if self.shown == on then return end
    self.shown = on
    if self.showHide then runShowHide(self, on) end
    fireScript(self, on and "OnShow" or "OnHide")
end

local function anchorOffset(point, w, h)
    point = point or "CENTER"
    local x = point:find("LEFT") and 0 or (point:find("RIGHT") and w or w / 2)
    local y = point:find("BOTTOM") and 0 or (point:find("TOP") and h or h / 2)
    return x, y
end
local function rectOf(f, depth)
    depth = depth or 0
    if depth > 30 or not f then return nil end
    if f == UIParent then return 0, 0, f.w, f.h end
    local p = f.points and f.points[1]
    if not p then return nil end
    local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4], p[5]
    if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
    if type(rel) == "string" then rel = _G[rel] end
    rel = rel or f.parent or UIParent
    relPoint = relPoint or point
    local rl, rb, rw, rh = rectOf(rel, depth + 1)
    if not rl then return nil end
    local ax, ay = anchorOffset(relPoint, rw, rh)
    local w, h = f.w or 0, f.h or 0
    local ox, oy = anchorOffset(point, w, h)
    return rl + ax + (x or 0) - ox, rb + ay + (y or 0) - oy, w, h
end

do
    local L = LEAN
    L.Show = function(s) setShown(s, true) end
    L.Hide = function(s) setShown(s, false) end
    L.SetShown = function(s, v) setShown(s, v) end
    L.IsShown = function(s) return s.shown end
    L.IsVisible = function(s) return s.shown end
    L.GetParent = function(s) return s.parent end
    L.GetWidth = function(s) return s.w end
    L.GetHeight = function(s) return s.h end
    L.GetSize = function(s) return s.w, s.h end
    L.SetWidth = function(s, w) s.w = w end
    L.SetHeight = function(s, h) s.h = h end
    L.SetSize = function(s, w, h) s.w, s.h = w, h end
    L.GetFrameLevel = function(s) return s.level end
    L.SetFrameLevel = function(s, l) s.level = l end
    L.GetFrameStrata = function(s) return s.strata end
    L.GetText = function(s) return s.text end
    L.SetText = function(s, t) s.text = t end
    L.GetStringWidth = function(s) return #(type(s.text) == "string" and s.text or "") * (s.fontSize or 10) * 0.56 end
    L.GetFont = function(s) return "Fonts\\FRIZQT__.TTF", s.fontSize or 10, "" end
    L.GetScale = function(s) return s.scale end
    L.GetEffectiveScale = function(s) return s.effScale or 1 end
    L.GetAlpha = function(s) return s.alpha end
    L.SetAlpha = function(s, a) s.alpha = a end
    L.GetAtlas = function(s) return s.atlas end
    L.SetAtlas = function(s, a) s.atlas = a end
    L.GetTexture = function(s) return s.texture end
    L.SetTexture = function(s, t) s.texture = t end
    L.GetName = function(s) return s.name end
    L.IsObjectType = function(s, k) return s.kind == k end
    L.GetObjectType = function(s) return s.kind end
    L.GetNumPoints = function(s) return #s.points end
    L.GetPoint = function(s, i) local p = s.points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
    L.GetCenter = function(s) if s.cx then return s.cx, s.cy end local l, b, w, h = rectOf(s); if l then return l + w / 2, b + h / 2 end end
    L.GetLeft = function(s) local l = rectOf(s); return l end
    L.GetRight = function(s) local l, _, w = rectOf(s); return l and l + w end
    L.GetTop = function(s) local _, b, _, h = rectOf(s); return b and b + h end
    L.GetBottom = function(s) local _, b = rectOf(s); return b end
    L.SetValue = function(s, v) s.value = v end
    L.GetValue = function(s) return s.value end
    L.SetMinMaxValues = function(s, a, b) s.min, s.max = a, b end
    L.GetMinMaxValues = function(s) return s.min, s.max end
    L.GetStatusBarTexture = function(s) return s.barTexture end
    L.GetNormalTexture = function(s) return s.normal end
    L.GetAttribute = function(s, k) return s.attrs[k] end
    L.GetScript = function(s, k) return s.scripts[k] end
    L.GetID = function(s) return s.id end
    L.IsMouseOver = function() return false end
    L.IsForbidden = function() return false end
    L.GetZoom = function(s) return s.zoom or 0 end
    L.GetZoomLevels = function() return 5 end
    L.GetChildren = function(s) return unpack(s.kids or LEAN_EMPTY) end
end
LEAN_EMPTY = {}
local function newFrame(kind, name, parent, template)
    local o = { kind = kind, name = name, parent = parent, template = template, shown = true, scripts = {}, hooks = {},
        points = {}, level = 1, w = 0, h = 0, attrs = {}, refs = {}, wraps = {}, anims = {}, scale = 1, alpha = 1, id = 0,
        masks = {}, events = {} }
    o.mockProtected = template ~= nil and template:find("Secure") ~= nil
    if parent then parent.kids = parent.kids or {}; table.insert(parent.kids, o) end
    o.showHide = template == "SecureHandlerShowHideTemplate"
    if o.mockProtected then
        local p = parent
        while p do p.mockImplicit = true; p = p.parent end
    end
    setmetatable(o, { __index = function(_, k)
        if k == "Selection" then return nil end -- optional child frame, not a callable API
        if type(k) ~= "string" or not k:match("^%u") then return nil end
        if leanMode then return LEAN[k] or LEAN_NOOP end
        return function(self, ...)
            local a = { ... }
            if combat and (self.mockProtected or self.mockImplicit) and PROTECTED_METHODS[k] and not insideSecure then
                blocked[#blocked + 1] = k .. " on " .. tostring(self.name)
                return
            end
            if k == "Show" then setShown(self, true)
            elseif k == "Hide" then setShown(self, false)
            elseif k == "SetShown" then setShown(self, a[1])
            elseif k == "IsShown" or k == "IsVisible" then return self.shown
            elseif k == "SetScript" then self.scripts[a[1]] = a[2]
            elseif k == "HookScript" then
                self.hooks[a[1]] = self.hooks[a[1]] or {}
                table.insert(self.hooks[a[1]], a[2])
            elseif k == "GetScript" then return self.scripts[a[1]]
            elseif k == "SetAttribute" then self.attrs[a[1]] = a[2]
            elseif k == "GetAttribute" then return self.attrs[a[1]]
            elseif k == "SetID" then self.id = a[1]
            elseif k == "GetID" then return self.id
            elseif k == "GetName" then return self.name
            elseif k == "GetChildren" then return unpack(self.kids or {})
            elseif k == "IsObjectType" then return self.kind == a[1]
            elseif k == "GetParent" then return self.parent
            elseif k == "SetParent" then
                if self.parent and self.parent.kids then
                    for i, c in ipairs(self.parent.kids) do if c == self then table.remove(self.parent.kids, i) break end end
                end
                self.parent = a[1]
                if a[1] then a[1].kids = a[1].kids or {}; table.insert(a[1].kids, self) end
            elseif k == "SetText" then self.text = a[1]
            elseif k == "GetFont" then if self.kind == "FontString" then return "Fonts\\FRIZQT__.TTF", self.fontSize or 10, "" end
            elseif k == "SetFont" then self.fontSize = a[2]
            elseif k == "GetStringWidth" then return #(self.text or "") * (self.fontSize or 10) * 0.56
            elseif k == "SetFormattedText" then -- the game formats hidden values: the text is hidden then
                local hidden = false
                for i = 2, #a do if issecretvalue(a[i]) then hidden = true; a[i] = reveal(a[i]) end end
                local t = string.format(unpack(a))
                self.text = hidden and hide(t) or t
            elseif k == "SetJustifyH" then self.justifyH = a[1]
            elseif k == "GetText" then return self.text
            elseif k == "SetTextColor" then self.color = a
            elseif k == "SetSize" then self.w, self.h = a[1], a[2]
            elseif k == "SetWidth" then self.w = a[1]
            elseif k == "SetHeight" then self.h = a[1]
            elseif k == "GetWidth" then return self.w
            elseif k == "GetHeight" then return self.h
            elseif k == "GetSize" then return self.w, self.h
            elseif k == "GetFrameLevel" then return self.level
            elseif k == "SetFrameLevel" then self.level = a[1]
            elseif k == "GetFrameStrata" then return self.strata
            elseif k == "SetFrameStrata" then
                local function set(f) f.strata = a[1]; for _, c in ipairs(f.kids or {}) do set(c) end end
                set(self)
            elseif k == "SetStartPoint" then self.start = a
            elseif k == "SetEndPoint" then self.finish = a
            elseif k == "SetPoint" then self.points[#self.points + 1] = a
            elseif k == "ClearAllPoints" then self.points = {}
            elseif k == "SetAllPoints" then
                local rel = a[1] or self.parent
                self.points = { { "CENTER", rel, "CENTER", 0, 0 } }
                self.w, self.h = rel and rel.w or 0, rel and rel.h or 0
            elseif k == "GetNumPoints" then return #self.points
            elseif k == "GetPoint" then local p = self.points[a[1] or 1] or {}; return p[1], p[2], p[3], p[4], p[5]
            elseif k == "GetCenter" then
                if self.cx then return self.cx, self.cy end
                local l, b, w, h = rectOf(self)
                if l then return l + w / 2, b + h / 2 end
            elseif k == "GetLeft" then
                if self.left then return self.left end
                local l = rectOf(self); return l
            elseif k == "GetRight" then
                if self.right then return self.right end
                local l, _, w = rectOf(self); return l and l + w
            elseif k == "GetBottom" then local _, b = rectOf(self); return b
            elseif k == "GetTop" then local _, b, _, h = rectOf(self); return b and b + h
            elseif k == "SetScale" then self.scale = a[1]
            elseif k == "GetScale" then return self.scale
            elseif k == "GetEffectiveScale" then return self.effScale or 1
            elseif k == "SetAlpha" then self.alpha = a[1]
            elseif k == "GetAlpha" then return self.alpha
            elseif k == "SetRotation" then self.rotation = a[1]
            elseif k == "EnableMouse" then self.mouse = a[1]
            elseif k == "EnableMouseWheel" then self.wheel = a[1]
            elseif k == "SetAtlas" then self.atlas = a[1]
            elseif k == "GetAtlas" then return self.atlas
            elseif k == "SetTexture" then self.texture, self.wrap, self.wrapV = a[1], a[2], a[3]
            elseif k == "SetTexCoord" then self.texcoord = a
            elseif k == "GetTexture" then return self.texture
            elseif k == "SetColorTexture" then self.colorTexture = a
            elseif k == "SetVertexColor" then self.vertex = a
            elseif k == "SetBlendMode" then self.blend = a[1]
            elseif k == "SetClipsChildren" then self.clips = a[1]
            elseif k == "SetRenderMode" then self.renderMode = a[1]
            elseif k == "SetHitRectInsets" then self.hitInsets = a
            elseif k == "AddMaskTexture" then self.masks[#self.masks + 1] = a[1]
            elseif k == "GetNumMaskTextures" then return #self.masks
            elseif k == "RemoveMaskTexture" then
                for i, m in ipairs(self.masks) do if m == a[1] then table.remove(self.masks, i) break end end
            elseif k == "SetMaskTexture" then self.maskFile = a[1]
            elseif k == "RegisterForClicks" then self.clicks = a
            elseif k == "RegisterEvent" or k == "RegisterUnitEvent" then self.events[a[1]] = a[2] or true
            elseif k == "SetStatusBarTexture" then -- a texture object (the bar takes it), or a file/atlas name
                if type(a[1]) == "table" then self.barTexture = a[1]
                else
                    self.barTexture = self.barTexture or newFrame("Texture", nil, self)
                    self.barTexture.atlas, self.barTexture.texture = a[1], a[1]
                end
            elseif k == "GetStatusBarTexture" then return self.barTexture
            elseif k == "SetMinMaxValues" then self.min, self.max = a[1], a[2]
            elseif k == "SetValue" then self.value, self.interpolation = a[1], a[2]
            elseif k == "GetValue" then return self.value
            elseif k == "SetOrientation" then self.orientation = a[1]
            elseif k == "SetReverseFill" then self.reverse = a[1]
            elseif k == "SetStatusBarColor" then self.color = a
            elseif k == "GetNormalTexture" then return self.normal
            elseif k == "SetCooldownFromDurationObject" then self.cooldown = { kind = "duration", obj = a[1] }
            elseif k == "SetCooldown" then
                for _, v in ipairs(a) do if issecretvalue(v) then error("secret value to SetCooldown") end end
                self.cooldown = { kind = "numbers", start = a[1], duration = a[2] }
            elseif k == "Clear" then self.cooldown = nil
            elseif k == "CreateTexture" or k == "CreateFontString" or k == "CreateMaskTexture" or k == "CreateLine" then
                if a[4] ~= nil and (a[4] < -8 or a[4] > 7) then -- as the game: it throws
                    error(k .. ": sublevel " .. tostring(a[4]) .. " out of -8..7", 2)
                end
                local t = newFrame(k == "CreateFontString" and "FontString" or k == "CreateLine" and "Line"
                    or k == "CreateMaskTexture" and "MaskTexture" or "Texture", nil, self)
                t.layer, t.sublevel, t.font = a[2], a[4], a[3]
                return t
            elseif k == "CreateAnimationGroup" then
                local ag = newFrame("AnimationGroup", nil, self)
                ag.plays = 0
                function ag:CreateAnimation(kind2) local an = newFrame(kind2, nil, self)
                    function an:SetOffset(x, y) self.offset = { x, y } end
                    return an end
                function ag:Play() self.plays = self.plays + 1 end
                self.anims[#self.anims + 1] = ag
                return ag
            elseif k == "Click" then self.clicked = (self.clicked or 0) + 1
            elseif k == "GetZoom" then return self.zoom or 0
            elseif k == "SetZoom" then self.zoom = a[1]
            elseif k == "GetZoomLevels" then return 5
            end
        end
    end })
    if name then _G[name] = o end
    frames[#frames + 1] = o
    return o
end
function CreateFrame(kind, name, parent, template)
    local f = newFrame(kind, name, parent, template)
    if template == "AutoCastOverlayTemplate" then -- Blizzard's autocast ants: shown, and turning while on
        function f:ShowAutoCastEnabled(on) self.enabled = on end
    elseif template == "EditModeSystemSelectionBaseTemplate" then
        -- Blizzard's XML has parentKey="Selection": CreateFrame writes this before OnLoad.
        parent.Selection = f
        function f:ShowHighlighted() self.isSelected = false; self:Show() end
        function f:ShowSelected() self.isSelected = true; self:Show() end
    end
    return f
end
EditModeSystemSelectionBaseMixin = {} -- enable the real selection-template path on the mocked client
UIParent = newFrame("Frame", "UIParent")
UIParent.w, UIParent.h = 1920, 1080
function hooksecurefunc(obj, method, fn)
    if type(obj) == "string" then
        local name, hook = obj, method
        local orig = _G[name]
        _G[name] = function(...)
            local r = { orig(...) }
            local s = insideSecure
            insideSecure = false
            hook(...)
            insideSecure = s
            return unpack(r)
        end
        return
    end
    local orig = obj[method]
    rawset(obj, method, function(...)
        local r = { orig(...) }
        local s = insideSecure
        insideSecure = false
        fn(...)
        insideSecure = s
        return unpack(r)
    end)
end

GameTooltip = newFrame("GameTooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner, anchor) self.lines = {}; self.owner, self.anchor = owner, anchor end
function GameTooltip:IsOwned(f) return self.owner == f end
function GameTooltip:SetText(t) self.lines = { t } end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " " .. r end
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:SetAction(slot)
    if ACTIONS[slot] then self.lines = { "spell " .. ACTIONS[slot].name }; return true end
end
local function tipText() return table.concat(GameTooltip.lines, "|") end

local ATLASES = { asked = 0 }
-- an atlas: its file and where it sits in it (the reservoir's liquids: somewhere in a sheet)
C_Texture = { GetAtlasInfo = function(n)
    ATLASES[n] = true
    ATLASES.asked = ATLASES.asked + 1
    if n:find("reservoir%-full") then
        return { file = "file:" .. n, leftTexCoord = 0.3, rightTexCoord = 0.5, topTexCoord = 0.6, bottomTexCoord = 1.0 }
    end
    return {}
end }
local events = {}
EventRegistry = { RegisterCallback = function(_, event, fn, owner) events[event] = function(...) fn(owner, ...) end end }

-------------------------------------------------------------------------------
-- Blizzard's bottom of the screen: the bars, the menu, the bags, the status bars, the minimap
-------------------------------------------------------------------------------
MicroMenuContainer = newFrame("Frame", "MicroMenuContainer", UIParent)
MicroMenu = newFrame("Frame", "MicroMenu", MicroMenuContainer)
rawset(MicroMenu, "MarkDirty", function(self) self.dirty = (self.dirty or 0) + 1 end)
MainActionBar = newFrame("Frame", "MainActionBar", UIParent, "SecureActionBarStandIn")
for i = 1, 12 do newFrame("CheckButton", "ActionButton" .. i, MainActionBar, "SecureActionButtonTemplate") end
for _, n in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }) do
    newFrame("Frame", n, UIParent, "SecureActionBarStandIn")
end
StanceBar = newFrame("Frame", "StanceBar", UIParent, "SecureStanceBarStandIn")
PetActionBar = newFrame("Frame", "PetActionBar", UIParent, "SecurePetBarStandIn")
rawset(PetActionBar, "IsInDefaultPosition", function() return true end)
PetActionBar.points = { { "BOTTOM", MainActionBar, "TOP", 0, 40 } }
PetActionBar.w, PetActionBar.h, PetActionBar.shown = 300, 30, false -- no pet
PetActionBar.actionButtons = {}
for i = 1, 10 do
    local pb = newFrame("CheckButton", "PetActionButton" .. i, PetActionBar, "SecurePetButtonStandIn")
    pb.id = i
    pb.scripts.OnClick = function(self, button)
        if button == "LeftButton" then CastPetAction(self:GetID()) else TogglePetAutocast(self:GetID()) end
    end
    rawset(pb, "Click", function(self, button) self.scripts.OnClick(self, button or "LeftButton") end)
    PetActionBar.actionButtons[i] = pb
end
PlayerCastingBarFrame = newFrame("StatusBar", "PlayerCastingBarFrame", UIParent)
rawset(PlayerCastingBarFrame, "IsInDefaultPosition", function() return true end)
PlayerCastingBarFrame.points = { { "BOTTOM", UIParent, "BOTTOM", 0, 120 } }
PlayerFrame = newFrame("Button", "PlayerFrame", UIParent, "SecureUnitButtonTemplate")
BagsBar = newFrame("Frame", "BagsBar", UIParent)
rawset(BagsBar, "Layout", function(self) self.layouts = (self.layouts or 0) + 1 end)
for _, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "KeyRingButton" }) do -- no reagent bag in this client
    local b = newFrame("ItemButton", n, BagsBar)
    b:SetSize(45, 45)
    b.icon = newFrame("Texture", nil, b)
    b.icon:SetSize(37, 37)
    b.icon:SetPoint("CENTER", b, "CENTER")
    b.SquareMask = newFrame("MaskTexture", nil, b)
    b.SquareMask:SetSize(45, 45)
    b.normalAndPushedTextureWidth, b.normalAndPushedTextureHeight = 46, 46
    b.scripts.OnClick = function(self) self.opened = (self.opened or 0) + 1 end
end
local MICRO = { CharacterMicroButton = "Character", ProfessionMicroButton = "Professions", SpellbookMicroButton = "Spellbook",
    TalentMicroButton = "SpecTalents", QuestLogMicroButton = "Questlog", GuildMicroButton = "Guild", LFDMicroButton = "Groupfinder",
    CollectionsMicroButton = "Collections", HelpMicroButton = "Help", MainMenuMicroButton = "GameMenu" }
for name, tex in pairs(MICRO) do
    local m = newFrame("Button", name, MicroMenu)
    m.textureName = tex
    m.tooltipText = tex .. " (key)"
    m.normal = newFrame("Texture", nil, m)
    m.normal.atlas = "UI-HUD-MicroMenu-" .. tex .. "-Up"
end
MainMenuMicroButton.scripts.OnClick = function(self) self.opened = (self.opened or 0) + 1 end
NET_STATS = { home = 45, world = 61 }
function GetNetStats() return 0, 0, NET_STATS.home, NET_STATS.world end
function GetFramerate() return 143.6 end
function MainMenuBarPerformanceBarFrame_OnEnter(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(owner.tooltipText)
    GameTooltip:AddLine("Latency: 45 / 61")
    GameTooltip:AddLine("Framerate: 143.6")
    GameTooltip:Show()
end
function SetPortraitTexture(t, unit) t.portraitOf = unit end
-- the experience bar's container, where Blizzard puts it
StatusTrackingBarManager = newFrame("Frame", "StatusTrackingBarManager", UIParent)
STATUS_BAR_SIZE_ADJUSTMENT = 3
function StatusTrackingBarManager:CheckForLayoutChange() self.relayouts = (self.relayouts or 0) + 1 end
MainStatusTrackingBarContainer = newFrame("Frame", "MainStatusTrackingBarContainer", StatusTrackingBarManager)
MainStatusTrackingBarContainer.w, MainStatusTrackingBarContainer.h = 1192, 17
MainStatusTrackingBarContainer.points = { { "BOTTOM", MainActionBar, "TOP", 0, 0 } }
rawset(MainStatusTrackingBarContainer, "IsInDefaultPosition", function() return true end)
MainStatusTrackingBarContainer.BarFrameTexture = newFrame("Texture", nil, MainStatusTrackingBarContainer)
MainStatusTrackingBarContainer.BarFrameTexture.points = { { "CENTER", MainStatusTrackingBarContainer, "CENTER", 0, 0 } }
MainStatusTrackingBarContainer.BarFrameTexture.w, MainStatusTrackingBarContainer.BarFrameTexture.h = 1200, 23
MainStatusTrackingBarContainer.bars = { [4] = newFrame("Frame", nil, MainStatusTrackingBarContainer) }
MainStatusTrackingBarContainer.bars[4].StatusBar = newFrame("StatusBar", nil, MainStatusTrackingBarContainer.bars[4])
StatusTrackingBarManager.barContainers = { MainStatusTrackingBarContainer }
-- the minimap, top right in its cluster, with its zoom buttons and compass ring
MinimapCluster = newFrame("Frame", "MinimapCluster", UIParent)
MinimapCluster.points = { { "TOPRIGHT", UIParent, "TOPRIGHT", 0, 0 } }
MinimapCluster.w, MinimapCluster.h = 230, 260
Minimap = newFrame("Frame", "Minimap", MinimapCluster)
Minimap.w, Minimap.h = 200, 200
Minimap.points = { { "TOP", MinimapCluster, "TOP", 0, -30 } }
Minimap.ZoomIn = newFrame("Button", "MinimapZoomIn", Minimap)
Minimap.ZoomOut = newFrame("Button", "MinimapZoomOut", Minimap)
MinimapCompassTexture = newFrame("Texture", "MinimapCompassTexture", MinimapCluster)
-- its header, as Forever has it: the zone name with the clock in it, tracking (a dropdown),
-- the calendar, the mail icon, the add-on compartment (a dropdown)
MinimapCluster.ZoneTextButton = newFrame("Button", nil, MinimapCluster)
MinimapCluster.ZoneTextButton.points = { { "TOP", MinimapCluster, "TOP", 0, 0 } }
MinimapCluster.Tracking = newFrame("Frame", nil, MinimapCluster)
local tracking = newFrame("DropdownButton", nil, MinimapCluster.Tracking)
MinimapCluster.Tracking.Button = tracking
tracking.points = { { "CENTER", MinimapCluster.Tracking, "CENTER", 0, 0 } }
tracking.w, tracking.h = 23, 23
-- their art (Forever's bronze square round the logo) and its additive hover copy
tracking.StateTexture = newFrame("Texture", nil, tracking)
tracking.AddTexture = newFrame("Texture", nil, tracking)
rawset(tracking, "OnMenuClosed", function(self) self.closed = (self.closed or 0) + 1 end)
MinimapCluster.IndicatorFrame = newFrame("Frame", nil, MinimapCluster)
-- the group finder eye: its own frame on UIParent, anchored by Edit Mode to the minimap's edge
QueueStatusButton = newFrame("Button", "QueueStatusButton", UIParent)
QueueStatusButton.strata, QueueStatusButton.level = "MEDIUM", 2
QueueStatusButton.points = { { "BOTTOMLEFT", Minimap, "BOTTOMLEFT", -6, -6 } }
local mail = newFrame("Frame", nil, MinimapCluster.IndicatorFrame)
MinimapCluster.IndicatorFrame.MailFrame = mail
mail.points = { { "TOPLEFT", MinimapCluster.IndicatorFrame, "TOPLEFT", 0, 0 } }
GameTimeFrame = newFrame("Button", "GameTimeFrame", MinimapCluster)
GameTimeFrame.points = { { "TOPLEFT", MinimapCluster.ZoneTextButton, "TOPRIGHT", -4, 0 } }
GameTimeFrame.w, GameTimeFrame.h = 23, 23
GameTimeFrame.scripts.OnClick = function(self) self.opened = (self.opened or 0) + 1 end
AddonCompartmentFrame = newFrame("DropdownButton", "AddonCompartmentFrame", MinimapCluster)
rawset(AddonCompartmentFrame, "OnMenuClosed", function() end)
AddonCompartmentFrame.w, AddonCompartmentFrame.h = 23, 22
AddonCompartmentFrame.StateTexture = newFrame("Texture", nil, AddonCompartmentFrame)
AddonCompartmentFrame.AddTexture = newFrame("Texture", nil, AddonCompartmentFrame)
-- the game's day and night (Forever's minimap shows it on its rim) and the server's clock
C_DateAndTime = { day = true, IsDayTime = function() return C_DateAndTime.day end }
function GetGameTime() return 14, 5 end
TimeManagerClockButton = newFrame("Button", "TimeManagerClockButton", MinimapCluster)
TimeManagerClockButton.points = { { "RIGHT", MinimapCluster.ZoneTextButton, "RIGHT", -3, -1 } }
-- where you are: Durotar, 45.23, 67.81 (nothing in an instance)
local WHERE = { map = 1411, x = 0.4523, y = 0.6781 }
function CreateVector2D(x, y)
    return { x = x, y = y, GetXY = function(v) return v.x, v.y end, SetXY = function(v, a, b) v.x, v.y = a, b end }
end
-- Durotar as 1500 yards wide and 1000 tall on continent 1: world x grows north, y west
C_Map = {
    GetBestMapForUnit = function() return WHERE.map end,
    GetPlayerMapPosition = function(map)
        if not map or not WHERE.x then return nil end
        return { GetXY = function() return WHERE.x, WHERE.y end }
    end,
    GetWorldPosFromMapPos = function(map, v)
        if map ~= WHERE.map then return nil end
        return 1, CreateVector2D((1 - v.y) * 1000, (1 - v.x) * 1500)
    end,
    GetUserWaypoint = function() return WHERE.track.pin end,
}
-- what you super-track: a quest (its place on the map, or a waypoint toward it) or your map pin
WHERE.track = { view = 233, facing = 0 }
C_SuperTrack = {
    IsSuperTrackingQuest = function() return WHERE.track.quest ~= nil end,
    GetSuperTrackedQuestID = function() return WHERE.track.quest end,
    IsSuperTrackingUserWaypoint = function() return WHERE.track.pin ~= nil end,
}
-- the game's add-on profiler: milliseconds a frame (Spheres 0.08 of the add-ons' 0.6, the whole frame 7.2)
C_AddOnProfiler = {
    GetAddOnMetric = function(name, m) return ({ [1] = 0.08, [4] = 3.4, [5] = 14, [6] = 0 })[m] end,
    GetOverallMetric = function() return 0.6 end,
    GetApplicationMetric = function() return 7.2 end,
}
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage() return 1534 end
function UnitPosition(unit) -- the same world as GetWorldPosFromMapPos: x north, y west, continent 1
    if unit ~= "player" or not WHERE.x or WHERE.track.noUnitPosition then return nil end
    return (1 - WHERE.y) * 1000, (1 - WHERE.x) * 1500, 0, 1
end
C_Minimap = { GetViewRadius = function() return WHERE.track.view end, IsRotateMinimapIgnored = function() return false end,
    IsInsideQuestBlob = function() return WHERE.track.inside == true end }
function GetPlayerFacing() return WHERE.track.facing end
-- your corpse, while you're a ghost: a place on your map
function UnitIsGhost(u) return u == "player" and WHERE.track.ghost == true end
C_DeathInfo = { GetCorpseMapPosition = function(map)
    local c = WHERE.track.corpse
    if map ~= WHERE.map or not c then return nil end
    return CreateVector2D(c[1], c[2])
end }
MINIMAP_PLAYER_COORDS_INTEGER = "%d, %d"
-- buffs and debuffs where Edit Mode puts them by default (255 px in, clear of the header)
local AURA_HOME = {}
for name, xy in pairs({ BuffFrame = { -255, -10 }, DebuffFrame = { -270, -155 } }) do
    local f = newFrame("Frame", name, UIParent)
    f.points = { { "TOPRIGHT", UIParent, "TOPRIGHT", xy[1], xy[2] } }
    AURA_HOME[f] = { inDefault = true, xy = xy }
    rawset(f, "IsInDefaultPosition", function(self) return AURA_HOME[self].inDefault end)
    rawset(f, "ApplySystemAnchor", function(self)
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", AURA_HOME[self].xy[1], AURA_HOME[self].xy[2])
    end)
    -- sized for a full row (11 icons and its collapse arrow), its icons right to left from its top right
    f.w, f.h = 11 * 35 + 15, 3 * 35
    f.CollapseAndExpandButton = newFrame("CheckButton", nil, f)
    f.auraFrames = {}
    for i = 1, 24 do
        local b = newFrame("Button", nil, f)
        b.w, b.h = 30, 30
        b.points = { { "TOPRIGHT", f, "TOPRIGHT", -15 - ((i - 1) % 11) * 35, -math.floor((i - 1) / 11) * 35 } }
        f.auraFrames[i] = b
    end
    rawset(f, "UpdateGridLayout", function(self)
        for i, b in ipairs(self.auraFrames) do b.shown = i <= self.n end
    end)
    f.n = name == "BuffFrame" and 3 or 2
    f:UpdateGridLayout()
end
-- Blizzard's bottom container (extra ability buttons, alternate power, cooldown viewer)
local bottomBox = newFrame("Frame", "BottomManagedFrameContainer", UIParent)
bottomBox.w, bottomBox.h = 573, 40
bottomBox.points = { { "BOTTOM", UIParent, "BOTTOM", 0, 120 } }
function GetBottomManagedFrameContainer() return bottomBox end
local CURSOR = { 0, 0 }
function GetCursorPosition() return CURSOR[1], CURSOR[2] end
-- the mouse's own moves, its buttons, the cursor shown or hidden (a camera drag hides it), your speed
MOUSE = { dx = 0, dy = 0, left = false, right = false, hidden = false }
function GetCursorDelta() return MOUSE.dx, MOUSE.dy end
function IsMouseButtonDown(b) return b == "LeftButton" and MOUSE.left or b == "RightButton" and MOUSE.right or false end
function IsCursorVisible() return not MOUSE.hidden end
function IsMouselooking() return MOUSE.right end
function GetUnitSpeed() return 7 end
function IsFalling() return MOUSE.falling == true end
function JumpOrAscendStart() end

-- you: a Horde Paladin, 750 of 1000 health and 300 of 600 mana (hidden from add-ons, like Forever)
function UnitClass() return "Paladin", "PALADIN" end
function UnitFactionGroup() return "Horde" end
local HP = { cur = 750, max = 1000, power = 300, powerMax = 600, ptype = 0, token = "MANA" }
-- your experience: level 20 of 60, 450 of 1000, 200 rested; no faction watched yet
local XPS = { level = 20, cur = 450, max = 1000, rested = 200 }
-- your target: a Defias Pillager, its numbers hidden too
local TGT = { exists = false, hp = 400, max = 800, name = "Defias Pillager", level = 15, reaction = 2, class = "elite" }
-- your pet: a Hunter's wolf, 180 of 300 health and 50 of 100 focus, happy
local PET = { exists = true, cur = 180, max = 300, power = 50, powerMax = 100, ptype = 2, token = "FOCUS",
    hunter = true, mood = 3, dead = false }
function UnitExists(u) if u == "target" then return TGT.exists elseif u == "pet" then return PET.exists end return true end
function UnitHealth(u)
    if u == "target" then return hide(TGT.hp) elseif u == "pet" then return hide(PET.cur) end
    return hide(HP.cur)
end
function UnitHealthMax(u)
    if u == "target" then return hide(TGT.max) elseif u == "pet" then return hide(PET.max) end
    return hide(HP.max)
end
function UnitPower(u) if u == "pet" then return hide(PET.power) end return hide(HP.power) end
function UnitPowerMax(u)
    if u == "pet" then return hide(PET.powerMax) end
    if u == "target" and TGT.powerMax ~= nil then return TGT.powerMax end -- (plain: a whole target sphere's test)
    return hide(HP.powerMax)
end
function UnitPowerType(u) if u == "pet" then return PET.ptype, PET.token end return HP.ptype, HP.token end
function UnitIsDead(u) if u == "target" then return TGT.dead or false end return u == "pet" and PET.dead end
function HasPetUI() return PET.exists, PET.hunter end
C_PetInfo = { GetPetHappiness = function() if PET.exists and PET.hunter then return PET.mood, 125, 1 end end }
-- its action slots: Attack (attacking now), Bite (autocast on, out of range, cooling down), Growl (not usable now)
PET.acts = {
    [1] = { name = "PET_ACTION_ATTACK", texture = "PET_ATTACK_TEXTURE", token = true, active = true, attack = true },
    [4] = { name = "Bite", texture = "Interface\\Icons\\Ability_Racial_Cannibalize", allowed = true, auto = true,
        spell = 17253, range = true, inRange = false, cd = { 100, 10, 1 } },
    [5] = { name = "Growl", texture = "Interface\\Icons\\Ability_Physical_Taunt", allowed = true, spell = 2649,
        usable = false },
}
PET.cast, PET.picked = {}, {}
PET_ACTION_ATTACK, PET_ATTACK_TEXTURE = "Attack", "Interface\\Icons\\Ability_GhoulFrenzy"
function GetPetActionInfo(i)
    local a = PET.exists and PET.acts[i]
    if a then return a.name, a.texture, a.token or false, a.active or false, a.allowed or false, a.auto or false,
        a.spell, a.range or false, a.inRange end
end
function GetPetActionCooldown(i) local a = PET.acts[i]; if a and a.cd then return unpack(a.cd) end return 0, 0, 1 end
function GetPetActionSlotUsable(i) local a = PET.acts[i]; return a ~= nil and a.usable ~= false end
function IsPetAttackAction(i) local a = PET.acts[i]; return a ~= nil and a.attack == true end
function CastPetAction(i) PET.cast[#PET.cast + 1] = i end
function TogglePetAutocast(i) local a = PET.acts[i]; if a then a.auto = not a.auto end end
function PickupPetAction(i) PET.picked[#PET.picked + 1] = i end
function GameTooltip:SetPetAction(i)
    local a = PET.exists and PET.acts[i]
    if a then self.lines = { "pet " .. a.name }; return true end
end
PET_HAPPINESS1, PET_HAPPINESS2, PET_HAPPINESS3 = "Unhappy", "Content", "Happy"
function UnitGetIncomingHeals(u) if u == "player" and HP.incoming then return hide(HP.incoming) end end
-- the game shortens numbers, hidden ones too (its answer hidden then)
function AbbreviateNumbers(v, opts)
    local hidden = issecretvalue(v); v = reveal(v)
    local s = tostring(v)
    for _, b in ipairs(opts and opts.breakpointData or {}) do
        if v >= b.breakpoint then
            local n = math.floor(v / b.significandDivisor) / b.fractionDivisor
            s = (b.fractionDivisor > 1 and string.format("%.1f", n) or tostring(math.floor(n))) .. b.abbreviation
            break
        end
    end
    return hidden and hide(s) or s
end
function UnitName(u) if u == "target" then return hide(TGT.name) end return "Me" end
function UnitLevel(u) if u == "target" then return hide(TGT.level) end return XPS.level end
function UnitReaction() return TGT.reaction end
function UnitIsPlayer() return false end
function UnitClassification() return TGT.class end
function UnitIsTapDenied() return TGT.tapped == true end
function UnitPlayerControlled() return false end
PowerBarColor = { MANA = { r = 0, g = 0, b = 1 } }
function UnitXP() return XPS.cur end
function UnitXPMax() return XPS.max end
function GetXPExhaustion() return XPS.rested end
function IsXPUserDisabled() return false end
function GetMaxLevelForPlayerExpansion() return 60 end
local REP = {}
C_Reputation = { GetWatchedFactionData = function() return REP.data end }
FACTION_BAR_COLORS = { [5] = { r = 0, g = 0.6, b = 0.1 } }
FACTION_STANDING_LABEL5 = "Friendly"
local watched = {}
function RegisterUnitWatch(f) watched[f] = true end
function UnregisterUnitWatch(f) watched[f] = nil end
TargetFrame = newFrame("Button", "TargetFrame", UIParent, "SecureUnitButtonTemplate")
-- its auras: your Judgement (magic), a curse whose details Forever hides, a 5-stack buff
local TGT_AURAS = {
    ["HARMFUL|INCLUDE_NAME_PLATE_ONLY"] = {
        { icon = 135959, auraInstanceID = 11, applications = 0, duration = 10, expirationTime = 110, dispelName = "Magic" },
        { icon = hide(136207), auraInstanceID = hide(12), applications = hide(3), duration = hide(30),
            expirationTime = hide(130), dispelName = hide("Curse") },
    },
    HELPFUL = { { icon = 135987, auraInstanceID = 21, applications = 5, duration = 0, expirationTime = 0 } },
}
local handedBack = 0 -- hidden values add-on code handed back to the aura API
local function auraByID(id)
    for _, l in pairs(TGT_AURAS) do for _, a in ipairs(l) do if a.auraInstanceID == id then return a end end end
end
C_UnitAuras = {
    GetAuraDataByIndex = function(unit, i, filter)
        if unit ~= "target" or not TGT.exists then return nil end
        return TGT_AURAS[filter] and TGT_AURAS[filter][i]
    end,
    -- add-on code may not hand hidden values back
    GetAuraApplicationDisplayCount = function(_, id, min)
        if issecretvalue(id) then handedBack = handedBack + 1; error("secret argument") end
        local a = auraByID(id)
        return a and a.applications >= min and tostring(a.applications) or ""
    end,
    GetAuraDuration = function(_, id)
        if issecretvalue(id) then handedBack = handedBack + 1; error("secret argument") end
        return { durationOf = id }
    end,
}
DebuffTypeColor = { none = { r = 0.8, g = 0, b = 0 }, Magic = { r = 0.2, g = 0.6, b = 1 } }
TargetFrameSpellBar = newFrame("StatusBar", "TargetFrameSpellBar", TargetFrame)
-- Blizzard's breath, fatigue and feign-death bars: Edit Mode's timer bars, top centre, 100 down
MirrorTimerContainer = newFrame("Frame", "MirrorTimerContainer", UIParent)
MirrorTimerContainer:SetPoint("TOP", UIParent, "TOP", 0, -100)
MirrorTimerContainer.IsInDefaultPosition = function() return true end
MirrorTimerContainer.ApplySystemAnchor = function(self) self:SetPoint("TOP", UIParent, "TOP", 0, -100) end
local CURVE = {}
CURVE.__index = CURVE
function CURVE:SetType(t) self.type = t end
function CURVE:AddPoint(x, y) self.pts[#self.pts + 1] = { x, y } end
function CURVE:Evaluate(x) -- through every point, as the game's (Linear; Step snaps)
    local pts = self.pts
    if x <= pts[1][1] then return pts[1][2] end
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        if x <= b[1] then
            if self.type == Enum.LuaCurveType.Step then return a[2] end
            return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
        end
    end
    return pts[#pts][2]
end
Enum = { AddOnProfilerMetric = { RecentAverageTime = 1, PeakTime = 4, CountTimeOver1Ms = 5, CountTimeOver5Ms = 6 },
    SpellBookItemType = { Spell = 1 }, SpellBookSpellBank = { Player = 0 }, LuaCurveType = { Linear = 0, Step = 1 },
    StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }, StatusBarRenderMode = { Linear = 0, Radial = 1 } }
local curvesMade = 0
C_CurveUtil = { CreateCurve = function() curvesMade = curvesMade + 1; return setmetatable({ pts = {} }, CURVE) end }
LEAN_PERCENT = setmetatable({ __secret = true, v = 0 }, SECRET_MT)
function UnitHealthPercent(unit, _, curve)
    local subject = unit == "pet" and PET or HP
    local f = subject.cur / subject.max
    f = curve and curve:Evaluate(f) or f
    -- lean: one hidden value made, as the game's make no tables (a crack's curves give many values)
    if leanMode then rawset(LEAN_PERCENT, "v", f); return LEAN_PERCENT end
    return hide(f)
end
function UnitPowerPercent(unit, _, _, curve)
    local subject = unit == "pet" and PET or HP
    local f = subject.power / subject.powerMax
    return hide(curve and curve:Evaluate(f) or f)
end
local LOADED = { ActionRing = true }
C_AddOns = { IsAddOnLoaded = function(n) return LOADED[n] end, GetAddOnMetadata = function() return "0.1.0" end }

-- Bar 1's page, as the game knows it (a warrior's stance gives a bonus bar)
local PAGE = { page = 1, bonus = false, bonusIndex = 7, vehicle = false }
function GetActionBarPage() return PAGE.page end
function HasVehicleActionBar() return PAGE.vehicle end
function GetVehicleBarIndex() return 12 end
function HasOverrideActionBar() return false end
function HasTempShapeshiftActionBar() return false end
function HasBonusActionBar() return PAGE.bonus end
function GetBonusBarIndex() return PAGE.bonusIndex end
-- This client's secure click (SecureActionButtonMixin:CalculateAction, the forever branch): a button with an
-- ID gets its slot from its "actionpage" (its own, or its parent's with "useparent-actionpage"), else
-- from the bar page alone: no forms, vehicles or override bars (Blizzard's main bar sets its own
-- actionpage). Until 0.5.479 this mock paged forms too, and hid the bug: in bear form a key cast page 1.
local function calculateAction(f, suffix)
    local id = f.id or 0
    if id > 0 then
        local page = f.attrs.actionpage
        if page == nil and f.attrs["useparent-actionpage"] and f.parent then page = f.parent.attrs.actionpage end
        page = tonumber(page) or PAGE.page
        return id + (page - 1) * 12
    end
    return f.attrs["action" .. suffix] or f.attrs.action
end

-- a Paladin's spellbook
local SPELLBOOK = {
    { name = "Seal of Righteousness", spellID = 21084 }, { name = "Seal of Righteousness", spellID = 20287 },
    { name = "Seal of the Crusader", spellID = 21082 }, { name = "Seal of Light", spellID = 20165 },
    { name = "Blessing of Might", spellID = 19740 }, { name = "Devotion Aura", spellID = 465 },
    { name = "Retribution Aura", spellID = 7294 },
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #SPELLBOOK } end,
    GetSpellBookItemInfo = function(i)
        local e = SPELLBOOK[i]
        return { name = e.name, spellID = e.spellID, itemType = 1, isPassive = false }
    end,
}
local SPELL_NAMES = { [21084] = "Seal of Righteousness", [20375] = "Seal of Command", [21082] = "Seal of the Crusader",
    [20165] = "Seal of Light", [20166] = "Seal of Wisdom", [20164] = "Seal of Justice", [19740] = "Blessing of Might",
    [465] = "Devotion Aura", [7294] = "Retribution Aura" }
C_Spell = {
    GetSpellName = function(id) return SPELL_NAMES[id] end,
    GetSpellTexture = function(id) return "Interface\\Icons\\spell" .. id end,
    IsSpellUsable = function() return true, false end,
    GetSpellCooldownDuration = function(id) return { durationFor = id } end,
    IsSpellInRange = function() return nil end,
}
local MACROS = { perCharacter = 0, made = {} }
function GetMacroIndexByName(name) for i, m in ipairs(MACROS.made) do if m.name == name then return 120 + i end end return 0 end
function GetNumMacros() return 0, MACROS.perCharacter end
function CreateMacro(name, icon, body, perCharacter)
    MACROS.made[#MACROS.made + 1] = { name = name, icon = icon, body = body, perCharacter = perCharacter }
    MACROS.perCharacter = MACROS.perCharacter + 1
    return 120 + #MACROS.made
end

-------------------------------------------------------------------------------
-- the stand-in for Blizzard's secure environment
-------------------------------------------------------------------------------
local bindings = {}
local function handle(f)
    if not f then return nil end
    local h = { __frame = f }
    function h:Show() local s = insideSecure; insideSecure = true; f:Show(); insideSecure = s end
    function h:Hide() local s = insideSecure; insideSecure = true; f:Hide(); insideSecure = s end
    function h:IsShown() return f.shown end
    function h:GetName() return f.name end
    function h:GetFrameRef(label) return handle(f.refs[label]) end
    function h:GetAttribute(n) return f.attrs[n] end
    function h:SetAttribute(n, v) f.attrs[n] = v end
    function h:ClearBindings() for k, b in pairs(bindings) do if b.owner == f then bindings[k] = nil end end end
    function h:SetBindingClick(_, key, name, button)
        if type(name) == "table" then name = name:GetName() end
        assert(type(name) == "string", "Invalid click target name")
        bindings[key] = { owner = f, name = name, button = button }
    end
    return h
end
local function runSnippet(code, selfFrame, ownerFrame, vars)
    local fn = assert(loadstring(code))
    local env = { self = handle(selfFrame), owner = handle(ownerFrame), tostring = tostring, tonumber = tonumber,
        type = type, math = math, string = string, IsShiftKeyDown = IsShiftKeyDown }
    for k, v in pairs(vars or {}) do env[k] = v end
    setfenv(fn, env)
    local s = insideSecure
    insideSecure = true
    local r = { fn() }
    insideSecure = s
    return unpack(r)
end
function runShowHide(f, on)
    local code = f.attrs[on and "_onshow" or "_onhide"]
    if code then runSnippet(code, f, f) end
end
function SecureHandlerSetFrameRef(frame, label, ref) frame.refs[label] = ref end
function SecureHandlerWrapScript(frame, script, header, pre, post)
    frame.wraps[script] = { header = header, pre = pre, post = post }
end
local drivers = {}
local stateChanged
do
local function drive(f)
    for clause in (drivers[f] .. ";"):gmatch("([^;]*);") do
        local holds, any = false, false
        for c in clause:gmatch("%[(.-)%]") do
            any = true
            if c == "pet" and PET.exists then holds = true end -- vehicles, override, possess, pet battles: never here
        end
        if holds or not any then
            local s = insideSecure
            insideSecure = true
            setShown(f, clause:match("(%a+)%s*$") == "show")
            insideSecure = s
            return
        end
    end
end
stateChanged = function() for f in pairs(drivers) do drive(f) end end
function RegisterStateDriver(f, _, cond) drivers[f] = cond; drive(f) end
end
function UnregisterStateDriver(f) drivers[f] = nil end
-- attribute drivers (the game's SecureStateDriver): their macro conditions on the page's state here
do
local attrDrivers = {}
local function attrHolds(c)
    for part in (c .. ","):gmatch("([^,]*),") do
        local name, arg = part:match("^%s*(%a+):?(%d*)%s*$")
        local ok = false
        if name == "vehicleui" then ok = PAGE.vehicle
        elseif name == "bar" then ok = PAGE.page == tonumber(arg)
        elseif name == "bonusbar" then ok = PAGE.bonus and PAGE.bonusIndex == 6 + tonumber(arg) end
        if not ok then return false end -- (possessbar, overridebar, shapeshift: never here)
    end
    return true
end
local function attrDrive(f)
    local d = attrDrivers[f]
    for clause in (d.cond .. ";"):gmatch("([^;]*);") do
        local holds, any = false, false
        for c in clause:gmatch("%[(.-)%]") do
            any = true
            if attrHolds(c) then holds = true end
        end
        if holds or not any then
            local value = clause:match("([^%]]-)%s*$"):match("^%s*(.-)%s*$")
            if f.attrs[d.attr] ~= value then
                f.attrs[d.attr] = value
                fireScript(f, "OnAttributeChanged", d.attr, value)
            end
            return
        end
    end
end
function RegisterAttributeDriver(f, attr, cond) attrDrivers[f] = { attr = attr, cond = cond }; attrDrive(f) end
function UnregisterAttributeDriver(f) attrDrivers[f] = nil end
local visibility = stateChanged
stateChanged = function() visibility(); for f in pairs(attrDrivers) do attrDrive(f) end end
end
local overrideSets, overrideSeq = {}, 0
local overrides = setmetatable({}, { __index = function(_, key)
    local best
    for _, b in pairs(overrideSets[key] or {}) do
        if not best or (b.priority and not best.priority) or (b.priority == best.priority and b.seq > best.seq) then best = b end
    end
    return best
end })
function SetOverrideBindingClick(owner, priority, key, name, button)
    if combat then blocked[#blocked + 1] = "SetOverrideBindingClick " .. key; return end
    overrideSeq = overrideSeq + 1
    overrideSets[key] = overrideSets[key] or {}
    overrideSets[key][owner] = { owner = owner, name = name, button = button, priority = priority and true or false, seq = overrideSeq }
end
function ClearOverrideBindings(owner)
    if combat then blocked[#blocked + 1] = "ClearOverrideBindings"; return end
    for _, set in pairs(overrideSets) do set[owner] = nil end
end

local used, casts = {}, {}
local function click(f, button, down)
    button = button or "LeftButton"
    if not f.shown then return end
    local wrap = f.wraps.OnClick
    local message
    -- as the game's: the snippets run only for a frame with a secure handle (SecureHandlers.lua
    -- GetFrameHandle(self, true)), so never for Blizzard's own unprotected buttons
    if wrap and f.mockProtected then
        local newbutton
        newbutton, message = runSnippet(wrap.pre, f, wrap.header, { button = button, down = down or false })
        if newbutton == false then return end
        if newbutton then button = tostring(newbutton) end
    end
    local suffix = button == "RightButton" and "2" or "1"
    local kind = f.attrs["type" .. suffix] or f.attrs.type
    if down == false then kind = nil end
    if kind == "action" then
        local slot = calculateAction(f, suffix)
        if slot then used[#used + 1] = slot end
    elseif kind == "pet" then
        local act = f.attrs["action" .. suffix] or f.attrs.action
        if act then CastPetAction(act) end
    elseif kind == "click" then
        local target = f.attrs["clickbutton" .. suffix] or f.attrs.clickbutton
        if target then target:Click(button) end
    elseif kind == "spell" then
        local sp = f.attrs["spell" .. suffix] or f.attrs.spell
        if sp then casts[#casts + 1] = sp end
    end
    fireScript(f, "OnClick", button, false)
    if wrap and wrap.post and message ~= nil then
        runSnippet(wrap.post, f, wrap.header, { message = message, button = button, down = down or false })
    end
    fireScript(f, "PostClick", button, false)
end
local function press(key)
    local b = bindings[key] or overrides[key]
    if b then click(_G[b.name], b.button) end
    return b ~= nil
end

-------------------------------------------------------------------------------
-- action slots, CVars, bindings
-------------------------------------------------------------------------------
ACTIONS = {}
local function spell(name, extra)
    local a = { name = name, texture = "Interface\\Icons\\" .. name, usable = true, noMana = false, count = "",
        cd = { startTime = 0, duration = 0, isEnabled = true, modRate = 1 } }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end
local cursor
C_ActionBar = {
    ranged = {}, -- slots the add-on asked the game to report range for
    EnableActionRangeCheck = function(slot, on) C_ActionBar.ranged[slot] = on end,
    HasAction = function(s) return ACTIONS[s] ~= nil end,
    GetActionTexture = function(s) return ACTIONS[s] and ACTIONS[s].texture end,
    GetActionText = function(s) return ACTIONS[s] and ACTIONS[s].macro end,
    IsUsableAction = function(s) local a = ACTIONS[s]; if a then return a.usable, a.noMana end return false, false end,
    GetActionDisplayCount = function(s) return ACTIONS[s] and ACTIONS[s].count or "" end,
    IsActionInRange = function() return nil end,
    IsEquippedAction = function() return false end,
    IsCurrentAction = function() return false end,
    IsAutoRepeatAction = function() return false end,
    GetActionCooldownDuration = function(s) return { durationFor = s } end,
}
local fired
local function fire(event, ...) fired(event, ...) end
function GetCursorInfo()
    if PET.cursor then return "petaction", PET.cursor end
    if cursor then return "spell", cursor end
end
function PickupAction(s) cursor = ACTIONS[s]; ACTIONS[s] = nil; fire("ACTIONBAR_SLOT_CHANGED", s); fire("CURSOR_CHANGED") end
function PickupMacro(index)
    local m = MACROS.made[index - 120]
    cursor = { name = m.name, macro = m.name, texture = m.icon }
end
function PlaceAction(s) ACTIONS[s], cursor = cursor, nil; fire("ACTIONBAR_SLOT_CHANGED", s); fire("CURSOR_CHANGED") end
local CVARS = { lockActionBars = "0", chatStyle = "im" }
function GetCVar(n) return CVARS[n] end
function GetCVarBool(n) return CVARS[n] == "1" end
function SetCVar(n, v) CVARS[n] = v end
-- the chat (Action Ring's stand-ins): General (ChatFrame1) and the Combat Log (ChatFrame2) docked
-- beside it, Blizzard's buttons beside it, its scroll bar on the right
CHAT_FRAME_TEXTURES = { "Background", "TopLeftTexture", "BottomRightTexture" }
CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
local function chatFrame(name)
    local f = newFrame("ScrollingMessageFrame", name, UIParent)
    f.lines = {}
    rawset(f, "AddMessage", function(self, message) table.insert(self.lines, 1, message) end)
    rawset(f, "TransformMessages", function(self, predicate, transform)
        for i, m in ipairs(self.lines) do if predicate(m) then self.lines[i] = transform(m) end end
    end)
    for _, part in ipairs(CHAT_FRAME_TEXTURES) do newFrame("Texture", name .. part, f) end
    f.buttonFrame = newFrame("Frame", name .. "ButtonFrame", f)
    f.ResizeButton = newFrame("Button", name .. "ResizeButton", f)
    f.ScrollToBottomButton = newFrame("Button", nil, f)
    f.ScrollToBottomButton.points = { { "BOTTOMRIGHT", f.ResizeButton, "TOPRIGHT", -2, -2 } }
    f.ScrollBar = newFrame("EventFrame", nil, f)
    f.ScrollBar.points = { { "TOPLEFT", f, "TOPRIGHT", 0, 0 }, { "BOTTOMLEFT", f.ScrollToBottomButton, "TOPLEFT", 0, 2 } }
    f.editBox = newFrame("EditBox", name .. "EditBox", f)
    f.editBox.points = { { "TOPLEFT", f, "BOTTOMLEFT", -5, -2 }, { "RIGHT", f.ScrollBar, "RIGHT", 8, 0 } }
    f.editBox.shown = false
    return f
end
chatFrame("ChatFrame1")
chatFrame("ChatFrame2")
ChatFrame2.isDocked = 1
for _, name in ipairs({ "QuickJoinToastButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
    newFrame("Button", name, UIParent)
end
function IsCombatLog(f) return f == ChatFrame2 end
local chatCalls = { closed = 0, docked = {} }
function FCF_Close(f) chatCalls.closed = chatCalls.closed + 1; f.isDocked = nil; f:Hide() end
function FCF_DockFrame(f, index) chatCalls.docked[#chatCalls.docked + 1] = index; f.isDocked = 1 end
function FCF_UpdateScrollbarAnchors(f)
    f.ScrollBar:ClearAllPoints()
    f.ScrollBar:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
    f.ScrollBar:SetPoint("BOTTOMLEFT", f.ScrollToBottomButton, "TOPLEFT", 0, 2)
end
CHAT_FRAME_TAB_SELECTED_MOUSEOVER_ALPHA, CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 1.0, 0.4
newFrame("Button", "ChatFrame1Tab", UIParent)
newFrame("Button", "ChatFrame2Tab", UIParent)
local tabAlphas = {}
ChatFrameUtil = {
    SetTabAlphas = function(tab, over, none) tabAlphas[tab] = { over, none } end,
    GetTabAlphas = function(tab) local a = tabAlphas[tab] or {}; return a[1], a[2] end,
    IsTabAlerting = function() return false end,
}
function FCFTab_UpdateAlpha(f)
    local tab = _G[f:GetName() .. "Tab"]
    ChatFrameUtil.SetTabAlphas(tab, 1.0, 0.4)
    tab:SetAlpha(f.hasBeenFaded and 1.0 or 0.4)
end
FCFTab_UpdateAlpha(ChatFrame1)
-- the objectives list, open (Blizzard_ObjectiveTracker loads later): its header with its title,
-- its bar and its fold button, which Blizzard gives its atlases when it folds or opens
local tracker = { collapsed = false, sets = 0 }
tracker.Header = newFrame("Frame", nil, UIParent)
tracker.Header.Background = newFrame("Texture", nil, tracker.Header)
tracker.Header.Text = newFrame("FontString", nil, tracker.Header)
local fold = newFrame("Button", nil, tracker.Header)
tracker.Header.MinimizeButton = fold
fold.w, fold.h = 18, 19
fold.normal, fold.pushed, fold.highlight = newFrame("Texture", nil, fold), newFrame("Texture", nil, fold), newFrame("Texture", nil, fold)
rawset(fold, "GetPushedTexture", function(self) return self.pushed end)
rawset(fold, "GetHighlightTexture", function(self) return self.highlight end)
rawset(tracker.Header, "SetCollapsed", function(self, on)
    fold.normal.atlas = on and "ui-questtrackerbutton-expand-all" or "ui-questtrackerbutton-collapse-all"
end)
function tracker:IsCollapsed() return self.collapsed end
function tracker:SetCollapsed(on) self.collapsed = on; self.sets = self.sets + 1; self.Header:SetCollapsed(on) end
local questWatches = 3
C_QuestLog = { GetNumQuestWatches = function() return questWatches end,
    GetNextWaypointForMap = function(quest, map) if WHERE.track.waypoint then return WHERE.track.waypoint[1], WHERE.track.waypoint[2] end end,
    GetDistanceSqToQuest = function()
        if WHERE.track.questDistance then return WHERE.track.questDistance ^ 2, true end
    end,
    GetQuestsOnMap = function(map)
        return WHERE.track.poi and { { questID = 77, x = 0.1, y = 0.1 }, { questID = WHERE.track.quest, x = WHERE.track.poi[1], y = WHERE.track.poi[2] } } or {}
    end }
Settings = {
    GetValue = function() return false end,
    RegisterCanvasLayoutCategory = function(panel, name) return { GetID = function() return 77 end, name = name, panel = panel } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) OPENED = id end,
}
local shiftDown, pickupMod = false, false
function IsShiftKeyDown() return shiftDown end
function IsModifiedClick(k) return k == "PICKUPACTION" and pickupMod end
local KEYBINDS = { ACTIONBUTTON1 = "1", ACTIONBUTTON5 = "Q", MULTIACTIONBAR1BUTTON1 = "SHIFT-1", MULTIACTIONBAR1BUTTON2 = "E",
    BONUSACTIONBUTTON4 = "ALT-4",
    TOGGLEBACKPACK = "B",
    ["CLICK SpheresBar3Hub:LeftButton"] = "CTRL-R", ["CLICK SpheresAurasHub:RightButton"] = "F",
    ["CLICK SpheresBar2Button13:LeftButton"] = "CTRL-B" }
function GetBindingKey(cmd) return KEYBINDS[cmd] end
function GetBindingText(key) return key end
RANGE_INDICATOR = "●"
C_Timer = { After = function(_, fn) fn() end }
function debugprofilestop() return os.clock() * 1000 end

-------------------------------------------------------------------------------
-- load the add-on: TOC order, its own globals only
-------------------------------------------------------------------------------
local OWN = { "^Spheres", "^SLASH_SPHERES", "^BINDING_HEADER_SPHERES", "^BINDING_NAME_CLICK Spheres" }
local strays = {}
SlashCmdList = {}
local env = setmetatable({}, { __index = _G, __newindex = function(_, k, v)
    local own = false
    for _, p in ipairs(OWN) do if tostring(k):match(p) then own = true end end
    if not own then strays[#strays + 1] = tostring(k) end
    _G[k] = v
end })
local ns = {}
for line in io.lines(dir .. "/Spheres.toc") do
    if line:match("%.lua%s*$") then
        local chunk = assert(loadfile(dir .. "/" .. line:gsub("%s+$", "")))
        setfenv(chunk, env)
        chunk("Spheres", ns)
    end
end
function fired(event, ...)
    for _, f in ipairs(frames) do
        if f.scripts.OnEvent and (f.events[event] ~= nil or event == "ADDON_LOADED" or event == "PLAYER_LOGIN") then
            f.scripts.OnEvent(f, event, ...)
        end
    end
end
local function slash(msg) SlashCmdList.SPHERES(msg) end

-- The browser simulator can run the actual bars, rings and target modules on this same mock
-- game. This branch is deliberately before the scenario assertions below: the harness and the
-- simulator share the fixture and frame implementations, while the normal test run stays intact.
if SIM_UI_MODE then
    local S, B, R, T
    local SIM_LEVEL = 0
    local FORM_IDS = { ["Bear Form"] = "bear", ["Dire Bear Form"] = "bear", ["Cat Form"] = "cat",
        ["Travel Form"] = "travel", ["Moonkin Form"] = "moonkin" }
    local function encode(v)
        local kind = type(v)
        if kind == "string" then return string.format("%q", v) end
        if kind == "number" then return string.format("%.6g", v) end
        if kind == "boolean" then return tostring(v) end
        if kind ~= "table" then return "null" end
        local array, count = true, 0
        for k in pairs(v) do count = count + 1; if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then array = false end end
        local out = {}
        if array then
            for i = 1, count do out[i] = encode(v[i]) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        for k, value in pairs(v) do out[#out + 1] = encode(tostring(k)) .. ":" .. encode(value) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    local function n(v) v = reveal(v); return type(v) == "number" and v or 0 end
    local function str(v) v = reveal(v); return type(v) == "string" and v or "" end
    local function ratio(bar)
        local v, lo, hi = n(bar.value), n(bar.min), n(bar.max)
        return hi > lo and math.max(0, math.min(1, (v - lo) / (hi - lo))) or 0
    end
    local function buttonState(b)
        local a = b.art
        local action = b.action and ACTIONS[b.action]
        return { shown = action ~= nil, name = action and action.name or a and a.name and tostring(a.name.text or "") or "",
            texture = a and a.icon and (a.icon.texture or a.icon.atlas) or nil,
            count = a and a.count and tostring(a.count.text or "") or "",
            key = a and a.hotkey and tostring(a.hotkey.text or "") or "",
            action = b.action, x = select(1, rectOf(b)), y = select(2, rectOf(b)), w = b.w, h = b.h }
    end
    local function snapshot()
        local rows = {}
        for row = 1, 2 do
            rows[row] = {}
            for i, b in ipairs(B.Buttons(row)) do rows[row][i] = buttonState(b) end
        end
        local rings = {}
        for _, o in ipairs(R.List()) do
            if o.id == "menu" or o.id == "bags" or o.id == "forms" then
                local x, y = o.hub:GetCenter()
                local ring = { id = o.id, kind = o.def.kind, shown = o.ring.shown == true,
                    hub = { x = x or 0, y = y or 0, w = o.hub.w or 0, h = o.hub.h or 0 }, slots = {} }
                for i, b in ipairs(o.slots) do
                    local bx, by = b:GetCenter()
                    ring.slots[i] = { shown = b.shown == true, name = b.name or "", texture = b.art and b.art.icon and
                        (b.art.icon.texture or b.art.icon.atlas) or nil, x = bx or 0, y = by or 0, w = b.w or 0, h = b.h or 0,
                        action = b:GetAttribute("action"), spell = b:GetAttribute("spell"), native = b.native == true,
                        form = b.entry and FORM_IDS[b.entry.key] or nil, spellID = b.entry and b.entry.id or nil }
                end
                rings[#rings + 1] = ring
            end
        end
        local f = T.Follow()
        local c = T.Card()
        local target = f or c
        local health, power = target and target.health, target and target.power
        local castX, castY, castW, castH = rectOf(PlayerCastingBarFrame)
        return { page = B.Page(), rows = rows, rings = rings,
            cast = { x = castX or 960, y = castY or 0, w = castW or 200, h = castH or 13 },
            target = { shown = target and target.shown == true or false, name = target and str(target.name.text) or "",
                kind = target and str(target.kind.text) or "", health = health and ratio(health) or 0,
                power = power and ratio(power) or 0, powerShown = TGT.powerMax ~= nil,
                nameColor = target and target.name.color or nil, healthColor = health and health.color or nil,
                powerColor = power and power.color or nil,
                reaction = TGT.reaction, dead = TGT.dead == true, level = TGT.level,
                x = target and select(1, rectOf(target)) or 0, y = target and select(2, rectOf(target)) or 0,
                w = target and target.w or 0, h = target and target.h or 0 },
            loaded = SpheresHUD ~= nil }
    end
    local function parse(line)
        local out = {}
        for k, v in tostring(line or ""):gmatch("([%w_]+)=([^%s]+)") do out[k] = v end
        return out
    end
    local function number(v, fallback) v = tonumber(v); return v or fallback end
    local function update(line)
        local p = parse(line)
        if p.op == "init" then
            SpheresDB = { schema = 6, targetCard = true, targetStyle = "nameplate", locked = true,
                statueFinish = (p.statues == "modern" or p.statues == "charcoal" or p.statues == "none") and p.statues or nil,
                rings = { bar3 = { shown = true } } }
            PlayerCastingBarFrame.w, PlayerCastingBarFrame.h = 200, 13
            LOADED.ActionRing = nil
            UnitClass = function() return "Druid", "DRUID" end
            UnitPower = function(u)
                if u == "target" then return TGT.powerMax and hide(TGT.power) or nil end
                if u == "pet" then return hide(PET.power) end
                return hide(HP.power)
            end
            UnitPowerMax = function(u)
                if u == "target" then return TGT.powerMax end
                if u == "pet" then return hide(PET.powerMax) end
                return hide(HP.powerMax)
            end
            UnitPowerType = function(u)
                if u == "target" then return TGT.powerMax and TGT.ptype or nil, TGT.powerMax and TGT.token or nil end
                if u == "pet" then return PET.ptype, PET.token end
                return HP.ptype, HP.token
            end
            HP.cur, HP.max = number(p.hp, 75), 100
            HP.power, HP.powerMax = number(p.power, 60), 100
            HP.ptype, HP.token = 0, "MANA"
            TGT.exists = false
            SIM_LEVEL = number(p.level, 20)
            local formSpells = { { 10, "Bear Form", 5487 }, { 20, "Cat Form", 768 },
                { 30, "Travel Form", 783 }, { 40, "Moonkin Form", 24858 } }
            SPELLBOOK = {}
            for _, item in ipairs(formSpells) do
                if SIM_LEVEL >= item[1] then SPELLBOOK[#SPELLBOOK + 1] = { name = item[2], spellID = item[3] } end
            end
            ACTIONS = {}
            local chunks = {}
            for i = 1, 6 do chunks[i] = p["s" .. i] or "" end
            for i = 1, 6 do if chunks[i] ~= "" then ACTIONS[i] = spell(chunks[i]) end end
            fire("ADDON_LOADED", "Spheres")
            fire("PLAYER_LOGIN")
            S, B, R, T = ns.Sphere, ns.Bars, ns.Ring, ns.Target
            return snapshot()
        end
        if not B then return { error = "simulator UI is not initialized" } end
        if p.op == "ring" then
            local o = R.Get(p.id)
            if not o then return { error = "unknown ring " .. tostring(p.id) } end
            if p.open == "1" then o.ring:Show() else o.ring:Hide() end
            R.UpdateAll()
            return snapshot()
        end
        if (p.statues == "modern" or p.statues == "charcoal" or p.statues == "none") and ns.db.statueFinish ~= p.statues then
            ns.db.statueFinish = p.statues
            ns.Apply()
        end
        local formPages = { caster = 1, bear = 7, cat = 8, travel = 9, moonkin = 10 }
        local form = p.form or "caster"
        local level = number(p.level, SIM_LEVEL)
        local levelChanged = level ~= SIM_LEVEL
        if levelChanged then
            SIM_LEVEL = level
            local formSpells = { { 10, "Bear Form", 5487 }, { 20, "Cat Form", 768 },
                { 30, "Travel Form", 783 }, { 40, "Moonkin Form", 24858 } }
            SPELLBOOK = {}
            for _, item in ipairs(formSpells) do
                if SIM_LEVEL >= item[1] then SPELLBOOK[#SPELLBOOK + 1] = { name = item[2], spellID = item[3] } end
            end
            ns.Spells.Scan()
        end
        local page = formPages[form] or 1
        local strip = B.Buttons(1)[1] and B.Buttons(1)[1].parent
        if strip then strip:SetAttribute("actionpage", page) end
        HP.cur, HP.max = number(p.hp, HP.cur), 100
        HP.power, HP.powerMax = number(p.power, HP.power), 100
        HP.token = p.powerType == "rage" and "RAGE" or p.powerType == "energy" and "ENERGY" or "MANA"
        HP.ptype = p.powerType == "rage" and 1 or p.powerType == "energy" and 3 or 0
        TGT.power = math.floor(number(p.tpp, 0.5) * 600)
        TGT.ptype, TGT.token = p.targetPower == "rage" and 1 or 0, p.targetPower == "rage" and "RAGE" or "MANA"
        TGT.exists = p.target ~= nil and p.target ~= "none"
        TGT.name = p.targetName and p.targetName:gsub("_", " ") or "Gnarlpine Warrior"
        TGT.hp, TGT.max = math.floor(number(p.thp, 0.7) * 800), 800
        if p.targetPower == "none" then TGT.powerMax = nil else TGT.powerMax = 600 end
        TGT.reaction = p.target == "friendly" and 5 or p.target == "neutral" and 4 or 2
        TGT.tapped = p.target == "tapped"
        TGT.class = TGT.reaction <= 3 and "elite" or "normal"
        TGT.dead = TGT.exists and TGT.hp <= 0
        ACTIONS = {}
        for i = 1, 6 do
            local id = p["s" .. i] or ""
            local slot = i + (page - 1) * 12
            if id ~= "" then ACTIONS[slot] = spell(id) end
        end
        fire("ACTIONBAR_PAGE_CHANGED")
        fire("PLAYER_TARGET_CHANGED")
        fire("UNIT_NAME_UPDATE", "target")
        fire("UNIT_LEVEL", "target")
        fire("UNIT_HEALTH", "target")
        fire("UNIT_POWER_UPDATE", "target")
        B.Update()
        if levelChanged then R.Layout() end
        R.UpdateAll()
        T.Update()
        T.Layout()
        return snapshot()
    end
    SimAsk = function(line)
        local ok, result = xpcall(function() return update(line) end, function(err)
            return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
        end)
        if not ok then return encode({ error = tostring(result) }) end
        return encode(result)
    end
    return
end

-------------------------------------------------------------------------------
-- 1) with Action Ring enabled, Spheres stays off; without it, it builds at login
-------------------------------------------------------------------------------
local from = #printed
SpheresDB = { schema = 1, backdrop = 60, buttonSize = 40, scale = 1, rings = { bar3 = { shown = true, dock = { "left", 338 } } } }
fire("ADDON_LOADED", "Spheres")
check("saved by 0.3 (rings round the old halos): their places start over, the band and button size gone",
    ns.db.rings.bar3.dock == nil and ns.db.backdrop == nil and ns.db.buttonSize == nil and ns.db.schema == ns.SCHEMA
    and ns.db.rings.bar3.shown == true)
do
    local hiddenStatues = { schema = 4, statues = false, statueFinish = "charcoal" }
    ns.migrate(hiddenStatues)
    check("saved statue checkbox off becomes None", hiddenStatues.statueFinish == "none" and hiddenStatues.statues == nil)
    local charcoalStatues = { schema = 4, statues = true, statueFinish = "charcoal" }
    ns.migrate(charcoalStatues)
    check("saved charcoal finish remains charcoal", charcoalStatues.statueFinish == "charcoal" and charcoalStatues.statues == nil)
    local retiredBrass = { schema = 10, statueFinish = "brass" }
    ns.migrate(retiredBrass)
    check("schema 11 migrates the retired Brass finish to Charcoal", retiredBrass.statueFinish == "charcoal")
    local onCard, onSphere = { schema = 5, targetStyle = "card" }, { schema = 5, targetStyle = "sphere" }
    ns.migrate(onCard)
    ns.migrate(onSphere)
    check("schema 6: the target card becomes its nameplate's (the default now); a sphere stays",
        onCard.targetStyle == "nameplate" and onSphere.targetStyle == "sphere" and ns.DEFAULTS.targetStyle == "nameplate")
end
fire("PLAYER_LOGIN")
check("Action Ring on: Spheres stays off and says so", SpheresHUD == nil and saidSince(from, "Action Ring is enabled"))
check("and leaves Blizzard's bars alone", MainActionBar.parent == UIParent and Minimap.parent == MinimapCluster)
LOADED.ActionRing = nil
ACTIONS[1] = spell("Crusader_Strike")
ACTIONS[49] = spell("Seal_of_Righteousness")
ACTIONS[50] = spell("Judgement")
fire("PLAYER_LOGIN")
local S, B, R = ns.Sphere, ns.Bars, ns.Ring
check("built: the bottom of the screen, two spheres", SpheresHUD and SpheresLeft and SpheresRight)
do
    -- Match Blizzard's GetCombinedSelectionOffset when a native frame is dragged to UIParent.
    -- Its Selection child is the capability check before calling GetSelectionOffset on the target.
    local function chatSnapOffset(frame)
        local offset = -34
        if frame.Selection then offset = offset + frame:GetSelectionOffset("LEFT", false) end
        return offset
    end
    local ok, offset = pcall(chatSnapOffset, UIParent)
    check("Edit Mode: native chat can snap to the screen edge", ok and offset == -34)
    check("Edit Mode: Spheres does not install a Selection child on UIParent", UIParent.Selection == nil)
    check("Edit Mode: the selection belongs to a private unscaled overlay",
        S.edit.selection:GetParent() == S.edit.owner and S.edit.owner.Selection == S.edit.selection
        and S.edit.owner:GetParent() == UIParent and S.edit.owner:GetScale() == 1)
    S.SetEditMode(true)
    check("Edit Mode: the private selection still highlights", S.edit.selection:IsShown())
    S.SetEditMode(false)
    check("Edit Mode: exiting hides the private selection", not S.edit.selection:IsShown())
end
local addonMapButton = newFrame("Button", "LateAddonMinimapButton", Minimap)
addonMapButton:SetPoint("CENTER", Minimap, "CENTER", 60, -60)
local rightOrb = S.Get("right")
rightOrb.pins.scripts.OnUpdate(rightOrb.pins, 1.1)
check("late minimap button renders above the sphere overlays", addonMapButton.parent == rightOrb.pins
    and addonMapButton.level > rightOrb.pins.level)
check("no black disc behind the map: MapDissolve covers the ring round it (MapBack outlined the glass)",
    rightOrb.mapBack == nil and rightOrb.mapDissolve ~= nil)
local tendrils = rightOrb.clouds.layers[6]
local secondTendrils = rightOrb.clouds.layers[7]
check("five smoke rings, MapCloud1-5, each its own texture, all showing", #rightOrb.clouds.layers == 7
    and (function()
        for i = 1, 5 do
            local ring = rightOrb.clouds.layers[i]
            if ring.texture ~= "Interface\\AddOns\\Spheres\\Media\\MapCloud" .. i or ring.alpha < 0.88 then return false end
        end
        return true
    end)())
check("two copies of the same inward wisps", secondTendrils and tendrils.texture == secondTendrils.texture
    and tendrils.texture == "Interface\\AddOns\\Spheres\\Media\\MapTendrils")
check("inward wisps start invisible", tendrils.alpha == 0 and secondTendrils.alpha == 0)
rightOrb.clouds.scripts.OnUpdate(rightOrb.clouds, 0.1)
check("staggered wisps keep one stream visible", tendrils.alpha == 0 and secondTendrils.alpha > 0.5)
rightOrb.clouds.scripts.OnUpdate(rightOrb.clouds, 1.7)
local outerWidth, outerAngle, visibleAlpha = tendrils.w, tendrils.rotation, tendrils.alpha
rightOrb.clouds.scripts.OnUpdate(rightOrb.clouds, 1.8)
check("wisps move inward while rotating", tendrils.w < outerWidth and tendrils.rotation > outerAngle)
rightOrb.clouds.scripts.OnUpdate(rightOrb.clouds, 1.6)
check("wisps stay close to the rim and fade as the other stream continues",
    tendrils.w > rightOrb.glass.kids[1].w * 0.91 and visibleAlpha > 0.6
    and tendrils.alpha < visibleAlpha * 0.3
    and secondTendrils.alpha > 0.4)
S.GiveBackMinimap()
check("minimap button returns to its addon parent when Spheres releases the map",
    addonMapButton.parent == Minimap)
S.PlaceMinimap()
check("minimap button comes forward when Spheres retakes the map", addonMapButton.parent == rightOrb.pins)
if arg[2] == "map-buttons" then
    io.stdout:write("passed " .. pass .. ", failed " .. fail .. "\n")
    os.exit(fail == 0 and 0 or 1)
end

-------------------------------------------------------------------------------
-- 2) the left sphere: Roth UI's orb, health 2/3, mana 1/3, the hidden numbers straight in
-------------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\Spheres\\Media\\"
local BALL = 206 * 226 / 256
local L = S.Get("left")
do
    local center = S.FrameAnchor():GetCenter()
    local bottom = S.FrameAnchor():GetBottom()
    local wellX = (1652.47 / 2048 - 0.5) * 788 - 8 * 788 / 2048
    local wellY = (1 - 438.96 / 500) * 202 - 1 -- Frame1Modern's painted center and frame offset
    local levelX, levelY = L.levelBadge:GetCenter()
    local menuX, menuY = SpheresMenuHub:GetCenter()
    check("Modern level badge is centered in the painted Frame1 slot",
        near(levelX, center - wellX) and near(levelY, bottom + wellY))
    check("Modern Game Menu button is centered in the painted Frame1 slot",
        near(menuX, center + wellX) and near(menuY, bottom + wellY))
end
local SURF = { w = 56 * 3, wavelength = 56, pad = 3, fade = 8, glow = 12 } -- the main chunk is near Lua's 200 locals
check("level well has a 26-unit Modern gray ring", L.levelBadge.shown
    and L.levelRing.texture == MEDIA .. "MenuLatencyRing" and L.levelRing.w == 26 and L.levelRing.h == 26
    and L.levelRing.blend == "BLEND" and L.levelRing.vertex[3] > L.levelRing.vertex[1]
    and L.levelRing.points[1][1] == "CENTER")
IsResting = function() return true end
S.UpdateCombat(false)
check("resting halo reaches the brass level ring", L.restHalo.shown and L.restHalo.w == 30
    and L.restHalo.h == 30 and L.restHalo.points[1][2] == L.levelBadge and L.levelRing.w == 26)
IsResting = nil
S.UpdateCombat(true)
check("the brass ring remains around the combat icon", L.levelBadge.shown and L.levelRing.shown
    and not L.levelText.shown and L.combatBadge.shown)
-- one beat of the swords' red outline, sampled every 10 ms: deep, up quickly and down slowly
SURF.beat = { lo = 1, hi = 0, t = 0 }
for _ = 1, math.floor(S.COMBAT_GLOW.period / 0.01 + 0.5) do
    L.combatBadge.scripts.OnUpdate(L.combatBadge, 0.01)
    SURF.beat.t = SURF.beat.t + 0.01
    local a = L.combatBadge.kids[1].alpha
    if a < SURF.beat.lo then SURF.beat.lo, SURF.beat.loAt = a, SURF.beat.t end
    if a > SURF.beat.hi then SURF.beat.hi, SURF.beat.hiAt = a, SURF.beat.t end
end
SURF.beat.rise = (SURF.beat.hiAt - SURF.beat.loAt) % S.COMBAT_GLOW.period
check("the combat outline beats every 1.6 s up to 0.6, rising in a fifth of it, and nothing else glows",
    S.COMBAT_GLOW.period == 1.6 and L.combatBadge.kids[1].blend == "ADD"
    and SURF.beat.lo < 0.17 and SURF.beat.hi > 0.59 and SURF.beat.hi <= 0.6
    and SURF.beat.rise <= 0.25 * S.COMBAT_GLOW.period and L.combatHalo == nil)
S.UpdateCombat(false)
check("the level returns inside its brass ring", L.levelBadge.shown and L.levelText.shown
    and not L.combatBadge.shown)
local hb, pb = L.health, L.power
local PIECES = { health = { -1.0000, 0.1897, 1.0000 }, mana = { 0.1608, 1.0000, 0.9680 } }
local function boxOf(name)
    local p = PIECES[name]
    return (p[2] - p[1]) * BALL / 2, p[3] * BALL, (p[1] + p[2]) / 2 * BALL / 2
end
local hw, hh, hx0 = boxOf("health")
local mw, mh, mx0 = boxOf("mana")
check("Roth's orb back (dark glass), 206 across", L.w == 206 and L.back.texture == MEDIA .. "OrbBack")
check("unused socket does not add a shadow behind the spheres", L.socket == nil and S.Get("right").socket == nil)
check("two pieces: health 60% on the left, mana 40% on the right",
    hb.points[1][4] < 0 and pb.points[1][4] > 0 and hw > mw)
check("health and mana: status bars over their piece's box, filling upwards", near(hb.w, hw) and near(hb.h, hh)
    and near(hb.points[1][4], hx0) and near(pb.w, mw) and near(pb.h, mh) and near(pb.points[1][4], mx0)
    and hb.orientation == "VERTICAL" and hb.points[1][1] == "CENTER" and hb.points[1][2] == SpheresLeft and hb.reverse == nil)
check("their fill empty, unmasked (masked fills never drew): it only sets the level",
    hb.barTexture.texture == MEDIA .. "FillNone" and pb.barTexture.texture == MEDIA .. "FillNone"
    and #hb.barTexture.masks == 0 and #pb.barTexture.masks == 0)
check("their plain colour drawn in the clip instead, cut to the piece, where the pet's hole can cut it",
    hb.base.texture == MEDIA .. "FillHealth" and pb.base.texture == MEDIA .. "FillMana" and hb.base.sublevel == -8
    and hb.base.parent == hb.inside and hb.base.masks[1] == hb.inside.hole and hb.base.vertex[1] == 0.45)
local glassTex = {}
for _, t in ipairs(L.glass.kids or {}) do -- a pet: its cavity's (a crack's mask: none till it cracks)
    if t.texture then glassTex[(t.texture:gsub("Cavity$", ""))] = t end
end
local gh, gm = glassTex[MEDIA .. "GlassHealth"], glassTex[MEDIA .. "GlassMana"]
check("each piece its own glass, over its box, over the liquid", gh and gm and near(gh.w, hw) and near(gh.h, hh)
    and near(gh.points[1][4], hx0) and near(gm.w, mw) and near(gm.points[1][4], mx0)
    and L.glass.level > hb.level and L.glass.level > pb.level)
check("deep red health, deep blue mana", hb.color[1] == 0.45 and hb.color[3] < 0.2 and pb.color[3] == 0.58 and pb.color[1] < 0.5)
check("health: the hidden numbers, as they are", issecretvalue(hb.value) and issecretvalue(hb.max)
    and reveal(hb.value) == 750 and reveal(hb.max) == 1000 and hb.min == 0)
check("mana too", issecretvalue(pb.value) and reveal(pb.value) == 300 and reveal(pb.max) == 600)
HP.cur = 200
fire("UNIT_HEALTH", "player")
check("health falls with the game's event", reveal(hb.value) == 200)
-- The wavy top: a mask pinned to the fill's top over the whole liquid, its light riding with it
check("no glow over the level any more (Roth's OrbSpark: \"a ghosty layer\")", hb.spark == nil and pb.spark == nil)
function SURF.pinned(t, bar, depth) -- reaching the slosh's room further each way (0.5.442), clamped
    local a, b, room = t.points[1], t.points[2], ns.Motion.ROOM
    return #t.points == 2 and a[1] == "TOPLEFT" and a[2] == bar.barTexture and a[3] == "TOPLEFT" and a[4] == 0
        and a[5] == SURF.pad + room and b[1] == "TOPRIGHT" and b[2] == bar.barTexture and b[3] == "TOPRIGHT"
        and b[5] == SURF.pad + room and t.h == SURF.pad + depth + 2 * room and t.masks[1] == bar.surface.mask
        and t.wrap == "REPEAT" and t.wrapV == "CLAMP" -- 0.5.452: the waves repeat across (wider spheres)
end
check("the wavy top: its liquid, pinned to the fill's top across the piece, fading into the layers",
    hb.crest.texture == MEDIA .. "SurfaceCrest" and SURF.pinned(hb.crest, hb, SURF.fade)
    and SURF.pinned(pb.crest, pb, SURF.fade) and hb.crest.blend == nil and hb.crest.layer == "ARTWORK"
    and hb.crest.parent == hb.surface and hb.crest.vertex[1] == 0.45 and SURF.w - SURF.wavelength >= hw)
check("the light under it, pinned the same way, longer", SURF.pinned(hb.line, hb, SURF.glow)
    and SURF.pinned(pb.line, pb, SURF.glow))
check("the liquid stays on the vessel (spending lowers it from the top), its layers tiling",
    hb.inside.points[1][2] == hb and #hb.inside.points == 1 and hb.inside.parent == hb.clip
    and hb.motion[1].texture.points[1][2] == hb.inside and hb.motion[1].texture.wrap == "REPEAT"
    and pb.motion[#pb.motion].texture.wrap == "REPEAT")
check("the fills ease to a new level, hidden values and all", hb.interpolation == 1 and pb.interpolation == 1
    and L.heal.interpolation == 1 and issecretvalue(hb.value))
check("the light along it: over the shade, clipped to its piece, tinted lighter", hb.line.texture == MEDIA .. "SurfaceLine"
    and hb.line.blend == "ADD" and hb.line.layer == "OVERLAY" and hb.line.parent == hb.surface
    and hb.line.masks[1] == hb.surface.mask and hb.surface.mask.texture == MEDIA .. "MaskHealth"
    and pb.surface.mask.texture == MEDIA .. "MaskMana" and hb.surface.mask.parent == hb.surface
    and hb.surface.points[1][2] == hb and near(hb.surface.w, hw) and near(hb.surface.h, hh)
    and near(hb.line.vertex[1], math.min(1, 0.45 * 1.6 + 0.12)) and hb.line.alpha < 1)
check("the heal band keeps the bar's own mask", L.healBand.masks[1] == hb.mask and hb.mask.parent == hb
    and hb.mask.texture == MEDIA .. "MaskHealth")

-- The moving layers: plain textures in a frame clipped to the liquid's level, masked to the piece.
local hc, pc = hb.clip, pb.clip
check("moving layers: clipped from the bar's bottom to its fill's top", hc and pc and hc.clips == true
    and pc.clips == true and hc.points[1][1] == "BOTTOMLEFT" and hc.points[1][2] == hb
    and hc.points[2][1] == "TOPRIGHT" and hc.points[2][2] == hb.barTexture and hc.points[2][3] == "TOPRIGHT"
    and hc.points[2][5] == 0
    and pc.points[2][2] == pb.barTexture and hc.level > hb.level and hc.level < L.glass.level)
local function layersMasked(bar, file)
    for _, layer in ipairs(bar.motion) do
        local t = layer.texture
        if not (t.masks[1] and t.masks[1].texture == MEDIA .. "Mask" .. file and #t.masks == 2
            and t.masks[2] == bar.inside.hole
            and t.texture:find("Liquid", 1, true)
            and t.layer == "ARTWORK" and (t.blend == "ADD" or t.blend == "BLEND")) then return false end
    end
    return #bar.motion > 0
end
check("each a plain texture masked to its piece, under its shade and surface line",
    layersMasked(hb, "Health") and layersMasked(pb, "Mana") and hb.surface.level > hc.level
    and hb.surface.level < L.glass.level and hb.surface.shade.texture == MEDIA .. "LiquidShadeHealth"
    and pb.surface.shade.texture == MEDIA .. "LiquidShadeMana")
check("the layers start at the bottom sublevel the game allows", hb.motion[1].texture.sublevel == -7
    and pb.glints[1].masks[1] == pb.inside.hole)
-- Anything pinned to the hidden level is anchored once: the client moves a region re-anchored to it
-- only when the level changes (0.5.264's waves stood still while regenerating, then jumped)
function SURF.pins()
    local out = {}
    for _, f in ipairs(frames) do
        for _, pt in ipairs(f.points or {}) do
            if pt[2] == hb.barTexture or pt[2] == pb.barTexture then
                out[#out + 1] = tostring(f) .. table.concat({ tostring(pt[1]), tostring(pt[3]), tostring(pt[4]), tostring(pt[5]) }, ",")
            end
        end
    end
    table.sort(out)
    return table.concat(out, ";"), #out
end
SURF.before, SURF.count = SURF.pins()
local function magicCount(bar)
    local n = 0
    for _, layer in ipairs(bar.motion) do if layer.spec.magic and not layer.spec.twin then n = n + 1 end end
    return n
end
check("the mana's purple haze, currents and glints in the mana only", magicCount(hb) == 0
    and magicCount(pb) == 5 and #hb.glints == 0 and #pb.glints == 5)
check("its glints violet, added to the blue (\"purple tinted instead of being white\")",
    pb.glints[1].blend == "ADD" and pb.glints[1].vertex[1] == 0.72 and pb.glints[1].vertex[2] == 0.30
    and pb.glints[1].vertex[3] == 1)
check("the health moves slower than the mana", hb.motion[1].speed < 1 and pb.motion[1].speed == 1)
check("health filling the whole sphere moves faster than the split piece's (\"too slow\" in bear form)",
    hb.motion[1].speed == 0.55 and hb.offset.speed == 0.55
    and L.wholeHealth.motion[1].speed == 0.8 and L.wholeHealth.offset.speed == 0.8
    and L.wholeHealth.health)
local layered = true
for _, layer in ipairs(pb.motion) do
    local t = layer.texture
    layered = layered and t.sublevel >= -8 and t.sublevel <= 7
end
check("layers drawn in the table's order, within the game's sublevels", layered
    and pb.motion[1].texture.sublevel < pb.motion[#pb.motion].texture.sublevel)
local moved, crossFade, glinted, glintInside = false, true, false, true
local wv = { covers = true, inStep = true, slides = {} }
SpheresLeft.scripts.OnUpdate(SpheresLeft, 0.02)
local before = hb.motion[1].texture.texcoord
local function glintIn(g)
    local p = PIECES.mana
    local x = (g.points[1][4] / (BALL / 2)) + (p[1] + p[2]) / 2
    local y = g.points[1][5] / (BALL / 2)
    return x > p[1] + 0.1 and x * x + y * y < 0.81
end
for _ = 1, 700 do
    SpheresLeft.scripts.OnUpdate(SpheresLeft, 0.31)
    for _, bar in ipairs({ hb, pb }) do
        local sums = {}
        for _, layer in ipairs(bar.motion) do
            wv.centred = (wv.centred ~= false) and layer.u >= 0 and layer.u < 1 and layer.v >= 0 and layer.v < 1
            if layer.spec.flow then sums[layer.spec] = (sums[layer.spec] or 0) + layer.texture.alpha end
        end
        for spec, sum in pairs(sums) do crossFade = crossFade and near(sum, spec.alpha) end
    end
    for _, g in ipairs(pb.glints) do
        if g.alpha > 0 then glinted = true; glintInside = glintInside and glintIn(g) end
    end
    for _, bar in ipairs({ hb, pb }) do
        local c, l = bar.crest.texcoord, bar.line.texcoord -- UL, LL, UR, LR: at rest, level across
        wv.covers = wv.covers and #c == 8 and c[1] >= 0 and c[5] <= 1 and c[1] == c[3] and c[5] == c[7]
            and near(c[5] - c[1], bar.w / SURF.w) and c[1] < SURF.wavelength / SURF.w and near(c[2], c[6])
            and near(c[4], c[8]) and c[2] < 0 and c[4] > 1
        wv.inStep = wv.inStep and l[1] == c[1] and l[5] == c[5]
        wv.slides[bar] = wv.slides[bar] or {}
        wv.slides[bar][math.floor(c[1] * SURF.w)] = true
    end
end
function wv.spread(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
check("the waves slide along and wrap inside their texture", wv.covers and wv.spread(wv.slides[hb]) > 20
    and wv.spread(wv.slides[pb]) > 20)
check("the light rides the waves", wv.inStep)
check("nothing pinned to the hidden level is re-anchored as it moves", SURF.count >= 6
    and SURF.pins() == SURF.before)
moved = hb.motion[1].texture.texcoord[1] ~= before[1] or hb.motion[1].texture.texcoord[2] ~= before[2]
check("the layers move", moved and #hb.motion[1].texture.texcoord == 8)
check("each window's own centre wraps round its tiling texture", wv.centred)
check("a current's two copies cross-fade: always its whole strength together", crossFade)
check("mana glints twinkle, inside the piece", glinted and glintInside)
check("tinted from the liquid's colour, the purple its own", hb.motion[2].texture.vertex[1] < 0.1
    and near(hb.motion[4].texture.vertex[1], math.min(1, 0.45 * 1.3 + 0.14)))
HP.ptype, HP.token = 1, "RAGE"
fire("UNIT_DISPLAYPOWER", "player")
SpheresLeft.scripts.OnUpdate(SpheresLeft, 0.31)
local quiet = true
for _, layer in ipairs(pb.motion) do if layer.spec.magic and layer.texture.alpha > 0 then quiet = false end end
for _, g in ipairs(pb.glints) do if g.alpha > 0 then quiet = false end end
check("rage: no purple, no glints", quiet)
HP.ptype, HP.token = 0, "MANA"
fire("UNIT_DISPLAYPOWER", "player")
S.ShowHeal(50)
S.ShowDamage(40)
wv.noticed = L.healNotice.shown and L.damageNotice.shown
UnitIsDeadOrGhost = function() return true end
fire("UNIT_HEALTH", "player")
check("dead: the layers, shade and surface line go with the liquid, and both notices",
    wv.noticed and not L.healNotice.shown and not L.damageNotice.shown and hb.alpha == 0 and hc.alpha == 0
    and hb.surface.alpha == 0 and pc.alpha == 0 and pb.surface.alpha == 0)
UnitIsDeadOrGhost = nil
fire("UNIT_HEALTH", "player")
check("alive again: back", hc.alpha == 1 and hb.surface.alpha == 1 and pc.alpha == 1)
-- Only what comes in lifts the liquid; spending lowers it from the top (Sphere.lua SURGE)
function wv.run(seconds)
    for _ = 1, math.floor(seconds / 0.05 + 0.5) do SpheresLeft.scripts.OnUpdate(SpheresLeft, 0.05) end
end
function wv.moved(layer, u0, v0) -- how far its window went, and which way on the screen
    local du, dv = (layer.u - u0 + 0.5) % 1 - 0.5, (layer.v - v0 + 0.5) % 1 - 0.5
    local tc = layer.texture.texcoord -- upper left minus lower left: the window's up
    return math.sqrt(du * du + dv * dv), du * (tc[1] - tc[3]) + dv * (tc[2] - tc[4])
end
wv.run(12)
check("settled: nothing owed", hb.surge == 0 and pb.surge == 0)
wv.layer = pb.motion[2]
wv.u0, wv.v0 = wv.layer.u, wv.layer.v
fire("UNIT_POWER_UPDATE", "player")
fire("UNIT_POWER_FREQUENT", "player")
wv.run(0.1)
wv.pending = pb.surge == 0
wv.run(0.3)
check("a regeneration tick lifts the mana once it's clear nothing was cast", wv.pending
    and pb.surge > 1 and pb.surge < 5 and hb.surge == 0)
wv.run(6)
wv.dist, wv.way = wv.moved(wv.layer, wv.u0, wv.v0)
check("lifted up the screen by a tick's worth", wv.way < 0
    and near(wv.dist, 5 * wv.layer.spec.size / wv.layer.height, 0.002))
wv.u0, wv.v0 = wv.layer.u, wv.layer.v
for _ = 1, 8 do fire("UNIT_POWER_FREQUENT", "player"); wv.run(0.25) end
wv.run(6)
wv.dist = wv.moved(wv.layer, wv.u0, wv.v0)
check("reported 8 times in 2 s, it lifts about two ticks' worth, not eight", wv.dist > 8 * wv.layer.spec.size / wv.layer.height
    and wv.dist < 10.5 * wv.layer.spec.size / wv.layer.height)
wv.u0, wv.v0 = wv.layer.u, wv.layer.v
fire("UNIT_SPELLCAST_SUCCEEDED", "player")
fire("UNIT_POWER_UPDATE", "player")
wv.run(0.5)
wv.castFirst = pb.surge == 0
fire("UNIT_POWER_UPDATE", "player")
wv.run(0.1)
fire("UNIT_SPELLCAST_SUCCEEDED", "player")
wv.run(0.5)
check("spending mana leaves the liquid where it is, whichever event comes first", wv.castFirst
    and pb.surge == 0 and wv.layer.u == wv.u0 and wv.layer.v == wv.v0)
fire("UNIT_COMBAT", "player", "WOUND", "", 120)
fire("UNIT_HEALTH", "player")
wv.run(1)
wv.wounded = hb.surge == 0
fire("UNIT_HEALTH", "player")
wv.run(0.05)
check("a wound leaves the health where it is, a heal or regeneration lifts it", wv.wounded and hb.surge > 0)
-- your health out of combat: regeneration starts lifting with the level, not after it, and
-- climbs steadily rather than sliding every layer up at once (0.5.333)
wv.run(6)
wv.layer = hb.motion[2]
wv.tick = 5 * wv.layer.spec.size / wv.layer.height
wv.u0, wv.v0 = wv.layer.u, wv.layer.v
fire("UNIT_HEALTH", "player")
wv.steady, wv.last = true, 0
for _ = 1, 20 do
    wv.run(0.05)
    wv.dist = wv.moved(wv.layer, wv.u0, wv.v0)
    if wv.dist - wv.last > 0.05 * wv.tick / 2 * 1.001 then wv.steady = false end -- a tick per 2 s
    if _ == 1 then wv.first = wv.dist end
    wv.last = wv.dist
end
check("out of combat a health tick lifts from the next frame, no faster than a tick per 2 s",
    wv.first > 0 and wv.steady)
wv.run(6)
wv.dist, wv.way = wv.moved(wv.layer, wv.u0, wv.v0)
check("and in the end by a tick's worth, up the screen", wv.way < 0
    and wv.dist > 0.99 * wv.tick and wv.dist < 1.01 * wv.tick)
wv.run(3)
wv.u0, wv.v0 = wv.layer.u, wv.layer.v
fire("UNIT_HEALTH", "player")
wv.run(0.05)
fire("UNIT_COMBAT", "player", "WOUND", "", 30)
wv.run(1)
check("a wound reported just after the change stops its lift", hb.surge == 0
    and wv.moved(wv.layer, wv.u0, wv.v0) < 0.7 * wv.tick)
wv.run(3)
combat = true
wv.u0, wv.v0 = wv.layer.u, wv.layer.v
fire("UNIT_HEALTH", "player")
wv.run(0.1)
wv.waited = wv.layer.u == wv.u0 and wv.layer.v == wv.v0
wv.run(3)
wv.u0, wv.v0 = wv.layer.u, wv.layer.v
fire("UNIT_COMBAT", "player", "HEAL", "", 200)
fire("UNIT_HEALTH", "player")
wv.run(0.05)
check("in combat a change waits to rule out a wound, unless a heal came with it", wv.waited
    and wv.moved(wv.layer, wv.u0, wv.v0) > 0)
combat = false
wv.run(3)
-- what you receive and take, on the health arc: "+heal" yellow, "-damage" brighter orange inward only together
function wv.said(n) -- a notice's text: its glyphs, or the hidden amount's FontString
    if n.protected.shown then return (n.sign.text or "") .. reveal(n.protected.text) end
    local t = ""
    for _, g in ipairs(n.glyphs) do t = t .. (g.text or "") end
    return t
end
function wv.inset(fs) return math.sqrt(fs.points[1][4] ^ 2 + fs.points[1][5] ^ 2) end
function wv.arcPart(n, glyph)
    local shift = n.arcCurve - n.arcRadius
    local cx, cy = -shift * math.cos(n.arcAngle), -shift * math.sin(n.arcAngle)
    local p = glyph.points[1]
    local x, y = p[4] - cx, p[5] - cy
    return near(math.sqrt(x * x + y * y), n.arcCurve, 0.01)
        and near(glyph.rotation, math.atan2(y, x) - math.pi / 2, 0.01)
end
function wv.onArc(n)
    for _, glyph in ipairs(n.glyphs) do
        if glyph.text ~= "" and not wv.arcPart(n, glyph) then return false end
    end
    return true
end
-- With an embedded sphere, notice line `share`: its circle that share of the way from the health
-- arc's to the one 16 outside the sphere's rim, and where it starts, walked from the health arc's
-- 10 o'clock across the circles in fine steps (the column square to every arc).
function wv.line(share)
    local shift = BALL / 2 - (BALL * 0.312 + 1) * math.sqrt(2)
    local x0, y0 = shift * math.cos(math.rad(-45)), shift * math.sin(math.rad(-45))
    local inner = BALL / 2 * 0.4275 + 5 + 16
    local function circle(s)
        return x0 + (27 - x0) * s, y0 + (8 - y0) * s, BALL / 2 + (inner - BALL / 2) * s
    end
    local cx, cy, r = circle(0)
    local a = math.rad(150)
    local x, y = cx + r * math.cos(a), cy + r * math.sin(a)
    for i = 1, 2000 do
        cx, cy, r = circle(share * i / 2000)
        a = math.atan2(y - cy, x - cx)
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
    end
    return cx, cy, r, a
end
function wv.startsLine(n, glyph, share) -- the glyph's leading edge on the column
    local _, _, r, start = wv.line(share)
    local p = glyph.points[1]
    return near((math.atan2(p[5], p[4]) + glyph:GetStringWidth() / 2 / r) * r, start * r, 0.3)
end
function wv.onLine(n, share)
    local cx, cy, r = wv.line(share)
    return near(n.points[1][4], cx) and near(n.points[1][5], cy)
        and near(n.arcRadius, r) and near(n.arcCurve, r) and wv.onArc(n)
        and wv.startsLine(n, n.glyphs[1], share)
end
L.healNotice:Hide(); L.damageNotice:Hide()
S.ShowHeal(1267)
fire("UNIT_COMBAT", "player", "WOUND", "", 120)
check("a wound shows its minus amount in pale pink, inward from a heal's plus in yellow",
    L.healNotice.shown and wv.said(L.healNotice) == "+1.2k" and L.healNotice.alpha == 0.95
    and L.healNotice.glyphs[1].color[2] > 0.9
    and L.damageNotice.shown and wv.said(L.damageNotice) == "-120" and L.damageNotice.alpha == 0.95
    and L.damageNotice.glyphs[1].color[1] == 1 and L.damageNotice.glyphs[1].color[2] > 0.75
    and L.damageNotice.glyphs[1].color[3] > L.damageNotice.glyphs[1].color[2])
check("both notices use larger text; damage moves inward only while healing shows",
    L.damageNotice.arcRadius < L.healNotice.arcRadius
    and L.healNotice.glyphs[1].fontSize > L.over.health.current.fontSize
    and L.damageNotice.glyphs[1].fontSize == L.healNotice.glyphs[1].fontSize
    and L.healNotice.protected.fontSize == L.damageNotice.protected.fontSize
    and L.healNotice.protected.fontSize > L.over.health.current.fontSize)
check("with a pet orb, the heal's line is halfway to it, a wound's under it; both start on one column",
    L.holed and wv.onLine(L.healNotice, 0.5) and wv.onLine(L.damageNotice, 1))
check("their arcs bend a step more towards the inner sphere, each turned a step further; health stays",
    near(math.atan2(L.over.health.separator.points[1][5], L.over.health.separator.points[1][4]), math.rad(135), 0.001)
    and BALL / 2 > L.healNotice.arcCurve and L.healNotice.arcCurve > L.damageNotice.arcCurve
    and L.healNotice.arcAngle - math.pi / 2 > L.over.health.separator.rotation
    and L.damageNotice.arcAngle > L.healNotice.arcAngle)
check("plain heal and damage digits visibly bend along their arcs",
    math.abs(L.healNotice.glyphs[1].rotation - L.healNotice.glyphs[5].rotation) > math.rad(7)
    and math.abs(L.damageNotice.glyphs[1].rotation - L.damageNotice.glyphs[4].rotation) > math.rad(10)
    and wv.onArc(L.healNotice) and wv.onArc(L.damageNotice))
L.healNotice.scripts.OnUpdate(L.healNotice, 3.1)
check("damage returns to the heal's line when the heal notice expires",
    not L.healNotice.shown and L.damageNotice.shown and wv.onLine(L.damageNotice, 0.5))
S.ShowHeal(100)
check("a new heal moves an existing damage notice to the inner line",
    wv.onLine(L.healNotice, 0.5) and wv.onLine(L.damageNotice, 1))
L.healNotice.scripts.OnUpdate(L.healNotice, 3.1)
wv.count = L.damageNotice.count
S.ShowDamage(0)
fire("UNIT_COMBAT", "player", "WOUND", "", hide(300))
check("a hidden wound is formatted by the game; nothing for none", L.damageNotice.count == wv.count + 1
    and L.damageNotice.protected.shown and issecretvalue(L.damageNotice.protected.text)
    and L.damageNotice.sign.shown and wv.said(L.damageNotice) == "-300"
    and math.abs(L.damageNotice.sign.rotation - L.damageNotice.protected.rotation) > math.rad(8)
    and wv.arcPart(L.damageNotice, L.damageNotice.sign)
    and wv.arcPart(L.damageNotice, L.damageNotice.protected))
L.damageNotice.scripts.OnUpdate(L.damageNotice, 2)
wv.fading = L.damageNotice.shown and L.damageNotice.alpha < 0.95 and L.damageNotice.alpha > 0
L.damageNotice.scripts.OnUpdate(L.damageNotice, 1.1)
check("the damage fades out like the heal", wv.fading and not L.damageNotice.shown)
S.ShowHeal(hide(25))
check("a protected heal's separate plus sign starts the column",
    L.healNotice.sign.shown and issecretvalue(L.healNotice.protected.text)
    and wv.startsLine(L.healNotice, L.healNotice.sign, 0.5)
    and wv.arcPart(L.healNotice, L.healNotice.sign) and wv.arcPart(L.healNotice, L.healNotice.protected))
L.healNotice:Hide()
-- Cracked glass (0.5.457-0.5.467), opt-in: a blow over 25% of the maximum cracks the health's glass,
-- over 40% larger, over 60% huge; it grows in 0.5 s, holds 3 s and mends in 2 s back into where it
-- broke, from a place at random. Forever hides the maximum: the game judges through a gate a size,
-- each crack drawn three times (small, large, huge), one or none shown.
;(function()
    local CRACK, drive = S.CRACK, L.crackDriver
    local GATE, R = 40000, BALL / 2
    local function busy(v)
        for _, c in ipairs(v.cracks) do if c.time then return c end end
    end
    local function shown(r)
        local n = 0
        for j = 1, r.n do if r.textures[j].shown then n = n + 1 end end
        return n
    end
    local function run(seconds) for _ = 1, math.floor(seconds / 0.05 + 0.5) do drive.scripts.OnUpdate(drive, 0.05) end end
    local function fed(c, amount, max)
        if not c then return false end
        for _, gate in ipairs(c.gates) do
            if not (reveal(gate.value) == amount and reveal(gate.max) == max and gate.min == 0) then return false end
        end
        return true
    end
    run(6)
    check("cracked glass is opt-in: off by default, a blow cracks nothing", SpheresDB.crackedGlass == false and not busy(L))
    SpheresDB.crackedGlass = true
    local c = L.cracks[1]
    local small, large, huge = c.drawings[1], c.drawings[2], c.drawings[3]
    check("each glass has its cracks ready: drawn small, large and huge in Media/CrackLine under its glass, over the liquid, cut to a piece and round the pet",
        #L.cracks == CRACK.pool and #L.pet.cracks == CRACK.pool and huge.textures[1].texture == MEDIA .. "CrackLine"
        and #small.textures == 32 and #large.textures == 64 and #huge.textures == 96
        and huge.frame.parent == L and huge.frame.level == L.glass.level - 1 and huge.frame.level > L.health.surface.level
        and huge.textures[1].masks[1] == huge.mask and huge.textures[1].masks[2] == huge.hole
        and small.textures[1].masks[1] == small.mask and small.textures[1].masks[2] == small.hole
        and not busy(L) and not drive.shown)
    local function past(gate, share) -- its fill reaches past the glass's right edge at `share`
        return near(gate.points[1][4] + share * GATE, R + 1) and gate.points[1][1] == "LEFT" and near(gate.w, GATE)
            and gate.orientation == "HORIZONTAL"
    end
    local function band(r, gate, nextGate) -- over its gate's fill and the next one's unfilled part
        local f = r.frame
        if not nextGate then return f.clips and f.points[1][2] == gate.barTexture end
        return f.clips and f.parent.clips and f.parent.points[1][2] == gate.barTexture
            and f.points[1][1] == "TOPLEFT" and f.points[1][2] == nextGate.barTexture and f.points[1][3] == "TOPRIGHT"
            and f.points[2][1] == "BOTTOMRIGHT" and f.points[2][2] == nextGate
    end
    check("the gates: their fills past the glass at 25%, 40% and 60%; each size over its gate's fill and the next one's unfilled part",
        past(c.gates[1], 0.25) and past(c.gates[2], 0.40) and past(c.gates[3], 0.60)
        and band(small, c.gates[1], c.gates[2]) and band(large, c.gates[2], c.gates[3]) and band(huge, c.gates[3]))
    fire("UNIT_COMBAT", "player", "WOUND", "", hide(300))
    c = busy(L)
    check("a hidden blow: a crack the game judges, every gate fed the blow out of your hidden maximum", fed(c, 300, HP.max))
    -- where it breaks: anywhere on the health's glass at random (0.5.467), in from its edge, the seam and the scoop
    local placed = true
    for _ = 1, 60 do
        run(6)
        S.Crack("player")
        local k = busy(L)
        local p = k.anchor.points[1]
        local x, y = k.x, k.y
        placed = placed and p[2] == L and near(p[4], x * R) and near(p[5], y * R)
            and x * x + y * y < 0.92 * 0.92 + 1e-6 and x > -1 + 0.08 - 1e-6 and x < 0.1897 - 0.08 + 1e-6
            and (not L.holed or (x - 27 / R) ^ 2 + (y - 8 / R) ^ 2 >= ((R * 0.4275 + 7) / R + 0.08) ^ 2 - 1e-6)
            and k.drawings[3].textures[1].points[1][2] == k.anchor and k.drawings[3].impact.points[1][2] == k.anchor
    end
    check("it breaks anywhere on your health's glass, in from its edge, the seam and the inner sphere's scoop", placed)
    -- it grows toward the side with more room: from the left end right, from the right end left, both ways from the middle
    local grows = true
    for _ = 1, 40 do
        run(6)
        S.Crack("player")
        local k = busy(L)
        local rights = 0
        for i = 1, k.inward do if math.cos(k.heading[i]) > 0 then rights = rights + 1 end end
        local want = k.inward * (1 - k.across)
        grows = grows and rights == k.rights and rights >= math.floor(want) and rights <= math.floor(want) + 1
    end
    check("it grows toward the side with more room: right from near the left, left from near the right, as many each way from the middle", grows)
    -- a branch reaching the scoop bends along its rim (0.5.467): no line ends inside it
    local hugs, inside = 0, false
    for _ = 1, 40 do
        run(6)
        S.Crack("player")
        local k = busy(L)
        for i = 1, k.count do
            local g = k.lines[i]
            local ex, ey = k.x + g.x0 + g.dx * g.len, k.y + g.y0 + g.dy * g.len
            local d = math.sqrt((ex - k.sx) ^ 2 + (ey - k.sy) ^ 2)
            if math.abs(d - k.sr) < 1e-3 then hugs = hugs + 1 end
            if g.s > 0.07 and d < k.sr - 1e-3 then inside = true end -- (past the splinters round the impact)
        end
    end
    check("with an inner sphere, its branches bend along the scoop's rim, not into it", L.holed and hugs > 0 and not inside)
    run(6)
    fire("UNIT_COMBAT", "player", "WOUND", "", hide(300))
    c = busy(L)
    small, large, huge = c.drawings[1], c.drawings[2], c.drawings[3]
    check("on yours, it stops at the scoop round the inner sphere (CrackCavity, with the pet hole)",
        c and huge.hole.on == MEDIA .. "CrackCavity" and small.hole.on == MEDIA .. "CrackCavity")
    check("cut to your health's piece; the small crack a part of the large, the large of the huge",
        c and huge.mask.texture == MEDIA .. "MaskHealth" and small.mask.texture == MEDIA .. "MaskHealth"
        and c.count >= 12 and huge.n == c.count and small.n > 0 and small.n < large.n and large.n < huge.n
        and small.reach < large.reach and large.reach <= huge.reach and drive.shown)
    run(0.1)
    local early = shown(huge)
    run(0.45)
    check("it grows from where it broke in 0.5 s, each size over its own reach",
        early > 0 and early < c.count and shown(huge) == c.count and shown(small) == small.n and shown(large) == large.n)
    run(3.5)
    local mending = shown(huge)
    run(1.5)
    check("after 3 s it mends in 2 s, drawing back into where it broke, then it's gone",
        mending > 0 and mending < c.count and not c.time and shown(huge) == 0 and shown(small) == 0
        and not huge.impact.shown and not small.impact.shown and not drive.shown)
    -- plain values: none under 25%, else through the gates too
    local hiddenMax = UnitHealthMax
    UnitHealthMax = function(u) if u == "player" then return 1000 end return hiddenMax(u) end
    S.Wound("player", 240)
    local none = busy(L)
    S.Wound("player", 250)
    c = busy(L)
    UnitHealthMax = hiddenMax
    check("plain values: under 25% no crack, from it one, the gates fed them", none == nil and fed(c, 250, 1000))
    run(6)
    fire("UNIT_COMBAT", "pet", "WOUND", "", hide(200))
    c = busy(L.pet)
    check("your pet's blows crack its glass (UNIT_COMBAT for the pet too)", fed(c, 200, PET.max)
        and c.drawings[3].mask.texture == MEDIA .. "MaskPet" and busy(L) == nil)
    run(6)
    SlashCmdList.SPHERES("crack")
    local hugeOne = fed(busy(L), 1, 1)
    run(6)
    SlashCmdList.SPHERES("crack small")
    local smallOne = fed(busy(L), 0.3, 1)
    run(6)
    SlashCmdList.SPHERES("crack large")
    local largeOne = fed(busy(L), 0.5, 1)
    run(6)
    SlashCmdList.SPHERES("crack gate")
    check("/spheres crack: the huge crack; small, large; gate: judged with your hidden maximum",
        hugeOne and smallOne and largeOne and fed(busy(L), HP.max, HP.max))
    run(6)
    SlashCmdList.SPHERES("crack off")
    local off = SpheresDB.crackedGlass == false
    SlashCmdList.SPHERES("crack on")
    check("/spheres crack off and on: the setting", off and SpheresDB.crackedGlass == true)
    L.damageNotice:Hide()
end)()
HP.ptype, HP.token = 1, "RAGE"
fire("UNIT_DISPLAYPOWER", "player")
wv.run(6)
fire("UNIT_POWER_UPDATE", "player")
wv.run(0.5)
check("rage drains on its own: it never lifts", pb.surge == 0)
-- an empty power liquid shows no wavy top; it fades in over the bar's first 3%
SURF.power = HP.power
HP.power = 0
fire("UNIT_POWER_UPDATE", "player")
SURF.emptyCrest = reveal(pb.crest.alpha)
SURF.emptyPile = reveal(pb.pile.alpha)
HP.power = 0.015 * HP.powerMax
fire("UNIT_POWER_UPDATE", "player")
SURF.halfCrest, SURF.halfLine, SURF.lowPile = reveal(pb.crest.alpha), reveal(pb.line.alpha), reveal(pb.pile.alpha)
HP.power = 0.04 * HP.powerMax
fire("UNIT_POWER_UPDATE", "player")
SURF.risingPile = reveal(pb.pile.alpha)
HP.power = SURF.power
fire("UNIT_POWER_UPDATE", "player")
check("empty: no wavy top at the bottom; it fades in over the first 3%", SURF.emptyCrest == 0
    and near(SURF.halfCrest, 0.5) and near(SURF.halfLine, 0.275) and reveal(pb.crest.alpha) == 1)
check("no slosh climb under 3% (0.5.444: \"a brief jumping effect\" at 0 rage), in full by 5%",
    SURF.emptyPile == 0 and SURF.lowPile == 0 and near(SURF.risingPile, 0.5) and reveal(pb.pile.alpha) == 1)
HP.ptype, HP.token = 0, "MANA"
fire("UNIT_DISPLAYPOWER", "player")
HP.ptype, HP.token = 1, "RAGE"
fire("UNIT_DISPLAYPOWER", "player")
check("rage: red-orange", pb.color[1] == 0.9 and pb.crest.vertex[1] == 0.9 and pb.line.vertex[1] == 1)
HP.ptype, HP.token = 0, "MANA"
fire("UNIT_DISPLAYPOWER", "player")
check("mana: blue again", pb.color[3] == 0.58)

-- A player without a pet and without mana uses the full outer glass for health.
PET.exists = false
SpheresPet:Hide() -- unit watch removes the pet button when the player has no pet
HP.ptype, HP.token = 1, "RAGE"
L.valueHover = true
fire("UNIT_DISPLAYPOWER", "player")
S.UpdatePet()
S.UpdateValueVisibility()
SURF.innerPower = L.innerPower
check("rage layout fills the outer health sphere and puts rage in the embedded sphere",
    L.wholeHealth and L.wholeHealth.shown and not hb.shown and not pb.shown
    and SURF.innerPower and SURF.innerPower.shown and SURF.innerPower.bar.color[1] == 0.9)
S.ShowHeal(50)
S.ShowDamage(30)
check("without a pet, inner rage still lays the two notices out towards it",
    L.holed and wv.onLine(L.healNotice, 0.5) and wv.onLine(L.damageNotice, 1)
    and near(math.atan2(L.over.health.separator.points[1][5], L.over.health.separator.points[1][4]), math.rad(135), 0.001))
L.healNotice:Hide(); L.damageNotice:Hide()
check("full health: one backing, no opening at the top where health and mana would meet",
    L.back.texture == MEDIA .. "OrbBackWhole")
-- no rage: no sliver of the wavy top at the bottom; the game's hidden answer sets its strength
SURF.power = HP.power
HP.power = 0
fire("UNIT_POWER_UPDATE", "player")
SURF.rageCrest, SURF.rageLine = SURF.innerPower.bar.crest.alpha, SURF.innerPower.bar.line.alpha
SURF.ragePileEmpty = reveal(SURF.innerPower.bar.pile.alpha)
HP.power = SURF.power
fire("UNIT_POWER_UPDATE", "player")
SURF.ragePile = reveal(SURF.innerPower.bar.pile.alpha)
check("no rage, no wavy top or slosh climb; some rage, all of it", issecretvalue(SURF.rageCrest)
    and reveal(SURF.rageCrest) == 0 and reveal(SURF.rageLine) == 0 and SURF.ragePileEmpty == 0 and SURF.ragePile == 1
    and reveal(SURF.innerPower.bar.crest.alpha) == 1 and near(reveal(SURF.innerPower.bar.line.alpha), 0.55))
check("rage layout moves both numbers to their matching spheres",
    SURF.innerPower and SURF.innerPower.over.value.shown and not L.over.power.shown
    and L.over.health.shown and SURF.innerPower.over.value.current.text ~= "")
-- where the client draws each part: its anchor plus the turned text's lift (Sphere.lua TURN_LIFT)
function SURF.drawn(fs)
    local p, r = fs.points[1], fs.rotation
    local x, y = p[4] + S.TURN_LIFT * math.sin(r), p[5] + S.TURN_LIFT * (1 - math.cos(r))
    return math.sqrt(x * x + y * y), math.deg(math.atan2(y, x))
end
SURF.rage = SURF.innerPower.over.value
SURF.rageR = BALL / 2 * 0.4275 - 8
SURF.curR, SURF.curA = SURF.drawn(SURF.rage.current)
SURF.sepR, SURF.sepA = SURF.drawn(SURF.rage.separator)
SURF.maxR, SURF.maxA = SURF.drawn(SURF.rage.maximum)
check("rage values sit at 5 o'clock on the embedded sphere, all three parts the same gap from its rim",
    near(SURF.sepA, -60, 0.01) and near(SURF.curA + SURF.maxA, -120, 0.01) and SURF.curA < SURF.maxA
    and near(SURF.curR, SURF.rageR, 0.01) and near(SURF.sepR, SURF.rageR, 0.01) and near(SURF.maxR, SURF.rageR, 0.01)
    and SURF.rage.points[1][4] == 0 and SURF.rage.points[1][5] == 0)
L.valueHover = false
ns.db.sphereValuesAlways = true
S.UpdateValueVisibility()
check("always show keeps outer health and inner rage values visible",
    L.over.health.shown and SURF.innerPower.over.value.shown and not L.over.power.shown)
ns.db.sphereValuesAlways = false
L.valueHover = true
S.UpdateValueVisibility()
check("whole health and embedded rage use their own masks, glass and hidden values",
    L.wholeHealth.mask.texture == MEDIA .. "MaskWhole"
    and L.wholeHealth.surface.shade.texture == MEDIA .. "LiquidShadeWhole"
    and L.wholeHealth.glass.texture == MEDIA .. "GlassWhole"
    and SURF.innerPower.bar.mask.texture == MEDIA .. "MaskPet"
    and reveal(L.wholeHealth.value) == HP.cur and reveal(SURF.innerPower.bar.value) == HP.power
    and L.holed and L.bowl.shown)
check("inner power contact shadow sits outside its liquid and follows the hidden level",
    SURF.innerPower.bar.contact.barTexture.texture == MEDIA .. "PetContactShadow"
    and SURF.innerPower.bar.contact.parent == SURF.innerPower
    and SURF.innerPower.bar.contact.w > SURF.innerPower.bar.w
    and SURF.innerPower.bar.contact.level < SURF.innerPower.bar.level
    and reveal(SURF.innerPower.bar.contact.value) == reveal(SURF.innerPower.bar.value)
    and SURF.innerPower.bar.contact.interpolation == SURF.innerPower.bar.interpolation)
SURF.rageLevel = HP.power
HP.power = 0
S.UpdateLeft()
SURF.emptyContact = reveal(SURF.innerPower.bar.contact.alpha)
HP.power = HP.powerMax * 0.05
S.UpdateLeft()
SURF.lowContact = reveal(SURF.innerPower.bar.contact.alpha)
HP.power = HP.powerMax * 0.10
S.UpdateLeft()
SURF.risingContact = reveal(SURF.innerPower.bar.contact.alpha)
HP.power = SURF.rageLevel
S.UpdateLeft()
check("empty inner power keeps a small contact spot and its added shade rises softly at 5-10 percent",
    SURF.innerPower.contactBase.texture == MEDIA .. "PetContactBase"
    and SURF.innerPower.contactBase.shown and SURF.emptyContact == 0
    and SURF.lowContact > 0 and SURF.lowContact < 0.1
    and SURF.risingContact > SURF.lowContact and SURF.risingContact < 0.2)
S.LiquidSpent("power")
check("rage spending belongs to the embedded liquid", SURF.innerPower.bar.spentAt ~= nil
    and SURF.innerPower.bar.rises == false)
HP.incoming = 200
fire("UNIT_HEAL_PREDICTION", "player")
check("incoming heals follow the full health glass", L.wholeHeal.shown and not L.heal.shown
    and L.wholeHealBand.masks[1] == L.wholeHealth.mask and reveal(L.wholeHeal.value) == 200)
HP.incoming = nil
UnitIsDeadOrGhost = function() return true end
fire("UNIT_HEALTH", "player")
check("both liquids empty on death in the rage layout", L.wholeHealth.alpha == 0
    and SURF.innerPower.bar.alpha == 0 and SURF.innerPower.bar.contact.alpha == 0)
UnitIsDeadOrGhost = nil
fire("UNIT_HEALTH", "player")
HP.ptype, HP.token = 0, "MANA"
fire("UNIT_DISPLAYPOWER", "player")
check("switching to mana restores the split glass, its backing and its power values",
    hb.shown and pb.shown and not L.wholeHealth.shown and not SURF.innerPower.shown
    and L.over.power.shown and not SURF.innerPower.over.value.shown and not L.holed
    and L.back.texture == MEDIA .. "OrbBack")
S.ShowHeal(50)
S.ShowDamage(30)
check("without an embedded sphere, both notices keep the ordinary outer arc",
    L.healNotice.arcCurve == 50 and L.damageNotice.arcCurve == 50
    and near(L.healNotice.arcRadius, L.damageNotice.arcRadius)
    and near(math.atan2(L.over.health.separator.points[1][5], L.over.health.separator.points[1][4]), math.rad(135), 0.001)
    and near(L.healNotice.arcAngle, math.rad(135), 0.001)
    and near(L.damageNotice.arcAngle, math.rad(135), 0.001)
    and near(L.damageNotice.points[1][4], -22 * math.cos(math.rad(135)), 0.01)
    and near(L.damageNotice.points[1][5], -22 * math.sin(math.rad(135)), 0.01))
HP.ptype, HP.token = 1, "RAGE"
fire("UNIT_DISPLAYPOWER", "player")
check("visible notices follow the embedded power sphere when it appears",
    L.holed and wv.onLine(L.healNotice, 0.5) and wv.onLine(L.damageNotice, 1))
HP.ptype, HP.token = 0, "MANA"
fire("UNIT_DISPLAYPOWER", "player")
check("visible notices return to the outer arc when the embedded sphere vanishes",
    not L.holed and L.healNotice.arcCurve == 50 and L.damageNotice.arcCurve == 50
    and near(L.damageNotice.points[1][4], -22 * math.cos(math.rad(135)), 0.01))
L.healNotice:Hide(); L.damageNotice:Hide()
L.valueHover = false
HP.ptype, HP.token = 1, "RAGE"
fire("UNIT_DISPLAYPOWER", "player")
PET.exists = true
SpheresPet:Show()
fire("UNIT_PET", "player")
check("a pet keeps the split player layout available for non-mana power, its backing too",
    not L.wholeHealth.shown and hb.shown and pb.shown and not SURF.innerPower.shown
    and L.back.texture == MEDIA .. "OrbBack")
HP.ptype, HP.token = 0, "MANA"
fire("UNIT_DISPLAYPOWER", "player")
S.UpdatePet()
S.UpdateValueVisibility()

-- Your pet: an orb of its own, for now beside the left sphere (its cavity in it waits on the player)
-- (Blizzard's PetFrame goes with the player frame)
local pet = SpheresPet
SURF.rb = BALL / 2 * 0.4275
SURF.rh = SURF.rb + 5.0
check("a pet orb: a secure button for the pet, shown while there is one", pet and pet.mockProtected
    and pet.attrs.unit == "pet" and pet.attrs.type1 == "target" and pet.attrs.type2 == "togglemenu"
    and watched[pet] == true and pet.parent == SpheresHUD)
check("in the scoop, right of the middle and a little up, see-through (no back)",
    pet.points[1][1] == "CENTER" and pet.points[1][2] == SpheresLeft and pet.points[1][4] == 27 and pet.points[1][5] == 8
    and pet.back == nil and pet.level > L.glass.level and pet.gap.level > pet.glass.level)
fire("UNIT_PET", "player")
fireScript(pet, "OnShow")
check("your health and mana carry the scoop: its concave walls on their glass round the pet's ball, their liquid on in it",
    L.holed and #L.holes == 18 and L.holes[1].texture == MEDIA .. "PetCavity" and L.bowl.shown
    and L.bowl.texture == MEDIA .. "PetBowl" and L.bowl.parent == L.glass and L.bowl.layer == "OVERLAY"
    and near(L.bowl.w, 2 * (SURF.rb + 7)) and L.bowl.points[1][2] == SpheresLeft
    and L.bowl.points[1][4] == 27 and L.bowl.points[1][5] == 8
    and L.glassHealth.texture == MEDIA .. "GlassHealth")
PET.exists = false
fire("UNIT_PET", "player")
fireScript(pet, "OnHide")
SURF.holesOff = true
for _, m in ipairs(L.holes) do SURF.holesOff = SURF.holesOff and m.texture == "Interface\\Buttons\\WHITE8x8" end
check("without a pet, no scoop: your health and mana as they were (\"Characters without pets shouldn't have that cavity\")",
    not L.holed and not L.bowl.shown and SURF.holesOff)
PET.exists = true
fire("UNIT_PET", "player")
local whole = pet.whole
SURF.magicIn = function(bar)
    local n, purple = 0, true
    for _, layer in ipairs(bar.motion) do
        if layer.spec.magic and not layer.spec.twin then -- not the gold's dark twins (unseen here)
            n = n + 1
            local v = layer.texture.vertex
            purple = purple and v[3] > v[1] and v[3] > v[2] and layer.texture.alpha > 0
        end
    end
    return n, purple
end
SpheresLeft.scripts.OnUpdate(SpheresLeft, 0.05)
SURF.wholeMagic, SURF.wholePurple = SURF.magicIn(whole)
check("a Hunter's pet: one orb, its health red with purple magic in it, its own hidden numbers", whole.shown
    and not pet.health.shown and not pet.mana.shown and whole.base.texture == MEDIA .. "FillPet"
    and whole.color[1] > whole.color[3] and whole.color[1] > whole.color[2] and SURF.wholeMagic == 5 and SURF.wholePurple
    and issecretvalue(whole.value) and reveal(whole.value) == 180 and reveal(whole.max) == 300
    and whole.interpolation == 1 and whole.glass.shown)
check("whole pet liquid reveals a contact shadow outside its glass as it fills",
    whole.contact.barTexture.texture == MEDIA .. "PetContactShadow" and whole.contact.parent == pet
    and whole.contact.w > whole.w and whole.contact.level < whole.level
    and reveal(whole.contact.value) == reveal(whole.value)
    and whole.contact.interpolation == whole.interpolation and whole.clip.points[2][2] == whole.barTexture)
SURF.petLevel = PET.cur
PET.cur = 0
S.UpdatePet()
SURF.emptyPetContact = reveal(whole.contact.alpha)
PET.cur = 15
S.UpdatePet()
SURF.lowPetContact = reveal(whole.contact.alpha)
PET.cur = SURF.petLevel
S.UpdatePet()
check("empty pet orb retains its small contact spot and gently adds shade at five percent",
    pet.contactBase.texture == MEDIA .. "PetContactBase" and pet.contactBase.shown
    and SURF.emptyPetContact == 0 and SURF.lowPetContact > 0 and SURF.lowPetContact < 0.1)
check("its liquid the big ones' without their bottom shadow, the clouds the same size on the screen, no mana glints",
    #whole.motion == #pb.motion and near(whole.motion[1].scale, 2 * SURF.rb / BALL) and #whole.glints == 0
    and whole.crest and near(whole.unit, 0.4275) and whole.surface.shade == nil and pet.health.surface.shade == nil)
check("smaller than 0.5.271's by a quarter; clicks inside its ball, so the ring still targets you",
    near(SURF.rb, BALL / 2 * 0.57 * 0.75) and near(pet.hitInsets and pet.hitInsets[1] or -1, SURF.rh - SURF.rb * math.sqrt(0.5)))
check("its mood on its edge", pet.mood.shown and pet.mood.atlas == "UI-PetHappiness" and pet.moodLevel == 3)
PET.cur = 90
fire("UNIT_HEALTH", "player")
SURF.ownOnly = reveal(whole.value) == 180
fire("UNIT_HEALTH", "pet")
check("it follows the pet's events, not yours", SURF.ownOnly and reveal(whole.value) == 90)
fireScript(pet, "OnEnter")
check("its tooltip: the pet, its mood, its menu", GameTooltip.owner == pet and tipText():find("Happy", 1, true)
    and tipText():find("Right-click for pet options", 1, true))
check("its values while hovered: health at 3 o'clock along its rim (no mana value for a pet without)",
    pet.over.health.shown and not pet.over.mana.shown and pet.over.health.current.text ~= ""
    and pet.over.health.points[1][2] == pet and pet.mood.points[1][4] == 0 and pet.mood.points[1][5] > 0)
fireScript(pet, "OnLeave")
SpheresLeft.scripts.OnUpdate(SpheresLeft, 0.1)
SURF.petTc = whole.motion[1].texture.texcoord
SpheresLeft.scripts.OnUpdate(SpheresLeft, 0.5)
check("it churns with the left sphere", SURF.petTc and whole.motion[1].texture.texcoord[1] ~= SURF.petTc[1])
PET.hunter = false
PET.ptype, PET.token = 0, "MANA"
fire("UNIT_PET", "player")
SURF.seamX = 27 + (pet.mana.points[1][4] + pet.mana.w / 2) -- the mana half's right edge, on the left sphere
check("a Warlock's demon: cut in two upright along your own seam, mana the smaller left, health the bigger right, no mood",
    not whole.shown and not whole.glass.shown
    and pet.health.shown and pet.mana.shown and pet.health.glass.shown and pet.mana.glass.shown
    and pet.mana.points[1][4] < 0 and pet.health.points[1][4] > 0 and pet.health.w > pet.mana.w
    and math.abs(pet.health.points[1][5]) < 1 and near(SURF.seamX, hb.points[1][4] + hb.w / 2, 0.6)
    and reveal(pet.health.value) == 90 and reveal(pet.mana.value) == 50 and reveal(pet.mana.max) == 100
    and pet.mana.color[3] > pet.mana.color[1] and pet.mana.color[1] > pet.mana.color[2] and pet.mana.color ~= pb.color
    and not pet.mood.shown and select(1, SURF.magicIn(pet.health)) == 5 and select(1, SURF.magicIn(pet.mana)) == 0)
check("split health and mana reveal their own outside contact shadow arcs",
    pet.health.contact.barTexture.texture == MEDIA .. "PetContactShadowHealth"
    and pet.mana.contact.barTexture.texture == MEDIA .. "PetContactShadowMana"
    and pet.health.contact.parent == pet and pet.mana.contact.parent == pet
    and pet.health.contact.shown and pet.mana.contact.shown and not whole.contact.shown
    and reveal(pet.health.contact.value) == reveal(pet.health.value)
    and reveal(pet.mana.contact.value) == reveal(pet.mana.value)
    and pet.health.clip.points[2][2] == pet.health.barTexture
    and pet.mana.clip.points[2][2] == pet.mana.barTexture)
fireScript(pet, "OnEnter")
check("a demon's values: mana at 9 o'clock over its left part, health at 3 over its right", pet.over.mana.shown
    and pet.over.health.shown and pet.over.mana.current.text ~= "" and pet.over.mana.separator.text == "/")
check("both set back left and down, where the client draws text turned a quarter round",
    #pet.over.mana.points == 1 and (pet.over.mana.points[1][4] or 0) < 0 and (pet.over.mana.points[1][5] or 0) < 0
    and pet.over.health.points[1][4] == pet.over.mana.points[1][4]
    and pet.over.health.points[1][5] == pet.over.mana.points[1][5])
fireScript(pet, "OnLeave")
check("gone when the mouse leaves (unless always shown)", ns.db.sphereValuesAlways == true or
    (not pet.over.health.shown and not pet.over.mana.shown))
PET.dead = true
fire("UNIT_HEALTH", "pet")
check("a dead pet: its liquid gone", pet.health.alpha == 0 and pet.mana.alpha == 0 and pet.health.surface.alpha == 0)
PET.dead, PET.hunter, PET.ptype, PET.token = false, true, 2, "FOCUS"
fire("UNIT_PET", "player")
fireScript(SpheresLeft, "OnEnter")
local nh, np = L.over.health, L.over.power
check("hovered: what you have / what you can have, side by side, the game joining hidden values", nh.shown and np.shown
    and issecretvalue(nh.text.text) and reveal(nh.text.text) == "200|cff8c8c8c / 1.0k|r"
    and reveal(np.text.text) == "300|cff8c8c8c / 600|r")
check("shortened from 1000 up by the game (1267 -> 1.2k, 12345 -> 12k)", AbbreviateNumbers(1267, S.ABBREVIATE) == "1.2k"
    and AbbreviateNumbers(12345, S.ABBREVIATE) == "12k" and AbbreviateNumbers(999, S.ABBREVIATE) == "999")
check("health and mana in one style, faded and two sizes under the game's font", nh.text.font == np.text.font
    and nh.text.fontSize == 9 and np.text.fontSize == 9 and nh.text.color[4] == 0.7
    and nh.current.points[1][4] < 0 and np.current.points[1][4] > 0)
fireScript(SpheresLeft, "OnLeave")
check("and gone after", not nh.shown and not np.shown)
local heal, band = L.heal, L.healBand
check("no heals coming: nothing over your health", heal.value == 0)
HP.incoming = 300
fire("UNIT_HEAL_PREDICTION", "player")
check("a heal on its way: the amount, hidden, out of your maximum", issecretvalue(heal.value) and reveal(heal.value) == 300
    and reveal(heal.max) == 1000)
check("standing on your health's level, the piece's size", heal.points[1][1] == "BOTTOM" and heal.points[1][2] == hb.barTexture
    and heal.points[1][3] == "TOP" and near(heal.w, hb.w) and near(heal.h, hb.h) and heal.orientation == "VERTICAL")
check("a soft red band between the two, clipped to the health piece", band.points[1][2] == hb.barTexture
    and band.points[2][2] == heal.barTexture and band.points[2][1] == "TOPRIGHT" and band.masks[1] == hb.mask
    and band.vertex[1] > band.vertex[2] and band.vertex[4] < 1)
HP.incoming = nil
fire("UNIT_HEAL_PREDICTION", "player")
check("healed: gone", heal.value == 0)
local art = S.Art()
check("the default Modern lion and griffin beside the orbs", art.statueL.texture == MEDIA .. "StatueLeftModern"
    and art.statueR.texture == MEDIA .. "StatueRightModern" and art.statueL.shown and art.statueR.shown)
check("facing the orbs, their heads over the orbs' outer lower edges (where make_media.py drew their places)",
    near(art.statueL.points[1][4], -389.3 + 8 * 788 / 2048) and art.statueL.w == 121.6
    and near(art.statueR.points[1][4], 373.3 - 8 * 788 / 2048) and art.statueR.w == art.statueL.w
    and near(art.statueL.points[1][5], -1.4) and near(art.statueR.points[1][5], -1) -- migrated legacy offset and Modern alignment
    and art.statueL.points[1][2] == S.FrameAnchor() and art.statueR.points[1][2] == S.FrameAnchor()
    and near(art.frame.w, 788 * 2032 / 2048) and art.frame.h == 202 and art.frame.points[1][4] == 0
    and art.frame.points[1][5] == -1 and SpheresHUD.points[1][5] == 0)
check("carved frame over the orb glass, below the statues", art.frameLayer.level > L.glass.level
    and art.frameLayer.level < art.level and art.frame.layer == "BACKGROUND")
-- /spheres test: plain numbers, to tell drawing from hidden values
SURF.power = HP.power
HP.power = 0
fire("UNIT_POWER_UPDATE", "player") -- your own power empty: its top faded out
HP.power = SURF.power
SlashCmdList.SPHERES("test")
check("/spheres test: 70% health and 40% mana, plain, the mana's wavy top at full strength",
    hb.value == 0.7 and pb.value == 0.4 and hb.max == 1 and pb.crest.alpha == 1 and pb.line.alpha == 0.55)
SlashCmdList.SPHERES("test")
check("and back to yours", issecretvalue(pb.value))

-------------------------------------------------------------------------------
-- 3) the right sphere: Blizzard's minimap in it; the player frame hidden
-------------------------------------------------------------------------------
local Rt = S.Get("right")
local lx, ly = SpheresLeft:GetCenter()
local rx, ry = SpheresRight:GetCenter()
check("Modern orbs follow the compacted cavities and stay inside the bottom edge",
    near(lx, 960 - (320 - 8 * 788 / 2048)) and near(rx, 960 + (320 - 8 * 788 / 2048)) and near(ly, 92) and near(ry, 92)
    and lx + BALL / 2 < 960 - 220 and rx - BALL / 2 > 960 + 220)
check("the minimap inset in the right sphere", Minimap.parent == Rt.mapHolder and near(Minimap.w, BALL * 0.945)
    and Minimap.points[1][1] == "CENTER" and Minimap.points[1][2] == SpheresRight)
check("under a glass globe", Rt.glass.level > Rt.mapHolder.level and Rt.glass.kids[1].texture == MEDIA .. "GlassMap"
    and near(Rt.glass.kids[1].w, BALL))
check("round, its zoom buttons and compass out of sight", Minimap.maskFile and Minimap.ZoomIn.parent ~= Minimap
    and not MinimapCompassTexture.shown and Minimap.wheel)
Minimap:SetPoint("TOP", MinimapCluster, "TOP", 0, -30) -- Blizzard puts it back (Edit Mode)
check("Blizzard placing it again: back in the sphere", Minimap.points[#Minimap.points][2] == SpheresRight)
check("Blizzard's player frame hidden", PlayerFrame.parent ~= UIParent and S.PlayerFrameHidden())
slash("minimap")
check("/spheres minimap: back where it was", Minimap.parent == MinimapCluster and Minimap.w == 200 and Minimap.ZoomIn.parent == Minimap
    and MinimapCompassTexture.shown)
slash("minimap")
check("and into the sphere again", Minimap.parent == Rt.mapHolder)
check("the minimap's header out of sight with it (zone name, clock bar, tracking, calendar)", MinimapCluster.parent ~= UIParent)
local function pinnedAt(f)
    local p = f.points[#f.points]
    return f.parent == Rt.pins and p[1] == "CENTER" and p[2] == Rt.mailBadge
end
check("the mail icon in its brass badge", pinnedAt(mail))
do -- clear of the Bag hub and the lower row's last slot (13 places of 31.36, 3 apart: to x 221.84)
   -- and the Game Menu hub in its well (28.8 across at 241, 25: to y 39.4);
   -- 0.5.478: at x 230 the Bag hub came in front of it
    local b = Rt.mailBadge.points[1]
    local left, bottom = b[4] - Rt.mailBadge.w / 2, b[5] - Rt.mailBadge.h / 2
    check("the mail badge clear of the Bag hub, the last slot and the Game Menu hub", b[1] == "CENTER" and b[2] == S.FrameAnchor()
        and left > 226 + 2 and bottom > 39.4 + 2)
end
check("no clock: it stays in the hidden header", TimeManagerClockButton.parent == MinimapCluster)
local co = Rt.coords
co.scripts.OnUpdate(co, 0.3)
check("your coordinates are curved above the glass", co.parent == Rt.pins
    and co.glyphs[1] and co.glyphs[1].points[1][2] == co)
check("coordinates have a small, faded font", co.glyphs[1].color[4] < 1 and co.glyphs[1].fontSize == 9)
check("Blizzard's format", co.value == "45, 68")
CVARS.coordsByTenths = "1"
co.scripts.OnUpdate(co, 0.3)
check("tenths if you asked for them", co.value == "45.2, 67.8")
wv.mapAsks, wv.mapAsk = 0, C_Map.GetPlayerMapPosition
C_Map.GetPlayerMapPosition = function(...) wv.mapAsks = wv.mapAsks + 1; return wv.mapAsk(...) end
WHERE.x = 0.5123 -- you move
co.scripts.OnUpdate(co, 0.3)
check("coordinates five times a second from UnitPosition through the map's corners: no new Vector2D each time",
    co.value == "51.2, 67.8" and wv.mapAsks == 0)
WHERE.track.noUnitPosition = true
co.scripts.OnUpdate(co, 0.3)
check("without UnitPosition, the map's own answer", co.value == "51.2, 67.8" and wv.mapAsks == 1)
WHERE.track.noUnitPosition, WHERE.x, C_Map.GetPlayerMapPosition = nil, 0.4523, wv.mapAsk
CVARS.coordsByTenths = nil
WHERE.x = nil
co.scripts.OnUpdate(co, 0.3)
check("none where the map has none (an instance)", co.value == "")
WHERE.x = 0.4523
check("both over the glass and the art", Rt.pins.level > S.Art().level and Rt.pins.level > Rt.glass.level)
Rt.pins.scripts.OnUpdate(Rt.pins, 1)
check("the group finder eye over the globe, where Blizzard and Edit Mode put it",
    QueueStatusButton.level == Rt.pins.level + 2 and QueueStatusButton.strata == "MEDIUM"
    and QueueStatusButton.parent == UIParent and QueueStatusButton.points[1][2] == Minimap)
-- the minimap's arrow to a super-tracked quest, copied where the game draws it, where the griffin
-- covers it (about -95 to -36 degrees round the map)
wv.qa = Rt.questArrow
function wv.arrowTick() -- the game says the quest's place changed, then a frame
    wv.qa.ticker.scripts.OnEvent(wv.qa.ticker, "QUEST_POI_UPDATE")
    wv.qa.ticker.scripts.OnUpdate(wv.qa.ticker, 0.6)
end
function wv.aim(degrees, yards) -- a place on your map, `yards` away in that direction on the screen
    local a = math.rad(degrees)
    return { 0.4523 + yards * math.cos(a) / 1500, 0.6781 - yards * math.sin(a) / 1000 }
end
function wv.arrowAt(degrees)
    local p, r = wv.qa.points[#wv.qa.points], BALL * 0.945 / 2 * 0.82
    return wv.qa.shown and p[2] == Rt and near(p[4], r * math.cos(math.rad(degrees)))
        and near(p[5], r * math.sin(math.rad(degrees)))
        and near(wv.qa.texture.rotation, math.rad(degrees) - math.pi / 2)
end
wv.arrowTick()
check("no arrow while nothing is super-tracked", not wv.qa.shown)
WHERE.track.quest, WHERE.track.poi = 501, wv.aim(-60, 300) -- the map shows 233 yards
wv.qa.ticker.scripts.OnUpdate(wv.qa.ticker, 0.01)
wv.lagged = not wv.qa.shown
wv.qa.ticker.scripts.OnEvent(wv.qa.ticker, "SUPER_TRACKING_CHANGED")
check("a newly tracked quest's arrow comes with the game's event, not the next look-up",
    wv.lagged and wv.qa.shown and wv.qa.ticker.events.SUPER_TRACKING_CHANGED and wv.qa.ticker.events.QUEST_POI_UPDATE)
check("a quest beyond the minimap, behind the griffin: the arrow on the rim over it",
    wv.arrowAt(-60) and wv.qa.level > S.Art().level and wv.qa.w == 34 and wv.qa.alpha == 0.4
    and wv.qa.texture.texture == "Interface\\Minimap\\MiniMap-QuestArrow")
WHERE.track.poi = wv.aim(-85, 300)
wv.arrowTick()
check("it turns with the target's direction", wv.arrowAt(-85))
WHERE.track.poi = wv.aim(90, 300)
wv.arrowTick()
check("none clear of the griffin, where the minimap's own shows", not wv.qa.shown)
CVARS.rotateMinimap = "1"
wv.qa.ticker.scripts.OnUpdate(wv.qa.ticker, 0.016)
WHERE.track.facing = math.rad(150) -- you turn: north goes behind the griffin
wv.qa.ticker.scripts.OnUpdate(wv.qa.ticker, 0.016)
wv.idle = wv.qa.shown
wv.qa.ticker.scripts.OnUpdate(wv.qa.ticker, 0.1)
check("hidden, it checks ten times a second rather than every frame", not wv.idle and wv.arrowAt(-60))
CVARS.rotateMinimap, WHERE.track.facing = nil, 0
wv.arrowTick()
WHERE.track.waypoint = wv.aim(-45, 450) -- on the way to another zone
wv.arrowTick()
check("a waypoint on the way comes first", wv.arrowAt(-45))
WHERE.track.waypoint, WHERE.track.poi = nil, wv.aim(-60, 150)
wv.arrowTick()
check("none while the target is on the minimap", not wv.qa.shown)
WHERE.track.poi, WHERE.track.questDistance = wv.aim(-60, 300), 200
wv.arrowTick()
check("none once the game's own distance to the quest's area is within the map", not wv.qa.shown)
WHERE.track.questDistance, WHERE.track.inside = nil, true
wv.arrowTick()
check("none inside the quest's area", not wv.qa.shown)
WHERE.track.inside, ns.db.statueFinish = nil, "none"
wv.arrowTick()
check("none without the statues", not wv.qa.shown)
ns.db.statueFinish = "brass"
ns.Apply()
wv.arrowTick()
check("the griffin's head is solid while ours shows", wv.qa.shown and S.Art().statueR.texture == MEDIA .. "StatueRight")
ns.db.questArrow = false
ns.Apply()
wv.arrowTick()
check("the setting off: none of ours, the griffin's head see-through for the minimap's own",
    not wv.qa.shown and S.Art().statueR.texture == MEDIA .. "StatueRightClearHead"
    and S.Debug():find("quest arrow off (the setting)", 1, true) ~= nil)
ns.db.statueFinish = "charcoal"
ns.Apply()
check("in charcoal too", S.Art().statueR.texture == MEDIA .. "StatueRightClearHeadCharcoal")
ns.db.questArrow, ns.db.statueFinish = true, "brass"
ns.Apply()
wv.arrowTick()
check("and back on", wv.qa.shown and S.Art().statueR.texture == MEDIA .. "StatueRight")
WHERE.track.poi, WHERE.track.facing, CVARS.rotateMinimap = wv.aim(90, 300), math.rad(150), "1"
wv.arrowTick()
WHERE.track.facing = math.rad(160)
wv.qa.ticker.scripts.OnUpdate(wv.qa.ticker, 0.016)
check("a rotating minimap: north turns behind the griffin as you face it away, the very next frame",
    wv.arrowAt(-70))
WHERE.track.facing, CVARS.rotateMinimap, WHERE.track.quest, WHERE.track.poi = 0, nil, nil, nil
WHERE.track.pin = { uiMapID = WHERE.map, position = CreateVector2D(unpack(wv.aim(-60, 300))) }
wv.arrowTick()
check("your map pin, south-east", wv.arrowAt(-60))
check("/spheres debug says what it follows", S.Debug():find("quest arrow map pin 300 yd at 300 degrees (you by UnitPosition), map shows 233 yd", 1, true) ~= nil
    and S.Debug():find("behind the griffin, shown", 1, true) ~= nil)
WHERE.track.noUnitPosition = true
wv.arrowTick()
check("without UnitPosition, the map's way", wv.arrowAt(-60) and S.Debug():find("(you by the map)", 1, true) ~= nil)
WHERE.track.noUnitPosition = nil
WHERE.track.pin = nil
wv.arrowTick()
check("gone with the pin", not wv.qa.shown)
-- the red arrow to your corpse while you're a ghost (0.5.446: "same behavior for red arrow when
-- the character is dead"), beside the quest's
;(function() -- its own function: the main chunk is at Lua 5.1's 200 locals
    local ca = Rt.corpseArrow
    local function at(degrees)
        local p, r = ca.points[#ca.points], BALL * 0.945 / 2 * 0.82
        return ca.shown and p[2] == Rt and near(p[4], r * math.cos(math.rad(degrees)))
            and near(p[5], r * math.sin(math.rad(degrees))) and near(ca.texture.rotation, math.rad(degrees) - math.pi / 2)
    end
    local function event(name) wv.qa.ticker.scripts.OnEvent(wv.qa.ticker, name); wv.qa.ticker.scripts.OnUpdate(wv.qa.ticker, 0.6) end
    WHERE.track.corpse = wv.aim(-60, 300)
    event("PLAYER_DEAD")
    check("dead, not yet a ghost: no corpse arrow", not ca.shown)
    WHERE.track.ghost = true
    event("PLAYER_ALIVE") -- released: the game says alive, as a ghost
    check("a ghost, the corpse beyond the minimap, behind the griffin: the red arrow on the rim over it",
        at(-60) and ca.texture.texture == "Interface\\Minimap\\MiniMap-DeadArrow" and ca.alpha == 0.4 and ca.w == 34
        and ca.level == wv.qa.level and not wv.qa.shown)
    WHERE.x = 0.4523 + 50 / 1500 -- you walk toward it
    wv.qa.ticker.scripts.OnUpdate(wv.qa.ticker, 0.016)
    check("it turns as you move, the very next frame", ca.shown and not at(-60)
        and S.Debug():find("corpse arrow corpse", 1, true) ~= nil)
    WHERE.x = 0.4523
    WHERE.track.corpse = wv.aim(90, 300)
    event("CORPSE_OUT_OF_RANGE")
    check("none clear of the griffin, where the minimap's own shows", not ca.shown)
    WHERE.track.corpse = wv.aim(-60, 150)
    event("CORPSE_IN_RANGE")
    check("none while the corpse is on the minimap", not ca.shown)
    WHERE.track.corpse = wv.aim(-60, 300)
    ns.db.questArrow = false
    event("ZONE_CHANGED")
    check("the setting off: none of ours", not ca.shown)
    ns.db.questArrow = true
    event("ZONE_CHANGED")
    check("and back", at(-60))
    WHERE.track.ghost = false
    event("PLAYER_UNGHOST")
    check("alive again: gone", not ca.shown and S.Debug():find("corpse arrow no corpse", 1, true) ~= nil)
    WHERE.track.corpse = nil
end)()
mail:SetPoint("TOPLEFT", MinimapCluster.IndicatorFrame, "TOPLEFT", 0, 0) -- Blizzard lays its header out again
check("Blizzard placing the mail icon again: back in its badge", pinnedAt(mail))
ns.db.aurasAbove = false -- the setting off: the top right corner
ns.Apply()
check("buffs in the top right corner (their collapse arrow the margin), debuffs under them",
    BuffFrame.points[#BuffFrame.points][4] == 0 and BuffFrame.points[#BuffFrame.points][5] == -12
    and DebuffFrame.points[#DebuffFrame.points][4] == -15 and DebuffFrame.points[#DebuffFrame.points][5] == -157)
BuffFrame:ApplySystemAnchor() -- Edit Mode applies its layout
check("Edit Mode placing them again: back in the corner", BuffFrame.points[#BuffFrame.points][4] == 0)
slash("minimap")
check("the minimap back: its header, the mail icon and clock back in it, the buffs back where Blizzard puts them",
    MinimapCluster.parent == UIParent and mail.parent == MinimapCluster.IndicatorFrame
    and mail.points[#mail.points][2] == MinimapCluster.IndicatorFrame and not Rt.coords.shown
    and QueueStatusButton.level == 2
    and BuffFrame.points[#BuffFrame.points][4] == -255 and DebuffFrame.points[#DebuffFrame.points][4] == -270)
AURA_HOME[DebuffFrame].inDefault = false -- the player moves the debuffs in Edit Mode
DebuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -500, -300)
slash("minimap")
check("and in a sphere again; debuffs the player moved stay where they are", pinnedAt(mail, -0.53, 0.53)
    and BuffFrame.points[#BuffFrame.points][4] == 0 and DebuffFrame.points[#DebuffFrame.points][4] == -500)
AURA_HOME[DebuffFrame].inDefault = true
ns.db.aurasAbove = true
ns.Apply()

-------------------------------------------------------------------------------
-- 4) the rows in Roth's frame; your experience in its slots; Blizzard's bars out of sight
-------------------------------------------------------------------------------
local b1, b5, b21 = SpheresBar1Button1, SpheresBar1Button5, SpheresBar2Button1
check("25 secure action buttons plus the dedicated Bag position", SpheresBar1Button12 and not SpheresBar1Button13
    and SpheresBar2Button13 and B.BagAnchor() and b1.template == "SecureActionButtonTemplate")
check("Bar 1's buttons: an ID and no slot, so the game pages them", b1.id == 1 and b1.attrs.action == nil and SpheresBar1Button12.id == 12)
check("Bar 2: slots 61-72 plus Bar 8's final slot", b21.attrs.action == 61
    and SpheresBar2Button12.attrs.action == 72 and SpheresBar2Button13.attrs.action == 180)
check("the extra action has its own binding", overrides["CTRL-B"] and overrides["CTRL-B"].name == "SpheresBar2Button13")
ACTIONS[180] = spell("Extra_slot")
fire("ACTIONBAR_SLOT_CHANGED", 180)
combat = true
press("CTRL-B")
check("the extra bound button uses Bar 8's last action in combat", used[#used] == 180
    and SpheresBar2Button13.art.icon.texture == ACTIONS[180].texture)
combat = false
check("the look follows: Bar 1's first slot shows", b1.action == 1 and b1.art.icon.texture == ACTIONS[1].texture)
-- no garbage several times a second: one paint table per button; the game's cooldown duration
-- objects asked for only after a cooldown event
wv.cd, wv.paint = b1.art.cooldown.cooldown and b1.art.cooldown.cooldown.obj, b1.paint
B.Update(true)
check("the rows' quick refresh keeps the cooldowns as painted, and each button's paint table",
    wv.cd and wv.paint and b1.art.cooldown.cooldown.obj == wv.cd and b1.paint == wv.paint)
fire("ACTIONBAR_UPDATE_USABLE")
check("so does a usable change", b1.art.cooldown.cooldown.obj == wv.cd)
fire("ACTIONBAR_UPDATE_COOLDOWN")
check("a cooldown change paints them again", b1.art.cooldown.cooldown.obj ~= wv.cd and b1.paint == wv.paint)
-- no timer repaints the rows: range and usable come with the game's events
check("the game reports range for each slot the rows show", C_ActionBar.ranged[1] == true and C_ActionBar.ranged[61] == true)
fire("ACTION_RANGE_CHECK_UPDATE", 1, false, true)
wv.out = b1.art.hotkey.color and b1.art.hotkey.color[1] == 1 and b1.art.hotkey.color[2] < 0.2
fire("ACTION_RANGE_CHECK_UPDATE", 1, true, true)
check("out of range from the game's event: the key red; back in range: grey again",
    wv.out and b1.art.hotkey.color[1] == 0.6)
fire("ACTION_USABLE_CHANGED", { { slot = 1, usable = false, noMana = true } })
wv.blue = b1.art.icon.vertex and b1.art.icon.vertex[3] == 1 and b1.art.icon.vertex[1] == 0.5
fire("ACTION_USABLE_CHANGED", { { slot = 1, usable = true, noMana = false } })
check("usable from the game's event: blue without the mana, white again", wv.blue and b1.art.icon.vertex[1] == 1)
check("keys: Blizzard's bindings onto ours", overrides.Q and overrides.Q.name == "SpheresBar1Button5"
    and overrides["SHIFT-1"] and overrides["SHIFT-1"].name == "SpheresBar2Button1")
press("Q")
check("Q uses Bar 1's slot 5", used[#used] == 5)
PAGE.bonus = true -- a warrior in Battle Stance: Bar 1 shows page 7
fire("UPDATE_BONUS_ACTIONBAR")
stateChanged() -- the game's state drivers
press("Q")
check("a bonus bar: the game's own page, and ours shows it", used[#used] == 77 and b5.action == 77)
-- 0.5.479, the player's: "in bear form, my primary action bar looks empty but when say hit 3, it casts human
-- form spell": the game pages row 1 (an attribute driver on its strip), the keys and the look both read it
do
local strip1 = SpheresBar1
check("row 1's page from the game: an attribute driver on its strip (forms, stances, vehicles, override bars), its buttons taking it",
    strip1.attrs.actionpage == "7" and b5.attrs["useparent-actionpage"] == true)
PAGE.bonusIndex = 9 -- bear form: bonus bar 3
stateChanged()
press("1")
check("bear form: key 1 casts what button 1 shows (page 9), not your own form's", used[#used] == 97
    and SpheresBar1Button1.action == 97 and strip1.attrs.actionpage == "9")
PAGE.bonusIndex = 7
PAGE.bonus = false
fire("UPDATE_BONUS_ACTIONBAR")
stateChanged()
press("1")
check("your own form again: page 1", used[#used] == 1 and SpheresBar1Button1.action == 1 and strip1.attrs.actionpage == "1")
end
check("vehicles: Blizzard's own bar takes over, ours hide", drivers[B.Holder()] and drivers[B.Holder()]:find("vehicleui", 1, true))
check("Blizzard's bars, menu, bags and experience bar out of sight", MainActionBar.parent ~= UIParent and MultiBarBottomLeft.parent ~= UIParent
    and MicroMenuContainer.parent ~= UIParent and BagsBar.parent ~= UIParent
    and MainStatusTrackingBarContainer.parent ~= StatusTrackingBarManager and PetActionBar.parent ~= UIParent
    and B.Stowed() == 12)
local hx, hy = B.Holder():GetCenter()
check("thirteen positions per row, 31.36 px buttons 3 apart, 7.5 units above the frame bottom", near(hx, 960)
    and near(B.Holder().w, 13 * 31.36 + 12 * 3) and near(b1.w, 31.36)
    and near(hy, 7.5 + (2 * 31.36 + 3.5) / 2) and near(SpheresBar2Button2.points[1][4], 34.36)
    and B.Holder().points[1][2] == S.FrameAnchor())
check("Bag and the extra action align in the last column", near(select(1, B.BagAnchor():GetCenter()), select(1, SpheresBar2Button13:GetCenter()))
    and near(select(2, B.BagAnchor():GetCenter()) - select(2, SpheresBar2Button13:GetCenter()), 34.86))
check("the orbs' glass clear of the rows", lx + BALL / 2 < 960 - B.Holder().w / 2 and rx - BALL / 2 > 960 + B.Holder().w / 2)
local K = ns.Track
local xpBar = K.Bar("xp")
local function slotAt(bar, y, w, h)
    local p = bar.points[#bar.points]
    return bar.shown and p[1] == "CENTER" and p[2] == S.FrameAnchor() and p[3] == "BOTTOM"
        and near(p[5], y) and near(bar.w, w) and near(bar.h, h)
end
check("leveling: Roth's frame with one slot, your experience in it", art.frame.texture == MEDIA .. "Frame1" and S.Slots() == 1
    and slotAt(xpBar, 80.5, 450, 9) and not K.Bar("rep").shown)
check("compact frame: lower row raised, upper row fixed and clear of tracking slot", near(B.Holder():GetBottom(), 7.5)
    and near(B.Buttons(1)[1]:GetBottom(), 42.36)
    and xpBar:GetBottom() > B.Holder():GetTop() + 2)
check("under the frame (only its slot shows it)", xpBar.strata == "LOW" and art.strata ~= "LOW")
check("rested: blue, and how far your rest reaches dimmer behind", xpBar.main.value == 450 and xpBar.main.max == 1000
    and xpBar.main.color[3] == 1 and xpBar.rest.shown and xpBar.rest.value == 1
    and xpBar.restTick.shown and xpBar.rest.level < xpBar.main.level)
XPS.rested = nil
fire("UPDATE_EXHAUSTION")
check("not rested: purple", xpBar.main.color[1] == 0.78 and not xpBar.rest.shown)
fireScript(xpBar, "OnEnter")
check("hovered: the numbers", tipText():find("450 / 1000", 1, true) ~= nil)
fireScript(xpBar, "OnLeave")
REP.data = { name = "Undercity", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4500 }
fire("UPDATE_FACTION")
check("a faction watched: the frame with two slots, experience below, reputation above", art.frame.texture == MEDIA .. "Frame2"
    and slotAt(xpBar, 80.3, 436, 9) and slotAt(K.Bar("rep"), 89.4, 436, 7))
check("its standing's colour, how far into it", K.Bar("rep").main.value == 1500 and K.Bar("rep").main.max == 6000
    and K.Bar("rep").main.color[2] == 0.6)
local topY = select(5, S.TopAnchor():GetPoint(1))
check("the frame's top higher with it", topY == 128.2)
XPS.level = 60
fire("PLAYER_LEVEL_UP")
check("the top level: the reputation alone in one slot", art.frame.texture == MEDIA .. "Frame1" and not xpBar.shown
    and slotAt(K.Bar("rep"), 80.5, 450, 9))
REP.data = nil
fire("UPDATE_FACTION")
check("nothing to show: the frame without slots", art.frame.texture == MEDIA .. "Frame0" and not K.Bar("rep").shown
    and select(5, S.TopAnchor():GetPoint(1)) == 114.4)
XPS.level, XPS.rested = 20, 200
fire("PLAYER_LEVEL_UP")
check("leveling again: one slot", S.Slots() == 1 and xpBar.shown and select(5, S.TopAnchor():GetPoint(1)) == 120.9)
-- leveling up as the game does it: PLAYER_LEVEL_UP carries the new level while UnitLevel still
-- answers the old one; UNIT_LEVEL follows once it has caught up
fire("PLAYER_LEVEL_UP", 21)
check("leveling up: the level well shows the new level at once (UnitLevel lags behind the event)",
    tostring(L.levelText.text) == "21")
fire("PLAYER_UPDATE_RESTING") -- a refresh before the game's level catches up
SURF.heldLevel = tostring(L.levelText.text) == "21"
XPS.level = 21
fire("UNIT_LEVEL", "player")
check("and keeps it through a refresh, and when the game's own level catches up", SURF.heldLevel
    and tostring(L.levelText.text) == "21")
XPS.level = 20
fire("PLAYER_LEVEL_UP", 20)
-- your pet's buttons: ours, centred over the frame (Blizzard's moved in combat: "in combat, the pet
-- controls go in a different position")
SURF.petAt = SpheresPetBar.points[#SpheresPetBar.points]
check("your pet's buttons: ten of our own, centred on the frame's top edge", SpheresPetBar and SpheresPetButton10
    and SURF.petAt[1] == "BOTTOM" and SURF.petAt[2] == S.TopAnchor() and SURF.petAt[3] == "TOP" and SURF.petAt[4] == 0
    and select(1, S.TopAnchor():GetPoint(1)) == "BOTTOM" and select(4, S.TopAnchor():GetPoint(1)) == 0
    and near(SpheresPetBar.w, 10 * 26 + 9 * 3) and SpheresPetButton10.points[1][4] == 9 * 29)
check("secure: a click casts the slot (type pet), right-click goes to Blizzard's own button for it (autocast)",
    SpheresPetButton4.template == "SecureActionButtonTemplate" and SpheresPetButton4.attrs.type == "pet"
    and SpheresPetButton4.attrs.action == 4 and SpheresPetButton4.attrs.type2 == "click"
    and SpheresPetButton4.attrs.clickbutton2 == PetActionBar.actionButtons[4])
check("Blizzard's pet bar out of sight (Edit Mode may move it, nobody sees it)",
    PetActionBar:GetParent() ~= UIParent and not PetActionBar:GetParent().shown)
check("shown with a pet (a state driver: in combat too)", drivers[SpheresPetBar]:find("[pet] show", 1, true) and SpheresPetBar.shown)
combat = true
SURF.blockedBefore = #blocked
insideSecure = true -- Edit Mode re-stacks the bottom bars in combat (a bar shows or hides)
PetActionBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 600, 300)
insideSecure = false
PET.exists = false
stateChanged()
SURF.petGone = not SpheresPetBar.shown
PET.exists = true
stateChanged()
fire("UNIT_PET", "player")
check("in combat: Blizzard's moving its own bar leaves ours where it is; a pet gone and back hides and shows it",
    SpheresPetBar.points[#SpheresPetBar.points] == SURF.petAt and SURF.petGone and SpheresPetBar.shown and #blocked == SURF.blockedBefore)
SURF.art = function(i) return _G["SpheresPetButton" .. i].art end
check("Blizzard's look: Attack's icon, checked at half strength while attacking (as Blizzard's)",
    SURF.art(1).icon.texture == PET_ATTACK_TEXTURE and SURF.art(1).checked.shown and SURF.art(1).checked.alpha == 0.5)
check("Bite: autocast on (Blizzard's ants), its cooldown, its key red out of range",
    SpheresPetButton4.autocast and SpheresPetButton4.autocast.shown and SURF.art(4).hotkey.text == "ALT-4"
    and SURF.art(4).cooldown.cooldown and SURF.art(4).cooldown.cooldown.start == 100 and SURF.art(4).hotkey.color[1] == 1)
check("Growl not usable now: grey; an empty slot: the empty frame",
    SURF.art(5).icon.vertex[1] == 0.4 and not SURF.art(6).icon.shown and SURF.art(6).empty.shown
    and not SpheresPetButton6.autocast.shown)
SURF.cast = #PET.cast
click(SpheresPetButton4, "LeftButton")
SURF.castOk = PET.cast[#PET.cast] == 4 and #PET.cast == SURF.cast + 1
combat = true
click(SpheresPetButton4, "RightButton")
combat = false
check("click: Bite cast; right-click in combat: its autocast off, the ants still on and not turning",
    SURF.castOk and PET.acts[4].auto == false and SpheresPetButton4.autocast.shown
    and SpheresPetButton4.autocast.enabled == false and #blocked == SURF.blockedBefore)
click(SpheresPetButton4, "RightButton")
SURF.cast = #PET.cast
check("its key (Blizzard's pet slot binding) clicks ours", overrides["ALT-4"] and overrides["ALT-4"].name == "SpheresPetButton4"
    and press("ALT-4") and PET.cast[#PET.cast] == 4 and #PET.cast == SURF.cast + 1)
pickupMod = true
fireScript(SpheresPetButton5, "OnDragStart")
pickupMod = false
PET.cursor = 5
fireScript(SpheresPetButton2, "OnReceiveDrag")
PET.cursor = nil
check("drag to rearrange (shift with the bars locked, as Blizzard's)", PET.picked[1] == 5 and PET.picked[2] == 2)
fireScript(SpheresPetButton4, "OnEnter")
SURF.tip = tipText()
fireScript(SpheresPetButton4, "OnLeave")
check("its tooltip: the pet's spell", SURF.tip == "pet Bite")
-- your buffs and debuffs above the action bars, centred, then your cast bar, then Blizzard's box
PET.exists = false -- no pet: nothing between them and the frame
stateChanged()
local cb = PlayerCastingBarFrame
cb.w, cb.h = 200, 12
ns.Apply()
local function shown(f)
    local l, r, b, t
    for _, btn in ipairs(f.auraFrames) do
        if btn.shown then
            local x, y = btn:GetLeft(), btn:GetBottom()
            l, r = math.min(l or x, x), math.max(r or x + btn.w, x + btn.w)
            b, t = math.min(b or y, y), math.max(t or y + btn.h, y + btn.h)
        end
    end
    return l, r, b, t
end
local artTop = S.ArtTop()
local bl, br, bb, bt = shown(BuffFrame)
local dl, dr, db_, dt = shown(DebuffFrame)
check("buffs centred over the action bars (on the icons they show, not Blizzard's full-row frame)",
    near((bl + br) / 2, 960) and near(bb, artTop + 4) and near(br - bl, 3 * 35 - 5))
check("debuffs centred over them", near((dl + dr) / 2, 960) and near(db_, bt + 4))
check("their collapse arrows out of sight (they'd stand off at the frames' far ends)",
    BuffFrame.CollapseAndExpandButton.alpha == 0 and not BuffFrame.CollapseAndExpandButton.mouse)
local function castBottom() return select(5, cb:GetPoint(#cb.points)) end
check("your cast bar over your debuffs", cb.points[#cb.points][2] == UIParent and near(castBottom(), dt + 6))
check("Blizzard's bottom box (extra ability buttons, alternate power) over your cast bar",
    near(select(5, bottomBox:GetPoint(#bottomBox.points)), castBottom() + 12 + 4))
cb:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120) -- Blizzard places it when a cast starts
check("Blizzard placing it again: back over your debuffs", near(castBottom(), dt + 6))
combat = true
BuffFrame.n = 14 -- a raid's worth of buffs, in combat
BuffFrame:UpdateGridLayout()
bl, br, bb, bt = shown(BuffFrame)
dl, dr, db_, dt = shown(DebuffFrame)
check("buffs gained in combat: two rows, still centred, the debuffs and cast bar up over them", near((bl + br) / 2, 960)
    and near(bb, artTop + 4) and near(bt - bb, 65) and near(db_, bt + 4) and near(castBottom(), dt + 6) and #blocked == 0)
cb:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120) -- a cast starts in combat
check("Blizzard placing the cast bar in combat: ours again (it isn't protected)", near(castBottom(), dt + 6))
combat = false
fire("PLAYER_REGEN_ENABLED")
BuffFrame.n = 3
BuffFrame:UpdateGridLayout()
PET.exists = true -- a pet: its buttons over the frame
stateChanged()
bl, br, bb, bt = shown(BuffFrame)
check("a pet: its buttons over the frame, your buffs over them", near(bb, SpheresPetBar:GetTop() + 4)
    and SpheresPetBar:GetTop() > artTop)
PET.exists = false
stateChanged()
bl, br, bb, bt = shown(BuffFrame)
check("no pet: down again", near(bb, artTop + 4))
PET.exists = true
stateChanged()
local kl, kr, kb, kt = ns.Auras.KeepOut()
local ringOut = true
for _, o in ipairs(R.List()) do
    for _, s in ipairs(o.slots or {}) do
        local x, y = s:GetCenter()
        if s.shown and x and ns.Auras.Blocks(x, y, 30) then ringOut = false end
    end
end
check("the rings' slots keep out of the stack's column", kl and kr - kl > 400 and ringOut)
SURF.ringsOut = function()
    for _, o in ipairs(R.List()) do
        for _, sl in ipairs(o.slots or {}) do
            local x, y = sl:GetCenter()
            if sl.shown and x and ns.Auras.Blocks(x, y, 30) then return false end
        end
    end
    return true
end
PET.exists = false -- the rings round a short column, then a pet called in a fight
stateChanged()
R.Layout()
SURF.blockedBefore = #blocked
combat = true
PET.exists = true
stateChanged()
SURF.waitedRings = #blocked == SURF.blockedBefore
combat = false
fire("PLAYER_REGEN_ENABLED")
check("a pet's buttons coming in a fight: the rings move out of the taller column after it", SURF.waitedRings
    and SURF.ringsOut())
AURA_HOME[BuffFrame].inDefault = false -- moved in Edit Mode
BuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -600, -200)
ns.Apply()
check("buffs the player moved in Edit Mode stay where they are", BuffFrame.points[#BuffFrame.points][4] == -600)
AURA_HOME[BuffFrame].inDefault = true
ns.Apply()
-- a narrow screen: it all shrinks to fit
UIParent.w = 800
ns.Apply()
check("a narrow screen: smaller, to fit", SpheresHUD.scale < 1 and SpheresHUD.w * SpheresHUD.scale <= 792 + 0.01)
do
    local fits = true
    for _, button in ipairs(R.Get("menu").slots) do
        if button.shown then
            local x, y = button:GetCenter()
            if x - button.w / 2 < 0 or x + button.w / 2 > UIParent.w
                    or y - button.h / 2 < S.ArtTop() + 4 or y + button.h / 2 > UIParent.h then
                fits = false
            end
        end
    end
    check("larger menu buttons remain on screen at narrow width", fits)
end
do
    local allClear = true
    for _, button in ipairs(R.Get("bags").slots) do
        if button.shown then
            local x, y = button:GetCenter()
            if x - button.w / 2 < 0 or x + button.w / 2 > UIParent.w
                    or y - button.h / 2 < S.ArtTop() + 4 or ns.Auras.Blocks(x, y, button.w + 16) then
                allClear = false
            end
            for _, other in ipairs(R.List()) do
                if other ~= R.Get("bags") and other:Config().shown and other.hub.shown then
                    local ox, oy = other.hub:GetCenter()
                    local clear = (button.w + other.hub.w) / 2 + 10
                    if ox and math.abs(x - ox) < clear and math.abs(y - oy) < clear then allClear = false end
                end
            end
        end
    end
    check("Bag arc clears the stack and screen edge on a narrow screen", allClear)
end
UIParent.w = 1920
ns.Apply()
check("a wide one: as asked", SpheresHUD.scale == 1 and SpheresHUD.w == 966)
do
    local brassFrame = art.frame.texture
    ns.db.statueFinish = "none"
    ns.Apply()
    check("None: statues hidden, narrow HUD, charcoal frame",
        not art.statueL.shown and not art.statueR.shown and SpheresHUD.w == 848
        and art.frame.texture == brassFrame .. "Charcoal")
    ns.db.statueFinish = "charcoal"
    ns.Apply()
    check("Charcoal: statues shown with matching frame ends",
        art.statueL.shown and art.statueR.shown and SpheresHUD.w == 966
        and art.statueL.texture == MEDIA .. "StatueLeftCharcoal"
        and art.statueR.texture == MEDIA .. "StatueRightCharcoal"
        and art.frame.texture == brassFrame .. "Charcoal")
    ns.db.statueFinish = "brass"
    ns.Apply()
    check("Brass: statues and frame ends restored", art.statueL.shown and art.statueR.shown
        and art.statueL.texture == MEDIA .. "StatueLeft" and art.frame.texture == brassFrame)
end

-------------------------------------------------------------------------------
-- 5) rings docked round the spheres: Bar 3 over the left one, the menu and the bags over the right
-------------------------------------------------------------------------------
local hub3, ring3 = SpheresBar3Hub, SpheresBar3Ring
local function dockedAt(hub, side, angle)
    local cx, cy = (side == "left" and SpheresLeft or SpheresRight):GetCenter()
    local x, y = hub:GetCenter()
    local r = BALL / 2 + hub.w / 2 - 8 -- a button over the ball's rim
    return near(x, cx + r * math.cos(math.rad(angle)), 0.5) and near(y, cy + r * math.sin(math.rad(angle)), 0.5)
end
local function overFrame(hub) local _, y = hub:GetCenter(); return y - hub.w / 2 >= S.ArtTop() end
-- the HUD at 1.2 (0.5.434): every docked hub at its scale, still over its sphere's rim; its fan not
do
    SpheresHUD.effScale, SpheresLeft.effScale, SpheresRight.effScale = 1.2, 1.2, 1.2
    ns.Apply()
    local ok, n = true, 0
    for _, o in ipairs(R.List()) do
        if o.docked and o.def.kind ~= "bags" and o.hub.shown then
            n = n + 1
            local p = o.hub.points[#o.hub.points]
            local x, y = p[4] * o.hub.scale, p[5] * o.hub.scale -- its points are in its own units
            local cx, cy, r = S.Geometry(o:Dock())
            local want = o.def.kind == "menu" and { S.SocketPosition("right") }
                or { cx + r * math.cos(math.rad(select(2, o:Dock()))), cy + r * math.sin(math.rad(select(2, o:Dock()))) }
            if not (o.hub.scale == 1.2 and near(o.ring.scale, 1 / 1.2) and near(x, want[1]) and near(y, want[2])) then
                ok = false
            end
        end
    end
    check("the HUD at 1.2: every docked hub (" .. n .. ") at 1.2, where it docks; its fan at UIParent's size",
        ok and n >= 3)
    SpheresHUD.effScale, SpheresLeft.effScale, SpheresRight.effScale = nil, nil, nil
    ns.Apply()
    check("and back at 1", hub3.scale == 1 and R.Get("bar3").ring.scale == 1)
end
check("Bar 3's ring over the left sphere, above the frame", hub3.shown and dockedAt(hub3, "left", 92) and overFrame(hub3))
local menuX, menuY = S.SocketPosition("right")
local hubMenuX, hubMenuY = SpheresMenuHub:GetCenter()
check("game menu in its engraved well, Bag in the upper action row", SpheresMenuHub.shown
    and near(hubMenuX, menuX) and near(hubMenuY, menuY)
    and SpheresBagsHub.shown and SpheresBagsHub.art.shown and not SpheresBagsHub.mini.shown
    and near(select(1, SpheresBagsHub:GetCenter()), select(1, B.BagAnchor():GetCenter()))
    and near(select(2, SpheresBagsHub:GetCenter()), select(2, B.BagAnchor():GetCenter())))
check("Bag shows and uses the game's backpack key", SpheresBagsHub.art.hotkey.text == "B"
    and overrides.B and overrides.B.name == "SpheresBagsHub" and overrides.B.button == "RightButton")
press("B")
check("the backpack key opens the backpack directly", MainMenuBarBackpackButton.clicked == 1
    and not SpheresBagsRing.shown)
press("B")
check("the backpack key continues to open the backpack directly", MainMenuBarBackpackButton.clicked == 2
    and not SpheresBagsRing.shown)
SURF.hasSpellFans = R.HasSpellFans
R.HasSpellFans = function() return false end -- binding refresh also works for a Warrior
KEYBINDS.TOGGLEBACKPACK = "V"
fire("UPDATE_BINDINGS")
check("Bag follows a changed backpack key", SpheresBagsHub.art.hotkey.text == "V"
    and overrides.V and overrides.V.name == "SpheresBagsHub" and overrides.V.button == "RightButton" and not overrides.B)
KEYBINDS.TOGGLEBACKPACK = "B"
fire("UPDATE_BINDINGS")
R.HasSpellFans = SURF.hasSpellFans
check("Bag returns to B when the backpack key does", SpheresBagsHub.art.hotkey.text == "B"
    and overrides.B and overrides.B.button == "RightButton" and not overrides.V)
-- a usable event while the menu ring is closed: its hub alone, no atlas asked again
SpheresMenuRing:Hide()
wv.asked, wv.slotText = ATLASES.asked, SpheresMenuSlot1 and SpheresMenuSlot1.art.hotkey.text
if SpheresMenuSlot1 then SpheresMenuSlot1.art.hotkey.text = "untouched" end
fire("SPELL_UPDATE_USABLE")
check("a closed ring's slots aren't painted on every usable event; atlases asked once a name",
    ATLASES.asked == wv.asked and (not SpheresMenuSlot1 or SpheresMenuSlot1.art.hotkey.text == "untouched"))
if SpheresMenuSlot1 then SpheresMenuSlot1.art.hotkey.text = wv.slotText end
check("the menu hub shows the original Game Menu question mark in the well, no square backing",
    not SpheresMenuHub.mini.bg.shown and SpheresMenuHub.mini.icon.atlas == "UI-HUD-MicroMenu-GameMenu-Up"
    and SpheresMenuHub.mini.icon.h == 22 and near(SpheresMenuHub.mini.icon.w, 22 * 0.8)
    and SpheresMenuHub.mini.icon.blend == "BLEND")
fireScript(SpheresMenuHub, "OnEnter")
wv.hovered = SpheresMenuHub.mini.hover.shown and SpheresMenuHub.mini.hover.atlas == "UI-HUD-MicroMenu-GameMenu-Mouseover"
    and SpheresMenuHub.mini.hover.blend == "BLEND" and SpheresMenuHub.mini.icon.alpha == 0
fireScript(SpheresMenuHub, "OnLeave")
check("hovered, the question mark lights up as on Blizzard's button, no blue glow",
    wv.hovered and not SpheresMenuHub.mini.hover.shown and SpheresMenuHub.mini.icon.alpha == 1)
do
    local border = SpheresMenuHub.mini.border
    check("menu latency ring starts green round the hub, the level well's ring's size",
        border.shown and border.w == 26 and border.w == S.Get("left").levelRing.w
        and border.blend == "BLEND" and border.alpha == 0.28
        and border.texture == "Interface\\AddOns\\Spheres\\Media\\MenuLatencyRing"
        and border.points[1][1] == "CENTER" and border.vertex[1] == 0 and border.vertex[2] == 1)
    NET_STATS.world = 400
    fireScript(SpheresMenuHub, "OnUpdate", 1)
    check("menu latency ring follows yellow latency", border.vertex[1] == 1 and border.vertex[2] == 1
        and border.vertex[3] == 0)
    NET_STATS.home = 650
    fireScript(SpheresMenuHub, "OnUpdate", 1)
    check("menu latency ring follows red latency", border.vertex[1] == 1 and border.vertex[2] == 0
        and border.vertex[3] == 0)
    NET_STATS.home, NET_STATS.world = 45, 61
    fireScript(SpheresMenuHub, "OnUpdate", 1)
end
fireScript(SpheresMenuHub, "OnEnter")
check("menu hub uses Blizzard's game menu tooltip", GameTooltip.owner == SpheresMenuHub
    and tipText():find(MainMenuMicroButton.tooltipText, 1, true)
    and tipText():find("Latency: 45 / 61", 1, true))
-- the gear: a click opens the fan, in combat too; it never passes a click on to Blizzard's game
-- menu button (which acts only with the mouse over it: Ring.lua R.NATIVE)
for _, inFight in ipairs({ false, true }) do
    combat = inFight
    local before, fight = MainMenuMicroButton.clicked or 0, inFight and ", in combat" or ""
    click(SpheresMenuHub, "LeftButton")
    check("a click on the gear opens the Game Menu fan" .. fight, SpheresMenuRing.shown)
    click(SpheresMenuHub, "RightButton")
    check("a right-click closes it and passes nothing on" .. fight, not SpheresMenuRing.shown
        and (MainMenuMicroButton.clicked or 0) == before and SpheresMenuHub.attrs.type2 == nil)
end
combat = false
check("a docked hub looks like a minimap button", hub3.mini.shown and not hub3.art.shown)
check("Bar 3's hub shows its first filled slot", hub3.mini.icon.texture == ACTIONS[49].texture and hub3.attrs.action2 == 49)
click(hub3, "LeftButton")
check("a click opens it", ring3.shown and bindings.ESCAPE and bindings.ESCAPE.name == "SpheresBar3Hub")
local allOn = true
for i = 1, 2 do
    local s = _G["SpheresBar3Slot" .. i]
    local x, y = s:GetCenter()
    if not (x and y and x > 0 and x < 1920 and y > 0 and y < 1080) then allOn = false end
end
check("its slots round the sphere, on the screen", allOn and _G["SpheresBar3Slot1"].dx ~= nil)
-- the arc: round the hub's angle, and clear of the frame
local ax, ay, above = 0, 0, true
for i = 1, 2 do
    local x, y = _G["SpheresBar3Slot" .. i]:GetCenter()
    ax, ay = ax + x / 2, ay + y / 2
    if y - 20 < S.ArtTop() + 4 then above = false end
end
local arc = math.deg(math.atan2(ay - ly, ax - lx)) % 360
check("and up by the hub, above the frame", arc > 60 and arc < 100 and above)
click(SpheresBar3Slot2)
check("a slot fires, the ring folds back", used[#used] == 50 and not ring3.shown and hub3.attrs.action2 == 50)
check("the bags ring holds Blizzard's bag buttons", MainMenuBarBackpackButton.parent == SpheresBagsSlot1.art
    and CharacterBag3Slot.parent == SpheresBagsSlot5.art and KeyRingButton.parent == SpheresBagsSlot7.art and not SpheresBagsSlot6.shown)
check("Bag slots and native icons match the center row buttons", SpheresBagsSlot1.w == SpheresBar1Button1.w
    and SpheresBagsSlot1.h == SpheresBar1Button1.h
    and MainMenuBarBackpackButton.w == SpheresBar1Button1.w
    and MainMenuBarBackpackButton.icon.w == SpheresBar1Button1.w
    and MainMenuBarBackpackButton.icon.points[1][2] == MainMenuBarBackpackButton
    and near(MainMenuBarBackpackButton.normalAndPushedTextureWidth,
        SpheresBar1Button1.art.frame.w))
do
    local mx, my = SpheresRight:GetCenter()
    local bagArcClear, bagGap = true, true
    local previousX, previousY
    for _, button in ipairs(R.Get("bags").slots) do
        if button.shown then
            local x, y = button:GetCenter()
            local distance = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
            if not near(distance, R.Get("bags").radius, 1) or ns.Auras.Blocks(x, y, button.w + 16)
                    or y - button.h / 2 < S.ArtTop() + 4 then bagArcClear = false end
            for _, other in ipairs(R.List()) do
                if other ~= R.Get("bags") and other:Config().shown and other.hub.shown then
                    local ox, oy = other.hub:GetCenter()
                    local clear = (button.w + other.hub.w) / 2 + 10
                    if ox and math.abs(x - ox) < clear and math.abs(y - oy) < clear then bagArcClear = false end
                end
            end
            if previousX and math.sqrt((x - previousX) ^ 2 + (y - previousY) ^ 2) < button.w + 9 then bagGap = false end
            previousX, previousY = x, y
        end
    end
    check("Bag buttons curve around the map, outside the buff stack and ring hubs", bagArcClear
        and R.Get("bags").shape == "round the map" and R.Get("bags").radius > 140)
    check("Bag buttons have breathing room between them", bagGap)
end
do
    local bags, shown = R.Get("bags"), {}
    for _, button in ipairs(bags.slots) do if button.shown then shown[#shown + 1] = button end end
    local oldScale = bags.hub.effScale
    bags.hub.effScale = 1.5 -- GetCenter is in hub units; its children inherit this scale in the client
    bags:OrbitBags(shown, shown[1].w)
    local cx, cy = S.Geometry("right")
    local onSphere = true
    for _, button in ipairs(shown) do
        local hx, hy = bags.hub:GetCenter()
        local x, y = (hx + button.dx) * 1.5, (hy + button.dy) * 1.5
        onSphere = onSphere and near(math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2), bags.radius, 1)
    end
    check("Bag arc remains centred on the map when its hub is scaled", onSphere)
    bags.hub.effScale = oldScale
    bags:OrbitBags(shown, shown[1].w)
end
BagsBar:Layout(); CharacterBag0Slot:SetPoint("LEFT", BagsBar, "LEFT", 0, 0) -- Blizzard lays its bag bar out again
check("Blizzard placing a bag button: back in the ring", CharacterBag0Slot.parent == SpheresBagsSlot2.art
    and CharacterBag0Slot.points[#CharacterBag0Slot.points][2] ~= BagsBar)
click(SpheresBagsHub, "LeftButton")
click(CharacterBag1Slot)
check("a bag button opens its bag (Blizzard's click) and folds the ring", CharacterBag1Slot.opened == 1 and not SpheresBagsRing.shown)
combat = true
SURF.backpackClicks = MainMenuBarBackpackButton.clicked or 0
click(SpheresBagsHub, "RightButton")
check("the Bag button securely delegates to the backpack in combat",
    MainMenuBarBackpackButton.clicked == SURF.backpackClicks + 1)
combat = false
slash("bags")
check("hiding Bag restores Blizzard's button size and icon", MainMenuBarBackpackButton.parent == BagsBar
    and MainMenuBarBackpackButton.w == 45 and MainMenuBarBackpackButton.icon.w == 37
    and MainMenuBarBackpackButton.normalAndPushedTextureWidth == 46 and not overrides.B)
slash("bags")
check("showing Bag restores its backpack shortcut", overrides.B and SpheresBagsHub.art.hotkey.text == "B")
check("the game menu button in the menu ring", MainMenuMicroButton.parent == SpheresMenuSlot15.art)
check("the minimap header's calendar, tracking and add-on compartment in it too, on a minimap button's disc",
    GameTimeFrame.parent == SpheresMenuSlot10.art and tracking.parent == SpheresMenuSlot12.art
    and AddonCompartmentFrame.parent == SpheresMenuSlot13.art and SpheresMenuSlot10.art.mini.shown
    and GameTimeFrame.points[#GameTimeFrame.points][1] == "CENTER" and GameTimeFrame.w == 23
    and SpheresMenuSlot10.w == 36 and GameTimeFrame.scale == 1)
-- 0.5.432: tracking's and the compartment's bronze square cut off, the logo filling the disc
do
    local cut = SpheresMenuSlot12.cutMask
    local p1, p2 = cut and cut.points[1], cut and cut.points[2]
    check("tracking and add-ons: their art masked inside its bronze square, 1.25 times the size",
        cut and tracking.StateTexture.masks[1] == cut and tracking.AddTexture.masks[1] == cut
        and cut.texture == "Interface\\Buttons\\WHITE8X8"
        and p1[1] == "TOPLEFT" and p1[2] == tracking.StateTexture and p1[4] == 4 and p1[5] == -4.5
        and p2[1] == "BOTTOMRIGHT" and p2[4] == -4 and p2[5] == 4.5
        and AddonCompartmentFrame.StateTexture.masks[1] == SpheresMenuSlot13.cutMask
        and tracking.scale == 1.25 and AddonCompartmentFrame.scale == 1.25
        and #GameTimeFrame.masks == 0 and SpheresMenuSlot10.cutMask == nil)
end
for _, pair in ipairs({ { GameTimeFrame, SpheresMenuSlot10 }, { SpheresMenuSlot11.native, SpheresMenuSlot11 },
        { tracking, SpheresMenuSlot12 }, { AddonCompartmentFrame, SpheresMenuSlot13 } }) do
    local x, y = pair[1]:GetCenter()
    local sx, sy = pair[2]:GetCenter()
    check("native menu control stays centered in its disc", near(x, sx) and near(y, sy))
end
-- day or night (0.5.433): ours, after the calendar, on a disc as the add-ons button
do
    local slot = SpheresMenuSlot11
    local diel = slot.native
    check("day or night in the menu ring, after the calendar: the sun by day, a minimap button's icon on its disc",
        diel and diel.parent == slot.art and slot.shown and slot.w == 36 and slot.art.mini.shown
        and slot.art.mini.border.texture == "Interface\\AddOns\\Spheres\\Media\\HubFrame"
        and diel.icon.atlas == "UI-HUD-Minimap-DayCycle" and #diel.icon.masks == 1
        and near(diel.w, 22.5 * 36 / 31) and diel.points[#diel.points][1] == "CENTER"
        and slot.art.mini.hover.alpha == 0 and diel.mouse == true)
    check("nothing to click: no secure wrap on it", #(diel.wraps or {}) == 0 and next(diel.wraps or {}) == nil)
    diel.scripts.OnEvent(diel, "DIEL_CYCLE_CHANGED", false)
    check("night falls (the game's event): the moon", diel.icon.atlas == "UI-HUD-Minimap-NightCycle" and diel.shown)
    C_DateAndTime.day = true
    diel.scripts.OnEvent(diel, "PLAYER_ENTERING_WORLD")
    check("entering the world: asked again, the sun", diel.icon.atlas == "UI-HUD-Minimap-DayCycle")
    diel.scripts.OnEnter(diel)
    check("hovered: the server's time", GameTooltip.owner == diel and tipText():find("Server time: 14:05", 1, true)
        and diel.scripts.OnUpdate ~= nil)
    GameTime_GetGameTime = function(ampm) return ampm and "2:05 PM" or "2:05", 14, 5 end
    GameTime_GetLocalTime = function(ampm) return ampm and "4:05 PM" or "4:05", 16, 5 end
    TIMEMANAGER_TOOLTIP_REALMTIME, TIMEMANAGER_TOOLTIP_LOCALTIME = "Realm time:", "Local time:"
    diel.scripts.OnUpdate(diel, 0.5)
    check("not again within the second", not tipText():find("PM", 1, true))
    diel.scripts.OnUpdate(diel, 0.6)
    check("each second: Blizzard's clock lines, in your 12 or 24 hour setting, realm (server) and local",
        tipText() == "Time|Realm time: 2:05 PM|Local time: 4:05 PM")
    GameTime_GetGameTime, GameTime_GetLocalTime, TIMEMANAGER_TOOLTIP_REALMTIME, TIMEMANAGER_TOOLTIP_LOCALTIME = nil, nil, nil, nil
    diel.scripts.OnLeave(diel)
    check("left: no tooltip, no ticking", not GameTooltip.shown and diel.scripts.OnUpdate == nil)
end
check("open menu buttons are larger and character hover fits the full frame",
    near(SpheresMenuSlot1.w, 36.8) and SpheresMenuSlot1.h == 46
    and near(MainMenuMicroButton.scale, 1.15)
    and SpheresMenuSlot1.art.hover.atlas == "UI-HUD-MicroMenu-ButtonBG-Up")
do
    local hotkey = SpheresMenuSlot1.art.hotkey
    local point = hotkey.points[1]
    check("menu keys sit inside the upper-right frame", point[1] == "TOPRIGHT"
        and near(point[2], -6 * SpheresMenuSlot1.w / 32)
        and near(point[3], -8 * SpheresMenuSlot1.h / 40))
end
click(SpheresMenuHub, "LeftButton")
click(GameTimeFrame)
check("the calendar opens (Blizzard's click) and the ring folds", GameTimeFrame.opened == 1 and not SpheresMenuRing.shown)
click(SpheresMenuHub, "LeftButton")
click(MainMenuMicroButton)
check("the game menu's own button: the ring folds too (Blizzard's buttons have no secure handle)",
    not SpheresMenuRing.shown)
combat = true
click(SpheresMenuHub, "LeftButton")
click(MainMenuMicroButton)
check("in combat the ring can't be folded from add-on code: it stays, nothing blocked", SpheresMenuRing.shown
    and #blocked == 0)
click(SpheresMenuHub, "LeftButton")
combat = false
click(SpheresMenuHub, "LeftButton")
click(tracking)
check("tracking: its menu opens, the ring stays (the menu closes with its button)", SpheresMenuRing.shown)
tracking:OnMenuClosed()
check("the menu closed: the ring folds", not SpheresMenuRing.shown and tracking.closed == 1)
slash("menu")
check("the menu ring hidden: the calendar back in the header, where it was", GameTimeFrame.parent == MinimapCluster
    and (GameTimeFrame.points[#GameTimeFrame.points] or {})[2] == MinimapCluster.ZoneTextButton
    and (GameTimeFrame.points[#GameTimeFrame.points] or {})[3] == "TOPRIGHT"
    and GameTimeFrame.scale == 1 and MainMenuMicroButton.scale == 1)
check("day or night: in its hidden frame while the ring is hidden", SpheresMenuSlot11.native.parent ~= SpheresMenuSlot11.art
    and SpheresMenuSlot11.native.parent.shown == false)
check("and tracking and add-ons framed again, at their size", tracking.parent == MinimapCluster.Tracking
    and #tracking.StateTexture.masks == 0 and #tracking.AddTexture.masks == 0
    and #AddonCompartmentFrame.StateTexture.masks == 0 and tracking.scale == 1 and AddonCompartmentFrame.scale == 1)
slash("menu")
check("shown again: in the ring again", GameTimeFrame.parent == SpheresMenuSlot10.art)
check("cut and scaled again, the mask once", #tracking.StateTexture.masks == 1 and tracking.scale == 1.25)
check("day or night: out of sight with the ring hidden, back in it shown", SpheresMenuSlot11.native.parent == SpheresMenuSlot11.art)
-- the Game Menu's ten buttons: all up over the frame, all on screen
local menuOk, menuN = true, 0
for i = 1, 11 do
    local b = _G["SpheresMenuSlot" .. i]
    if b.shown then
        menuN = menuN + 1
        local x, y = b:GetCenter()
        if not (y - 20 >= S.ArtTop() + 4 and x > 20 and x < 1900 and y < 1060) then menuOk = false end
    end
end
check("a big ring opens up over the frame, on screen (" .. menuN .. " buttons)", menuN >= 10 and menuOk)
-- dragging Bar 3's hub over to the right sphere, low on its right
local dock = R.Get("bar3")
lx, ly = SpheresLeft:GetCenter() -- style changes can move the complete orb assemblies
rx, ry = SpheresRight:GetCenter()
fireScript(hub3, "OnDragStart")
CURSOR[1], CURSOR[2] = rx + 100, ry - 60
for _, f in ipairs(frames) do if f.scripts.OnUpdate and f.ring == dock then f.scripts.OnUpdate(f, 0.1) end end
fireScript(hub3, "OnDragStop")
local side, angle = dock:Dock()
check("dragged: round the right sphere", side == "right" and near(angle, (math.deg(math.atan2(-60, 100))) % 360, 0.01)
    and dockedAt(hub3, "right", angle))
CURSOR[1], CURSOR[2] = lx, ly + 150
fireScript(hub3, "OnDragStart")
for _, f in ipairs(frames) do if f.scripts.OnUpdate and f.ring == dock then f.scripts.OnUpdate(f, 0.1) end end
fireScript(hub3, "OnDragStop")
side, angle = dock:Dock()
check("over the top of a sphere: docked there (all round)", side == "left" and near(angle, 90, 0.01))
slash("reset")
check("/spheres reset: back in its first place", dockedAt(hub3, "left", 92))

-------------------------------------------------------------------------------
-- 6) spell fans: Auras docked on the left collar; Seals over a slot (Action Ring's macro works)
-------------------------------------------------------------------------------
local auras, aurasHub = R.Get("auras"), SpheresAurasHub
check("the Auras fan over the left sphere, on the rows' side", aurasHub.shown and auras.docked and dockedAt(aurasHub, "left", 64)
    and overFrame(aurasHub))
check("its key from Key Bindings casts the pick", auras.keys[1] == "F" and aurasHub.attrs.type2 == "spell"
    and aurasHub.attrs.spell == "Devotion Aura")
check("Blizzard's aura buttons out of sight meanwhile", StanceBar.parent ~= UIParent and R.StanceBarHidden())
check("Seals: no macro on the rows yet, so not shown", not SpheresSealsHub.shown)
ACTIONS[62] = spell("Ring_Seals", { macro = "Ring: Seals" }) -- Action Ring's macro, in Bar 2's second slot (key E)
fire("ACTIONBAR_SLOT_CHANGED", 62)
local seals, sealHub = R.Get("seals"), SpheresSealsHub
check("Action Ring's Seals macro: the fan sits over that slot", sealHub.shown and seals.home and seals.home.button == SpheresBar2Button2
    and SpheresBar2Button2.alpha == 0)
check("and takes its key, over the row's own", overrides.E and overrides.E.name == "SpheresSealsHub" and overrides.E.button == "RightButton")
press("E")
check("E casts the pick", casts[#casts] == "Seal of Righteousness")
local fan = Spheres_FanFor("Seal of Light")
check("Encounter Coach can find a spell in it", fan and fan.fan == "seals" and fan.key == "E" and fan.openKey == "SHIFT-E" and not fan.current)
combat = true
check("not in combat: the fan's pick is secure", Spheres_SetFanPick("Seal of Light") == false)
combat = false
check("out of combat it changes the pick", Spheres_SetFanPick("Seal of Light") and sealHub.attrs.spell == "Seal of Light")
check("a one-shot is armed for one cast", Spheres_SetFanPick("Seal of the Crusader") and sealHub.attrs.spell == "Seal of the Crusader"
    and sealHub.attrs.revert == "Seal of Light")
combat = true
click(sealHub, "RightButton", true)
click(sealHub, "RightButton", false)
check("in combat: the Crusader once, then Light again", casts[#casts] == "Seal of the Crusader" and sealHub.attrs.spell == "Seal of Light")
combat = false
check("a fan's answer for a spell is one table, refreshed (Encounter Coach asks every tick)",
    Spheres_FanFor("Seal of Light") == fan and Spheres_FanFor("Retribution Aura") ~= fan)
local aurasFan = Spheres_FanFor("Retribution Aura")
check("a docked fan: its own key, opened with its ring binding", aurasFan and aurasFan.key == "F" and aurasFan.openKey == nil)
ns.db.rings.seals.collar = true
ns.Apply()
check("Seals by a sphere instead: the slot is a slot again", seals.docked and dockedAt(sealHub, "left", 120)
    and SpheresBar2Button2.alpha == 1 and not (overrides.E and overrides.E.name == "SpheresSealsHub"))
ns.db.rings.seals.collar = false
ns.Apply()
check("Spheres' own macro works too", R.PickupMacro("seals") and MACROS.made[1].name == "Spheres: Seals"
    and MACROS.made[1].body == "/click SpheresSealsHub RightButton")

-------------------------------------------------------------------------------
-- 7) combat: rings and rows work, anything that moves waits; nothing protected is touched
-------------------------------------------------------------------------------
combat = true
local before = #blocked
from = #printed
ns.db.scale = 1.1
ns.Apply()
check("in combat: changes wait", saidSince(from, "apply when combat ends") and SpheresHUD.scale == 1 and #blocked == before)
click(hub3, "LeftButton")
check("a ring opens in combat", ring3.shown)
click(SpheresBar3Slot1)
check("and fires", used[#used] == 49 and not ring3.shown)
HP.cur = 900
fire("UNIT_HEALTH", "player")
check("the sphere follows your health in combat", reveal(hb.value) == 900 and reveal(pb.value) == 300)
local topBefore = select(5, S.TopAnchor():GetPoint(1))
REP.data = { name = "Undercity", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4500 }
fire("UPDATE_FACTION")
check("a faction watched in combat: the bar shows, the frame's top (Blizzard's bars hang off it) waits",
    K.Bar("rep").shown and art.frame.texture == MEDIA .. "Frame2" and select(5, S.TopAnchor():GetPoint(1)) == topBefore)
combat = false
fire("PLAYER_REGEN_ENABLED")
check("after the fight: applied", SpheresHUD.scale == 1.1 and select(5, S.TopAnchor():GetPoint(1)) == 128.2)
REP.data = nil
fire("UPDATE_FACTION")
ns.db.scale = 1
ns.Apply()

-------------------------------------------------------------------------------
-- 8) the target card, top centre: portrait, level, name, health, power, Blizzard's cast bar
-------------------------------------------------------------------------------
local card = SpheresTarget
check("a secure unit button for the target: click targets, right-click Blizzard's menu", card and card.template == "SecureUnitButtonTemplate"
    and card.attrs.unit == "target" and card.attrs.type1 == "target" and card.attrs.type2 == "togglemenu")
check("shown only with a target (a unit watch, works in combat)", watched[card])
check("standing free: no plate, no border", card.metal == nil and card.edge == nil and card.shade == nil and card.face.ring)
check("its health and power bars bigger, under glass", card.health.w == 148 and card.health.h == 18 and card.power.h == 11
    and card.health.gloss.texture:find("BarGlossHealth", 1, true) and card.health.gloss.sublevel == 7
    and card.power.gloss.points[1][2] == card.power and card.power.gloss.texture:find("BarGlossPower", 1, true))
check("round-ended: fill and track drawn round at their size, a brass rim round them, no square border",
    card.health.fill.texture:find("BarFillHealth", 1, true) and card.health.barTexture == card.health.fill
    and card.health.bg.texture:find("BarShapeHealth", 1, true) and card.health.bg.vertex[4] == 0.75
    and card.health.rim.texture:find("BarRimHealth", 1, true) and card.health.rim.points[1][2] == -2.5
    and card.power.fill.texture:find("BarFillPower", 1, true) and card.health.edge == nil and #card.health.fill.masks == 0)
check("top centre, near the top (0.5.476: 220 down \"gets in the way\")", card.points[1][1] == "TOP" and card.points[1][3] == "TOP" and card.points[1][5] == -24)
check("Blizzard's breath bars under the card's cast bar (they stood over its name)", MirrorTimerContainer.points[#MirrorTimerContainer.points][2] == TargetFrameSpellBar
    and MirrorTimerContainer.points[#MirrorTimerContainer.points][3] == "BOTTOM")
MirrorTimerContainer:SetPoint("TOP", UIParent, "TOP", 0, -100) -- Edit Mode placing them again
check("Blizzard placing them again: back under the card", MirrorTimerContainer.points[#MirrorTimerContainer.points][2] == TargetFrameSpellBar)
check("Blizzard's target frame out of sight", TargetFrame.parent ~= UIParent and ns.Target.Hidden())
check("its cast bar under the card (under its auras)", TargetFrameSpellBar.parent == card
    and TargetFrameSpellBar.points[#TargetFrameSpellBar.points][2] == card.auras)
TargetFrameSpellBar:SetPoint("TOPLEFT", TargetFrame, "BOTTOMLEFT", 0, 0) -- Blizzard moves it under the target's auras
check("Blizzard moving the cast bar: back under the card", TargetFrameSpellBar.points[#TargetFrameSpellBar.points][2] == card.auras)
TGT.exists = true
fire("PLAYER_TARGET_CHANGED")
check("a target: its portrait, name and level (hidden values, drawn by the game)", card.face.portrait.portraitOf == "target"
    and issecretvalue(card.name.text) and reveal(card.name.text) == "Defias Pillager" and reveal(card.face.badge.number.text) == 15)
check("hostile: red; elite portrait ring and label", card.name.color[1] == 1 and card.name.color[2] == 0.2
    and card.kind.text == "Elite" and card.face.rankRing.atlas == "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold")
check("hostile health is deep red; mana is deep blue", card.health.color[1] == 0.78 and card.health.color[2] == 0.07
    and not card.health.tapped and card.power.color[3] == 0.82)
TGT.tapped = true -- someone else hits it first
fire("UNIT_FACTION", "target")
check("someone else got to it first: its health grey", card.health.color[1] == 0.5 and card.health.color[2] == 0.5
    and card.health.tapped)
TGT.tapped = false
fire("UNIT_FACTION", "target")
check("hostile health color returns after tap denial", card.health.color[2] == 0.07)
-- Target Style "Sphere" (0.5.468, experimental): a sphere as yours, the portrait in its very centre
;(function()
    SpheresDB.targetStyle = "sphere"
    ns.Apply()
    local s, face = card.sphere, card.face
    check("Target Style Sphere (experimental): a sphere as yours, the bars gone, the portrait in its very centre over its glass",
        s and s.shown and not card.health.shown and not card.power.shown and near(s.w, 206 * 0.75)
        and face.points[1][1] == "CENTER" and face.points[1][2] == s and face.points[1][4] == nil
        and near(face.w, BALL * 0.75 * 0.55) and face.level > s.health.glass.parent.level and face.level > s.over.level
        and face.badge.level > face.level
        and card.name.points[1][2] == s and card.auras.points[1][2] == card.kind)
    check("its liquids the target's hidden health and power, cut round the portrait's ball (TargetCavity, its ball's size)",
        issecretvalue(s.health.value) and reveal(s.health.value) == 400 and reveal(s.health.max) == 800
        and s.power.value ~= nil and s.holes[1].texture == MEDIA .. "TargetCavity" and near(s.holes[1].w, BALL * 0.75)
        and s.health.base.masks[1] == s.health.inside.hole and s.bowl.texture == MEDIA .. "PetBowl")
    check("its health red as yours (what it is to you: its name's colour, the gold ring as it is)",
        s.health.color[1] == 0.45 and s.health.color[2] < 0.05 and s.health.alpha == 1 and face.nature == nil)
    check("floating at the top: no shadow under it (no bottom shade, no liquid shade), its own glass with light round its rim",
        s.bottomShade == nil and s.health.surface.shade == nil and s.power.surface.shade == nil
        and s.health.glass.texture == MEDIA .. "GlassTargetHealth" and s.power.glass.texture == MEDIA .. "GlassTargetMana")
    local splitClip, wholeClip = s.splitLayer.parent, s.wholeLayer.parent
    check("split or whole, the game picks: its hidden maximum power out of 1 into a gate; the split sphere over its fill, the whole one over the rest",
        issecretvalue(s.gate.value) and s.gate.min == 0 and s.gate.max == 1 and splitClip.clips and wholeClip.clips
        and splitClip.points[1][2] == s.gate.barTexture and wholeClip.points[1][2] == s.gate.barTexture
        and wholeClip.points[1][3] == "TOPRIGHT" and wholeClip.points[2][2] == s.gate
        and s.health.parent == s.splitLayer and s.power.parent == s.splitLayer and s.whole.parent == s.wholeLayer
        and s.splitLayer.back.texture == MEDIA .. "OrbBack" and s.wholeLayer.back.texture == MEDIA .. "OrbBackWhole"
        and s.whole.glass.texture == MEDIA .. "GlassTargetWhole" and reveal(s.whole.value) == 400)
    TGT.powerMax = 0
    fire("UNIT_MAXPOWER", "target")
    check("no power: an empty gate (the whole sphere shows)", s.gate.value == 0)
    TGT.powerMax = nil
    fire("UNIT_MAXPOWER", "target")
    TGT.dead = true
    fire("UNIT_FACTION", "target")
    check("dead: its liquids gone", s.health.alpha == 0 and s.power.alpha == 0 and s.whole.alpha == 0)
    TGT.dead = false
    fire("UNIT_FACTION", "target")
    -- Target Style "Nameplate" (0.5.495, experimental): its card on the target's nameplate (the game moves it),
    -- Blizzard's plate for it invisible, the middle without a plate, a boss's at the top; the player's CVars back after
    local plate, follow = CreateFrame("Frame", nil, UIParent), ns.Target.Follow()
    C_NamePlate = { GetNamePlateForUnit = function(unit) if unit == "target" then return plate end end }
    plate.GetUnit = function() return "target" end
    C_NamePlate.GetNamePlates = function()
        return C_NamePlate.GetNamePlateForUnit("target") and { plate } or {}
    end
    CVARS.nameplateShowEnemies, CVARS.nameplateSelectedAlpha, CVARS.nameplateTargetRadialPosition = "1", "1", "0"
    TGT.class = "elite"
    SpheresDB.targetStyle = "nameplate"
    ns.Apply()
    fire("PLAYER_TARGET_CHANGED")
    check("Target Style Nameplate: a small card on the target's plate, the card at the top invisible and not clickable",
        follow.shown and follow.points[1][2] == plate and follow.points[1][1] == "CENTER" and card.alpha == 0 and card.mouse == false)
    check("its portrait at its left, in a circle in the gold ring, its name and bars at its right",
        follow.face.points[1][1] == "LEFT" and #follow.face.portrait.masks == 1 and follow.face.ring.shown ~= false
        and follow.name.points[1][2] == follow.face and follow.health.points[1][2] == follow.name)
    check("its bars the target's hidden health and power, as the card's",
        issecretvalue(follow.health.value) and reveal(follow.health.value) == 400 and reveal(follow.health.max) == 800
        and follow.health.color[1] == card.health.color[1] and follow.power.value ~= nil
        and reveal(follow.name.text) == reveal(card.name.text))
    check("Blizzard's plate for the target invisible, kept at the screen's edge toward it off camera (the player's saved)",
        CVARS.nameplateSelectedAlpha == "0" and CVARS.nameplateTargetRadialPosition == "1"
        and CVARS.nameplateTargetBehindMaxDistance == "30" and SpheresDB.target.cvars.nameplateSelectedAlpha == "1")
    do
        local default, hudTop, hudScale = GetCVarDefault, SpheresHUD.GetTop, SpheresHUD.GetEffectiveScale
        local uiHeight, uiScale, cardHeight = UIParent.GetHeight, UIParent.GetEffectiveScale, follow.GetHeight
        GetCVarDefault = function(name) if name == "nameplateBottomInset" then return "0.1" end end
        CVARS.nameplateBottomInset = "0.1"
        SpheresHUD.GetTop, SpheresHUD.GetEffectiveScale = function() return 300 end, function() return 1 end
        UIParent.GetHeight, UIParent.GetEffectiveScale = function() return 1000 end, function() return 1 end
        follow.GetHeight = function() error("nameplate dimensions are hidden") end
        ns.Target.Layout()
        check("nameplate boundary uses known card dimensions even when attached dimensions are hidden",
            near(tonumber(CVARS.nameplateBottomInset), 0.342))
        SpheresHUD.GetEffectiveScale = function() return 2 end
        ns.Target.Layout()
        check("nameplate clearance scales with the HUD, including its margin",
            near(tonumber(CVARS.nameplateBottomInset), 0.660))
        SpheresHUD.GetTop = function() return 350 end
        ns.Target.Layout()
        check("nameplate boundary follows the moved HUD",
            near(tonumber(CVARS.nameplateBottomInset), 0.760))
        SpheresDB.targetStyle = "card"
        ns.Target.Layout()
        check("leaving nameplate mode restores the original screen inset", CVARS.nameplateBottomInset == "0.1")
        GetCVarDefault, SpheresHUD.GetTop, SpheresHUD.GetEffectiveScale = default, hudTop, hudScale
        UIParent.GetHeight, UIParent.GetEffectiveScale, follow.GetHeight = uiHeight, uiScale, cardHeight
        CVARS.nameplateBottomInset = nil
        SpheresDB.targetStyle = "nameplate"
        ns.Target.Layout()
    end
    check("an elite: the card's dragon round its portrait too, turned over (its wing out to the left)",
        follow.face.rankRing.shown and follow.face.rankRing.atlas == card.face.rankRing.atlas and card.face.rankRing.atlas ~= nil)
    local opened
    UnitPopup_OpenMenu = function(which, data) opened = { which, data.unit, data.ownerFrame } end
    follow.face.scripts.OnClick(follow.face, "LeftButton")
    check("a click on its portrait: the target's menu (Blizzard's togglemenu's)", opened and opened[1] == "TARGET"
        and opened[2] == "target" and opened[3] == follow.face)
    UnitPopup_OpenMenu = nil
    fire("UNIT_AURA", "target")
    local fb, cb = follow.auras.buttons, card.auras.buttons
    check("its buffs and debuffs over its name, rows growing up, the card's own",
        #fb > 0 and fb[1].shown and fb[1].points[1][1] == "BOTTOMLEFT" and fb[1].points[1][2] == follow.auras
        and follow.auras.points[1][2] == follow.name and follow.auras.points[1][3] == "TOPLEFT"
        and fb[1].index == cb[1].index and fb[1].key == cb[1].key and #fb == #cb)
    C_NamePlate.GetNamePlateForUnit = function() return nil end
    fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    check("no plate (too far): the card in the screen's middle",
        follow.shown and follow.points[1][2] == UIParent and follow.points[1][3] == "CENTER" and follow.points[1][5] == 140)
    C_NamePlate.GetNamePlateForUnit = function(unit) if unit == "target" then return plate end end
    fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    TGT.dead = true -- it dies: the game takes its plate away
    C_NamePlate.GetNamePlateForUnit = function() return nil end
    fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    check("it dies: cleared from sight, its card and the card at the top gone", not follow.shown and card.alpha == 0)
    local unitIsUnit, cursor = UnitIsUnit, GetCursorPosition
    UnitIsUnit = function(a, b) return a == "mouseover" and b == "target" end -- the mouse over it
    GetCursorPosition = function() return 900, 500 end
    fire("GLOBAL_MOUSE_UP", "LeftButton")
    check("a click on its body: its card there, a little over the click (the corpse already targeted too)",
        follow.shown and follow.points[1][1] == "BOTTOM" and follow.points[1][2] == UIParent and follow.points[1][3] == "BOTTOMLEFT"
        and math.abs(follow.points[1][4] - 900 / follow:GetEffectiveScale()) < 0.01 and card.alpha == 0)
    UnitIsUnit = function() return false end -- Tab to it: the mouse elsewhere
    fire("PLAYER_TARGET_CHANGED")
    check("a corpse you Tab to: in the card at the top", not follow.shown and card.alpha == 1)
    UnitIsUnit, GetCursorPosition = unitIsUnit, cursor
    TGT.dead = false
    fire("PLAYER_TARGET_CHANGED")
    check("a new, living target: its card again (in the middle: no plate)", follow.shown and follow.points[1][2] == UIParent
        and card.alpha == 0)
    TGT.class = "worldboss"
    fire("UNIT_CLASSIFICATION_CHANGED", "target")
    check("a boss: the card at the top, nothing on its plate", not follow.shown and card.alpha == 1)
    TGT.class = "elite"
    TGT.reaction = 5
    fire("UNIT_FACTION", "target")
    check("a friend without a plate (friendly plates off): the card in the middle, as any target but a boss",
        follow.shown and follow.points[1][2] == UIParent and card.alpha == 0)
    TGT.reaction = 2
    fire("UNIT_FACTION", "target")
    C_NamePlate = nil
    SpheresDB.targetStyle = "card"
    ns.Apply()
    check("back to the card: the player's CVars back, the card seen and clickable, nothing on a plate",
        CVARS.nameplateSelectedAlpha == "1" and CVARS.nameplateTargetRadialPosition == "0" and SpheresDB.target.cvars == nil
        and card.alpha == 1 and card.mouse == true and not follow.shown)
    check("back to the card: the bars, the portrait on top, no sphere", not s.shown and card.health.shown and card.power.shown
        and face.points[1][1] == "TOP" and near(face.w, 74) and card.auras.points[1][2] == card.power)
end)()
local ab = card.auras.buttons
local function auraAt(b, col, row, inRow)
    local p = b.points[#b.points]
    local left = (card.auras.w - (inRow * 22 + (inRow - 1) * 3)) / 2
    return b.shown and p[2] == card.auras and near(p[4], left + col * 25) and near(p[5], -row * 25)
end
check("its auras under its bars: debuffs first, centred in their row", ab[1] and ab[2] and auraAt(ab[1], 0, 0, 2)
    and auraAt(ab[2], 1, 0, 2) and card.auras.points[1][2] == card.power)
check("an aura: its icon, its time from its duration object, its dispel colour", ab[1].icon.texture == 135959
    and ab[1].cd.cooldown and ab[1].cd.cooldown.kind == "duration" and ab[1].cd.cooldown.obj.durationOf == 11
    and ab[1].edge.colorTexture[3] == 1 and ab[1].count.text == "")
check("one whose details are hidden: its icon as it is, nothing handed back to the API", issecretvalue(ab[2].icon.texture)
    and ab[2].cd.cooldown == nil and ab[2].count.text == "" and ab[2].edge.colorTexture[1] == 0.8 and handedBack == 0)
check("buffs on a row of their own, with their stacks, a black edge", auraAt(ab[3], 0, 1, 1) and ab[3].count.text == "5"
    and ab[3].edge.colorTexture[1] == 0 and not (ab[4] and ab[4].shown))
fireScript(ab[3], "OnEnter")
check("hovered: the aura's tooltip", GameTooltip.owner == ab[3])
fireScript(ab[3], "OnLeave")
table.remove(TGT_AURAS["HARMFUL|INCLUDE_NAME_PLATE_ONLY"], 2)
fire("UNIT_AURA", "target")
check("an aura gone: one less (the game's event)", ab[1].shown and auraAt(ab[2], 0, 1, 1) and ab[2].count.text == "5"
    and not ab[3].shown)
check("its health, hidden, straight into the bar", issecretvalue(card.health.value) and reveal(card.health.value) == 400
    and reveal(card.health.max) == 800 and reveal(card.health.text.text) == 400)
TGT.hp = 100
fire("UNIT_HEALTH", "target")
check("its health falls with the game's event", reveal(card.health.value) == 100)
combat = true
TGT.hp = 50
fire("UNIT_HEALTH", "target")
check("in combat too", reveal(card.health.value) == 50)
combat = false
ns.db.targetCard = false
ns.Apply()
check("off: Blizzard's target frame and cast bar back, its breath bars in their place", TargetFrame.parent == UIParent and TargetFrameSpellBar.parent == TargetFrame
    and not watched[card] and not card.shown and MirrorTimerContainer.points[#MirrorTimerContainer.points][2] == UIParent
    and MirrorTimerContainer.points[#MirrorTimerContainer.points][5] == -100)
ns.db.targetCard = true
ns.Apply()

-------------------------------------------------------------------------------
-- 8b) Action Ring's chat and objectives list, carried over
-------------------------------------------------------------------------------
local cf = ChatFrame1
local stash = cf.buttonFrame.parent
check("the chat's buttons out of sight", stash ~= cf and not stash.shown and QuickJoinToastButton.parent == stash)
check("the input box only while typing: Blizzard's Classic chat style", CVARS.chatStyle == "classic")
CVARS.chatStyle = "im"
fire("VARIABLES_LOADED")
check("the game puts chatStyle back: ours again", CVARS.chatStyle == "classic")
check("no background tint, no Combat Log tab", not ChatFrame1Background.shown and chatCalls.closed == 1 and not ChatFrame2.isDocked)
check("the scroll bar on the left", cf.ScrollBar.points[1][1] == "TOPRIGHT" and cf.ScrollBar.points[1][3] == "TOPLEFT")
check("the tabs only while the mouse is over the chat", tabAlphas[ChatFrame1Tab][2] == 0 and ChatFrame1Tab.alpha == 0)
cf:AddMessage("|Hchannel:channel:1|h[1. General - Durotar]|h |Hplayer:Bob|h[Bob]|h: lfg")
check("channels as [1], still a link", cf.lines[1] == "|Hchannel:channel:1|h[1]|h |Hplayer:Bob|h[Bob]|h: lfg")
fire("PLAYER_ENTERING_WORLD", true, false) -- login, the tracker not loaded yet
ObjectiveTrackerFrame = tracker
fire("ADDON_LOADED", "Blizzard_ObjectiveTracker")
check("the objectives list folded when it loads", tracker.collapsed and tracker.sets == 1)
check("folded: an icon the size of a buff, its own fold button (no header bar or title)", fold.w == 27 and fold.h == 27
    and fold.normal.alpha == 0
    and tracker.Header.Background.alpha == 0 and tracker.Header.Text.alpha == 0)
local deco = {}
for _, k in ipairs(fold.kids or {}) do if k.kind == "FontString" then deco.count = k end end
check("the number of quests you follow in its corner", deco.count and deco.count.text == 3 and deco.count.shown)
tracker:SetCollapsed(false) -- its own button clicked (Blizzard's write)
check("open: as Blizzard has it, its bar and title back", fold.w == 18 and fold.h == 19 and not deco.count.shown
    and tracker.Header.Background.alpha == 1 and fold.normal.atlas == "ui-questtrackerbutton-collapse-all")
tracker:SetCollapsed(true)
check("folded again: the icon again", fold.w == 27 and tracker.Header.Text.alpha == 0)
questWatches = 5
fire("QUEST_WATCH_LIST_CHANGED")
check("following another quest: the number follows", deco.count.text == 5)
ns.db.objectivesIcon = false
ns.Apply()
check("the setting off: Blizzard's folded bar", fold.w == 18 and tracker.Header.Text.alpha == 1)
ns.db.objectivesIcon = true
ns.Apply()
tracker.collapsed = false
fire("PLAYER_ENTERING_WORLD", false, false) -- a loading screen
check("a loading screen leaves it open", not tracker.collapsed)
fire("PLAYER_ENTERING_WORLD", false, true) -- /reload
check("/reload folds it again", tracker.collapsed)
from = #printed
slash("debug")
function wv.reported(text) -- in /spheres debug's window
    local w = ns.DebugWindow()
    return w ~= nil and w.shown and type(w.box.text) == "string" and w.box.text:find(text, 1, true) ~= nil
end
check("/spheres debug says how the chat and the objectives are", wv.reported("chat: buttons hidden, input box while typing")
    and wv.reported("objectives: folded at login, folded now"))
check("and what Spheres costs, from the game's profiler", wv.reported(
    "cost: 0.080 ms a frame lately (all add-ons 0.600, the whole frame 7.20), peak 3.40 ms, frames over 1 ms 14, over 5 ms 0; memory 1534 KB"))
wv.box = ns.DebugWindow().box
rawset(wv.box, "HighlightText", function(self) self.highlighted = true end)
rawset(wv.box, "SetFocus", function(self) self.focused = true end)
slash("debug")
check("in a window to copy from: the report selected and in focus, a line in the chat",
    wv.box.highlighted and wv.box.focused and wv.box.text:find("^Spheres v") ~= nil
    and saidSince(from, "debug report open") and not saidSince(from, "orbs: scale")
    and ns.DebugWindow().strata == "DIALOG")
wv.box.scripts.OnTextChanged(wv.box, true) -- typing into it
check("read-only: typing puts the report back", wv.box.text == ns.DebugWindow().text)
wv.box.scripts.OnEscapePressed(wv.box)
check("Escape closes it", not ns.DebugWindow().shown)
-- /spheres profile: each busy part timed for a while, in the same window
wv.after = C_Timer.After
C_Timer.After = function(_, fn) wv.done = fn end
slash("profile")
for _ = 1, 30 do L.scripts.OnUpdate(L, 0.016) end
fire("UNIT_POWER_FREQUENT", "player")
wv.done()
C_Timer.After = wv.after
check("/spheres profile: what each part costs, the busiest first, beside the profiler's cost",
    wv.reported("profile: 10 s") and wv.reported("liquids: ") and wv.reported("health and power events: ")
    and wv.reported("cost: ") and ns.DebugWindow().title.text == "Spheres profile"
    and ns.DebugWindow().box.text:find("liquids: [%d.]+ ms a frame %(%d+%%%), [%d.]+ KB a second, 30 calls") ~= nil
    and wv.reported("event UNIT_POWER_FREQUENT: 0.1 a second") and wv.reported("KB a second"))
ns.db.chatButtons, ns.db.chatScrollLeft = true, false
ns.Apply()
check("each part a setting: buttons back, scroll bar back on the right", cf.buttonFrame.parent == cf
    and cf.ScrollBar.points[1][1] == "TOPLEFT")
ns.db.chatButtons, ns.db.chatScrollLeft = false, true
ns.Apply()

-------------------------------------------------------------------------------
-- 9) settings, slash commands, debug, the key binding file, globals
-------------------------------------------------------------------------------
check("an Options page", SpheresSettingsPanel ~= nil)
do
    (function()
        local function findStatuesRow(parent)
            for _, child in ipairs(parent.kids or {}) do
                if child.label and child.label.text == "Statues" then return child end
                local found = findStatuesRow(child)
                if found then return found end
            end
        end
        ns.db.statueFinish = ns.DEFAULTS.statueFinish
        ns.Apply()
        local statuesRow = findStatuesRow(SpheresSettingsPanel)
        local statuesSelector
        for _, child in ipairs(statuesRow and statuesRow.kids or {}) do
            if child.kind == "Button" and type(child.text) == "table" then statuesSelector = child end
        end
        check("one statue selector starts at Modern", statuesSelector and statuesSelector.text.text == "Modern")
        if statuesSelector then
            fireScript(statuesSelector, "OnClick")
            check("the selector offers Charcoal", ns.db.statueFinish == "charcoal" and statuesSelector.text.text == "Charcoal")
            fireScript(statuesSelector, "OnClick")
            check("the selector offers None", ns.db.statueFinish == "none" and statuesSelector.text.text == "None"
                and not art.statueL.shown and not art.statueR.shown)
            fireScript(statuesSelector, "OnClick")
            check("the selector returns to Modern", ns.db.statueFinish == "modern" and statuesSelector.text.text == "Modern"
                and art.statueL.shown and art.statueR.shown)
        end
    end)()
end
slash("bar4")
check("/spheres bar4 shows that ring", SpheresBar4Hub.shown and dockedAt(SpheresBar4Hub, "right", 60))
slash("bar4")
check("and hides it", not SpheresBar4Hub.shown)
from = #printed
slash("debug")
check("/spheres debug: the orbs, the bars, the rows, the rings", wv.reported("orbs: scale") and wv.reported("rows: Bar 1 page")
    and wv.reported("Action Bar 3: by the left sphere") and wv.reported("power hidden values")
    and wv.reported("power: visible") and wv.reported("FillNone") and wv.reported("tracking: xp")
    and wv.reported("target card: on") and wv.reported("pet: visible") and wv.reported("pet orb shown, whole"))
fireScript(hub3, "OnEnter")
check("a docked ring's tooltip says how to move it", tipText():find("round the sphere", 1, true))
check("one Modern bevel on every button: the docked hubs' round one, the action buttons' square one,"
    .. " the mail and target level badges' round one, its inner line on their discs",
    hub3.mini.border.texture == "Interface\\AddOns\\Spheres\\Media\\HubFrameModern"
    and hub3.mini.border.w == hub3.w and hub3.mini.border.points[1][1] == "CENTER" and hub3.mini.border.vertex == nil
    and SpheresBar1Button1.art.frame.texture == "Interface\\AddOns\\Spheres\\Media\\SlotFrameModern"
    and SpheresTarget.face.badge.border.texture == hub3.mini.border.texture
    and near(SpheresTarget.face.badge.border.w * 14 / 36, 13)
    and (function()
        for _, t in ipairs(S.Get("right").mailBadge.kids or {}) do
            if t.texture == hub3.mini.border.texture and near(t.w * 14 / 36, 8) then return true end
        end
    end)())
do
    local a = SpheresBar1Button1.art
    local function masked(texture, mask)
        for _, m in ipairs(texture.masks) do if m == mask then return true end end
        return false
    end
    check("Modern square borders and backgrounds share the slot chamfer mask",
        near(a.frame.w, SpheresBar1Button1.w * 48 / 45) and near(a.frame.h, SpheresBar1Button1.h * 48 / 45)
        and a.frame.points[1][1] == "CENTER"
        and a.modernMask.texture == MEDIA .. "SlotMaskModern"
        and masked(a.icon, a.modernMask) and masked(a.bg, a.modernMask) and masked(a.empty, a.modernMask)
        and not masked(a.icon, a.mask) and near(SpheresBagsHub.w, SpheresBar1Button1.w))
    ns.db.statueFinish = "charcoal"
    ns.Apply()
    check("Charcoal restores the native icon mask and frame proportions",
        near(a.frame.w, SpheresBar1Button1.w * 46 / 45) and masked(a.icon, a.mask)
        and not masked(a.icon, a.modernMask) and not masked(a.bg, a.modernMask)
        and not masked(a.empty, a.modernMask) and a.bg.vertex[1] == 1 and a.empty.vertex[1] == 1)
    check("Charcoal restores the original cavity, sphere and statue positions",
        near(SpheresLeft:GetCenter(), 960 - 320) and near(SpheresRight:GetCenter(), 960 + 320)
        and art.frame.w == 788 and near(art.statueL.points[1][4], -389.3) and near(art.statueR.points[1][4], 373.3))
    ns.db.statueFinish = "modern"
    ns.Apply()
end
check("the docked hubs 20% smaller than a minimap button, frame, disc and icon alike (0.5.440), the menu's and"
    .. " Bag's their own; their inner edge as far over the ball's as before",
    near(hub3.w, 36 * 0.8) and near(hub3.h, 36 * 0.8) and near(hub3.mini.bg.w, 24 * 36 * 0.8 / 31)
    and near(hub3.mini.icon.w, 22.5 * 36 * 0.8 / 31) and SpheresMenuHub.w == 27
    and (function()
        local _, _, r, ball, s = S.Geometry("left")
        return near(r - hub3.w / 2 * s, ball - 8 * s)
    end)())
-- The slosh (0.5.442): your character's turns, moves and falls, felt by the liquids
;(function() -- its own function: the main chunk is at Lua 5.1's 200 locals
    local M, facing = ns.Motion, WHERE.track.facing
    local bar
    for _, b in ipairs(SpheresLeft.liquids) do if b:IsVisible() then bar = b; break end end
    local function frames(n, turn, each) -- `turn` degrees a second, + to the right (the facing goes down)
        for _ = 1, n do
            WHERE.track.facing = ((WHERE.track.facing or 0) - math.rad(turn or 0) / 60) % (2 * math.pi)
            SpheresLeft.scripts.OnUpdate(SpheresLeft, 1 / 60)
            if each then each() end
        end
    end
    WHERE.track.facing = 1
    frames(400)
    -- 0.5.442's full tilt animated a mask's texture coordinates on the body: in game every liquid
    -- looked half full. Nothing but the piece and the pet's hole may cut it, and its clip stays on the level.
    local cuts = #bar.base.masks == 1 and bar.clip.points[2][5] == 0
    for _, layer in ipairs(bar.motion) do cuts = cuts and #layer.texture.masks == 2 end
    check("the slosh: on by default, nothing cutting the liquid's body (0.5.442's half-full liquids)", bar ~= nil
        and cuts and bar.inside.tilt == nil and math.abs(bar.sloshS) < 0.001 and not bar.pile.shown)
    frames(60, 180)
    check("a key turn (180°/s, under the threshold) leaves it still", math.abs(bar.sloshS) < 0.001)
    local least, climbed = 0, false
    frames(20, 720, function()
        least = math.min(least, bar.sloshS)
        local c = bar.crest.texcoord
        climbed = climbed or (bar.pile.shown and c[2] > c[6] + 0.01)
    end)
    check("a fast turn right: the liquid lags, climbing the left wall, its surface leaning with it", least < -0.02 and climbed)
    local most = bar.sloshS
    frames(90, 0, function() most = math.max(most, bar.sloshS) end)
    check("stopping, it rocks back past the middle", most > 0.02)
    frames(600)
    check("and settles", math.abs(bar.sloshS) < 0.01 and math.abs(bar.sloshSV) < 0.05 and not bar.pile.shown)
    MOUSE.falling = true
    frames(60)
    local floated, low = bar.sloshB, 0
    MOUSE.falling = false
    frames(60, 0, function() low = math.min(low, bar.sloshB) end)
    check("in the air it gets lighter, landing slams it down", floated > 0.02 and low < -0.02)
    frames(600)
    JumpOrAscendStart()
    frames(1)
    check("a jump's push-off presses it down", bar.sloshBV < 0)
    frames(600)
    slash("slosh off")
    frames(20, 720)
    check("/spheres slosh off: still", bar.sloshS == 0 and not bar.pile.shown and ns.db.slosh == "off")
    slash("slosh on")
    frames(600)
    slash("debug")
    check("/spheres debug: the slosh", wv.reported("slosh: on; turning 0°/s"))
    WHERE.track.facing = facing
end)()
-- The mana's magic by who you are (0.5.454): paladins and priests mixed purple and gold, the rest purple
;(function() -- its own function: the main chunk is at Lua 5.1's 200 locals
    local mana = S.Get("left").power
    local function layers()
        local magic, twins, n = {}, {}, 0
        for _, layer in ipairs(mana.motion) do
            if layer.magicIndex then magic[layer.magicIndex] = layer end
            if layer.twinOf then twins[layer.twinOf] = layer; n = n + 1 end
        end
        return magic, twins, n
    end
    local function gold(layer) local v = layer.texture.vertex; return v[1] > 0.9 and v[2] > 0.6 and v[3] < 0.4 end
    local function purple(layer) local v = layer.texture.vertex; return v[3] > v[2] and layer.texture.blend == "ADD" end
    local function mixed()
        local m, t = layers()
        return mana.magicLook == "mixed" and m[1].texture.blend == "BLEND" and m[1].texture.vertex[1] > m[1].texture.vertex[3]
            and purple(m[2]) and gold(m[3]) and m[3].texture.blend == "ADD" and t[3].texture.blend == "BLEND"
            and t[3].magicAlpha == 0.50 and t[3].texture.vertex[1] < 0.1 and mana.glints[1].vertex[3] < 0.7
    end
    local class = UnitClass
    fire("PLAYER_ENTERING_WORLD", false, false)
    local _, t, twins = layers()
    check("a paladin's mana: purple and gold, the gold current added over its dark twin (the first current's twin unseen)",
        mixed() and twins == 4 and t[2] and t[2].magicAlpha == nil and t[2].spec.alpha == 0)
    UnitClass = function() return "Priest", "PRIEST" end
    fire("PLAYER_ENTERING_WORLD", false, false)
    check("a priest's too", mixed() and S.LiquidDebug():find("mana's magic: mixed (PRIEST)", 1, true) ~= nil)
    local function green()
        local m, tw = layers()
        local v = m[3].texture.vertex
        local light = m[2].texture.vertex
        return mana.magicLook == "nature" and not purple(m[2]) and m[2].texture.blend == "ADD" and light[2] == 1
            and light[1] > 0.5 and tw[2].magicAlpha == 0.45 and m[3].texture.blend == "ADD" and v[2] > 0.9 and v[1] < 0.5
            and tw[3].magicAlpha == 0.50 and mana.glints[1].vertex[2] == 1 and mana.glints[1].vertex[3] < 0.7
    end
    UnitClass = function() return "Druid", "DRUID" end
    fire("PLAYER_ENTERING_WORLD", false, false)
    local druid = green()
    UnitClass = function() return "Shaman", "SHAMAN" end
    fire("PLAYER_ENTERING_WORLD", false, false)
    check("a druid's and a shaman's: no purple, a light green current and a green one, each over its dark twin (0.5.474)", druid and green()
        and S.LiquidDebug():find("mana's magic: nature (SHAMAN)", 1, true) ~= nil)
    UnitClass = function() return "Mage", "MAGE" end
    fire("PLAYER_ENTERING_WORLD", false, false)
    local m
    m, t = layers()
    check("a mage's: the purple, added, the twin unseen", mana.magicLook == "arcane" and purple(m[1]) and purple(m[2])
        and purple(m[3]) and m[3].magicAlpha == nil and t[3].magicAlpha == nil and t[3].spec.alpha == 0
        and mana.glints[1].vertex[3] == 1)
    UnitClass = class
    fire("PLAYER_ENTERING_WORLD", false, false)
end)()
-- /spheres motion (0.5.441): a live panel of how fast the view moves, its peaks kept for /spheres debug
;(function() -- its own function: the main chunk is at Lua 5.1's 200 locals
    local facing = WHERE.track.facing
    local from = #printed
    slash("motion")
    local panel
    for _, f in ipairs(frames) do if f.title and f.title.text == "Spheres motion" then panel = f end end
    check("/spheres motion opens the live panel", panel ~= nil and panel.shown and saidSince(from, "motion panel open"))
    -- a camera drag (left button held, the cursor hidden and still) while turning 2 radians a second
    -- across north (the facing wraps from 2 pi to 0); 1/16 s frames, two to a reading
    MOUSE.left, MOUSE.hidden, MOUSE.dx, MOUSE.dy = true, true, 3, 4
    for i = 1, 4 do
        WHERE.track.facing = (6.2 + i * 0.125) % (2 * math.pi)
        panel.scripts.OnUpdate(panel, 0.0625)
    end
    local text = {}
    for _, kid in ipairs(panel.kids or {}) do if type(kid.text) == "string" then text[#text + 1] = kid.text end end
    text = table.concat(text, "\n")
    check("it reads the turn (across north too), the mouse, the drag and the still cursor", text:find("turn: 115°/s   (peak 115)", 1, true)
        and text:find("mouse: 80 /s   (peak 80)", 1, true) and text:find("camera drag seen: YES   (peak 80 /s, 4 frames moved)", 1, true)
        and text:find("cursor position moved: 0 /s", 1, true) and text:find("left DOWN   right up   mouselook no   cursor hidden yes", 1, true)
        and text:find("moving: 7.0 yd/s   falling no", 1, true))
    MOUSE.left, MOUSE.hidden, MOUSE.dx, MOUSE.dy = false, false, 0, 0
    WHERE.track.facing = facing
    from = #printed
    slash("motion")
    check("and closes", not panel.shown and saidSince(from, "motion panel closed"))
    slash("debug")
    check("/spheres debug keeps its peaks", wv.reported("motion (/spheres motion, 0 s, 4 frames): turn peak 115°/s (facing read), "
        .. "mouse peak 80 /s (GetCursorDelta read), camera drag: seen, peak 80 /s over 4 frames, cursor position moved 0 /s at most meanwhile"))
end)()
local xml = io.open(dir .. "/Bindings.xml"):read("*a")
for _, def in ipairs(R.DEFS) do
    check("a key binding for " .. def.label, xml:find(R.ToggleBinding(def), 1, true) ~= nil)
    if def.kind == "spells" then check("and casting " .. def.label, xml:find(R.CastBinding(def), 1, true) ~= nil) end
end
check("no protected call in combat, whole run", #blocked == 0)
check("no globals outside its own names: " .. table.concat(strays, ", "), #strays == 0)

-------------------------------------------------------------------------------
-- 10) no garbage on the busy paths (0.5.433: the player saw 32 MB before the game collected).
-- Frames switch to allocation-free methods (LEAN) and hidden values are made once each, so what
-- a handler allocates is the add-on's own; the game's own tables (cooldown and aura duration
-- objects, aura data) are new on every call here as in game, and those events aren't held to 0.
-------------------------------------------------------------------------------
;(function()
    leanMode = true
    local function garbage(n, fn, ...)
        for _ = 1, 3 do fn(...) end -- first-time tables, memoized answers
        collectgarbage("collect")
        collectgarbage("stop")
        local m0 = collectgarbage("count")
        for _ = 1, n do fn(...) end
        local kb = (collectgarbage("count") - m0) / n
        collectgarbage("restart")
        return kb
    end
    local FREE = {
        { "UNIT_HEALTH", "player" }, { "UNIT_MAXHEALTH", "player" }, { "UNIT_HEAL_PREDICTION", "player" },
        { "UNIT_POWER_FREQUENT", "player", "MANA" }, { "UNIT_POWER_UPDATE", "player", "MANA" },
        { "UNIT_COMBAT", "player", "WOUND", 0, 123 }, { "UNIT_COMBAT", "player", "HEAL", 0, 45 },
        { "UNIT_SPELLCAST_SUCCEEDED", "player" }, { "ACTIONBAR_UPDATE_STATE" }, { "ACTIONBAR_UPDATE_USABLE" },
        { "SPELL_UPDATE_USABLE" }, { "ACTION_RANGE_CHECK_UPDATE", 1, true, true },
        { "UNIT_HEALTH", "target" }, { "UNIT_POWER_UPDATE", "target" }, { "UNIT_PORTRAIT_UPDATE", "target" },
        { "CURSOR_CHANGED" }, { "UPDATE_SHAPESHIFT_FORM" }, { "ZONE_CHANGED" }, { "QUEST_POI_UPDATE" },
    }
    for _, fighting in ipairs({ false, true }) do
        combat = fighting
        for _, e in ipairs(FREE) do
            local kb = garbage(100, fire, unpack(e))
            check(string.format("no garbage %s: %s %s (%.3f KB a call)", fighting and "in combat" or "out of combat",
                e[1], tostring(e[2] or ""), kb), kb < 0.02)
        end
    end
    combat = false
    -- every shown frame's OnUpdate, a frame at a time
    local function visible(f) while f do if not f.shown then return false end f = f.parent end return true end
    for _, f in ipairs(frames) do
        if visible(f) then
            local fns = {}
            if f.scripts.OnUpdate then fns[#fns + 1] = f.scripts.OnUpdate end
            for _, h in ipairs(f.hooks.OnUpdate or {}) do fns[#fns + 1] = h end
            for _, fn in ipairs(fns) do
                local name = tostring(f.name)
                for u = 1, 8 do
                    local un, uv = debug.getupvalue(fn, u)
                    if un == "name" and type(uv) == "string" then name = uv end
                end
                local kb = garbage(600, fn, f, 0.016)
                check(string.format("no garbage a frame: %s (%.4f KB)", name, kb), kb < 0.005)
            end
        end
    end
    leanMode = false
end)()

io.stdout:write(string.format("passed %d, failed %d\n", pass, fail))
if fail > 0 then os.exit(1) end
