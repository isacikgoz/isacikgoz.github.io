local _, ns = ...

-- A quieter chat window, Action Ring's (copied: each add-on keeps its own; Spheres is off while
-- Action Ring is on, so only one of them ever runs this). Every part is a setting (Options ->
-- AddOns -> Spheres -> Chat):
--   * no buttons beside it (chat menu, channels, voice, friends): moved under a hidden frame
--   * the input box only while typing: Blizzard's own Classic chat style (CVar chatStyle),
--     kept in our settings and set again at every login before Blizzard applies it
--   * no background tint: its background and border textures hidden (Blizzard fades only
--     the shown ones, FCF_FadeInChatFrame)
--   * no Combat Log tab: Blizzard closes and docks windows with FCF_Close / FCF_DockFrame
--     (its tab menu offers neither for the Combat Log)
--   * the scroll bar on the left, where the buttons were, a little away from the text
--   * the tabs (General ...) only while the mouse is over the chat, like the scroll bar
--   * channels as [1] rather than [1. General - Durotar]
--
-- Chat is where taint hurts most: a chat line or input box touched by addon code can get
-- /cast or /target typed in chat blocked. So nothing here writes Blizzard's chat tables or
-- input box fields. Frames are hidden by reparenting, moved with SetPoint, Blizzard
-- functions are hooked with hooksecurefunc, and channel names are rewritten through
-- TransformMessages, which Blizzard made for addons (ScrollingMessageFrameSecureMixin, a
-- "secure elevation barrier").

local C = {}
ns.Chat = C

local hidden -- where hidden Blizzard frames live
local parents = {} -- frame -> its own parent, to give it back
local hooked = {} -- chat frames whose AddMessage we follow
local hookedBoxes = {} -- edit boxes with temporary XP-bar positioning
local boxInsets = {} -- original text insets, restored when chat focus leaves
local boxAtXP = {} -- edit boxes that should stay above the XP bar after focus leaves

local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

