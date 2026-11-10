-- The "bestiary" part: what you've seen yourself. Kills, corpses looted, the items you got (so
-- you have your own Forever drop rates next to the Classic numbers), skinning/pickpocket loot,
-- and spells you've seen each mob cast. Saved account-wide in TotalIntelDB.mobs.

local _, SB = ...
local Public, NpcIdFromGUID = SB.Public, SB.NpcIdFromGUID

local MAX_RECENT = 60
local recentGUIDs = { kills = {}, loot = {}, casts = {} } -- guid -> time, so nothing counts twice

local function Remember(set, key)
    if not key then return false end
    if set[key] then return false end
    set[key] = GetTime()
    return true
end

-- old GUIDs are forgotten after 15 minutes
local function Prune()
    local now = GetTime()
    for _, set in pairs(recentGUIDs) do
        for k, t in pairs(set) do if now - t > 900 then set[k] = nil end end
    end
end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(300, Prune) end

function SB.Mob(id, create)
    local mobs = SB.db.mobs
    local m = mobs[id]
    if not m and create then
        m = {}
        mobs[id] = m
    end
    return m
end

local function Touch(id)
    local m = SB.Mob(id, true)
    local now = time()
    m.f = m.f or now
    m.l = now
    local zone = GetZoneText and GetZoneText()
    if zone and zone ~= "" then m.z = zone end
    return m
end

local function Count(t, key, n)
    t[key] = (t[key] or 0) + (n or 1)
end

------------------------------------------------------------------------------
-- Seen / recent
------------------------------------------------------------------------------

function SB.AddRecent(id)
    local r = SB.db.recent
    for i = #r, 1, -1 do if r[i] == id then table.remove(r, i) end end
    table.insert(r, 1, id)
    for i = #r, MAX_RECENT + 1, -1 do r[i] = nil end
end

