local ADDON, ns = ...

-- The bottom of the screen in Diablo's style: Roth UI's art and layout (MIT, Media/RothUI-
-- LICENSE.txt; its pictures adapted by tools/make_media.py) with Spheres' own engine.
--   * two orbs on Roth's back (dark glass): the left one shows health and mana side by side,
--     or full health with non-mana power in its embedded ball when there is no pet; the
--     right one Blizzard's minimap under a glass globe. The glass is ours (tools/make_media.py).
--   * between them Roth's action bar frame: our two rows (Bars.lua) sit in it, and the slots
--     along its top show the experience and reputation bars under it (Track.lua picks the frame
--     with as many slots as bars show).
--   * a winged bronze lion and griffin (the player's art, tools/ornaments) stand outside the orbs;
--     the center frame crosses in front of their edges, with the statues above it.
--   * all of it in Roth's units on one frame, shrunk to fit the screen's width (S.fit).
--
-- Health and power: Forever hides them from add-ons, but a status bar takes the hidden values
-- (StatusBar:SetMinMaxValues and SetValue are allowed to). Each liquid is a status bar over its
-- piece's bounding box with a plain fill cut to the piece. Nothing masks a fill: 0.1-0.3 drew
-- Blizzard's masked liquids and they never showed. What is pinned to the fill's top follows the
-- hidden level: a frame that clips the liquid's moving layers to its level, and its wavy top. Pin
-- to it once: a region re-anchored to it moves only when the level changes (0.5.264).

local A = ns.Art
local S = {}
ns.Sphere = S

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local D = 206                  -- roughly 10% larger than the previous 187-unit orb
local BALL = D * 226 / 256     -- the glass ball inside it (Roth's art: 15..241 of 256)
local PET_BOWL = 7             -- reach of the contact shade beyond the embedded ball
local MAP_SIZE = BALL * 0.945  -- inset map; keep in sync with map_cloud() and map_dissolve()
local ORB_X, ORB_Y = 320, 92  -- lower the glass spheres without moving the center frame or action rows
S.ORB_TEXT_Y = 0               -- label frames share the sphere's origin; no screen-space offset
S.ORB_INNER_TEXT = 5           -- inset mana and coordinate text from the health/zone arcs
local OVERLAP = 8              -- the rings' buttons this far over the ball's edge (Ring.lua)
local EDGE_LABEL = BALL * 0.312 -- health and mana labels, inset from the glass edge
-- The left orb's pieces: their bounding boxes in ball radii (x0, x1, top; centred on y = 0), as
-- tools/make_media.py prints them. Their fill, glass and mask files cover exactly these.
local PIECES = {
    health = { -1.0000, 0.1897, 1.0000 },
    mana = { 0.1608, 1.0000, 0.9680 },
}

-- Roth's pieces: size, and where their bottom middle sits (the art is cut round the orbs for
-- these places: tools/make_media.py PLACES)
local ART = {
    frame = { 788, 202, 0, 0 },  -- Roth's 220 high, a little shorter: the rows fill its inside
    modernFrameY = -1,
    modernInset = 8 * 788 / 2048, -- cropped side rims; keep in step with make_media.py MODERN_SIDE_CUT
    -- Painted well centers in the user's 2048x500 Frame1Modern master, measured in pixels.
    modernSockets = { left = { 395.53, 438.96 }, right = { 1652.47, 438.96 } },
    -- the winged lion and griffin, their shadow pad round them (make_media.py prints these)
    statueL = { 121.6, 107.4, -389.3, -5.4 },  -- wind rider 6 units inward
    statueR = { 121.6, 105.9, 373.3, -7.0 },  -- 10 units outward, 1.6 units below the left statue
}
-- Shared layout reference: every element is positioned against this center-console box, not
-- independently against the HUD's large drag frame. The frame art and its invisible anchor have
-- the same bounds, with their bottom edge at the HUD baseline.
-- The frame by how many slots along its top are in use: its file, its top edge (the pet and
-- stance bars, the cast bar and the open rings go above it) and each slot's hole (centre y,
-- width, height; the bar extends through the frame's transparent slot). Slot centers are
-- measured from the final cropped, compacted textures at their 788 x 202 display size.
local FRAMES = {
    [0] = { file = "Frame0", top = 114.4 },
    [1] = { file = "Frame1", top = 120.9, slots = { { 80.5, 450, 9 } } },
    [2] = { file = "Frame2", top = 128.2, slots = { { 80.3, 436, 9 }, { 89.4, 436, 7 } } },
}
local function finishSuffix()
    local finish = ns.db and ns.db.statueFinish or "modern"
    if finish == "modern" then return "Modern" end
    if finish == "charcoal" or finish == "none" then return "Charcoal" end
    return ""
end
-- The griffin's file: its head see-through while Spheres doesn't draw the minimap's quest arrow
-- over it (questArrow off; the game's arrow shows faintly through), solid while it does (0.5.417).
local function griffinFile()
    return "StatueRight" .. (ns.db and ns.db.questArrow == false and "ClearHead" or "") .. finishSuffix()
end
local function frameFile(slots)
    return FRAMES[slots].file .. finishSuffix()
end
local HALF = { statues = 483, bare = 424 } -- half the width: statue to statue, or orb to orb
-- The complete HUD sits flush to the screen's bottom edge. The center frame and rows share this
-- baseline, so the art keeps its fit round the orbs.
local SINK = 0 -- align the complete HUD's bottom baseline with the screen edge
local SOCKET_X, SOCKET_Y = 241, 25 -- original-style hubs; Modern uses the measured image coordinates

local COLORS = {
    HEALTH = { 0.45, 0.018, 0.014 }, -- dark blood red under the moving textures
    PET = { 0.45, 0.018, 0.014 }, -- the pet's health: red as yours, with purple magic in it (0.5.284)
    PET_MANA = { 0.30, 0.06, 0.55 }, -- a pet's mana: violet (0.5.284; 0.5.271-0.5.283 its health's colour)
    MANA = { 0.020, 0.095, 0.58 }, -- slightly darker blue, still saturated
    RAGE = { 0.9, 0.3, 0.1 }, ENERGY = { 0.95, 0.85, 0.2 },
    FOCUS = { 0.95, 0.55, 0.2 }, RUNIC_POWER = { 0.2, 0.75, 1 },
}

local hud, art, top
S.edit = S.edit or {}
local spheres = {}
local frameSlots = 1
local placing = false
local pending = false
local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() end
local function secret(v) return A.secret(v) end
local function num(v) return v ~= nil and not secret(v) end

function S.HUD() return hud end
function S.FrameAnchor() return art and art.frameAnchor end
function S.Get(side) return spheres[side] end
function S.Art() return art end
function S.FrameInset() return finishSuffix() == "Modern" and ART.modernInset or 0 end
function S.OrbOffset() return ORB_X - S.FrameInset() end
function S.SocketOffset(side)
    if finishSuffix() == "Modern" then
        local socket = ART.modernSockets[side == "left" and "left" or "right"]
        return (socket[1] / 2048 - 0.5) * ART.frame[1] + (side == "left" and ART.modernInset or -ART.modernInset),
            (1 - socket[2] / 500) * ART.frame[2] + ART.modernFrameY
    end
    return side == "left" and -SOCKET_X or SOCKET_X, SOCKET_Y
end

function S.PlaceHud()
    if not hud or S.edit.moving then return end
    local point = ns.db and ns.db.hudPoint
    local x = type(point) == "table" and tonumber(point.x)
    local y = type(point) == "table" and tonumber(point.y)
    hud:ClearAllPoints()
    if x and y then hud:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y)
    else hud:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, SINK) end
end

function S.SetEditMode(active)
    S.edit.mode = active and true or false
    if not hud then return end
    hud:EnableMouse(S.edit.mode)
    if S.edit.selection then
        if S.edit.mode then
            if S.edit.selection.ShowHighlighted then
                S.edit.selection:ShowHighlighted()
            else
                S.edit.selection:Show()
            end
        else
            S.edit.selection:Hide()
            if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
                EditModeManagerFrame:ClearSnapPreviewFrame()
            end
        end
    end
    if not S.edit.mode and S.edit.panel then S.edit.panel:Hide() end
    S.UpdateValueVisibility()
    if not S.edit.mode and S.edit.moving then
        hud:StopMovingOrSizing()
        S.edit.moving = false
    end
end

function S.ToggleEditSettings()
    if not S.edit.panel then
        local panel = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        S.edit.panel = panel
        panel:SetSize(320, 250)
        panel:SetFrameStrata("DIALOG")
        panel:SetFrameLevel((S.edit.selection and S.edit.selection:GetFrameLevel() or 102) + 1)
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        panel:SetMovable(true)
        panel:RegisterForDrag("LeftButton")
        local close = panel.CloseButton or CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        panel.CloseButton = close
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function()
            panel:Hide()
            if S.edit.mode and S.edit.selection and S.edit.selection.ShowHighlighted then
                S.edit.selection:ShowHighlighted()
            end
        end)
        if panel.Bg and panel.Bg.SetAlpha then
            panel.Bg:SetAlpha(0.6)
        elseif panel.NineSlice and panel.NineSlice.Center and panel.NineSlice.Center.SetAlpha then
            panel.NineSlice.Center:SetAlpha(0.6)
        else
            panel.fill = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
            panel.fill:SetColorTexture(0.015, 0.018, 0.025, 0.6)
            panel.fill:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
            panel.fill:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
        end
        local savedPoint = ns.db.editSettingsPoint
        if type(savedPoint) == "table" and tonumber(savedPoint.x) and tonumber(savedPoint.y) then
            panel:SetPoint("BOTTOM", UIParent, "BOTTOM", tonumber(savedPoint.x), tonumber(savedPoint.y))
        else
            panel:SetPoint("LEFT", S.edit.selection, "RIGHT", 12, 0)
        end
        panel:SetScript("OnDragStart", function()
            if S.edit.mode and not inCombat() then panel:StartMoving() end
        end)
        panel:SetScript("OnDragStop", function()
            panel:StopMovingOrSizing()
            local x, bottom = panel:GetCenter(), panel:GetBottom()
            local panelScale, uiScale = panel:GetEffectiveScale(), UIParent:GetEffectiveScale()
            local uiWidth = UIParent:GetWidth()
            if num(x) and num(bottom) and num(panelScale) and num(uiScale) and num(uiWidth) and uiScale > 0 then
                local px, py = x * panelScale / uiScale - uiWidth / 2, bottom * panelScale / uiScale
                ns.db.editSettingsPoint = { x = px, y = py }
                panel:ClearAllPoints()
                panel:SetPoint("BOTTOM", UIParent, "BOTTOM", px, py)
            end
        end)
        if panel.TitleText then panel.TitleText:SetText("Spheres")
        else
            panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            panel.title:SetPoint("TOP", panel, "TOP", 0, -12)
            panel.title:SetText("Spheres")
        end

        panel.controls = {}
        local function addSlider(key, label, minValue, maxValue, step, y, read, write, display)
            local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
            title:SetText(label)
            local valueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            valueText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, y)
            local slider = CreateFrame("Slider", nil, panel)
            slider:SetOrientation("HORIZONTAL")
            slider:SetPoint("TOPLEFT", panel, "TOPLEFT", 130, y - 12)
            slider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -36, y - 12)
            slider:SetHeight(18)
            slider:SetMinMaxValues(minValue, maxValue)
            slider:SetValueStep(step)
            if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
            local track = slider:CreateTexture(nil, "BACKGROUND")
            track:SetPoint("LEFT")
            track:SetPoint("RIGHT")
            track:SetHeight(6)
            track:SetColorTexture(0.08, 0.075, 0.07, 1)
            slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            local previous = CreateFrame("Button", nil, panel)
            local nextButton = CreateFrame("Button", nil, panel)
            for button, direction in pairs({ [previous] = -1, [nextButton] = 1 }) do
                button:SetSize(20, 20)
                local base = direction < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-"
                    or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
                button:SetNormalTexture(base .. "Up")
                button:SetPushedTexture(base .. "Down")
                button:SetDisabledTexture(base .. "Disabled")
                button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
            end
            previous:SetPoint("RIGHT", slider, "LEFT", -3, 0)
            nextButton:SetPoint("LEFT", slider, "RIGHT", 3, 0)
            local function updateValue(value)
                valueText:SetText(display(value))
                previous:SetEnabled(value > minValue)
                nextButton:SetEnabled(value < maxValue)
            end
            slider:SetScript("OnValueChanged", function(_, value)
                value = math.max(minValue, math.min(maxValue, math.floor(value / step + 0.5) * step))
                updateValue(value)
                if S.edit.syncing then return end
                write(value)
                ns.Apply()
            end)
            previous:SetScript("OnClick", function() slider:SetValue(slider:GetValue() - step) end)
            nextButton:SetScript("OnClick", function() slider:SetValue(slider:GetValue() + step) end)
            panel.controls[#panel.controls + 1] = {
                slider = slider, read = read, display = display, text = valueText, update = updateValue,
            }
            panel[key] = slider
        end
        addSlider("scale", "HUD Scale", 0.8, 1.6, 0.05, -42,
            function() return ns.db.scale or 1 end,
            function(value) ns.db.scale = value end,
            function(value) return math.floor(value * 100 + 0.5) .. "%" end)
        local statueTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statueTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -82)
        statueTitle:SetText("Mirrored Statues")
        local function statueValue(field, fallback)
            local layout = ns.db.statueLayout
            return type(layout) == "table" and tonumber(layout[field]) or fallback
        end
        local function setStatueValue(field, value)
            ns.db.statueLayout = ns.db.statueLayout or { x = 0, y = 0, scale = 1 }
            ns.db.statueLayout[field] = value
        end
        addSlider("statueX", "Spread", -24, 24, 1, -106,
            function() return statueValue("x", 0) end,
            function(value) setStatueValue("x", value) end,
            function(value) return string.format("%+d", value) end)
        addSlider("statueY", "Vertical", -20, 20, 1, -139,
            function() return statueValue("y", 0) end,
            function(value) setStatueValue("y", value) end,
            function(value) return string.format("%+d", value) end)
        addSlider("statueSize", "Size", 0.7, 1.3, 0.05, -172,
            function() return statueValue("scale", 1) end,
            function(value) setStatueValue("scale", value) end,
            function(value) return math.floor(value * 100 + 0.5) .. "%" end)
        panel:SetScript("OnShow", function()
            S.edit.syncing = true
            for _, control in ipairs(panel.controls) do
                local value = control.read()
                control.slider:SetValue(value)
                control.update(value)
            end
            S.edit.syncing = false
        end)
        panel:Hide()
    end
    if S.edit.panel:IsShown() then S.edit.panel:Hide() else S.edit.panel:Show() end
end

-- Match Blizzard's Edit Mode magnetic grid: snap frame edges or centre to its visible grid
-- lines and screen guides, only when the player's Snap option is enabled.
function S.SnapHudPosition(centerX, bottomY, hudScale, uiScale)
    local uiWidth, uiHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if not (uiWidth and uiHeight and uiWidth > 0 and uiHeight > 0 and uiScale and uiScale > 0) then
        return centerX, bottomY
    end
    local scale = hudScale / uiScale
    local width, height = hud:GetWidth() * scale, hud:GetHeight() * scale
    local x = centerX * scale - uiWidth / 2
    local bottom = bottomY * scale
    local manager, magnetism = EditModeManagerFrame, EditModeMagnetismManager
    if not (manager and manager.IsSnapEnabled and manager:IsSnapEnabled() and magnetism) then
        return x, bottom
    end
    local y = bottom + height / 2 - uiHeight / 2
    local range = (magnetism.magnetismRange or 8) / uiScale
    local function snap(position, extent, screenExtent, lines, origin)
        local bestScreen, screenDistance
        local sources = { position - extent / 2, position, position + extent / 2 }
        local function screenTest(source, target)
            local delta = target - source
            local d = math.abs(delta)
            if d <= range * 2 and (not screenDistance or d < screenDistance) then bestScreen, screenDistance = delta, d end
        end
        local edges = { -screenExtent / 2, 0, screenExtent / 2 }
        for _, source in ipairs(sources) do
            for _, target in ipairs(edges) do screenTest(source, target) end
        end
        -- Prefer a nearby screen edge or center so snapping to the grid cannot leave
        -- a visible gap at the edge of the display.
        if bestScreen then return position + bestScreen end
        local bestGrid, gridDistance
        for _, source in ipairs(sources) do
            for _, line in pairs(lines or {}) do
                local delta = line - origin - source
                local d = math.abs(delta)
                if not gridDistance or d < gridDistance then bestGrid, gridDistance = delta, d end
            end
        end
        return position + (bestGrid or 0)
    end
    local grid = magnetism.magneticGridLines
    local snappedX = snap(x, width, uiWidth, grid and grid.vertical, uiWidth / 2)
    local snappedY = snap(y, height, uiHeight, grid and grid.horizontal, uiHeight / 2)
    return snappedX, snappedY - height / 2 + uiHeight / 2
end

