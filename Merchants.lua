-- Vendors and trainers, read from the game when you open their window: what a vendor sells
-- (with prices and limited stock) and what a trainer teaches (with level, skill and cost).
-- Saved for your whole account and refreshed on every visit, so it follows Forever's patches.

local _, SB = ...
local Public = SB.Public

local function Try(f, ...)
    if not f then return nil end
    local ok, a, b, c, d, e, g, h = pcall(f, ...)
    if ok then return a, b, c, d, e, g, h end
end

------------------------------------------------------------------------------
-- Merchants
------------------------------------------------------------------------------

local function ReadMerchant()
    if not SB.db or not GetMerchantNumItems then return end
    local npc = SB.UnitNpcId("npc")
    if not npc then return end
    local items = {}
    for i = 1, Try(GetMerchantNumItems) or 0 do
        local id = Public(Try(GetMerchantItemID, i))
        if not id then
            local link = Public(Try(GetMerchantItemLink, i))
            id = link and tonumber(link:match("item:(%d+)"))
        end
        if id then
            local price, stack, available
            local info = C_MerchantFrame and Try(C_MerchantFrame.GetItemInfo, i)
            if type(info) == "table" then
                price, stack, available = info.price, info.stackCount, info.numAvailable
            else
                local _, _, p, q, n = Try(GetMerchantItemInfo, i)
                price, stack, available = p, q, n
            end
            items[#items + 1] = { item = id, price = Public(price), stack = Public(stack),
                                  limited = (Public(available) or -1) >= 0 or nil }
        end
    end
    if #items > 0 then
        SB.db.vendors[npc] = { items = items, t = time() }
        if SB.OnMobChanged then SB.OnMobChanged(npc) end
    end
end

------------------------------------------------------------------------------
-- Trainers
------------------------------------------------------------------------------

local FILTERS = { "available", "unavailable", "used" }
local reading, lastRead = false, -10

local function ReadTrainer()
    if reading or not SB.db or not GetNumTrainerServices then return end
    -- changing the filters below fires TRAINER_UPDATE again; don't read twice in a row
    if GetTime() - lastRead < 2 then return end
    local npc = SB.UnitNpcId("npc")
    if not npc then return end
    reading = true
    -- show every service while reading (the trainer window's filters hide some), then put them back
    local saved = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, f in ipairs(FILTERS) do
            saved[f] = Try(GetTrainerServiceTypeFilter, f)
            if not saved[f] then Try(SetTrainerServiceTypeFilter, f, 1) end
        end
    end
    local list = {}
    for i = 1, Try(GetNumTrainerServices) or 0 do
        local name, rank, category = Try(GetTrainerServiceInfo, i)
        if name and category ~= "header" then
            local e = { name = Public(name), rank = Public(rank) ~= "" and Public(rank) or nil }
            if Public(category) == "used" then e.used = true end
            e.cost = Public(Try(GetTrainerServiceCost, i))
            e.level = Public(Try(GetTrainerServiceLevelReq, i))
            local skillName, skillRank = Try(GetTrainerServiceSkillReq, i)
            if Public(skillName) and Public(skillName) ~= "" then e.skillName, e.skill = Public(skillName), Public(skillRank) end
            e.icon = Public(Try(GetTrainerServiceIcon, i))
            local data = C_TooltipInfo and Try(C_TooltipInfo.GetTrainerService, i)
            if type(data) == "table" then e.spell = Public(data.id) end
            local link = GetTrainerServiceItemLink and Public(Try(GetTrainerServiceItemLink, i))
            if link then e.item = tonumber(link:match("item:(%d+)")) end
            list[#list + 1] = e
        end
    end
    for f, v in pairs(saved) do if not v then Try(SetTrainerServiceTypeFilter, f, 0) end end
    reading = false
    lastRead = GetTime()
    if #list > 0 then
        SB.db.trainers[npc] = { list = list, t = time() }
        if SB.OnMobChanged then SB.OnMobChanged(npc) end
    end
end

local function Later(fn)
    local pending
    return function()
        if pending then return end
        pending = true
        SB.After(0.3, function() pending = false; fn() end)
    end
end

SB.On("MERCHANT_SHOW", Later(ReadMerchant))
SB.On("MERCHANT_UPDATE", Later(ReadMerchant))
SB.On("TRAINER_SHOW", Later(ReadTrainer))
SB.On("TRAINER_UPDATE", Later(ReadTrainer))

SB.AddLoad(function()
    SB.db.vendors = SB.db.vendors or {}
    SB.db.trainers = SB.db.trainers or {}
end)

SB.ReadMerchant, SB.ReadTrainer = ReadMerchant, ReadTrainer

------------------------------------------------------------------------------
-- Your skills (for "Requires Fishing 50": do you have it?)
------------------------------------------------------------------------------

-- Names for the skill lines trainers ask for, used when the game doesn't name one you lack.
SB.SKILL_NAMES = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering",
    [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning", [762] = "Riding", [633] = "Lockpicking",
    [40] = "Poisons", [142] = "Survival" }

local function Lines()
    local out = {}
    local count, info
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        count = Try(C_SkillInfo.GetNumSkillLines) or 0
        for i = 1, count do
            info = Try(C_SkillInfo.GetSkillLineInfo, i)
            if type(info) == "table" and not info.isHeader and info.name then
                out[#out + 1] = { id = info.skillID, name = info.name, rank = info.rank or 0, max = info.maxRank or 0 }
            end
        end
    elseif GetNumSkillLines and GetSkillLineInfo then
        for i = 1, Try(GetNumSkillLines) or 0 do
            local name, header, _, rank, _, _, max = Try(GetSkillLineInfo, i)
            if name and not header then out[#out + 1] = { name = name, rank = rank or 0, max = max or 0 } end
        end
    end
    return out
end

-- Your rank in a skill, by skill line ID and/or name: rank, maxRank, name. nil rank = you don't have it.
function SB.PlayerSkill(id, name)
    if id and id > 0 and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local info = Try(C_SkillInfo.GetSkillLineInfoByID, id)
        if type(info) == "table" and info.name then
            name = name or info.name
            if (info.maxRank or 0) > 0 then return info.rank or 0, info.maxRank, info.name end
        end
    end
    if id and id > 0 and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local info = Try(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
        if type(info) == "table" and (info.maxSkillLevel or 0) > 0 then
            return info.skillLevel or 0, info.maxSkillLevel, name or info.professionName
        end
        if type(info) == "table" and not name and info.professionName and info.professionName ~= "" then name = info.professionName end
    end
    name = name or (id and SB.SKILL_NAMES[id])
    for _, l in ipairs(Lines()) do
        if (id and l.id == id) or (name and l.name == name) then return l.rank, l.max, l.name end
    end
    return nil, nil, name or (id and ("Skill " .. id)) or "?"
end