-- Every chat window the game made (ChatFrame1 ..., and new ones as they come).
local function chatFrames()
    local t = {}
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local f = _G[name]
        if f then t[#t + 1] = f end
    end
    return t
end
C.Frames = chatFrames

-------------------------------------------------------------------------------
-- Buttons beside the chat
-------------------------------------------------------------------------------
-- The chat menu and channel buttons sit in ChatFrame1's button frame; voice mute/deafen,
-- the friends button (QuickJoinToastButton) and text to speech sit on UIParent.
local LOOSE = { "QuickJoinToastButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    "TextToSpeechButtonFrame" }

local function stow(f)
    if not f or parents[f] then return end
    parents[f] = f:GetParent()
    f:SetParent(hidden)
end
local function unstow(f)
    if not (f and parents[f]) then return end
    f:SetParent(parents[f])
    parents[f] = nil
end

local function applyButtons(show)
    for _, f in ipairs(chatFrames()) do
        if f.buttonFrame then if show then unstow(f.buttonFrame) else stow(f.buttonFrame) end end
    end
    for _, name in ipairs(LOOSE) do
        if show then unstow(_G[name]) else stow(_G[name]) end
    end
end

-------------------------------------------------------------------------------
-- Background
-------------------------------------------------------------------------------
local function applyBackground(show)
    for _, f in ipairs(chatFrames()) do
        local name = f:GetName()
        for _, part in ipairs(CHAT_FRAME_TEXTURES or {}) do
            local t = _G[name .. part]
            if t then t:SetShown(show) end
        end
    end
end

-------------------------------------------------------------------------------
-- Message direction and the temporary input box above the experience track
-------------------------------------------------------------------------------
local function standardBox(f)
    local box = f and f.editBox
    if not box then return end
    boxAtXP[box] = nil
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -5, -2)
    if ns.db and ns.db.chatScrollLeft then
        box:SetPoint("RIGHT", f, "RIGHT", 16, 0)
    else
        box:SetPoint("RIGHT", f.ScrollBar, "RIGHT", 8, 0)
    end
end

local function restoreInputBox(box)
    local insets = boxInsets[box]
    if insets and box.SetTextInsets then
        pcall(box.SetTextInsets, box, insets[1], insets[2], insets[3], insets[4])
    end
    for _, f in ipairs(chatFrames()) do
        if f.editBox == box then
            if not boxAtXP[box] then standardBox(f) end
            return
        end
    end
end

local function placeInputBox(box)
    box:SetAlpha(1)
    if box.GetTextInsets and box.SetTextInsets then
        if not boxInsets[box] then
            local ok, left, right, top, bottom = pcall(box.GetTextInsets, box)
            if ok then boxInsets[box] = { left, right, top, bottom } end
        end
        local insets = boxInsets[box]
        if insets and type(insets[4]) == "number" then
            pcall(box.SetTextInsets, box, insets[1], insets[2], insets[3], insets[4] + 6)
        end
    end
    local xp = ns.Track and ns.Track.Bar and ns.Track.Bar("xp")
    if not (xp and xp:IsShown()) then return end
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", xp, "TOPLEFT", 0, 3)
    box:SetPoint("BOTTOMRIGHT", xp, "TOPRIGHT", 0, 3)
    boxAtXP[box] = true
end

local function applyMessageDirection(f)
    if not (f and f.SetInsertMode and ns.db) then return end
    local mode = ns.db.chatTopToBottom
        and (SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP or "TOP")
        or (SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM or "BOTTOM")
    pcall(f.SetInsertMode, f, mode)
end

-- Fade older lines over several lines before they leave the chat frame. Blizzard's
-- vertical edge fades use a vector with no horizontal component.
local function applyMessageFade(f)
    if not (f and f.SetAlphaGradient and CreateVector2D and ns.db) then return end
    local fade = math.min(80, f:GetHeight() * 0.6)
    local top = ns.db.chatTopToBottom and 0 or fade
    local bottom = ns.db.chatTopToBottom and fade or 0
    -- Flattening is protected on some client frames. Attempt each call separately so
    -- a rejected flattening call cannot prevent the gradients from being applied.
    if f.SetFlattensRenderLayers then pcall(f.SetFlattensRenderLayers, f, true) end
    pcall(f.SetAlphaGradient, f, 0, CreateVector2D(0, top))
    pcall(f.SetAlphaGradient, f, 1, CreateVector2D(0, bottom))
end

local function hookInputBox(box)
    if hookedBoxes[box] or not box.HookScript then return end
    hookedBoxes[box] = true
    box:HookScript("OnEditFocusGained", placeInputBox)
    box:HookScript("OnEditFocusLost", restoreInputBox)
end

-------------------------------------------------------------------------------
-- The scroll bar on the left
-------------------------------------------------------------------------------
-- Mirrors Blizzard's right-hand layout (FCF_UpdateScrollbarAnchors): the 8 px bar beside the
-- window over the 17 px "back to the newest" button, centred on each other; SCROLL_GAP
-- between the bar and the text (2 sat too close, seen in 0.5.0).
local SCROLL_GAP = 6
C.SCROLL_GAP = SCROLL_GAP
local function scrollLeft(f)
    local bar, bottom, box = f.ScrollBar, f.ScrollToBottomButton, f.editBox
    if not (bar and bottom) then return end
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 4.5 - SCROLL_GAP, 8)
    bar:ClearAllPoints()
    bar:SetPoint("TOPRIGHT", f, "TOPLEFT", -SCROLL_GAP, 0)
    bar:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", -4.5, 2)
    if box then standardBox(f) end
end

-- Blizzard's own anchors back (FloatingChatFrame.xml, FCF_UpdateScrollbarAnchors).
local function scrollRight(f)
    local bar, bottom, box = f.ScrollBar, f.ScrollToBottomButton, f.editBox
    if not (bar and bottom) then return end
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMRIGHT", f.ResizeButton, "TOPRIGHT", -2, -2)
    if box then standardBox(f) end
    if FCF_UpdateScrollbarAnchors then FCF_UpdateScrollbarAnchors(f) end
end

-------------------------------------------------------------------------------
-- The tabs only while the mouse is over the chat
-------------------------------------------------------------------------------
-- Blizzard fades each tab between two alphas, kept per tab by ChatFrameUtil.SetTabAlphas
-- (off the tab and read through securecallfunction, so an addon's write can't taint the
-- shared UIFrameFade list) and set again by FCFTab_UpdateAlpha. We leave its hover alpha and
-- make the other 0, so Blizzard's own fade shows a tab when you're over the chat and hides
-- it after. A tab flashing for a new message keeps Blizzard's look.
local function selectedAlphas()
    return CHAT_FRAME_TAB_SELECTED_MOUSEOVER_ALPHA or 1, CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA or 0.4
