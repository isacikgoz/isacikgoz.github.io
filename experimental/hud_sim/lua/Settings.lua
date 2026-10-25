local _, ns = ...

-- A settings page under Options -> AddOns -> Spheres, laid out like
-- Blizzard's own pages: gold labels on the left, controls in one column,
-- white section headers, a red "Defaults" button top right. Same builder as
-- Action Ring's, AutoBuff's and DPS Meter's pages (copied: each add-on must work alone).

local S = {}
ns.Settings = S

local ROW_H = 38
local LABEL_X = 34
local CTRL_X = 330
local CTRL_W = 230

local panel, content, category
local refreshers = {}
local y = 0

local function atlasOK(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function texture(parent, atlas, file, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  if atlas and atlasOK(atlas) then t:SetAtlas(atlas) else t:SetTexture(file) end
  return t
end

local function refreshAll()
  for _, fn in ipairs(refreshers) do fn() end
end
S.Refresh = function() if panel then refreshAll() end end

local function changed()
  ns.Apply()
  refreshAll()
end

-------------------------------------------------------------------------------
-- Building blocks
-------------------------------------------------------------------------------

local function header(text)
  y = y + (y > 0 and 16 or 4)
  local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -y)
  fs:SetText(text)
  y = y + 30
end

local function row(label, tip)
  local r = CreateFrame("Frame", nil, content)
  r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
  r:SetPoint("RIGHT", content, "RIGHT", -8, 0)
  r:SetHeight(ROW_H)
  r:EnableMouse(true)

  local hl = r:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  hl:Hide()

  local fs = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("LEFT", LABEL_X, 0)
  fs:SetText(label)
  r.label = fs

  local function enter()
    hl:Show()
    if tip and GameTooltip then
      GameTooltip:SetOwner(r, "ANCHOR_NONE")
      GameTooltip:SetPoint("BOTTOMLEFT", r, "TOPLEFT", CTRL_X - 20, -4)
      GameTooltip:SetText(label, 1, 1, 1)
      GameTooltip:AddLine(tip, 1, 0.82, 0, true)
      GameTooltip:Show()
    end
  end
  local function leave()
    hl:Hide()
    if GameTooltip then GameTooltip:Hide() end
  end
  r:SetScript("OnEnter", enter)
  r:SetScript("OnLeave", leave)
  r.enter, r.leave = enter, leave

  y = y + ROW_H
  return r
end

-- child controls keep the row highlighted and the tooltip up
local function linkHover(r, ctrl)
  ctrl:HookScript("OnEnter", r.enter)
  ctrl:HookScript("OnLeave", r.leave)
end

local function makeCheck(parent)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(30, 30)
  cb:SetNormalTexture(texture(cb, "checkbox-minimal", "Interface\\Buttons\\UI-CheckBox-Up"))
  cb:SetPushedTexture(texture(cb, "checkbox-minimal", "Interface\\Buttons\\UI-CheckBox-Down"))
  cb:SetCheckedTexture(texture(cb, "checkmark-minimal", "Interface\\Buttons\\UI-CheckBox-Check"))
  local hl = cb:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
  hl:SetBlendMode("ADD")
  hl:SetAllPoints()
  return cb
end

local function arrowButton(parent, dir)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(26, 26)
  local base = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
  b:SetNormalTexture(base .. "Up")
  b:SetPushedTexture(base .. "Down")
  b:SetDisabledTexture(base .. "Disabled")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  return b
end

local function box(parent, w, h)
  local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
  f:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("CENTER")
  f.text = fs
  return f
end

local function checkbox(label, tip, get, set)
  local r = row(label, tip)
  local cb = makeCheck(r)
  cb:SetPoint("LEFT", CTRL_X, 0)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); changed() end)
  linkHover(r, cb)
  refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
  return r, cb
end

