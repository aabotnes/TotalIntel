-- A tiny stand-in for the QuestieDB addon (LibQuestieDB), with real Forever records copied from
-- QuestieDB's data, so the tests exercise the same public API the addon uses in the game.
local F = {}

local npcs = {
    [448] = { name = "Hogger", minLevel = 11, maxLevel = 11, rank = 1, zoneID = 12,
              spawns = { [12] = { { 25.8, 89.8 }, { 26.4, 90.1 }, { 24.9, 88.7 }, { 25.5, 92.0 }, { 27.0, 90.6 } } } },
    [11502] = { name = "Ragnaros", minLevel = 63, maxLevel = 63, rank = 3 },
    [639] = { name = "Edwin VanCleef", subName = "Defias Kingpin", minLevel = 21, maxLevel = 21, rank = 1,
              spawns = { [1581] = { { 0, 0 } } }, zoneID = 1581 },
    [644] = { name = "Rhahk'Zor", minLevel = 19, maxLevel = 19, rank = 1, spawns = { [1581] = { { 0, 0 } } }, zoneID = 1581 },
    [636] = { name = "Defias Blackguard", minLevel = 16, maxLevel = 17, rank = 1, spawns = { [1581] = { { 0, 0 } } }, zoneID = 1581 },
    [240] = { name = "Marshal Dughan", minLevel = 25, maxLevel = 25, rank = 1, friendlyToFaction = "A", npcFlags = 2,
              questStarts = { 176 }, questEnds = { 176 }, spawns = { [12] = { { 42.1, 65.9 } } } },
    [38] = { name = "Defias Thug", minLevel = 3, maxLevel = 4, spawns = { [12] = { { 54.0, 47.0 } } } },
}
local vendors = {}
for i = 1, 35 do
    local id = 90000 + i
    npcs[id] = { name = "Reagent Vendor " .. i, minLevel = 30, maxLevel = 30, npcFlags = 4, spawns = { [1519] = { { 50, 50 } } } }
    vendors[i] = id
end
local items = {
    [1931] = { name = "Huge Gnoll Claw", npcDrops = { 448 }, class = 12, itemLevel = 1 },
    [17076] = { name = "Bonereaver's Edge", npcDrops = { 11502 }, itemLevel = 77, requiredLevel = 60, class = 2 },
    [2589] = { name = "Linen Cloth", npcDrops = { 448, 38 }, class = 7, itemLevel = 5 },
    [17033] = { name = "Symbol of Divinity", vendors = vendors, itemLevel = 30, class = 15 },
    [4306] = { name = "Silk Cloth", class = 7, itemLevel = 26 },
}
local quests = {
    [176] = { name = "Wanted:  \"Hogger\"", questLevel = 11, requiredLevel = 5, requiredRaces = 77 + 2 ^ 32,
              startedBy = { nil, { 68 } }, finishedBy = { { 240 } }, objectives = { nil, nil, { { 1931 } } },
              objectivesText = { "Slay the gnoll Hogger and bring his Huge Gnoll Claw to Marshal Dughan." } },
}

local function Entity(rows, numeric)
    local e = {}
    function e.Get(id, key)
        local r = rows[id]
        if not r then return nil end
        local v = r[key]
        if v == nil and numeric[key] then return 0 end
        return v
    end
    function e.GetAllIds()
        local ids = {}
        for id in pairs(rows) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end
    for key in pairs(numeric) do e[key] = function(id) return e.Get(id, key) end end
    e.name = function(id) return e.Get(id, "name") end
    return e
end

LibQuestieDB = {
    contractVersion = 4, minSupportedContract = 1,
    RequireContract = function(v) return v >= 1 and v <= 4 end,
    Npc = Entity(npcs, { minLevel = true, maxLevel = true, rank = true, zoneID = true, npcFlags = true }),
    Item = Entity(items, { itemLevel = true, requiredLevel = true, class = true, subClass = true, startQuest = true }),
    Quest = Entity(quests, { questLevel = true, requiredLevel = true, requiredRaces = true, requiredClasses = true }),
    Enum = {
        factionRaceMasks = { Alliance = 77 + 2 ^ 32, Horde = 178 + 2 ^ 33 },
        npcFlags = { VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, REPAIR = 16384, QUEST_GIVER = 2 },
    },
    Support = {
        Get = function(name)
            if name == "ZoneDB" then
                return {
                    instanceIdToAreaId = { [36] = 1581, [409] = 2717 },
                    private = {
                        areaIdToUiMapId = "return { [12] = 1429, [1581] = 291, [2717] = 232, [1519] = 1453 }",
                        dungeons = { [1581] = { "The Deadmines", { 10029 }, 40, {} }, [2717] = { "Molten Core", nil, 46, {} } },
                    },
                }
            elseif name == "QuestieClassicItemDrops" then
                return { wowheadData = "return { [1931] = { [448] = 98.5 } }" }
            end
        end,
    },
}

return F
