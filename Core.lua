-- Total Intel core: namespace, settings, events, slash commands and helpers.
--
-- WoW: Forever runs on a modern client that hides some values from addons ("secret values"),
-- mainly inside dungeons/raids and on world objects in combat. Every value that comes from the
-- game about a unit goes through SB.Public() before the addon compares, parses or stores it.

local ADDON_NAME, SB = ...
_G.TotalIntel = SB
SB.name = ADDON_NAME
SB.D = SB.D or {}   -- bundled database (Data/*.lua)
SB.TITLE = "|cffc27dff[Soeta's]|r |cffff9933Total Intel on Targets & Spoils|r"
SB.ICON = "Interface\\Icons\\Ability_Physical_Taunt" -- Beast Lore

SB.DEFAULTS = {
    tip = {
        enabled = true,
        modifier = "NONE",      -- show the extra lines only while this key is held: NONE, SHIFT, CTRL, ALT
        npcId = false,
        info = true,            -- "Elite · Humanoid · Wolf"
        health = false,
        quests = true,          -- your active quests that need this mob (with progress)
        questGiver = true,      -- quests this NPC starts / where you turn in
        drops = true,
        dropsCount = 4,
        dropsMinQuality = 2,    -- 0 poor .. 4 epic; quest drops always show
        abilities = true,
        abilitiesCount = 4,
        kills = true,           -- your kills / corpses looted
        skinning = true,
        gold = false,
        hint = true,
        itemEnabled = true,
        itemId = false,
        itemDroppedBy = true,
        itemDroppedByCount = 3,
        itemQuests = true,
        itemCrafted = true,
        itemVendors = true,
        itemYourLoot = true,
    },
    wowhead = "forever",        -- forever | classic
    style = "journal",          -- journal (Adventure Guide art) | dark
    itemClick = "ALT",          -- modifier+click on an item or mob opens its page: ALT, CTRL-ALT, SHIFT-ALT, NONE
    learn = true,               -- record kills, loot and spells you see
    minimap = { angle = 215, hide = false },
    mobs = {},
    recent = {},
}

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

function SB.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(SB.TITLE .. ": " .. msg)
end

function SB.After(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

local issecret = _G.issecretvalue
-- The value if the addon may look at it, otherwise nil.
function SB.Public(v)
    if v == nil then return nil end
    if issecret then
        local ok, secret = pcall(issecret, v)
        if not ok or secret then return nil end
    end
    return v
end

-- "Creature-0-4469-0-17-448-000012ABCD" -> 448 (creatures and vehicles only)
function SB.NpcIdFromGUID(guid)
    guid = SB.Public(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

function SB.UnitNpcId(unit)
    if not unit or not UnitExists(unit) then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil end
    return SB.NpcIdFromGUID(guid)
end

-- Splits on "^" keeping empty fields.
function SB.Fields(s, sep)
    local out, n = {}, 0
    sep = sep or "^"
    local pat = "(.-)%" .. sep
    for f in (s .. sep):gmatch(pat) do n = n + 1; out[n] = f end
    return out
end

function SB.List(s, sep)
    local out = {}
    if not s or s == "" then return out end
    for f in s:gmatch("[^" .. (sep or ",") .. "]+") do out[#out + 1] = f end
    return out
end

function SB.Money(copper)
    copper = tonumber(copper) or 0
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local t = {}
    if g > 0 then t[#t + 1] = g .. "g" end
    if s > 0 then t[#t + 1] = s .. "s" end
    if c > 0 or #t == 0 then t[#t + 1] = c .. "c" end
    return table.concat(t, " ")
end

function SB.Percent(chance)
    if not chance then return "?" end
    if chance <= 0 then return "0%" end
    if chance >= 10 then return (("%.1f"):format(chance):gsub("%.0$", "")) .. "%" end
    if chance >= 1 then return ("%.1f%%"):format(chance) end
    if chance >= 0.1 then return ("%.2f%%"):format(chance) end
    return "<0.1%"
end

function SB.Plural(n, one, many)
    return n .. " " .. (n == 1 and one or (many or one .. "s"))
end

local MODIFIERS = {
    NONE = function() return true end,
    SHIFT = function() return IsShiftKeyDown() end,
    CTRL = function() return IsControlKeyDown() end,
    ALT = function() return IsAltKeyDown() end,
}
function SB.ModifierHeld(name)
    local f = MODIFIERS[name or "NONE"]
    return f and f() or false
end

function SB.WowheadURL(kind, id)
    local site = SB.db and SB.db.wowhead == "classic" and "classic" or "forever"
    return ("https://www.wowhead.com/%s/%s=%d"):format(site, kind, id)
end

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function SB.ResetTooltipSettings()
    SB.db.tip = {}
    Merge(SB.db.tip, SB.DEFAULTS.tip)
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
SB.frame = frame
local handlers = {}

-- Several modules can listen to the same event.
function SB.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then handlers[event] = nil return false end
    end
    table.insert(handlers[event], fn)
    return true
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok and SB.debug then SB.Print("|cffff5555" .. event .. "|r " .. tostring(err)) end
    end
end)

SB.On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    TotalIntelDB = TotalIntelDB or {}
    SB.db = TotalIntelDB
    Merge(SB.db, SB.DEFAULTS)
    SB.db.version = 1
    if SB.OnLoad then for _, fn in ipairs(SB.OnLoad) do fn() end end
end)

function SB.AddLoad(fn)
    SB.OnLoad = SB.OnLoad or {}
    table.insert(SB.OnLoad, fn)
end

------------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------------

local HELP = {
    "|cffffd100/tits|r - open the window on your target (or the last mob you viewed)",
    "|cffffd100/tits <name>|r - search mobs and items, e.g. |cffffd100/tits hogger|r",
    "|cffffd100/tits zone|r - mobs in your zone or instance",
    "|cffffd100/tits dungeons|r, |cffffd100/tits raids|r - the instance journal",
    "|cffffd100/tits options|r - tooltip and window settings",
    "|cffffd100/tits link|r - Wowhead link for your target",
    "|cffffd100/tits minimap|r - hide or show the minimap button",
    "|cffffd100/tits learn|r - turn recording kills, loot and spells on or off",
}

local function Slash(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        SB.OpenTarget()
    elseif cmd == "help" or cmd == "?" then
        SB.Print("commands:")
        for _, l in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("   " .. l) end
    elseif cmd == "options" or cmd == "settings" or cmd == "config" then
        SB.OpenSettings()
    elseif cmd == "zone" then
        SB.OpenZone()
    elseif cmd == "dungeons" or cmd == "dungeon" then
        SB.OpenDungeons(false)
    elseif cmd == "raids" or cmd == "raid" then
        SB.OpenDungeons(true)
    elseif cmd == "link" or cmd == "wowhead" then
        local id = SB.UnitNpcId("target")
        if id then SB.ShowLink("npc", id, SB.NpcName(id)) else SB.Print("target a mob first.") end
    elseif cmd == "minimap" then
        SB.db.minimap.hide = not SB.db.minimap.hide
        if SB.UpdateMinimap then SB.UpdateMinimap() end
        SB.Print("minimap button " .. (SB.db.minimap.hide and "hidden" or "shown") .. ".")
    elseif cmd == "learn" then
        SB.db.learn = not SB.db.learn
        SB.Print("recording kills, loot and spells is " .. (SB.db.learn and "|cff33ff33on|r" or "|cffff5555off|r") .. ".")
    elseif cmd == "debug" then
        SB.debug = not SB.debug
        SB.Print("debug " .. (SB.debug and "on" or "off"))
    else
        SB.OpenSearch(msg)
    end
end

SLASH_TOTALINTEL1 = "/tits"
SLASH_TOTALINTEL2 = "/totalintel"
SlashCmdList.TOTALINTEL = Slash

-- Key bindings (Bindings.xml)
BINDING_HEADER_TOTALINTEL = "Total Intel"
BINDING_NAME_TOTALINTEL_TARGET = "Open for target"
BINDING_NAME_TOTALINTEL_MOUSEOVER = "Open for mouseover"
BINDING_NAME_TOTALINTEL_TOGGLE = "Toggle window"

function SB.BindingTarget() SB.OpenTarget() end
function SB.BindingMouseover()
    local id = SB.UnitNpcId("mouseover")
    if id then SB.OpenNpc(id) else SB.OpenTarget() end
end
function SB.BindingToggle() SB.Toggle() end
