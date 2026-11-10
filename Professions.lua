-- Crafting, read from the game client. Whenever a profession window opens (yours, or a
-- profession link someone posted in chat), every recipe in it is read with the client's own
-- profession API: what it makes, the reagents, the profession, how it's learned and its skill.
-- Saved for your whole account, so any character can see who crafts what, and kept current:
-- each time a window opens the recipes are read again from the client.

local _, SB = ...
local P = {}
SB.Crafting = P

local function TS(name, ...)
    local f = C_TradeSkillUI and C_TradeSkillUI[name]
    if not f then return nil end
    local ok, a, b, c = pcall(f, ...)
    if ok then return a, b, c end
end

local function CharKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName()
    return (name or "?") .. (realm and realm ~= "" and ("-" .. realm) or "")
end

-- "Requires Tailoring (165)" / "Trainer" / "Drop: ..." -> a readable line without markup
local function Clean(text)
    text = SB.Public(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|n", "\n")
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local byItem -- item -> { recipeID, ... }

local function Index()
    byItem = {}
    for id, r in pairs(SB.db.recipes) do
        if r.o then
            byItem[r.o] = byItem[r.o] or {}
            table.insert(byItem[r.o], id)
        end
    end
end

-- Reads one recipe from the client. Returns true if it's a recipe that makes something.
function P.ReadRecipe(id, profession, mine)
    local schematic = TS("GetRecipeSchematic", id, false)
    if type(schematic) ~= "table" then return false end
    local info = TS("GetRecipeInfo", id) or {}
    local r = SB.db.recipes[id] or {}
    r.n = SB.Public(schematic.name) or info.name or r.n
    r.o = SB.Public(schematic.outputItemID) or r.o
    r.qmin, r.qmax = schematic.quantityMin or 1, schematic.quantityMax or 1
    r.icon = schematic.icon or info.icon
    r.reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        local basic = slot.reagentType == nil or slot.reagentType == 1 or (Enum and Enum.CraftingReagentType and slot.reagentType == Enum.CraftingReagentType.Basic)
        if reagent and reagent.itemID and basic then
            table.insert(r.reagents, { reagent.itemID, slot.quantityRequired or 1 })
        end
    end
    local prof = TS("GetProfessionInfoByRecipeID", id)
    if type(prof) == "table" then
        r.p = prof.parentProfessionName or prof.professionName or r.p
        r.pid = prof.parentProfessionID or prof.professionID or r.pid
    elseif profession then
        r.p = profession
    end
    if info.maxTrivialLevel and info.maxTrivialLevel > 0 then r.grey = info.maxTrivialLevel end
    local source = Clean(TS("GetRecipeSourceText", id))
    if source and source ~= "" then r.src = source end
    -- "Requires Tailoring (165)" in the source or the recipe text gives the skill
    local req = source and source:match("%((%d+)%)")
    if req then r.skill = tonumber(req) end
    r.seen = time()
    if mine then
        local known = SB.db.knownRecipes[CharKey()] or {}
        SB.db.knownRecipes[CharKey()] = known
        known[id] = info.learned and true or nil
    end
    SB.db.recipes[id] = r
    return true
end

local scanning = false
function P.Scan()
    if scanning or not C_TradeSkillUI or not SB.db then return end
    scanning = true
    local ids = TS("GetAllRecipeIDs") or TS("GetFilteredRecipeIDs") or {}
    local linked = TS("IsTradeSkillLinked") or TS("IsTradeSkillGuild") or TS("IsNPCCrafting")
    local base = TS("GetBaseProfessionInfo")
    local profName = type(base) == "table" and base.professionName or nil
    local count = 0
    for _, id in ipairs(ids) do
        if P.ReadRecipe(id, profName, not linked) then count = count + 1 end
    end
    if type(base) == "table" and base.professionName and not linked then
        SB.db.professions[CharKey()] = SB.db.professions[CharKey()] or {}
        SB.db.professions[CharKey()][base.professionName] = base.skillLevel
    end
    Index()
    scanning = false
    if count > 0 and SB.OnDataChanged then SB.OnDataChanged() end
    return count
end

local pending
local function Later()
    if pending then return end
    pending = true
    SB.After(0.5, function() pending = false; P.Scan() end)
end
SB.On("TRADE_SKILL_SHOW", Later)
SB.On("TRADE_SKILL_LIST_UPDATE", Later)
SB.On("TRADE_SKILL_DATA_SOURCE_CHANGED", Later)

SB.AddLoad(function()
    SB.db.recipes = SB.db.recipes or {}
    SB.db.knownRecipes = SB.db.knownRecipes or {}
    SB.db.professions = SB.db.professions or {}
end)

-- Recipes that make this item: { {id=, name, profession, skill, grey, source, reagents = {{item, count}}, qmin, qmax, known = {characters}} }
function P.ForItem(item)
    if not byItem then Index() end
    local out = {}
    for _, id in ipairs(byItem[item] or {}) do
        local r = SB.db.recipes[id]
        local known = {}
        for char, list in pairs(SB.db.knownRecipes) do if list[id] then known[#known + 1] = char end end
        table.sort(known)
        out[#out + 1] = { id = id, name = r.n, profession = r.p, skill = r.skill, grey = r.grey, source = r.src,
                          reagents = r.reagents or {}, qmin = r.qmin, qmax = r.qmax, icon = r.icon, known = known }
    end
    table.sort(out, function(a, b) return (a.skill or 0) < (b.skill or 0) end)
    return out
end

-- Recipes that use this item as a reagent: { {id=, name, profession, output, count} }
function P.UsedIn(item)
    local out = {}
    for id, r in pairs(SB.db.recipes) do
        for _, rg in ipairs(r.reagents or {}) do
            if rg[1] == item then
                out[#out + 1] = { id = id, name = r.n, profession = r.p, output = r.o, count = rg[2] }
                break
            end
        end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

function P.Count()
    local n = 0
    for _ in pairs(SB.db.recipes) do n = n + 1 end
    return n
end
