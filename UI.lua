-- The Super Bestiary window: a list of mobs on the left (recent targets, your zone or instance,
-- your bestiary, or search results) and a page for the selected mob or item on the right.

local _, SB = ...
local W = SB.W
local Text, Button = W.Text, W.Button

local WIDTH, HEIGHT = 940, 600
local SIDEBAR_W = 250
local GOLD, GREY, BLUE, GREEN = { 1, 0.82, 0 }, { 0.6, 0.6, 0.6 }, { 0.53, 0.8, 1 }, { 0.4, 1, 0.4 }

local ui
local state = { mode = "recent", page = nil, tab = "overview", history = {} }

------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------

local function Difficulty(level)
    local f = GetCreatureDifficultyColor or GetQuestDifficultyColor
    if f and level and level > 0 then
        local ok, c = pcall(f, level)
        if ok and type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    end
    return { 1, 1, 1 }
end

local NPC_ICON = {
    boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    elite = "Interface\\Icons\\Ability_Warrior_Challange",
    rare = "Interface\\Icons\\INV_Misc_Gem_Diamond_01",
    vendor = "Interface\\Icons\\INV_Misc_Coin_01",
    quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    normal = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
}

local function NpcIcon(n)
    if not n then return NPC_ICON.normal end
    if n.boss then return NPC_ICON.boss end
    if n.rank == 2 or n.rank == 4 then return NPC_ICON.rare end
    if n.rank == 1 then return NPC_ICON.elite end
    if #n.starts > 0 then return NPC_ICON.quest end
    if n.vendor then return NPC_ICON.vendor end
    return NPC_ICON.normal
end

local function QuestState(id)
    if SB.QuestLog.IsActive(id) then
        local e = SB.QuestLog.IsActive(id)
        return e.complete and "ready to turn in" or "in your log", e.complete and GREEN or GOLD
    end
    if SB.QuestDone(id) then return "done", { 0.45, 0.7, 0.45 } end
    local q = SB.GetQuest(id)
    if q and not SB.QuestForMe(q) then return "not for you", { 0.5, 0.5, 0.5 } end
    return nil, { 1, 1, 1 }
end

local function QuestTooltip(tt, row)
    local q = SB.GetQuest(row.id)
    local active = SB.QuestLog.IsActive(row.id)
    tt:AddLine((q and q.name) or (active and active.title) or ("Quest " .. row.id), 1, 0.82, 0)
    if q then
        tt:AddLine(("Level %d · requires %d"):format(q.level, q.reqLevel), 0.8, 0.8, 0.8)
        if q.text and q.text ~= "" then tt:AddLine(q.text, 1, 1, 1, true) end
        if #q.starters > 0 then tt:AddLine("Starts at: " .. SB.NpcName(q.starters[1]), 0.6, 0.6, 0.6) end
        if #q.enders > 0 then tt:AddLine("Ends at: " .. SB.NpcName(q.enders[1]), 0.6, 0.6, 0.6) end
    end
    if active then
        for _, o in ipairs(active.objectives) do
            tt:AddLine(o.text, o.done and 0.4 or 1, o.done and 1 or 1, o.done and 0.4 or 1)
        end
    end
    tt:AddLine("|cff888888Click: Wowhead link (quest " .. row.id .. ")|r")
end

local function NpcTooltip(tt, row)
    local n = SB.GetNpc(row.id)
    if not n then tt:AddLine("NPC " .. row.id) return end
    tt:AddLine(n.name, 1, 1, 1)
    if n.sub then tt:AddLine("<" .. n.sub .. ">", 0.8, 0.8, 0.8) end
    local cls = SB.Classification(n)
    tt:AddLine("Level " .. SB.LevelText(n) .. (cls and (" " .. cls) or ""), 1, 0.82, 0)
    if n.zones[1] and n.zones[1].area then tt:AddLine(SB.ZoneName(n.zones[1].area), 0.6, 0.6, 0.6) end
    local m = SB.db.mobs[row.id]
    if m and (m.k or 0) > 0 then tt:AddLine("You've killed " .. m.k, 0.53, 0.8, 1) end
    tt:AddLine("|cff888888Click to open|r")
end

local function NpcRow(id, mid, right, extra)
    local n = SB.GetNpc(id)
    local r = { kind = "npc", id = id, icon = NpcIcon(n), mid = mid, right = right, tooltip = NpcTooltip,
                onClick = function() SB.OpenNpc(id) end }
    if n then
        r.text = n.name .. " |cff888888(" .. SB.LevelText(n) .. ")|r"
        r.color = Difficulty(n.maxLevel)
    else
        r.text = "NPC " .. id
    end
    if extra then for k, v in pairs(extra) do r[k] = v end end
    return r
end

local function ItemRow(id, mid, right)
    return { kind = "item", id = id, icon = SB.ItemIcon(id), text = SB.ItemText(id, true), mid = mid, right = right,
             onClick = function() SB.OpenItem(id) end }
end

local function QuestRow(id, right, prefix)
    local q = SB.GetQuest(id)
    local active = SB.QuestLog.IsActive(id)
    local name = (q and q.name) or (active and active.title) or ("Quest " .. id)
    local st, color = QuestState(id)
    return { kind = "quest", id = id, text = (prefix or "") .. name .. (q and (" |cff888888[" .. q.level .. "]|r") or ""),
             color = color, mid = st, right = right, tooltip = QuestTooltip,
             onClick = function() SB.ShowLink("quest", id, name) end }
