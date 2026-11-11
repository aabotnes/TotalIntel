-- The bundled snapshot of QuestieDB's WoW: Forever data (Data/Forever*.lua), served through the
-- same interface as the live LibQuestieDB addon. Total Intel uses it only when no live Questie
-- database is installed, so the addon works on its own and still follows a live one when present.

local _, SB = ...
local D = SB.D
local Fields, List = SB.Fields, SB.List

local function Ids(s)
    if not s or s == "" then return nil end
    local out = {}
    for v in s:gmatch("%d+") do out[#out + 1] = tonumber(v) end
    return out
end

local function Num(s)
    local n = tonumber(s)
    return n
end

local decode = {}

function decode.npc(raw)
    local f = Fields(raw)
    local spawns
    for _, z in ipairs(List(f[6])) do
        local area, x, y, count = strsplit(":", z)
        spawns = spawns or {}
        local pts = {}
        if tonumber(x) then pts[1] = { tonumber(x), tonumber(y) } end
        pts.count = tonumber(count) or #pts   -- the snapshot keeps one central point per zone
        spawns[tonumber(area)] = pts
    end
    return { name = f[1], subName = f[2] ~= "" and f[2] or nil, minLevel = Num(f[3]) or 0, maxLevel = Num(f[4]) or 0,
             rank = Num(f[5]) or 0, spawns = spawns, zoneID = Num(f[7]) or 0,
             friendlyToFaction = f[8] ~= "" and f[8] or nil, questStarts = Ids(f[9]), questEnds = Ids(f[10]),
             npcFlags = Num(f[11]) or 0 }
end

function decode.item(raw)
    local f = Fields(raw)
    local objects
    local count = Num(f[9]) or 0
    if count > 0 then
        objects = {}
        for i = 1, count do objects[i] = 0 end   -- only the count is kept
    end
    return { name = f[1], itemLevel = Num(f[2]) or 0, requiredLevel = Num(f[3]) or 0, class = Num(f[4]) or 0,
             subClass = Num(f[5]) or 0, npcDrops = Ids(f[6]), vendors = Ids(f[7]), itemDrops = Ids(f[8]),
             objectDrops = objects, startQuest = Num(f[10]) or 0, questRewards = Ids(f[11]) }
end

local function Pairs(s)
    if not s or s == "" then return nil end
    local out = {}
    for a, b in s:gmatch("(%-?%d+):(%-?%d+)") do out[#out + 1] = { tonumber(a), tonumber(b) } end
    return out
end

function decode.quest(raw)
    local f = Fields(raw)
    local function Wrap(ids)
        if not ids then return nil end
        local out = {}
        for i, id in ipairs(ids) do out[i] = { id } end
        return out
    end
    return { name = f[1], questLevel = Num(f[2]) or 0, requiredLevel = Num(f[3]) or 0, requiredRaces = Num(f[4]) or 0,
             requiredClasses = Num(f[5]) or 0, objectivesText = f[6] ~= "" and { f[6] } or nil,
             startedBy = { Ids(f[7]), nil, Ids(f[8]) }, finishedBy = { Ids(f[9]) },
             objectives = { Wrap(Ids(f[10])), nil, Wrap(Ids(f[11])) }, requiredSourceItems = Ids(f[12]),
             reputationReward = Pairs(f[13]) }
end

-- Records are decoded when asked for. Only a few hundred stay decoded at a time, so walking the
-- whole database (the index, search) doesn't keep 30,000 tables in memory.
local function Entity(raw, dec)
    local cache, cached, ids = {}, 0, nil
    local e = {}
    function e.Get(id, key)
        local s = raw[id]
        if not s then return nil end
        if key == "name" then return s:match("^([^^]*)") end
        local r = cache[id]
        if not r then
            if cached > 400 then cache, cached = {}, 0 end
            r = dec(s)
            cache[id] = r
            cached = cached + 1
        end
        return r[key]
    end
    function e.GetAllIds()
        if not ids then
            ids = {}
            for id in pairs(raw) do ids[#ids + 1] = id end
            table.sort(ids)
        end
        return ids
    end
    return e
end

local provider
function SB.Bundled()
    if provider ~= nil then return provider or nil end
    if not (D.fnpc and D.fitem and D.fquest) then provider = false return nil end

    local dungeons = {}
    for area, s in pairs(D.fdungeon or {}) do
        local name, alts = s:match("^(.-)|(.*)$")
        dungeons[area] = { name, Ids(alts) }
    end
    -- item -> { [npc] = percent }, parsed when first asked for
    local rates = setmetatable({}, { __index = function(t, item)
        local s = D.frate and D.frate[item]
        if not s then return nil end
        local per = {}
        for npc, pct in s:gmatch("(%d+):([%d.]+)") do per[tonumber(npc)] = tonumber(pct) end
        rawset(t, item, per)
        return per
    end })
    -- quest -> { questLevel, xp }, parsed when first asked for
    local questXP = setmetatable({}, { __index = function(t, quest)
        local s = D.fqxp and D.fqxp[quest]
        if not s then return nil end
        local level, xp = s:match("^(%d+):(%d+)$")
        local v = { tonumber(level), tonumber(xp) }
        rawset(t, quest, v)
        return v
    end })
    local zoneDB = { instanceIdToAreaId = D.finstance or {}, names = D.fzoneName or {},
                     private = { areaIdToUiMapId = D.fuiMap or {}, dungeons = dungeons } }

    provider = {
        Npc = Entity(D.fnpc, decode.npc),
        Item = Entity(D.fitem, decode.item),
        Quest = Entity(D.fquest, decode.quest),
        Enum = {
            npcFlags = { VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, REPAIR = 16384 },
            factionRaceMasks = { Alliance = 77 + 2 ^ 32, Horde = 178 + 2 ^ 33 },
        },
        Support = { Get = function(name)
            if name == "ZoneDB" then return zoneDB end
            if name == "QuestieClassicItemDrops" then return { wowheadData = rates } end
            if name == "QuestXP" then return { db = questXP } end
        end },
        info = D.finfo,
    }
    return provider
end
