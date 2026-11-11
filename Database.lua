-- Where Total Intel's facts come from. Everything about WoW: Forever itself is read live:
--   * QuestieDB (LibQuestieDB): NPCs, levels, spawns, quests, who drops and sells each item,
--     zones and instances. It is updated along with Forever, so Total Intel follows it.
--   * The game client: item names, quality and levels (hotfixes included), spells, the
--     Adventure Guide, and recipes (Professions.lua).
-- Only Classic reference numbers that no live source has are bundled (Data/*.lua, CMaNGOS):
-- drop chances, health, mana, coin, creature type, abilities, display IDs.

local _, SB = ...
local D = SB.D
local Fields, List = SB.Fields, SB.List

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
SB.RAID_MAPS = { [409] = true, [249] = true, [469] = true, [309] = true, [509] = true, [531] = true, [533] = true }

------------------------------------------------------------------------------
-- QuestieDB
------------------------------------------------------------------------------

local LQ, NpcDB, ItemDB, QuestDB, ZoneDB, DropRates
local lastTry = -100
SB.dataSource = nil   -- "QuestieDB" (the LibQuestieDB addon) or "Questie" (Questie's built-in database)

-- Questie's own database module (Questie releases that don't use the separate QuestieDB addon),
-- wrapped to look like LibQuestieDB's entities. It only answers once Questie has finished
-- loading it, a few seconds after login.
local function QuestieBuiltIn()
    local loader = _G.QuestieLoader
    if type(loader) ~= "table" or not loader.ImportModule then return nil end
    local ok, qdb = pcall(loader.ImportModule, loader, "QuestieDB")
    if not ok or type(qdb) ~= "table" or type(qdb.QueryNPCSingle) ~= "function" then return nil end
    local probe, name = pcall(qdb.QueryNPCSingle, 448, "name")
    if not probe or type(name) ~= "string" then return nil end
    local function Entity(query, pointers)
        return {
            Get = function(id, key) return query(id, key) end,
            GetAllIds = function()
                local ids = {}
                for id in pairs(type(qdb[pointers]) == "table" and qdb[pointers] or {}) do ids[#ids + 1] = id end
                table.sort(ids)
                return ids
            end,
        }
    end
    return {
        Npc = Entity(qdb.QueryNPCSingle, "NPCPointers"),
        Item = Entity(qdb.QueryItemSingle, "ItemPointers"),
        Quest = Entity(qdb.QueryQuestSingle, "QuestPointers"),
        Enum = { npcFlags = qdb.npcFlags },
        Support = { Get = function(module)
            local okm, m = pcall(loader.ImportModule, loader, module)
            return okm and m or nil
        end },
    }
end

local function FindLive()
    local lib = _G.LibQuestieDB
    if type(lib) == "table" and lib.Npc and lib.Item and lib.Quest then
        local ok, res = true, true
        if lib.RequireContract then ok, res = pcall(lib.RequireContract, 1) end
        if ok and res ~= false then return lib, "QuestieDB" end
    end
    local q = QuestieBuiltIn()
    if q then return q, "Questie" end
end

local function Adopt(db, source)
    LQ, SB.dataSource = db, source
    NpcDB, ItemDB, QuestDB, ZoneDB, DropRates = db.Npc, db.Item, db.Quest, nil, nil
    if db.Support and db.Support.Get then
        local ok, z = pcall(db.Support.Get, "ZoneDB")
        if ok then ZoneDB = z end
    end
    if SB.ResetCaches then SB.ResetCaches() end
    -- a different database than the index was built from: build it again
    if SB.index and SB.index.started and SB.BuildIndex then SB.After(0.5, function() SB.BuildIndex() end) end
end

-- The database for NPCs, quests and items. A live one is preferred: the QuestieDB addon
-- (LibQuestieDB) or Questie's built-in database, which Questie fills a few seconds after login,
-- so it is looked for again every few seconds. Until one answers, and when neither is
-- installed, the bundled snapshot of QuestieDB's Forever data is used (Bundled.lua).
function SB.QDB()
    if LQ and SB.dataSource ~= "bundled" then return LQ end
    local now = GetTime and GetTime() or 0
    if now - lastTry >= 3 then
        lastTry = now
        local live, source = FindLive()
        if live then Adopt(live, source) return LQ end
    end
    if not LQ then
        local b = SB.Bundled and SB.Bundled()
        if b then Adopt(b, "bundled") end
    end
    return LQ
end

-- Where NPC, quest and item data comes from right now, for the indicator in the window:
-- label, live (true when a Questie database is being read), and lines explaining it.
function SB.DataSource()
    local db = SB.QDB()
    if SB.dataSource == "QuestieDB" then
        return "Data: live (QuestieDB)", true, {
            "NPCs, quests, spawns and vendors are read live from the QuestieDB addon.",
            "They update whenever QuestieDB updates.",
        }
    elseif SB.dataSource == "Questie" then
        return "Data: live (Questie)", true, {
            "NPCs, quests, spawns and vendors are read live from Questie's database.",
            "They update whenever Questie updates.",
        }
    elseif db then
        local date = db.info and db.info.date or "?"
        return "Data: built-in snapshot", false, {
            "NPCs, quests, spawns and vendors come from Total Intel's built-in snapshot of Forever (" .. date .. ").",
            "Install |cffffffffQuestie|r or the |cffffffffQuestieDB|r addon for better data: Total Intel then reads their database instead, with newer quests, NPCs and spawn points whenever they update.",
        }
    end
    return "Data: none", false, { "No NPC or quest database is loaded. Type /tits status for details." }
end

-- Forgets the database (used by the tests to swap databases).
function SB.ResetSources()
    LQ, NpcDB, ItemDB, QuestDB, ZoneDB, DropRates, lastTry = nil, nil, nil, nil, nil, nil, -100
    SB.dataSource = nil
    SB.ResetCaches()
end

local function Get(entity, id, key)
    if not entity or not id then return nil end
    local ok, v = pcall(entity.Get, id, key)
    if ok then return v end
end
local function N(id, key) SB.QDB() return Get(NpcDB, id, key) end
local function I(id, key) SB.QDB() return Get(ItemDB, id, key) end
local function Q(id, key) SB.QDB() return Get(QuestDB, id, key) end

local function AllIds(entity)
    if not entity or not entity.GetAllIds then return {} end
    local ok, ids = pcall(entity.GetAllIds)
    return ok and ids or {}
end

-- Wowhead drop rates for quest items, shipped by QuestieDB: item -> { [npc] = percent }
local function WowheadRates()
    if DropRates ~= nil then return DropRates or nil end
    DropRates = false
    SB.QDB()
    if not (LQ and LQ.Support and LQ.Support.Get) then return nil end
    local ok, mod = pcall(LQ.Support.Get, "QuestieClassicItemDrops")
    if ok and type(mod) == "table" and type(mod.wowheadData) == "string" then
        local fn = loadstring(mod.wowheadData)
        local ok2, data = pcall(fn or error)
        if ok2 and type(data) == "table" then DropRates = data end
    elseif ok and type(mod) == "table" and type(mod.wowheadData) == "table" then
        DropRates = mod.wowheadData
    end
    return DropRates or nil
end

------------------------------------------------------------------------------
-- Classic reference numbers (bundled)
------------------------------------------------------------------------------

local cmCache = {}
local function Classic(id)
    local c = cmCache[id]
    if c ~= nil then return c or nil end
    local raw = D.cm and D.cm[id]
    if not raw then cmCache[id] = false return nil end
    local f = Fields(raw)
    c = { rank = tonumber(f[1]) or 0, type = tonumber(f[2]) or 0, family = tonumber(f[3]) or 0,
          hpMin = tonumber(f[4]) or 0, hpMax = tonumber(f[5]) or 0, mana = tonumber(f[6]) or 0,
          goldMin = tonumber(f[7]) or 0, goldMax = tonumber(f[8]) or 0, flags = f[9] or "",
          display = tonumber(f[10]) or 0, worldDrops = tonumber(f[11]) or 0, map = tonumber(f[12]) or 0 }
    cmCache[id] = c
    return c
end
SB.Classic = Classic

local function ParseLoot(s)
    local out = {}
    for _, e in ipairs(List(s)) do
        local item, chance, q = strsplit(":", e)
        out[#out + 1] = { item = tonumber(item), chance = tonumber(chance), quest = q == "q", src = "classic" }
    end
    return out
end

------------------------------------------------------------------------------
-- Zones and instances (from QuestieDB's ZoneDB, names from the client)
------------------------------------------------------------------------------

local uiMapOf, areasOfUiMap, dungeonParent, dungeonName
local function ZoneTables()
    if uiMapOf then return end
    SB.QDB()   -- first: finding a database resets these tables
    uiMapOf, areasOfUiMap, dungeonParent, dungeonName = {}, {}, {}, {}
    local priv = ZoneDB and ZoneDB.private or {}
    for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
        local src = priv[key]
        local t = type(src) == "string" and select(2, pcall(loadstring(src) or error)) or src
        if type(t) == "table" then
            for area, ui in pairs(t) do
                if type(ui) == "number" and ui > 0 then uiMapOf[area] = ui else uiMapOf[area] = nil end
            end
        end
    end
    for area, ui in pairs(uiMapOf) do
        areasOfUiMap[ui] = areasOfUiMap[ui] or {}
        areasOfUiMap[ui][area] = true
    end
    for area, d in pairs(type(priv.dungeons) == "table" and priv.dungeons or {}) do
        dungeonName[area] = d[1]
        for _, alt in ipairs(type(d[2]) == "table" and d[2] or {}) do dungeonParent[alt] = area end
    end
end

function SB.UiMapForArea(area)
    ZoneTables()
    return uiMapOf[area]
end

function SB.ZoneName(area)
    area = tonumber(area)
    if not area or area == 0 then return "Unknown" end
    ZoneTables()
    area = dungeonParent[area] or area
    if dungeonName[area] then return dungeonName[area] end
    if C_Map and C_Map.GetAreaInfo then
        local ok, name = pcall(C_Map.GetAreaInfo, area)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    local names = ZoneDB and ZoneDB.names
    return names and names[area] or ("Zone #" .. area)
end

local function InstanceAreaTable()
    SB.QDB()
    return ZoneDB and type(ZoneDB.instanceIdToAreaId) == "table" and ZoneDB.instanceIdToAreaId or {}
end

function SB.InstanceAreas(mapID)
    local area = InstanceAreaTable()[mapID]
    if not area then return nil end
    ZoneTables()
    local areas = { [area] = true }
    for alt, parent in pairs(dungeonParent) do if parent == area then areas[alt] = true end end
    return areas, area
end

-- The areas for where the player is now, and a label for them.
function SB.PlayerAreas()
    local mapID = SB.CurrentInstance()
    if mapID then
        local areas, area = SB.InstanceAreas(mapID)
        return areas, (GetInstanceInfo and GetInstanceInfo()) or SB.ZoneName(area), mapID
    end
    ZoneTables()
    local ui = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local areas = {}
    if ui and areasOfUiMap[ui] then for a in pairs(areasOfUiMap[ui]) do areas[a] = true end end
    local info = ui and C_Map.GetMapInfo and C_Map.GetMapInfo(ui)
    return areas, info and info.name or (GetZoneText and GetZoneText()) or "?"
end

-- Every area on the same map as `area` (a zone and its subzones).
function SB.AreasForZone(area)
    ZoneTables()
    local out = { [area] = true }
    local ui = uiMapOf[area]
    if ui and areasOfUiMap[ui] then for a in pairs(areasOfUiMap[ui]) do out[a] = true end end
    return out
end

local function MapInfo(ui)
    if not (ui and C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, ui)
    return ok and type(info) == "table" and info or nil
end

-- Every outdoor zone with mobs: { {area, name, continent, mobs, minLevel, maxLevel}, ... },
-- sorted by continent then name. Zones on the same map are merged. Built once per index.
local zoneDirectory
function SB.ZoneDirectory()
    if zoneDirectory and zoneDirectory.ready == SB.index.ready then return zoneDirectory end
    ZoneTables()
    local instances = {}
    for _, a in pairs(InstanceAreaTable()) do instances[a] = true end
    local byKey, list = {}, {}
    for area, npcs in pairs(SB.index.npcsInArea or {}) do
        local top = dungeonParent[area] or area
        if not instances[top] and not dungeonName[top] then
            local ui = uiMapOf[area]
            local key = ui and ("m" .. ui) or ("a" .. area)
            local z = byKey[key]
            if not z then
                z = { area = area, uiMap = ui, seen = {}, mobs = 0 }
                byKey[key] = z
                list[#list + 1] = z
            end
            for _, id in ipairs(npcs) do
                if not z.seen[id] then z.seen[id] = true; z.mobs = z.mobs + 1 end
            end
        end
    end
    for _, z in ipairs(list) do
        local info = MapInfo(z.uiMap)
        z.name = info and info.name or SB.ZoneName(z.area)
        local parent = info and MapInfo(info.parentMapID)
        z.continent = parent and parent.name or "Zones"
        local lo, hi = 999, 0
        for id in pairs(z.seen) do
            local minL, maxL, rank = N(id, "minLevel") or 0, N(id, "maxLevel") or 0, N(id, "rank") or 0
            local friendly = N(id, "friendlyToFaction")
            if minL > 0 and maxL < 64 and rank ~= 3 and (friendly == nil or friendly == "") then
                lo, hi = math.min(lo, minL), math.max(hi, maxL)
            end
        end
        if hi > 0 then z.minLevel, z.maxLevel = lo, hi end
        z.seen = nil
    end
    table.sort(list, function(a, b)
        if a.continent ~= b.continent then return a.continent < b.continent end
        return a.name < b.name
    end)
    list.ready = SB.index.ready
    zoneDirectory = list
    return list
end

-- A zone from the directory by (part of) its name.
function SB.FindZone(text)
    text = (text or ""):lower()
    if text == "" then return nil end
    local best
    for _, z in ipairs(SB.ZoneDirectory()) do
        local name = z.name:lower()
        if name == text then return z end
        if not best and name:find(text, 1, true) then best = z end
    end
    return best
end

function SB.CurrentInstance()
    if not (IsInInstance and IsInInstance()) or not GetInstanceInfo then return nil end
    local mapID = select(8, GetInstanceInfo())
    if mapID and InstanceAreaTable()[mapID] then return mapID end
end

------------------------------------------------------------------------------
-- Background indexes: the reverse lookups no single getter answers
------------------------------------------------------------------------------

local idx = {}
SB.index = idx

local function Add(t, k, v)
    local l = t[k]
    if not l then l = {}; t[k] = l end
    l[#l + 1] = v
end

-- steps yield between batches when run as a coroutine
local function Build(yield)
    local count = 0
    local function Tick()
        count = count + 1
        if yield and count % 150 == 0 then coroutine.yield() end
    end
    local n = {
        foreverItems = {},     -- npc  -> { item, ... } from QuestieDB's npcDrops
        sells = {},            -- npc  -> { item, ... } from QuestieDB's vendors
        rewards = {},          -- quest -> { item, ... } from QuestieDB's questRewards
        npcsInArea = {},       -- area -> { npc, ... }
        killFor = {},          -- npc  -> { quest, ... }
        itemFor = {},          -- item -> { quest, ... } (quest objectives and required items)
    }
    if SB.QDB() then
        for _, item in ipairs(AllIds(ItemDB)) do
            for _, npc in ipairs(I(item, "npcDrops") or {}) do Add(n.foreverItems, npc, item) end
            for _, npc in ipairs(I(item, "vendors") or {}) do Add(n.sells, npc, item) end
            for _, q in ipairs(I(item, "questRewards") or {}) do Add(n.rewards, q, item) end
            Tick()
        end
        for _, npc in ipairs(AllIds(NpcDB)) do
            local spawns = N(npc, "spawns")
            local any = false
            if type(spawns) == "table" then
                for area in pairs(spawns) do Add(n.npcsInArea, area, npc); any = true end
            end
            if not any then
                local z = N(npc, "zoneID")
                if z and z ~= 0 then Add(n.npcsInArea, z, npc); any = true end
            end
            if not any then
                local c = Classic(npc)
                local area = c and c.map > 0 and InstanceAreaTable()[c.map]
                if area then Add(n.npcsInArea, area, npc) end
            end
            Tick()
        end
        for _, q in ipairs(AllIds(QuestDB)) do
            local o = Q(q, "objectives") or {}
            for _, c in ipairs(o[1] or {}) do if c[1] then Add(n.killFor, c[1], q) end end
            for _, kc in ipairs(o[5] or {}) do
                for _, c in ipairs(kc[1] or {}) do Add(n.killFor, c, q) end
                if kc[2] then Add(n.killFor, kc[2], q) end
            end
            for _, it in ipairs(o[3] or {}) do if it[1] then Add(n.itemFor, it[1], q) end end
            for _, it in ipairs(Q(q, "requiredSourceItems") or {}) do Add(n.itemFor, it, q) end
            Tick()
        end
    end
    for k, v in pairs(n) do idx[k] = v end
    idx.ready = true
    idx.built = true
    idx.source = SB.dataSource
    if SB.OnIndexReady then SB.OnIndexReady() end
end

-- now = build synchronously (tests); otherwise spread over a few seconds after login.
-- Starting a build while one is running replaces it.
local generation = 0
function SB.BuildIndex(now)
    idx.ready, idx.started, idx.error = false, true, nil
    generation = generation + 1
    local mine = generation
    if now or not (C_Timer and C_Timer.NewTicker) then Build(false) return end
    local co = coroutine.create(function() Build(true) end)
    local ticker
    ticker = C_Timer.NewTicker(0.02, function()
        if mine ~= generation then ticker:Cancel() return end
        local ok, err = coroutine.resume(co)
        if not ok then
            idx.error = tostring(err)
            SB.Print("|cffff5555couldn't read the database:|r " .. idx.error .. " (type /tits status and send this to the author)")
            ticker:Cancel()
        elseif coroutine.status(co) == "dead" then
            ticker:Cancel()
        end
    end)
end
SB.On("PLAYER_LOGIN", function()
    SB.After(2, function() SB.BuildIndex() end)
    -- Questie fills its database a little after login: check for it for a few minutes
    if C_Timer and C_Timer.NewTicker then
        local tries = 0
        local t
        t = C_Timer.NewTicker(5, function()
            tries = tries + 1
            SB.QDB()
            if SB.dataSource ~= "bundled" or tries > 40 then t:Cancel() end
        end)
    end
end)

------------------------------------------------------------------------------
-- NPCs
------------------------------------------------------------------------------

local npcCache = {}

local function Zones(id, c)
    local zones = {}
    local spawns = N(id, "spawns")
    if type(spawns) == "table" then
        for area, pts in pairs(spawns) do
            local list = {}
            for _, p in ipairs(pts) do if type(p) == "table" and p[1] and p[1] >= 0 then list[#list + 1] = p end end
            local z = { area = area, count = pts.count or #list }
            if #list > 0 then
                local cx, cy = 0, 0
                for _, p in ipairs(list) do cx, cy = cx + p[1], cy + p[2] end
                cx, cy = cx / #list, cy / #list
                local best, bd
                for _, p in ipairs(list) do
                    local d = (p[1] - cx) ^ 2 + (p[2] - cy) ^ 2
                    if not bd or d < bd then best, bd = p, d end
                end
                z.x, z.y = best[1], best[2]
            end
            zones[#zones + 1] = z
        end
        table.sort(zones, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.area < b.area end)
    end
    if #zones == 0 then
        local z = N(id, "zoneID")
        local area = (z and z ~= 0 and z) or (c and c.map > 0 and InstanceAreaTable()[c.map])
        if area then zones[1] = { area = area, count = 0 } end
    end
    return zones
end

local function Flags()
    SB.QDB()
    local f = LQ and LQ.Enum and LQ.Enum.npcFlags
    return f or { VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, REPAIR = 16384 }
end

local function HasFlag(flags, bitValue)
    if not bitValue or bitValue == 0 or not flags then return false end
    return math.floor(flags / bitValue) % 2 == 1
end

-- The name the game client has cached for a creature (any NPC you or the client has seen).
local function ClientNpcName(id)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, ("unit:Creature-0-0-0-0-%d-0000000000"):format(id))
    local line = ok and type(data) == "table" and data.lines and data.lines[1]
    local name = line and SB.Public(line.leftText)
    if type(name) == "string" and name ~= "" and not name:find("^Unknown") then return name end
end
SB.ClientNpcName = ClientNpcName

-- A table describing the NPC (nil if nothing at all is known about it).
function SB.GetNpc(id)
    id = tonumber(id)
    if not id then return nil end
    local cached = npcCache[id]
    if cached ~= nil then return cached or nil end
    local c = Classic(id)
    local name = N(id, "name")
    local seen = SB.db and SB.db.mobs[id]
    if not name then name = (seen and seen.name) or ClientNpcName(id) end
    if not name and not c and not seen then npcCache[id] = false return nil end
    local n = {
        id = id, name = name or ("NPC #" .. id), sub = N(id, "subName"),
        minLevel = N(id, "minLevel") or 0, maxLevel = N(id, "maxLevel") or 0,
        rank = N(id, "rank") or (c and c.rank) or 0,
        type = c and c.type or 0, family = c and c.family or 0,
        hpMin = c and c.hpMin or 0, hpMax = c and c.hpMax or 0, mana = c and c.mana or 0,
        goldMin = c and c.goldMin or 0, goldMax = c and c.goldMax or 0,
        friendly = N(id, "friendlyToFaction"), starts = N(id, "questStarts") or {}, ends = N(id, "questEnds") or {},
        worldDrops = c and c.worldDrops or 0, display = c and c.display or 0,
        live = name ~= nil, classic = c ~= nil,
    }
    if n.sub == "" then n.sub = nil end
    if n.friendly == "" then n.friendly = nil end
    if n.maxLevel == 0 and seen and seen.lv then n.minLevel, n.maxLevel = seen.lv, seen.lv end
    local flags = c and c.flags or ""
    n.boss = flags:find("B") ~= nil or n.rank == 3
    n.skinnable = flags:find("S") ~= nil
    n.pickpocket = flags:find("P") ~= nil
    local npcFlags, F = N(id, "npcFlags") or 0, Flags()
    n.vendor = HasFlag(npcFlags, F.VENDOR)
    n.trainer = HasFlag(npcFlags, F.TRAINER)
    n.flightMaster = HasFlag(npcFlags, F.FLIGHT_MASTER)
    n.repair = HasFlag(npcFlags, F.REPAIR)
    n.zones = Zones(id, c)
    -- keep asking the client for a name it hasn't cached yet
    if name then npcCache[id] = n end
    return n
end

-- Forget what's cached about an NPC (after seeing its name in the game).
function SB.ForgetNpc(id) npcCache[id] = nil end

function SB.NpcName(id)
    local n = SB.GetNpc(id)
    return n and n.name or ("NPC #" .. tostring(id))
end

function SB.Classification(n)
    if n.boss then return (n.rank == 1 or n.rank == 2) and (SB.RANKS[n.rank] .. " Boss") or "Boss" end
    if n.rank and n.rank > 0 then return SB.RANKS[n.rank] end
end

function SB.LevelText(n)
    if not n then return "?" end
    if n.maxLevel == 0 then return "?" end
    if n.boss and n.rank == 3 and n.maxLevel >= 63 then return "??" end
    if n.minLevel == n.maxLevel then return tostring(n.minLevel) end
    return n.minLevel .. "-" .. n.maxLevel
end

-- Quests that need this NPC killed (from the index; empty until it's built).
function SB.KillFor(id) return idx.killFor and idx.killFor[id] or {} end

-- Quests that need an item this NPC drops: { {quest=, item=} }
function SB.DropFor(id)
    local out, seen = {}, {}
    for _, d in ipairs(SB.GetLoot(id)) do
        for _, q in ipairs(idx.itemFor and idx.itemFor[d.item] or {}) do
            local it = SB.GetItem(d.item)
            -- quest items, or items a limited set of mobs drop (Murloc Fin: yes; Linen Cloth, dropped by
            -- 700 kinds of mob: no)
            local few = SB.DropperCount(d.item) <= 100
            if (d.quest or it.class == 12 or few) and not seen[q .. ":" .. d.item] then
                seen[q .. ":" .. d.item] = true
                out[#out + 1] = { quest = q, item = d.item }
            end
        end
    end
    return out
end

------------------------------------------------------------------------------
-- Loot
------------------------------------------------------------------------------

local lootCache = {}

-- { {item=, chance=(percent or nil), quest=bool, src="classic"|"wowhead"|nil}, ... } best first.
-- Forever (QuestieDB) decides which items drop; the chance is Wowhead's for quest items,
-- otherwise the Classic number when there is one.
function SB.GetLoot(id)
    local c = lootCache[id]
    if c and (c.ready or not idx.ready) then return c end
    c = ParseLoot(D.loot and D.loot[id])
    local have = {}
    for _, d in ipairs(c) do have[d.item] = d end
    local rates = WowheadRates()
    for _, item in ipairs(idx.foreverItems and idx.foreverItems[id] or {}) do
        if not have[item] then
            local d = { item = item, quest = false }
            c[#c + 1] = d
            have[item] = d
        end
    end
    if rates then
        for item, d in pairs(have) do
            local r = rates[item] and rates[item][id]
            if r then d.chance, d.src = r, "wowhead" end
        end
    end
    table.sort(c, function(a, b)
        if (a.chance or -1) ~= (b.chance or -1) then return (a.chance or -1) > (b.chance or -1) end
        return a.item < b.item
    end)
    c.ready = idx.ready
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

local function Ids(s)
    local out = {}
    for _, v in ipairs(List(s)) do out[#out + 1] = tonumber(v) end
    return out
end

-- What a vendor sells: the list you saw in the game (with prices) when you've visited it,
-- otherwise QuestieDB's. { {item=, price=, stack=, limited=}, ... }, src = "game"|"questie"
function SB.Sells(id)
    local seen = SB.db and SB.db.vendors and SB.db.vendors[id]
    if seen and seen.items then return seen.items, "game", seen.t end
    local out = {}
    for _, item in ipairs(idx.sells and idx.sells[id] or {}) do out[#out + 1] = { item = item } end
    table.sort(out, function(a, b) return a.item < b.item end)
    return out, "questie"
end

local function ParseTrainer(s, out)
    for spell, cost, level, line, skill in (s or ""):gmatch("(%d+):(%d+):(%d+):(%d+):(%d+)") do
        out[#out + 1] = { spell = tonumber(spell), cost = tonumber(cost), level = tonumber(level),
                          skillLine = tonumber(line), skill = tonumber(skill) }
    end
end

-- What a trainer teaches: the list you saw in the game when you've visited it, otherwise the
-- Classic reference list. { {spell=, name=, rank=, cost=, level=, skill=, skillName=, icon=}, ... }, src
function SB.Teaches(id)
    local seen = SB.db and SB.db.trainers and SB.db.trainers[id]
    if seen and seen.list and #seen.list > 0 then return seen.list, "game", seen.t end
    local out = {}
    for _, part in ipairs(List(D.trainer and D.trainer[id], ";")) do
        local tpl = part:match("^t(%d+)$")
        if tpl then ParseTrainer(D.ttpl and D.ttpl[tonumber(tpl)], out) else ParseTrainer(part, out) end
    end
    return out, "classic"
end

function SB.GetSpells(id)
    return Ids(D.spells and D.spells[id])
end

-- Classic loot is stored per NPC ("item:chance[:q],..."). Who drops an item is found by searching
-- those strings when asked (about a millisecond), and the last few hundred answers are kept:
-- an up-front table of every drop would cost tens of megabytes.
local function ClassicEntry(raw, item)
    if not raw then return nil end
    local needle = item .. ":"
    local a, b = raw:find(needle, 1, true)
    while a do
        if a == 1 or raw:byte(a - 1) == 44 then
            local chance, q = raw:match("^([%d.]+)(:?q?)", b + 1)
            return tonumber(chance), q == ":q"
        end
        a, b = raw:find(needle, b + 1, true)
    end
end

local byItem, byItemCount = {}, 0
local function ClassicDroppers(item)
    local list = byItem[item]
    if list then return list end
    list = {}
    for npc, raw in pairs(D.loot or {}) do
        local chance, quest = ClassicEntry(raw, item)
        if chance then list[#list + 1] = { npc = npc, chance = chance, quest = quest } end
    end
    table.sort(list, function(a, b)
        if a.chance ~= b.chance then return a.chance > b.chance end
        return a.npc < b.npc
    end)
    if byItemCount > 300 then byItem, byItemCount = {}, 0 end
    byItem[item] = list
    byItemCount = byItemCount + 1
    return list
end

-- The chance for one NPC/item pair: Wowhead's rate for quest items, else the Classic number.
local function ChanceFor(npc, item)
    local rates = WowheadRates()
    local r = rates and rates[item] and rates[item][npc]
    if r then return r, "wowhead" end
    local c = ClassicEntry(D.loot and D.loot[npc], item)
    if c then return c, "classic" end
end

-- How many NPCs drop the item (cheap; no chances looked up).
function SB.DropperCount(item)
    local seen, n = {}, 0
    for _, npc in ipairs(I(item, "npcDrops") or {}) do if not seen[npc] then seen[npc] = true; n = n + 1 end end
    for _, d in ipairs(ClassicDroppers(item)) do if not seen[d.npc] then seen[d.npc] = true; n = n + 1 end end
    return n
end

-- Every NPC that drops the item: { {npc=, chance=, src=} } best first. Live list from QuestieDB,
-- plus Classic sources it doesn't list.
function SB.Droppers(item)
    local out, seen = {}, {}
    for _, npc in ipairs(I(item, "npcDrops") or {}) do
        if not seen[npc] then
            seen[npc] = true
            local chance, src = ChanceFor(npc, item)
            out[#out + 1] = { npc = npc, chance = chance, src = src }
        end
    end
    for _, d in ipairs(ClassicDroppers(item)) do
        if not seen[d.npc] then
            seen[d.npc] = true
            local chance, src = ChanceFor(d.npc, item)
            out[#out + 1] = { npc = d.npc, chance = chance or d.chance, src = src or "classic" }
        end
    end
    table.sort(out, function(a, b)
        if (a.chance or -1) ~= (b.chance or -1) then return (a.chance or -1) > (b.chance or -1) end
        return a.npc < b.npc
    end)
    return out
end

function SB.GetDroppedBy(item)
    local list = SB.Droppers(item)
    return #list, list
end

------------------------------------------------------------------------------
-- Items (the client first: it knows every Forever item, hotfixes included)
------------------------------------------------------------------------------

local itemCache = {}

local function GameItemInfo(id)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end
    local ok, name, link, quality, ilvl, req, _, _, _, _, icon, _, class, subClass = pcall(getInfo, id)
    if ok and name then return name, link, quality, ilvl, req, icon, class, subClass end
end

function SB.ItemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if f then
        local ok, icon = pcall(f, id)
        if ok and icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function SB.RequestItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

function SB.GetItem(id)
    id = tonumber(id)
    if not id then return nil end
    local it = itemCache[id]
    if not it then
        it = { id = id, name = I(id, "name"), ilvl = I(id, "itemLevel"), req = I(id, "requiredLevel"),
               class = I(id, "class"), subClass = I(id, "subClass") }
        if C_Item and C_Item.GetItemQualityByID then
            local ok, q = pcall(C_Item.GetItemQualityByID, id)
            if ok and q then it.quality = q end
        end
        itemCache[id] = it
    end
    if not it.link then
        local name, link, quality, ilvl, req, _, class, subClass = GameItemInfo(id)
        if name then
            it.name, it.link, it.quality = name, link, quality or it.quality
            it.ilvl, it.req = ilvl or it.ilvl, req or it.req
            it.class, it.subClass = class or it.class, subClass or it.subClass
        else
            SB.RequestItem(id)
        end
    end
    if not it.name then it.name = "Item #" .. id end
    return it
end

function SB.ItemText(id, noBrackets, journal)
    local it = SB.GetItem(id)
    local q = it.quality or 1
    local hex = SB.QUALITY_HEX[q] or "ffffff"
    if journal and q <= 1 and SB.Skin and SB.Skin.Journal() then hex = SB.Skin.Hex("text") end
    local name = noBrackets and it.name or ("[" .. it.name .. "]")
    return "|cff" .. hex .. name .. "|r"
end

-- { objectiveOf = {quests}, starts = quest, rewardOf = {quests}, vendors = {npcs}, vendorCount, containers = {items}, objects }
function SB.GetItemUses(id)
    local u = { objectiveOf = {}, rewardOf = I(id, "questRewards") or {}, vendors = I(id, "vendors") or {},
                containers = I(id, "itemDrops") or {}, objects = #(I(id, "objectDrops") or {}) }
    u.vendorCount = #u.vendors
    local s = I(id, "startQuest")
    if s and s ~= 0 then u.starts = s end
    local seen = {}
    for _, q in ipairs(idx.itemFor and idx.itemFor[id] or {}) do
        if not seen[q] then seen[q] = true; u.objectiveOf[#u.objectiveOf + 1] = q end
    end
    if not idx.ready then
        for _, q in ipairs(I(id, "relatedQuests") or {}) do
            if not seen[q] then seen[q] = true; u.objectiveOf[#u.objectiveOf + 1] = q end
        end
    end
    return u
end

------------------------------------------------------------------------------
-- Quests
------------------------------------------------------------------------------

local questCache = {}

function SB.GetQuest(id)
    id = tonumber(id)
    if not id then return nil end
    local c = questCache[id]
    if c ~= nil then return c or nil end
    local name = Q(id, "name")
    if not name then questCache[id] = false return nil end
    local o = Q(id, "objectives") or {}
    local kill, items = {}, {}
    for _, cr in ipairs(o[1] or {}) do if cr[1] then kill[#kill + 1] = cr[1] end end
    for _, kc in ipairs(o[5] or {}) do
        for _, cr in ipairs(kc[1] or {}) do kill[#kill + 1] = cr end
        if kc[2] then kill[#kill + 1] = kc[2] end
    end
    for _, it in ipairs(o[3] or {}) do if it[1] then items[#items + 1] = it[1] end end
    local sb, fb = Q(id, "startedBy") or {}, Q(id, "finishedBy") or {}
    local text = table.concat(Q(id, "objectivesText") or {}, " ")
    c = { id = id, name = name, level = Q(id, "questLevel") or 0, reqLevel = Q(id, "requiredLevel") or 0,
          races = Q(id, "requiredRaces") or 0, classMask = Q(id, "requiredClasses") or 0, text = text,
          starters = sb[1] or {}, enders = fb[1] or {}, startItems = sb[3] or {}, kill = kill, items = items,
          sourceItems = Q(id, "requiredSourceItems") or {} }
    questCache[id] = c
    return c
end

-- A quest's full description, as the quest giver says it, with $N/$C/$R/$B/$G filled in for you.
function SB.QuestText(id)
    local raw = D.qtext and D.qtext[id]
    if not raw then return nil end
    local name = UnitName and UnitName("player") or "you"
    local class = UnitClass and UnitClass("player") or "adventurer"
    local race = UnitRace and UnitRace("player") or "adventurer"
    local female = UnitSex and UnitSex("player") == 3
    raw = raw:gsub("%$[Gg]([^:;]*):([^;]*);", function(male, fem) return female and fem or male end)
    raw = raw:gsub("%$[Bb]", "\n"):gsub("%$[Nn]", name):gsub("%$[Cc]", class:lower()):gsub("%$[Rr]", race:lower())
    raw = raw:gsub("\n\n+", "\n\n")
    return raw
end

-- How many of each item / mob / object a quest needs: { items = {[id]=n}, kills = {[id]=n}, objects = {[id]=n} }
function SB.QuestCounts(id)
    local out = { items = {}, kills = {}, objects = {} }
    for kind, target, n in ((D.qcount and D.qcount[id]) or ""):gmatch("(%a)(%d+)x(%d+)") do
        local t = kind == "i" and out.items or kind == "c" and out.kills or out.objects
        t[tonumber(target)] = tonumber(n)
    end
    return out
end

-- Experience for a quest at your level. Quests far below you give less: from 6 levels above the
-- quest it drops to 80, 60, 40, 20 and then 10 percent, rounded like the game does.
local function ReduceXP(xp, questLevel, playerLevel)
    local diff = playerLevel - questLevel
    local f = diff <= 5 and 1 or diff == 6 and 0.8 or diff == 7 and 0.6 or diff == 8 and 0.4 or diff == 9 and 0.2 or 0.1
    if f == 1 then return xp end
    xp = xp * f
    local step = xp > 1000 and 50 or xp > 500 and 25 or xp > 100 and 10 or 5
    return math.floor(xp / step + 0.5) * step
end
SB.ReduceXP = ReduceXP

-- What a quest gives: { choices = {{item, count}}, items = {{item, count}}, money, moneyMax,
-- xp (full), xpYou (at your level, nil at max level), rep = {{faction, value}} }
function SB.QuestRewards(id)
    local r = { choices = {}, items = {}, rep = {} }
    local seen = {}
    for kind, a, b in ((D.qreward and D.qreward[id]) or ""):gmatch("(%a)(%d+)x?:?(%-?%d*)") do
        a, b = tonumber(a), tonumber(b)
        if kind == "c" then r.choices[#r.choices + 1] = { a, b or 1 }; seen[a] = true
        elseif kind == "r" then r.items[#r.items + 1] = { a, b or 1 }; seen[a] = true
        elseif kind == "m" then r.money = a
        elseif kind == "M" then r.moneyMax = a
        elseif kind == "f" then r.rep[#r.rep + 1] = { a, b } end
    end
    -- reward items Forever's data lists that the Classic table doesn't
    for _, item in ipairs(idx.rewards and idx.rewards[id] or {}) do
        if not seen[item] then seen[item] = true; r.items[#r.items + 1] = { item, 1 } end
    end
    -- reputation: Forever's own values win over the Classic ones
    local live = Q(id, "reputationReward")
    if type(live) == "table" and #live > 0 then
        r.rep = {}
        for _, p in ipairs(live) do if p[1] and p[2] then r.rep[#r.rep + 1] = { p[1], p[2] } end end
    end
    -- experience from QuestieDB's quest XP table
    SB.QDB()
    local xpdb = LQ and LQ.Support and LQ.Support.Get and select(2, pcall(LQ.Support.Get, "QuestXP"))
    local e = type(xpdb) == "table" and type(xpdb.db) == "table" and xpdb.db[id]
    if type(e) == "table" and (e[2] or 0) > 0 then
        r.xp = e[2]
        local level = UnitLevel("player") or 1
        local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
        if level < max then r.xpYou = ReduceXP(e[2], e[1] or 0, level) end
    end
    return r
end

-- A faction's name, from the game.
function SB.FactionName(id)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
        if ok and type(d) == "table" and d.name then return d.name end
    end
    if GetFactionInfoByID then
        local ok, name = pcall(GetFactionInfoByID, id)
        if ok and name then return name end
    end
    return "Faction " .. id
end

-- true when masks a and b share a bit (works above 32 bits, unlike bit.band)
local function Overlap(a, b)
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then return true end
        a, b = math.floor(a / 2), math.floor(b / 2)
    end
    return false
end

function SB.QuestForMe(q)
    if not q then return false end
    if q.races and q.races > 0 then
        local fac = UnitFactionGroup and UnitFactionGroup("player")
        local masks = LQ and LQ.Enum and LQ.Enum.factionRaceMasks
        local mask = masks and masks[fac] or (fac == "Alliance" and (77 + 2 ^ 32) or (178 + 2 ^ 33))
        if not Overlap(q.races, mask) then return false end
    end
    if q.classMask and q.classMask > 0 then
        local classId = select(3, UnitClass("player"))
        if classId and not Overlap(q.classMask, 2 ^ (classId - 1)) then return false end
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
-- Instances
------------------------------------------------------------------------------

local instanceCache = {}

function SB.NpcsInAreas(areas)
    local seen, out = {}, {}
    for area in pairs(areas or {}) do
        for _, id in ipairs(idx.npcsInArea and idx.npcsInArea[area] or {}) do
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

-- { map, area, name, raid, mobs, bosses, minLevel, maxLevel, art = Adventure Guide data }
function SB.GetInstance(mapID)
    local cached = instanceCache[mapID]
    if cached and (cached.ready or not idx.ready) then return cached end
    local areas, area = SB.InstanceAreas(mapID)
    if not areas then return nil end
    local art = SB.Skin and SB.Skin.InstanceArt(mapID)
    local inst = { map = mapID, area = area, name = (art and art.name) or SB.ZoneName(area), art = art,
                   raid = art and art.raid or SB.RAID_MAPS[mapID] or false, mobs = SB.NpcsInAreas(areas), bosses = {} }
    local lo, hi = 999, 0
    for _, id in ipairs(inst.mobs) do
        local n = SB.GetNpc(id)
        if n.boss then inst.bosses[#inst.bosses + 1] = id end
        if not n.friendly and n.minLevel > 1 and n.rank ~= 3 then
            lo, hi = math.min(lo, n.minLevel), math.max(hi, n.maxLevel)
        end
    end
    if hi > 0 then inst.minLevel, inst.maxLevel = lo, hi end
    inst.ready = idx.ready
    instanceCache[mapID] = inst
    return inst
end

function SB.Instances(raid)
    local out = {}
    for mapID in pairs(InstanceAreaTable()) do
        local inst = SB.GetInstance(mapID)
        if inst and (inst.raid and true or false) == (raid and true or false) and #inst.mobs > 0 then
            out[#out + 1] = inst
        end
    end
    table.sort(out, function(a, b)
        if (a.minLevel or 99) ~= (b.minLevel or 99) then return (a.minLevel or 99) < (b.minLevel or 99) end
        return a.name < b.name
    end)
    return out
end

------------------------------------------------------------------------------
-- Search
------------------------------------------------------------------------------

local npcNames, itemNames
local function Names(entity, getter)
    local t = {}
    for _, id in ipairs(AllIds(entity)) do
        local name = getter(id)
        if type(name) == "string" then t[id] = name:lower() end
    end
    return t
end

function SB.Search(text, limit)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    limit = limit or 150
    if text == "" then return {} end
    SB.QDB()
    npcNames = npcNames or Names(NpcDB, function(id) return N(id, "name") end)
    itemNames = itemNames or Names(ItemDB, function(id) return I(id, "name") end)
    -- mobs you've seen that the database doesn't have
    for id, m in pairs(SB.db and SB.db.mobs or {}) do
        if m.name and not npcNames[id] then npcNames[id] = m.name:lower() end
    end
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
    -- an item ID the database doesn't know, but the client does (new in Forever)
    if asId and not itemNames[asId] and GameItemInfo(asId) then
        results[#results + 1] = { kind = "item", id = asId, score = 0, name = GameItemInfo(asId):lower() }
    end
    -- items crafted by recipes you've scanned
    for _, r in pairs(SB.db and SB.db.recipes or {}) do
        if r.o and not itemNames[r.o] and r.n and r.n:lower():find(text, 1, true) then
            results[#results + 1] = { kind = "item", id = r.o, score = 3, name = r.n:lower() }
            itemNames[r.o] = r.n:lower()
        end
    end
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

function SB.ResetCaches()
    wipe(npcCache); wipe(lootCache); wipe(itemCache); wipe(questCache); wipe(instanceCache); wipe(cmCache)
    npcNames, itemNames, uiMapOf, zoneDirectory = nil, nil, nil, nil
end

SB.OnIndexReady = function()
    wipe(lootCache); wipe(instanceCache)
    if SB.OnDataChanged then SB.OnDataChanged() end
end