end

local function tabOf(f) return _G[f:GetName() .. "Tab"] end

local function quietTab(f)
    local U, tab = ChatFrameUtil, tabOf(f)
    if not (tab and U and U.GetTabAlphas and U.SetTabAlphas) then return end
    if U.IsTabAlerting and U.IsTabAlerting(tab) then return end
    local over = U.GetTabAlphas(tab)
    U.SetTabAlphas(tab, over or (selectedAlphas()), 0)
    if not f.hasBeenFaded then tab:SetAlpha(0) end -- the mouse isn't over the chat
end

-- Back to Blizzard's alphas (as FCFTab_UpdateAlpha picks them), without running its fades.
local function loudTab(f)
    local U, tab = ChatFrameUtil, tabOf(f)
    if not (tab and U and U.SetTabAlphas) or (U.IsTabAlerting and U.IsTabAlerting(tab)) then return end
    local over, none
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    if not f.isDocked or f == selected then
        over, none = selectedAlphas()
    else
        over, none = CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA or 0.6, CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA or 0.2
    end
    U.SetTabAlphas(tab, over, none)
    tab:SetAlpha(f.hasBeenFaded and over or none)
end

-------------------------------------------------------------------------------
-- Channel names: [1] for [1. General - Durotar]
-------------------------------------------------------------------------------
local CHANNEL = "|Hchannel:channel:(%d+)|h%[(%d+)%. [^%]]*%]|h"
local function long(message)
    return type(message) == "string" and not secret(message) and message:find(CHANNEL) ~= nil
end
local function shorten(message, ...)
    return (message:gsub(CHANNEL, "|Hchannel:channel:%1|h[%2]|h")), ...
end
C.Shorten = function(message) return (shorten(message)) end

local function shortenIn(f)
    if f.TransformMessages then f:TransformMessages(long, shorten) end
end

-- A line just went in: shorten it (and any long ones from before).
local onAddMessage = ns.Art.Timed("chat lines", function(f, message)
    if ns.db and ns.db.shortChannels and long(message) then shortenIn(f) end
end)

local function follow(f)
    if hooked[f] or not (hooksecurefunc and f.AddMessage) then return end
    hooked[f] = true
    hooksecurefunc(f, "AddMessage", onAddMessage)
end

-------------------------------------------------------------------------------
-- The Combat Log tab
-------------------------------------------------------------------------------
local function combatLog()
    return ChatFrame2 ~= nil and IsCombatLog ~= nil and IsCombatLog(ChatFrame2) and ChatFrame2 or nil
end

local function applyCombatLog(show)
    local f = combatLog()
    if not f then return end
    local open = f.isDocked or f:IsShown()
    if show and not open then
        f:Show()
        if FCF_DockFrame then FCF_DockFrame(f, 2, false) end -- next to General, where Blizzard puts it
    elseif not show and open then
        if FCF_Close then FCF_Close(f) end -- picks General if it was the one showing
    end
end

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------
-- The input box only while typing: Blizzard's Classic chat style ("im" keeps it showing).
-- Blizzard applies the style once, at login (SETTINGS_LOADED -> ChatFrameUtil.UpdateChatFrames),
-- from CVar chatStyle, and the game can put the CVar back (0.5.0 wrote it once; it came back
-- as "im"). So the choice lives in our settings and the CVar is set again at our load and
-- after the account's settings arrive (VARIABLES_LOADED), before Blizzard reads it.
function C.TypingOnly() return ns.db ~= nil and ns.db.chatTyping and true or false end

function C.ApplyStyle()
    if not (ns.db and GetCVar and SetCVar) or inCombat() then return end
    local want = ns.db.chatTyping and "classic" or "im"
    if GetCVar("chatStyle") ~= want then SetCVar("chatStyle", want) end
end

function C.SetTypingOnly(on)
    if not ns.db then return end
    ns.db.chatTyping = on and true or false
    C.ApplyStyle()
end