end

local function Header(text) return { kind = "header", text = text } end
local function Note(text, color) return { kind = "text", text = text, color = color or GREY } end
local function KV(key, value) return { kind = "kv", key = key, text = value } end

------------------------------------------------------------------------------
-- Waypoints
------------------------------------------------------------------------------

function SB.SetWaypoint(npcId, zone)
    local n = SB.GetNpc(npcId)
    if not n then return end
    if not zone then
        local here = SB.PlayerAreas()
        for _, z in ipairs(n.zones) do if z.x and here[z.area] then zone = z break end end
        if not zone then for _, z in ipairs(n.zones) do if z.x then zone = z break end end end
    end
    if not zone or not zone.x then SB.Print("no map position known for " .. n.name .. ".") return end
    local uiMap = SB.D.uiMap and SB.D.uiMap[zone.area]
    local where = ("%s %.1f, %.1f"):format(SB.ZoneName(zone.area), zone.x, zone.y)
    if uiMap and TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(uiMap, zone.x / 100, zone.y / 100, { title = n.name })
        SB.Print("TomTom waypoint: " .. n.name .. " - " .. where)
        return
    end
    if uiMap and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok = pcall(function()
            if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(uiMap) then error("map") end
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMap, zone.x / 100, zone.y / 100))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        if ok then SB.Print("map pin set: " .. n.name .. " - " .. where) return end
    end
    SB.Print(n.name .. ": " .. where)
end

------------------------------------------------------------------------------
-- Sidebar lists
------------------------------------------------------------------------------

local MODES = {
    { key = "recent", label = "Recent", tip = "Mobs you've targeted lately." },
    { key = "zone", label = "Zone", tip = "Every mob in your zone, or in the dungeon or raid you're in. Bosses first." },
    { key = "bestiary", label = "Bestiary", tip = "Every mob you've killed, most kills first." },
}

