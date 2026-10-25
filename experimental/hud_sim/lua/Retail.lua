local _, ns = ...

-- Keep Retail-only UI lookups here. Forever remains the default path in the shared files.
local interface
if GetBuildInfo then
    local _, _, _, version = GetBuildInfo()
    interface = tonumber(version)
end
if not interface or interface < 120000 then return end

local Retail = {}
ns.Retail = Retail

function Retail.MicroButtons()
    return {
        "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
        "AchievementMicroButton", "QuestLogMicroButton", "HousingMicroButton", "GuildMicroButton",
        "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton", "StoreMicroButton",
        "GameTimeFrame", "SpheresDiel", "MinimapTracking", "AddonCompartmentFrame",
        "HelpMicroButton", "MainMenuMicroButton",
    }
end

function Retail.Micro(name)
    local aliases = {
        SpellbookMicroButton = "ProfessionMicroButton",
        TalentMicroButton = "PlayerSpellsMicroButton",
        LegacyMicroButton = "AchievementMicroButton",
    }
    name = aliases[name] or name
    if name == "MinimapTracking" then
        local cluster = MinimapCluster
        return cluster and cluster.Tracking and cluster.Tracking.Button
    end
    return _G[name]
end

function Retail.MinimapContainer()
    local cluster = MinimapCluster
    return cluster and cluster.MinimapContainer
end

function Retail.MinimapCoordinates()
    local container = Retail.MinimapContainer()
    local cluster = MinimapCluster
    return (container and container.PlayerCoords) or (cluster and cluster.PlayerCoords)
end

function Retail.AdditionalStowFrames()
    return { "MicroButtonAndBagsBar" }
end

function Retail.PrepareMailParent(parent)
    -- MiniMapMailFrameMixin calls its parent's Layout() after mail state changes. Spheres
    -- reparents that indicator into a plain overlay frame, which has no layout method.
    if parent and not parent.Layout then
        parent.Layout = function() end
    end
end

function Retail.TargetCastBar()
    return TargetFrameSpellBar or (TargetFrame and TargetFrame.spellbar)
end