-- [<]  value  [>] cycling selector, like Blizzard's "Auto Loot Key"
local function selector(label, tip, options, get, set)
  local r = row(label, tip)
  local left = arrowButton(r, -1)
  left:SetPoint("LEFT", CTRL_X, 0)
  local mid = box(r, CTRL_W - 4, 28)
  mid:SetPoint("LEFT", left, "RIGHT", 2, 0)
  mid.text:SetFontObject("GameFontNormal")
  local right = arrowButton(r, 1)
  right:SetPoint("LEFT", mid, "RIGHT", 2, 0)

  local function step(d)
    local cur, idx = get(), 1
    for i, o in ipairs(options) do if o.value == cur then idx = i end end
    idx = ((idx - 1 + d) % #options) + 1
    set(options[idx].value)
    changed()
  end
  left:SetScript("OnClick", function() step(-1) end)
  right:SetScript("OnClick", function() step(1) end)
  mid:SetScript("OnClick", function() step(1) end)
  for _, c in ipairs({ left, mid, right }) do linkHover(r, c) end

  refreshers[#refreshers + 1] = function()
    local cur, text = get(), nil
    for _, o in ipairs(options) do if o.value == cur then text = o.text end end
    mid.text:SetText(text or options[1].text)
  end
  return mid
end

local function slider(label, tip, min, max, stepv, get, set, fmt)
  local r = row(label, tip)
  local left = arrowButton(r, -1)
  left:SetSize(22, 22)
  left:SetPoint("LEFT", CTRL_X, 0)

  local s = CreateFrame("Slider", nil, r)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(CTRL_W - 50, 18)
  s:SetPoint("LEFT", left, "RIGHT", 6, 0)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(stepv)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouseWheel(true)

  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT"); track:SetPoint("RIGHT")
  track:SetHeight(8)
  track:SetColorTexture(0.06, 0.06, 0.08, 1)
  local edge = s:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPLEFT", track, -1, 1); edge:SetPoint("BOTTOMRIGHT", track, 1, -1)
  edge:SetColorTexture(0.35, 0.35, 0.4, 1)
  edge:SetDrawLayer("BACKGROUND", -1)

  local thumb = texture(s, "Minimal_SliderBar_Button", "Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  thumb:SetSize(atlasOK("Minimal_SliderBar_Button") and 20 or 32, atlasOK("Minimal_SliderBar_Button") and 20 or 32)
  s:SetThumbTexture(thumb)

  local right = arrowButton(r, 1)
  right:SetSize(22, 22)
  right:SetPoint("LEFT", s, "RIGHT", 6, 0)

  local val = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  val:SetPoint("LEFT", right, "RIGHT", 10, 0)

  local quiet = false
  local function apply(v)
    v = math.floor(v / stepv + 0.5) * stepv
    v = math.max(min, math.min(max, v))
    set(v)
    val:SetText(fmt(v))
    ns.Apply()
  end
  s:SetScript("OnValueChanged", function(_, v) if not quiet then apply(v) end end)
  s:SetScript("OnMouseWheel", function(_, d) s:SetValue((get() or min) + d * stepv) end)
  left:SetScript("OnClick", function() s:SetValue((get() or min) - stepv) end)
  right:SetScript("OnClick", function() s:SetValue((get() or min) + stepv) end)
  for _, c in ipairs({ left, s, right }) do linkHover(r, c) end

  refreshers[#refreshers + 1] = function()
    quiet = true
    s:SetValue(get() or min)
    quiet = false
    val:SetText(fmt(get() or min))
  end
  return s
end

local function button(label, tip, text, onClick)
  local r = row(label, tip)
  local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  b:SetSize(110, 24)
  b:SetPoint("LEFT", CTRL_X, 0)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  linkHover(r, b)
  return b
end

-------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------

local function buildRows()
  local db = ns.db

  header("Spheres")
  slider("Size", "The whole bottom of the screen: the spheres, the action bar frame and its rows, the statues. 100% is Roth UI's size; it never gets wider than your screen.", 0.8, 1.6, 0.05,
    function() return db.scale end, function(v) db.scale = v end, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
  checkbox("Minimap in the Right Sphere",
    "Blizzard's minimap moves into the right sphere (the mouse wheel zooms). Off: back in its own place; a /reload puts it exactly where it was.",
    function() return db.minimap end, function(v) db.minimap = v end)
  checkbox("Always Show Sphere Values",
    "Keep health and mana values visible, and show map coordinates whenever the minimap is in the right sphere. Off: show each value on hover.",
    function() return db.sphereValuesAlways end, function(v)
      db.sphereValuesAlways = v
      if ns.Sphere then ns.Sphere.UpdateValueVisibility() end
    end)
  checkbox("Liquid Motion",
    "The liquids slosh as your character turns fast, starts, stops, strafes, jumps and lands: they climb the wall they lag behind, rock back and settle. Off: they keep still.",
    function() return db.slosh ~= "off" end, function(v) db.slosh = v and "on" or "off" end)
  checkbox("Cracked Glass",
    "A blow for more than a third of your health cracks your health's glass, and more than half cracks it further; your pet's too. The crack mends after a few seconds. (/spheres crack shows one.)",
    function() return db.crackedGlass end, function(v) db.crackedGlass = v end)
  checkbox("Hide the Player Frame",
    "Blizzard's portrait with your health and mana bars, top left: the left sphere shows your health and mana instead.",
    function() return db.hidePlayerFrame end, function(v) db.hidePlayerFrame = v end)
  selector("Statues", "None hides both statues and uses the charcoal frame. Modern and Charcoal show the lion and griffin with matching frame ends.",
    { { value = "none", text = "None" }, { value = "modern", text = "Modern" }, { value = "charcoal", text = "Charcoal" } },
    function() return db.statueFinish or "modern" end, function(v) db.statueFinish = v end)
  checkbox("Quest Arrow Over the Griffin",
    "The minimap's arrow to the quest or map pin you track, and its red arrow to your corpse while you're a ghost, are drawn again where the griffin covers them. Off: the griffin's head turns see-through instead, so the minimap's own arrow shows faintly behind it.",
    function() return db.questArrow end, function(v) db.questArrow = v end)

  checkbox("Buffs Above the Action Bars",
    "Your buffs and debuffs centred over the action bars, under your cast bar (Diablo's way). Off: in the top right corner.",
    function() return db.aurasAbove end, function(v) db.aurasAbove = v end)
  checkbox("Target Card",
    "Your target as a card near the top centre: its portrait, level, name, health and power, and Blizzard's cast bar under them. It stays in a fixed position; drag it in Edit Mode or Shift-drag it outside Edit Mode. Off: Blizzard's target frame.",
    function() return db.targetCard end, function(v) db.targetCard = v end)
  selector("Target Style", "Card: the portrait over its health and power bars. Sphere (experimental): a sphere as your own, its health and power as liquids, its portrait in the centre. Nameplate (the default): its portrait, name, health and power where its nameplate is, for any target (Blizzard's for the target hidden). If needed, Spheres enables the target's nameplate type or Always Show Nameplates, hides any other plates caused by an override, and restores your setting when you switch styles. On Forever, the off-screen target card stops above the full Spheres HUD; in the middle when it has no plate; a boss keeps the card at the top.",
    { { value = "nameplate", text = "Nameplate" }, { value = "card", text = "Card" }, { value = "sphere", text = "Sphere (experimental)" } },
    function() return db.targetStyle or "nameplate" end, function(v) db.targetStyle = v end)
  button("Target Card Position", "Back to the top of the screen, in the middle.", "Reset",
    function() db.target.point = nil; ns.Apply() end)

  header("Chat")
  checkbox("Chat Buttons",
    "The chat menu, channel, voice and friends buttons beside the chat. Off: hidden; the friends list and chat channels open from the buttons below.",
    function() return db.chatButtons end, function(v) db.chatButtons = v end)
  checkbox("Input Box Only While Typing",
    "The input box shows when you press Enter and hides when you send (Blizzard's Classic chat style, Options -> Social; this setting wins at each login).",
    function() return ns.Chat.TypingOnly() end, function(v) ns.Chat.SetTypingOnly(v) end)
  checkbox("Chat Flows Top to Bottom",
    "New chat messages appear at the top of the window and older messages flow down. Turn off to keep new messages at the bottom.",
    function() return db.chatTopToBottom end, function(v) db.chatTopToBottom = v end)
  checkbox("Tabs Only on Hover",
    "The chat's tabs (General, ...) show while the mouse is over the chat and fade away after, like its scroll bar. A tab with a new message still lights up.",
    function() return db.chatTabsOnHover end, function(v) db.chatTabsOnHover = v end)
  checkbox("Chat Background",
    "The dark tint behind the chat window. Off: just the text.",
    function() return db.chatBackground end, function(v) db.chatBackground = v end)
  checkbox("Combat Log Tab",
    "The Combat Log next to General. Off: closed; turn it on here when you want it.",
    function() return db.combatLog end, function(v) db.combatLog = v end)
  checkbox("Scroll Bar on the Left",
    "The chat's scroll bar and its back-to-newest arrow on the left side, where the buttons were.",
    function() return db.chatScrollLeft end, function(v) db.chatScrollLeft = v end)
  checkbox("Short Channel Names",
    "Channels as [1] and [2] rather than [1. General - Durotar]. Click one to talk in it, as before.",
    function() return db.shortChannels end, function(v) db.shortChannels = v end)
  button("Friends", "Your friends list (the friends button beside the chat).", "Open", function() ns.Chat.OpenFriends() end)
  button("Chat Channels", "Join, leave and list chat channels (the channel button beside the chat).", "Open",
    function() ns.Chat.OpenChannels() end)

  header("Objectives")
  checkbox("Folded at Login",
    "The objectives list (All Objectives) starts folded each time you log in or reload. Unfold it with its button and it stays open until next time.",
    function() return db.foldObjectives end, function(v) db.foldObjectives = v end)
  checkbox("An Icon When Folded",
    "Folded, the objectives list becomes a brass quest badge with a red center and plus, with the number of quests you follow in its corner. Click it to show the list.",
    function() return db.objectivesIcon end, function(v) db.objectivesIcon = v end)

  header("Rings")
  for _, def in ipairs(ns.Ring.DEFS) do
    if def.kind ~= "spells" then
      local tip = def.kind == "menu"
        and "One button for Character, Professions, Spellbook, Talents, Quest Log, Guild, Group Finder, Collections, Help and the Game Menu. Hover it for your ping and frame rate. Blizzard's collection and talent alerts appear here too."
        or def.kind == "bags" and "Click to open the bag fan. Your Toggle Backpack key opens the backpack directly; right-click does the same. Click a bag in the fan to open it, or drop a bag on one to swap it."
        or ("One button that fans out " .. def.label .. "'s slots.")
      checkbox(def.label, tip, function() return db.rings[def.id].shown end, function(v) db.rings[def.id].shown = v end)
    end
  end
  checkbox("Only Filled Slots",
    "Leave out empty slots and spread the rest evenly. All 12 show while you drag a spell, item or macro, so you can drop it on any slot.",
    function() return db.hideEmpty end, function(v) db.hideEmpty = v end)
  checkbox("Number Keys While Open",
    "While a ring is open, 1-9, 0, - and = use its slots 1-12, and each slot shows its key. They go back to your bars when it closes.",
    function() return db.numberKeys end, function(v) db.numberKeys = v end)
  checkbox("Lock Positions", "No moving. Unlocked: drag a ring's button round its sphere, or over to the other one.",
    function() return db.locked end, function(v) db.locked = v end)
  button("Ring Positions", "Put every ring's button back in its first place round the spheres.", "Reset",
    function() ns.Ring.ResetDocks() end)

  local fans = {}
  for _, o in ipairs(ns.Ring.List()) do if o.def.kind == "spells" then fans[#fans + 1] = o end end
  if #fans > 0 then
    header("Spell Fans")
    for _, o in ipairs(fans) do
      checkbox(o.def.label .. " by a Sphere",
        "A button by a sphere (drag it round): click it and your " .. o.def.label
          .. " open round the sphere; right-click, or its key in Key Bindings -> Spheres, casts the current pick. Off: it lives in an action slot (below).",
        function() return db.rings[o.id].collar end, function(v) db.rings[o.id].collar = v end)
      button(o.def.label .. " in a Slot",
        "Puts the \"" .. o.def.macro .. "\" macro on your cursor: drop it in a slot of the rows. That slot's key casts your current pick; "
          .. "click the slot (or Shift + its key) to fan out your " .. o.def.label .. ". Action Ring's \"" .. o.def.legacy .. "\" macro works too.",
        "Put on Cursor", function()
          local ok, why = ns.Ring.PickupMacro(o.id)
          if not ok then ns.Say("can't make the " .. o.def.label .. " macro: " .. why .. ".") end
        end)
    end
    if ns.Ring.Get("auras") or ns.Ring.Get("forms") then
      local label = ns.Ring.Get("forms") and "Hide Blizzard's Form Buttons" or "Hide Blizzard's Aura Buttons"
      local group = ns.Ring.Get("forms") and "Forms" or "Auras"
      checkbox(label,
        "While the " .. group .. " fan is in use, Blizzard's stance buttons are hidden.",
        function() return db.hideStanceBar end, function(v) db.hideStanceBar = v end)
    end
  end

  header("Look")
  slider("Ring Slot Size", "A ring's buttons when it's open.", 28, 64, 1,
    function() return db.size end, function(v) db.size = v end, function(v) return v .. " px" end)
  slider("Fan Size", "How far a spell fan over a slot spreads its spells. It grows by itself if they would touch.", 50, 200, 2,
    function() return db.radius end, function(v) db.radius = v end, function(v) return v .. " px" end)

  y = y + 20
end

function S.Create()
  if panel then return end
  panel = CreateFrame("Frame", "SpheresSettingsPanel")
  panel:Hide()

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
  title:SetPoint("TOPLEFT", 10, -14)
  title:SetText("Spheres")

  local status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  status:SetPoint("LEFT", title, "RIGHT", 16, -2)

  local defaults = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  defaults:SetSize(140, 26)
  defaults:SetPoint("TOPRIGHT", -36, -12)
  defaults:SetText(DEFAULTS or "Defaults")
  defaults:SetScript("OnClick", function() S.ResetDefaults() end)

  local line = texture(panel, "Options_HorizontalDivider", nil)
  if not atlasOK("Options_HorizontalDivider") then line:SetColorTexture(1, 0.82, 0, 0.25) end
  line:SetPoint("TOPLEFT", 0, -50)
  line:SetPoint("TOPRIGHT", -20, -50)
  line:SetHeight(1)

  local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "ScrollFrameTemplate")
  if not ok or not scroll then
    ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  end
  if not ok or not scroll then scroll = CreateFrame("ScrollFrame", nil, panel) end
  scroll:SetPoint("TOPLEFT", 0, -58)
  scroll:SetPoint("BOTTOMRIGHT", -30, 6)
  scroll:EnableMouseWheel(true)

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(600, 100)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then content:SetWidth(w) end end)
  if not scroll.ScrollBar then -- bare frame: wheel scrolling only
    scroll:SetScript("OnMouseWheel", function(self, d)
      local maxv = math.max(0, y - (self:GetHeight() or 0))
      self:SetVerticalScroll(math.max(0, math.min(maxv, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
  end

  buildRows()
  content:SetHeight(y)

  local acc = 0
  panel:SetScript("OnShow", function() refreshAll(); status:SetText(S.Status()) end)
  panel:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc > 0.5 then acc = 0; status:SetText(S.Status()) end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local okc, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Spheres")
    if okc and cat then
      category = cat
      pcall(Settings.RegisterAddOnCategory, cat)
    end
  elseif InterfaceOptions_AddCategory then
    panel.name = "Spheres"
    InterfaceOptions_AddCategory(panel)
  end
end

-- One line under the title: what's on, and anything waiting for combat to end.
function S.Status()
  if not ns.db then return "" end
  local rings = ns.Ring.ShownLabels()
  local text = "rings: " .. (#rings > 0 and table.concat(rings, ", ") or "none")
  if ns.Ring.Pending() or ns.Bars.Pending() or ns.Sphere.Pending() then text = text .. "  ·  changes wait for combat to end" end
  return text
end

-- Everything back to the defaults, except where the rings sit, their last slot and picks.
function S.ResetDefaults()
  local db = ns.db
  local kept = {}
  for id, c in pairs(db.rings) do kept[id] = { dock = c.dock, lastSlot = c.lastSlot, current = c.current } end
  for k in pairs(db) do db[k] = nil end
  ns.copyDefaults(db, ns.DEFAULTS)
  db.schema = ns.SCHEMA
  ns.FillRings(db)
  for id, k in pairs(kept) do
    local c = db.rings[id]
    if c then c.dock, c.lastSlot, c.current = k.dock, k.lastSlot, k.current end
  end
  changed()
end

-- returns true if a settings window was opened
function S.Open()
  if not panel then S.Create() end
  if category and Settings and Settings.OpenToCategory then
    local id = (category.GetID and category:GetID()) or category.ID
    if pcall(Settings.OpenToCategory, id) then return true end
  end
  if InterfaceOptionsFrame_OpenToCategory and panel.name then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
    return true
  end
  return false
end