-------------------------------------------------------------------------------
-- Building (once)
-------------------------------------------------------------------------------
local function child(parent, levelUp, kind)
    local f = CreateFrame(kind or "Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() + levelUp)
    f:EnableMouse(false)
    return f
end

local function piece(name, layer, sub, parent)
    local a = ART[name]
    local t = (parent or art):CreateTexture(nil, layer, nil, sub)
    t:SetSize(a[1], a[2])
    local anchor = name == "frame" and art.frameAnchor or hud
    t:SetPoint("BOTTOM", anchor, "BOTTOM", a[3], a[4])
    return t
end

-- The center frame goes over the orb glass; statues stay above its edges, with
-- the action rows above all of Roth's art. XP and reputation bars stay on LOW behind the frame.
local function buildArt()
    art = CreateFrame("Frame", nil, hud)
    art:SetFrameLevel(hud:GetFrameLevel() + 14)
    art:SetAllPoints(hud)
    art:EnableMouse(false)
    art.frameLayer = CreateFrame("Frame", nil, hud)
    art.frameLayer:SetFrameLevel(hud:GetFrameLevel() + 12)
    art.frameLayer:SetAllPoints(hud)
    art.frameLayer:EnableMouse(false)
    art.frameAnchor = CreateFrame("Frame", nil, hud)
    art.frameAnchor:SetSize(ART.frame[1], ART.frame[2])
    art.frameAnchor:SetPoint("BOTTOM", hud, "BOTTOM", 0, 0)
    art.frameAnchor:EnableMouse(false)
    art.frame = piece("frame", "BACKGROUND", -8, art.frameLayer)
    art.frame:SetTexture(MEDIA .. frameFile(frameSlots))
    art.statueL = piece("statueL", "BACKGROUND", 4)
    art.statueL:SetTexture(MEDIA .. "StatueLeft" .. finishSuffix())
    art.statueR = piece("statueR", "BACKGROUND", 4)
    art.statueR:SetTexture(MEDIA .. griffinFile())
    -- the frame's top edge: your pet's buttons and Blizzard's stance and cast bars hang off it (Bars.lua)
    top = CreateFrame("Frame", nil, hud)
    top:SetSize(1, 1)
    top:EnableMouse(false)
end

-- A piece's box on the orb: size and offset from its centre.
local function box(name)
    local p = PIECES[name]
    local r = BALL / 2
    return (p[2] - p[1]) * r, 2 * p[3] * r, (p[1] + p[2]) / 2 * r
end

-- The liquids' moving layers (0.5.259), over each plain fill: three textures both pieces share
-- (Media/LiquidCloud, LiquidStream, LiquidFine: tools/make_media.py), each seen through a
-- window `size` of its height, turned by `spin` (radians a second) from `angle`, its centre
-- circling (`drift`: x and y reach in the texture, x and y periods in seconds). A current also
-- travels along `flow` (x and y in the texture, over its period): two copies half a period apart,
-- each faded out before it starts over, so it never jumps. Regeneration lifts every window
-- (SURGE): the textures tile and repeat, and the windows wrap round them. Tint: the liquid's
-- colour times `gain` plus `lift`, or `rgb`; a BLEND layer darkens, an ADD one lights. `magic`:
-- the mana's purple haze and currents (0.5.260: "more purple liquid flows ... its magical
-- effect"), only while the power is mana; the pet's health has them too (MAGIC), tinted `petRgb`
-- (0.5.284: "pet health red but with purple things in it, because it's like magic": more blue than
-- red, so on red they read as purple, not pink). 0.5.258's layers were status bars nudged a
-- few units each way, pattern and outline together: the liquid looked still. `follow`: how much
-- of the slosh's carry each takes (0.5.442, the mockup's: the dark deep clouds least, the
-- streams most), so the layers part a little as it sloshes.
local LIQUID_LAYERS = {
    { file = "LiquidFine", blend = "BLEND", gain = 0.15, alpha = 0.40, size = 0.55, spin = 0.06, angle = 0.4,
      drift = { 0.05, 0.05, 11, 13 }, follow = 0.7 },
    { file = "LiquidCloud", blend = "BLEND", gain = 0.06, alpha = 0.85, size = 0.74, spin = -0.03, angle = 1.2,
      drift = { 0.04, 0.04, 21, 19 }, follow = 0.45 },
    { file = "LiquidCloud", blend = "ADD", gain = 1.1, lift = 0.05, alpha = 0.70, size = 0.70, spin = 0.045,
      angle = 2.6, mirror = true, drift = { 0.05, 0.04, 15, 26 }, follow = 0.6 },
    { file = "LiquidStream", blend = "ADD", gain = 1.3, lift = 0.14, alpha = 0.75, size = 0.75, spin = 0.008,
      flow = { 0, 0.12, 10 }, follow = 1.0 },
    { file = "LiquidStream", blend = "BLEND", gain = 0.05, alpha = 0.55, size = 0.62, spin = -0.012, angle = 1.9,
      mirror = true, flow = { 0.02, 0.10, 13 }, follow = 0.8 },
    { file = "LiquidCloud", blend = "ADD", rgb = { 0.42, 0.17, 0.70 }, alpha = 0.35, size = 0.66, spin = -0.05,
      angle = 4.1, drift = { 0.05, 0.05, 17, 14 }, magic = true, petRgb = { 0.12, 0.03, 0.55 }, follow = 0.6 },
    -- more red than blue: added to the blue, they read as purple, not as lighter blue
    { file = "LiquidStream", blend = "ADD", rgb = { 0.60, 0.06, 0.50 }, alpha = 0.80, size = 0.66, spin = 0.02,
      angle = 3.3, flow = { -0.02, 0.11, 11 }, magic = true, petRgb = { 0.18, 0.03, 0.70 }, follow = 1.0 },
    { file = "LiquidStream", blend = "ADD", rgb = { 0.70, 0.12, 0.62 }, alpha = 0.60, size = 0.56, spin = -0.03,
      angle = 5.2, mirror = true, flow = { 0.03, 0.09, 8.5 }, magic = true, petRgb = { 0.24, 0.06, 0.80 }, follow = 0.9 },
}
-- The liquids with the magic layers: your mana (while it is mana) and your pet's health (always).
local MAGIC = { mana = true, pet = true, pethealth = true }
-- The pieces share the textures: the mana's windows run later, turned and mirrored. `speed`: the
-- health moves slower (0.5.260, the player's call; the mana as it was). Health filling the whole
-- sphere (rage, energy: `whole`) faster than the piece (0.5.405, the player's: bear form's "too
-- slow"; at 0.55 the full sphere read as sluggish beside the full-speed inner power).
local LIQUID_OFFSET = {
    health = { time = 0, angle = 0, speed = 0.55 },
    whole = { time = 0, angle = 0, speed = 0.8 },
    mana = { time = 7.3, angle = 1.0, mirror = true, speed = 1 },
    pet = { time = 3.1, angle = 2.4, speed = 0.8 },
    pethealth = { time = 5.6, angle = 3.0, speed = 0.8 },
    petmana = { time = 9.2, angle = 4.4, mirror = true, speed = 0.9 },
}
-- Tiny glints the mana carries up: each at a random place inside the piece, rising while it
-- twinkles, then gone for a while. Violet, added to the blue (0.5.288, the player's: "the sparks
-- inside the mana should be purple tinted instead of being white"; a near white 0.84, 0.93, 1
-- before; lavender still read white, more red read pink).
local GLINTS, GLINT_SIZE, GLINT_LIFE, GLINT_RISE = 5, 11, 0.9, 5
local GLINT_COLOR = { 0.72, 0.30, 1 }
local GLINT_ALPHA = 0.85
-- The mana's magic by who you are (0.5.454, the player's: "mana's purple liquid can be golden for
-- paladin and priest", then "let's use mixed purple and gold for both paladin and priest and not
-- over complicate"): its haze and two currents (LIQUID_LAYERS' `magic` layers, in order) and its
-- glints. `arcane`: LIQUID_LAYERS' own purple (everyone else). `mixed` (Paladins and Priests): a warm
-- shade over the haze, the first current's purple, the second's gold added over its own dark twin
-- (`shadow`): blended over the blue, gold read as beige; added to it, as pale pink (picked in the
-- liquid simulator from five tries). S.UpdateMagic picks it by your class.
-- 0.5.456, the player's: "reduce the amount of gold, it's still too much": about half (0.30, 0.85,
-- 0.95 before), its twin with it so the gold still glows rather than greying.
local GOLD_HAZE = { rgb = { 0.30, 0.20, 0.05 }, blend = "BLEND", alpha = 0.15 }
local GOLD_CURRENT = { rgb = { 1.00, 0.72, 0.20 }, blend = "ADD", alpha = 0.45,
    shadow = { rgb = { 0.06, 0.04, 0.01 }, alpha = 0.50 } }
-- Druids and Shamans: the same with green for the gold (0.5.472, the player's: "druid and shaman may
-- have green tint of swirls in their mana (similar to paladin/priest replace green with yellow)"),
-- over a dark twin as the gold, or added green only pales the blue to cyan.
-- 0.5.474: "druid and shaman shouldn't have purple swirl at all, maybe replace their current purple with
-- light green": their first current light green too (over a twin of its own), no purple left.
local NATURE_HAZE = { rgb = { 0.08, 0.26, 0.06 }, blend = "BLEND", alpha = 0.15 }
local NATURE_LIGHT = { rgb = { 0.55, 1.00, 0.50 }, blend = "ADD", alpha = 0.50,
    shadow = { rgb = { 0.01, 0.05, 0.01 }, alpha = 0.45 } }
local NATURE_CURRENT = { rgb = { 0.36, 1.00, 0.30 }, blend = "ADD", alpha = 0.45,
    shadow = { rgb = { 0.01, 0.06, 0.01 }, alpha = 0.50 } }
local MAGIC_LOOK = {
    arcane = { {}, {}, {}, glint = GLINT_COLOR },
    mixed = { GOLD_HAZE, {}, GOLD_CURRENT, glint = { 1, 0.78, 0.66 } },
    nature = { NATURE_HAZE, NATURE_LIGHT, NATURE_CURRENT, glint = { 0.70, 1, 0.62 } },
}
local MIXED = { PALADIN = "mixed", PRIEST = "mixed", DRUID = "nature", SHAMAN = "nature" } -- the rest: arcane
-- Gold needs the blue under it darkened, or added gold only pales it: a magic current a look gives
-- a `shadow` gets a twin drawn just under it, its copy (the same window, so the same wisps), BLEND,
-- unseen (alpha 0) in the looks without one.
do
    local n, i = 0, 1
    while i <= #LIQUID_LAYERS do
        local spec = LIQUID_LAYERS[i]
        if spec.magic and not spec.twin then
            n = n + 1
            local shaded = false
            for _, look in pairs(MAGIC_LOOK) do if look[n] and look[n].shadow then shaded = true end end
            if shaded then
                local twin = {}
                for k, v in pairs(spec) do twin[k] = v end
                twin.blend, twin.twin, twin.alpha, twin.rgb, twin.petRgb = "BLEND", true, 0, { 0, 0, 0 }, { 0, 0, 0 }
                table.insert(LIQUID_LAYERS, i, twin)
                i = i + 1
            end
        end
        i = i + 1
    end
end
-- The liquid's wavy top (0.5.263, in place of Roth's OrbSpark, a soft glow half over the level:
-- "a ghosty layer ... a glow with no real purpose"): two strips across the piece, pinned once to
-- the fill's top. Media/SurfaceCrest is the waves' liquid, solid from their edge down to the level
-- (troughs on it: full shows no dips, a hidden level can't be tested), then fading over `fade`
-- into the moving layers; Media/SurfaceLine, the light under the edge, falls off over `glow`.
-- Only their texture coordinates move: they travel (`speed` wavelengths a second) and slosh
-- (`slosh` units each way over `sloshPeriod`) on their piece's clock. 0.5.263-0.5.264 re-anchored
-- a wave mask to the hidden level every frame: the client moved it only when the level changed,
-- so while regenerating the waves stood still and jumped. Sizes in units, as make_media.py
-- SURFACE_*: the strips' textures span `periods` wavelengths, and scroll by up to one.
-- 0.5.268: twice 0.5.266's travel (0.045) and slosh (over 9 s), the player's "just faster" for
-- the top; 0.5.267's 0.07 read as no change.
local SURFACE = { wavelength = 56, periods = 3, pad = 3, fade = 8, glow = 12, speed = 0.09, slosh = 4,
    sloshPeriod = 4.5, alpha = 0.55 }
-- The liquids' slosh with your character (0.5.442, Motion.lua: the physics; here its drawing), all
-- by texture coordinates (nothing re-anchored per frame): the swirls' windows shear (moveLayer),
-- the surface strips reach Motion.ROOM further each way and lean their line (stripCoords), and the
-- liquid climbs the wall it sloshes to: Media/SloshEdge (SLOSH_EDGE_SPAN units of it, its edge at
-- its middle, clamped past its ends) as a texture over the level (`pile`, movePile); the low side
-- stays level. 0.5.442 drained the low side too ("full tilt") with that edge as a mask on the
-- body, leaned by the mask's texture coordinates every frame: in game every liquid looked half
-- full ("liquids are half full"), the edge at the middle of the mask's rectangle, as if a mask
-- takes no texture coordinates (or only when its layout changes). Don't animate a mask.
local SLOSH_EDGE = MEDIA .. "SloshEdge"
local SLOSH_EDGE_SPAN = 32 -- units the edge's texture spans (make_media.py SLOSH_EDGE)
local function sloshOn() return not (ns.db and ns.db.slosh == "off") end
-- Spending or a wound lowers the level from the top and leaves the liquid where it is; only what
-- comes in lifts the whole liquid, filling from the bottom (0.5.269, the player's: "when spending
-- mana or losing health, it should go from the top ... Only when regenerating the whole liquid
-- should fill from bottom"; 0.5.266-0.5.268 pinned the layers to the level, and spending drained
-- them "from below"). The values are hidden: a change counts as spent when the player cast a
-- spell (power) or took a wound (health) up to `before` seconds ahead of it or `after` seconds
-- behind it. Any other change (a regeneration tick, a heal, a potion, a drink) lifts every layer
-- about a tick's worth of the level, `lift` units per `tick` seconds at most however often the
-- game reports it. Rage and runic power drain on their own, so they never lift.
-- What is owed goes out no faster than `lift` per `tick`, the last unit easing out at `rate`: a
-- steady climb under the churning, as the mana's many small reports always gave. Health comes in
-- one 2 s tick: 0.5.331 waited `after` and eased the whole tick out at `rate` ("the animations
-- pauses, and comes upwards after a while"), 0.5.332 lifted it within 0.2 s, and either way every
-- layer slid up together faster than it churns ("swirls slide up stiffly"). Your health doesn't
-- wait for `after` when the change is surely a gain: out of combat (only regeneration, food and
-- heals raise it there) or with a heal reported up to `before` ahead of it; a wound reported with
-- it or within `after` behind it stops it.
local SURGE = { lift = 5, tick = 2, rate = 2.5, cap = 15, before = 0.6, after = 0.2 }
local liquidClock = 0 -- seconds the left orb has animated: when changes and spending happened

-- The moving layers of one liquid, clipped to its level: a frame from the bar's bottom to its
-- fill's top (the hidden value sets the fill's height; the game lays out what is pinned to it,
-- as it does the surface line) clips plain textures, masked to the piece. Without clipping
-- (no SetClipsChildren) there are none: they would show above the level.
-- A mask for the pet's cavity on what a frame of the left orb draws, over its ball, centred on
-- it: blank until there is a pet in it (S.SetPetHole, PET.inside), then `on`: Media/PetCavity for
-- its liquids (seen behind the pet's ball, a little dimmer: 0.5.275, "I should see the liquid behind
-- because it is sitting in front of the cavity"; 0.5.273-0.5.274 cut them away, 0.5.276-0.5.277 cut
-- a gap round it to the world: "I still see the god damn background"). Each frame its own.
local HOLE_OFF = "Interface\\Buttons\\WHITE8x8"
local function holeMask(frame, orb, holes, on)
    local m = frame:CreateMaskTexture()
    m.on = MEDIA .. (on or orb.cavity or "PetCavity") -- (the target sphere's: TargetCavity)
    m:SetTexture(HOLE_OFF, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetSize(orb.ballSize or BALL, orb.ballSize or BALL)
    m:SetPoint("CENTER", orb, "CENTER", 0, 0)
    holes[#holes + 1] = m
    return m
end

local function buildMotion(o, bar, name, file, w, h, scale, holes)
    bar.motion, bar.glints = {}, {}
    local clip = CreateFrame("Frame", nil, o)
    if not clip.SetClipsChildren or not clip.CreateMaskTexture then
        clip:Hide()
        return
    end
    clip:SetFrameLevel(bar:GetFrameLevel() + 1)
    clip:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    clip:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    -- On the vessel: what goes out leaves the liquid where it is; what comes in lifts it by
    -- texture (SURGE).
    local inside = CreateFrame("Frame", nil, clip)
    inside:SetAllPoints(bar)
    inside:EnableMouse(false)
    inside.mask = inside:CreateMaskTexture()
    inside.mask:SetTexture(MEDIA .. "Mask" .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    inside.mask:SetAllPoints(inside)
    if holes then inside.hole = holeMask(inside, o, holes) end
    -- the liquid's plain colour, here rather than as the bar's fill: a bar's fill can't be masked
    -- (masked fills never drew), and the pet's hole has to cut it (0.5.273)
    bar.base = inside:CreateTexture(nil, "ARTWORK", nil, -8)
    bar.base:SetTexture(MEDIA .. "Fill" .. file)
    bar.base:SetAllPoints(inside)
    if inside.hole then bar.base:AddMaskTexture(inside.hole) end
    local offset = bar.offset
    local magicIndex = 0 -- its place among the magic layers (MAGIC_LOOK)
    for i, spec in ipairs(LIQUID_LAYERS) do
        if spec.magic and not spec.twin then magicIndex = magicIndex + 1 end
        if not spec.magic or MAGIC[name] then
            for copy = 0, spec.flow and 1 or 0 do
                -- in the table's order; the game takes sublevels -8 to 7 and throws past them
                -- (0.5.260's eighth layer at 8 broke the whole build)
                local t = inside:CreateTexture(nil, "ARTWORK", nil, i - 8)
                t:SetTexture(MEDIA .. spec.file, "REPEAT", "REPEAT")
                t:SetAllPoints(inside)
                t:SetBlendMode(spec.blend)
                t:AddMaskTexture(inside.mask)
                if inside.hole then t:AddMaskTexture(inside.hole) end
                bar.motion[#bar.motion + 1] = { texture = t, spec = spec, copy = copy, aspect = w / h,
                    height = h, scale = scale, time = offset.time, angle = offset.angle,
                    speed = offset.speed, mirror = not spec.mirror ~= not offset.mirror, u = 0.5, v = 0.5,
                    magicIndex = spec.magic and not spec.twin and magicIndex or nil,
                    twinOf = spec.twin and magicIndex + 1 or nil }
            end
        end
    end
    if name == "mana" then
        for i = 1, GLINTS do
            local g = inside:CreateTexture(nil, "OVERLAY")
            g:SetTexture(MEDIA .. "LiquidGlint")
            g:SetSize(GLINT_SIZE * bar.unit, GLINT_SIZE * bar.unit)
            g:SetBlendMode("ADD")
            g:SetVertexColor(GLINT_COLOR[1], GLINT_COLOR[2], GLINT_COLOR[3])
            g:SetAlpha(0)
            if inside.hole then g:AddMaskTexture(inside.hole) end
            g.wait = 0.4 + 0.9 * i -- the first ones staggered
            bar.glints[i] = g
        end
    end
    bar.clip, bar.inside = clip, inside
end

-- One of the surface's strips: across the piece, pinned once to the fill's top, from SURFACE.pad
-- over the level to `depth` under it, and Motion.ROOM further each way for the slosh (all times
-- the liquid's `unit`), clipped to the piece. Only its texture coordinates move (stripCoords):
-- across, the waves repeat (0.5.452: the whole sphere and the inner one are wider than the texture's
-- three waves, `SURFACE.periods`, at their unit; clamped, their surface's right part ran flat,
-- seen in the liquid simulator); down, clamped past its ends (nothing over the waves, nothing
-- under the light).
local function surfaceStrip(bar, file, layer, depth)
    local surface, top, k, room = bar.surface, bar:GetStatusBarTexture(), bar.unit, ns.Motion.ROOM
    local t = surface:CreateTexture(nil, layer)
    t:SetTexture(MEDIA .. file, "REPEAT", "CLAMP")
    t:SetPoint("TOPLEFT", top, "TOPLEFT", 0, (SURFACE.pad + room) * k)
    t:SetPoint("TOPRIGHT", top, "TOPRIGHT", 0, (SURFACE.pad + room) * k)
    t:SetHeight((SURFACE.pad + depth + 2 * room) * k)
    t.depth = depth
    t:AddMaskTexture(surface.mask)
    if surface.hole then t:AddMaskTexture(surface.hole) end
    return t
end

-- One liquid: a status bar over its piece's box, its plain fill cut to the piece; its moving
-- layers under its wavy top (buildMotion); over them its shade (the bottom in shadow,
-- LiquidShade*) and the light along the waves, clipped to the piece. A piece of the left orb by
-- default; `geom` gives another's box (the pet's: w, h, x, y) and how small it is beside the big
-- ones: `scale` for its layers' windows (the same clouds at the same size on the screen), `unit`
-- for its waves and their light, `clock` another LIQUID_OFFSET than its name's. `holes`: the left orb's pieces gather the masks the pet's hole
-- cuts them with. With clipping the bar's own fill is empty (FillNone): the plain colour is drawn
-- in the clip, where masks reach it; it still sets the level everything is pinned to.
local function buildLiquid(o, name, file, geom, holes)
    local w, h, x, y, scale, unit
    if geom then w, h, x, y, scale, unit = geom.w, geom.h, geom.x, geom.y or 0, geom.scale, geom.unit
    else w, h, x = box(name); y, scale, unit = 0, 1, 1 end
    local bar = CreateFrame("StatusBar", nil, o)
    bar.unit, bar.width, bar.clock, bar.centreX = unit, w, 0, x -- (centreX: where S.Crack breaks)
    bar.sloshRate = math.sqrt((box("health")) / w) -- Motion.Step: a narrower vessel rocks faster
    bar:SetFrameLevel(o:GetFrameLevel() + 1)
    bar:SetSize(w, h)
    bar:SetPoint("CENTER", o, "CENTER", x, y)
    bar:SetOrientation("VERTICAL")
    bar:EnableMouse(false)
    local clips = bar.SetClipsChildren ~= nil and bar.CreateMaskTexture ~= nil
    bar:SetStatusBarTexture(MEDIA .. (clips and "FillNone" or "Fill" .. file))
    bar.maskFile = MEDIA .. "Mask" .. file -- its shape (and a crack's in its glass: S.Crack)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    if bar.CreateMaskTexture then -- the heal band's
        bar.mask = bar:CreateMaskTexture()
        bar.mask:SetTexture(MEDIA .. "Mask" .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        bar.mask:SetAllPoints(bar)
        if holes then bar.hole = holeMask(bar, o, holes) end
    end
    bar.offset = LIQUID_OFFSET[geom and geom.clock or name] -- its clock: speed and phase
    buildMotion(o, bar, name, file, w, h, scale, holes)
    if geom and geom.flat then
        -- The contact shade belongs to the outer sphere, just beyond this ball's
        -- edge. Its own status bar reveals the appropriate arc with the liquid's
        -- hidden value; the textures separate the two sides of a split pet orb.
        local contact = CreateFrame("StatusBar", nil, o)
        local reach = BALL * unit + 2 * PET_BOWL
        contact:SetFrameLevel(o:GetFrameLevel())
        contact:SetSize(reach, reach)
        contact:SetPoint("CENTER", o, "CENTER")
        contact:SetOrientation("VERTICAL")
        contact:EnableMouse(false)
        contact:SetStatusBarTexture(MEDIA .. "PetContactShadow" .. (file == "Pet" and "" or file:sub(4)))
        contact:SetMinMaxValues(0, 1)
        contact:SetValue(0)
        bar.contact = contact
    end
    local surface = CreateFrame("Frame", nil, o)
    surface:SetFrameLevel(bar:GetFrameLevel() + 3)
    surface:SetAllPoints(bar)
    surface:EnableMouse(false)
    if not (geom and (geom.flat or geom.unshaded)) then -- none in the pet's (0.5.274: "a donut effect") or the target's
        surface.shade = surface:CreateTexture(nil, "ARTWORK")
        surface.shade:SetTexture(MEDIA .. "LiquidShade" .. file)
        surface.shade:SetAllPoints(surface)
    end
    if holes and surface.CreateMaskTexture then
        surface.hole = holeMask(surface, o, holes)
        if surface.shade then surface.shade:AddMaskTexture(surface.hole) end
    end
    bar.surface, bar.surge = surface, 0
    bar.health = name == "health" -- your health, whole or a piece: lifts sooner (SURGE)
    if bar.clip then -- no waves without the clip: the plain fill's flat top alone
        surface.mask = surface:CreateMaskTexture()
        surface.mask:SetTexture(MEDIA .. "Mask" .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        surface.mask:SetAllPoints(surface)
        bar.crest = surfaceStrip(bar, "SurfaceCrest", "ARTWORK", SURFACE.fade)
        bar.line = surfaceStrip(bar, "SurfaceLine", "OVERLAY", SURFACE.glow)
        bar.line:SetBlendMode("ADD")
        bar.line:SetAlpha(SURFACE.alpha)
        -- one-sided slosh: the liquid up the wall, from the level to the leaning line (movePile)
        local top = bar:GetStatusBarTexture()
        bar.pile = surface:CreateTexture(nil, "ARTWORK", nil, -1)
        bar.pile:SetTexture(SLOSH_EDGE, "CLAMP", "CLAMP")
        bar.pile:SetPoint("BOTTOMLEFT", top, "TOPLEFT", 0, 0)
        bar.pile:SetPoint("TOPRIGHT", top, "TOPRIGHT", 0, ns.Motion.ROOM * unit)
        bar.pile:AddMaskTexture(surface.mask)
        if surface.hole then bar.pile:AddMaskTexture(surface.hole) end
        bar.pile:Hide()
    end
    return bar
end

local function contactBase(o, radius)
    local t = o:CreateTexture(nil, "ARTWORK")
    t:SetTexture(MEDIA .. "PetContactBase")
    t:SetSize(2 * (radius + PET_BOWL), 2 * (radius + PET_BOWL))
    t:SetPoint("CENTER", o, "CENTER")
    return t
end

-- A layer at `time` seconds (on its piece's clock), lifted `rise` units since the last frame: its
-- window into the texture (LIQUID_LAYERS) and, for a current's copy, its share of the cross-fade.
-- The slosh (Motion.Shape) carries its swirls `shift` units sideways at the top, a quarter of it
-- at the bottom, and `lift` up, turned `swirl`, each layer by its `follow`.
local TWO_PI = 2 * math.pi
local function moveLayer(bar, layer, time, rise, shift, lift, swirl)
    local spec = layer.spec
    time = time * layer.speed
    local t = time + layer.time
    local a = (spec.angle or 0) + layer.angle + spec.spin * time + swirl * spec.follow
    local c, s = math.cos(a), math.sin(a)
    local size = spec.size * layer.scale
    if rise > 0 then -- up the screen: the window goes down it, whichever way it is turned
        local k = rise * size / layer.height
        layer.u, layer.v = (layer.u + k * s) % 1, (layer.v + k * c) % 1
    end
    local u, v = layer.u, layer.v
    local d = spec.drift
    if d then
        u = u + d[1] * math.sin(TWO_PI * t / d[3])
        v = v + d[2] * math.cos(TWO_PI * t / d[4])
    end
    local weight = 1
    local f = spec.flow
    if f then
        local p = (t / f[3] + 0.5 * layer.copy) % 1
        u, v = u + f[1] * (p - 0.5), v - f[2] * (p - 0.5)
        weight = math.sin(math.pi * p) ^ 2
    end
    if spec.magic and not bar.manaEffects then weight = 0 end
    local hu, hv = size * layer.aspect / 2, size / 2
    if layer.mirror then hu = -hu end
    local xu, xv = hu * c, -hu * s -- the window's half-width in the texture (v runs down)
    local yu, yv = -hv * s, -hv * c -- its half-height
    -- the corners (-1 left, +1 right; +1 top, -1 bottom) moved against the carry, in half-sizes
    local top = 2 * shift * spec.follow / bar.width
    local bottom = top * ns.Motion.K.carryBottom
    local up = 2 * lift * spec.follow / layer.height
    local lx, rx, lbx, rbx, ty, by = -1 - top, 1 - top, -1 - bottom, 1 - bottom, 1 - up, -1 - up
    layer.texture:SetTexCoord(u + lx * xu + ty * yu, v + lx * xv + ty * yv, u + lbx * xu + by * yu, v + lbx * xv + by * yv,
                              u + rx * xu + ty * yu, v + rx * xv + ty * yv, u + rbx * xu + by * yu, v + rbx * xv + by * yv)
    local alpha = (layer.magicAlpha or spec.alpha) * weight
    if layer.alpha ~= alpha then -- most layers' never changes: no call for it every frame
        layer.alpha = alpha
        layer.texture:SetAlpha(alpha)
    end
end

-- A change in a liquid, or spending from it (Core.lua's unit events): see SURGE.
local function liquidOf(kind)
    local o = spheres.left
    if not o then return nil end
    if o.innerPowerActive then return kind == "health" and o.wholeHealth or o.innerPower.bar end
    return kind == "health" and o.health or o.power
end
function S.LiquidChanged(kind)
    local bar = liquidOf(kind)
    if bar and not bar.changedAt then bar.changedAt = liquidClock end
end
function S.LiquidSpent(kind)
    local bar = liquidOf(kind)
    if not bar then return end
    bar.spentAt = liquidClock
    -- a change that lifted without waiting (sureGain) was this spend's after all: stop lifting
    if bar.liftedAt and liquidClock - bar.liftedAt <= SURGE.after then bar.surge = 0 end
end
function S.LiquidHealed()
    local bar = liquidOf("health")
    if bar then bar.healedAt = liquidClock end
end

-- Your health's change at `at`, known to be a gain without waiting for `after` (see SURGE).
local function sureGain(bar, at)
    return bar.health and (not inCombat() or (bar.healedAt ~= nil and bar.healedAt >= at - SURGE.before))
end

-- Once a change is old enough to know nothing was spent with it, or surely a gain, it lifts the
-- liquid (a tick's worth at most per tick); then this frame's share of what is owed, at a steady
-- pace easing out.
local function riseOf(bar, elapsed)
    local at = bar.changedAt
    if at and (liquidClock - at >= SURGE.after or sureGain(bar, at)) then
        bar.changedAt = nil
        local spent = bar.spentAt and bar.spentAt >= at - SURGE.before
        if not spent and bar.rises ~= false then
            local share = bar.liftedAt and math.min(1, (at - bar.liftedAt) / SURGE.tick) or 1
            bar.surge = math.min(SURGE.cap, bar.surge + SURGE.lift * share)
            bar.liftedAt = at
        end
    end
    if bar.surge <= 0 then return 0 end
    local rise = math.min(bar.surge * (1 - math.exp(-SURGE.rate * elapsed)), SURGE.lift / SURGE.tick * elapsed)
    bar.surge = bar.surge - rise
    if bar.surge < 0.01 then rise, bar.surge = rise + bar.surge, 0 end
    return rise
end

-- A strip's window: u to u2 across, and down it the texture's level line on the waves' line, `hL`
-- and `hR` units over the level at the walls, stretched `amp` times (surfaceStrip's extent).
local function stripCoords(strip, k, u, u2, hL, hR, amp)
    local P, room = SURFACE.pad * k, ns.Motion.ROOM * k
    local span = P + strip.depth * k
    local top, bottom = P + room, -(strip.depth * k + room) -- over the level
    strip:SetTexCoord(u, (P - (top - hL) / amp) / span, u, (P - (bottom - hL) / amp) / span,
                      u2, (P - (top - hR) / amp) / span, u2, (P - (bottom - hR) / amp) / span)
end

-- The wavy top at `time` seconds (on its piece's clock): both strips' windows slid along their
-- waves, together (wrapping by whole wavelengths, the same waves again), and leaned with the
-- slosh (`hL`, `hR`, `amp`: Motion.Shape). Never re-anchored.
local function moveSurface(bar, time, hL, hR, amp)
    if not bar.line then return end
    local t = time * bar.offset.speed + bar.offset.time
    local w = SURFACE.wavelength * bar.unit
    local span = w * SURFACE.periods
    local u = ((t * SURFACE.speed * w + SURFACE.slosh * bar.unit * math.sin(TWO_PI * t / SURFACE.sloshPeriod)) % w) / span
    local u2 = u + bar.width / span
    stripCoords(bar.crest, bar.unit, u, u2, hL, hR, amp)
    stripCoords(bar.line, bar.unit, u, u2, hL, hR, amp)
end

-- The liquid up the wall, from the level (its bottom) to the leaning line.
local function movePile(bar, hL, hR)
    local pile = bar.pile
    if not pile then return end
    local show = hL > 0.05 or hR > 0.05
    if show ~= bar.pileShown then
        bar.pileShown = show
        pile:SetShown(show)
    end
    if not show then return end
    local span, top = SLOSH_EDGE_SPAN * bar.unit, ns.Motion.ROOM * bar.unit
    pile:SetTexCoord(0, 0.5 - (top - hL) / span, 0, 0.5 + hL / span, 1, 0.5 - (top - hR) / span, 1, 0.5 + hR / span)
end


-- A random place for a glint, in the piece and clear of its edges: its offset from the box's centre.
local function glintPlace(name)
    local p = PIECES[name]
    for _ = 1, 20 do
        local x = p[1] + 0.12 + (p[2] - p[1] - 0.17) * math.random()
        local y = p[3] * (1.6 * math.random() - 0.8)
        if x * x + y * y < 0.62 then return (x - (p[1] + p[2]) / 2) * BALL / 2, y * BALL / 2 end
    end
    return 0, 0
end

local function moveGlint(bar, g, elapsed)
    if g.wait > 0 then
        g.wait = g.wait - elapsed
        g:SetAlpha(0)
        if g.wait > 0 then return end
        g.age, g.x, g.y = 0, glintPlace("mana")
    end
    g.age = g.age + elapsed
    local p = g.age / GLINT_LIFE
    if p >= 1 then
        g.wait = 1.2 + 3 * math.random()
        g:SetAlpha(0)
        return
    end
    g:ClearAllPoints()
    local k = bar.unit -- (a smaller liquid's: the target sphere's)
    g:SetPoint("CENTER", bar, "CENTER", g.x * k + bar.sloshShift, (g.y + GLINT_RISE * p) * k + bar.sloshLift)
    g:SetAlpha(bar.manaEffects and GLINT_ALPHA * math.sin(math.pi * p) ^ 2 or 0)
end

-- Heals on their way to you (Blizzard's player frame shows them): a soft red band from your
-- health's level up by the incoming amount, in the health piece's shape. Both amounts may be
-- hidden, so nothing adds them up in Lua: an invisible status bar fed the incoming amount (out of
-- your maximum, the health piece's height) stands on the health fill's top, and the band is
-- pinned between the two fills' tops. A plain texture clipped by the piece's mask (as the surface
-- line is: those draw; masked status bar fills never did); past the top the mask cuts it off.
local HEAL_COLOR = { 1, 0.025, 0.015, 0.42 }
local function buildHeals(o, bar)
    local w, h = bar:GetSize()
    local heal = CreateFrame("StatusBar", nil, o)
    heal:SetFrameLevel(bar:GetFrameLevel())
    heal:SetSize(w, h)
    heal:SetPoint("BOTTOM", bar:GetStatusBarTexture(), "TOP", 0, 0)
    heal:SetOrientation("VERTICAL")
    heal:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    heal:SetStatusBarColor(1, 1, 1, 0) -- only its top edge is used
    heal:EnableMouse(false)
    heal:SetMinMaxValues(0, 1)
    heal:SetValue(0)
    local band = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    band:SetTexture("Interface\\Buttons\\WHITE8x8")
    band:SetVertexColor(HEAL_COLOR[1], HEAL_COLOR[2], HEAL_COLOR[3], HEAL_COLOR[4])
    band:SetPoint("BOTTOMLEFT", bar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", heal:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    if bar.mask then band:AddMaskTexture(bar.mask) end
    if bar.hole then band:AddMaskTexture(bar.hole) end
    o.heal, o.healBand = heal, band
end

local function setColor(bar, c)
    bar:SetStatusBarColor(c[1], c[2], c[3])
    if bar.base then bar.base:SetVertexColor(c[1], c[2], c[3]) end
    if bar.crest then bar.crest:SetVertexColor(c[1], c[2], c[3]) end
    if bar.pile then bar.pile:SetVertexColor(c[1], c[2], c[3]) end
    if bar.line then
        bar.line:SetVertexColor(math.min(1, c[1] * 1.6 + 0.12), math.min(1, c[2] * 1.6 + 0.12),
                                math.min(1, c[3] * 1.6 + 0.12))
    end
    bar.color = c
    local look = MAGIC_LOOK[bar.magicLook or "arcane"]
    for _, layer in ipairs(bar.motion) do
        local spec = layer.spec
        local rgb = bar.petMagic and spec.petRgb or (layer.magicIndex and look[layer.magicIndex].rgb)
            or (layer.twinOf and look[layer.twinOf].shadow and look[layer.twinOf].shadow.rgb) or spec.rgb
        if rgb then
            layer.texture:SetVertexColor(rgb[1], rgb[2], rgb[3])
        else
            local k, lift = spec.gain, spec.lift or 0
            layer.texture:SetVertexColor(math.min(1, c[1] * k + lift), math.min(1, c[2] * k + lift),
                                         math.min(1, c[3] * k + lift))
        end
    end
end

-- A liquid's magic in one of MAGIC_LOOK's looks: its layers' blend, colour and strength, its glints'
-- colour. Not your pet's (its own colours, petRgb).
local function setMagic(bar, name)
    if bar.petMagic or bar.magicLook == name then return end
    bar.magicLook = name
    local look = MAGIC_LOOK[name]
    for _, layer in ipairs(bar.motion) do
        if layer.magicIndex then
            local entry = look[layer.magicIndex]
            layer.texture:SetBlendMode(entry.blend or layer.spec.blend)
            layer.magicAlpha = entry.alpha
            layer.alpha = nil -- moveLayer sets it again
        elseif layer.twinOf then
            local shadow = look[layer.twinOf].shadow
            layer.magicAlpha = shadow and shadow.alpha or nil
            layer.alpha = nil
        end
    end
    for _, g in ipairs(bar.glints) do g:SetVertexColor(look.glint[1], look.glint[2], look.glint[3]) end
    if bar.color then setColor(bar, bar.color) end
end

-- An orb: Roth's back on dark glass, then whatever it holds, then its glass (glass()).
local function orbFrame(side)
    local playerOrb = side == "left"
    local o = CreateFrame(playerOrb and "Button" or "Frame", "Spheres" .. (playerOrb and "Left" or "Right"),
        hud, playerOrb and "SecureUnitButtonTemplate" or nil)
    o.side = side
    if playerOrb then
        o:SetAttribute("unit", "player")
        o:SetAttribute("type1", "target")
        o:SetAttribute("type2", "togglemenu")
        o:RegisterForClicks("AnyUp")
    end
    o:SetSize(D, D)
    o:SetFrameLevel(hud:GetFrameLevel() + 5)
    -- ORB_Y is measured from the shared console's bottom; moving the frame moves its spheres
    -- and all orb-attached text, pins and map layers as one unit.
    o:SetPoint("CENTER", art.frameAnchor, "BOTTOM", side == "left" and -S.OrbOffset() or S.OrbOffset(), ORB_Y)
    o.back = o:CreateTexture(nil, "BACKGROUND")
    o.back:SetTexture(MEDIA .. "OrbBack")
    o.back:SetAllPoints()
    if playerOrb then
        o.bottomShade = o:CreateTexture(nil, "BACKGROUND", nil, 1)
        o.bottomShade:SetTexture(MEDIA .. "OrbBottomShade")
        o.bottomShade:SetAllPoints()
    end
    return o
end

-- Glass over what an orb holds: a texture of ours with its shading, bright edge and highlight.
local function glassOver(o, file, w, h, x)
    o.glass = o.glass or child(o, 6)
    local t = o.glass:CreateTexture(nil, "ARTWORK")
    t:SetTexture(MEDIA .. file)
    t:SetSize(w, h)
    t:SetPoint("CENTER", o, "CENTER", x, 0)
    return t
end

-- A piece's numbers, both in one style: what you have / what you can have, side by side (0.5.23),
-- shortened from 1000 up (1267 -> 1.3k, 12345 -> 12k). The values may be hidden, and a hidden
-- value can't be measured, compared or joined in Lua: the game's own AbbreviateNumbers shortens
-- them and FontString:SetFormattedText joins them (both take hidden values from add-ons). So the
-- rule can't depend on the length: everything from 1000 up is shortened.
local NUMBER_FONT = "GameFontHighlightSmall"
local NUMBER_SMALLER = 1               -- match the coordinate label's face and size
local NUMBER_ALPHA = 0.7
local NUMBER_FORMAT = "%s|cff8c8c8c / %s|r" -- the maximum dimmer
local ABBREVIATE = { breakpointData = {     -- lower-case k and m (the player's "1.3k")
    { breakpoint = 1e7, abbreviation = "m", significandDivisor = 1e6, fractionDivisor = 1, abbreviationIsGlobal = false },
    { breakpoint = 1e6, abbreviation = "m", significandDivisor = 1e5, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1e4, abbreviation = "k", significandDivisor = 1e3, fractionDivisor = 1, abbreviationIsGlobal = false },
    { breakpoint = 1e3, abbreviation = "k", significandDivisor = 1e2, fractionDivisor = 10, abbreviationIsGlobal = false },
} }
S.ABBREVIATE = ABBREVIATE
local function smaller(fs, by)
    local file, size, flags = fs:GetFont()
    if file and num(size) and size > 6 + by then fs:SetFont(file, size - by, flags or "") end
end
local function outline(fs)
    local file, size, flags = fs:GetFont()
    flags = flags or ""
    if file and num(size) and not string.find(flags, "OUTLINE", 1, true) then
        fs:SetFont(file, size, flags ~= "" and (flags .. ",OUTLINE") or "OUTLINE")
    end
end
-- Place a glyph or value block on the sphere's rim curve while keeping the arc's
-- midpoint inset. This is the same construction used by the minimap labels.
local function arcPoint(angle, radius, curveRadius, distance, direction)
    local a = angle + direction * distance / curveRadius
    local shift = curveRadius - radius
    return curveRadius * math.cos(a) - shift * math.cos(angle),
        curveRadius * math.sin(a) - shift * math.sin(angle), a
end

local NUMBER_SPACING = 16
-- The combat badge's beat (buildLeft): every `period` s the red outline round the swords rises
-- from `low` to `high` alpha. The player's: "just do the outline glow at 0.75 and beat is 1.6"
-- (0.5.338), then "make outline glow 0.6" (0.5.339); 0.5.336-0.5.337 also ringed the well with
-- red halos (the rest halo's ring), "less glowy" asked next, then dropped; 0.5.335 swung
-- 0.12-0.30 over 2.4 s.
local COMBAT_GLOW = { period = 1.6, color = { 1, 0.16, 0.10 }, low = 0.16, high = 0.6 }
-- 0..1 through a beat: up in its first fifth, fading over the rest.
local function combatBeat(p)
    if p < 0.2 then return math.sin(p / 0.2 * math.pi / 2) end
    return math.cos((p - 0.2) / 0.8 * math.pi / 2) ^ 2
end
S.COMBAT_GLOW = COMBAT_GLOW
-- The client turns a value's text about the top of its line, not its middle: turned by `r` it
-- shows TURN_LIFT * (sin r, 1 - cos r) right and up of its anchor (0.5.289 measured 3.6 right and
-- 3.8 up a quarter round: PET.valueShift; about 2.5 right at 45 degrees). `settle` anchors each
-- part back by its own turn, so parts turned differently stay on their arc (0.5.335: the
-- embedded sphere's rage drifted out along its tight curve, "off-center and it's end is closer
-- to the outer edge"). Your outer values and the pet's were placed by eye without it.
local TURN_LIFT = 3.7
S.TURN_LIFT = TURN_LIFT
local NOTICE_DURATION = 3.0
local NOTICE_HOLD = 1.2
local HEALTH_ANGLE = math.rad(135)
local HEALTH_RADIUS = (EDGE_LABEL + 1) * math.sqrt(2)
local NOTICE_CURVE = 50
-- With an embedded sphere the notices take two lines between the health value's arc and the
-- sphere (noticeCircle): the heal, or a notice alone, halfway in, a wound under a heal all the way.
-- They start on one column from the health arc at 10 o'clock (noticeStart).
local NOTICE_START = math.rad(150)
local NOTICE_INNER_GAP = 16 -- the inmost line outside the embedded sphere's rim
local NOTICE_LINES = { 0.5, 1 }
local NOTICE_STEPS = 32
local function numberPart(parent, angle, radius, direction, distance, tint, alpha, curve, settle)
    local x, y, a = arcPoint(angle, radius, curve or BALL / 2, distance, direction)
    local turn = a + direction * math.pi / 2
    if settle then x, y = x - TURN_LIFT * math.sin(turn), y - TURN_LIFT * (1 - math.cos(turn)) end
    local fs = parent:CreateFontString(nil, "OVERLAY", NUMBER_FONT)
    fs:SetSize(36, 16)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetPoint("CENTER", parent, "CENTER", x, y)
    fs:SetTextColor(tint[1], tint[2], tint[3], alpha)
    if fs.SetRotation then fs:SetRotation(turn) end
    smaller(fs, NUMBER_SMALLER)
    outline(fs)
    return fs
end
-- `curve`: the rim the value bends along (the left orb's by default; the pet's ball for its own),
-- `spacing` between its three parts, `shift` ({ x, y }) moving all of it, `settle` each part set
-- back where the client draws it turned (TURN_LIFT).
local function numbers(parent, o, angle, radius, direction, curve, spacing, shift, settle)
    spacing = spacing or NUMBER_SPACING
    local n = CreateFrame("Frame", nil, parent)
    n:SetSize(D, D)
    n:SetPoint("CENTER", o, "CENTER", shift and shift[1] or 0, shift and shift[2] or 0)
    n:EnableMouse(false)
    n.text = n:CreateFontString(nil, "OVERLAY", NUMBER_FONT)
    n.text:SetPoint("CENTER", n, "CENTER", 0, 0)
    n.text:SetTextColor(1, 1, 1, NUMBER_ALPHA)
    smaller(n.text, NUMBER_SMALLER)
    n.text:Hide() -- retains the full protected string; visible pieces below follow the arc
    n.current = numberPart(n, angle, radius, direction, -spacing, { 1, 1, 1 }, NUMBER_ALPHA, curve, settle)
    n.separator = numberPart(n, angle, radius, direction, 0, { 0.55, 0.55, 0.55 }, NUMBER_ALPHA, curve, settle)
    n.maximum = numberPart(n, angle, radius, direction, spacing, { 0.55, 0.55, 0.55 }, NUMBER_ALPHA, curve, settle)
    n:Hide()
    return n
end

-- Received heals and wounds use the health arc inside the values. A wound's pale pink
-- "-amount" moves toward the sphere's centre only while a yellow "+amount" is also showing. Each starts at `alpha`,
-- holds, fades out by NOTICE_DURATION; a new one replaces it.
-- Plain amounts bend glyph by glyph. A protected amount stays together, with its sign on
-- another tangent; secret digits cannot be split into glyphs in Lua.
local NOTICES = {
    heal = { sign = "+", color = { 1, 0.92, 0.18 }, alpha = 0.95, inset = 18 },
    damage = { sign = "-", color = { 1, 0.82, 0.88 }, alpha = 0.95, inset = 18 }, -- pale pink (0.5.431)
}
local refreshDamagePosition
local function notice(parent, o, kind)
    local spec = NOTICES[kind]
    local n = CreateFrame("Frame", nil, parent)
    n:SetSize(D, D)
    n:SetPoint("CENTER", o, "CENTER", 0, S.ORB_TEXT_Y)
    n:SetFrameLevel(parent:GetFrameLevel() + 1)
    n:EnableMouse(false)
    n.spec, n.count = spec, 0
    n.glyphs = {}
    n.textColor = spec.color
    n.outline = true
    n.fontSizeBoost = 3
    n.sign = numberPart(n, HEALTH_ANGLE, HEALTH_RADIUS - spec.inset, -1, -12,
        spec.color, 1, NOTICE_CURVE)
    n.sign:SetText(spec.sign)
    n.protected = numberPart(n, HEALTH_ANGLE, HEALTH_RADIUS - spec.inset, -1, 5,
        spec.color, 1, NOTICE_CURVE)
    for _, part in ipairs({ n.sign, n.protected }) do
        local font, size, flags = part:GetFont()
        if font and num(size) then part:SetFont(font, size + 3, flags or "") end
    end
    n.protected:SetSize(80, 20)
    n.parts = { { n.sign, -12 }, { n.protected, 5 } } -- along the arc: refreshNoticeArc
    n.sign:Hide()
    n.protected:Hide()
    n.elapsed = 0
    n:SetScript("OnUpdate", A.Timed("heal and damage notices", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= NOTICE_DURATION then
            self:Hide()
            if kind == "heal" then refreshDamagePosition() end
        elseif self.elapsed > NOTICE_HOLD then
            self:SetAlpha(spec.alpha * (NOTICE_DURATION - self.elapsed) / (NOTICE_DURATION - NOTICE_HOLD))
        end
    end))
    n:Hide()
    return n
end

-- Ordinary text (coordinates and zone names) can follow the map's arc glyph by glyph. Health and
-- power values can contain protected values and must stay in one FontString.
-- Into `chars` (a list kept per text: a notice comes with every hit, 0.5.433), emptied first.
local function utf8Glyphs(value, chars)
    for k = #chars, 1, -1 do chars[k] = nil end
    local i = 1
    while i <= #value do
        local byte = string.byte(value, i)
        local length = byte < 128 and 1 or (byte < 224 and 2 or (byte < 240 and 3 or 4))
        chars[#chars + 1] = string.sub(value, i, i + length - 1)
        i = i + length
    end
    return chars
end

-- Each glyph's width into `widths` (kept per text too), its glyph made the first time; the total.
local function measureGlyphs(c, chars, widths)
    local total = 0
    for k = #widths, 1, -1 do widths[k] = nil end
    for i, char in ipairs(chars) do
        local glyph = c.glyphs[i]
        if not glyph then
            glyph = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            local color = c.textColor or { 0.96, 0.94, 0.88, 0.78 }
            glyph:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            local file, size, flags = glyph:GetFont()
            if file and num(size) and size > 8 then
                glyph:SetFont(file, size - 1 + (c.fontSizeBoost or 0), flags or "")
            end
            if c.outline then outline(glyph) end
            if c.shadow then
                local font, height = glyph:GetFont()
                local soft = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                local dark = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                if font and num(height) then
                    soft:SetFont(font, height + 2, "OUTLINE")
                    dark:SetFont(font, height + 1, "OUTLINE")
                end
                soft:SetTextColor(0, 0, 0, 0.35)
                dark:SetTextColor(0, 0, 0, 0.75)
                c.shadowGlyphs[i] = { soft, dark }
            end
            c.glyphs[i] = glyph
        end
        glyph:SetText(char)
        if c.shadow then
            for _, shadow in ipairs(c.shadowGlyphs[i]) do shadow:SetText(char) end
        end
        widths[i] = glyph:GetStringWidth()
        total = total + widths[i]
    end
    return widths, total
end

local function setCurvedText(c, value, angle, radius, maxWidth, rotationOffset, reverse, curveRadius, tangentShift, startAngle)
    value = value or ""
    angle = angle or math.rad(-140)
    radius = radius or BALL * 0.42
    curveRadius = curveRadius or radius
    rotationOffset = rotationOffset or math.pi / 2
    -- the same text again (the coordinates and zone name, five times a second): nothing to lay
    -- out, so no glyph tables to make; a start angle needs the widths
    if c.value == value and not startAngle then return angle end
    c.chars, c.widths = c.chars or {}, c.widths or {}
    local chars = utf8Glyphs(value, c.chars)
    local widths, total = measureGlyphs(c, chars, c.widths)
    if maxWidth and total > maxWidth then
        while #chars > 0 do -- a letter less and "...", until it fits
            table.remove(chars)
            chars[#chars + 1], chars[#chars + 2], chars[#chars + 3] = ".", ".", "."
            widths, total = measureGlyphs(c, chars, widths)
            if total <= maxWidth then break end
            chars[#chars - 2], chars[#chars - 1], chars[#chars] = nil, nil, nil
        end
        if total > maxWidth then
            for k = #chars, 1, -1 do chars[k] = nil end
            for k = #widths, 1, -1 do widths[k] = nil end
            total = 0
        end
    end
    local count = #chars
    if startAngle then -- the first glyph's leading edge, not the middle, at startAngle
        angle = startAngle + (reverse and -total or total) / 2 / curveRadius
    end
    if c.value == value then return angle end
    c.value = value
    for i = count + 1, #c.glyphs do
        c.glyphs[i]:SetText("")
        if c.shadow then
            for _, shadow in ipairs(c.shadowGlyphs[i]) do shadow:SetText("") end
        end
    end

    -- A label inset from the rim needs the rim's curvature, not the tighter curve of a
    -- concentric circle at the label's distance. Shift the curve's centre so its midpoint
    -- stays at the requested inset position.
    -- Long zone names need their whole arc nudged clockwise: otherwise the first
    -- letters crowd the top rim while the last letters sit too far inside it.
    local nudge = 0
    if tangentShift and maxWidth and maxWidth > 0 then
        nudge = tangentShift * math.min(1, total / (c.tangentReferenceWidth or maxWidth))
    end
    local nudgeX, nudgeY = nudge * math.sin(angle), -nudge * math.cos(angle)
    local cursor = -total / 2
    for i = 1, count do
        local index = reverse and (count - i + 1) or i
        local glyph = c.glyphs[index]
        local width = widths[index]
        local x, y, a = arcPoint(angle, radius, curveRadius, cursor + width / 2, 1)
        glyph:ClearAllPoints()
        glyph:SetPoint("CENTER", c, "CENTER", x + nudgeX, y + nudgeY)
        if glyph.SetRotation then glyph:SetRotation(a + rotationOffset) end
        if c.shadow then
            for layer, shadow in ipairs(c.shadowGlyphs[index]) do
                shadow:ClearAllPoints()
                shadow:SetPoint("CENTER", c, "CENTER", x + nudgeX + layer * 0.5,
                    y + nudgeY - layer * 0.8)
                if shadow.SetRotation then shadow:SetRotation(a + rotationOffset) end
            end
        end
        cursor = cursor + width
    end
    return angle
end

-------------------------------------------------------------------------------
-- The pet's orb (0.5.271, the player's reference art: "a central orb when there is a minion ...
-- divided into two if minion has mana"). Blizzard's PetFrame is the player frame's child (the
-- forever branch's PetFrame.xml), so hiding that frame hid the pet's too; 0.5.270's small sphere
-- docked on the rim gave way to this. A ball `r` of the left orb's radius (0.5.272: 0.57 was "too
-- big") sitting in a scoop in its health and mana (below), with no back: where it is
-- empty your liquid shows through, a little dimmer, under the ball's own glass (the client can't
-- bend it). Tried and dropped: an opaque back (0.5.271-0.5.272), a hole cut to the dark backing
-- (0.5.273-0.5.275), a ring cut to the world (0.5.276-0.5.277: "I still see the god damn
-- background"). Whole for a pet without mana (a Hunter's: its health), cut in two for one with (a
-- Warlock's demon: mana left, health right; `pieces` x0, x1, y0, y1 as make_media.py prints them).
-- Each liquid the big orbs' (layers, waves), scaled, without their broad bottom shade (0.5.274:
-- "a donut effect"). A narrow contact shadow appears outside the filled part of the inner ball.
-- A Hunter's pet's mood (Blizzard's PetHappiness.lua) is on its edge, upper right. The
-- button targets the pet, right-click its menu, a unit watch shows it while there is one; clicks
-- only in the square inside its ball (`edge`: the button's margin round it), so the rest still
-- targets you.
-------------------------------------------------------------------------------
-- The scoop (0.5.279, the player's: "use the scooped sphere parts for health and mana" ... "YES this
-- is what I want"): while there is a pet, the pieces carry the scoop its ball sits in, a concave
-- dent in their front `bowl` units round its ball (Media/PetBowl on their glass, their liquid a
-- little dimmer at its middle: PetCavity); without one, the pieces as they were (0.5.287, the
-- player's: "Characters without pets shouldn't have that cavity"; 0.5.279-0.5.286 kept it). Centred `at` (units right and up of the left orb's
-- centre, make_media.py PET_AT; 0.5.283: far enough right that its halves swap, below; 0.5.280-
-- 0.5.282: 8, 8, "towards the up right corner, but not too much"). `inside`:
-- the pet's ball sits in it (0.5.280), else beside the left orb at `angle`, `apart` units off its
-- glass, on its own dark glass (PetBack; 0.5.278-0.5.279, while the player showed what they meant).
-- Its halves are cut along the left orb's own seam where it crosses the ball (0.5.280: "align the
-- separation with the outer spheres separation"; 0.5.273-0.5.279 cut them at 45 degrees): mana the
-- smaller left part, health the bigger right (0.5.283, the player's: "swapped the positions of
-- health and mana for the pet ... a nice off centered look ... maintain the bigger part on the
-- health"; make_media.py PET_ROLES).
-- Its values: `valueInset` units inside its rim (0.5.290: health "inwards just a pinch"; 0.5.291:
-- mana "a pinch outwards", the same gap to the rim as health's), `valueSpacing` between their parts, `valueShift`
-- setting them back where the client draws text turned a quarter round (both read bottom to top):
-- 3.6 right and 3.8 up of its anchor, measured on the player's screen (0.5.289, "off centered, they
-- seem shifted right"; turned less, yours at 10:30 and 4:30 move less).
local PET = { r = 0.4275, edge = 5.0, mood = 18, inside = true, angle = 150, apart = 3, bowl = PET_BOWL,
    valueInset = { mana = 6.5, health = 8 }, valueSpacing = 13, valueShift = { -3.6, -3.8 },
    at = { 27, 8 },
    pieces = { health = { -0.2537, 0.9988, -0.9988, 0.9988 }, mana = { -0.9988, -0.2512, -0.9387, 0.9363 } } }
local PET_MOOD = { "UI-PetMad", "UI-PetNeutral", "UI-PetHappiness" }

local function buildPet(left)
    local rb = BALL / 2 * PET.r
    local rh = rb + PET.edge
    local p = CreateFrame("Button", "SpheresPet", hud, "SecureUnitButtonTemplate")
    p:SetAttribute("unit", "pet")
    p:SetAttribute("type1", "target")
    p:SetAttribute("type2", "togglemenu")
    p:RegisterForClicks("AnyUp")
    p:SetSize(2 * rh, 2 * rh)
    if PET.inside then
        p:SetPoint("CENTER", left, "CENTER", PET.at[1], PET.at[2])
    else
        local a, d = math.rad(PET.angle), BALL / 2 + rb + PET.apart
        p:SetPoint("CENTER", left, "CENTER", d * math.cos(a), d * math.sin(a))
        p.back = p:CreateTexture(nil, "BACKGROUND")
        p.back:SetTexture(MEDIA .. "PetBack")
        p.back:SetSize(2 * rb, 2 * rb)
        p.back:SetPoint("CENTER")
    end
    p:SetFrameLevel(hud:GetFrameLevel() + 13) -- over the left orb's glass and numbers, under the statues
    p.contactBase = contactBase(p, rb)
    local inset = rh - rb * math.sqrt(0.5)   -- the square inside the ball
    p:SetHitRectInsets(inset, inset, inset, inset)
    p.whole = buildLiquid(p, "pet", "Pet",
        { w = 2 * rb, h = 2 * rb, x = 0, scale = 2 * rb / BALL, unit = PET.r, flat = true })
    local function half(side, name, file)
        local q = PET.pieces[side]
        local h = (q[4] - q[3]) * rb
        return buildLiquid(p, name, file, { w = (q[2] - q[1]) * rb, h = h, x = (q[1] + q[2]) / 2 * rb,
            y = (q[3] + q[4]) / 2 * rb, scale = h / BALL, unit = PET.r, flat = true })
    end
    p.health = half("health", "pethealth", "PetHealth")
    p.mana = half("mana", "petmana", "PetMana")
    -- its health red with the purple magic always in it, tinted for red (LIQUID_LAYERS petRgb)
    for _, bar in ipairs({ p.whole, p.health }) do bar.manaEffects, bar.petMagic = true, true end
    setColor(p.whole, COLORS.PET)
    setColor(p.health, COLORS.PET)
    setColor(p.mana, COLORS.PET_MANA)
    p.glass = child(p, 6)
    local function glassOf(file, bar)
        local t = p.glass:CreateTexture(nil, "ARTWORK")
        t:SetTexture(MEDIA .. file)
        t:SetAllPoints(bar)
        return t
    end
    p.whole.glass = glassOf("GlassPet", p.whole)
    p.health.glass = glassOf("GlassPetHealth", p.health)
    p.mana.glass = glassOf("GlassPetMana", p.mana)
    p.gap = child(p, 7) -- over its glass: the mood
    p.mood = p.gap:CreateTexture(nil, "OVERLAY")
    p.mood:SetSize(PET.mood, PET.mood)
    p.mood:SetPoint("CENTER", p, "CENTER", 0, rb) -- on the ball's edge, at the top (clear of its values)
    p.mood:Hide()
    -- Its values left and right (0.5.285, the player's: "left and right as there isn't much space to
    -- be on the 10:30 and 4:30 positions like others"): mana at 9 o'clock over its left part, health
    -- at 3 over its right (a pet without mana: health alone), bent along its rim a little inside it,
    -- read bottom to top; yours' style, shown as yours are (hover, sphereValuesAlways).
    p.over = child(p, 8)
    p.over.mana = numbers(p.over, p, math.pi, rb - PET.valueInset.mana, -1, rb, PET.valueSpacing, PET.valueShift)
    p.over.health = numbers(p.over, p, 0, rb - PET.valueInset.health, 1, rb, PET.valueSpacing, PET.valueShift)
    p:SetScript("OnEnter", function(self)
        self.valueHover = true
        S.UpdateValueVisibility()
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, A.TooltipAnchor(self))
        GameTooltip:SetUnit("pet")
        local mood = self.moodLevel and _G["PET_HAPPINESS" .. self.moodLevel]
        if type(mood) == "string" then GameTooltip:AddLine(mood, 1, 0.82, 0) end
        GameTooltip:AddLine("Right-click for pet options", 0.8, 0.7, 0.5)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function(self)
        self.valueHover = false
        S.UpdateValueVisibility()
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    -- the hole in your health and mana while the orb shows (the unit watch shows it, in combat too)
    p:SetScript("OnShow", function() S.SetPetHole(true) end)
    p:SetScript("OnHide", function() S.SetPetHole(false) end)
    if RegisterUnitWatch then RegisterUnitWatch(p) end -- out of combat: built at login
    p.events = CreateFrame("Frame")
    pcall(p.events.RegisterEvent, p.events, "UNIT_PET")
    -- Retail removed pet happiness and its event; Forever still reports it for Hunters.
    pcall(p.events.RegisterEvent, p.events, "UNIT_HAPPINESS")
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
            "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        if p.events.RegisterUnitEvent then pcall(p.events.RegisterUnitEvent, p.events, e, "pet")
        else pcall(p.events.RegisterEvent, p.events, e) end
    end
    p.events:SetScript("OnEvent", function(_, event, who)
        if event == "UNIT_PET" then
            if who ~= "player" then return end
        elseif event ~= "UNIT_HAPPINESS" and who ~= nil and who ~= "pet" then
            return
        end
        S.UpdatePet()
    end)
    return p
end

-- Without a pet, non-mana power occupies the same embedded ball. It has no unit button:
-- the whole left sphere continues to target the player.
local function buildInnerPower(left)
    local rb = BALL / 2 * PET.r
    local p = CreateFrame("Frame", nil, hud)
    p:SetFrameLevel(hud:GetFrameLevel() + 13)
    p:SetSize(2 * rb, 2 * rb)
    p:SetPoint("CENTER", left, "CENTER", PET.at[1], PET.at[2])
    p:EnableMouse(false)
    p.contactBase = contactBase(p, rb)
    p.bar = buildLiquid(p, "mana", "Pet",
        { w = 2 * rb, h = 2 * rb, x = 0, scale = 2 * rb / BALL, unit = PET.r, flat = true })
    p.glass = child(p, 6)
    p.glass.texture = p.glass:CreateTexture(nil, "ARTWORK")
    p.glass.texture:SetTexture(MEDIA .. "GlassPet")
    p.glass.texture:SetAllPoints(p.bar)
    p.over = child(p, 7)
    -- at 5 o'clock, on a circle round the ball's own centre (the same gap to its rim end to end)
    local r = rb - PET.valueInset.health
    p.over.value = numbers(p.over, p, math.rad(-60), r, 1, r, PET.valueSpacing, { 0, S.ORB_TEXT_Y }, true)
    p:Hide()
    return p
end

-------------------------------------------------------------------------------
-- Cracked glass (0.5.457)
-------------------------------------------------------------------------------
-- A big blow cracks the glass of your health, and of your pet's (the player's: "the health container
-- should crack ... This should happen for pet health too"; in the liquid simulator first). Opt-in:
-- the crackedGlass setting, off by default (0.5.466: "crack can also be an opt-in feature"). From a
-- place anywhere on the health's glass, at random (0.5.467, the player's: "crack better be random
-- start place, that's way it's less complicated and now its always starting at top"; 0.5.463-0.5.466
-- broke near the health's top line, found through hidden status bars and curves), it grows toward
-- the side with more room (0.5.465: "if the crack happens in the middle, the crack should grow equal
-- side, if close to right, it should grow towards left"), a little out toward a near edge, in
-- CRACK.grow s; it holds CRACK.hold s, then mends in CRACK.restore s, drawing back into the point it
-- broke from. Three sizes (0.5.467: "25% dmg can be small and 40% can be large and 60% can be even
-- bigger crack"; 0.5.462-0.5.466: 34% and 55%): each blow's crack is drawn three times, the small and
-- large ones parts of the huge one (CRACK.sizes). Each crack is new (math.random): branches running
-- straight, kinking now and then and forking, splinters round the impact, web rings across the
-- branches and a crushed spot (CrackImpact). A branch that reaches the scoop round an inner sphere
-- bends along its rim (0.5.464: "it should also warp with the cutouts structure"; the mask,
-- CrackCavity, cuts what's left in it). Every line is Media/CrackLine mapped onto its segment by
-- texture coordinates: laid out once when it cracks, its growing and mending only move those (the
-- texture's end columns are empty, so past the front there is nothing). Under the glass, cut to the
-- piece's shape (bar.maskFile) and, as the liquids are, round the embedded sphere (o.holes).
-- Lengths are shares of the ball's radius, widths units (the pet's times `petWidth`).
-- Forever hides your health's maximum (and often a blow's amount), and a hidden value can't be
-- compared in Lua. So the game compares them: each crack has a horizontal status bar (`gate`) for
-- each size, GATE units wide, fed the blow out of the maximum, its fill reaching past the glass's
-- right edge at its share: past the glass only for a blow of that share or more (within the glass's
-- width / GATE under it, in part). Each size is drawn in a clip frame over its gate's fill
-- holding one over the next size's gate's unfilled part (the huge one: its fill alone), so the game
-- shows one of them, or none. Every hidden blow takes a crack (unseen when small): CRACK.pool of
-- them, the oldest taken over when all are busy. Plain values go through the gates as well (under
-- the small share: no crack).
local CRACK = { grow = 0.5, hold = 3, restore = 2,
    -- the sizes: the share of the maximum a blow must pass, the lines drawn (of the huge crack's:
    -- `reach` its branches' lines out to that far, on `spokes` of them; the huge one all), how light,
    -- its crushed spot's size
    sizes = {
        { share = 0.25, lines = 32, reach = { 0.20, 0.30 }, spokes = { 2, 3 }, dim = 0.8, impact = 0.75 },
        { share = 0.40, lines = 64, reach = { 0.42, 0.55 }, dim = 1, impact = 1 },
        { share = 0.60, lines = 96, dim = 1, impact = 1.25 },
    },
    inset = 0.08,                -- where it breaks: at least this far in from the glass's edge, the seam, the scoop
    width = 10, petWidth = 0.8,  -- CrackLine's section at the impact (its light core about 1/15 of it)
    impact = 15,                 -- Media/CrackImpact across (units), the crushed spot where it broke
    taper = 0.4,                 -- a branch this much narrower at its end (thinner broke into dashes)
    light = { -0.6, 0.8 },       -- where the glass's light comes from: each line's lit side faces it
    -- how light a line is (its vertex colour): full at the impact, `tip` at the far ends, falling
    -- off by `falloff`; darker away from the light (`shade` of it at the far side); and each line
    -- catches the light `bright` (its alpha). 0.5.457 (no vertex colour): "too bright, only the core
    -- can be this bright but the edges can be darker"; 0.5.458 (tip 0.2, falloff 2.2, shade 0.35 and
    -- dark sides): "made too dark"; 0.5.459 (tip 0.38): "still too dark ... initial numbers and tone
    -- that down a little" (0.5.460: 0.5.457's line, these over it)
    tip = 0.65, falloff = 1.2, shade = 0.15, bright = { 0.5, 0.9 },
    -- branches: how many, degrees either side of the way they go, length; their steps, a slight
    -- wander each and now and then a kink (glass breaks straight, then turns); forks; steps bent
    -- along a scoop's rim
    inward = { 5, 7 }, spread = 75, reach = { 0.55, 0.95 },
    step = { 0.07, 0.13 }, wander = 6, kink = 0.3, kinkAngle = { 12, 30 },
    fork = 0.3, forkAngle = { 20, 45 }, forkReach = { 0.3, 0.6 }, hug = { 2, 4 },
    outward = { 1, 2 }, outReach = { 0.07, 0.15 },
    splinters = { 7, 10 }, splinterReach = { 0.02, 0.06 },
    -- the rings across neighbouring branches (a web round the impact): how far out, how likely
    rings = { { 0.08, 0.12, 0.85 }, { 0.20, 0.28, 0.6 }, { 0.38, 0.48, 0.45 } }, ringBend = 0.25, ringGap = 80,
    pool = 3 }                   -- cracks on a glass at once
local GATE = 40000 -- a gate's width (units): blows within the glass's width / GATE under a share show in part
local cracksPlain, cracksHidden = 0, 0 -- /spheres debug: blows with plain values that cracked, hidden blows
local buildCracks
do -- (the main chunk's 200 locals)
local CRACK_U0, CRACK_U1 = 1.5 / 64, 62.5 / 64 -- CrackLine's first and last lit columns' centres
local CRACK_END = 0 -- each line runs past its ends this share of its width (0.05 lit knots at the joints)
local LINES = CRACK.sizes[#CRACK.sizes].lines
local crackDriver, crackVessels = nil, {}

local function randomIn(r) return r[1] + math.random() * (r[2] - r[1]) end
local function randomCount(r) return math.random(r[1], r[2]) end

-- One line from x0, y0 to x1, y1 `s` along the crack from where it broke, in sizes from `size` up.
-- False once it's full.
local function crackSegment(c, x0, y0, x1, y1, w, s, size)
    local n = c.count + 1
    if n > LINES then return false end
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-4 then return true end
    c.count = n
    local g = c.lines[n]
    g.x0, g.y0, g.dx, g.dy, g.len, g.w, g.s, g.size = x0, y0, dx / len, dy / len, len, w, s, size
    if s + len > c.reach then c.reach = s + len end
    return true
end

-- The smallest size a line `s` out on a branch is in: the small one's out to `small` (0: none), the
-- large one's out to c.largeReach.
local function sizeAt(c, s, small)
    if s < small then return 1 end
    if s < c.largeReach then return 2 end
    return 3
end

-- A branch from x, y (from where it broke) heading `angle` (radians) for `length`, in steps that
-- wander, forking on the way; it ends at the glass's edge (`out`: past it, the mask cuts it) and
-- bends along a scoop's rim (c.scoop) for a few steps; in the small crack out to `small`.
local function crackBranch(c, x, y, angle, length, w, s, depth, out, small)
    local gone, wander, hug = 0, math.rad(CRACK.wander), 0
    local w0 = w
    while length - gone > 0.004 do
        local step = math.min(length - gone, randomIn(CRACK.step))
        angle = angle + (math.random() * 2 - 1) * wander
        if gone > 0 and hug == 0 and math.random() < CRACK.kink then
            angle = angle + (math.random() < 0.5 and -1 or 1) * math.rad(randomIn(CRACK.kinkAngle))
        end
        local nx, ny = x + step * math.cos(angle), y + step * math.sin(angle)
        local ax, ay = c.x + nx, c.y + ny -- from the ball's centre
        if not out and ax * ax + ay * ay > 0.96 then return end
        if c.scoop then -- at the scoop: along its rim a few steps, the way it was going (the cutout's curve)
            local dx, dy = ax - c.sx, ay - c.sy
            local d = math.sqrt(dx * dx + dy * dy)
            if d < c.sr or hug > 0 then
                if d < 1e-4 then return end
                local tx, ty = -dy / d, dx / d
                if tx * math.cos(angle) + ty * math.sin(angle) < 0 then tx, ty = -tx, -ty end
                nx, ny = c.sx + dx / d * c.sr - c.x, c.sy + dy / d * c.sr - c.y
                angle = math.atan2(ty, tx)
                if hug > 0 then hug = hug - 1 else hug = randomCount(CRACK.hug) end
            end
        end
        if not crackSegment(c, x, y, nx, ny, w, s, sizeAt(c, s, small)) then return end
        local moved = math.sqrt((nx - x) ^ 2 + (ny - y) ^ 2)
        gone, s, x, y = gone + step, s + moved, nx, ny
        w = w0 * (1 - CRACK.taper * math.min(1, gone / length))
        if depth < 2 and length - gone > 0.08 and math.random() < CRACK.fork then
            local side = math.random() < 0.5 and -1 or 1
            crackBranch(c, x, y, angle + side * math.rad(randomIn(CRACK.forkAngle)),
                (length - gone) * randomIn(CRACK.forkReach), w * 0.85, s, depth + 1, out, small)
        end
    end
end

-- Whether x, y (from where it broke) is in the scoop round an inner sphere (c.scoop).
local function inScoop(c, x, y)
    return c.scoop and (c.x + x - c.sx) ^ 2 + (c.y + y - c.sy) ^ 2 < c.sr * c.sr or false
end

-- Where a branch from the impact (its lines first..last) is `d` along it, for the ring.
local function crackAlong(c, first, last, d)
    for i = first, last do
        local g = c.lines[i]
        if g.s + g.len >= d then
            local t = math.max(0, d - g.s)
            return g.x0 + g.dx * t, g.y0 + g.dy * t
        end
    end
end

-- A new crack's lines, in shares of the radius round where it broke (0, 0), `across` (0-1) of the
-- way from the glass's left edge to its right there: its branches toward the side with more room
-- (from the middle, as many each way), longer the more room; one or two short ones out toward a near
-- edge. The huge crack's; each line in the sizes from its own up.
local function crackLines(c, across)
    c.count, c.reach = 0, 0
    local x, y = 0, 0
    local w = c.width
    c.largeReach = randomIn(CRACK.sizes[2].reach)
    for _ = 1, randomCount(CRACK.splinters) do
        local t, l = math.random() * 2 * math.pi, randomIn(CRACK.splinterReach)
        crackSegment(c, x, y, x + l * math.cos(t), y + l * math.sin(t), w * 0.7, 0, 1)
    end
    -- the branches, each a spoke for the ring (its first line, its last, its heading): the first
    -- `rights` to the right, the rest to the left, then out; the small crack's on spokes from..to
    local first, last, heading, n = c.first, c.last, c.heading, 0
    local inward = randomCount(CRACK.inward)
    local rights = math.max(0, math.min(inward, math.floor(inward * (1 - across) + math.random())))
    local outward = math.abs(across - 0.5) > 0.3 and randomCount(CRACK.outward) or 0
    local a = across < 0.5 and math.pi or 0 -- the way out, toward the nearer edge
    c.across, c.inward, c.rights = across, inward, rights
    local smalls = math.min(inward, randomCount(CRACK.sizes[1].spokes))
    local from = math.random(1, inward - smalls + 1)
    local to, reach = from + smalls - 1, randomIn(CRACK.sizes[1].reach)
    for i = 1, inward + outward do
        n, first[i] = i, c.count + 1
        local small = ((i >= from and i <= to) or i == inward + 1) and reach or 0
        if i <= inward then
            local right = i <= rights
            local m, k = right and rights or inward - rights, right and i or i - rights
            local part = (k - 0.5) / m * 2 - 1 -- -1..1 across the spread
            heading[i] = (right and 0 or math.pi) + math.rad(CRACK.spread) * (part + (math.random() - 0.5) / m)
            local room = right and 1 - across or across
            crackBranch(c, x, y, heading[i], randomIn(CRACK.reach) * (0.4 + 0.6 * room), w, 0, 0, false, small)
        else
            heading[i] = a + math.rad((math.random() * 2 - 1) * 40)
            crackBranch(c, x, y, heading[i], randomIn(CRACK.outReach), w * 0.8, 0, 1, true, small)
        end
        last[i] = c.count
    end
    -- the rings: across neighbouring spokes, each crossing bent once at its middle
    for _, ring in ipairs(CRACK.rings) do
        local d = ring[1] + math.random() * (ring[2] - ring[1])
        for i = 1, n do
            local best, gap = nil, math.rad(CRACK.ringGap)
            for j = 1, n do -- the next spoke round, counter-clockwise
                local turn = (heading[j] - heading[i]) % (2 * math.pi)
                if j ~= i and turn > 0 and turn < gap then best, gap = j, turn end
            end
            if best and math.random() < ring[3] then
                local x0, y0 = crackAlong(c, first[i], last[i], d * (0.9 + 0.2 * math.random()))
                local x1, y1 = crackAlong(c, first[best], last[best], d * (0.9 + 0.2 * math.random()))
                local mx, my
                if x0 and x1 then
                    local bend = (math.random() * 2 - 1) * CRACK.ringBend
                    mx, my = (x0 + x1) / 2 - (y1 - y0) * bend, (y0 + y1) / 2 + (x1 - x0) * bend
                end
                if mx and not (inScoop(c, mx, my) or inScoop(c, (x0 + mx) / 2, (y0 + my) / 2)
                        or inScoop(c, (mx + x1) / 2, (my + y1) / 2)) then -- none across a scoop
                    local half = math.sqrt((mx - x0) ^ 2 + (my - y0) ^ 2)
                    local size = sizeAt(c, d, (d < reach and i >= from and i <= to and best >= from and best <= to) and reach or 0)
                    crackSegment(c, x0, y0, mx, my, w * 0.65, d, size)
                    crackSegment(c, mx, my, x1, y1, w * 0.65, d + half, size)
                end
            end
        end
    end
end

-- One line's texture in a drawing of the crack (r: one size) over the line's box.
local function layLine(r, j, g, x0, y0, x1, y1, k)
    local t = r.textures[j]
    t:ClearAllPoints()
    t:SetSize(x1 - x0, y1 - y0)
    t:SetPoint("CENTER", r.anchor, "CENTER", (x0 + x1) / 2, (y0 + y1) / 2)
    t:SetVertexColor(k, k, k)
    t:SetAlpha(g.bright * r.dim)
    t:Hide()
    r.shown[j] = false
end

-- Its crushed spot, `size` across at the impact, turned at random.
local function layImpact(r, size)
    r.impact:ClearAllPoints()
    r.impact:SetSize(size, size)
    r.impact:SetPoint("CENTER", r.anchor, "CENTER")
    r.impact:SetAlpha(r.dim)
    r.impact:Show()
    local turn = math.random() * 2 * math.pi
    r.cos, r.sin, r.impactGrow, r.alpha = math.cos(turn), math.sin(turn), size, 1
end

-- Lay a crack's lines out on its glass (once a crack): where each line's corners fall along and
-- across it (for the coordinates the front sets, drawCrack), and each size's textures over them.
local function layCrack(c, radius)
    local drawings = c.drawings
    for _, r in ipairs(drawings) do r.n, r.reach = 0, 0 end
    for i = 1, c.count do
        local g = c.lines[i]
        local w, len = g.w, g.len * radius
        local e = w * CRACK_END
        local ax, ay = g.x0 * radius - g.dx * e, g.y0 * radius - g.dy * e -- its start, run back
        local bx, by = ax + g.dx * (len + 2 * e), ay + g.dy * (len + 2 * e)
        local nx, ny = -g.dy * w / 2, g.dx * w / 2
        -- its lit side (CrackLine's v over 0.5, toward the line's left) toward the light
        local lit = (-g.dy * CRACK.light[1] + g.dx * CRACK.light[2]) >= 0 and 1 or -1
        local x0, x1 = math.min(ax, bx) - math.abs(nx), math.max(ax, bx) + math.abs(nx)
        local y0, y1 = math.min(ay, by) - math.abs(ny), math.max(ay, by) + math.abs(ny)
        -- corners UL, LL, UR, LR: along the line from its run-back start, and across it in sections
        local i8 = 0
        for k = 1, 4 do
            local cx = (k <= 2) and x0 or x1
            local cy = (k % 2 == 1) and y1 or y0
            local px, py = cx - ax, cy - ay
            g[i8 + 1] = px * g.dx + py * g.dy
            g[i8 + 2] = 0.5 + lit * (py * g.dx - px * g.dy) / w
            i8 = i8 + 2
        end
        g.unitLen, g.unitS, g.ends = len, g.s * radius, 2 * e
        -- light near the impact and towards the light, dark further out
        local along = (g.s + g.len / 2) / math.max(c.reach, 1e-4)
        local mx, my = c.x + g.x0 + g.dx * g.len / 2, c.y + g.y0 + g.dy * g.len / 2
        local toLight = 0.5 + 0.5 * math.max(-1, math.min(1, mx * CRACK.light[1] + my * CRACK.light[2]))
        local k = (CRACK.tip + (1 - CRACK.tip) * (1 - math.min(1, along)) ^ CRACK.falloff)
            * (1 - CRACK.shade * (1 - toLight))
        g.bright = randomIn(CRACK.bright)
        for size, r in ipairs(drawings) do
            if g.size <= size and r.n < CRACK.sizes[size].lines then
                r.n = r.n + 1
                r.line[r.n] = i
                layLine(r, r.n, g, x0, y0, x1, y1, k)
                if g.s + g.len > r.reach then r.reach = g.s + g.len end
            end
        end
    end
    local spot = c.width / CRACK.width * CRACK.impact
    for size, r in ipairs(drawings) do
        for j = r.n + 1, CRACK.sizes[size].lines do r.textures[j]:Hide() end
        layImpact(r, spot * CRACK.sizes[size].impact)
    end
end

-- A drawing's lines as far as its front has come (units from the impact), at `alpha`. The crushed
-- spot grows with the front's first units and shrinks with its last (turned and sized by texture
-- coordinates: past the texture, its empty edge).
local function drawCrack(c, r, front, alpha)
    local k = math.max(0.05, math.min(1, front / r.impactGrow))
    local cs, sn = 0.5 * r.cos / k, 0.5 * r.sin / k
    r.impact:SetTexCoord(0.5 - cs + sn, 0.5 - sn - cs, 0.5 - cs - sn, 0.5 - sn + cs,
        0.5 + cs + sn, 0.5 + sn - cs, 0.5 + cs - sn, 0.5 + sn + cs)
    if alpha ~= r.alpha then r.impact:SetAlpha(alpha * r.dim) end
    for j = 1, r.n do
        local g, t = c.lines[r.line[j]], r.textures[j]
        local shown = front > g.unitS
        if shown ~= r.shown[j] then
            r.shown[j] = shown
            t:SetShown(shown)
        end
        if shown then
            local du = (CRACK_U1 - CRACK_U0) / (math.min(g.unitLen, front - g.unitS) + g.ends)
            t:SetTexCoord(CRACK_U0 + g[1] * du, g[2], CRACK_U0 + g[3] * du, g[4],
                CRACK_U0 + g[5] * du, g[6], CRACK_U0 + g[7] * du, g[8])
            if alpha ~= r.alpha then t:SetAlpha(alpha * g.bright * r.dim) end
        end
    end
    r.alpha = alpha
end

-- Its timeline: growing (ease out), holding, mending (ease in and out) back into the impact, its
-- last quarter fading; every size, each over its own reach (the game shows one, or none). False
-- once it's over.
local function stepCrack(c, elapsed)
    c.time = c.time + elapsed
    local t = c.time
    local share, alpha = 1, 1
    if t < CRACK.grow then
        local p = 1 - t / CRACK.grow
        share = 1 - p * p * p
    elseif t < CRACK.grow + CRACK.hold then
        if c.whole then return true end -- held: drawn whole once
        c.whole = true
    else
        local p = (t - CRACK.grow - CRACK.hold) / CRACK.restore
        if p >= 1 then return false end
        share, alpha = 1 - p * p * (3 - 2 * p), math.min(1, (1 - p) * 4)
    end
    for _, r in ipairs(c.drawings) do drawCrack(c, r, r.reach * c.radius * share, alpha) end
    return true
end

local function stopCrack(c)
    c.time = false
    for _, r in ipairs(c.drawings) do
        for _, t in ipairs(r.textures) do t:Hide() end
        r.impact:Hide()
    end
end

-- A gate (see CRACK): a status bar whose fill reaches past the glass's right edge at `share`, open (1
-- of 1) till a blow is fed into it (so a blow of exactly the share shows; a little under, in part).
local function crackGate(vessel, radius, share)
    local gate = CreateFrame("StatusBar", nil, vessel)
    gate:SetSize(GATE, 2 * radius + 2)
    gate:SetPoint("LEFT", vessel, "CENTER", radius + 1 - share * GATE, 0)
    gate:SetOrientation("HORIZONTAL")
    gate:SetStatusBarTexture(MEDIA .. "FillNone")
    gate:SetMinMaxValues(0, 1)
    gate:SetValue(1)
    gate:EnableMouse(false)
    return gate
end

-- A clip frame under the glass (0.5.458, the player's: "it should be behind the shadow layer no?":
-- its shading, edge shadow and highlights over the crack, which is in it; over the liquid).
local function crackClip(parent, glass)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(glass:GetFrameLevel() - 1)
    f:EnableMouse(false)
    f:SetClipsChildren(true)
    return f
end

-- A drawing of the crack in frame `f` round `anchor`: `lines` textures, a crushed spot, its masks.
local function crackDrawing(vessel, anchor, f, holes, lines, dim)
    local r = { vessel = vessel, anchor = anchor, frame = f, textures = {}, line = {}, shown = {}, n = 0, reach = 0,
        dim = dim, alpha = 1, cos = 1, sin = 0, impactGrow = 1 }
    r.mask = f:CreateMaskTexture()
    if holes then r.hole = holeMask(f, vessel, holes, "CrackCavity") end -- it stops at the scoop
    for j = 1, lines do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetTexture(MEDIA .. "CrackLine", "CLAMP", "CLAMP")
        t:AddMaskTexture(r.mask)
        if r.hole then t:AddMaskTexture(r.hole) end
        t:Hide()
        r.textures[j], r.line[j], r.shown[j] = t, 0, false
    end
    r.impact = f:CreateTexture(nil, "OVERLAY", nil, 7)
    r.impact:SetTexture(MEDIA .. "CrackImpact", "CLAMP", "CLAMP")
    r.impact:AddMaskTexture(r.mask)
    if r.hole then r.impact:AddMaskTexture(r.hole) end
    r.impact:Hide()
    return r
end

-- A glass's cracks (CRACK.pool), drawn under `glass` round `vessel`'s centre, its ball `radius`;
-- `holes`: masks of its own round the embedded sphere, as the liquids have. Without clipping (not in
-- this client) nothing could judge a blow: none.
function buildCracks(vessel, glass, radius, holes)
    local cracks = {}
    vessel.cracks = cracks
    if not glass.SetClipsChildren then return end
    for k = 1, CRACK.pool do
        -- every field made now: a crack makes no tables (nor grows them) when it breaks or moves
        local c = { vessel = vessel, lines = {}, count = 0, reach = 0, largeReach = 0, width = 0,
            radius = radius, time = false, whole = false, x = 0, y = 0, across = 0, inward = 0, rights = 0,
            scoop = false, sx = 0, sy = 0, sr = 0, gates = {}, drawings = {},
            first = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, last = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
            heading = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }
        for i = 1, LINES do
            c.lines[i] = { 0, 0, 0, 0, 0, 0, 0, 0, x0 = 0, y0 = 0, dx = 0, dy = 0, len = 0, w = 0, s = 0,
                unitLen = 0, unitS = 0, ends = 0, bright = 1, size = 1 }
        end
        c.anchor = CreateFrame("Frame", nil, vessel) -- where it broke
        c.anchor:SetSize(1, 1)
        c.anchor:EnableMouse(false)
        for size, def in ipairs(CRACK.sizes) do c.gates[size] = crackGate(vessel, radius, def.share) end
        -- each size over its gate's fill and the next size's gate's unfilled part
        for size, def in ipairs(CRACK.sizes) do
            local f = crackClip(vessel, glass)
            f:SetAllPoints(c.gates[size]:GetStatusBarTexture())
            local next = c.gates[size + 1]
            if next then
                local below = crackClip(f, glass)
                below:SetPoint("TOPLEFT", next:GetStatusBarTexture(), "TOPRIGHT")
                below:SetPoint("BOTTOMRIGHT", next, "BOTTOMRIGHT")
                f = below
            end
            c.drawings[size] = crackDrawing(vessel, c.anchor, f, holes, def.lines, def.dim)
        end
        cracks[k] = c
    end
    if not crackDriver then
        crackDriver = CreateFrame("Frame", nil, hud)
        crackDriver:Hide()
        crackDriver:SetScript("OnUpdate", A.Timed("cracks", function(self, elapsed)
            local any = false
            for _, v in ipairs(crackVessels) do for _, c in ipairs(v.cracks) do
                if c.time then
                    if stepCrack(c, elapsed or 0) then any = true else stopCrack(c) end
                end
            end end
            if not any then self:Hide() end
        end))
    end
    crackVessels[#crackVessels + 1] = vessel
    vessel.crackDriver = crackDriver -- (the harness runs it)
end

-- Where a crack breaks on `bar`'s glass (its box over the ball, `radius`; shares of it from the
-- ball's centre): anywhere on it at random, CRACK.inset in from its edge, the seam and the scoop
-- (`scoop`: centre and radius, or nil); and `across` (0-1): how far from the glass's left edge
-- (or the scoop's right) to its right (or the scoop's left) it is there.
local function crackPlace(bar, radius, scoop, sx, sy, sr)
    local left, right = (bar.centreX - bar.width / 2) / radius, (bar.centreX + bar.width / 2) / radius
    local inset = CRACK.inset
    local x, y = (left + right) / 2, 0
    for _ = 1, 40 do
        local tx, ty = left + inset + math.random() * (right - left - 2 * inset), (math.random() * 2 - 1) * (1 - inset)
        local inGlass = tx * tx + ty * ty < (1 - inset) ^ 2
        if inGlass and not (scoop and (tx - sx) ^ 2 + (ty - sy) ^ 2 < (sr + inset) ^ 2) then
            x, y = tx, ty
            break
        end
    end
    local half = math.sqrt(math.max(0, 1 - y * y))
    local lo, hi = math.max(-half, left), math.min(half, right)
    if scoop and math.abs(y - sy) < sr then -- the scoop is a wall too
        local chord = math.sqrt(sr * sr - (y - sy) ^ 2)
        if x < sx then hi = math.min(hi, sx - chord) else lo = math.max(lo, sx + chord) end
    end
    return x, y, hi > lo and math.max(0, math.min(1, (x - lo) / (hi - lo))) or 0.5
end

-- Crack `who`'s health glass ("player" or "pet") for a blow of `amount` out of `max` (hidden, or
-- not; none: a full one), the game judging which size shows: a new crack, in the oldest's place if
-- all are busy.
function S.Crack(who, amount, max)
    local o = spheres.left
    if not o then return end
    local vessel, bar, radius, width = o, nil, BALL / 2, CRACK.width
    if who == "pet" then
        vessel = o.pet
        if not vessel:IsShown() then return end
        bar = vessel.health:IsShown() and vessel.health or vessel.whole
        radius, width = BALL / 2 * PET.r, width * CRACK.petWidth
    else
        bar = o.innerPowerActive and o.wholeHealth or o.health
    end
    local c
    for _, k in ipairs(vessel.cracks) do
        if not k.time then c = k break end
        if not c or k.time > c.time then c = k end
    end
    if not c then return end
    if not secret(amount) and amount == nil then amount, max = 1, 1 end -- (a hidden value is never compared)
    for _, gate in ipairs(c.gates) do
        gate:SetMinMaxValues(0, max)
        gate:SetValue(amount)
    end
    for _, r in ipairs(c.drawings) do
        r.mask:SetTexture(bar.maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        r.mask:ClearAllPoints()
        r.mask:SetAllPoints(bar)
    end
    -- where it breaks; on yours round the scoop of an inner sphere while there is one
    c.scoop = vessel == o and o.holed or false
    c.sx, c.sy, c.sr = PET.at[1] / radius, PET.at[2] / radius, (BALL / 2 * PET.r + PET.bowl) / radius
    local x, y, across = crackPlace(bar, radius, c.scoop, c.sx, c.sy, c.sr)
    c.x, c.y = x, y
    c.anchor:ClearAllPoints()
    c.anchor:SetPoint("CENTER", vessel, "CENTER", x * radius, y * radius)
    c.width, c.radius, c.time, c.whole = width, radius, 0, false
    crackLines(c, across)
    layCrack(c, radius)
    crackDriver:Show()
end

-- Cracked glass is opt-in (0.5.466, the player's: "crack can also be an opt-in feature"): the
-- crackedGlass setting, off by default; off, blows crack nothing.
local function cracksOn() return ns.db ~= nil and ns.db.crackedGlass == true end

-- A blow to `who` for `amount` (UNIT_COMBAT's WOUND): a crack the game judges (see CRACK). Plain
-- values under the small crack's share of the maximum take none.
function S.Wound(who, amount)
    if not cracksOn() then return end
    if not secret(amount) and amount == nil then return end -- (a hidden value is never compared)
    local ok, max = pcall(UnitHealthMax, who)
    if not ok or (not secret(max) and max == nil) then return end
    if num(amount) and num(max) then
        if max <= 0 or amount < CRACK.sizes[1].share * max then return end
        cracksPlain = cracksPlain + 1
    else
        cracksHidden = cracksHidden + 1
    end
    S.Crack(who, amount, max)
end
end
S.CRACK = CRACK

-- Every frame (the left orb's OnUpdate; and tools/sim_bridge.lua, the simulator, runs this same
-- code): the slosh (Motion.lua) first, what you did this frame, then each shown liquid: its surge,
-- its springs (its clock runs faster while it churns), its layers, surface, climb and glints.
-- `follows`: another set of liquids in the same frame (the target sphere's): the clock and what you
-- did are the left orb's, taken once.
local motionTime = 0
local function animateLiquids(liquids, elapsed, follows)
    local M = ns.Motion
    elapsed = elapsed or 0
    local on = sloshOn()
    if not follows then
        motionTime = motionTime + elapsed
        liquidClock = motionTime
        if on then M.Sample(elapsed) end
    end
    for _, bar in ipairs(liquids) do if bar:IsVisible() then
        local rise = riseOf(bar, elapsed)
        local hL, hR, amp, shift, lift, swirl = 0, 0, 1, 0, 0, 0
        if on then
            bar.clock = bar.clock + M.Step(bar, elapsed)
            hL, hR, amp, shift, lift, swirl = M.Shape(bar)
        else
            bar.clock = bar.clock + elapsed
        end
        bar.sloshShift, bar.sloshLift = shift, lift
        for _, layer in ipairs(bar.motion) do moveLayer(bar, layer, bar.clock, rise, shift, lift, swirl) end
        moveSurface(bar, bar.clock, hL, hR, amp)
        movePile(bar, hL, hR)
        for _, g in ipairs(bar.glints) do moveGlint(bar, g, elapsed) end
    end end
end

local function buildLeft()
    local o = orbFrame("left")
    o.holes = {}
    o.health = buildLiquid(o, "health", "Health", nil, o.holes)
    o.power = buildLiquid(o, "mana", "Mana", nil, o.holes)
    o.wholeHealth = buildLiquid(o, "health", "Whole",
        { w = BALL, h = BALL, x = 0, scale = 1, unit = 1, clock = "whole" }, o.holes)
    buildHeals(o, o.wholeHealth)
    o.wholeHeal, o.wholeHealBand = o.heal, o.healBand
    buildHeals(o, o.health)
    o.pet = buildPet(o) -- not in `spheres`: hubs dock round the two orbs only
    o.innerPower = buildInnerPower(o)
    -- Every frame: the layers' motion is slow, a coarser step showed as a stutter. Only what shows.
    local liquids = { o.health, o.power, o.wholeHealth, o.innerPower.bar, o.pet.whole, o.pet.health, o.pet.mana }
    o.liquids = liquids
    o:SetScript("OnUpdate", A.Timed("liquids", function(_, elapsed) animateLiquids(liquids, elapsed) end))
    setColor(o.health, COLORS.HEALTH)
    setColor(o.wholeHealth, COLORS.HEALTH)
    setColor(o.power, COLORS.MANA)
    local hw, hh, hx = box("health")
    local mw, mh, mx = box("mana")
    local gh = glassOver(o, "GlassHealth", hw, hh, hx)
    local gm = glassOver(o, "GlassMana", mw, mh, mx)
    local gw = glassOver(o, "GlassWhole", BALL, BALL, 0)
    o.glassHealth, o.glassMana = gh, gm
    o.wholeHealth.glass = gw
    o.health.glass, o.power.glass = gh, gm
    o.wholeHealth:Hide()
    o.wholeHealth.surface:Hide()
    if o.wholeHealth.clip then o.wholeHealth.clip:Hide() end
    gw:Hide()
    o.wholeHeal:Hide()
    -- the scoop's concave walls, over both pieces' glass (S.SetPetHole)
    local rb = BALL / 2 * PET.r
    o.bowl = o.glass:CreateTexture(nil, "OVERLAY")
    o.bowl:SetTexture(MEDIA .. "PetBowl")
    o.bowl:SetSize(2 * (rb + PET.bowl), 2 * (rb + PET.bowl))
    o.bowl:SetPoint("CENTER", o, "CENTER", PET.at[1], PET.at[2])
    o.bowl:Hide()
    buildCracks(o, o.glass, BALL / 2, o.holes)
    buildCracks(o.pet, o.pet.glass, BALL / 2 * PET.r)
    -- the numbers, while the mouse is over it (hidden values: the game draws them)
    o.over = child(o, 7)
    o.over.health = numbers(o.over, o, HEALTH_ANGLE, HEALTH_RADIUS, -1, nil, nil, { 0, S.ORB_TEXT_Y })
    o.over.power = numbers(o.over, o, math.rad(-45), EDGE_LABEL * math.sqrt(2) - S.ORB_INNER_TEXT,
        1, nil, nil, { 0, S.ORB_TEXT_Y })
    o.healNotice = notice(o.over, o, "heal")
    o.damageNotice = notice(o.over, o, "damage")
    -- Both states use the same engraved well. Keep them outside the secure player button
    -- so combat can swap the display without changing protected attributes or anchors.
    o.levelBadge = CreateFrame("Frame", nil, hud)
    o.levelBadge:SetFrameLevel(hud:GetFrameLevel() + 16)
    o.levelBadge:SetSize(27, 27)
    o.levelBadge:SetPoint("CENTER", art.frameAnchor, "BOTTOM", S.SocketOffset("left"))
    o.levelBadge:EnableMouse(false)
    o.levelRing = o.levelBadge:CreateTexture(nil, "ARTWORK")
    o.levelRing:SetTexture(MEDIA .. "MenuLatencyRing")
    o.levelRing:SetSize(26, 26)
    o.levelRing:SetPoint("CENTER")
    if finishSuffix() == "Modern" then o.levelRing:SetVertexColor(0.62, 0.68, 0.74)
    else o.levelRing:SetVertexColor(0.80, 0.62, 0.36) end
    o.levelRing:SetBlendMode("BLEND")
    o.levelRing:SetAlpha(0.55)
    o.levelText = o.levelBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    o.levelText:SetPoint("CENTER")
    o.levelText:SetTextColor(0.92, 0.81, 0.59)
    o.levelText:SetShadowColor(0, 0, 0, 0.9)
    o.levelText:SetShadowOffset(1, -1)
    local levelFont, _, levelFlags = o.levelText:GetFont()
    if levelFont then o.levelText:SetFont(levelFont, 11, levelFlags or "") end

    -- The resting bubble sits at the level's corner; its warm halo belongs around
    -- the engraved level well, behind the number.
    local stateIcon = "Interface\\CharacterFrame\\UI-StateIcon"
    o.restHalo = CreateFrame("Frame", nil, hud)
    o.restHalo:SetFrameLevel(hud:GetFrameLevel() + 15)
    o.restHalo:SetSize(30, 30)
    o.restHalo:SetPoint("CENTER", o.levelBadge, "CENTER")
    o.restHalo:EnableMouse(false)
    local restGlow = o.restHalo:CreateTexture(nil, "ARTWORK")
    restGlow:SetTexture(MEDIA .. "LevelRestHalo")
    restGlow:SetAllPoints()
    restGlow:SetBlendMode("ADD")
    local restPulse = 0
    o.restHalo:SetScript("OnUpdate", A.Timed("rest glow", function(_, elapsed)
        restPulse = (restPulse + (elapsed or 0)) % 3.2
        restGlow:SetAlpha(0.34 + 0.30 * (0.5 + 0.5 * math.sin(restPulse * 2 * math.pi / 3.2)))
    end))
    o.restHalo:Hide()

    o.restBadge = CreateFrame("Frame", nil, hud)
    o.restBadge:SetFrameLevel(hud:GetFrameLevel() + 17)
    o.restBadge:SetSize(18, 18)
    o.restBadge:SetPoint("CENTER", o.levelBadge, "TOPLEFT", 4, 0)
    o.restBadge:EnableMouse(false)
    local restIcon = o.restBadge:CreateTexture(nil, "OVERLAY")
    restIcon:SetTexture(stateIcon)
    restIcon:SetTexCoord(0, 0.5, 0, 0.421875)
    restIcon:SetSize(18, 18)
    restIcon:SetPoint("CENTER")
    o.restBadge:Hide()

    -- In combat the swords' red outline beats: a quick rise, a slower fade (COMBAT_GLOW).
    o.combatBadge = CreateFrame("Frame", nil, hud)
    o.combatBadge:SetFrameLevel(hud:GetFrameLevel() + 16)
    o.combatBadge:SetSize(18, 18)
    o.combatBadge:SetPoint("CENTER", o.levelBadge, "CENTER")
    o.combatBadge:EnableMouse(false)
    local glow = {}
    for _, offset in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 },
                             { -1.4, -1.4 }, { -1.4, 1.4 }, { 1.4, -1.4 }, { 1.4, 1.4 } }) do
        local edge = o.combatBadge:CreateTexture(nil, "ARTWORK")
        edge:SetAtlas("UI-HUD-UnitFrame-Player-CombatIcon")
        edge:SetSize(17, 17)
        edge:SetPoint("CENTER", o.combatBadge, "CENTER", offset[1], offset[2])
        edge:SetVertexColor(COMBAT_GLOW.color[1], COMBAT_GLOW.color[2], COMBAT_GLOW.color[3])
        edge:SetBlendMode("ADD")
        glow[#glow + 1] = edge
    end
    local badgeArt = o.combatBadge:CreateTexture(nil, "OVERLAY")
    badgeArt:SetAllPoints()
    badgeArt:SetAtlas("UI-HUD-UnitFrame-Player-CombatIcon")
    local pulse = 0
    local function beat(elapsed)
        pulse = (pulse + elapsed) % COMBAT_GLOW.period
        local alpha = COMBAT_GLOW.low + (COMBAT_GLOW.high - COMBAT_GLOW.low) * combatBeat(pulse / COMBAT_GLOW.period)
        for _, edge in ipairs(glow) do edge:SetAlpha(alpha) end
    end
    o.combatBadge:SetScript("OnUpdate", A.Timed("combat badge", function(_, elapsed) beat(elapsed or 0) end))
    beat(0)
    o.combatBadge:Hide()
    o:EnableMouse(true)
    o:SetScript("OnEnter", function()
        o.valueHover = true
        S.UpdateValueVisibility()
        if GameTooltip then
            GameTooltip:SetOwner(o, A.TooltipAnchor(o))
            GameTooltip:SetUnit("player")
            GameTooltip:AddLine("Right-click for player options", 0.8, 0.7, 0.5)
            GameTooltip:Show()
        end
    end)
    o:SetScript("OnLeave", function()
        o.valueHover = false
        S.UpdateValueVisibility()
        if GameTooltip and GameTooltip:IsOwned(o) then GameTooltip:Hide() end
    end)
    spheres.left = o
    S.ApplySlosh()
end

function S.UpdateCombat(active)
    local left = spheres.left
    local badge = left and left.combatBadge
    if not badge then return end
    if active == nil then
        active = UnitAffectingCombat and UnitAffectingCombat("player") or inCombat()
    end
    local resting = IsResting and A.call(IsResting) and true or false
    badge:SetShown(active and true or false)
    left.restHalo:SetShown(not active and resting)
    left.restBadge:SetShown(not active and resting)
    left.levelText:SetShown(not active)
    if not active then S.UpdateLevel() end
end

-- `level`: PLAYER_LEVEL_UP's new one. The game sends it before UnitLevel catches up (0.5.282: "level
-- doesn't get updated when character levels up"; UNIT_LEVEL follows once it has), so the well
-- holds it until UnitLevel reaches it: a refresh in between (resting, a fight's end) can't undo it.
function S.UpdateLevel(level)
    local left = spheres.left
    if not left or not left.levelText then return end
    if num(level) then left.levelUp = level end
    local now = UnitLevel and UnitLevel("player")
    if not num(now) then now = nil end
    local up = left.levelUp
    if up and now and now >= up then up, left.levelUp = nil, nil end
    local shown = up or now
    if shown then left.levelText:SetText(shown) end
end

-- The minimap's arrow to what you super-track stands at the map's edge while the target is beyond
-- it, and under the griffin's head when it points down right. Ours is a copy where the game draws
-- its own, over the statue (0.5.406, the player's: "the exact same position with the original
-- arrow inside the map, only layers above to go over gryphons head"; S.UpdateQuestArrow). The
-- game's arrow can't be read: it is worked out from where you are and where the target is.
-- `reach`: its centre's share of the map's radius (0.8 measured on the player's screenshot of both
-- arrows in 0.5.407; 0.82 in 0.5.415 at the larger size, the player's "a little outwards"); `size` the
-- player's (0.5.414: 34; 20 to 32 before were smaller than the game's, 35 a pinch bigger), `alpha` too
-- (0.5.412: "transparent like 55%"; 0.4 in 0.5.417: "reduce the opacity ... some more"). Only where it's needed (0.5.416): while the game shows its own
-- (the quest's own distance from the game, see arrowDistance) and the griffin covers that, the
-- ring's `griffin` arc (degrees counter-clockwise from the right), where its art (alpha over 0.5,
-- placed as ART.statueR) comes within 10 units of the arrow's centre. While it shows it moves every
-- frame, as the game's does (0.5.408: every 0.05 s, the target every 0.5 s, it trailed "like a half
-- second"); hidden, it checks every `idle` s. The target is looked up again on `events` and every
-- `lookup` s besides (0.5.418: 0.5 s, 2 s to 0.5.424: a table per quest on the map each time).
-- The same for the red arrow to your corpse while you're a ghost (0.5.446, the player's: "we need
-- same behavior for red arrow when the character is dead"): `corpseFile`, the quest arrow's
-- sibling in the game's files (FileDataIDs 457290 and 457291), the corpse from C_DeathInfo, shown
-- while it is beyond the minimap (the straight line: the game shows the corpse itself within it).
local QUEST_ARROW = { file = "Interface\\Minimap\\MiniMap-QuestArrow", corpseFile = "Interface\\Minimap\\MiniMap-DeadArrow",
    size = 34, alpha = 0.4, reach = 0.82, griffin = { -95, -36 }, idle = 0.1, lookup = 10,
    events = { "SUPER_TRACKING_CHANGED", "QUEST_POI_UPDATE", "WAYPOINT_UPDATE", "USER_WAYPOINT_UPDATED",
        "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
        "CORPSE_IN_RANGE", "CORPSE_OUT_OF_RANGE" } }

-- The map sphere's own layers round and over the minimap (buildRight; tools/sim_bridge.lua, the
-- simulator, builds them too): its holder, the fade, the smoke and wisps turning, the glass, the pins (the
-- coordinates and the zone name), the arrows.
-- S.PlaceMinimap puts the minimap in the holder and shows the fade and the smoke.
local function buildMapLayers(o)
    o.mapHolder = child(o, 2)
    o.mapHolder:SetFrameStrata("LOW")
    o.mapDissolve = child(o, 3)
    local fade = o.mapDissolve:CreateTexture(nil, "ARTWORK")
    fade:SetTexture(MEDIA .. "MapDissolve")
    fade:SetSize(BALL, BALL)
    fade:SetPoint("CENTER", o, "CENTER")
    o.mapDissolve:Hide()
    -- The smoke: five rings (MapCloud1-5, make_media.py MAP_CLOUDS: liquid billows, the last two
    -- fine swirls, 0.5.342), each turning at its own speed, then two copies of the inward wisps
    -- (MapTendrils). Sublevels 1-7: the game's last is 7, so a further layer needs another frame.
    o.clouds = child(o, 4)
    o.clouds.elapsed = 0
    o.clouds.layers = {}
    local cloudSpeeds = { 0.018, -0.023, 0.031, -0.037, 0.026 }
    for i = 1, #cloudSpeeds + 2 do
        local cloud = o.clouds:CreateTexture(nil, "ARTWORK", nil, i)
        cloud:SetTexture(MEDIA .. (i <= #cloudSpeeds and "MapCloud" .. i or "MapTendrils"))
        cloud:SetSize(BALL, BALL)
        cloud:SetPoint("CENTER", o, "CENTER")
        if i > #cloudSpeeds then cloud:SetAlpha(0) end
        o.clouds.layers[i] = cloud
    end
    local tendrilCycles = {
        { duration = 9.6, offset = 0, spin = 0.11, angle = 0 },
        { duration = 11.4, offset = 5.7, spin = -0.08, angle = 0.72 },
    }
    local function smoothstep(t)
        t = math.max(0, math.min(1, t))
        return t * t * (3 - 2 * t)
    end
    o.clouds:SetScript("OnUpdate", A.Timed("map smoke", function(self, elapsed)
        self.elapsed = self.elapsed + (elapsed or 0) * 1.6
        for i, cloud in ipairs(self.layers) do
            if i > #cloudSpeeds then
                local cycle = tendrilCycles[i - #cloudSpeeds]
                local phase = ((self.elapsed + cycle.offset) % cycle.duration) / cycle.duration
                -- 1.04: make_media.py TENDRIL_SCALE, which fades the texture out before the glass
                local size = BALL * (1.04 - 0.13 * phase)
                cloud:SetSize(size, size)
                if cloud.SetRotation then
                    cloud:SetRotation((self.elapsed * cycle.spin + cycle.angle) % (2 * math.pi))
                end
                cloud:SetAlpha(0.70 * smoothstep((phase - 0.04) / 0.18)
                    * (1 - smoothstep((phase - 0.60) / 0.34)))
            else
                if cloud.SetRotation then cloud:SetRotation(self.elapsed * cloudSpeeds[i]) end
                cloud:SetAlpha(0.94 + 0.06 * math.sin(self.elapsed * (0.37 + i * 0.08) + i))
            end
        end
    end))
    o.clouds:Hide()
    glassOver(o, "GlassMap", BALL, BALL, 0)
    -- curved labels stay over the map (the coordinates, the zone name; buildRight's mail badge)
    o.pins = CreateFrame("Frame", nil, o)
    o.pins:SetAllPoints()
    o.pins:SetFrameLevel(hud:GetFrameLevel() + 16)
    o.pins:EnableMouse(false)
    -- Coordinates and the zone name follow opposite sides of the sphere curve, appearing on
    -- hover or by setting. Coordinates are empty where the map has none (instances).
    local c = CreateFrame("Frame", nil, o.pins)
    c:SetSize(80, 12)
    c:SetPoint("CENTER", o, "CENTER", 0, S.ORB_TEXT_Y)
    c.glyphs = {}
    local since = 1
    c:SetScript("OnUpdate", A.Timed("coordinates and zone name", function(_, elapsed)
        since = since + (elapsed or 0)
        if since >= 0.2 then
            since = 0
            S.UpdateCoords()
            S.UpdateZoneName()
        end
    end))
    c:Hide()
    o.coords = c
    local zone = CreateFrame("Frame", nil, o.pins)
    zone:SetSize(100, 12)
    zone:SetPoint("CENTER", o, "CENTER", 0, S.ORB_TEXT_Y)
    zone.glyphs = {}
    zone.fontSizeBoost = 1
    zone.shadow = true -- two dark copies follow each curved letter as the name changes length
    zone.shadowGlyphs = {}
    zone.tangentReferenceWidth = 100 -- preserve the current placement as the length cap grows
    zone:Hide()
    o.zone = zone
    -- the minimap's arrows, copied over the griffin (QUEST_ARROW): above the statues (art, + 14)
    local function newArrow(file)
        local a = CreateFrame("Frame", nil, o)
        a:SetSize(QUEST_ARROW.size, QUEST_ARROW.size)
        a:SetFrameLevel(hud:GetFrameLevel() + 15)
        a:EnableMouse(false)
        a.texture = a:CreateTexture(nil, "ARTWORK")
        a.texture:SetTexture(file)
        a.texture:SetAllPoints()
        a:SetAlpha(QUEST_ARROW.alpha)
        a:Hide()
        return a
    end
    local arrow = newArrow(QUEST_ARROW.file)
    o.questArrow, o.corpseArrow = arrow, newArrow(QUEST_ARROW.corpseFile)
    local ticker = CreateFrame("Frame", nil, o) -- the arrow can't tick while it is hidden
    arrow.ticker = ticker
    local lookup, since = QUEST_ARROW.lookup, QUEST_ARROW.idle
    ticker:SetScript("OnUpdate", A.Timed("quest arrow", function(_, elapsed)
        lookup, since = lookup + (elapsed or 0), since + (elapsed or 0)
        if lookup >= QUEST_ARROW.lookup then
            lookup = 0
            S.FindQuestTarget()
            S.FindCorpse()
        end
        if since >= QUEST_ARROW.idle then
            since = 0
            S.UpdateQuestArrow()
        else
            S.MoveQuestArrow()
        end
    end))
    for _, event in ipairs(QUEST_ARROW.events) do pcall(ticker.RegisterEvent, ticker, event) end
    ticker:SetScript("OnEvent", function()
        lookup = 0
        S.FindQuestTarget()
        S.FindCorpse()
        S.UpdateQuestArrow()
    end)
end

local function buildRight()
    local o = orbFrame("right")
    -- The minimap's terrain paints above sibling frames on its own strata.
    -- Keep the map on LOW, then draw the fade, clouds and glass on the orb's
    -- MEDIUM strata in that order. No black disc behind the map (MapBack until
    -- 0.5.349, the player's: "it causes a black outline around the sphere
    -- hurting its glass effect"): MapDissolve covers the ring round the map.
    o.back:Hide()
    buildMapLayers(o)
    -- mail gets its own brass badge by the Game Menu well (on the pins: buildMapLayers)
    o.mailBadge = CreateFrame("Frame", nil, o.pins)
    o.mailBadge:SetFrameLevel(hud:GetFrameLevel() + 17)
    o.mailBadge:SetSize(20, 20)
    -- right over the Game Menu well, between the Bag hub (the upper row's 13th place, to x 226) and the
    -- map sphere's rim (0.5.478, the player's: "bag button getting in front of mail icon": at x 230 it
    -- was placed when the rows had 12 places)
    local mailX, mailY = S.SocketOffset("right")
    o.mailBadge:SetPoint("CENTER", art.frameAnchor, "BOTTOM", mailX, mailY + 28)
    o.mailBadge:EnableMouse(false)
    local mailDisc = o.mailBadge:CreateTexture(nil, "BACKGROUND")
    mailDisc:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    mailDisc:SetSize(16, 16)
    mailDisc:SetPoint("CENTER")
    local mailRim = o.mailBadge:CreateTexture(nil, "OVERLAY")
    A.SetBezel(mailRim, "Hub") -- match the round hub's current finish
    mailRim:SetSize(8 / A.HUB_FRAME_INNER, 8 / A.HUB_FRAME_INNER)
    mailRim:SetPoint("CENTER")
    o.mailBadge:Hide()
    spheres.right = o
end

function S.Create()
    if hud then return end
    -- everything hangs off one frame on the bottom of the screen, scaled as one
    hud = CreateFrame("Frame", "SpheresHUD", UIParent)
    hud:SetFrameStrata("MEDIUM")
    hud:SetFrameLevel(2)
    hud:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, SINK) -- in its own units: scales with it
    hud:SetSize(2 * HALF.statues, 260)
    hud:SetMovable(true)
    hud:SetClampedToScreen(true)
    hud:EnableMouse(false)
    buildArt()
    buildLeft()
    buildRight()
    local selectionTemplate = EditModeSystemSelectionBaseMixin and "EditModeSystemSelectionBaseTemplate"
    -- The Blizzard template declares parentKey="Selection". Give it an addon-owned,
    -- unscaled parent so it cannot install UIParent.Selection: native chat snapping
    -- treats that field as proof the target implements EditModeSystemMixin methods.
    S.edit.owner = CreateFrame("Frame", "SpheresEditOverlay", UIParent)
    S.edit.owner:SetAllPoints(hud)
    S.edit.owner:EnableMouse(false)
    S.edit.selection = CreateFrame("Frame", nil, S.edit.owner, selectionTemplate)
    S.edit.selection:SetAllPoints(hud)
    S.edit.selection:SetFrameStrata("DIALOG")
    S.edit.selection:SetFrameLevel(hud:GetFrameLevel() + 100)
    S.edit.selection:EnableMouse(true)
    S.edit.selection:RegisterForDrag("LeftButton")
    S.edit.selection:Hide()
    -- Reuse Blizzard's rounded Edit Mode nine-slice and texture kits. This is
    -- the same blue highlight / gold selected treatment used by native frames.
    -- The custom selector is not a registered Edit Mode system, so keep labels
    -- and selection plumbing local to the existing drag-and-settings behavior.
    S.edit.selection.UpdateLabelVisibility = function() end
    S.edit.selection.system = { GetSystemName = function() return "Spheres" end }
    -- Blizzard's Edit Mode manager draws its magnetic preview guides for this
    -- frame when we provide the same selection geometry its native systems use.
    S.edit.selection.GetScaledSelectionCenter = function(frame)
        return frame:GetCenter()
    end
    S.edit.selection.GetScaledSelectionSides = function(frame)
        local left, bottom, width, height = frame:GetRect()
        if not left then return nil end
        return left, left + width, bottom, bottom + height
    end
    S.edit.selection.GetFrameMagneticEligibility = function() return false, false end
    local mouseOverHighlight = S.edit.selection.MouseOverHighlight
    if type(mouseOverHighlight) ~= "function" and mouseOverHighlight then
        mouseOverHighlight:SetAllPoints(S.edit.selection)
    end
    S.edit.selection.label = S.edit.selection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    S.edit.selection.label:SetPoint("BOTTOM", S.edit.selection, "TOP", 0, 4)
    S.edit.selection.label:SetText("Spheres - drag to move, click for settings")
    S.edit.selection:SetScript("OnDragStart", function()
        if S.edit.mode and not inCombat() then
            S.edit.moving = true
            S.edit.dragged = true
            if EditModeManagerFrame and EditModeManagerFrame.SetSnapPreviewFrame then
                EditModeManagerFrame:SetSnapPreviewFrame(S.edit.selection)
            end
            hud:StartMoving()
        end
    end)
    S.edit.selection:SetScript("OnDragStop", function()
        if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
            EditModeManagerFrame:ClearSnapPreviewFrame()
        end
        if not S.edit.moving then return end
        hud:StopMovingOrSizing()
        S.edit.moving = false
        local x, bottom = hud:GetCenter(), hud:GetBottom()
        local hudScale, uiScale = hud:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if num(x) and num(bottom) and num(hudScale) and num(uiScale) and uiScale > 0 then
            local pointX, pointY = S.SnapHudPosition(x, bottom, hudScale, uiScale)
            ns.db.hudPoint = { x = pointX, y = pointY }
        end
        if ns.Apply then ns.Apply() else S.Layout() end
    end)
    S.edit.selection:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then S.edit.dragged = false end
    end)
    S.edit.selection:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        if S.edit.mode and not S.edit.dragged then
            if S.edit.selection.ShowSelected then S.edit.selection:ShowSelected() end
            S.ToggleEditSettings()
        end
        S.edit.dragged = false
    end)
    if hooksecurefunc and Minimap then
        -- Blizzard (Edit Mode, the cluster's layout) puts the minimap back: ours again
        for _, m in ipairs({ "SetPoint", "SetParent", "SetSize" }) do
            if Minimap[m] then
                hooksecurefunc(Minimap, m, function()
                    if not placing and S.MapTaken() then S.PlaceMinimap() end
                end)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- The frame's slots (Track.lua): which frame, and where its slots are
-------------------------------------------------------------------------------
-- The frame's top edge moves Blizzard's bars anchored on it: out of combat only (they're
-- protected); in combat it waits for the end.
local function placeTop()
    if not top then return end
    if inCombat() then pending = true; return end
    top:ClearAllPoints()
    top:SetPoint("BOTTOM", art.frameAnchor, "BOTTOM", 0, FRAMES[frameSlots].top)
end

-- n: how many bars show (0-2). Returns true when that changed the frame.
function S.SetSlots(n)
    if not FRAMES[n] then n = 0 end
    local changed = n ~= frameSlots
    frameSlots = n
    if art then
        art.frame:SetTexture(MEDIA .. frameFile(n))
    end
    if changed then placeTop() end
    return changed
end
function S.Slots() return frameSlots end
function S.Slot(i) return FRAMES[frameSlots].slots and FRAMES[frameSlots].slots[i] end
function S.TopAnchor() return top end

-------------------------------------------------------------------------------
-- Health and power (the left orb): in combat too, these are plain frames
-------------------------------------------------------------------------------
-- Hidden values can be passed on, never tested (no `v or x`, no `c and v or x`, no
-- comparisons): `given` checks, `pick` chooses with an if.
local function given(v) return secret(v) or v ~= nil end
local function pick(v, default)
    if given(v) then return v end
    return default
end

-- 1267 -> 1.3k by the game (it takes hidden values); its answer may be hidden too.
local function short(v)
    if not given(v) then return nil end
    if AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, v, ABBREVIATE)
        if ok and given(s) then return s end
    end
    return v
end

-- A notice line `share` of the way from the health value's arc (0) to the inmost one round the
-- embedded sphere (1): its circle's centre and radius, both that share of the way, so each line
-- bends a step more from the outer sphere's curve towards the inner one's.
local function noticeCircle(share)
    local outer, shift = BALL / 2, BALL / 2 - HEALTH_RADIUS -- the health arc's (arcPoint)
    local x0, y0 = -shift * math.cos(HEALTH_ANGLE), -shift * math.sin(HEALTH_ANGLE)
    local inner = BALL / 2 * PET.r + PET.edge + NOTICE_INNER_GAP
    return x0 + (PET.at[1] - x0) * share, y0 + (PET.at[2] - y0) * share,
        outer + (inner - outer) * share
end
-- Where line `share` starts: from the health arc at NOTICE_START across the circles in between,
-- each step to the nearest point of the next, so the lines start on one column square to them all.
local function noticeStart(share)
    local cx, cy, r = noticeCircle(0)
    local a = NOTICE_START
    local x, y = cx + r * math.cos(a), cy + r * math.sin(a)
    for i = 1, NOTICE_STEPS do
        cx, cy, r = noticeCircle(share * i / NOTICE_STEPS)
        a = math.atan2(y - cy, x - cx)
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
    end
    return a, cx, cy, r
end

-- A notice's arc: the middle's angle, its radius and curve round (x0, y0), and with an embedded
-- sphere the angle its first glyph starts at.
local function noticeArc(n)
    local o = spheres.left
    local stacked = n == o.damageNotice and o.healNotice:IsShown()
    if o.holed then
        local start, x0, y0, r = noticeStart(NOTICE_LINES[stacked and 2 or 1])
        -- a hidden amount's sign starts there, the amount after it (the parts at -12 and 5)
        return start - (n.sign:GetStringWidth() / 2 + 12) / r, r, r, x0, y0, start
    end
    local inward = stacked and 22 or 0
    return HEALTH_ANGLE, HEALTH_RADIUS - n.spec.inset, NOTICE_CURVE,
        -inward * math.cos(HEALTH_ANGLE), -inward * math.sin(HEALTH_ANGLE)
end

local function refreshNoticeArc(n)
    local angle, radius, curve, x0, y0, startAngle = noticeArc(n)
    n.arcAngle, n.arcRadius, n.arcCurve = angle, radius, curve
    n:ClearAllPoints()
    n:SetPoint("CENTER", spheres.left, "CENTER", x0, y0)
    for _, part in ipairs(n.parts) do
        local x, y, tangent = arcPoint(angle, radius, curve, part[2], -1)
        part[1]:ClearAllPoints()
        part[1]:SetPoint("CENTER", n, "CENTER", x, y)
        if part[1].SetRotation then part[1]:SetRotation(tangent - math.pi / 2) end
    end
    if n.plainText then
        n.value = nil -- the same amount must move when the embedded sphere appears or vanishes
        n.arcAngle = setCurvedText(n, n.plainText, angle, radius, nil, -math.pi / 2, true, curve,
            nil, startAngle)
    end
end

-- A received heal's or wound's amount (UNIT_COMBAT's, maybe hidden) on its notice (NOTICES).
local function showNotice(n, amount)
    if not given(amount) or (num(amount) and amount <= 0) then return end -- no "-0"
    local spec, value = n.spec, short(amount)
    if secret(value) then
        n.plainText = nil
        setCurvedText(n, "", HEALTH_ANGLE)
        n.protected:SetFormattedText("%s", value)
        n.sign:Show()
        n.protected:Show()
    else
        n.sign:Hide()
        n.protected:Hide()
        n.plainText = spec.sign .. tostring(value)
    end
    n.count = n.count + 1
    n.elapsed = 0
    n:SetAlpha(spec.alpha)
    n:Show()
    refreshNoticeArc(n)
    refreshDamagePosition()
end
refreshDamagePosition = function()
    local o = spheres.left
    if not o then return end
    local damage = o.damageNotice
    if damage:IsShown() then refreshNoticeArc(damage) end
end
function S.ShowHeal(amount)
    if spheres.left then showNotice(spheres.left.healNotice, amount) end
end
function S.ShowDamage(amount)
    if spheres.left then showNotice(spheres.left.damageNotice, amount) end
end

-- "cur / max" joined by the game (SetFormattedText takes hidden values); without it, cur alone.
local function setNumbers(n, cur, max)
    local a, b = short(cur), short(max)
    if not given(a) then
        n.text:SetText("")
        n.current:SetText("")
        n.separator:SetText("")
        n.maximum:SetText("")
        return
    end
    if given(b) and n.text.SetFormattedText then
        pcall(n.text.SetFormattedText, n.text, NUMBER_FORMAT, a, b)
        n.current:SetFormattedText("%s", a)
        n.separator:SetText("/")
        n.maximum:SetFormattedText("%s", b)
    else
        if n.text.SetFormattedText then pcall(n.text.SetFormattedText, n.text, "%s", a) end
        n.current:SetFormattedText("%s", a)
        n.separator:SetText("")
        n.maximum:SetText("")
    end
end

local function evaluate(fn, ...)
    if not fn then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function powerColor(token)
    local c = token and COLORS[token]
    if c then return c end
    local p = token and PowerBarColor and PowerBarColor[token]
    if type(p) == "table" and num(p.r) and num(p.g) and num(p.b) then return { p.r, p.g, p.b } end
    return COLORS.MANA
end

local filled = {} -- what the last update handed each liquid, for /spheres debug
-- The mana's purple and its glints, only while the power is mana (the frame moves them).
local function setManaEffects(bar, enabled)
    bar.manaEffects = enabled and true or false
end

-- A liquid, its moving layers, shade and surface line shown, or all gone (dead).
local function liquidVisible(bar, visible)
    local alpha = visible and 1 or 0
    bar:SetAlpha(alpha)
    bar.surface:SetAlpha(alpha)
    if bar.clip then bar.clip:SetAlpha(alpha) end
    if bar.contact then
        bar.contactVisible = visible
        bar.contact:SetAlpha(visible and (bar.contactFade or 1) or 0)
    end
end

-- A new level, eased (0.5.266): the client interpolates even a hidden value itself (StatusBar:
-- SetValue's interpolation, in the forever branch's SimpleStatusBarAPIDocumentation), and what is
-- pinned to the level rides with it every frame: a regeneration tick rises, it doesn't jump.
local SMOOTH = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local function setLevel(bar, value)
    if SMOOTH then bar:SetValue(value, SMOOTH) else bar:SetValue(value) end
end

local contactCurve
local function contactOpacity(what, cur, max)
    if num(cur) and num(max) and max > 0 then
        local share = math.max(0, math.min(1, cur / max))
        if share <= 0.08 then return share end
        if share <= 0.2 then return 0.08 + (share - 0.08) * 2.833333333 end
        return math.min(1, 0.42 + (share - 0.2) * 1.933333333)
    end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then return 1 end
    if not contactCurve then
        contactCurve = C_CurveUtil.CreateCurve()
        contactCurve:SetType(Enum.LuaCurveType.Linear)
        for _, point in ipairs({ { 0, 0 }, { 0.08, 0.08 }, { 0.2, 0.42 }, { 0.5, 1 }, { 1, 1 } }) do
            contactCurve:AddPoint(point[1], point[2])
        end
    end
    local unit = what == "power" and "player" or "pet"
    local opacity
    if what == "pet" and UnitHealthPercent then
        opacity = evaluate(UnitHealthPercent, unit, true, contactCurve)
    elseif UnitPowerPercent then
        opacity = evaluate(UnitPowerPercent, unit, nil, false, contactCurve)
    end
    return given(opacity) and opacity or 1
end

-- The moving layers follow on their own: their clip frame is pinned to the fill's top.
local function fill(bar, what, cur, max)
    bar:SetMinMaxValues(0, pick(max, 1))
    setLevel(bar, pick(cur, 0))
    if bar.contact then
        bar.contact:SetMinMaxValues(0, pick(max, 1))
        setLevel(bar.contact, pick(cur, 0))
        bar.contactFade = contactOpacity(what, cur, max)
        bar.contact:SetAlpha(bar.contactVisible == false and 0 or bar.contactFade)
    end
    filled[what] = (secret(cur) or secret(max)) and "hidden values" or (cur == nil and "no value" or "plain values")
end

-- The wavy top stands on the level and over it (SURFACE.pad), so an empty power liquid kept a
-- sliver of it at the bottom (0.5.340, the player's: "a small rage liquid buttom of the rage
-- sphere when the rage is 0 ... it shouldn't appear at all"). The level is hidden and can't be
-- tested, but the client runs its share through a curve (UnitPowerPercent) and SetAlpha takes the
-- hidden answer: nothing when empty, full strength from SURFACE_FADE of the bar up.
local SURFACE_FADE = 0.03
local surfaceCurves -- crest and line, made once
local function surfaceCurve(strength)
    local c = C_CurveUtil.CreateCurve()
    c:SetType(Enum.LuaCurveType.Linear)
    c:AddPoint(0, 0)
    c:AddPoint(SURFACE_FADE, strength)
    c:AddPoint(1, strength)
    return c
end
-- The slosh's climb up the wall (bar.pile) only from SLOSH_FROM of the bar up, in full by
-- SLOSH_FULL (0.5.444, the player's: "when there is 0 rage, the camera movement creates a brief
-- jumping effect, let's don't do the movement effects below 3%"; the crest and line already faded).
local SLOSH_FROM, SLOSH_FULL = 0.03, 0.05
local function pileCurve()
    local c = C_CurveUtil.CreateCurve()
    c:SetType(Enum.LuaCurveType.Linear)
    c:AddPoint(0, 0)
    c:AddPoint(SLOSH_FROM, 0)
    c:AddPoint(SLOSH_FULL, 1)
    c:AddPoint(1, 1)
    return c
end
local function fadeSurface(bar, pt, unit)
    if not bar.crest then return end
    unit = unit or "player" -- (the target sphere's: "target")
    local crest, line, pile = 1, SURFACE.alpha, 1
    if pt ~= false and UnitPowerPercent and C_CurveUtil and C_CurveUtil.CreateCurve
            and Enum and Enum.LuaCurveType then
        surfaceCurves = surfaceCurves or { crest = surfaceCurve(1), line = surfaceCurve(SURFACE.alpha), pile = pileCurve() }
        local c = evaluate(UnitPowerPercent, unit, pt, false, surfaceCurves.crest)
        local l = evaluate(UnitPowerPercent, unit, pt, false, surfaceCurves.line)
        local p = evaluate(UnitPowerPercent, unit, pt, false, surfaceCurves.pile)
        if given(c) and given(l) and given(p) then crest, line, pile = c, l, p end
    end
    bar.crest:SetAlpha(crest)
    bar.line:SetAlpha(line)
    if bar.pile then bar.pile:SetAlpha(pile) end
end

-- The liquids' and the map sphere's own code, for tools/sim_bridge.lua: the simulator builds and runs them with it.
S.Liquids = {
    build = buildLiquid, animate = animateLiquids, color = setColor, fade = fadeSurface,
    magic = setManaEffects, colors = COLORS, box = box, D = D,
    changed = function(bar) if not bar.changedAt then bar.changedAt = liquidClock end end, -- S.LiquidChanged
    -- the map sphere's layers (buildMapLayers, with the arrows over the griffin) on `o`, the map sphere the
    -- add-on's arrow code reads (spheres.right: buildRight's in game)
    map = function(o)
        buildMapLayers(o)
        spheres.right = o
    end,
    mapSize = MAP_SIZE, mapMask = MEDIA .. "MaskMap", -- S.PlaceMinimap's size and mask
    -- the whole left orb (buildLeft) on `parent` as the HUD, laid out by S.UpdateLeft and S.UpdatePet
    left = function(parent)
        hud = hud or parent
        if not art then buildArt() end
        buildLeft()
        return spheres.left
    end,
    -- The simulator rebuilds its stand-in frame tree on reset; clear only these
    -- build-once references so the next build attaches fresh art to that tree.
    reset = function(parent)
        hud, art, top = parent, nil, nil
        spheres = {}
        frameSlots, placing, pending = 1, false, false
    end,
    ORB_X = ORB_X, ORB_Y = ORB_Y,
    SINK = SINK, -- the HUD's baseline aligns with the screen's bottom edge
    -- the rings' geometry (the simulator lays the menu's and the bags' fans out as Ring.lua does): the ball, how far
    -- a hub stands over its edge, the frame wells (the menu's hub sits in the right one), the frame's top now
    BALL = BALL, OVERLAP = OVERLAP, SOCKET = { SOCKET_X, SOCKET_Y },
    frameTop = function() return FRAMES[frameSlots].top end,
}

-------------------------------------------------------------------------------
-- The target's sphere (0.5.468, experimental: Target Style "Sphere" in Target.lua)
-------------------------------------------------------------------------------
-- The player's: "On B, could we have similar health/mana sphere and an embedded target avatar. But
-- avatar needs to be in perfect center. I think we can keep todays avatar style of spheres, and add
-- this as experimental" (B: the "Third orb" of the target frame ideas). Your orb's two glass pieces
-- at TARGET.scale, their liquids the target's health and power (left and right, as yours), and in
-- the very centre a ball for its portrait: Target.lua's face (today's gold ring, rank ring and level
-- badge) sits in it, in a scoop as your pet's sits in yours (PetBowl; Media/TargetCavity, the hole
-- round it, centred: make_media.py TARGET_AVATAR). Its liquids move with yours (animateLiquids,
-- following the left orb's clock and slosh). No surge: nothing tells what it spent from what it got.
-- It floats at the top of the screen: no shadow sits it on the frame (0.5.469, the player's: "Having
-- shadow on target frame doesn't make sense, at least the level of player spheres"): no bottom shade
-- behind it, no shade in its liquids, its own glass (GlassTarget*: no lower edge shadow, light round
-- its rim, "a little more highlight around the edges"). Its health is red, as yours ("target health
-- can be red too"); what it is to you shows in its name's colour (0.5.470, the player's: "The character name
-- color gives the target nature ... keep everything as is for the frame coloring"; 0.5.469 tinted a band
-- round the portrait's gold ring).
-- The portrait's ball 0.55 of its radius (0.47 in 0.5.468; 0.5.469: "increase the avatar picture a little to
-- take sphere out from the focus"): make_media.py TARGET_AVATAR, Media/TargetCavity.
local TARGET = { scale = 0.75, avatar = 0.55 } -- of your orb; the portrait's ball, of its ball's radius
S.TARGET = TARGET

function S.TargetSphere(parent)
    local s = TARGET.scale
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(D * s, D * s)
    t:EnableMouse(false)
    t.holes = {}
    -- Split (health and power) or whole (its health alone, as yours in bear form: 0.5.471, the
    -- player's: "If target doesn't have mana, rage, power why not use whole sphere?"). A target's
    -- maximum power comes hidden ("I target beasts and there is still mana hemisphere": 0.5.471 compared
    -- a plain one), so the game picks: a bar fed it out of 1 (`gate`) is full with any power, empty
    -- with none; the split sphere is drawn in a clip frame over its fill, the whole one over the rest.
    t.gate = CreateFrame("StatusBar", nil, t)
    t.gate:SetAllPoints(t)
    t.gate:SetOrientation("HORIZONTAL")
    t.gate:SetStatusBarTexture(MEDIA .. "FillNone")
    t.gate:SetMinMaxValues(0, 1)
    t.gate:SetValue(1)
    t.gate:EnableMouse(false)
    local fillOf = t.gate:GetStatusBarTexture()
    local function layer(overFill)
        local clip = CreateFrame("Frame", nil, t)
        clip:SetFrameLevel(t:GetFrameLevel())
        clip:EnableMouse(false)
        if clip.SetClipsChildren then
            clip:SetClipsChildren(true)
            if overFill then
                clip:SetAllPoints(fillOf)
            else
                clip:SetPoint("TOPLEFT", fillOf, "TOPRIGHT")
                clip:SetPoint("BOTTOMRIGHT", t.gate, "BOTTOMRIGHT")
            end
        else
            clip:SetAllPoints(t)
            if not overFill then clip:Hide() end -- no clipping: split, always
        end
        local o = CreateFrame("Frame", nil, clip) -- the sphere's own place, whatever the clip's
        o:SetAllPoints(t)
        o:SetFrameLevel(t:GetFrameLevel())
        o:EnableMouse(false)
        o.ballSize, o.cavity = BALL * s, "TargetCavity"
        o.back = o:CreateTexture(nil, "BACKGROUND")
        o.back:SetTexture(MEDIA .. (overFill and "OrbBack" or "OrbBackWhole")) -- whole: no opening at the top
        o.back:SetAllPoints()
        return o
    end
    local split, whole = layer(true), layer(false)
    t.splitLayer, t.wholeLayer = split, whole
    local hw, hh, hx = box("health")
    local mw, mh, mx = box("mana")
    t.health = buildLiquid(split, "health", "Health",
        { w = hw * s, h = hh * s, x = hx * s, scale = s, unit = s, unshaded = true }, t.holes)
    t.power = buildLiquid(split, "mana", "Mana",
        { w = mw * s, h = mh * s, x = mx * s, scale = s, unit = s, unshaded = true }, t.holes)
    t.health.glass = glassOver(split, "GlassTargetHealth", hw * s, hh * s, hx * s)
    t.power.glass = glassOver(split, "GlassTargetMana", mw * s, mh * s, mx * s)
    t.whole = buildLiquid(whole, "health", "Whole",
        { w = BALL * s, h = BALL * s, x = 0, scale = s, unit = s, clock = "whole", unshaded = true }, t.holes)
    t.whole.glass = glassOver(whole, "GlassTargetWhole", BALL * s, BALL * s, 0)
    t.liquids = { t.health, t.power, t.whole }
    -- the scoop round the portrait's ball, over either glass
    local rb = BALL / 2 * s * TARGET.avatar
    t.over = child(t, 7)
    t.bowl = t.over:CreateTexture(nil, "OVERLAY")
    t.bowl:SetTexture(MEDIA .. "PetBowl")
    t.bowl:SetSize(2 * (rb + PET.bowl * s), 2 * (rb + PET.bowl * s))
    t.bowl:SetPoint("CENTER")
    for _, m in ipairs(t.holes) do m:SetTexture(m.on, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
    t.avatarSize, t.avatarLevel = 2 * rb, t.over:GetFrameLevel() + 2 -- the portrait's ball, over the glass
    setColor(t.health, COLORS.HEALTH)
    setColor(t.whole, COLORS.HEALTH)
    setColor(t.power, COLORS.MANA)
    t:SetScript("OnUpdate", A.Timed("target sphere", function(_, elapsed) animateLiquids(t.liquids, elapsed, true) end))
    return t
end

-- Its levels and looks (Target.lua): the values hidden or not, straight into the bars (both healths:
-- either may show).
function S.TargetSphereHealth(t, cur, max)
    fill(t.health, "target", cur, max)
    fill(t.whole, "target", cur, max)
end
-- Its maximum, out of 1, into the gate: the game shows the split sphere with any power, the whole one
-- without (hidden or not: no comparing in Lua; none given: none).
function S.TargetSpherePower(t, cur, max, pt, token)
    t.gate:SetValue(pick(max, 0))
    setManaEffects(t.power, token == "MANA")
    local c = powerColor(token)
    if t.power.color ~= c then setColor(t.power, c) end
    fill(t.power, "target power", cur, max)
    fadeSurface(t.power, pt, "target")
end
-- A dead one's liquids gone.
function S.TargetSphereDead(t, dead)
    for _, bar in ipairs(t.liquids) do liquidVisible(bar, not dead) end
end

-- The pet's scoop in your health and mana (holeMask, o.bowl): while the pet's orb shows in it
-- (PET.inside); without a pet, the pieces as they were. Only textures change: fine in combat.
function S.SetPetHole(on)
    local o = spheres.left
    on = PET.inside and (on or (o and o.innerPowerActive)) and true or false
    if not o or o.holed == on then return end
    o.holed = on
    for _, m in ipairs(o.holes) do
        m:SetTexture(on and m.on or HOLE_OFF, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    o.bowl:SetShown(on)
    for _, n in ipairs({ o.healNotice, o.damageNotice }) do
        if n and n:IsShown() then refreshNoticeArc(n) end
    end
end

-- One of the pet's liquids shown or not, its glass with it.
local function liquidShown(bar, shown)
    bar:SetShown(shown)
    bar.surface:SetShown(shown)
    bar.glass:SetShown(shown)
    if bar.clip then bar.clip:SetShown(shown) end
    if bar.contact then bar.contact:SetShown(shown) end
end

local function wantsInnerPower(token)
    if not token or token == "MANA" then return false end
    local exists = evaluate(UnitExists, "pet")
    return not secret(exists) and not exists
end

-- The pet's orb: whole (its health) or, for a pet with mana, its health and mana side by side;
-- a Hunter's pet's mood in the gap.
function S.UpdatePet()
    local p = spheres.left and spheres.left.pet
    if not p then return end
    local exists = evaluate(UnitExists, "pet") -- as the unit watch will show it (at login: no OnShow)
    if not secret(exists) then S.SetPetHole(exists and true or false) end
    local hp, hpMax, mp, mpMax, split
    if S.test then
        split, hp, hpMax, mp, mpMax = true, 0.6, 1, 0.35, 1
    else
        local pt, token = evaluate(UnitPowerType, "pet")
        if secret(pt) then pt = nil end
        if secret(token) then token = nil end
        split = token == "MANA"
        hp, hpMax = evaluate(UnitHealth, "pet"), evaluate(UnitHealthMax, "pet")
        mp, mpMax = evaluate(UnitPower, "pet", pt), evaluate(UnitPowerMax, "pet", pt)
    end
    liquidShown(p.whole, not split)
    liquidShown(p.health, split)
    liquidShown(p.mana, split)
    local dead = not S.test and evaluate(UnitIsDead, "pet")
    if secret(dead) then dead = false end
    for _, bar in ipairs({ p.whole, p.health, p.mana }) do liquidVisible(bar, not dead) end
    if split then
        fill(p.health, "pet", hp, hpMax)
        fill(p.mana, "pet mana", mp, mpMax)
    else
        fill(p.whole, "pet", hp, hpMax)
        filled["pet mana"] = nil
    end
    local values = p.over.health:IsShown()
    p.over.mana:SetShown(values and split)
    if values then
        setNumbers(p.over.health, dead and 0 or hp, hpMax)
        if split then setNumbers(p.over.mana, dead and 0 or mp, mpMax) end
    end
    if S.test then filled.pet, filled["pet mana"] = "test 60%", "test 35%" end
    local _, hunterPet = evaluate(HasPetUI)
    local mood
    if not S.test and not secret(hunterPet) and hunterPet and C_PetInfo and C_PetInfo.GetPetHappiness then
        mood = evaluate(C_PetInfo.GetPetHappiness)
    end
    if num(mood) and PET_MOOD[mood] then
        p.mood:SetAtlas(PET_MOOD[mood])
        p.mood:Show()
        p.moodLevel = mood
    else
        p.mood:Hide()
        p.moodLevel = nil
    end
    local _, playerToken = evaluate(UnitPowerType, "player")
    if secret(playerToken) then playerToken = nil end
    if spheres.left.innerPowerActive ~= (not S.test and wantsInnerPower(playerToken)) then S.UpdateLeft() end
end

S.test = false -- /spheres test: plain numbers, to tell drawing from hidden values
local function playerLayout(o, inner)
    local exists = evaluate(UnitExists, "pet")
    S.SetPetHole(not secret(exists) and exists)
    if o.laidOut and o.innerPowerActive == inner then return end -- each health change asks again
    o.laidOut = true
    o.innerPowerActive = inner
    -- full health: the backing without the opening where health and mana meet at the top
    -- (0.5.346: in bear form "there is an opening there which should only happen when health and
    -- mana spheres exist")
    o.back:SetTexture(MEDIA .. (inner and "OrbBackWhole" or "OrbBack"))
    liquidShown(o.health, not inner)
    liquidShown(o.power, not inner)
    liquidShown(o.wholeHealth, inner)
    o.heal:SetShown(not inner)
    o.wholeHeal:SetShown(inner)
    o.innerPower:SetShown(inner)
    S.SetPetHole(not secret(exists) and exists) -- again: the inner power sphere changes it
    local show = (ns.db and ns.db.sphereValuesAlways == true) or o.valueHover
    o.over.power:SetShown(show and not inner or false)
    o.innerPower.over.value:SetShown(show and inner or false)
end

function S.UpdateLeft()
    local o = spheres.left
    if not o then return end
    if S.test then
        playerLayout(o, false)
        setManaEffects(o.power, true)
        liquidVisible(o.health, true)
        liquidVisible(o.power, true)
        fill(o.health, "health", 0.7, 1)
        fill(o.power, "power", 0.4, 1)
        fadeSurface(o.power, false) -- plain 40%: the whole top
        filled.health, filled.power = "test 70%", "test 40%"
        return
    end
    local pt, token = evaluate(UnitPowerType, "player")
    if secret(pt) then pt = nil end
    if secret(token) then token = nil end
    local inner = wantsInnerPower(token)
    playerLayout(o, inner)
    local health = inner and o.wholeHealth or o.health
    local power = inner and o.innerPower.bar or o.power
    local heal = inner and o.wholeHeal or o.heal
    local powerNumbers = inner and o.innerPower.over.value or o.over.power
    setManaEffects(o.power, token == "MANA")
    setManaEffects(o.innerPower.bar, false)
    power.rises = token ~= "RAGE" and token ~= "RUNIC_POWER" -- they drain on their own
    local dead = evaluate(UnitIsDeadOrGhost, "player")
    if secret(dead) then dead = false end
    o.powerType, o.dead = pt, dead -- for S.UpdatePower
    liquidVisible(health, not dead)
    liquidVisible(power, not dead)
    if dead then
        o.healNotice:Hide()
        o.damageNotice:Hide()
        fill(health, "health", 0, 1)
        fill(power, "power", 0, 1)
        heal:SetMinMaxValues(0, 1)
        heal:SetValue(0)
        if o.over.health:IsShown() then
            setNumbers(o.over.health, 0, evaluate(UnitHealthMax, "player"))
            setNumbers(powerNumbers, 0, evaluate(UnitPowerMax, "player", pt))
        end
        return
    end
    fill(health, "health", evaluate(UnitHealth, "player"), evaluate(UnitHealthMax, "player"))
    -- incoming heals: out of your maximum, standing on your health (none: nothing to show)
    local incoming = evaluate(UnitGetIncomingHeals, "player")
    heal:SetMinMaxValues(0, pick(evaluate(UnitHealthMax, "player"), 1))
    setLevel(heal, pick(incoming, 0))
    filled.heals = incoming or 0 -- worded only for /spheres debug: no string per health change
    local c = powerColor(token)
    if power.color ~= c then setColor(power, c) end
    fill(power, "power", evaluate(UnitPower, "player", pt), evaluate(UnitPowerMax, "player", pt))
    fadeSurface(power, pt)
    if o.over.health:IsShown() then
        setNumbers(o.over.health, evaluate(UnitHealth, "player"), evaluate(UnitHealthMax, "player"))
        setNumbers(powerNumbers, evaluate(UnitPower, "player", pt), evaluate(UnitPowerMax, "player", pt))
    end
end

-- The mana's magic for your class (MAGIC_LOOK): at login.
local magicWhy = "not read yet"
function S.UpdateMagic()
    local o = spheres.left
    if not o then return end
    local _, class = evaluate(UnitClass, "player")
    if secret(class) then class = nil end
    magicWhy = tostring(class)
    local look = class and MIXED[class] or "arcane"
    setMagic(o.power, look)
    setMagic(o.innerPower.bar, look)
end

-- The power alone (UNIT_POWER_FREQUENT, several times a second while it regenerates): its liquid,
-- its wavy top and its values; the layout, health and the rest with S.UpdateLeft (0.5.422: the
-- whole of it for every tick of power).
function S.UpdatePower()
    local o = spheres.left
    if not o then return end
    if S.test or not o.laidOut then return S.UpdateLeft() end
    if o.dead then return end
    local pt = o.powerType
    local power = o.innerPowerActive and o.innerPower.bar or o.power
    fill(power, "power", evaluate(UnitPower, "player", pt), evaluate(UnitPowerMax, "player", pt))
    fadeSurface(power, pt)
    if o.over.health:IsShown() then
        setNumbers(o.innerPowerActive and o.innerPower.over.value or o.over.power,
            evaluate(UnitPower, "player", pt), evaluate(UnitPowerMax, "player", pt))
    end
end

-------------------------------------------------------------------------------
-- The minimap, in the right orb. Its cluster (top right: the zone name with the clock in it,
-- tracking, calendar, mail, the add-on compartment) goes out of sight with it (0.5.1, the
-- player's call; the clock too, 0.5.2: "not needed"): calendar, tracking and compartment into the
-- game menu ring (Ring.lua), the mail icon to a small badge above the Game Menu well;
-- our angled coordinates and zone name on the map's lower-left and
-- upper-right edges (buildRight).
-------------------------------------------------------------------------------
local mapHome      -- where it was: { parent, points, w, h }
local mapHidden = {} -- Blizzard's minimap bits we hid (their old parent)
local mapButtonHomes = {} -- buttons moved out of the minimap's LOW frame while the globe owns it
local raisedHomes = {} -- Blizzard's frames by the map lifted over the globe in place: their layer
local hiddenHolder
local pinned = {}  -- Blizzard's frame -> { parent, points } before we pinned it
local pinHooked = {}

local function stow(f)
    if not f or mapHidden[f] then return end
    hiddenHolder = hiddenHolder or CreateFrame("Frame")
    hiddenHolder:Hide()
    mapHidden[f] = f:GetParent() or UIParent
    f:SetParent(hiddenHolder)
end

function S.MapTaken() return mapHome ~= nil end

-- Each child the scan finds (every second: through the arguments, no table of them each time).
local function raiseEach(level, ...)
    for i = 1, select("#", ...) do
        local button = select(i, ...)
        if button.IsObjectType and button:IsObjectType("Button") and
            button ~= Minimap.ZoomIn and button ~= Minimap.ZoomOut then
            if not mapButtonHomes[button] then
                mapButtonHomes[button] = { parent = button:GetParent(), strata = button:GetFrameStrata(),
                    level = button:GetFrameLevel() }
            end
            -- A high frame level cannot lift a child out of the minimap's LOW render group.
            -- Keep its Minimap anchors, but put its frame in our overlay group.
            button:SetParent(spheres.right.pins)
            if button:GetFrameStrata() ~= "MEDIUM" then button:SetFrameStrata("MEDIUM") end
            button:SetFrameLevel(level)
        end
    end
end

-- Blizzard's group finder eye (QueueStatusButton, 0.5.424, the player's: "should be in front of
-- the map sphere, it's getting behind"): its own frame on UIParent, which Edit Mode anchors to the
-- minimap's edge, so it stood under the globe's smoke and glass. It stays where Blizzard and Edit
-- Mode put it; only its layer goes over the globe, as the minimap's own buttons'.
local function raiseOver(f, level)
    if not f or (f.IsForbidden and f:IsForbidden()) then return end
    if not raisedHomes[f] then raisedHomes[f] = { strata = f:GetFrameStrata(), level = f:GetFrameLevel() } end
    if f:GetFrameStrata() ~= "MEDIUM" then f:SetFrameStrata("MEDIUM") end
    if f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
end

local function raiseMapButtons()
    if not S.MapTaken() or inCombat() or not Minimap or not spheres.right then return end
    local level = spheres.right.pins:GetFrameLevel() + 2
    raiseEach(level, Minimap:GetChildren())
    raiseOver(QueueStatusButton, level)
end

function S.UpdateValueVisibility()
    local always = ns.db and ns.db.sphereValuesAlways == true
    local left = spheres.left
    if left then
        local show = always or left.valueHover
        left.over.health:SetShown(show and true or false)
        left.over.power:SetShown(show and not left.innerPowerActive or false)
        left.innerPower.over.value:SetShown(show and left.innerPowerActive or false)
        if show then S.UpdateLeft() end
        local p = left.pet
        if p then -- its own: while it is hovered, or always
            p.over.health:SetShown((always or p.valueHover) and true or false)
            S.UpdatePet()
        end
    end
    local right = spheres.right
    if right then
        local show = not S.edit.mode and S.MapTaken() and (always or right.coordsHover)
        right.coords:SetShown(show and true or false)
        right.zone:SetShown(show and true or false)
        if show then
            S.UpdateCoords()
            S.UpdateZoneName()
        end
    end
end

-- A place on a map in the world: its continent and yards (x grows north, y west), or nil.
-- C_Map hands each answer back as a Vector2D, a table with the mixin's methods copied in: one
-- probe for every question, and what is asked often (where you are) doesn't come this way.
local probe
local function worldAt(map, x, y)
    local M = C_Map
    if not (M and M.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    probe = probe or CreateVector2D(0, 0)
    probe:SetXY(x, y)
    local continent, pos = A.call(M.GetWorldPosFromMapPos, map, probe)
    if not num(continent) or type(pos) ~= "table" or not pos.GetXY then return nil end
    local wx, wy = pos:GetXY()
    if num(wx) and num(wy) then return continent, wx, wy end
end

-- Each map's corners in the world, asked once (false: it has none).
local mapRects = {}
local function mapRect(map)
    local r = mapRects[map]
    if r == nil then
        local c0, n0, w0 = worldAt(map, 0, 0)
        local c1, n1, w1 = worldAt(map, 1, 1)
        r = c0 and c0 == c1 and n0 ~= n1 and w0 ~= w1
            and { continent = c0, north = n0, west = w0, tall = n0 - n1, wide = w0 - w1 } or false
        mapRects[map] = r
    end
    return r or nil
end

-- Where you are on your map (0 to 1 across and down), or nil where there's none. UnitPosition's
-- plain numbers through the map's corners; the map's own answer (C_Map.GetPlayerMapPosition, a new
-- Vector2D each time: the coordinates ask five times a second, the quest arrow often too: 0.5.419,
-- "it still climbs every second") only where UnitPosition says nothing or you're off its map.
local function playerMap()
    local M = C_Map
    if not (M and M.GetBestMapForUnit) then return nil end
    local map = A.call(M.GetBestMapForUnit, "player")
    if not num(map) then return nil end
    local r = mapRect(map)
    if r and UnitPosition then
        local wx, wy, _, instance = UnitPosition("player")
        if num(wx) and num(wy) and num(instance) and instance == r.continent then
            local x, y = (r.west - wy) / r.wide, (r.north - wx) / r.tall
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return map, x, y end
        end
    end
    if not M.GetPlayerMapPosition then return nil end
    local pos = A.call(M.GetPlayerMapPosition, map, "player")
    if type(pos) ~= "table" or not pos.GetXY then return nil end
    local x, y = pos:GetXY()
    if num(x) and num(y) and not (x == 0 and y == 0) then return map, x, y end
end

-- Where you are on your map, in percent, or nil where there's none.
function S.Coords()
    local _, x, y = playerMap()
    if not x then return nil end
    return x * 100, y * 100
end

-- Blizzard's own formats, tenths if you asked for them (the coordsByTenths CVar).
local COORD_ANGLE = math.rad(-135)
local COORD_RADIUS = BALL * 0.44 - S.ORB_INNER_TEXT
local COORD_CURVE_RADIUS = BALL * 0.42
local function setCoordinateText(c, value)
    setCurvedText(c, value, COORD_ANGLE, COORD_RADIUS, nil, nil, nil, COORD_CURVE_RADIUS)
end
function S.UpdateCoords()
    local c = spheres.right and spheres.right.coords
    if not c then return end
    local x, y = S.Coords()
    if not x then
        setCoordinateText(c, "")
    elseif GetCVarBool and GetCVarBool("coordsByTenths") then
        setCoordinateText(c, string.format(MINIMAP_PLAYER_COORDS or "%.1f, %.1f", x, y))
    else
        setCoordinateText(c, string.format(MINIMAP_PLAYER_COORDS_INTEGER or "%d, %d", math.floor(x + 0.5), math.floor(y + 0.5)))
    end
end

function S.UpdateZoneName()
    local zone = spheres.right and spheres.right.zone
    if not zone then return end
    local name = GetMinimapZoneText and GetMinimapZoneText()
    if (type(name) ~= "string" or name == "") and GetZoneText then name = GetZoneText() end
    if type(name) ~= "string" then name = "" end
    setCurvedText(zone, name, math.rad(47), BALL * 0.45, 112, math.rad(-90), true, BALL / 2, 4)
end

local function points(f)
    local pts = {}
    for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) do pts[i] = { f:GetPoint(i) } end
    return pts
end

local function mailFrame()
    local c = MinimapCluster
    return c and c.IndicatorFrame and c.IndicatorFrame.MailFrame or MiniMapMailFrame
end
-- Keep Blizzard's mail frame and tooltip. Its own visibility controls the brass trim.
local function pinMail(f)
    local o = spheres.right
    if not (f and o) then return end
    if not pinned[f] then
        pinned[f] = { parent = f:GetParent(), points = points(f), scale = f:GetScale(), level = f:GetFrameLevel() }
    end
    if not pinHooked[f] then
        pinHooked[f] = true
        if hooksecurefunc then
            hooksecurefunc(f, "SetPoint", function()
                if not placing and pinned[f] and S.MapTaken() then pinMail(f) end
            end)
        end
        f:HookScript("OnShow", function()
            if pinned[f] and S.MapTaken() then o.mailBadge:Show() end
        end)
        f:HookScript("OnHide", function() o.mailBadge:Hide() end)
    end
    local retail = ns.Retail
    if retail and retail.PrepareMailParent then retail.PrepareMailParent(o.pins) end
    placing = true
    if f:GetParent() ~= o.pins then f:SetParent(o.pins) end
    f:ClearAllPoints()
    f:SetPoint("CENTER", o.mailBadge, "CENTER")
    local width = f:GetWidth()
    if num(width) and width >= 8 and width <= 64 then
        f:SetScale(14 / width)
    end
    f:SetFrameLevel(o.mailBadge:GetFrameLevel() + 1)
    o.mailBadge:SetShown(f:IsShown())
    placing = false
end

local function unpinAll()
    placing = true
    for f, home in pairs(pinned) do
        f:SetParent(home.parent)
        f:ClearAllPoints()
        for _, p in ipairs(home.points) do f:SetPoint(unpack(p)) end
        f:SetScale(home.scale)
        f:SetFrameLevel(home.level)
    end
    if spheres.right and spheres.right.mailBadge then spheres.right.mailBadge:Hide() end
    placing = false
    wipe(pinned)
end

-- What you super-track, as a continent and a world position (yards: x grows north, y west), or
-- nil: a quest's next waypoint on your map (on the way to another zone), else its place on your
-- map, else its next waypoint anywhere; or your map pin. Any hidden answer: none.
local questTarget = {}
local function trackedSpot(map)
    local T, Q, M = C_SuperTrack, C_QuestLog, C_Map
    if not T then return nil end
    local quest = T.IsSuperTrackingQuest and A.call(T.IsSuperTrackingQuest)
    if num(quest) and quest and Q then
        local id = A.call(T.GetSuperTrackedQuestID)
        if not num(id) then return nil end
        local x, y = A.call(Q.GetNextWaypointForMap, id, map)
        if num(x) and num(y) then return map, x, y, id, "waypoint" end
        local pois = A.call(Q.GetQuestsOnMap, map)
        for _, poi in ipairs(type(pois) == "table" and pois or {}) do
            if num(poi.questID) and poi.questID == id and num(poi.x) and num(poi.y) then
                return map, poi.x, poi.y, id, "quest"
            end
        end
        if Q.GetNextWaypoint then
            local ok, m, wx, wy = pcall(Q.GetNextWaypoint, id)
            if ok and num(m) and num(wx) and num(wy) then return m, wx, wy, id, "waypoint" end
        end
        return nil
    end
    local pinned = T.IsSuperTrackingUserWaypoint and A.call(T.IsSuperTrackingUserWaypoint)
    if num(pinned) and pinned and M and M.GetUserWaypoint then
        local pin = A.call(M.GetUserWaypoint)
        local at = type(pin) == "table" and pin.position
        if not (at and at.GetXY and num(pin.uiMapID)) then return nil end
        local x, y = at:GetXY()
        if num(x) and num(y) then return pin.uiMapID, x, y, "map pin", "pin" end
    end
end
function S.FindQuestTarget()
    wipe(questTarget)
    local map = playerMap()
    if not map then return end
    local m, x, y, what, kind = trackedSpot(map)
    if not m then return end
    questTarget.continent, questTarget.x, questTarget.y = worldAt(m, x, y)
    questTarget.what, questTarget.kind = what, kind
end

-- Your corpse while you're a ghost, as a continent and a world position, or nothing: on your map,
-- else the maps it sits in (a corpse over a zone's edge).
local corpseTarget = {}
function S.FindCorpse()
    wipe(corpseTarget)
    local ghost = A.call(UnitIsGhost, "player")
    local D = C_DeathInfo
    if not (num(ghost) and ghost and D and D.GetCorpseMapPosition) then return end
    local map = playerMap()
    for _ = 1, 4 do
        if not map then return end
        local at = A.call(D.GetCorpseMapPosition, map)
        if type(at) == "table" and at.GetXY then
            local x, y = at:GetXY()
            if num(x) and num(y) then
                corpseTarget.continent, corpseTarget.x, corpseTarget.y = worldAt(map, x, y)
                return
            end
        end
        local info = C_Map and C_Map.GetMapInfo and A.call(C_Map.GetMapInfo, map)
        map = type(info) == "table" and num(info.parentMapID) and info.parentMapID > 0 and info.parentMapID or nil
    end
end

-- Toward the target on the minimap: its angle (counter-clockwise from the right, as textures turn),
-- how far it is and how far the minimap shows (yards); nil without a target, or on a rotating
-- minimap without your facing.
-- Where you are in the world on `continent` (yards, x north, y west), or nil. UnitPosition answers
-- plain numbers; the map's way hands back a new Vector2D each call, garbage every frame (0.5.418:
-- "memory consumption ... slightly increased"), so it's only where UnitPosition says nothing.
local positionVia
local function playerWorld(continent)
    if UnitPosition then
        local x, y, _, instance = UnitPosition("player")
        if num(x) and num(y) and num(instance) and instance == continent then
            positionVia = "UnitPosition"
            return x, y
        end
    end
    local map, px, py = playerMap()
    if not map then return nil end
    local c, x, y = worldAt(map, px, py)
    if c == continent then
        positionVia = "the map"
        return x, y
    end
end

local function bearingTo(target)
    if not target.continent then return nil end
    local x, y = playerWorld(target.continent)
    if not x then return nil end
    local north, west = target.x - x, target.y - y
    local bearing = math.atan2(west, north) -- counter-clockwise from north
    local Mm = C_Minimap
    local ignored = Mm and A.call(Mm.IsRotateMinimapIgnored)
    if GetCVarBool and GetCVarBool("rotateMinimap") and not (num(ignored) and ignored) then
        local facing = A.call(GetPlayerFacing) -- 0 north, counter-clockwise; it points up
        if not num(facing) then return nil end
        bearing = bearing - facing
    end
    return math.pi / 2 + bearing, math.sqrt(north * north + west * west)
end
function S.QuestBearing() return bearingTo(questTarget) end
function S.CorpseBearing() return bearingTo(corpseTarget) end
local function viewRadius()
    local view = C_Minimap and A.call(C_Minimap.GetViewRadius)
    return num(view) and view or nil
end

-- How far the target is, to judge whether the minimap shows its arrow: for a quest's own place,
-- the game's distance to the quest (to its nearest objective area, it seems: the minimap dropped
-- its arrow before the place's middle came into view, 0.5.416), none inside the quest's area;
-- else the straight line.
local function arrowDistance(far)
    local quest = questTarget.kind == "quest" and questTarget.what
    if not quest then return far end
    local inside = C_Minimap and A.call(C_Minimap.IsInsideQuestBlob, quest)
    if num(inside) and inside then return 0 end
    local d2 = C_QuestLog and A.call(C_QuestLog.GetDistanceSqToQuest, quest)
    if num(d2) and d2 >= 0 then return math.min(far, math.sqrt(d2)) end
    return far
end

-- Where the griffin covers the minimap's arrow (QUEST_ARROW.griffin), while it stands and the
-- questArrow setting is on.
local function behindGriffin(angle)
    if not (ns.db and ns.db.statueFinish ~= "none" and ns.db.questArrow ~= false) then return false end
    local deg = (math.deg(angle) + 180) % 360 - 180
    return deg >= QUEST_ARROW.griffin[1] and deg <= QUEST_ARROW.griffin[2]
end

-- The copy of the minimap's arrow: on the map's rim toward the target, while the game shows its
-- own there and the griffin covers it.
local function placeArrow(o, arrow, angle)
    if arrow.angle and math.abs(arrow.angle - angle) < 0.001 then return end -- still: no calls
    arrow.angle = angle
    local r = MAP_SIZE / 2 * QUEST_ARROW.reach
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", o, "CENTER", r * math.cos(angle), r * math.sin(angle))
    if arrow.texture.SetRotation then arrow.texture:SetRotation(angle - math.pi / 2) end
end
local function updateArrow(o, arrow, target, distance)
    local angle, far
    if S.MapTaken() then angle, far = bearingTo(target) end
    local view = angle and viewRadius()
    if not (angle and view and behindGriffin(angle) and (distance and distance(far) or far) > view) then
        arrow:Hide()
        arrow.angle = nil
        return
    end
    placeArrow(o, arrow, angle)
    arrow:Show()
end
function S.UpdateQuestArrow()
    local o = spheres.right
    if not (o and o.questArrow) then return end
    updateArrow(o, o.questArrow, questTarget, arrowDistance)
    updateArrow(o, o.corpseArrow, corpseTarget)
end
-- Every frame while they show: only their place (whether they should show is S.UpdateQuestArrow's,
-- every QUEST_ARROW.idle).
function S.MoveQuestArrow()
    local o = spheres.right
    if not o then return end
    local arrow = o.questArrow
    if arrow and arrow:IsShown() then
        local angle = bearingTo(questTarget)
        if angle then placeArrow(o, arrow, angle) end
    end
    arrow = o.corpseArrow
    if arrow and arrow:IsShown() then
        local angle = bearingTo(corpseTarget)
        if angle then placeArrow(o, arrow, angle) end
    end
end

-- For /spheres debug: what the arrow follows, how far, which way and whether it shows.
local function questArrowState()
    if ns.db and ns.db.questArrow == false then return "off (the setting)" end
    if not questTarget.continent then
        return C_SuperTrack and "nothing tracked, or no place for it here" or "no C_SuperTrack"
    end
    local angle, far = S.QuestBearing()
    local view = viewRadius()
    if not angle then return string.format("%s, but no bearing (instance or facing hidden)", tostring(questTarget.what)) end
    local zoom = Minimap and Minimap.GetZoom and A.call(Minimap.GetZoom, Minimap)
    -- the game's own distance to a quest, and whether you're inside its area: what may decide
    -- when the minimap's arrow goes (0.5.408: it went sooner than ours)
    local quest, engine = num(questTarget.what) and questTarget.what, ""
    if quest then
        local d2 = C_QuestLog and A.call(C_QuestLog.GetDistanceSqToQuest, quest)
        local inside = C_Minimap and A.call(C_Minimap.IsInsideQuestBlob, quest)
        engine = string.format(", quest distance %s, %s its area", num(d2) and string.format("%.0f yd", math.sqrt(d2)) or "?",
            not num(inside) and "?" or (inside and "inside" or "outside"))
    end
    return string.format("%s %.0f yd at %.0f degrees (you by %s), map shows %s yd (zoom %s)%s, %s, %s",
        tostring(questTarget.what), far, math.deg(angle) % 360, tostring(positionVia),
        view and string.format("%.0f", view) or "?", num(zoom) and tostring(zoom) or "?",
        engine, behindGriffin(angle) and "behind the griffin" or "clear of the griffin",
        spheres.right.questArrow:IsShown() and "shown" or "hidden")
end

-- For /spheres debug: the corpse arrow's state.
local function corpseArrowState()
    if ns.db and ns.db.questArrow == false then return "off (the setting)" end
    if not corpseTarget.continent then return "no corpse (alive, or not found on your maps)" end
    local angle, far = bearingTo(corpseTarget)
    if not angle then return "corpse, but no bearing" end
    return string.format("corpse %.0f yd at %.0f degrees, %s, %s", far, math.deg(angle) % 360,
        behindGriffin(angle) and "behind the griffin" or "clear of the griffin",
        spheres.right.corpseArrow:IsShown() and "shown" or "hidden")
end

function S.PlaceMinimap()
    local o = spheres.right
    if not (Minimap and o) or inCombat() then return false end
    local retail = ns.Retail
    local container = retail and retail.MinimapContainer and retail.MinimapContainer()
    if container then
        if not mapHome then
            local pts = {}
            for i = 1, (container.GetNumPoints and container:GetNumPoints() or 0) do
                pts[i] = { container:GetPoint(i) }
            end
            mapHome = { container = container, parent = container:GetParent(), points = pts,
                w = container:GetWidth(), h = container:GetHeight(), scale = container:GetScale(),
                strata = container:GetFrameStrata(), level = container:GetFrameLevel() }
        end
        -- Retail anchors the engine minimap inside MinimapContainer. Move that wrapper so
        -- Blizzard keeps ownership of the map itself while Spheres owns its position.
        placing = true
        local ok, err = pcall(function()
            if container:GetParent() ~= o.mapHolder then container:SetParent(o.mapHolder) end
            container:ClearAllPoints()
            container:SetPoint("CENTER", o, "CENTER", 0, 0)
            container:SetScale(MAP_SIZE / 198)
            if container.SetFrameStrata then container:SetFrameStrata("LOW") end
            container:SetFrameLevel(o.mapHolder:GetFrameLevel())
            Minimap:SetFrameStrata("LOW")
            Minimap:SetFrameLevel(o.mapHolder:GetFrameLevel())
            if Minimap.SetMaskTexture then Minimap:SetMaskTexture(MEDIA .. "MaskMap") end
            o.mapDissolve:Show()
        end)
        placing = false
        if not ok then
            S.mapError = tostring(err)
            if not S.mapErrorReported and ns.Say then
                S.mapErrorReported = true
                ns.Say("Retail minimap could not be moved: " .. S.mapError)
            end
            return false
        end
        S.mapError = nil
    else
        if not mapHome then
            local pts = {}
            for i = 1, (Minimap.GetNumPoints and Minimap:GetNumPoints() or 0) do pts[i] = { Minimap:GetPoint(i) } end
            mapHome = { parent = Minimap:GetParent(), points = pts, w = Minimap:GetWidth(), h = Minimap:GetHeight(),
                strata = Minimap:GetFrameStrata(), level = Minimap:GetFrameLevel() }
        end
        placing = true
        if Minimap:GetParent() ~= o.mapHolder then Minimap:SetParent(o.mapHolder) end
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", o, "CENTER", 0, 0)
        Minimap:SetSize(MAP_SIZE, MAP_SIZE)
        if Minimap.SetFrameStrata then Minimap:SetFrameStrata("LOW") end
        Minimap:SetFrameLevel(o.mapHolder:GetFrameLevel())
        if Minimap.SetMaskTexture then Minimap:SetMaskTexture(MEDIA .. "MaskMap") end
        o.mapDissolve:Show()
        placing = false
    end
    o.clouds:Show()
    -- its zoom buttons and the compass ring would sit on the glass: out of sight (the mouse
    -- wheel zooms instead)
    stow(Minimap.ZoomIn)
    stow(Minimap.ZoomOut)
    if retail and retail.MinimapCoordinates then stow(retail.MinimapCoordinates()) end
    pinMail(mailFrame())
    stow(MinimapCluster)
    if not o.coordsHoverHooked and Minimap.HookScript then
        o.coordsHoverHooked = true
        Minimap:HookScript("OnEnter", function()
            if S.MapTaken() then
                o.coordsHover = true
                S.UpdateValueVisibility()
            end
        end)
        Minimap:HookScript("OnLeave", function()
            o.coordsHover = false
            S.UpdateValueVisibility()
        end)
    end
    if MinimapCompassTexture then MinimapCompassTexture:Hide() end
    raiseMapButtons()
    if not o.buttonScan then
        o.buttonScan = true
        o.pins.buttonScanElapsed = 0
        o.pins:SetScript("OnUpdate", A.Timed("minimap buttons scan", function(self, elapsed)
            self.buttonScanElapsed = self.buttonScanElapsed + (elapsed or 0)
            if self.buttonScanElapsed >= 1 then
                self.buttonScanElapsed = 0
                raiseMapButtons()
            end
        end))
    end
    if Minimap.EnableMouseWheel then Minimap:EnableMouseWheel(true) end
    if not o.wheel and Minimap.HookScript then
        o.wheel = true
        Minimap:HookScript("OnMouseWheel", function(m, d)
            if not S.MapTaken() or not (m.GetZoom and m.SetZoom and m.GetZoomLevels) then return end
            local z = m:GetZoom() + (d > 0 and 1 or -1)
            if z >= 0 and z < m:GetZoomLevels() then m:SetZoom(z) end
        end)
    end
    return true
end

function S.GiveBackMinimap()
    if not (mapHome and Minimap) or inCombat() then return false end
    placing = true
    if mapHome.container then
        local container = mapHome.container
        container:SetParent(mapHome.parent)
        container:ClearAllPoints()
        for _, p in ipairs(mapHome.points) do container:SetPoint(unpack(p)) end
        container:SetSize(mapHome.w, mapHome.h)
        container:SetScale(mapHome.scale)
        if container.SetFrameStrata and mapHome.strata then container:SetFrameStrata(mapHome.strata) end
        if mapHome.level then container:SetFrameLevel(mapHome.level) end
    else
        Minimap:SetParent(mapHome.parent)
        Minimap:ClearAllPoints()
        for _, p in ipairs(mapHome.points) do Minimap:SetPoint(unpack(p)) end
        Minimap:SetSize(mapHome.w, mapHome.h)
        if Minimap.SetFrameStrata and mapHome.strata then Minimap:SetFrameStrata(mapHome.strata) end
        if mapHome.level then Minimap:SetFrameLevel(mapHome.level) end
    end
    placing = false
    unpinAll()
    for button, home in pairs(mapButtonHomes) do
        button:SetParent(home.parent)
        button:SetFrameStrata(home.strata)
        button:SetFrameLevel(home.level)
        mapButtonHomes[button] = nil
    end
    for f, home in pairs(raisedHomes) do
        f:SetFrameStrata(home.strata)
        f:SetFrameLevel(home.level)
        raisedHomes[f] = nil
    end
    if spheres.right then
        if spheres.right.mapDissolve then spheres.right.mapDissolve:Hide() end
        spheres.right.clouds:Hide()
        spheres.right.coordsHover = false
        spheres.right.coords:Hide()
    end
    for f, parent in pairs(mapHidden) do f:SetParent(parent) end
    wipe(mapHidden)
    if MinimapCompassTexture then MinimapCompassTexture:Show() end
    mapHome = nil
    return true
end

-------------------------------------------------------------------------------
-- Blizzard's player frame: the left orb shows your health and mana instead
-------------------------------------------------------------------------------
local playerParent, playerHolder
function S.UpdatePlayerFrame()
    local f = PlayerFrame
    if not f or inCombat() then return end
    local hide = ns.db.hidePlayerFrame
    if hide and not playerParent then
        playerHolder = playerHolder or CreateFrame("Frame")
        playerHolder:Hide()
        playerParent = f:GetParent()
        f:SetParent(playerHolder)
    elseif not hide and playerParent then
        f:SetParent(playerParent)
        playerParent = nil
    end
end
function S.PlayerFrameHidden() return playerParent ~= nil end

-------------------------------------------------------------------------------
-- Layout (out of combat): the size, the statues, the minimap
-------------------------------------------------------------------------------
-- The HUD's width and the art's finish for the Statues setting: the statues shown or not, Modern
-- or Charcoal, with the frame finish matching. Returns half the HUD's width.
local function paintArt()
    local statues = not (ns.db and ns.db.statueFinish == "none")
    local inset = S.FrameInset()
    local half = (statues and HALF.statues or HALF.bare) - inset
    hud:SetSize(2 * half, 260)
    art.statueL:SetShown(statues)
    art.statueR:SetShown(statues)
    local finish = finishSuffix()
    for side, o in pairs(spheres) do
        o:ClearAllPoints()
        o:SetPoint("CENTER", art.frameAnchor, "BOTTOM", side == "left" and -S.OrbOffset() or S.OrbOffset(), ORB_Y)
    end
    art.statueL:SetTexture(MEDIA .. "StatueLeft" .. finish)
    art.statueR:SetTexture(MEDIA .. griffinFile())
    if spheres.left and spheres.left.levelRing then
        if finish == "Modern" then spheres.left.levelRing:SetVertexColor(0.62, 0.68, 0.74)
        else spheres.left.levelRing:SetVertexColor(0.80, 0.62, 0.36) end
    end
    if spheres.left and spheres.left.levelBadge then
        spheres.left.levelBadge:ClearAllPoints()
        spheres.left.levelBadge:SetPoint("CENTER", art.frameAnchor, "BOTTOM", S.SocketOffset("left"))
    end
    if spheres.right and spheres.right.mailBadge then
        local mailX, mailY = S.SocketOffset("right")
        spheres.right.mailBadge:ClearAllPoints()
        spheres.right.mailBadge:SetPoint("CENTER", art.frameAnchor, "BOTTOM", mailX, mailY + 28)
    end
    local layout = ns.db and ns.db.statueLayout
    local spread = tonumber(layout and layout.x) or 0
    local vertical = -3 + (tonumber(layout and layout.y) or 0)
    local scale = math.max(0.7, math.min(1.3, tonumber(layout and layout.scale) or 1))
    art.statueL:SetSize(ART.statueL[1] * scale, ART.statueL[2] * scale)
    art.statueL:ClearAllPoints()
    art.statueL:SetPoint("BOTTOM", art.frameAnchor, "BOTTOM", ART.statueL[3] - spread + inset, ART.statueL[4] + vertical)
    art.statueR:SetSize(ART.statueR[1] * scale, ART.statueR[2] * scale)
    art.statueR:ClearAllPoints()
    art.statueR:SetPoint("BOTTOM", art.frameAnchor, "BOTTOM", ART.statueR[3] + spread - inset,
        ART.statueR[4] + vertical + (finish == "Modern" and 2 or 0))
    art.frame:SetTexture(MEDIA .. frameFile(frameSlots))
    art.frame:SetSize(ART.frame[1] - 2 * inset, ART.frame[2])
    art.frame:ClearAllPoints()
    art.frame:SetPoint("BOTTOM", art.frameAnchor, "BOTTOM", ART.frame[3], ART.frame[4] + (finish == "Modern" and ART.modernFrameY or 0))
    return half
end
-- for tools/sim_bridge.lua: the frame and the statues (buildArt), finished as S.Layout finishes them
S.Liquids.art = function()
    if not art then buildArt() end
    paintArt()
    return art
end

-- The `slosh` setting turned on or off: each liquid's motion at rest. In combat too.
function S.ApplySlosh()
    local o = spheres.left
    if not (o and o.liquids) then return end
    local on = sloshOn()
    for _, bar in ipairs(o.liquids) do
        if bar.sloshOn ~= on then
            bar.sloshOn = on
            ns.Motion.Reset(bar)
            bar.sloshShift, bar.sloshLift = 0, 0
        end
    end
end

function S.Layout()
    if not hud then return true end
    S.ApplySlosh()
    if inCombat() then pending = true; return false end
    pending = false
    S.PlaceHud()
    local db = ns.db
    local half = paintArt()
    -- as big as asked, but never wider than the screen
    local scale, W = db.scale or 1, UIParent:GetWidth()
    if num(W) and W > 0 then scale = math.min(scale, (W - 8) / (2 * half)) end
    S.fit = scale
    hud:SetScale(scale)
    placeTop()
    -- Paint the player spheres before touching the Retail minimap hierarchy. If a client
    -- refuses a minimap move, the health and power update must still complete.
    S.UpdatePlayerFrame()
    S.UpdateValueVisibility()
    S.UpdateLeft()
    S.UpdatePet()
    if db.minimap then S.PlaceMinimap() else S.GiveBackMinimap() end
    return true
end

function S.Pending() return pending end

-- The frame's top edge in UIParent's coordinates: open rings stay above it (Ring.lua).
function S.ArtTop()
    local b = top and top:GetBottom()
    if not num(b) then return nil end
    return b * top:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- An orb's centre in UIParent's coordinates, where the rings' buttons' centres sit (a button,
-- in UIParent's size, OVERLAP over the ball's edge, which scales with the HUD), and its ball's
-- radius (for Ring.lua).
function S.Geometry(side)
    local o = spheres[side]
    if not (o and o:IsShown()) then return nil end
    local x, y = o:GetCenter()
    if not (num(x) and num(y)) then return nil end
    local s = o:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * s, y * s, (BALL / 2 + A.HUB_SIZE / 2 - OVERLAP) * s, BALL / 2 * s, s
end

-- The HUD's scale in UIParent's units (the setting, shrunk to fit the screen): the docked hubs'.
function S.HudScale()
    if not hud then return 1 end
    local s = hud:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (num(s) and s > 0) and s or 1
end

function S.SocketPosition(side)
    local anchor = art and art.frameAnchor
    if not anchor then return nil end
    local x, y = anchor:GetCenter()
    local bottom = anchor:GetBottom()
    if not (num(x) and num(y) and num(bottom)) then return nil end
    local scale = hud:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local socketX, socketY = S.SocketOffset(side)
    return x * scale + socketX * scale, bottom * scale + socketY * scale
end

-- Which orb is nearer a point (UIParent's coordinates).
function S.Nearest(px, py)
    local best, bd
    for side in pairs(spheres) do
        local x, y = S.Geometry(side)
        if x then
            local d = (px - x) ^ 2 + (py - y) ^ 2
            if not bd or d < bd then best, bd = side, d end
        end
    end
    return best
end

function S.Debug()
    return string.format("orbs: scale %.2f (asked %.2f, screen %.0f wide), frame with %d slot(s), statues %s, health %s, power %s, minimap %s (%s), player frame %s",
        S.fit or 0, ns.db.scale or 1, UIParent:GetWidth() or 0, frameSlots, ns.db.statueFinish or "modern",
        (filled.health or "-") .. ", heals " .. (secret(filled.heals) and "hidden" or tostring(filled.heals or "-")), filled.power or "-", S.MapTaken() and "in the right orb" or "Blizzard's",
        Minimap and Minimap:GetParent() and (Minimap:GetParent() == (spheres.right and spheres.right.mapHolder) and "parent ours" or "parent Blizzard's") or "none",
        S.PlayerFrameHidden() and "hidden" or "shown") .. string.format(", minimap header %s, mail %s, coordinates %s",
        MinimapCluster and mapHidden[MinimapCluster] and "hidden" or "shown",
        mailFrame() and (pinned[mailFrame()] and "by the menu" or "Blizzard's") or "none",
        S.Coords() and string.format("%.1f, %.1f", S.Coords()) or "none here")
        .. ", quest arrow " .. (spheres.right and questArrowState() or "-")
        .. ", corpse arrow " .. (spheres.right and corpseArrowState() or "-")
end

-- A region's height for /spheres debug: laid out from a hidden value, the game hides it too.
local function heightText(region)
    local h = region and region:GetHeight()
    return h == nil and "?" or (secret(h) and "hidden" or string.format("%.0f", h))
end

-- One liquid's state, for /spheres debug: is it shown, how big, its fill texture and value, and
-- how high its moving layers are clipped (as high as the fill, when the clip follows it).
local function liquidState(name, bar)
    local tex = bar:GetStatusBarTexture()
    local v = bar:GetValue()
    local file = tex and tex.GetTexture and tex:GetTexture()
    return string.format("%s: %s %.0fx%.0f, fill %s (%s), %s high, value %s",
        name, bar:IsVisible() and "visible" or "HIDDEN", bar:GetWidth() or 0, bar:GetHeight() or 0,
        tex and "set" or "NONE", num(file) and tostring(file) or "?", heightText(tex),
        secret(v) and "hidden" or tostring(v))
        .. (bar.clip and string.format(", %d moving layers clipped %s high", #bar.motion,
            heightText(bar.clip)) or ", no moving layers (no clipping)")
end

function S.LiquidDebug()
    local o = spheres.left
    if not o then return "no orbs" end
    local p = o.pet
    local split = p.health:IsShown()
    local health = o.innerPowerActive and o.wholeHealth or o.health
    local power = o.innerPowerActive and o.innerPower.bar or o.power
    return liquidState("health", health) .. "\n  " .. liquidState("power", power)
        .. "\n  " .. liquidState("pet", split and p.health or p.whole)
        .. (split and "\n  " .. liquidState("pet mana", p.mana) or "")
        .. string.format("\n  pet orb %s, %s, mood %s", p:IsShown() and "shown" or "hidden (no pet)",
            split and "health and mana" or "whole", tostring(p.moodLevel or "-"))
        .. string.format("\n  received heal notices %d, currently %s", o.healNotice.count,
            o.healNotice:IsVisible() and "visible" or "hidden")
        .. string.format("\n  damage taken notices %d, currently %s", o.damageNotice.count,
            o.damageNotice:IsVisible() and "visible" or "hidden")
        .. string.format("\n  mana's magic: %s (%s)", tostring(o.power.magicLook or "arcane"), magicWhy)
        .. string.format("\n  cracked glass %s: %d blows with plain values over %d%% of health; %d hidden blows the game judged (small over %d%%, large %d%%, huge %d%%)",
            ns.db and ns.db.crackedGlass and "on" or "off", cracksPlain, CRACK.sizes[1].share * 100, cracksHidden,
            CRACK.sizes[1].share * 100, CRACK.sizes[2].share * 100, CRACK.sizes[3].share * 100)
        .. string.format("\n  slosh: %s; %s; health tilt %.1f, bob %.1f", sloshOn() and "on" or "off",
            ns.Motion.SloshDebug(), math.tanh(health.sloshS or 0) * ns.Motion.SLOSH.climb, (health.sloshB or 0) * 5)
end
