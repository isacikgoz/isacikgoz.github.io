local _, ns = ...

-- The objectives list (Blizzard's ObjectiveTrackerFrame, "All Objectives") starts folded at
-- each login and /reload, not on every loading screen: unfold it and it stays so until next time.
-- Action Ring's (copied: each add-on keeps its own).
--
-- Folding it from addon code writes its collapsed flag, so its updates run tainted until it's
-- unfolded with its own button (Blizzard's click writes the flag again, securely). That's
-- harmless here: folded, it lays nothing out; and its quest item buttons read their quest from
-- an attribute (QuestObjectiveItemButtonMixin:OnClick, Blizzard_ObjectiveTrackerShared), so a
-- click on one still uses the item. Blizzard only unfolds it by itself for scenarios, auto quest
-- pop-ups and the new player tutorial (ForceExpand), none of which Forever's world has.
--
-- Spheres' own (0.5.13, the player's call): folded, it's a brass quest badge the size of a buff,
-- not its header bar. Its own fold button (the header's MinimizeButton) keeps the click, while
-- our red inset and brass plus replace Blizzard's square icon. Unfolded: as Blizzard has it.

local T = {}
ns.Tracker = T

local ICON_SIZE = 27 -- slightly smaller than a buff icon
local FOLD_W, FOLD_H = 18, 19 -- the button as Blizzard makes it (ObjectiveTrackerContainerMinimizeButtonTemplate)

local waiting = false -- folding asked for, the tracker not loaded yet
local deco             -- our look on its button: { edge, count } (kept here, not on Blizzard's frames)
local hooked = false

local function header()
    local f = ObjectiveTrackerFrame
    return f and f.Header, f
end

local function watched()
    local fn = C_QuestLog and C_QuestLog.GetNumQuestWatches or GetNumQuestWatches
    if not fn then return 0 end
    local ok, n = pcall(fn)
    return ok and type(n) == "number" and not (issecretvalue and issecretvalue(n)) and n or 0
end

-- Its button as an icon (folded) or as Blizzard made it (open).
function T.Style()
    local h, f = header()
    local b = h and h.MinimizeButton
    if not (b and f.IsCollapsed) then return end
    local icon = ns.db and ns.db.objectivesIcon and f:IsCollapsed()
    if not deco then
        deco = {}
        local k = ICON_SIZE / 30
        deco.red = b:CreateTexture(nil, "BACKGROUND", nil, -7)
        deco.red:SetColorTexture(0.34, 0.035, 0.03, 1)
        deco.red:SetSize(23 * k, 23 * k)
        deco.red:SetPoint("CENTER")
        deco.frame = b:CreateTexture(nil, "OVERLAY", nil, 2)
        ns.Art.SetBezel(deco.frame, "Slot") -- match the action buttons' current finish (Art.lua)
        deco.frame:SetAllPoints(b)
        deco.plusShadow = {}
        deco.plus = {}
        for i = 1, 2 do
            local layer = i == 1 and deco.plusShadow or deco.plus
            local color = i == 1 and { 0.16, 0.045, 0.015, 0.9 } or { 1, 0.78, 0.34, 1 }
            layer.horizontal = b:CreateTexture(nil, "ARTWORK", nil, i)
            layer.horizontal:SetColorTexture(unpack(color))
            layer.horizontal:SetSize((i == 1 and 14 or 12) * k, (i == 1 and 4 or 2.5) * k)
            layer.horizontal:SetPoint("CENTER", (i == 1 and 0.7 or 0) * k, (i == 1 and -0.7 or 0) * k)
            layer.vertical = b:CreateTexture(nil, "ARTWORK", nil, i)
            layer.vertical:SetColorTexture(unpack(color))
            layer.vertical:SetSize((i == 1 and 4 or 2.5) * k, (i == 1 and 14 or 12) * k)
            layer.vertical:SetPoint("CENTER", (i == 1 and 0.7 or 0) * k, (i == 1 and -0.7 or 0) * k)
        end
        deco.hover = b:CreateTexture(nil, "OVERLAY", nil, 3)
        if deco.hover.SetAtlas then deco.hover:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
        else deco.hover:SetTexture("Interface\\Buttons\\CheckButtonHilight") end
        deco.hover:SetBlendMode("ADD")
        deco.hover:SetAllPoints(b)
        deco.hover:Hide()
        deco.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        deco.count:SetPoint("BOTTOMRIGHT", 2, 0)
        deco.count:SetTextColor(1, 0.82, 0.45)
        b:HookScript("OnEnter", function(self)
            if not deco.on then return end
            deco.hover:Show()
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(OBJECTIVES_TRACKER_LABEL or "Objectives", 1, 1, 1)
            GameTooltip:AddLine(string.format("%d followed. Click to show them.", watched()), 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function()
            deco.hover:Hide()
            if deco.on and GameTooltip then GameTooltip:Hide() end
        end)
    end
    deco.on = icon
    for _, part in ipairs({ h.Background, h.Text }) do if part then part:SetAlpha(icon and 0 or 1) end end
    deco.red:SetShown(icon)
    deco.frame:SetShown(icon)
    for _, layer in ipairs({ deco.plusShadow, deco.plus }) do
        layer.horizontal:SetShown(icon)
        layer.vertical:SetShown(icon)
    end
    deco.hover:SetShown(false)
    deco.count:SetShown(icon)
    local hl = b:GetHighlightTexture()
    if hl and hl.SetAlpha then hl:SetAlpha(icon and 0 or 1) end
    for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture() }) do
        if t and t.SetAlpha then t:SetAlpha(icon and 0 or 1) end
    end
    if icon then
        b:SetSize(ICON_SIZE, ICON_SIZE)
        local n = watched()
        deco.count:SetText(n > 0 and n or "")
    else
        b:SetSize(FOLD_W, FOLD_H) -- Blizzard set its atlases just now (Header:SetCollapsed)
        for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture() }) do t:SetTexCoord(0, 1, 0, 1) end
    end
end

-- Blizzard sets the button's look when it folds or opens: ours after it.
local function hook()
    local h = header()
    if hooked or not (h and h.SetCollapsed and hooksecurefunc) then return end
    hooked = true
    hooksecurefunc(h, "SetCollapsed", function() T.Style() end)
end

function T.Fold()
    local f = ObjectiveTrackerFrame
    if not (f and f.SetCollapsed and f.IsCollapsed) then return false end
    waiting = false
    hook()
    if not f:IsCollapsed() then f:SetCollapsed(true) end
    T.Style()
    return true
end

function T.OnEnteringWorld(isLogin, isReload)
    if not (ns.db and ns.db.foldObjectives) or not (isLogin or isReload) then return end
    waiting = true
    T.Fold()
end

-- Blizzard_ObjectiveTracker loads after us: fold it when it arrives.
function T.OnAddOnLoaded(name)
    if name ~= "Blizzard_ObjectiveTracker" then return end
    hook()
    if waiting then T.Fold() else T.Style() end
end

-- The setting changed, quests followed or not: the icon again.
function T.Apply()
    hook()
    T.Style()
end

function T.Debug()
    local f = ObjectiveTrackerFrame
    local now = f and f.IsCollapsed and (f:IsCollapsed() and "folded" or "open") or "not loaded"
    return string.format("objectives: %s at login, %s now%s", ns.db.foldObjectives and "folded" or "as left", now,
        deco and deco.on and " (an icon)" or "")
end
