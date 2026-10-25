local _, ns = ...

-- How buttons look, shared by the rings and the two rows (copied from Action Ring; each add-on
-- keeps its own copy). Two looks, both Blizzard's
-- own, rebuilt on our frames so none of Blizzard's bar or menu code runs on them:
--   * action buttons: Blizzard_ActionBar ActionButtonTemplate.xml (UI-HUD-ActionBar-IconFrame
--     atlases, icon mask, cooldown inset 3 px, 64% black swipe)
--   * menu buttons: Blizzard_MicroMenu MainMenuBarMicroButtons (UI-HUD-MicroMenu-<name>-Up
--     on UI-HUD-MicroMenu-ButtonBG-Up, the character's portrait)
-- Everything sits on button.art, a plain child frame: it isn't protected, so it can
-- animate and update in combat while the secure button underneath takes the clicks.

local A = {}
ns.Art = A

local AB = C_ActionBar or {}
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
A.secret = secret

function A.call(fn, ...)
    if not fn then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local call = A.call

-- /spheres profile (Core.lua): for a few seconds, how long each busy part of Spheres takes
-- (debugprofilestop, milliseconds) and what it allocates (the Lua heap's growth while it runs:
-- nothing else runs meanwhile), to trace the cost line in /spheres debug to its parts. Busy
-- handlers are wrapped by name; while nothing is measured a wrapped call costs one test.
-- `events`: an OnEvent handler, its events counted too (how often the game sends each).
local timing
local function measured(name, fn, ...)
    local t0, m0 = debugprofilestop(), collectgarbage("count")
    fn(...)
    local spent, grew = debugprofilestop() - t0, collectgarbage("count") - m0
    local slot = timing[name]
    if not slot then slot = { ms = 0, calls = 0, kb = 0 }; timing[name] = slot end
    slot.ms, slot.calls, slot.kb = slot.ms + spent, slot.calls + 1, slot.kb + (grew > 0 and grew or 0)
end
-- An OnEvent handler's cost is told by event ("game events: CURSOR_CHANGED", 0.5.433: the 10 s the
-- player measured had no events at all, and the garbage came from play); those names are made
-- while measuring only, once each.
local byEvent = {}
function A.Timed(name, fn, events)
    return function(...)
        if not timing then return fn(...) end
        local as = name
        if events then
            local event = select(2, ...)
            timing.events[event] = (timing.events[event] or 0) + 1
            local names = byEvent[name]
            if not names then names = {}; byEvent[name] = names end
            as = names[event]
            if not as then as = name .. ": " .. tostring(event); names[event] = as end
        end
        measured(as, fn, ...)
    end
end
function A.StartTiming() timing = { events = {} } end
function A.StopTiming()
    local t = timing
    timing = nil
    return t
end

function A.HasAction(slot) return call(AB.HasAction or HasAction, slot) and true or false end
function A.ActionTexture(slot) return call(AB.GetActionTexture or GetActionTexture, slot) end

-- Whether the game has an atlas: asked once per name (C_Texture.GetAtlasInfo answers with a new
-- table each time; painting the menu ring asked twice a button on every usable event, 0.5.425).
local atlasKnown = {}
function A.AtlasOK(name)
    local known = atlasKnown[name]
    if known == nil then
        known = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
        atlasKnown[name] = known
    end
    return known
end
local function art(t, atlas, file)
    if atlas and A.AtlasOK(atlas) then t:SetAtlas(atlas) elseif file then t:SetTexture(file) end
end
A.SetArt = art
local function num(v) return v ~= nil and not secret(v) end
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"
local ACTION_ARTS = {}

-- Where a button's tooltip goes: away from the screen edges it's nearest to. Below it in
-- the top half (above it the tooltip runs off the top, under a notch), to its left in the
-- right half.
function A.TooltipAnchor(owner)
    local x, y = owner:GetCenter()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if not (x and y and w and h) or secret(x) or secret(y) or secret(w) or secret(h) or w <= 0 or h <= 0 then
        return "ANCHOR_RIGHT"
    end
    local s = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local below, left = y * s > h / 2, x * s > w / 2
    if below then return left and "ANCHOR_BOTTOMLEFT" or "ANCHOR_BOTTOMRIGHT" end
    return left and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