-- The quests the game itself attaches to this unit (its tooltip's quest lines carry quest IDs).
-- This is the client's own answer, so it covers Forever-only quests too.
local QUEST_TITLE = 17
local function LearnQuests(unit, m)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return end
    local questType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or QUEST_TITLE
    for _, line in ipairs(data.lines) do
        local kind = Public(line.type)
        local id = Public(line.id)
        if kind == questType and type(id) == "number" and id > 0 then
            m.q = m.q or {}
            m.q[id] = true
        end
    end
end
SB.LearnQuests = LearnQuests

local function SeeUnit(unit, recent)
    if not SB.db or not SB.db.learn then return end
    local id = SB.UnitNpcId(unit)
    if not id then return end
    if UnitIsPlayer(unit) or (UnitPlayerControlled and UnitPlayerControlled(unit)) then return end
    local m = Touch(id)
    -- remember its name and level for mobs the database doesn't know
    local name = SB.Public(UnitName(unit))
    if name then m.name = name end
    local lv = SB.Public(UnitLevel(unit))
    if lv and lv > 0 then m.lv = lv end
    if SB.ForgetNpc then SB.ForgetNpc(id) end
    LearnQuests(unit, m)
    if recent then
        SB.AddRecent(id)
        SB.lastTarget = id
        if SB.OnTargetChanged then SB.OnTargetChanged(id) end
    end
end

SB.On("PLAYER_TARGET_CHANGED", function() SeeUnit("target", true) end)
SB.On("UPDATE_MOUSEOVER_UNIT", function() SeeUnit("mouseover", false) end)

------------------------------------------------------------------------------
-- Spells mobs cast (unit events work without the combat log)
------------------------------------------------------------------------------

-- Skinning, Mining, Herb Gathering (rank 1 IDs; matched by name so every rank counts)
local GATHER_SPELLS = { 8613, 2575, 2366, 2656 }
local gatherNames
local function IsGathering(spellID)
    if not gatherNames then
        gatherNames = {}
        for _, id in ipairs(GATHER_SPELLS) do
            local name = SB.SpellInfo(id)
            if name then gatherNames[name] = true end
        end
    end
    local name = SB.SpellInfo(spellID)
    return name and gatherNames[name]
end
SB.lastGather = 0

local function OnCast(unit, castGUID, spellID)
    if not SB.db or not SB.db.learn or not unit then return end
    spellID = Public(spellID)
    if unit == "player" and spellID and IsGathering(spellID) then SB.lastGather = GetTime() end
    if not spellID or unit == "player" or unit:find("^party") or unit:find("^raid") or unit == "pet" then return end
    local id = SB.UnitNpcId(unit)
    if not id then return end
    if UnitIsPlayer(unit) or (UnitPlayerControlled and UnitPlayerControlled(unit)) then return end
    castGUID = Public(castGUID)
    if castGUID and not Remember(recentGUIDs.casts, castGUID) then return end
    local m = Touch(id)
    m.s = m.s or {}
    Count(m.s, spellID)
end

SB.On("UNIT_SPELLCAST_START", OnCast)
SB.On("UNIT_SPELLCAST_CHANNEL_START", OnCast)
SB.On("UNIT_SPELLCAST_SUCCEEDED", OnCast)

------------------------------------------------------------------------------
-- Kills
------------------------------------------------------------------------------

local function AddKill(guid)
    local id = NpcIdFromGUID(guid)
    if not id or not Remember(recentGUIDs.kills, guid) then return end
    local m = Touch(id)
    m.k = (m.k or 0) + 1
    if SB.OnMobChanged then SB.OnMobChanged(id) end
end
SB.AddKill = AddKill

-- WoW: Forever restricts the combat log (COMBAT_LOG_EVENT_UNFILTERED) to Blizzard's own UI;
-- registering it pops up "blocked from an action only available to the Blizzard UI". So kills
-- are counted from what addons may see: a mob you fought dying on your target or nameplates,
-- and looting its corpse.
-- A mob you (or your group) tagged is seen dead.
local function CheckDead(unit)
    if not SB.db or not SB.db.learn or not UnitExists(unit) then return end
    if not UnitIsDead(unit) or UnitIsPlayer(unit) then return end
    if UnitIsTapDenied and UnitIsTapDenied(unit) then return end
    if UnitCanAttack and not UnitCanAttack("player", unit) then return end
    local ok, guid = pcall(UnitGUID, unit)
    if ok then
        guid = Public(guid)
        -- only count a death we saw happen while it was our target or on a nameplate in combat
        if guid and SB.engaged and SB.engaged[guid] then AddKill(guid) end
    end
end

SB.engaged = {}
SB.On("UNIT_HEALTH", function(unit)
    if not unit or not (unit == "target" or unit:find("^nameplate")) then return end
    local ok, guid = pcall(UnitGUID, unit)
    guid = ok and Public(guid)
    if not guid then return end
    if not UnitIsDead(unit) then
        if UnitAffectingCombat and UnitAffectingCombat(unit) then SB.engaged[guid] = GetTime() end
        return
    end
    CheckDead(unit)
end)

------------------------------------------------------------------------------
-- Loot
------------------------------------------------------------------------------

local function ItemIdFromLink(link)
    link = Public(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function OnLoot()
    if not SB.db or not SB.db.learn or not GetNumLootItems then return end
    local stealthed = IsStealthed and IsStealthed()
    local corpses, got = {}, {}
    for slot = 1, GetNumLootItems() do
        local item = GetLootSlotLink and ItemIdFromLink(GetLootSlotLink(slot))
        local _, _, qty = GetLootSlotInfo(slot)
        qty = Public(qty) or 1
        local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
        for i = 1, #sources, 2 do
            local guid = Public(sources[i])
            local id = NpcIdFromGUID(guid)
            if id then
                corpses[guid] = id
                if item then
                    got[guid] = got[guid] or {}
                    got[guid][item] = (got[guid][item] or 0) + (Public(sources[i + 1]) or qty)
                end
            end
        end
    end
    for guid, id in pairs(corpses) do
        local m = Touch(id)
        local items = got[guid] or {}
        if stealthed and not recentGUIDs.loot[guid] then
            -- pickpocketing a living mob
            m.p = m.p or {}
            m.pc = (m.pc or 0) + 1
            for item, n in pairs(items) do Count(m.p, item, n) end
        elseif Remember(recentGUIDs.loot, guid) then
            m.c = (m.c or 0) + 1
            m.i = m.i or {}
            for item, n in pairs(items) do Count(m.i, item, n) end
            -- looting a corpse proves a kill when the combat log couldn't tell us
            if not recentGUIDs.kills[guid] then AddKill(guid) end
        elseif GetTime() - SB.lastGather < 5 then
            -- a loot window right after skinning / mining / herbing the corpse
            SB.lastGather = 0
            m.g = m.g or {}
            for item, n in pairs(items) do Count(m.g, item, n) end
            recentGUIDs.loot[guid] = GetTime()
        end
        if SB.OnMobChanged then SB.OnMobChanged(id) end
    end
end

-- LOOT_READY fires once per loot window on modern clients; LOOT_OPENED is the older event.
-- Remember() above keeps a corpse from counting twice when both fire.
local lootHandled = 0
SB.On("LOOT_READY", function() lootHandled = GetTime(); OnLoot() end)
SB.On("LOOT_OPENED", function() if GetTime() - lootHandled > 0.5 then OnLoot() end end)

------------------------------------------------------------------------------
-- Queries for the tooltip and window
------------------------------------------------------------------------------

-- Your loot counts for an item from this mob: count, corpses
function SB.YourDrop(npcId, itemId)
    local m = SB.db.mobs[npcId]
    if not m or not m.c or m.c == 0 then return nil end
    return (m.i and m.i[itemId]) or 0, m.c
end

-- Every mob you've looted this item from: { {npc=, count=, corpses=} } most first
function SB.YourItemSources(itemId)
    local out = {}
    for id, m in pairs(SB.db.mobs) do
        local n = (m.i and m.i[itemId]) or 0
        if n > 0 then out[#out + 1] = { npc = id, count = n, corpses = m.c or 0 } end
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end
