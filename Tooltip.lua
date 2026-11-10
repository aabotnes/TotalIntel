-- Extra lines on mob and item tooltips. Every line can be switched on or off in the settings.
--
-- On WoW: Forever, tooltips inside dungeons and raids carry secret data (the game hides which
-- mob it is from addons), so mob tooltips there stay as they are. Open-world mobs are readable,
-- even in combat. Use /tits zone inside an instance to browse its mobs and bosses instead.

local _, SB = ...
local Public = SB.Public

local GREY, GOLD, WHITE, GREEN = { 0.6, 0.6, 0.6 }, { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.4, 1, 0.4 }
local HEADER = "|cffff9933Bestiary|r"

local function Add(tt, text, c)
    c = c or WHITE
    tt:AddLine(text, c[1], c[2], c[3], true)
end

local function AddDouble(tt, left, right, lc, rc)
    lc, rc = lc or WHITE, rc or WHITE
    tt:AddDoubleLine(left, right, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
end

local function QuestColorName(entry)
    return entry.complete and ("|cff40c040" .. entry.title .. " (done)|r") or entry.title
end

------------------------------------------------------------------------------
-- Mobs
------------------------------------------------------------------------------

function SB.AddNpcLines(tt, id, unit)
    local o = SB.db.tip
    local n = SB.GetNpc(id)
    local shown = false
    local function Header()
        if not shown then shown = true end
    end

    if o.npcId then AddDouble(tt, HEADER, "NPC " .. id, nil, GREY) Header() end

    if n and o.info then
        local parts = {}
        local cls = SB.Classification(n)
        if cls then parts[#parts + 1] = cls end
        if n.type > 0 and n.type ~= 10 then parts[#parts + 1] = SB.TYPES[n.type] end
        if n.family > 0 and SB.FAMILIES[n.family] then parts[#parts + 1] = SB.FAMILIES[n.family] end
        if n.skinnable and o.skinning then parts[#parts + 1] = "|cffd8b080Skinnable|r" end
        if n.pickpocket and o.skinning then
            local _, class = UnitClass("player")
            if class == "ROGUE" then parts[#parts + 1] = "|cffd8b080Pickpocket|r" end
        end
        if #parts > 0 then Add(tt, table.concat(parts, " · "), GREY) Header() end
    end
    if n and o.health and n.hpMax > 0 then
        local hp = n.hpMin == n.hpMax and tostring(n.hpMax) or (n.hpMin .. "-" .. n.hpMax)
        Add(tt, "Health " .. hp .. (n.mana > 0 and ("  Mana " .. n.mana) or ""), GREY)
    end
    if n and o.gold and n.goldMax > 0 then
        Add(tt, "Coin " .. SB.Money(n.goldMin) .. " - " .. SB.Money(n.goldMax), GREY)
    end

    -- your active quests that need it
    if o.quests then
        for _, r in ipairs(SB.QuestLog.ForNpc(id, unit and Public(UnitName(unit)))) do
            local prog = SB.QuestLog.ObjectiveText(r.objective)
            local done = r.objective and r.objective.done
            local what
            if r.kind == "loot" then
                what = SB.ItemText(r.item, true) .. (r.chance and (" |cffaaaaaa" .. SB.Percent(r.chance) .. "|r") or "")
            else
                what = "kill"
            end
            local left = (done and "|cff40c040" or "|cffffd100") .. QuestColorName(r.entry) .. "|r"
            AddDouble(tt, left, what .. (prog and ("  " .. prog) or ""), nil, done and GREEN or WHITE)
            Header()
        end
    end

    -- quest giver / turn-in
    if n and o.questGiver then
        for _, qid in ipairs(n.ends) do
            local active = SB.QuestLog.IsActive(qid)
            if active then
                AddDouble(tt, "|cffffd100Turn in:|r " .. active.title, active.complete and "ready" or "",
                    nil, active.complete and GREEN or GREY)
                Header()
            end
        end
        local available = 0
        local level = UnitLevel("player") or 1
        for _, qid in ipairs(n.starts) do
            local q = SB.GetQuest(qid)
            if q and not SB.QuestDone(qid) and not SB.QuestLog.IsActive(qid) and SB.QuestForMe(q) then
                if q.reqLevel <= level then
                    available = available + 1
                    if available <= 3 then
                        AddDouble(tt, "|cffffd100Quest:|r " .. q.name, "[" .. q.level .. "]", nil, GREY)
                    end
                end
            end
        end
        if available > 3 then Add(tt, "  + " .. SB.Plural(available - 3, "more quest"), GREY) end
        if available > 0 then Header() end
    end

    -- drops
    if n and o.drops then
        local list = SB.GetLoot(id)
        local count, minQ = 0, o.dropsMinQuality or 0
        local yours = SB.db.mobs[id]
        for _, d in ipairs(list) do
            if count >= (o.dropsCount or 4) then break end
            local it = SB.GetItem(d.item)
            if d.quest or (it.quality or 1) >= minQ then
                count = count + 1
                local right = d.chance and SB.Percent(d.chance) or "|cff888888drops|r"
                if d.quest then right = "|cffffd100quest|r " .. right end
                if yours and yours.c and yours.c >= 5 and o.kills then
                    local got = yours.i and yours.i[d.item] or 0
                    right = right .. ("  |cff88ccffyou %d/%d|r"):format(got, yours.c)
                end
                local icon = "|T" .. SB.ItemIcon(d.item) .. ":0|t "
                AddDouble(tt, icon .. SB.ItemText(d.item, true), right, nil, GREY)
            end
        end
        if count > 0 then Header() end
        local extra = #list - count
        if count > 0 and extra > 0 and n.worldDrops > 0 then
            Add(tt, "  + more drops and random world drops", GREY)
        end
    end

    -- abilities
    if o.abilities then
        local spells, seen = {}, {}
        for _, sid in ipairs(SB.GetSpells(id)) do
            local name, icon = SB.SpellInfo(sid)
            if name and not seen[name] then seen[name] = true; spells[#spells + 1] = { name = name, icon = icon } end
        end
        local m = SB.db.mobs[id]
        if m and m.s then
            for sid in pairs(m.s) do
                local name, icon = SB.SpellInfo(sid)
                if name and not seen[name] then seen[name] = true; spells[#spells + 1] = { name = name, icon = icon } end
            end
        end
        if #spells > 0 then
            local parts = {}
            for i = 1, math.min(#spells, o.abilitiesCount or 4) do
                parts[#parts + 1] = (spells[i].icon and ("|T" .. spells[i].icon .. ":0|t ") or "") .. spells[i].name
            end
            if #spells > #parts then parts[#parts + 1] = "+" .. (#spells - #parts) end
            Add(tt, "|cffff7070Abilities:|r " .. table.concat(parts, ", "), WHITE)
            Header()
        end
    end

    -- your history
    if o.kills then
        local m = SB.db.mobs[id]
        if m and ((m.k or 0) > 0 or (m.c or 0) > 0) then
            local parts = {}
            if (m.k or 0) > 0 then parts[#parts + 1] = SB.Plural(m.k, "kill") end
            if (m.c or 0) > 0 then parts[#parts + 1] = SB.Plural(m.c, "corpse") .. " looted" end
            Add(tt, "You: " .. table.concat(parts, ", "), { 0.53, 0.8, 1 })
            Header()
        end
    end

    if shown and o.hint then
        Add(tt, "Alt-click it or type /tits for the full page", { 0.45, 0.45, 0.45 })
    end
end

------------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------------

function SB.AddItemLines(tt, id)
    local o = SB.db.tip
    if o.itemId then AddDouble(tt, HEADER, "Item " .. id, nil, GREY) end

    if o.itemQuests then
        for _, r in ipairs(SB.QuestLog.ForItem(id)) do
            local prog = SB.QuestLog.ObjectiveText(r.objective)
            local done = r.objective and r.objective.done
            AddDouble(tt, (done and "|cff40c040" or "|cffffd100") .. "Quest: " .. QuestColorName(r.entry) .. "|r",
                prog or "", nil, done and GREEN or WHITE)
        end
        local uses = SB.GetItemUses(id)
        if uses.starts then
            local q = SB.GetQuest(uses.starts)
            local state = SB.QuestDone(uses.starts) and " |cff40c040(done)|r" or ""
            Add(tt, "|cffffd100Starts a quest:|r " .. (q and q.name or ("#" .. uses.starts)) .. state, WHITE)
        end
        -- quests not in your log that use it
        local others = 0
        for _, qid in ipairs(uses.objectiveOf) do
            if not SB.QuestLog.IsActive(qid) and not SB.QuestDone(qid) and SB.QuestForMe(SB.GetQuest(qid)) then
                others = others + 1
                if others <= 2 then
                    local q = SB.GetQuest(qid)
                    Add(tt, "Needed for: " .. (q and q.name or ("#" .. qid)), GREY)
                end
            end
        end
        if others > 2 then Add(tt, "  + " .. SB.Plural(others - 2, "more quest"), GREY) end
    end

    if o.itemCrafted ~= false then
        for i, r in ipairs(SB.Crafting.ForItem(id)) do
            if i > 2 then break end
            local text = "|cffffd100Crafted:|r " .. (r.profession or "?") .. (r.skill and (" (" .. r.skill .. ")") or "")
            local who = #r.known > 0 and (#r.known == 1 and r.known[1] or (#r.known .. " of your characters")) or nil
            AddDouble(tt, text, who and ("|cff40c040" .. who .. "|r") or "", nil, GREY)
        end
    end

    if o.itemDroppedBy then
        local total, list = SB.GetDroppedBy(id)
        local shown = 0
        for _, d in ipairs(list) do
            if shown >= (o.itemDroppedByCount or 3) then break end
            shown = shown + 1
            local n = SB.GetNpc(d.npc)
            local name = n and n.name or ("#" .. d.npc)
            local lvl = n and (" |cff888888(" .. SB.LevelText(n) .. ")|r") or ""
            AddDouble(tt, (shown == 1 and "Dropped by: " or "     ") .. name .. lvl, d.chance and SB.Percent(d.chance) or "", GREY, GREY)
        end
        if total > shown and shown > 0 then Add(tt, "     + " .. SB.Plural(total - shown, "other mob"), GREY) end
    end

    if o.itemVendors then
        local uses = SB.GetItemUses(id)
        if uses.vendorCount > 0 then
            local first = SB.GetNpc(uses.vendors[1])
            local text = first and first.name or "a vendor"
            if uses.vendorCount > 1 then text = text .. " + " .. (uses.vendorCount - 1) .. " more" end
            Add(tt, "Sold by: " .. text, GREY)
        end
    end

    if o.itemYourLoot then
        local src = SB.YourItemSources(id)
        if #src > 0 then
            local s = src[1]
            local text = ("You looted %d from %s"):format(s.count, SB.NpcName(s.npc))
            if s.corpses > 0 then text = text .. (" (%d corpses)"):format(s.corpses) end
            if #src > 1 then text = text .. " + " .. (#src - 1) .. " more" end
            Add(tt, text, { 0.53, 0.8, 1 })
        end
    end
end

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

local function Allowed(tt)
    if not SB.db or not SB.db.tip.enabled then return false end
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return false end
    if tt.IsForbidden and tt:IsForbidden() then return false end
    return SB.ModifierHeld(SB.db.tip.modifier)
end

local function OnUnit(tt, data)
    if not Allowed(tt) then return end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    unit = ok and Public(unit) or nil
    local id
    if unit then
        if UnitIsPlayer(unit) then return end
        id = SB.UnitNpcId(unit)
    end
    -- some tooltips (nameplates, world frames) carry only the GUID
    if not id and data then id = SB.NpcIdFromGUID(data.guid) end
    if not id then return end
    local okAdd, err = pcall(SB.AddNpcLines, tt, id, unit)
    if not okAdd and SB.debug then SB.Print("tooltip: " .. tostring(err)) end
end

local function OnItem(tt, data)
    if not Allowed(tt) or not SB.db.tip.itemEnabled then return end
    local id = data and Public(data.id)
    if not id then
        local ok, _, link = pcall(tt.GetItem, tt)
        link = ok and Public(link)
        id = link and tonumber(link:match("item:(%d+)"))
    end
    if not id then return end
    local okAdd, err = pcall(SB.AddItemLines, tt, id)
    if not okAdd and SB.debug then SB.Print("tooltip: " .. tostring(err)) end
end

SB.AddLoad(function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data) OnUnit(tt, data) end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data) OnItem(tt, data) end)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) OnUnit(tt) end)
        GameTooltip:HookScript("OnTooltipSetItem", function(tt) OnItem(tt) end)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt) OnItem(tt) end) end
    end
end)

-- Holding the modifier down should show the lines without moving the mouse.
SB.On("MODIFIER_STATE_CHANGED", function()
    if not SB.db or SB.db.tip.modifier == "NONE" or not GameTooltip:IsShown() then return end
    local ok, _, unit = pcall(GameTooltip.GetUnit, GameTooltip)
    unit = ok and Public(unit)
    if unit and GameTooltip.SetUnit then pcall(GameTooltip.SetUnit, GameTooltip, unit) end
end)