-- Key names as the game abbreviates them on its buttons ("s-1", "m-R").
function A.KeyText(key)
    if not key then return "" end
    return GetBindingText and GetBindingText(key, "KEY_", true) or key
end

-------------------------------------------------------------------------------
-- The action button look
-------------------------------------------------------------------------------
local function hoverHooks(b, a)
    b:HookScript("OnEnter", function() a.hover:Show() end)
    b:HookScript("OnLeave", function() a.hover:Hide(); a.pushed:Hide() end)
    b:HookScript("OnMouseDown", function() a.pushed:Show() end)
    b:HookScript("OnMouseUp", function() a.pushed:Hide() end)
end

function A.BuildAction(b)
    local a = CreateFrame("Frame", nil, b)
    a:SetAllPoints()
    a:EnableMouse(false)
    a.kind = "action"
    a.bg = a:CreateTexture(nil, "BACKGROUND")
    a.bg:SetAllPoints()
    art(a.bg, "UI-HUD-ActionBar-IconFrame-Background", "Interface\\Buttons\\UI-EmptySlot-Disabled")
    a.empty = a:CreateTexture(nil, "BACKGROUND", nil, 1)
    a.empty:SetAllPoints()
    art(a.empty, "ui-hud-actionbar-iconframe-slot", "Interface\\Buttons\\UI-EmptySlot")
    a.icon = a:CreateTexture(nil, "BACKGROUND", nil, 2)
    a.icon:SetAllPoints()
    if a.CreateMaskTexture and A.AtlasOK(ICON_MASK) then
        -- Blizzard's mask (ActionButtonTemplate IconMask) keeps the atlas's own size, bigger
        -- than the 45 px icon, centred on it: only the icon's corners round off. Squeezed to
        -- the icon's size it would cut a black ring round a smaller icon.
        local m = a:CreateMaskTexture()
        m:SetAtlas(ICON_MASK, true)
        m:SetPoint("CENTER", a.icon, "CENTER")
        a.icon:AddMaskTexture(m)
        a.mask = m
        local w, h = m:GetSize()
        if num(w) and num(h) and w > 0 and h > 0 then a.maskW, a.maskH = w, h end
    else
        a.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    if a.CreateMaskTexture then
        a.modernMask = a:CreateMaskTexture()
        a.modernMask:SetTexture("Interface\\AddOns\\Spheres\\Media\\SlotMaskModern")
        a.modernMask:SetAllPoints()
    end
    a.cooldown = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
    a.cooldown:SetPoint("TOPLEFT", a.icon, "TOPLEFT", 3, -3)
    a.cooldown:SetPoint("BOTTOMRIGHT", a.icon, "BOTTOMRIGHT", -3, 3)
    if a.cooldown.SetDrawBling then a.cooldown:SetDrawBling(false) end
    if a.cooldown.SetDrawEdge then a.cooldown:SetDrawEdge(false) end
    if a.cooldown.SetSwipeColor then a.cooldown:SetSwipeColor(0, 0, 0, 0.64) end
    local top = CreateFrame("Frame", nil, a) -- the frame and its states, above the cooldown
    top:SetAllPoints()
    top:SetFrameLevel(a.cooldown:GetFrameLevel() + 1)
    a.top = top
    a.frame = top:CreateTexture(nil, "ARTWORK")
    A.SetBezel(a.frame, "Slot") -- Blizzard's IconFrame's place and size (46 x 45), themed bevel
    a.border = top:CreateTexture(nil, "ARTWORK", nil, 1) -- an equipped item: green
    art(a.border, "UI-HUD-ActionBar-IconFrame-Border", "Interface\\Buttons\\UI-ActionButton-Border")
    a.border:SetVertexColor(0, 1, 0, 0.5)
    a.border:Hide()
    a.checked = top:CreateTexture(nil, "OVERLAY") -- casting / auto-repeating, an open ring's hub
    art(a.checked, "UI-HUD-ActionBar-IconFrame-Mouseover", "Interface\\Buttons\\CheckButtonHilight")
    a.checked:SetBlendMode("ADD")
    a.checked:Hide()
    a.hover = top:CreateTexture(nil, "OVERLAY", nil, 1)
    art(a.hover, "UI-HUD-ActionBar-IconFrame-Mouseover", "Interface\\Buttons\\ButtonHilight-Square")
    a.hover:SetBlendMode("ADD")
    a.hover:Hide()
    a.pushed = top:CreateTexture(nil, "OVERLAY", nil, 2)
    art(a.pushed, "UI-HUD-ActionBar-IconFrame-Down", "Interface\\Buttons\\UI-Quickslot-Depress")
    a.pushed:Hide()
    for _, t in ipairs({ a.frame, a.border, a.checked, a.hover, a.pushed }) do t:SetPoint("TOPLEFT") end
    a.count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    a.count:SetJustifyH("RIGHT")
    a.count:SetPoint("BOTTOMRIGHT", -5, 5)
    a.hotkey = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    a.hotkey:SetJustifyH("RIGHT")
    a.hotkey:SetPoint("TOPRIGHT", -5, -5)
    a.name = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline") -- a macro's name
    a.name:SetPoint("BOTTOM", 0, 2)
    hoverHooks(b, a)
    b.art = a
    ACTION_ARTS[#ACTION_ARTS + 1] = a
    return a
end

-- Blizzard's frame art is 46x45 on a 45 px button, its icon mask the atlas's size: scale
-- them with the button.
function A.SizeAction(a, size)
    a.size = size
    local modern = ns.db and ns.db.statueFinish == "modern"
    local w, h = modern and size or size * 46 / 45, size
    for _, t in ipairs({ a.frame, a.border, a.checked, a.hover, a.pushed }) do t:SetSize(w, h) end
    a.frame:ClearAllPoints()
    if modern then
        a.frame:SetPoint("CENTER", a, "CENTER")
        a.frame:SetSize(size * 48 / 45, size * 48 / 45)
    else a.frame:SetPoint("TOPLEFT", a, "TOPLEFT") end
    if a.maskW then a.mask:SetSize(a.maskW * size / 45, a.maskH * size / 45) end
    if a.modernMask and a.modernMasked ~= modern then
        for _, t in ipairs({ a.icon, a.bg, a.empty }) do
            if modern then t:AddMaskTexture(a.modernMask) else t:RemoveMaskTexture(a.modernMask) end
        end
        if a.mask then
            if modern then a.icon:RemoveMaskTexture(a.mask) else a.icon:AddMaskTexture(a.mask) end
        end
        a.modernMasked = modern
    end
    -- Retain the game's recessed raven slot, with a neutral stone tint for Modern.
    a.bg:SetDesaturated(modern and true or false)
    a.empty:SetDesaturated(modern and true or false)
    local shade = modern and 0.8 or 1
    a.bg:SetVertexColor(shade, shade, shade)
    a.empty:SetVertexColor(shade, shade, shade)
    a.name:SetWidth(size - 4)
end

-- The same look for a spell (a spell fan's button and slots): spell = { id, name }.
local NO_OPTS = {}
local function spellCooldownFromDuration(cd, id) -- no closure per call: painting runs often
    cd:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(id))
end
function A.ShowSpellCooldown(a, id)
    local cd, SPL = a.cooldown, C_Spell or NO_OPTS
    if SPL.GetSpellCooldownDuration and cd.SetCooldownFromDurationObject then
        if pcall(spellCooldownFromDuration, cd, id) then return "duration" end
    end
    local info = call(SPL.GetSpellCooldown, id)
    if type(info) == "table" and not secret(info.startTime) and not secret(info.duration) and not secret(info.isEnabled) then
        if info.isEnabled and info.duration and info.duration > 0 then
            cd:SetCooldown(info.startTime, info.duration, info.modRate)
        else
            cd:Clear()
        end
        return "numbers"
    end
    return "hidden"
end

function A.PaintSpell(b, spell, opts)
    opts = opts or NO_OPTS
    local a, SPL = b.art, C_Spell or NO_OPTS
    a.icon:SetShown(spell ~= nil)
    a.empty:SetShown(spell == nil)
    a.cooldown:SetShown(spell ~= nil)
    a.count:SetText("")
    a.name:SetText("")
    a.border:Hide()
    a.checked:SetShown(opts.lit or false)
    a.hotkey:SetTextColor(0.6, 0.6, 0.6)
    if not spell then
        a.hotkey:SetText(A.KeyText(opts.key))
        return
    end
    a.icon:SetTexture(call(SPL.GetSpellTexture, spell.id))
    if not (opts.keepCooldown and b.cooldownSpell == spell.id) then
        b.cooldownSource, b.cooldownSpell = A.ShowSpellCooldown(a, spell.id), spell.id
    end
    local usable, noMana = call(SPL.IsSpellUsable, spell.id)
    if secret(usable) or secret(noMana) or usable then a.icon:SetVertexColor(1, 1, 1)
    elseif noMana then a.icon:SetVertexColor(0.5, 0.5, 1)
    else a.icon:SetVertexColor(0.4, 0.4, 0.4) end
    local inRange = call(SPL.IsSpellInRange, spell.id) -- nil: no target, or no range
    local out = not secret(inRange) and inRange == false
    local text = A.KeyText(opts.key)
    if text == "" and out then text = RANGE_INDICATOR or "●" end
    a.hotkey:SetText(text)
    if out then a.hotkey:SetTextColor(1, 0.1, 0.1) end
end

-- Cooldowns: Forever hides the numbers from addons in combat but takes a duration object
-- (C_ActionBar.GetActionCooldownDuration) for the sweep. Returns which way it worked.
local function cooldownFromDuration(cd, slot) -- no closure per call: painting runs often
    cd:SetCooldownFromDurationObject(AB.GetActionCooldownDuration(slot))
end
function A.ShowCooldown(a, slot)
    local cd = a.cooldown
    if AB.GetActionCooldownDuration and cd.SetCooldownFromDurationObject then
        if pcall(cooldownFromDuration, cd, slot) then return "duration" end
    end
    local info = call(AB.GetActionCooldown, slot)
    if type(info) == "table" and not secret(info.startTime) and not secret(info.duration) and not secret(info.isEnabled) then
        if info.isEnabled and info.duration and info.duration > 0 then
            cd:SetCooldown(info.startTime, info.duration, info.modRate)
        else
            cd:Clear()
        end
        return "numbers"
    end
    return "hidden"
end

-- One action button's look for an action slot. opts: key (its key binding), lit (shown
-- checked, e.g. an open ring's hub), emptyIcon (shown instead of the empty slot art),
-- showEmpty (the empty slot frame; a strip of Blizzard's bar shows it), keepCooldown (a range
-- and usable refresh: the cooldown stays as last painted for this slot; the game hands back a
-- new duration object each time it's asked, garbage several times a second over the rows).
-- Callers painting often keep one opts table per button rather than making one each time.
function A.PaintAction(b, slot, opts)
    opts = opts or NO_OPTS
    local a = b.art
    local filled = slot and A.HasAction(slot) or false
    a.icon:SetShown(filled or opts.emptyIcon ~= nil)
    a.empty:SetShown(not filled and opts.emptyIcon == nil)
    a.cooldown:SetShown(filled)
    a.hotkey:SetTextColor(0.6, 0.6, 0.6)
    if not filled then
        if opts.emptyIcon then
            a.icon:SetTexture(opts.emptyIcon)
            a.icon:SetVertexColor(1, 1, 1)
        end
        a.count:SetText("")
        a.name:SetText("")
        a.border:Hide()
        a.checked:SetShown(opts.lit or false)
        b.keyText = A.KeyText(opts.key)
        a.hotkey:SetText(b.keyText)
        return
    end
    a.icon:SetTexture(A.ActionTexture(slot))
    if not (opts.keepCooldown and b.cooldownSlot == slot) then
        b.cooldownSource, b.cooldownSlot = A.ShowCooldown(a, slot), slot
    end
    A.PaintUsable(b, slot)
    a.count:SetText(call(AB.GetActionDisplayCount, slot) or "")
    a.name:SetText(call(AB.GetActionText or GetActionText, slot) or "") -- macros: their name
    local equipped = call(AB.IsEquippedAction or IsEquippedAction, slot)
    a.border:SetShown(not secret(equipped) and equipped and true or false)
    local current = call(AB.IsCurrentAction or IsCurrentAction, slot)
    local repeating = call(AB.IsAutoRepeatAction or IsAutoRepeatAction, slot)
    a.checked:SetShown(opts.lit or (not secret(current) and current) or (not secret(repeating) and repeating) or false)
    local inRange = call(AB.IsActionInRange or IsActionInRange, slot)
    b.keyText = A.KeyText(opts.key)
    A.PaintRange(b, not secret(inRange) and inRange == false)
end

-- Usable: white; out of mana: blue; not now: grey (Blizzard's colours). Also alone, for the
-- game's usable events.
function A.PaintUsable(b, slot, usable, noMana)
    if usable == nil then usable, noMana = call(AB.IsUsableAction or IsUsableAction, slot) end
    local icon = b.art.icon
    if secret(usable) or secret(noMana) or usable then icon:SetVertexColor(1, 1, 1)
    elseif noMana then icon:SetVertexColor(0.5, 0.5, 1)
    else icon:SetVertexColor(0.4, 0.4, 0.4) end
end

-- Out of range: the key turns red (Blizzard's look); no key shown: its dot. Also alone, for the
-- game's range event (ACTION_RANGE_CHECK_UPDATE).
function A.PaintRange(b, out)
    local hotkey = b.art.hotkey
    local text = b.keyText or ""
    if text == "" and out then text = RANGE_INDICATOR or "●" end
    hotkey:SetText(text)
    if out then hotkey:SetTextColor(1, 0.1, 0.1) else hotkey:SetTextColor(0.6, 0.6, 0.6) end
end

-------------------------------------------------------------------------------
-- The menu button look (the micro buttons')
-------------------------------------------------------------------------------
function A.BuildMenu(b)
    local a = CreateFrame("Frame", nil, b)
    a:SetAllPoints()
    a:EnableMouse(false)
    a.kind = "menu"
    a.bg = a:CreateTexture(nil, "BACKGROUND")
    a.bg:SetAllPoints()
    art(a.bg, "UI-HUD-MicroMenu-ButtonBG-Up", "Interface\\Buttons\\UI-MicroButton-Up")
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetAllPoints()
    a.portrait = a:CreateTexture(nil, "ARTWORK", nil, 1) -- the character button's
    a.portrait:SetPoint("TOPLEFT", 6, -7)
    a.portrait:SetPoint("BOTTOMRIGHT", -6, 7)
    a.portrait:SetTexCoord(0.2, 0.8, 0.0666, 0.9)
    if a.CreateMaskTexture and A.AtlasOK("UI-HUD-MicroMenu-Portrait-Mask") then
        local m = a:CreateMaskTexture()
        m:SetAtlas("UI-HUD-MicroMenu-Portrait-Mask")
        m:SetAllPoints(a.portrait)
        a.portrait:AddMaskTexture(m)
    end
    a.portrait:Hide()
    a.hover = a:CreateTexture(nil, "OVERLAY")
    a.hover:SetAllPoints()
    a.hover:SetBlendMode("ADD")
    a.hover:Hide()
    a.pushed = a:CreateTexture(nil, "OVERLAY", nil, 1)
    a.pushed:SetAllPoints()
    a.pushed:Hide()
    a.hotkey = a:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    a.hotkey:SetJustifyH("RIGHT")
    a.hotkey:SetPoint("TOPRIGHT", -6, -8)
    hoverHooks(b, a)
    b.art = a
    return a
end

function A.SizeMenu(a, width, height)
    a.portrait:ClearAllPoints()
    a.portrait:SetPoint("TOPLEFT", 6 * width / 32, -7 * height / 40)
    a.portrait:SetPoint("BOTTOMRIGHT", -6 * width / 32, 7 * height / 40)
    a.hotkey:ClearAllPoints()
    a.hotkey:SetPoint("TOPRIGHT", -6 * width / 32, -8 * height / 40)
end

-------------------------------------------------------------------------------
-- The minimap button look (a ring's button docked on a sphere's collar): the dark disc and a round
-- icon, as every minimap button draws them, LibDBIcon's proportions (31 px, disc 24), a little
-- bigger, and the icon filling the disc: at its 18 px the gear read too small (seen in 0.4.0).
-- Round them the finish-matched bevel every button of ours wears (`Media/HubFrame`; the square one,
-- `SlotFrame`, round the action buttons; make_media.py BEZEL, HUB_FRAME): Blizzard's action button
-- frame's thin profile in the HUD's brass, made as the game's bronze frames are (0.5.436, the
-- player's pick from a mockup: "D, but add the texture that game frames have"). Its inner line on
-- the disc's edge. Before: a flat brass band (`HubRing`, 0.5.428-0.5.435), Blizzard's thick
-- MiniMap-TrackingBorder ("too outdated").
-------------------------------------------------------------------------------
A.MINIMAP_SIZE = 36
-- The docked rings' hubs: 0.8 of it, frame and all (0.5.440, the player's: "20% smaller in
-- overall size"; the frame's thickness kept in proportion: "the frame was good").
A.HUB_SIZE = A.MINIMAP_SIZE * 0.8
local BEZEL_TEXTURES = {}
local function bezelTexture(shape)
    local suffix = ns.db and ns.db.statueFinish == "modern" and "Modern" or ""
    return "Interface\\AddOns\\Spheres\\Media\\" .. shape .. "Frame" .. suffix
end
function A.SetBezel(texture, shape)
    texture:SetTexture(bezelTexture(shape))
    BEZEL_TEXTURES[#BEZEL_TEXTURES + 1] = { texture = texture, shape = shape }
end
function A.UpdateBezelStyle()
    for _, item in ipairs(BEZEL_TEXTURES) do item.texture:SetTexture(bezelTexture(item.shape)) end
    for _, a in ipairs(ACTION_ARTS) do if a.size then A.SizeAction(a, a.size) end end
end
A.HUB_FRAME = "Interface\\AddOns\\Spheres\\Media\\HubFrame"
A.SLOT_FRAME = "Interface\\AddOns\\Spheres\\Media\\SlotFrame"
A.HUB_FRAME_INNER = 14 / 36 -- its inner line's radius, of its size: badges size it to their disc

function A.BuildMinimapButton(b, size) -- `size`: the button's (A.MINIMAP_SIZE unless given)
    size = size or A.MINIMAP_SIZE
    local k = size / 31
    local m = CreateFrame("Frame", nil, b)
    m:SetAllPoints()
    m:EnableMouse(false)
    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    m.bg:SetSize(24 * k, 24 * k)
    m.bg:SetPoint("CENTER")
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetSize(22.5 * k, 22.5 * k)
    m.icon:SetPoint("CENTER")
    if m.CreateMaskTexture then
        local mask = m:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(m.icon)
        m.icon:AddMaskTexture(mask)
    else
        m.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    end
    m.border = m:CreateTexture(nil, "OVERLAY")
    A.SetBezel(m.border, "Hub")
    m.border:SetSize(size, size)
    m.border:SetPoint("CENTER")
    m.hover = m:CreateTexture(nil, "OVERLAY", nil, 1)
    m.hover:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    m.hover:SetBlendMode("ADD")
    m.hover:SetAllPoints()
    m.hover:Hide()
    b:HookScript("OnEnter", function() A.MinimapHover(m, true) end)
    b:HookScript("OnLeave", function() if not m.lit then A.MinimapHover(m, false) end end)
    m:Hide()
    b.mini = m
    return m
end

-- A minimap-look button's highlight, on hover and while its ring is open. `m.swapHover`: the
-- highlight is a brighter copy of the icon that stands in for it (the Game Menu's question mark,
-- as Blizzard's own button: its normal art hidden under its Mouseover art), not a glow over it.
function A.MinimapHover(m, on)
    m.hover:SetShown(on)
    if m.swapHover then m.icon:SetAlpha(on and 0 or 1) end
end

-- its icon, and lit while its ring is open
function A.PaintMinimapButton(m, icon, lit) -- `icon`: a texture, or an atlas's name
    if type(icon) == "string" and not icon:find("[\\/]") and A.AtlasOK(icon) then m.icon:SetAtlas(icon)
    else m.icon:SetTexture(icon) end
    m.lit = lit and true or false
    if lit then A.MinimapHover(m, true)
    elseif not (m:GetParent().IsMouseOver and m:GetParent():IsMouseOver()) then A.MinimapHover(m, false) end
end

-- Mirror one of Blizzard's micro buttons: its icon (or the character's portrait), its
-- hover and pressed art.
function A.PaintMenu(b, micro, key)
    local a = b.art
    a.hotkey:SetText(A.KeyText(key))
    if not micro then return end
    local name = micro.textureName
    if micro == CharacterMicroButton then
        a.icon:Hide()
        a.portrait:Show()
        if SetPortraitTexture then pcall(SetPortraitTexture, a.portrait, "player") end
        -- The portrait's mouseover atlas is only a strip; the frame atlas covers the full button.
        art(a.hover, "UI-HUD-MicroMenu-ButtonBG-Up", "Interface\\Buttons\\UI-MicroButton-Hilight")
        a.hover:SetVertexColor(1, 0.78, 0.38)
        a.hover:SetAlpha(0.5)
        art(a.pushed, "UI-HUD-MicroMenu-ButtonBG-Down", nil)
        return
    end
    a.portrait:Hide()
    a.icon:Show()
    local normal = micro.GetNormalTexture and micro:GetNormalTexture()
    local atlas = normal and normal.GetAtlas and normal:GetAtlas()
    if atlas then a.icon:SetAtlas(atlas)
    elseif normal and normal.GetTexture then a.icon:SetTexture(normal:GetTexture()) end
    if name then
        art(a.hover, "UI-HUD-MicroMenu-" .. name .. "-Mouseover", "Interface\\Buttons\\UI-MicroButton-Hilight")
        art(a.pushed, "UI-HUD-MicroMenu-" .. name .. "-Down", nil)
    else
        art(a.hover, nil, "Interface\\Buttons\\UI-MicroButton-Hilight")
    end
end

-------------------------------------------------------------------------------
-- Dragging actions on and off: Blizzard's own rules (pick up when the bars aren't locked,
-- shift when they are; drop a spell, item or macro onto a slot).
-------------------------------------------------------------------------------
function A.BarsLocked()
    local ok, v = pcall(function() return Settings and Settings.GetValue and Settings.GetValue("lockActionBars") end)
    if ok and v ~= nil then return v and true or false end
    return GetCVarBool and GetCVarBool("lockActionBars") or false
end

function A.CursorHoldsAction()
    local kind = GetCursorInfo and GetCursorInfo()
    return kind ~= nil and kind ~= "money" and kind ~= "merchant"
end

function A.SetupDrag(b, onChange)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        if not A.BarsLocked() or IsModifiedClick("PICKUPACTION") then
            PickupAction(self:GetAttribute("action"))
            if onChange then onChange() end
        end
    end)
    b:SetScript("OnReceiveDrag", function(self)
        PlaceAction(self:GetAttribute("action"))
        if onChange then onChange() end
    end)
end

-- An action's own tooltip, or "empty slot".
function A.ActionTooltip(b, emptyText)
    b:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, A.TooltipAnchor(self))
        local slot = self:GetAttribute("action")
        if not (slot and A.HasAction(slot) and GameTooltip.SetAction and GameTooltip:SetAction(slot)) then
            GameTooltip:SetText(emptyText and emptyText(self) or "Empty slot", 1, 1, 1)
            GameTooltip:AddLine("Drag a spell, item or macro here.", 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
