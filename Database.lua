-- Reads the bundled database (Data/*.lua). Records are compact strings, decoded on first use
-- and cached, so the data costs little memory until you actually look something up.

local _, SB = ...
local D = SB.D
local Fields, List = SB.Fields, SB.List

-- NPC record fields (tools/build_data.py writes them in this order)
local N_NAME, N_SUB, N_MINL, N_MAXL, N_RANK, N_TYPE, N_FAMILY, N_HPMIN, N_HPMAX, N_MANA, N_GOLDMIN, N_GOLDMAX,
      N_FLAGS, N_ZONES, N_FRIENDLY, N_STARTS, N_ENDS, N_KILLFOR, N_DROPFOR, N_WORLD, N_CLASSIC, N_DISPLAY = 1, 2, 3, 4,
      5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22

SB.RANKS = { [0] = "Normal", [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
SB.TYPES = { [1] = "Beast", [2] = "Dragonkin", [3] = "Demon", [4] = "Elemental", [5] = "Giant", [6] = "Undead",
    [7] = "Humanoid", [8] = "Critter", [9] = "Mechanical", [10] = "Not specified", [11] = "Totem" }
SB.FAMILIES = { [1] = "Wolf", [2] = "Cat", [3] = "Spider", [4] = "Bear", [5] = "Boar", [6] = "Crocolisk",
    [7] = "Carrion Bird", [8] = "Crab", [9] = "Gorilla", [11] = "Raptor", [12] = "Tallstrider", [15] = "Felhunter",
    [16] = "Voidwalker", [17] = "Succubus", [19] = "Doomguard", [20] = "Scorpid", [21] = "Turtle", [23] = "Imp",
    [24] = "Bat", [25] = "Hyena", [26] = "Owl", [27] = "Wind Serpent" }
SB.QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000",
    [6] = "e6cc80", [7] = "00ccff" }
SB.QUALITY_NAMES = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

local npcCache, lootCache, itemCache, questCache = {}, {}, {}, {}

------------------------------------------------------------------------------
-- NPCs
------------------------------------------------------------------------------

local function Ids(s)
    local out = {}
    for _, v in ipairs(List(s)) do out[#out + 1] = tonumber(v) end
    return out
end

-- Returns a table describing the NPC, or nil if it isn't in the database.
function SB.GetNpc(id)
    id = tonumber(id)
    if not id then return nil end
    local c = npcCache[id]
    if c ~= nil then return c or nil end
    local raw = D.npc and D.npc[id]
    if not raw then npcCache[id] = false return nil end
    local f = Fields(raw)
    local n = {
        id = id, name = f[N_NAME], sub = f[N_SUB] ~= "" and f[N_SUB] or nil,
        minLevel = tonumber(f[N_MINL]) or 0, maxLevel = tonumber(f[N_MAXL]) or 0,
        rank = tonumber(f[N_RANK]) or 0, type = tonumber(f[N_TYPE]) or 0, family = tonumber(f[N_FAMILY]) or 0,
        hpMin = tonumber(f[N_HPMIN]) or 0, hpMax = tonumber(f[N_HPMAX]) or 0, mana = tonumber(f[N_MANA]) or 0,
        goldMin = tonumber(f[N_GOLDMIN]) or 0, goldMax = tonumber(f[N_GOLDMAX]) or 0,
        friendly = f[N_FRIENDLY] ~= "" and f[N_FRIENDLY] or nil,
        starts = Ids(f[N_STARTS]), ends = Ids(f[N_ENDS]), killFor = Ids(f[N_KILLFOR]),
        worldDrops = tonumber(f[N_WORLD]) or 0, classic = f[N_CLASSIC] == "1", display = tonumber(f[N_DISPLAY]),
        zones = {}, dropFor = {},
    }
    local flags = f[N_FLAGS] or ""
    n.boss = flags:find("B") ~= nil
    n.skinnable = flags:find("S") ~= nil
    n.pickpocket = flags:find("P") ~= nil
    n.vendor = flags:find("V") ~= nil
    n.trainer = flags:find("T") ~= nil
    n.flightMaster = flags:find("F") ~= nil
    n.repair = flags:find("R") ~= nil
    for _, z in ipairs(List(f[N_ZONES])) do
        local area, x, y, count = strsplit(":", z)
        n.zones[#n.zones + 1] = { area = tonumber(area), x = tonumber(x), y = tonumber(y), count = tonumber(count) or 0 }
    end
    for _, d in ipairs(List(f[N_DROPFOR])) do
        local q, item = strsplit("/", d)
        n.dropFor[#n.dropFor + 1] = { quest = tonumber(q), item = tonumber(item) }
    end
    npcCache[id] = n
    return n
end

function SB.NpcName(id)
    local n = SB.GetNpc(id)
    return n and n.name or ("NPC #" .. tostring(id))
end

-- "Elite Boss", "Rare", ... (nil for plain normal mobs)
function SB.Classification(n)
    if n.boss then return n.rank == 0 and "Boss" or (n.rank == 3 and "Boss" or SB.RANKS[n.rank] .. " Boss") end
    if n.rank and n.rank > 0 then return SB.RANKS[n.rank] end
end

function SB.LevelText(n)
    if not n then return "?" end
    if n.rank == 3 or n.maxLevel >= 63 and n.boss then return "??" end
    if n.minLevel == n.maxLevel then return tostring(n.minLevel) end
    return n.minLevel .. "-" .. n.maxLevel
end

------------------------------------------------------------------------------
-- Loot
------------------------------------------------------------------------------

local function ParseLoot(s)
    local out = {}
    for _, e in ipairs(List(s)) do
        local item, chance, q = strsplit(":", e)
        out[#out + 1] = { item = tonumber(item), chance = tonumber(chance), quest = q == "q" }
    end
    return out
end

-- { {item=, chance=(percent or nil), quest=bool}, ... } highest chance first
function SB.GetLoot(id)
    local c = lootCache[id]
    if c then return c end
    c = ParseLoot(D.loot and D.loot[id])
    lootCache[id] = c
    return c
end

function SB.GetExtraLoot(id)
    local raw = D.lootx and D.lootx[id]
    local out = {}
    if not raw then return out end
    for _, part in ipairs(List(raw, ";")) do
        local kind, list = part:match("^(%a)=(.*)$")
        if kind == "s" then out.skinning = ParseLoot(list) elseif kind == "p" then out.pickpocket = ParseLoot(list) end
    end
    return out
end

function SB.GetSpells(id)
    return Ids(D.spells and D.spells[id])
end

------------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------------

local function GameItemInfo(id)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end
    local ok, name, link, quality, ilvl, req, _, _, _, _, icon = pcall(getInfo, id)
    if ok and name then return name, link, quality, ilvl, req, icon end
end

function SB.ItemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if f then
        local ok, icon = pcall(f, id)
        if ok and icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Asks the game to load an item it hasn't cached yet; GET_ITEM_INFO_RECEIVED fires when it has.
function SB.RequestItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

function SB.GetItem(id)
    id = tonumber(id)
    if not id then return nil end
    local it = itemCache[id]
    if not it then
        it = { id = id }
        local raw = D.item and D.item[id]
        if raw then
            local f = Fields(raw)
            it.name, it.quality, it.ilvl, it.req = f[1], tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
            it.class, it.subClass = tonumber(f[5]), tonumber(f[6])
            if it.quality == -1 then it.quality = nil end
        end
        itemCache[id] = it
    end
    if not it.link then
        local name, link, quality, ilvl, req = GameItemInfo(id)
        if name then
            it.name, it.link, it.quality = name, link, quality or it.quality
            it.ilvl, it.req = ilvl or it.ilvl, req or it.req
        else
            SB.RequestItem(id)
        end
    end
    it.name = it.name or ("Item #" .. id)
    return it
end

function SB.ItemText(id, noBrackets)
    local it = SB.GetItem(id)
    local hex = SB.QUALITY_HEX[it.quality or 1] or "ffffff"
    local name = noBrackets and it.name or ("[" .. it.name .. "]")
    return "|cff" .. hex .. name .. "|r"
end

-- total, { {npc=, chance=}, ... } highest chance first (capped list)
function SB.GetDroppedBy(id)
    local raw = D.dropby and D.dropby[id]
    if not raw then return 0, {} end
    local total, rest = raw:match("^(%d+)|(.*)$")
    local out = {}
    for _, e in ipairs(List(rest)) do
        local npc, chance = strsplit(":", e)
        out[#out + 1] = { npc = tonumber(npc), chance = tonumber(chance) }
    end
    return tonumber(total) or #out, out
end

-- { objectiveOf = {quests}, starts = quest, rewardOf = {quests}, vendors = {npcs}, vendorCount = n, containers = {items}, objects = n }
function SB.GetItemUses(id)
    local raw = D.itemq and D.itemq[id]
    local u = { objectiveOf = {}, rewardOf = {}, vendors = {}, containers = {}, vendorCount = 0, objects = 0 }
    if not raw then return u end
    for _, part in ipairs(List(raw, ";")) do
        local k, v = part:match("^(%a)=(.*)$")
        if k == "o" then u.objectiveOf = Ids(v)
        elseif k == "s" then u.starts = tonumber(v)
        elseif k == "r" then u.rewardOf = Ids(v)
        elseif k == "v" then
            local count, list = v:match("^(%d+)|(.*)$")
            u.vendorCount, u.vendors = tonumber(count) or 0, Ids(list)
        elseif k == "c" then u.containers = Ids(v)
        elseif k == "g" then u.objects = tonumber(v) or 0
        end
    end
    return u
end

------------------------------------------------------------------------------
-- Quests
------------------------------------------------------------------------------

function SB.GetQuest(id)
    id = tonumber(id)
    if not id then return nil end
    local c = questCache[id]
    if c ~= nil then return c or nil end
    local raw = D.quest and D.quest[id]
    if not raw then questCache[id] = false return nil end
    local f = Fields(raw)
    c = { id = id, name = f[1], level = tonumber(f[2]) or 0, reqLevel = tonumber(f[3]) or 0,
          faction = f[4] ~= "" and f[4] or nil, classMask = tonumber(f[5]) or 0, text = f[6],
          starters = Ids(f[7]), enders = Ids(f[8]), kill = Ids(f[9]), items = Ids(f[10]) }
    questCache[id] = c
    return c
end

-- Can this character do the quest at all (faction / class)?
function SB.QuestForMe(q)
    if not q then return false end
    if q.faction then
        local fac = UnitFactionGroup and UnitFactionGroup("player")
        if fac == "Alliance" and q.faction ~= "A" then return false end
        if fac == "Horde" and q.faction ~= "H" then return false end
    end
    if q.classMask and q.classMask > 0 and bit and bit.band then
        local classId = select(3, UnitClass("player"))
        if classId and bit.band(q.classMask, 2 ^ (classId - 1)) == 0 then return false end
    end
    return true
end

function SB.QuestDone(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
        return ok and done or false
    end
    return false
end

------------------------------------------------------------------------------
-- Zones
------------------------------------------------------------------------------

function SB.ZoneName(area)
    area = tonumber(area)
    if not area then return "Unknown" end
    area = D.zoneAlias and D.zoneAlias[area] or area
    if C_Map and C_Map.GetAreaInfo then
        local ok, name = pcall(C_Map.GetAreaInfo, area)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return D.zoneName and D.zoneName[area] or ("Zone #" .. area)
end

function SB.IsInstanceArea(area)
    area = D.zoneAlias and D.zoneAlias[area] or area
    if not D.instanceArea then return false end
    for _, a in pairs(D.instanceArea) do if a == area then return true end end
    return false
end

-- The areas (database zone IDs) for where the player is now, and a label for them.
function SB.PlayerAreas()
    local areas = {}
    local inInstance = IsInInstance and IsInInstance()
    if inInstance and GetInstanceInfo then
        local name, _, _, _, _, _, _, mapId = GetInstanceInfo()
        local area = D.instanceArea and D.instanceArea[mapId]
        if area then
            areas[area] = true
            for alias, parent in pairs(D.zoneAlias or {}) do if parent == area then areas[alias] = true end end
            return areas, name or SB.ZoneName(area)
        end
    end
    local uiMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if uiMap then
        for area, m in pairs(D.uiMap or {}) do if m == uiMap then areas[area] = true end end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(uiMap)
        return areas, info and info.name or GetZoneText()
    end
    return areas, GetZoneText and GetZoneText() or "?"
end

local zoneIndex
-- NPC ids that spawn in any of the given areas, bosses first then by level.
function SB.NpcsInAreas(areas)
    if not zoneIndex then
        zoneIndex = {}
        for id, raw in pairs(D.npc or {}) do
            local zones = raw:match("^" .. ("[^^]*%^"):rep(N_ZONES - 1) .. "([^^]*)")
            if zones then
                for area in zones:gmatch("(%d+):[^,]*") do
                    area = tonumber(area)
                    zoneIndex[area] = zoneIndex[area] or {}
                    table.insert(zoneIndex[area], id)
                end
            end
        end
    end
    local seen, out = {}, {}
    for area in pairs(areas) do
        for _, id in ipairs(zoneIndex[area] or {}) do
            if not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
    end
    table.sort(out, function(a, b)
        local na, nb = SB.GetNpc(a), SB.GetNpc(b)
        if na.boss ~= nb.boss then return na.boss end
        if na.maxLevel ~= nb.maxLevel then return na.maxLevel > nb.maxLevel end
        return na.name < nb.name
    end)
    return out
end

------------------------------------------------------------------------------
-- Search
------------------------------------------------------------------------------

local npcNames, itemNames
local function BuildNames(tbl)
    local t = {}
    for id, raw in pairs(tbl or {}) do t[id] = (raw:match("^[^^]*") or ""):lower() end
    return t
end

-- Matches by name (or by ID); exact and prefix matches first.
function SB.Search(text, limit)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    limit = limit or 150
    if text == "" then return {} end
    npcNames = npcNames or BuildNames(D.npc)
    itemNames = itemNames or BuildNames(D.item)
    local results = {}
    local asId = tonumber(text)
    local function Scan(names, kind)
        for id, name in pairs(names) do
            local score
            if asId and id == asId then score = 0
            elseif name == text then score = 1
            elseif name:sub(1, #text) == text then score = 2
            elseif name:find(text, 1, true) then score = 3 end
            if score then results[#results + 1] = { kind = kind, id = id, score = score, name = name } end
        end
    end
    Scan(npcNames, "npc")
    Scan(itemNames, "item")
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if a.kind ~= b.kind then return a.kind == "npc" end
        if #a.name ~= #b.name then return #a.name < #b.name end
        return a.id < b.id
    end)
    for i = #results, limit + 1, -1 do results[i] = nil end
    return results
end

------------------------------------------------------------------------------
-- Spells
------------------------------------------------------------------------------

function SB.SpellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and info.name then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local ok, name, _, icon = pcall(GetSpellInfo, id)
        if ok and name then return name, icon end
    end
    return nil
end

function SB.SpellDescription(id)
    local f = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    if f then
        local ok, d = pcall(f, id)
        if ok and type(d) == "string" and d ~= "" then return d end
    end
end
