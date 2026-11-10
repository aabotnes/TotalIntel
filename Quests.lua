-- Your quest log, matched against the database: which mobs you need to kill or loot, and how far
-- along you are. Rebuilt (throttled) whenever the quest log changes.

local _, SB = ...
local Q = {}
SB.QuestLog = Q

Q.active = {}       -- questID -> { id, title, complete, objectives = { {text, type, done, have, need} } }
local byKill = {}   -- npcID  -> { quest, ... }
local byItem = {}   -- itemID -> { quest, ... }
local dirty = true

local function LogEntries()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local n = C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, n do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and info.questID > 0 then
                local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                out[#out + 1] = { id = info.questID, title = info.title, complete = complete and true or false }
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local n = GetNumQuestLogEntries() or 0
        for i = 1, n do
            local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if not isHeader and questID and questID > 0 then
                out[#out + 1] = { id = questID, title = title, complete = isComplete == 1 or isComplete == true, index = i }
            end
        end
    end
    return out
end

local function Objectives(entry)
    local list = {}
    local objs
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, res = pcall(C_QuestLog.GetQuestObjectives, entry.id)
        if ok then objs = res end
    end
    if type(objs) == "table" then
        for _, o in ipairs(objs) do
            local text = SB.Public(o.text)
            if text then
                list[#list + 1] = { text = text, type = o.type, done = o.finished and true or false,
                                    have = SB.Public(o.numFulfilled), need = SB.Public(o.numRequired) }
            end
        end
    elseif entry.index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for j = 1, GetNumQuestLeaderBoards(entry.index) or 0 do
            local text, kind, done = GetQuestLogLeaderBoard(j, entry.index)
            if text then
                local have, need = text:match("(%d+)%s*/%s*(%d+)")
                list[#list + 1] = { text = text, type = kind, done = done and true or false,
                                    have = tonumber(have), need = tonumber(need) }
            end
        end
    end
    return list
end

function Q.Rebuild()
    dirty = false
    wipe(Q.active); wipe(byKill); wipe(byItem)
    for _, entry in ipairs(LogEntries()) do
        entry.objectives = Objectives(entry)
        Q.active[entry.id] = entry
        local q = SB.GetQuest(entry.id)
        if q then
            for _, npc in ipairs(q.kill) do byKill[npc] = byKill[npc] or {}; table.insert(byKill[npc], entry) end
            for _, item in ipairs(q.items) do byItem[item] = byItem[item] or {}; table.insert(byItem[item], entry) end
        end
    end
end

local function Fresh()
    if dirty then Q.Rebuild() end
end

-- The objective of `entry` whose text mentions `name` (or the only one of that type).
local function FindObjective(entry, name, kind)
    local lname = name and name:lower()
    local candidates = {}
    for _, o in ipairs(entry.objectives) do
        if lname and o.text:lower():find(lname, 1, true) then return o end
        if o.type == kind then candidates[#candidates + 1] = o end
    end
    if #candidates == 1 then return candidates[1] end
end

function Q.ObjectiveText(o)
    if not o then return nil end
    if o.have and o.need then return ("%d/%d"):format(o.have, o.need) end
    return o.done and "done" or nil
end

-- Active quests that involve this NPC: { {entry, kind="kill"|"loot", item=, objective=, chance=} }
function Q.ForNpc(npcId, unitName)
    Fresh()
    local out, seen = {}, {}
    local n = SB.GetNpc(npcId)
    local name = n and n.name or unitName
    for _, entry in ipairs(byKill[npcId] or {}) do
        seen[entry.id] = true
        out[#out + 1] = { entry = entry, kind = "kill", objective = FindObjective(entry, name, "monster") }
    end
    for _, drop in ipairs(SB.GetLoot(npcId)) do
        for _, entry in ipairs(byItem[drop.item] or {}) do
            local key = entry.id .. ":" .. drop.item
            if not seen[key] then
                seen[key] = true
                local it = SB.GetItem(drop.item)
                out[#out + 1] = { entry = entry, kind = "loot", item = drop.item, chance = drop.chance,
                                  objective = FindObjective(entry, it.name, "item") }
            end
        end
    end
    -- quests the game itself showed on this mob's tooltip
    local m = SB.db and SB.db.mobs[npcId]
    for qid in pairs(m and m.q or {}) do
        local entry = Q.active[qid]
        if entry and not seen[qid] then
            seen[qid] = true
            local kill = FindObjective(entry, name, "monster")
            out[#out + 1] = { entry = entry, kind = kill and "kill" or "game", objective = kill }
        end
    end
    -- quests the database doesn't know (new in Forever): match "Mob slain" objectives by name,
    -- and item objectives by the names of what it drops
    if name then
        local lname = name:lower()
        for id, entry in pairs(Q.active) do
            if not seen[id] and not SB.GetQuest(id) then
                local matched = false
                for _, o in ipairs(entry.objectives) do
                    if o.type == "monster" and o.text:lower():find(lname, 1, true) then
                        out[#out + 1] = { entry = entry, kind = "kill", objective = o }
                        matched = true
                        break
                    end
                end
                if not matched then
                    for _, o in ipairs(entry.objectives) do
                        if o.type == "item" and not matched then
                            local text = o.text:lower()
                            for _, drop in ipairs(SB.GetLoot(npcId)) do
                                local it = SB.GetItem(drop.item)
                                if it.link and text:find(it.name:lower(), 1, true) then
                                    out[#out + 1] = { entry = entry, kind = "loot", item = drop.item, chance = drop.chance, objective = o }
                                    matched = true
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

-- Active quests that need this item: { {entry, objective} }
function Q.ForItem(itemId)
    Fresh()
    local out = {}
    local it = SB.GetItem(itemId)
    for _, entry in ipairs(byItem[itemId] or {}) do
        out[#out + 1] = { entry = entry, objective = FindObjective(entry, it.name, "item") }
    end
    return out
end

function Q.IsActive(id)
    Fresh()
    return Q.active[id]
end

local function MarkDirty()
    dirty = true
    if SB.OnQuestLogChanged then SB.OnQuestLogChanged() end
end
SB.On("QUEST_LOG_UPDATE", MarkDirty)
SB.On("QUEST_ACCEPTED", MarkDirty)
SB.On("QUEST_REMOVED", MarkDirty)
SB.On("QUEST_TURNED_IN", MarkDirty)
SB.On("PLAYER_ENTERING_WORLD", MarkDirty)