-- A box Blizzard already showed in the IM style (the CVar arrived late): transparent until you
-- press Enter (ChatFrameUtil.ActivateChat sets its alpha back to 1; sending hides it, Classic
-- style). Only its alpha: no chat code of Blizzard's runs from here.
local function quietBoxes()
    for _, f in ipairs(chatFrames()) do
        local box = f.editBox
        local focused = false
        if box and box.HasFocus then
            local ok, value = pcall(box.HasFocus, box)
            focused = ok and value and true or false
        end
        if box and box:IsShown() and ACTIVE_CHAT_EDIT_BOX ~= box and not focused and (box:GetAlpha() or 0) > 0 then
            box:SetAlpha(0)
        end
    end
end

-- Everything as the settings say (out of combat: it moves Blizzard frames).
function C.Apply()
    local db = ns.db
    if not db then return true end
    if inCombat() then C.pending = true; return false end
    C.pending = false
    hidden = hidden or CreateFrame("Frame")
    hidden:Hide()
    for _, f in ipairs(chatFrames()) do
        follow(f)
        hookInputBox(f.editBox)
        applyMessageDirection(f)
        applyMessageFade(f)
        if db.chatScrollLeft then scrollLeft(f) elseif C.wasLeft then scrollRight(f) end
        if db.shortChannels then shortenIn(f) end
    end
    C.wasLeft = db.chatScrollLeft
    for _, f in ipairs(chatFrames()) do
        if db.chatTabsOnHover then quietTab(f) elseif C.wasQuiet then loudTab(f) end
    end
    C.wasQuiet = db.chatTabsOnHover
    C.ApplyStyle()
    if db.chatTyping then quietBoxes() end
    applyButtons(db.chatButtons)
    applyBackground(db.chatBackground)
    applyCombatLog(db.combatLog)
    return true
end

function C.OnCombatEnd() if C.pending then C.Apply() end end

-- Blizzard re-anchors the scroll bar (locking, resizing) and opens new windows: ours again.
function C.Create()
    if C.created then return end
    C.created = true
    if not hooksecurefunc then return end
    if FCF_UpdateScrollbarAnchors then
        hooksecurefunc("FCF_UpdateScrollbarAnchors", function(f)
            if ns.db and ns.db.chatScrollLeft and not inCombat() then scrollLeft(f) end
        end)
    end
    if FCFTab_UpdateAlpha then -- Blizzard sets a tab's alphas again (docking, selecting): ours on top
        hooksecurefunc("FCFTab_UpdateAlpha", function(f)
            if ns.db and ns.db.chatTabsOnHover and f then quietTab(f) end
        end)
    end
    for _, name in ipairs({ "FCF_OpenNewWindow", "FCF_OpenTemporaryWindow" }) do
        if _G[name] then hooksecurefunc(name, function() C.Apply() end) end
    end
    if ChatFrameUtil and ChatFrameUtil.UpdateChatFrames then
        hooksecurefunc(ChatFrameUtil, "UpdateChatFrames", function()
            for _, f in ipairs(chatFrames()) do
                applyMessageDirection(f)
                applyMessageFade(f)
            end
        end)
    end
end

-- The friends list and the chat channels, which had buttons beside the chat.
function C.OpenFriends() if ToggleFriendsFrame then ToggleFriendsFrame() end end
function C.OpenChannels() if ToggleChannelFrame then ToggleChannelFrame() end end

function C.Debug()
    local db = ns.db
    local log = combatLog()
    local box = ChatFrame1 and ChatFrame1.editBox
    local boxState = "?"
    if box then
        if ACTIVE_CHAT_EDIT_BOX == box then boxState = "in use: you're typing" -- e.g. /spheres debug itself
        elseif not box:IsShown() then boxState = "hidden"
        else boxState = (box:GetAlpha() or 0) > 0 and "showing" or "see-through" end
    end
    return string.format("chat: buttons %s, input box %s (chatStyle %s, box %s), tabs %s, background %s, combat log %s, scroll bar %s, channels %s",
        db.chatButtons and "shown" or "hidden", C.TypingOnly() and "while typing" or "always",
        tostring(GetCVar and GetCVar("chatStyle")), boxState, db.chatTabsOnHover and "on hover" or "always",
        db.chatBackground and "shown" or "hidden",
        log and ((log.isDocked or log:IsShown()) and "tab shown" or "tab closed") or "not loaded",
        db.chatScrollLeft and "left" or "right", db.shortChannels and "[1]" or "full names")
end
