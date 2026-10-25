local _, ns = ...

-- Spell fans: a group of spells (a Paladin's Seals, Blessings, Auras) in one action bar slot,
-- or docked by a sphere. In a slot, a macro ("Spheres: Seals", or Action Ring's "Ring:
-- Seals", so a slot set up for Action Ring keeps working) marks where the fan lives; Ring.lua
-- puts the fan's button over that slot. Its key casts the current pick, a click (or Shift +
-- its key) fans the group out to pick another. This file has the groups and what the
-- spellbook knows. (Copied from Action Ring.)

local SP = {}
ns.Spells = SP

-- By class: each group's spells in fan order, as { spell ID (any rank: for the local name), English name }.
-- Only the ones in your spellbook show. collar: docked by a sphere to start with (else
-- in an action slot, with its macro); dock: which sphere and where round it (degrees, 0 = right,
-- counter-clockwise). legacy: Action Ring's macro.
-- oneShot: a Seal for a moment (Crusader to Judge on an elite, Justice on a runner): picked
-- from the fan it's cast without becoming what the key casts, and armed for the key it goes
-- back to the pick after one cast (Ring.lua SPELL_HUB_POST).
SP.GROUPS = {
    PALADIN = {
        { id = "seals", frame = "Seals", label = "Seals", macro = "Spheres: Seals", legacy = "Ring: Seals",
          dock = { "left", 120 }, spells = {
            { 21084, "Seal of Righteousness" }, { 20375, "Seal of Command" },
            { 21082, "Seal of the Crusader", oneShot = true }, { 20164, "Seal of Justice", oneShot = true },
            { 20165, "Seal of Light" }, { 20166, "Seal of Wisdom" },
            { nil, "Seal of Fury" }, -- Forever's own
        } },
        { id = "blessings", frame = "Blessings", label = "Blessings", macro = "Spheres: Blessings", legacy = "Ring: Blessings",
          dock = { "left", 148 }, spells = {
            { 19740, "Blessing of Might" }, { 19742, "Blessing of Wisdom" }, { 20217, "Blessing of Kings" },
            { 1038, "Blessing of Salvation" }, { 19977, "Blessing of Light" }, { 20911, "Blessing of Sanctuary" },
            { 1044, "Blessing of Freedom" }, { 1022, "Blessing of Protection" }, { 6940, "Blessing of Sacrifice" },
            { 25782, "Greater Blessing of Might" }, { 25894, "Greater Blessing of Wisdom" }, { 25898, "Greater Blessing of Kings" },
            { 25895, "Greater Blessing of Salvation" }, { 25890, "Greater Blessing of Light" },
            { 25899, "Greater Blessing of Sanctuary" },
        } },
        { id = "auras", frame = "Auras", label = "Auras", macro = "Spheres: Auras", legacy = "Ring: Auras", collar = true,
          dock = { "left", 64 }, spells = {
            { 465, "Devotion Aura" }, { 7294, "Retribution Aura" }, { 19746, "Concentration Aura" },
            { 20218, "Sanctity Aura" }, { 19876, "Shadow Resistance Aura" }, { 19888, "Frost Resistance Aura" },
            { 19891, "Fire Resistance Aura" },
        } },
    },
    DRUID = {
        { id = "forms", frame = "Forms", label = "Forms", macro = "Spheres: Forms", legacy = "Ring: Forms", collar = true,
          dock = { "left", 64 }, spells = {
            { 5487, "Bear Form" }, { 9634, "Dire Bear Form" }, { 768, "Cat Form" },
            { 1066, "Aquatic Form" }, { 783, "Travel Form" }, { 24858, "Moonkin Form" },
            { 33891, "Tree of Life" }, { 33943, "Flight Form" }, { 40120, "Swift Flight Form" },
        } },
    },
}

local book = {} -- spellbook name -> spell ID (the highest rank)

-- Read the spellbook (out of combat or in: it only reads).
function SP.Scan()
    for k in pairs(book) do book[k] = nil end
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then return end
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    for line = 1, SB.GetNumSpellBookSkillLines() do
        local li = SB.GetSpellBookSkillLineInfo(line)
        if li and not li.shouldHide and (li.offSpecID == nil or li.offSpecID == 0) then
            for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local ok, item = pcall(SB.GetSpellBookItemInfo, i, bank)
                if ok and item and item.name and not item.isPassive and (not SPELL or item.itemType == SPELL) then
                    book[item.name] = item.spellID -- later (higher) ranks overwrite earlier ones
                end
            end
        end
    end
end

-- The spell's name in this client's language.
local function nameOf(entry)
    local n = entry[1] and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry[1])
    if type(n) == "string" and n ~= "" then return n end
    return entry[2]
end

-- A group's spells you know, in fan order: { key = English name, name = local name, id = highest rank }.
function SP.Known(group)
    local t = {}
    for _, entry in ipairs(group.spells) do
        local name = nameOf(entry)
        local id = book[name]
        if id then t[#t + 1] = { key = entry[2], name = name, id = id, oneShot = entry.oneShot } end
    end
    return t
end

-- This character's groups (none for classes without any).
function SP.ForPlayer()
    local class = UnitClass and select(2, UnitClass("player"))
    return SP.GROUPS[class or ""] or {}
end