local function SidebarRows()
    local rows = {}
    local mode = state.mode
    if mode == "search" then
        local results = SB.Search(state.query or "")
        ui.listTitle:SetText(("Search: %d result%s"):format(#results, #results == 1 and "" or "s"))
        for _, r in ipairs(results) do
            if r.kind == "npc" then
                rows[#rows + 1] = NpcRow(r.id)
            else
                local row = ItemRow(r.id)
                row.tooltip = nil
                rows[#rows + 1] = row
            end
        end
        if #results == 0 then rows[1] = Note("Nothing found. Try part of the name.") end
    elseif mode == "zone" then
        local areas, label = SB.PlayerAreas()
        local ids = SB.NpcsInAreas(areas)
        ui.listTitle:SetText((label or "Zone") .. (" · %d mobs"):format(#ids))
        local hostileOnly = {}
        for _, id in ipairs(ids) do
            local n = SB.GetNpc(id)
            if n then hostileOnly[#hostileOnly + 1] = id end
        end
        for _, id in ipairs(hostileOnly) do rows[#rows + 1] = NpcRow(id) end
        if #rows == 0 then rows[1] = Note("No mobs known for this zone.") end
    elseif mode == "bestiary" then
        local list = {}
        for id, m in pairs(SB.db.mobs) do
            if (m.k or 0) > 0 or (m.c or 0) > 0 then list[#list + 1] = id end
        end
        table.sort(list, function(a, b)
            local ka, kb = SB.db.mobs[a].k or 0, SB.db.mobs[b].k or 0
            if ka ~= kb then return ka > kb end
            return a < b
        end)
        ui.listTitle:SetText(("Your bestiary · %d mobs"):format(#list))
        for _, id in ipairs(list) do
            local row = NpcRow(id)
            row.right = tostring(SB.db.mobs[id].k or 0)
            rows[#rows + 1] = row
        end
        if #rows == 0 then rows[1] = Note("Kill something! Every mob you kill or loot shows up here.") end
    else
        ui.listTitle:SetText("Recent targets")
        for _, id in ipairs(SB.db.recent) do rows[#rows + 1] = NpcRow(id) end
        if #rows == 0 then rows[1] = Note("Target a mob and it shows up here.") end
    end
    -- the list is narrow: show names only
    for _, r in ipairs(rows) do
        if r.kind ~= "text" then r.mid = nil end
        if state.page and r.id == state.page.id and r.kind == state.page.kind then
            r.color = GOLD
        end
    end
    return rows
end

local function RefreshSidebar(keep)
    if not ui then return end
    for _, b in ipairs(ui.modeButtons) do
        local on = b.mode == state.mode
        b.sel:SetShown(on)
    end
    ui.sideList:SetRows(SidebarRows(), keep)
end

------------------------------------------------------------------------------
-- NPC pages
------------------------------------------------------------------------------

local NPC_TABS = {
    { key = "overview", label = "Overview" },
    { key = "loot", label = "Loot" },
    { key = "abilities", label = "Abilities" },
    { key = "quests", label = "Quests" },
    { key = "notes", label = "Notes" },
}
local ITEM_TABS = {
    { key = "overview", label = "Overview" },
    { key = "droppedby", label = "Dropped by" },
    { key = "quests", label = "Quests" },
    { key = "vendors", label = "Sold by" },
}

local function FormatTime(t)
    return t and date("%d %b %Y, %H:%M", t) or "-"
end

local function NpcOverview(id, n)
    local rows = {}
    local m = SB.db.mobs[id] or {}
    rows[#rows + 1] = Header("Details")
    if n then
        rows[#rows + 1] = KV("Level", SB.LevelText(n) .. ((SB.Classification(n) and ("  " .. SB.Classification(n))) or ""))
        if n.type > 0 then
            rows[#rows + 1] = KV("Type", (SB.TYPES[n.type] or "?") .. (SB.FAMILIES[n.family] and (" · " .. SB.FAMILIES[n.family]) or ""))
        end
        if n.hpMax > 0 then
            rows[#rows + 1] = KV("Health", n.hpMin == n.hpMax and tostring(n.hpMax) or (n.hpMin .. " - " .. n.hpMax))
        end
        if n.mana > 0 then rows[#rows + 1] = KV("Mana", tostring(n.mana)) end
        if n.goldMax > 0 then rows[#rows + 1] = KV("Coin", SB.Money(n.goldMin) .. "  -  " .. SB.Money(n.goldMax)) end
        local services = {}
        if n.vendor then services[#services + 1] = "Vendor" end
        if n.repair then services[#services + 1] = "Repairs" end
        if n.trainer then services[#services + 1] = "Trainer" end
        if n.flightMaster then services[#services + 1] = "Flight master" end
        if n.skinnable then services[#services + 1] = "Skinnable" end
        if n.pickpocket then services[#services + 1] = "Can be pickpocketed" end
        if #services > 0 then rows[#rows + 1] = KV("Notes", table.concat(services, ", ")) end
        if n.friendly then
            local f = n.friendly == "AH" and "Alliance and Horde" or (n.friendly == "A" and "Alliance" or "Horde")
            rows[#rows + 1] = KV("Friendly to", f)
        end
        rows[#rows + 1] = KV("NPC ID", tostring(id))

        if #n.zones > 0 then
            rows[#rows + 1] = Header("Where")
            for _, z in ipairs(n.zones) do
                local zone = z
                local r = { kind = "text", text = SB.ZoneName(z.area), icon = "Interface\\Icons\\INV_Misc_Map_01",
                            mid = z.x and ("%.1f, %.1f"):format(z.x, z.y) or nil,
                            right = z.count > 0 and SB.Plural(z.count, "spawn") or nil }
                if z.x then
                    r.onClick = function() SB.SetWaypoint(id, zone) end
                    r.tooltip = function(tt)
                        tt:AddLine(SB.ZoneName(zone.area), 1, 1, 1)
                        tt:AddLine("Click to put a pin on the map at the middle of its spawns.", nil, nil, nil, true)
                    end
                end
                rows[#rows + 1] = r
            end
        end
    else
        rows[#rows + 1] = Note("This mob isn't in the database (new in Forever?). What you see of it is still recorded.")
    end

    rows[#rows + 1] = Header("You")
    rows[#rows + 1] = KV("Kills", tostring(m.k or 0))
    rows[#rows + 1] = KV("Corpses looted", tostring(m.c or 0))
    if m.pc then rows[#rows + 1] = KV("Pickpocketed", tostring(m.pc)) end
    rows[#rows + 1] = KV("First seen", FormatTime(m.f))
    rows[#rows + 1] = KV("Last seen", FormatTime(m.l) .. (m.z and ("  in " .. m.z) or ""))

    local loot = SB.GetLoot(id)
    if #loot > 0 then
        rows[#rows + 1] = Header("Best drops")
        local shown = 0
        for _, d in ipairs(loot) do
            local it = SB.GetItem(d.item)
            if d.quest or (it.quality or 1) >= 2 then
                rows[#rows + 1] = ItemRow(d.item, d.quest and "quest" or nil, SB.Percent(d.chance))
                shown = shown + 1
                if shown >= 6 then break end
            end
        end
        if shown == 0 then rows[#rows] = nil end
    end
    rows[#rows + 1] = Note(" ")
    rows[#rows + 1] = Note("Drop chances and stats are Classic data (CMaNGOS); \"You\" numbers are what you've seen on Forever.")
    return rows
end

local function LootRows(list, yours, corpses)
    local rows = {}
    for _, d in ipairs(list) do
        local you
        if corpses and corpses > 0 then
            local got = yours and yours[d.item] or 0
            you = ("%d (%s)"):format(got, SB.Percent(got / corpses * 100))
        end
        local mid = SB.Percent(d.chance)
        if d.quest then mid = "|cffffd100quest|r " .. mid end
        if not d.chance then mid = "|cff888888Forever|r" end
        rows[#rows + 1] = ItemRow(d.item, mid, you)
    end
    return rows
end

local function NpcLoot(id, n)
    local rows = {}
    local m = SB.db.mobs[id] or {}
    local loot = SB.GetLoot(id)
    rows[#rows + 1] = { kind = "columns", text = "Item", mid = "Classic chance", right = m.c and ("You (" .. m.c .. ")") or "You" }
    local known = {}
    for _, d in ipairs(loot) do known[d.item] = true end
    for _, r in ipairs(LootRows(loot, m.i, m.c)) do rows[#rows + 1] = r end
    if #loot == 0 then rows[#rows + 1] = Note("No loot table in the database.") end
    if n and n.worldDrops > 0 then
        rows[#rows + 1] = Note(("Also rolls on a random world-drop pool (%d possible items)."):format(n.worldDrops))
    end
    -- what you've looted that the database doesn't list
    local extra = {}
    for item, count in pairs(m.i or {}) do if not known[item] then extra[#extra + 1] = { item = item, count = count } end end
    if #extra > 0 then
        table.sort(extra, function(a, b) return a.count > b.count end)
        rows[#rows + 1] = Header("Also looted by you")
        for _, e in ipairs(extra) do
            rows[#rows + 1] = ItemRow(e.item, nil, ("%d (%s)"):format(e.count, SB.Percent(e.count / math.max(1, m.c or 1) * 100)))
        end
    end
    local ex = SB.GetExtraLoot(id)
    if ex.skinning then
        rows[#rows + 1] = Header("Skinning")
        for _, r in ipairs(LootRows(ex.skinning)) do rows[#rows + 1] = r end
    end
    if ex.pickpocket then
        rows[#rows + 1] = Header("Pickpocket")
        for _, r in ipairs(LootRows(ex.pickpocket, m.p, m.pc)) do rows[#rows + 1] = r end
    end
    if m.g and next(m.g) then
        rows[#rows + 1] = Header("Gathered from it by you")
        for item, count in pairs(m.g) do rows[#rows + 1] = ItemRow(item, nil, tostring(count)) end
    end
    return rows
end

local function NpcAbilities(id)
    local rows = {}
    local m = SB.db.mobs[id] or {}
    local seen = m.s or {}
    local names = {}
    local db = SB.GetSpells(id)
    rows[#rows + 1] = { kind = "columns", text = "Ability", mid = "", right = "Seen by you" }
    for _, sid in ipairs(db) do
        local name, icon = SB.SpellInfo(sid)
        if name and not names[name] then
            names[name] = true
            rows[#rows + 1] = { kind = "spell", id = sid, icon = icon, text = name, right = seen[sid] and (seen[sid] .. "x") or nil,
                                note = SB.SpellDescription(sid), onClick = function() SB.ShowLink("spell", sid, name) end }
        end
    end
    local mine = {}
    for sid, count in pairs(seen) do
        local name, icon = SB.SpellInfo(sid)
        if name and not names[name] then
            names[name] = true
            mine[#mine + 1] = { kind = "spell", id = sid, icon = icon, text = name, right = count .. "x",
                                onClick = function() SB.ShowLink("spell", sid, name) end }
        end
    end
    if #mine > 0 then
        rows[#rows + 1] = Header("Seen by you, not in the database")
        table.sort(mine, function(a, b) return a.text < b.text end)
        for _, r in ipairs(mine) do rows[#rows + 1] = r end
    end
    if #rows == 1 then
        rows[#rows + 1] = Note("No abilities known yet.")
        rows[#rows + 1] = Note("Fight it: every spell you see it cast is recorded here.")
    end
    return rows
end

local function NpcQuests(id, n)
    local rows = {}
    local active = SB.QuestLog.ForNpc(id)
    if #active > 0 then
        rows[#rows + 1] = Header("On your quests")
        for _, r in ipairs(active) do
            local what = r.kind == "loot" and (SB.ItemText(r.item, true) .. " " .. SB.Percent(r.chance)) or "kill"
            local row = QuestRow(r.entry.id, SB.QuestLog.ObjectiveText(r.objective))
            row.mid = what
            rows[#rows + 1] = row
        end
    end
    if n then
        local needed, seen = {}, {}
        for _, q in ipairs(n.killFor) do
            if not SB.QuestLog.IsActive(q) and not seen[q] then seen[q] = true; needed[#needed + 1] = { q = q, what = "kill" } end
        end
        for _, d in ipairs(n.dropFor) do
            if not SB.QuestLog.IsActive(d.quest) and not seen[d.quest] then
                seen[d.quest] = true
                needed[#needed + 1] = { q = d.quest, what = SB.ItemText(d.item, true) }
            end
        end
        if #needed > 0 then
            rows[#rows + 1] = Header("Needed for")
            for _, e in ipairs(needed) do
                local row = QuestRow(e.q)
                row.right = e.what
                rows[#rows + 1] = row
            end
        end
        if #n.starts > 0 then
            rows[#rows + 1] = Header("Starts")
            for _, q in ipairs(n.starts) do rows[#rows + 1] = QuestRow(q) end
        end
        if #n.ends > 0 then
            rows[#rows + 1] = Header("Turn in here")
            for _, q in ipairs(n.ends) do rows[#rows + 1] = QuestRow(q) end
        end
    end
    if #rows == 0 then rows[1] = Note("No quests involve this mob.") end
    return rows
end

------------------------------------------------------------------------------
-- Item pages
------------------------------------------------------------------------------

local function ItemOverview(id)
    local it = SB.GetItem(id)
    local rows = { Header("Details") }
    if it.quality then rows[#rows + 1] = KV("Quality", "|cff" .. (SB.QUALITY_HEX[it.quality] or "ffffff") .. (SB.QUALITY_NAMES[it.quality] or "?") .. "|r") end
    if it.ilvl and it.ilvl > 0 then rows[#rows + 1] = KV("Item level", tostring(it.ilvl)) end
    if it.req and it.req > 0 then rows[#rows + 1] = KV("Requires level", tostring(it.req)) end
    rows[#rows + 1] = KV("Item ID", tostring(id))
    local total, list = SB.GetDroppedBy(id)
    if total > 0 then
        rows[#rows + 1] = Header(("Top sources (%d mobs)"):format(total))
        for i = 1, math.min(5, #list) do rows[#rows + 1] = NpcRow(list[i].npc, nil, SB.Percent(list[i].chance)) end
    end
    local src = SB.YourItemSources(id)
    if #src > 0 then
        rows[#rows + 1] = Header("You looted it from")
        for _, s in ipairs(src) do
            rows[#rows + 1] = NpcRow(s.npc, ("%d of %d corpses"):format(s.count, s.corpses), SB.Percent(s.count / math.max(1, s.corpses) * 100))
        end
    end
    local uses = SB.GetItemUses(id)
    if #uses.containers > 0 then
        rows[#rows + 1] = Header("Found inside")
        for _, c in ipairs(uses.containers) do rows[#rows + 1] = ItemRow(c) end
    end
    if uses.objects > 0 then rows[#rows + 1] = Note(("Also found in %d kinds of world objects (chests, herbs, veins...)."):format(uses.objects)) end
    return rows
end

local function ItemDroppedBy(id)
    local total, list = SB.GetDroppedBy(id)
    local rows = { { kind = "columns", text = ("Mob (%d drop it)"):format(total), mid = "Classic chance", right = "You" } }
    local yours = {}
    for _, s in ipairs(SB.YourItemSources(id)) do yours[s.npc] = s end
    for _, d in ipairs(list) do
        local y = yours[d.npc]
        rows[#rows + 1] = NpcRow(d.npc, SB.Percent(d.chance), y and ("%d/%d"):format(y.count, y.corpses) or nil)
    end
    if total > #list then rows[#rows + 1] = Note(("+ %d more mobs with lower chances."):format(total - #list)) end
    if total == 0 then rows[#rows + 1] = Note("No mob drops this item in the database.") end
    return rows
end

local function ItemQuests(id)
    local rows = {}
    local uses = SB.GetItemUses(id)
    local active = SB.QuestLog.ForItem(id)
    if #active > 0 then
        rows[#rows + 1] = Header("On your quests")
        for _, r in ipairs(active) do rows[#rows + 1] = QuestRow(r.entry.id, SB.QuestLog.ObjectiveText(r.objective)) end
    end
    if uses.starts then
        rows[#rows + 1] = Header("Starts")
        rows[#rows + 1] = QuestRow(uses.starts)
    end
    if #uses.objectiveOf > 0 then
        rows[#rows + 1] = Header("Needed for")
        for _, q in ipairs(uses.objectiveOf) do rows[#rows + 1] = QuestRow(q) end
    end
    if #uses.rewardOf > 0 then
        rows[#rows + 1] = Header("Reward from")
        for _, q in ipairs(uses.rewardOf) do rows[#rows + 1] = QuestRow(q) end
    end
    if #rows == 0 then rows[1] = Note("No quests use this item.") end
    return rows
end

local function ItemVendors(id)
    local uses = SB.GetItemUses(id)
    local rows = {}
    if uses.vendorCount > 0 then
        rows[#rows + 1] = Header(("Sold by %s"):format(SB.Plural(uses.vendorCount, "vendor")))
        for _, v in ipairs(uses.vendors) do
            local n = SB.GetNpc(v)
            rows[#rows + 1] = NpcRow(v, n and n.zones[1] and n.zones[1].area and SB.ZoneName(n.zones[1].area) or nil)
        end
        if uses.vendorCount > #uses.vendors then rows[#rows + 1] = Note(("+ %d more"):format(uses.vendorCount - #uses.vendors)) end
    else
        rows[1] = Note("No vendor sells this item.")
    end
    return rows
end

------------------------------------------------------------------------------
-- Page header + tabs
------------------------------------------------------------------------------

local function SetModel(n)
    local model = ui.model
    model:Hide()
    ui.portrait:Show()
    if not n then return end
    local ok = false
    if n.display and n.display > 0 and model.SetDisplayInfo then
        ok = pcall(model.SetDisplayInfo, model, n.display)
    elseif model.SetCreature then
        ok = pcall(model.SetCreature, model, n.id)
    end
    if ok then
        model:Show()
        ui.portrait:Hide()
        if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
        if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1.1) end
        if model.SetRotation then pcall(model.SetRotation, model, 0.4) end
    end
end

local function DrawHeader()
    local p = state.page
    if p.kind == "npc" then
        local n = SB.GetNpc(p.id)
        local name = n and n.name or SB.unitNames[p.id] or ("NPC " .. p.id)
        ui.name:SetText(name)
        local c = n and Difficulty(n.maxLevel) or { 1, 1, 1 }
        ui.name:SetTextColor(c[1], c[2], c[3])
        local parts = {}
        if n then
            if n.sub then parts[#parts + 1] = "<" .. n.sub .. ">" end
            parts[#parts + 1] = "Level " .. SB.LevelText(n)
            local cls = SB.Classification(n)
            if cls then parts[#parts + 1] = cls end
            if n.type > 0 and n.type ~= 10 then parts[#parts + 1] = SB.TYPES[n.type] end
        end
        ui.sub:SetText(table.concat(parts, " · "))
        local zones = {}
        for i, z in ipairs(n and n.zones or {}) do
            if i > 3 then zones[#zones + 1] = "..." break end
            zones[#zones + 1] = SB.ZoneName(z.area)
        end
        ui.where:SetText(table.concat(zones, ", "))
        W.SetIcon(ui.portrait, NpcIcon(n))
        SetModel(n)
        ui.waypoint:SetShown(n and n.zones[1] and n.zones[1].x and true or false)
    else
        local it = SB.GetItem(p.id)
        ui.name:SetText(it.name)
        local hex = SB.QUALITY_HEX[it.quality or 1] or "ffffff"
        ui.name:SetTextColor(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
        local parts = {}
        if it.ilvl and it.ilvl > 0 then parts[#parts + 1] = "Item level " .. it.ilvl end
        if it.req and it.req > 0 then parts[#parts + 1] = "Requires level " .. it.req end
        ui.sub:SetText(table.concat(parts, " · "))
        local total = SB.GetDroppedBy(p.id)
        ui.where:SetText(total > 0 and ("Dropped by " .. SB.Plural(total, "mob")) or "")
        ui.model:Hide()
        ui.portrait:Show()
        W.SetIcon(ui.portrait, SB.ItemIcon(p.id))
        ui.waypoint:Hide()
    end
    ui.back:SetEnabled(#state.history > 0)
end

local function DrawTabs()
    local tabs = state.page.kind == "npc" and NPC_TABS or ITEM_TABS
    local valid = false
    for _, t in ipairs(tabs) do if t.key == state.tab then valid = true end end
    if not valid then state.tab = "overview" end
    for i, b in ipairs(ui.tabs) do
        local t = tabs[i]
        if t then
            b:Show()
            b.key = t.key
            b.label:SetText(t.label)
            b:SetWidth(b.label:GetStringWidth() + 24)
            b.sel:SetShown(t.key == state.tab)
            b.label:SetTextColor(t.key == state.tab and 1 or 0.7, t.key == state.tab and 0.82 or 0.7, t.key == state.tab and 0 or 0.7)
        else
            b:Hide()
        end
    end
end

local function DrawContent(keep)
    local p = state.page
    ui.notes:Hide()
    ui.content:Show()
    local rows
    if p.kind == "npc" then
        local n = SB.GetNpc(p.id)
        if state.tab == "loot" then rows = NpcLoot(p.id, n)
        elseif state.tab == "abilities" then rows = NpcAbilities(p.id)
        elseif state.tab == "quests" then rows = NpcQuests(p.id, n)
        elseif state.tab == "notes" then
            ui.content:Hide()
            ui.notes:Show()
            local m = SB.db.mobs[p.id]
            ui.notes.edit:SetText(m and m.n or "")
            return
        else rows = NpcOverview(p.id, n) end
    else
        if state.tab == "droppedby" then rows = ItemDroppedBy(p.id)
        elseif state.tab == "quests" then rows = ItemQuests(p.id)
        elseif state.tab == "vendors" then rows = ItemVendors(p.id)
        else rows = ItemOverview(p.id) end
    end
    ui.content:SetRows(rows, keep)
end

local function DrawPage(keep)
    if not ui then return end
    ui.settingsPage:Hide()
    if not state.page then
        ui.pageFrame:Hide()
        ui.empty:Show()
        return
    end
    ui.empty:Hide()
    ui.pageFrame:Show()
    DrawHeader()
    DrawTabs()
    DrawContent(keep)
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function CreateUI()
    local tpl
    ui, tpl = W.CreateWithTemplate("Frame", "SuperBestiaryFrame", UIParent,
        { "PortraitFrameTemplate", "ButtonFrameTemplate", "BasicFrameTemplateWithInset" })
    ui:SetSize(WIDTH, HEIGHT)
    ui:SetPoint("CENTER")
    W.FixCloseButton(ui)
    ui:SetFrameStrata("HIGH")
    ui:SetToplevel(true)
    ui:SetMovable(true)
    ui:SetClampedToScreen(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
    ui:Hide()
    tinsert(UISpecialFrames, "SuperBestiaryFrame")

    local top = -30
    if tpl == "PortraitFrameTemplate" or tpl == "ButtonFrameTemplate" then
        top = -62
        if ui.SetTitle then ui:SetTitle(SB.TITLE) end
        if ui.SetPortraitToAsset then pcall(ui.SetPortraitToAsset, ui, SB.ICON) end
        if ui.Inset then ui.Inset:Hide() end
    else
        local title = Text(ui, "GameFontHighlight")
        title:SetPoint("TOP", 0, -6)
        title:SetText(SB.TITLE)
    end
    if not tpl then
        local bg = ui:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
    end
    if top < -40 then
        local tagline = Text(ui, "GameFontNormalSmall")
        tagline:SetPoint("TOPLEFT", 70, -34)
        tagline:SetText("Loot, abilities and quests for every mob")
    end

    -- sidebar
    local side = W.Panel(ui, 0.3)
    side:SetPoint("TOPLEFT", 10, top)
    side:SetPoint("BOTTOMLEFT", 10, 10)
    side:SetWidth(SIDEBAR_W)

    ui.search = W.Input(side, SIDEBAR_W - 20, "Search mobs and items")
    ui.search:SetPoint("TOPLEFT", 12, -8)
    ui.search:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        local text = self:GetText() or ""
        if #text >= 2 then
            state.mode, state.query = "search", text
        elseif state.mode == "search" then
            state.mode = "recent"
        end
        RefreshSidebar()
    end)
    ui.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local first = ui.sideList.rows[1]
        if first and first.onClick then first.onClick(first) end
    end)

    ui.modeButtons = {}
    local bw = math.floor((SIDEBAR_W - 16) / #MODES)
    for i, mdef in ipairs(MODES) do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(bw - 2, 22)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * bw, -36)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(1, 1, 1, 0.05)
        b.sel = b:CreateTexture(nil, "ARTWORK")
        b.sel:SetPoint("BOTTOMLEFT")
        b.sel:SetPoint("BOTTOMRIGHT")
        b.sel:SetHeight(2)
        b.sel:SetColorTexture(1, 0.6, 0.2, 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.label = Text(b, "GameFontNormalSmall")
        b.label:SetPoint("CENTER")
        b.label:SetText(mdef.label)
        b.mode = mdef.key
        b:SetScript("OnClick", function()
            state.mode = mdef.key
            ui.search:SetText("")
            ui.search:ClearFocus()
            RefreshSidebar()
        end)
        b:SetScript("OnEnter", function(self) W.Tooltip(self, mdef.label, mdef.tip) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ui.modeButtons[i] = b
    end

    ui.listTitle = Text(side, "GameFontNormalSmall")
    ui.listTitle:SetPoint("TOPLEFT", 10, -66)
    ui.listTitle:SetPoint("RIGHT", -10, 0)
    ui.listTitle:SetJustifyH("LEFT")

    ui.sideList = W.RowList(side)
    ui.sideList:SetPoint("TOPLEFT", 4, -82)
    ui.sideList:SetPoint("BOTTOMRIGHT", -4, 36)

    local settingsBtn = Button(side, "Settings", 100, 22, function() SB.OpenSettings() end)
    settingsBtn:SetPoint("BOTTOMLEFT", 8, 8)
    local targetBtn = Button(side, "My target", 100, 22, function() SB.OpenTarget(true) end)
    targetBtn:SetPoint("BOTTOMRIGHT", -8, 8)

    -- right side
    local main = CreateFrame("Frame", nil, ui)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, 0)
    main:SetPoint("BOTTOMRIGHT", -10, 10)
    ui.main = main

    ui.empty = Text(main, "GameFontDisable")
    ui.empty:SetPoint("CENTER")
    ui.empty:SetText("Target a mob, pick one on the left, or search.\n\nAlt-click an item anywhere to open its page.")

    local page = CreateFrame("Frame", nil, main)
    page:SetAllPoints()
    ui.pageFrame = page

    local head = W.Panel(page, 0.3)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(112)

    ui.portrait = head:CreateTexture(nil, "ARTWORK")
    ui.portrait:SetSize(64, 64)
    ui.portrait:SetPoint("LEFT", 24, 0)
    local modelOk, model = pcall(CreateFrame, "PlayerModel", nil, head)
    if not modelOk then model = CreateFrame("Frame", nil, head) end
    model:SetSize(104, 104)
    model:SetPoint("LEFT", 4, 0)
    ui.model = model

    ui.name = Text(head, W.Font("GameFontNormalHuge", "GameFontNormalLarge"))
    ui.name:SetPoint("TOPLEFT", 120, -18)
    ui.name:SetPoint("RIGHT", -150, 0)
    ui.name:SetJustifyH("LEFT")
    ui.name:SetWordWrap(false)
    ui.sub = Text(head, "GameFontHighlight")
    ui.sub:SetPoint("TOPLEFT", ui.name, "BOTTOMLEFT", 0, -8)
    ui.sub:SetPoint("RIGHT", -150, 0)
    ui.sub:SetJustifyH("LEFT")
    ui.where = Text(head, "GameFontDisable")
    ui.where:SetPoint("TOPLEFT", ui.sub, "BOTTOMLEFT", 0, -6)
    ui.where:SetPoint("RIGHT", -150, 0)
    ui.where:SetJustifyH("LEFT")

    ui.wowhead = Button(head, "Wowhead link", 130, 22, function()
        local p = state.page
        if p then SB.ShowLink(p.kind, p.id, ui.name:GetText()) end
    end)
    ui.wowhead:SetPoint("TOPRIGHT", -10, -10)
    ui.waypoint = Button(head, "Map pin", 130, 22, function()
        if state.page and state.page.kind == "npc" then SB.SetWaypoint(state.page.id) end
    end)
    ui.waypoint:SetPoint("TOPRIGHT", ui.wowhead, "BOTTOMRIGHT", 0, -4)
    ui.back = Button(head, "< Back", 130, 22, function() SB.Back() end)
    ui.back:SetPoint("TOPRIGHT", ui.waypoint, "BOTTOMRIGHT", 0, -4)

    ui.tabs = {}
    for i = 1, 5 do
        local b = CreateFrame("Button", nil, page)
        b:SetHeight(24)
        if i == 1 then b:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6) else b:SetPoint("LEFT", ui.tabs[i - 1], "RIGHT", 4, 0) end
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.05)
        b.sel = b:CreateTexture(nil, "ARTWORK")
        b.sel:SetPoint("BOTTOMLEFT")
        b.sel:SetPoint("BOTTOMRIGHT")
        b.sel:SetHeight(2)
        b.sel:SetColorTexture(1, 0.6, 0.2, 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.label = Text(b, "GameFontNormal")
        b.label:SetPoint("CENTER")
        b:SetScript("OnClick", function(self)
            state.tab = self.key
            DrawTabs()
            DrawContent()
        end)
        ui.tabs[i] = b
    end

    local body = W.Panel(page, 0.25)
    body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -34)
    body:SetPoint("BOTTOMRIGHT")
    ui.content = W.RowList(body)
    ui.content:SetPoint("TOPLEFT", 4, -4)
    ui.content:SetPoint("BOTTOMRIGHT", -4, 4)

    -- notes tab
    local notes = CreateFrame("Frame", nil, body)
    notes:SetAllPoints()
    notes:Hide()
    local nlabel = Text(notes, "GameFontNormal")
    nlabel:SetPoint("TOPLEFT", 10, -10)
    nlabel:SetText("Your notes on this mob (saved for all your characters)")
    local scroll = W.CreateWithTemplate("ScrollFrame", "SuperBestiaryNotesScroll", notes, { "UIPanelScrollFrameTemplate", "ScrollFrameTemplate" })
    scroll:SetPoint("TOPLEFT", 10, -34)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(WIDTH - SIDEBAR_W - 90)
    eb:SetMaxLetters(2000)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnTextChanged", function(self, user)
        if not user or not state.page or state.page.kind ~= "npc" then return end
        local text = self:GetText() or ""
        local m = SB.Mob(state.page.id, text ~= "")
        if m then m.n = text ~= "" and text or nil end
    end)
    scroll:SetScrollChild(eb)
    notes:EnableMouse(true)
    notes:SetScript("OnMouseDown", function() eb:SetFocus() end)
    notes.edit = eb
    ui.notes = notes

    ui.settingsPage = SB.CreateSettingsPage(main)
    ui.settingsPage:SetAllPoints()
    ui.settingsPage:Hide()

    ui:SetScript("OnShow", function() RefreshSidebar(true) end)
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

SB.unitNames = {}

local function Ensure()
    if not ui then CreateUI() end
    return ui
end

local function Open(kind, id)
    Ensure()
    if state.page and not (state.page.kind == kind and state.page.id == id) then
        table.insert(state.history, state.page)
        if #state.history > 30 then table.remove(state.history, 1) end
    end
    if not state.page or state.page.kind ~= kind then state.tab = "overview" end
    state.page = { kind = kind, id = id }
    ui:Show()
    DrawPage()
    RefreshSidebar(true)
end

function SB.OpenNpc(id) Open("npc", id) end
function SB.OpenItem(id) Open("item", id) end

function SB.Back()
    local prev = table.remove(state.history)
    if not prev then return end
    state.page = prev
    DrawPage()
    RefreshSidebar(true)
end

function SB.OpenTarget(fromButton)
    local id = SB.UnitNpcId("target")
    if id then
        local name = SB.Public(UnitName("target"))
        if name then SB.unitNames[id] = name end
        SB.OpenNpc(id)
        return
    end
    if fromButton then
        if UnitExists("target") and IsInInstance and IsInInstance() then
            SB.Print("the game hides which mob your target is inside instances. Use the Zone list instead.")
        else
            SB.Print("target a mob first.")
        end
        return
    end
    Ensure()
    if IsInInstance and IsInInstance() and not state.page then state.mode = "zone" end
    ui:Show()
    DrawPage()
    RefreshSidebar(true)
end

function SB.OpenZone()
    Ensure()
    state.mode = "zone"
    ui.search:SetText("")
    ui:Show()
    DrawPage()
    RefreshSidebar()
end

function SB.OpenSearch(text)
    Ensure()
    state.mode, state.query = "search", text
    ui.search:SetText(text)
    ui:Show()
    DrawPage()
    RefreshSidebar()
    -- one exact hit: open it straight away
    local rows = ui.sideList.rows
    if #rows == 1 and rows[1].onClick then rows[1].onClick(rows[1]) end
end

function SB.OpenSettings()
    Ensure()
    ui:Show()
    ui.pageFrame:Hide()
    ui.empty:Hide()
    ui.settingsPage:Show()
    ui.settingsPage:Refresh()
end

function SB.Toggle()
    if ui and ui:IsShown() then ui:Hide() else SB.OpenTarget() end
end

function SB.IsOpen() return ui and ui:IsShown() end
function SB.CurrentPage() return state.page, state.tab end
function SB.SetTab(tab) state.tab = tab; DrawPage(true) end
function SB.SidebarRows() return ui and ui.sideList.rows end
function SB.ContentRows() return ui and ui.content.rows end

-- Close settings and go back to the page (used by the settings page's Done button).
function SB.CloseSettings() DrawPage(true) end

-- Live refreshes while the window is open
local pending
local function Refresh()
    if pending then return end
    pending = true
    SB.After(0.3, function()
        pending = false
        if ui and ui:IsShown() and not ui.settingsPage:IsShown() then
            if not (state.tab == "notes") then DrawPage(true) end
            RefreshSidebar(true)
        end
    end)
end
SB.OnQuestLogChanged = Refresh
SB.OnMobChanged = function(id) if state.page and state.page.id == id then Refresh() end end
SB.OnTargetChanged = function() if ui and ui:IsShown() and state.mode == "recent" then Refresh() end end
SB.On("GET_ITEM_INFO_RECEIVED", Refresh)
SB.On("ZONE_CHANGED_NEW_AREA", function() if state.mode == "zone" then Refresh() end end)

-- Alt-click (configurable) an item anywhere to open its page.
local CLICK_MODS = {
    ["ALT"] = function() return IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() end,
    ["CTRL-ALT"] = function() return IsAltKeyDown() and IsControlKeyDown() and not IsShiftKeyDown() end,
    ["SHIFT-ALT"] = function() return IsAltKeyDown() and IsShiftKeyDown() and not IsControlKeyDown() end,
}
SB.AddLoad(function()
    if not HandleModifiedItemClick then return end
    hooksecurefunc("HandleModifiedItemClick", function(link)
        local check = CLICK_MODS[SB.db.itemClick]
        if not check or not check() then return end
        link = SB.Public(link)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then SB.OpenItem(id) end
    end)
end)
