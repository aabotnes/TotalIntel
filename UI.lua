-- The Total Intel window, laid out like the game's Adventure Guide: an open book with a list on
-- the left page (recent targets, your zone, your bestiary, an instance's bosses, search results)
-- and the selected mob, item or instance on the right page, with the journal's side tabs.
-- Bottom tabs switch lists; Dungeons and Raids show the Adventure Guide's instance grid.

local _, SB = ...
local W, Skin = SB.W, SB.Skin
local Text, Button = W.Text, W.Button

local WIDTH, HEIGHT = 980, 640          -- default size; drag the corner to resize (remembered)
local MIN_W, MIN_H, MAX_W, MAX_H = 800, 496, 1600, 1100
local TOP = 69                          -- height of the title + navigation bar above the book
local ui
local DrawPage
local state = { mode = "recent", page = nil, tab = "overview", history = {}, expanded = {} }

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------

local NPC_ICON = {
    boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    elite = "Interface\\Icons\\Ability_Warrior_Challange",
    rare = "Interface\\Icons\\INV_Misc_Gem_Diamond_01",
    vendor = "Interface\\Icons\\INV_Misc_Coin_01",
    quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    normal = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
}
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local ACTIVE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local function NpcIcon(n)
    if not n then return NPC_ICON.normal end
    if n.boss then return NPC_ICON.boss end
    if n.rank == 2 or n.rank == 4 then return NPC_ICON.rare end
    if n.rank == 1 then return NPC_ICON.elite end
    if #n.starts > 0 then return NPC_ICON.quest end
    if n.vendor then return NPC_ICON.vendor end
    return NPC_ICON.normal
end

local function NpcSub(n, extra)
    if not n then return extra end
    local parts = { "Level " .. SB.LevelText(n) }
    local cls = SB.Classification(n)
    if cls then parts[#parts + 1] = cls end
    if extra then parts[#parts + 1] = extra
    elseif n.zones[1] then parts[#parts + 1] = SB.ZoneName(n.zones[1].area) end
    return table.concat(parts, " · ")
end

local function NpcTooltip(tt, row)
    local n = SB.GetNpc(row.id)
    if not n then tt:AddLine("NPC " .. row.id) return end
    tt:AddLine(n.name, 1, 1, 1)
    if n.sub then tt:AddLine("<" .. n.sub .. ">", 0.8, 0.8, 0.8) end
    local cls = SB.Classification(n)
    tt:AddLine("Level " .. SB.LevelText(n) .. (cls and (" " .. cls) or ""), 1, 0.82, 0)
    if n.zones[1] then tt:AddLine(SB.ZoneName(n.zones[1].area), 0.6, 0.6, 0.6) end
    local m = SB.db.mobs[row.id]
    if m and (m.k or 0) > 0 then tt:AddLine("You've killed " .. m.k, 0.53, 0.8, 1) end
    tt:AddLine("|cff888888Click to open|r")
end

-- kind "boss" for the left page, "npc" for lists on the right page
local function NpcRow(id, kind, extra)
    local n = SB.GetNpc(id)
    local r = { kind = kind or "npc", id = id, icon = NpcIcon(n), portrait = n and n.display, tooltip = NpcTooltip,
                text = n and n.name or ("NPC " .. id), sub = NpcSub(n),
                onClick = function() SB.OpenNpc(id) end }
    if state.page and state.page.kind == "npc" and state.page.id == id then r.selected = true end
    if extra then for k, v in pairs(extra) do r[k] = v end end
    return r
end

local function ItemRow(id, mid, right, sub)
    local it = SB.GetItem(id)
    if not sub then
        local parts = {}
        if it.ilvl and it.ilvl > 0 then parts[#parts + 1] = "Item level " .. it.ilvl end
        if it.req and it.req > 1 then parts[#parts + 1] = "Requires level " .. it.req end
        sub = table.concat(parts, " · ")
    end
    return { kind = "item", id = id, icon = SB.ItemIcon(id), text = SB.ItemText(id, true), mid = mid, right = right,
             quality = it.quality,
             sub = sub, onClick = function() SB.OpenItem(id) end }
end

local function QuestState(id)
    local e = SB.QuestLog.IsActive(id)
    if e then return e.complete and "ready to turn in" or "in your log", e.complete and "good" or "warn" end
    if SB.QuestDone(id) then return "done", "good" end
    local q = SB.GetQuest(id)
    if q and not SB.QuestForMe(q) then return "not for you", "off" end
    return nil, "light"
end

local function QuestTooltip(tt, row)
    local q = SB.GetQuest(row.id)
    local active = SB.QuestLog.IsActive(row.id)
    tt:AddLine((q and q.name) or (active and active.title) or ("Quest " .. row.id), 1, 0.82, 0)
    if q then
        tt:AddLine(("Level %d · requires %d"):format(q.level, q.reqLevel), 0.8, 0.8, 0.8)
        if q.text and q.text ~= "" then tt:AddLine(q.text, 1, 1, 1, true) end
        if q.starters[1] then tt:AddLine("Starts at: " .. SB.NpcName(q.starters[1]), 0.6, 0.6, 0.6) end
        if q.enders[1] then tt:AddLine("Ends at: " .. SB.NpcName(q.enders[1]), 0.6, 0.6, 0.6) end
    end
    if active then
        for _, o in ipairs(active.objectives) do
            tt:AddLine(o.text, o.done and 0.4 or 1, 1, o.done and 0.4 or 1)
        end
    end
    tt:AddLine("|cff888888Click: Wowhead link (quest " .. row.id .. ")|r")
end

local function QuestRow(id, right, what)
    local q = SB.GetQuest(id)
    local active = SB.QuestLog.IsActive(id)
    local name = (q and q.name) or (active and active.title) or ("Quest " .. id)
    local st, color = QuestState(id)
    return { kind = "quest", id = id, icon = active and ACTIVE_ICON or QUEST_ICON,
             text = name .. (q and (" [" .. q.level .. "]") or ""), color = color,
             mid = what or st, right = right, tooltip = QuestTooltip,
             onClick = function() SB.ShowLink("quest", id, name) end }
end

local function Header(text, right) return { kind = "header", text = text, right = right } end
local function Note(text, color) return { kind = "text", text = text, color = color or "text" } end
local function KV(key, value, color) return { kind = "kv", key = key, text = value, color = color } end

local function FormatTime(t) return t and date("%d %b %Y, %H:%M", t) or "-" end

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
    local uiMap = SB.UiMapForArea(zone.area)
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
-- Left page: lists
------------------------------------------------------------------------------

local BOTTOM_TABS = {
    { key = "recent", label = "Recent" },
    { key = "zone", label = "Zone" },
    { key = "bestiary", label = "Bestiary" },
    { key = "dungeons", label = "Dungeons" },
    { key = "raids", label = "Raids" },
    { key = "settings", label = "Settings" },
}

local function ListRows()
    local rows, title, count = {}, "", nil
    local mode = state.mode
    if mode == "search" then
        local results = SB.Search(state.query or "")
        title, count = "Search: " .. (state.query or ""), #results
        local npcs, items = {}, {}
        for _, r in ipairs(results) do
            if r.kind == "npc" then npcs[#npcs + 1] = NpcRow(r.id, "boss") else items[#items + 1] = ItemRow(r.id) end
        end
        if #npcs > 0 then
            rows[#rows + 1] = Header("Mobs and NPCs", tostring(#npcs))
            for _, r in ipairs(npcs) do rows[#rows + 1] = r end
        end
        if #items > 0 then
            rows[#rows + 1] = Header("Items", tostring(#items))
            for _, r in ipairs(items) do rows[#rows + 1] = r end
        end
        if #results == 0 then rows[1] = Note("Nothing found. Try part of the name, or an ID.") end
    elseif mode == "instance" then
        local inst = SB.GetInstance(state.instance)
        title = inst and inst.name or "?"
        if inst then
            count = #inst.mobs
            if #inst.bosses > 0 then rows[#rows + 1] = Header("Bosses", tostring(#inst.bosses)) end
            for _, id in ipairs(inst.bosses) do rows[#rows + 1] = NpcRow(id, "boss") end
            local others = {}
            for _, id in ipairs(inst.mobs) do if not SB.GetNpc(id).boss then others[#others + 1] = id end end
            if #others > 0 then rows[#rows + 1] = Header("Other inhabitants", tostring(#others)) end
            for _, id in ipairs(others) do rows[#rows + 1] = NpcRow(id, "boss") end
        end
        if #rows == 0 then rows[1] = Note(SB.index.ready and "No mobs known for this instance." or "Reading the database...") end
    elseif mode == "zone" then
        local areas, label = SB.PlayerAreas()
        local ids, have = {}, {}
        for _, id in ipairs(SB.NpcsInAreas(areas)) do have[id] = true; ids[#ids + 1] = id end
        -- plus every mob you've seen here, whether or not a database knows it
        local here = GetZoneText and GetZoneText()
        for id, m in pairs(SB.db.mobs) do
            if not have[id] and m.z and (m.z == here or m.z == label) then have[id] = true; ids[#ids + 1] = id end
        end
        title, count = label or "Zone", #ids
        local groups = {
            { "For your quests", {} }, { "Bosses, elites & rares", {} }, { "Creatures", {} }, { "Friendly NPCs", {} },
        }
        for _, id in ipairs(ids) do
            local n = SB.GetNpc(id)
            local g
            if #SB.QuestLog.ForNpc(id) > 0 then g = 1
            elseif n and n.friendly then g = 4
            elseif n and (n.boss or n.rank > 0) then g = 2
            else g = 3 end
            table.insert(groups[g][2], id)
        end
        for _, grp in ipairs(groups) do
            table.sort(grp[2], function(a, b)
                local na, nb = SB.GetNpc(a), SB.GetNpc(b)
                local la, lb = na and na.maxLevel or 0, nb and nb.maxLevel or 0
                if la ~= lb then return la < lb end
                return SB.NpcName(a) < SB.NpcName(b)
            end)
            if #grp[2] > 0 then
                rows[#rows + 1] = Header(grp[1], tostring(#grp[2]))
                for _, id in ipairs(grp[2]) do rows[#rows + 1] = NpcRow(id, "boss") end
            end
        end
        if #rows == 0 then
            if not SB.QDB() then
                rows[1] = Note("No mobs listed for " .. (label or "this zone") .. " yet. Type /tits status to see what's loaded.")
            else
                rows[1] = Note(SB.index.ready and "No mobs known for this zone." or "Reading the database...")
            end
        end
    elseif mode == "bestiary" then
        local list = {}
        for id, m in pairs(SB.db.mobs) do if (m.k or 0) > 0 or (m.c or 0) > 0 then list[#list + 1] = id end end
        table.sort(list, function(a, b)
            local ka, kb = SB.db.mobs[a].k or 0, SB.db.mobs[b].k or 0
            if ka ~= kb then return ka > kb end
            return a < b
        end)
        title, count = "Your bestiary", #list
        for _, id in ipairs(list) do
            rows[#rows + 1] = NpcRow(id, "boss", { right = tostring(SB.db.mobs[id].k or 0) })
        end
        if #rows == 0 then rows[1] = Note("Kill something! Every mob you kill or loot shows up here.") end
    else
        title = "Recent targets"
        for _, id in ipairs(SB.db.recent) do rows[#rows + 1] = NpcRow(id, "boss") end
        if #rows == 0 then rows[1] = Note("Target a mob and it shows up here. Alt-click any mob to open it.") end
    end
    return rows, title, count
end

local function DrawList(keep)
    local rows, title, count = ListRows()
    ui.leftTitle:SetText(title)
    ui.leftCount:SetText(count and tostring(count) or "")
    ui.leftList:SetRows(rows, keep)
end

------------------------------------------------------------------------------
-- Right page: NPCs
------------------------------------------------------------------------------

local function ChanceText(d)
    if not d.chance then return "drops" end
    return SB.Percent(d.chance) .. (d.src == "wowhead" and " (Wowhead)" or "")
end

local function NpcOverview(id, n)
    local rows = {}
    local m = SB.db.mobs[id] or {}
    if n then
        rows[#rows + 1] = Header("Overview")
        if n.type > 0 then
            rows[#rows + 1] = KV("Type", (SB.TYPES[n.type] or "?") .. (SB.FAMILIES[n.family] and (", " .. SB.FAMILIES[n.family]) or ""))
        end
        if n.hpMax > 0 then
            rows[#rows + 1] = KV("Health", (n.hpMin == n.hpMax and tostring(n.hpMax) or (n.hpMin .. " - " .. n.hpMax)) .. "  (Classic)")
        end
        if n.mana > 0 then rows[#rows + 1] = KV("Mana", tostring(n.mana)) end
        if n.goldMax > 0 then rows[#rows + 1] = KV("Coin", SB.Money(n.goldMin) .. " - " .. SB.Money(n.goldMax)) end
        local services = {}
        if n.vendor then services[#services + 1] = "Vendor" end
        if n.repair then services[#services + 1] = "Repairs" end
        if n.trainer then services[#services + 1] = "Trainer" end
        if n.flightMaster then services[#services + 1] = "Flight master" end
        if n.skinnable then services[#services + 1] = "Skinnable" end
        if n.pickpocket then services[#services + 1] = "Can be pickpocketed" end
        if #services > 0 then rows[#rows + 1] = KV("Notes", table.concat(services, ", ")) end
        local sells, teaches = #SB.Sells(id), #SB.Teaches(id)
        if sells > 0 then rows[#rows + 1] = KV("Sells", SB.Plural(sells, "item") .. " (Sells tab)") end
        if teaches > 0 then rows[#rows + 1] = KV("Teaches", SB.Plural(teaches, "skill") .. " (Teaches tab)") end
        if n.friendly then
            rows[#rows + 1] = KV("Friendly to", n.friendly == "AH" and "Alliance and Horde" or (n.friendly == "A" and "Alliance" or "Horde"))
        end
        rows[#rows + 1] = KV("NPC ID", tostring(id))
        if #n.zones > 0 then
            rows[#rows + 1] = Header("Where")
            for _, z in ipairs(n.zones) do
                local zone = z
                local r = { kind = "zone", icon = MAP_ICON, text = SB.ZoneName(z.area),
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
        rows[#rows + 1] = Note("Nothing is known about this NPC yet. What you see of it is still recorded.")
    end
    rows[#rows + 1] = Header("Your record")
    rows[#rows + 1] = KV("Kills", tostring(m.k or 0))
    rows[#rows + 1] = KV("Corpses looted", tostring(m.c or 0))
    if m.pc then rows[#rows + 1] = KV("Pickpocketed", tostring(m.pc)) end
    rows[#rows + 1] = KV("First seen", FormatTime(m.f))
    rows[#rows + 1] = KV("Last seen", FormatTime(m.l) .. (m.z and (", " .. m.z) or ""))
    local loot = SB.GetLoot(id)
    local best = {}
    for _, d in ipairs(loot) do
        local it = SB.GetItem(d.item)
        if d.quest or (it.quality or 1) >= 2 then best[#best + 1] = d end
        if #best >= 4 then break end
    end
    if #best > 0 then
        rows[#rows + 1] = Header("Best drops", "all " .. #loot .. " on the Loot tab")
        for _, d in ipairs(best) do rows[#rows + 1] = ItemRow(d.item, ChanceText(d), nil, d.quest and "Quest drop" or nil) end
    end
    return rows
end

-- Rarity filter for the Loot tab (saved): SB.db.lootFilter[quality] == false hides that rarity.
local function RarityShown(item)
    local q = SB.GetItem(item).quality
    return q == nil or SB.db.lootFilter[q] ~= false
end

local function FilterActive()
    for _, v in pairs(SB.db.lootFilter) do if v == false then return true end end
    return false
end

-- The chips row: one toggle per rarity that occurs in `items`, and Reset while a rarity is hidden.
local function RarityChips(items)
    local present = {}
    for _, item in ipairs(items) do
        local q = SB.GetItem(item).quality
        if q then present[q] = (present[q] or 0) + 1 end
    end
    local chips = {}
    for q = 0, 7 do
        if present[q] then
            local hex = SB.QUALITY_HEX[q] or "ffffff"
            local on = SB.db.lootFilter[q] ~= false
            local name = SB.QUALITY_NAMES[q] or ("Quality " .. q)
            chips[#chips + 1] = {
                text = name .. " " .. present[q], on = on, quality = q,
                color = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 },
                tip = on and ("Click to hide " .. name .. " items.") or ("Click to show " .. name .. " items."),
                onClick = function()
                    if SB.db.lootFilter[q] == false then SB.db.lootFilter[q] = nil else SB.db.lootFilter[q] = false end
                    SB.Redraw(true)
                end,
            }
        end
    end
    if FilterActive() then
        chips[#chips + 1] = { text = "Reset filter", on = true, reset = true, color = { 1, 0.82, 0 },
            tip = "Show every rarity again.",
            onClick = function() wipe(SB.db.lootFilter); SB.Redraw(true) end }
    end
    return { kind = "filters", chips = chips }
end

local function LootRows(list, yours, corpses)
    local rows = {}
    for _, d in ipairs(list) do
        if RarityShown(d.item) then
            local you
            if corpses and corpses > 0 then
                local got = yours and yours[d.item] or 0
                you = ("you %d of %d (%s)"):format(got, corpses, SB.Percent(got / corpses * 100))
            end
            rows[#rows + 1] = ItemRow(d.item, ChanceText(d), you, d.quest and "Quest drop" or nil)
        end
    end
    return rows
end

local function NpcLoot(id, n)
    local rows = {}
    local m = SB.db.mobs[id] or {}
    local loot = SB.GetLoot(id)
    local ex = SB.GetExtraLoot(id)
    local known, extra = {}, {}
    for _, d in ipairs(loot) do known[d.item] = true end
    for item, count in pairs(m.i or {}) do if not known[item] then extra[#extra + 1] = { item = item, count = count } end end
    table.sort(extra, function(a, b) return a.count > b.count end)

    -- every item on this page, for the filter chips
    local all = {}
    for _, d in ipairs(loot) do all[#all + 1] = d.item end
    for _, e in ipairs(extra) do all[#all + 1] = e.item end
    for _, d in ipairs(ex.skinning or {}) do all[#all + 1] = d.item end
    for _, d in ipairs(ex.pickpocket or {}) do all[#all + 1] = d.item end
    for item in pairs(m.g or {}) do all[#all + 1] = item end

    local lootRows = LootRows(loot, m.i, m.c)
    local count = #loot > 0 and (#lootRows == #loot and tostring(#loot) or (#lootRows .. " of " .. #loot)) or nil
    rows[#rows + 1] = Header("Loot", count)
    if #all > 0 then rows[#rows + 1] = RarityChips(all) end
    for _, r in ipairs(lootRows) do rows[#rows + 1] = r end
    if #loot == 0 then
        rows[#rows + 1] = Note("No loot known for this mob.")
    elseif #lootRows == 0 then
        rows[#rows + 1] = Note("Every drop is hidden by the rarity filter. Click a rarity above, or Reset filter.")
    end
    if n and n.worldDrops > 0 then
        rows[#rows + 1] = Note(("Also rolls on a random world-drop pool (%d possible items)."):format(n.worldDrops))
    end
    if #loot > 0 then
        rows[#rows + 1] = Note("Chances: Wowhead for quest items, otherwise Classic numbers. Forever may differ, so your own rate is shown under each chance.")
    end
    local mine = {}
    for _, e in ipairs(extra) do
        if RarityShown(e.item) then
            mine[#mine + 1] = ItemRow(e.item, nil, ("you %d of %d (%s)"):format(e.count, math.max(1, m.c or 1), SB.Percent(e.count / math.max(1, m.c or 1) * 100)))
        end
    end
    if #mine > 0 then
        rows[#rows + 1] = Header("Also looted by you", tostring(#mine))
        for _, r in ipairs(mine) do rows[#rows + 1] = r end
    end
    local function Section(title, list)
        if #list > 0 then
            rows[#rows + 1] = Header(title, tostring(#list))
            for _, r in ipairs(list) do rows[#rows + 1] = r end
        end
    end
    Section("Skinning", LootRows(ex.skinning or {}))
    Section("Pickpocket", LootRows(ex.pickpocket or {}, m.p, m.pc))
    local gathered = {}
    for item, n2 in pairs(m.g or {}) do
        if RarityShown(item) then gathered[#gathered + 1] = ItemRow(item, tostring(n2)) end
    end
    Section("Gathered from it by you", gathered)
    return rows
end

local function SpellRows(rows, sid, name, icon, seenCount)
    local open = state.expanded[sid]
    rows[#rows + 1] = { kind = "spell", id = sid, icon = icon, text = name, expanded = open,
                        right = seenCount and (seenCount .. "x") or nil,
                        onClick = function() state.expanded[sid] = not state.expanded[sid]; SB.Redraw(true) end }
    if open then
        rows[#rows + 1] = { kind = "text", text = SB.SpellDescription(sid) or "No description.", indent = 34 }
        rows[#rows + 1] = { kind = "line", text = "Wowhead link", icon = "Interface\\Icons\\INV_Misc_Note_01",
                            color = "key", onClick = function() SB.ShowLink("spell", sid, name) end }
    end
end

local function NpcAbilities(id)
    local rows = {}
    local m = SB.db.mobs[id] or {}
    local seen, names = m.s or {}, {}
    rows[#rows + 1] = Header("Abilities")
    for _, sid in ipairs(SB.GetSpells(id)) do
        local name, icon = SB.SpellInfo(sid)
        if name and not names[name] then
            names[name] = true
            SpellRows(rows, sid, name, icon, seen[sid])
        end
    end
    local mine = {}
    for sid, count in pairs(seen) do
        local name, icon = SB.SpellInfo(sid)
        if name and not names[name] then names[name] = true; mine[#mine + 1] = { sid, name, icon, count } end
    end
    if #mine > 0 then
        table.sort(mine, function(a, b) return a[2] < b[2] end)
        rows[#rows + 1] = Header("Seen by you")
        for _, s in ipairs(mine) do SpellRows(rows, s[1], s[2], s[3], s[4]) end
    end
    if #rows == 1 then
        rows[#rows + 1] = Note("No abilities known yet. Fight it: every spell you see it cast is recorded here.")
    else
        rows[#rows + 1] = Note("Click an ability for its description.")
    end
    return rows
end

local function SeenWhen(t) return t and date("%d %b %Y", t) or nil end

local function NpcSells(id)
    local list, src, t = SB.Sells(id)
    local rows = { Header("Sells", tostring(#list)) }
    for _, e in ipairs(list) do
        local right = {}
        if e.stack and e.stack > 1 then right[#right + 1] = "x" .. e.stack end
        if e.limited then right[#right + 1] = "limited" end
        rows[#rows + 1] = ItemRow(e.item, e.price and e.price > 0 and SB.Money(e.price) or nil,
            #right > 0 and table.concat(right, ", ") or nil)
    end
    rows[#rows + 1] = Note(src == "game" and ("As you saw it on " .. SeenWhen(t) .. ". Visiting again refreshes it.")
        or "From Questie's database. Open this vendor in the game to see prices and stock.")
    return rows
end

local GOOD, BAD = "|cff40e040", "|cffff4040"

local function NpcTeaches(id)
    local list, src, t = SB.Teaches(id)
    local rows = { Header("Teaches", tostring(#list)) }
    local level = UnitLevel("player") or 1
    local money = GetMoney and GetMoney() or nil

    -- your rank in each skill these need, as bars on top
    local skills, order = {}, {}
    for _, e in ipairs(list) do
        if (e.skill or 0) > 0 or e.skillLine and e.skillLine > 0 then
            local key = (e.skillLine and e.skillLine > 0 and e.skillLine) or e.skillName
            if key and not skills[key] then
                local rank, max, name = SB.PlayerSkill(e.skillLine, e.skillName)
                skills[key] = { rank = rank, max = max, name = name }
                order[#order + 1] = key
            end
        end
    end
    for _, key in ipairs(order) do
        local sk = skills[key]
        rows[#rows + 1] = { kind = "bar", text = "Your " .. sk.name, value = sk.rank, max = sk.max, missing = "Not learned" }
    end

    for _, e in ipairs(list) do
        local name, icon = e.name, e.icon
        if e.spell then
            local n2, i2 = SB.SpellInfo(e.spell)
            name, icon = name or n2, icon or i2
        end
        name = (name or ("Spell " .. tostring(e.spell))) .. (e.rank and (" (" .. e.rank .. ")") or "")
        local needs = {}
        if e.level and e.level > 1 then
            needs[#needs + 1] = (level >= e.level and GOOD or BAD) .. "level " .. e.level .. "|r"
        end
        if e.skill and e.skill > 0 then
            local key = (e.skillLine and e.skillLine > 0 and e.skillLine) or e.skillName
            local sk = key and skills[key] or { name = e.skillName or "skill" }
            local ok = sk.rank and sk.rank >= e.skill
            needs[#needs + 1] = (ok and GOOD or BAD) .. sk.name .. " " .. e.skill .. "|r"
        end
        local sub = #needs > 0 and ("Requires " .. table.concat(needs, ", ")) or "No requirements"
        if e.used then sub = GOOD .. "Already known|r" end
        local cost
        if e.cost and e.cost > 0 then
            cost = SB.Money(e.cost)
            if money and money < e.cost and not e.used then cost = BAD .. cost .. "|r" end
        end
        local spell = e.spell
        rows[#rows + 1] = { kind = "teach", id = spell, icon = icon or "Interface\\Icons\\INV_Misc_Book_09", text = name,
                            sub = sub, mid = cost, faded = e.used,
                            onClick = spell and function() SB.ShowLink("spell", spell, name) end or nil }
    end
    rows[#rows + 1] = Note(src == "game" and ("As you saw it on " .. SeenWhen(t) .. ". Visiting again refreshes it.")
        or "Classic trainer list. Open this trainer in the game to see exactly what it teaches on Forever.")
    return rows
end

local function NpcQuests(id, n)
    local rows = {}
    local active = SB.QuestLog.ForNpc(id)
    if #active > 0 then
        rows[#rows + 1] = Header("On your quests")
        for _, r in ipairs(active) do
            local what = r.kind == "loot" and (SB.GetItem(r.item).name .. " " .. SB.Percent(r.chance))
                or (r.kind == "kill" and "kill") or "shown by the game"
            rows[#rows + 1] = QuestRow(r.entry.id, SB.QuestLog.ObjectiveText(r.objective), what)
        end
    end
    local needed, seen = {}, {}
    for _, q in ipairs(SB.KillFor(id)) do
        if not SB.QuestLog.IsActive(q) and not seen[q] then seen[q] = true; needed[#needed + 1] = { q = q, what = "kill" } end
    end
    for _, d in ipairs(SB.DropFor(id)) do
        if not SB.QuestLog.IsActive(d.quest) and not seen[d.quest] then
            seen[d.quest] = true
            needed[#needed + 1] = { q = d.quest, what = SB.GetItem(d.item).name }
        end
    end
    for q in pairs((SB.db.mobs[id] or {}).q or {}) do
        if not SB.QuestLog.IsActive(q) and not seen[q] then seen[q] = true; needed[#needed + 1] = { q = q, what = "seen in game" } end
    end
    if #needed > 0 then
        rows[#rows + 1] = Header("Needed for")
        for _, e in ipairs(needed) do rows[#rows + 1] = QuestRow(e.q, nil, e.what) end
    end
    if n and #n.starts > 0 then
        rows[#rows + 1] = Header("Starts")
        for _, q in ipairs(n.starts) do rows[#rows + 1] = QuestRow(q) end
    end
    if n and #n.ends > 0 then
        rows[#rows + 1] = Header("Turn in here")
        for _, q in ipairs(n.ends) do rows[#rows + 1] = QuestRow(q) end
    end
    if #rows == 0 then rows[1] = Note("No quests involve this mob.") end
    return rows
end

------------------------------------------------------------------------------
-- Right page: items
------------------------------------------------------------------------------

local function RecipeRows(rows, recipes)
    for _, r in ipairs(recipes) do
        local title = (r.profession or "Crafted") .. (r.skill and (" (" .. r.skill .. ")") or "")
        rows[#rows + 1] = { kind = "header", text = title, icon = r.icon,
                            right = (r.qmax and r.qmax > 1) and ("makes " .. (r.qmin == r.qmax and r.qmax or (r.qmin .. "-" .. r.qmax))) or nil }
        if r.name then rows[#rows + 1] = KV("Recipe", r.name) end
        if r.source then rows[#rows + 1] = KV("Learned", r.source) end
        if r.grey then rows[#rows + 1] = KV("Turns grey at", tostring(r.grey)) end
        rows[#rows + 1] = KV("Known by", #r.known > 0 and table.concat(r.known, ", ") or "none of your characters")
        for _, rg in ipairs(r.reagents) do
            rows[#rows + 1] = ItemRow(rg[1], "x" .. rg[2])
        end
    end
end

local function ItemOverview(id)
    local it = SB.GetItem(id)
    local rows = { Header("Overview") }
    if it.quality then rows[#rows + 1] = KV("Quality", SB.QUALITY_NAMES[it.quality] or "?") end
    if it.ilvl and it.ilvl > 0 then rows[#rows + 1] = KV("Item level", tostring(it.ilvl)) end
    if it.req and it.req > 0 then rows[#rows + 1] = KV("Requires level", tostring(it.req)) end
    rows[#rows + 1] = KV("Item ID", tostring(id))
    local recipes = SB.Crafting.ForItem(id)
    if #recipes > 0 then
        rows[#rows + 1] = Header("Crafted", "details on the Crafted tab")
        for _, r in ipairs(recipes) do
            rows[#rows + 1] = KV(r.profession or "?", (r.skill and ("skill " .. r.skill .. ", ") or "") .. SB.Plural(#r.reagents, "reagent"))
        end
    end
    local total, list = SB.GetDroppedBy(id)
    if total > 0 then
        rows[#rows + 1] = Header("Top sources", "all " .. total .. " on Dropped by")
        for i = 1, math.min(4, #list) do rows[#rows + 1] = NpcRow(list[i].npc, "npc", { mid = ChanceText(list[i]) }) end
    end
    local src = SB.YourItemSources(id)
    if #src > 0 then
        rows[#rows + 1] = Header("You looted it from")
        for _, s in ipairs(src) do
            rows[#rows + 1] = NpcRow(s.npc, "npc", { mid = SB.Percent(s.count / math.max(1, s.corpses) * 100),
                right = ("%d of %d corpses"):format(s.count, s.corpses) })
        end
    end
    local usedIn = SB.Crafting.UsedIn(id)
    if #usedIn > 0 then
        rows[#rows + 1] = Header("Reagent for", tostring(#usedIn))
        for _, u in ipairs(usedIn) do
            if u.output then rows[#rows + 1] = ItemRow(u.output, "x" .. u.count, nil, u.profession) end
        end
    end
    local uses = SB.GetItemUses(id)
    if #uses.containers > 0 then
        rows[#rows + 1] = Header("Found inside")
        for _, c in ipairs(uses.containers) do rows[#rows + 1] = ItemRow(c) end
    end
    if uses.objects > 0 then rows[#rows + 1] = Note(("Also found in %d kinds of world objects (chests, herbs, veins...)."):format(uses.objects)) end
    if total == 0 and #recipes == 0 and #src == 0 and uses.vendorCount == 0 then
        rows[#rows + 1] = Note("No source known yet. If it's crafted, open that profession on any character (or someone's profession link) and its recipe is read from the game.")
    end
    return rows
end

local function ItemDroppedBy(id)
    local total, list = SB.GetDroppedBy(id)
    local rows = { Header("Dropped by", tostring(total)) }
    local yours = {}
    for _, s in ipairs(SB.YourItemSources(id)) do yours[s.npc] = s end
    for _, d in ipairs(list) do
        local y = yours[d.npc]
        rows[#rows + 1] = NpcRow(d.npc, "npc", { mid = ChanceText(d),
            right = y and ("you %d of %d"):format(y.count, y.corpses) or nil })
    end
    for _, s in ipairs(SB.YourItemSources(id)) do
        local listed = false
        for _, d in ipairs(list) do if d.npc == s.npc then listed = true end end
        if not listed then rows[#rows + 1] = NpcRow(s.npc, "npc", { mid = "seen by you", right = ("you %d of %d"):format(s.count, s.corpses) }) end
    end
    if #rows == 1 then rows[#rows + 1] = Note("No mob is known to drop this item.") end
    return rows
end

local function ItemCrafted(id)
    local rows = {}
    local recipes = SB.Crafting.ForItem(id)
    RecipeRows(rows, recipes)
    if #recipes == 0 then
        rows[1] = Note("No recipe known for this item yet.")
        rows[2] = Note("Recipes are read from the game: open a profession window on any of your characters, or click someone's profession link in chat, and every recipe in it is saved for your whole account.")
        rows[3] = Note(("Recipes read so far: %d."):format(SB.Crafting.Count()))
    end
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
        rows[#rows + 1] = Header("Needed for", tostring(#uses.objectiveOf))
        for _, q in ipairs(uses.objectiveOf) do rows[#rows + 1] = QuestRow(q) end
    end
    if #uses.rewardOf > 0 then
        rows[#rows + 1] = Header("Reward from", tostring(#uses.rewardOf))
        for _, q in ipairs(uses.rewardOf) do rows[#rows + 1] = QuestRow(q) end
    end
    if #rows == 0 then rows[1] = Note("No quests use this item.") end
    return rows
end

local function ItemVendors(id)
    local uses = SB.GetItemUses(id)
    local rows = {}
    if uses.vendorCount > 0 then
        rows[#rows + 1] = Header("Sold by", tostring(uses.vendorCount))
        for _, v in ipairs(uses.vendors) do rows[#rows + 1] = NpcRow(v, "npc") end
    else
        rows[1] = Note("No vendor sells this item.")
    end
    return rows
end

------------------------------------------------------------------------------
-- Right page: instances
------------------------------------------------------------------------------

local function InstanceOverview(map)
    local inst = SB.GetInstance(map)
    if not inst then return { Note("Unknown instance.") } end
    local rows = {}
    if inst.art and inst.art.description and inst.art.description ~= "" then
        rows[#rows + 1] = { kind = "text", text = inst.art.description }
    end
    rows[#rows + 1] = Header("Overview")
    rows[#rows + 1] = KV("Type", inst.raid and "Raid" or "Dungeon")
    if inst.minLevel then rows[#rows + 1] = KV("Mob levels", inst.minLevel .. " - " .. inst.maxLevel) end
    rows[#rows + 1] = KV("Bosses", tostring(#inst.bosses))
    rows[#rows + 1] = KV("Inhabitants", tostring(#inst.mobs))
    local kills = 0
    for _, id in ipairs(inst.bosses) do kills = kills + ((SB.db.mobs[id] or {}).k or 0) end
    rows[#rows + 1] = KV("Boss kills by you", tostring(kills))
    if #inst.bosses > 0 then
        rows[#rows + 1] = Header("Bosses")
        for _, id in ipairs(inst.bosses) do rows[#rows + 1] = NpcRow(id, "npc") end
    end
    return rows
end

local function InstanceLoot(map)
    local inst = SB.GetInstance(map)
    local rows = {}
    if not inst then return rows end
    for _, boss in ipairs(inst.bosses) do
        local loot = SB.GetLoot(boss)
        local list = {}
        for _, d in ipairs(loot) do
            if d.quest or (SB.GetItem(d.item).quality or 1) >= 2 then list[#list + 1] = d end
        end
        if #list > 0 then
            rows[#rows + 1] = Header(SB.NpcName(boss), tostring(#list))
            for _, d in ipairs(list) do rows[#rows + 1] = ItemRow(d.item, ChanceText(d)) end
        end
    end
    if #rows == 0 then rows[1] = Note("No boss loot known.") end
    return rows
end

------------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------------

local NPC_TABS = {
    { key = "overview", tip = "Overview", off = "TabBossOff", on = "TabBossOn" },
    { key = "loot", tip = "Loot", off = "TabLootOff", on = "TabLootOn" },
    { key = "abilities", tip = "Abilities", off = "TabAbilitiesOff", on = "TabAbilitiesOn" },
    { key = "sells", tip = "Sells", icon = "Interface\\Icons\\INV_Misc_Bag_10", when = function(id) return #SB.Sells(id) > 0 end },
    { key = "teaches", tip = "Teaches", icon = "Interface\\Icons\\INV_Misc_Book_11", when = function(id) return #SB.Teaches(id) > 0 end },
    { key = "model", tip = "Model", off = "TabModelOff", on = "TabModelOn" },
    { key = "quests", tip = "Quests", icon = "Interface\\Icons\\INV_Misc_Book_08" },
    { key = "notes", tip = "Your notes", icon = "Interface\\Icons\\INV_Misc_Note_01" },
}

local TABS = {
    item = {
        { key = "overview", tip = "Overview", off = "TabLootOff", on = "TabLootOn" },
        { key = "droppedby", tip = "Dropped by", off = "TabBossOff", on = "TabBossOn" },
        { key = "crafted", tip = "Crafted", icon = "Interface\\Icons\\Trade_BlackSmithing" },
        { key = "quests", tip = "Quests", icon = "Interface\\Icons\\INV_Misc_Book_08" },
        { key = "vendors", tip = "Sold by", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    },
    instance = {
        { key = "overview", tip = "Overview", off = "TabBossOff", on = "TabBossOn" },
        { key = "loot", tip = "Loot", off = "TabLootOff", on = "TabLootOn" },
    },
}

local function TabsFor(page)
    if not page then return {} end
    if page.kind ~= "npc" then return TABS[page.kind] or {} end
    local out = {}
    for _, t in ipairs(NPC_TABS) do
        if not t.when or t.when(page.id) then out[#out + 1] = t end
    end
    return out
end

local function DrawTabs()
    local tabs = TabsFor(state.page)
    local valid = false
    for _, t in ipairs(tabs) do if t.key == state.tab then valid = true end end
    if not valid then state.tab = "overview" end
    for i, b in ipairs(ui.sideTabs) do
        local t = tabs[i]
        b.def = t
        if t and ui.book:IsShown() then
            b:Show()
            local on = t.key == state.tab
            Skin.Apply(b.bg, on and "TabSelected" or "TabUnselected")
            if t.off then
                b.icon:SetTexture(nil)
                Skin.Apply(b.icon, on and t.on or t.off)
                b.icon:SetSize(48, 43)
                b.icon:SetDesaturated(false)
            else
                b.icon:SetTexture(t.icon)
                b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                b.icon:SetSize(26, 26)
                b.icon:SetDesaturated(not on)
                b.icon:SetAlpha(on and 1 or 0.75)
            end
        else
            b:Hide()
        end
    end
end

------------------------------------------------------------------------------
-- Page header (right page) and model
------------------------------------------------------------------------------

local function Difficulty(level)
    local f = GetCreatureDifficultyColor or GetQuestDifficultyColor
    if f and level and level > 0 then
        local ok, c = pcall(f, level)
        if ok and type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    end
end

local function DrawHeader()
    local p = state.page
    local title, sub = "", ""
    ui.pin:Hide()
    if p.kind == "npc" then
        local n = SB.GetNpc(p.id)
        title = n and n.name or SB.unitNames[p.id] or ("NPC " .. p.id)
        local parts = {}
        if n then
            if n.sub then parts[#parts + 1] = "<" .. n.sub .. ">" end
            parts[#parts + 1] = "Level " .. SB.LevelText(n)
            local cls = SB.Classification(n)
            if cls then parts[#parts + 1] = cls end
            if n.type > 0 and n.type ~= 10 then parts[#parts + 1] = SB.TYPES[n.type] end
            local zones = {}
            for i, z in ipairs(n.zones) do if i <= 2 then zones[#zones + 1] = SB.ZoneName(z.area) end end
            if #zones > 0 then parts[#parts + 1] = table.concat(zones, ", ") .. (#n.zones > 2 and "..." or "") end
            ui.pin:SetShown(n.zones[1] and n.zones[1].x and true or false)
        end
        sub = table.concat(parts, " · ")
    elseif p.kind == "item" then
        local it = SB.GetItem(p.id)
        title = SB.ItemText(p.id, true)
        local parts = {}
        if it.ilvl and it.ilvl > 0 then parts[#parts + 1] = "Item level " .. it.ilvl end
        if it.req and it.req > 1 then parts[#parts + 1] = "Requires level " .. it.req end
        local recipes = SB.Crafting.ForItem(p.id)
        if recipes[1] then parts[#parts + 1] = "Crafted: " .. (recipes[1].profession or "?") end
        sub = table.concat(parts, " · ")
    elseif p.kind == "instance" then
        local inst = SB.GetInstance(p.id)
        title = inst and inst.name or "?"
        sub = inst and ((inst.raid and "Raid" or "Dungeon") .. (inst.minLevel and (" · Levels " .. inst.minLevel .. "-" .. inst.maxLevel) or "")
            .. " · " .. SB.Plural(#inst.bosses, "boss", "bosses")) or ""
    end
    ui.rightTitle:SetText(title)
    if p.kind ~= "item" then Skin.Color(ui.rightTitle, "title") end
    ui.rightSub:SetText(sub)
    Skin.Color(ui.rightSub, "text")
    ui.rightSubBg:SetShown(sub ~= "")
    ui.wowhead:SetShown(p.kind ~= "instance")
    ui.back:SetEnabled(#state.history > 0)
end

local function ShowModel(n)
    local v = ui.modelView
    v:Show()
    v.name:SetText(n and n.name or "")
    v.model:ClearModel()
    local ok = false
    if n and n.display and n.display > 0 and v.model.SetDisplayInfo then
        ok = pcall(v.model.SetDisplayInfo, v.model, n.display)
    elseif n and v.model.SetCreature then
        ok = pcall(v.model.SetCreature, v.model, n.id)
    end
    v.none:SetShown(not ok)
    if ok then
        if v.model.SetPortraitZoom then pcall(v.model.SetPortraitZoom, v.model, 0) end
        if v.model.SetCamDistanceScale then pcall(v.model.SetCamDistanceScale, v.model, 1.15) end
        v.rotation = 0.5
        if v.model.SetRotation then pcall(v.model.SetRotation, v.model, v.rotation) end
    end
end

------------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------------

local function Breadcrumb()
    local parts = {}
    local mode = state.mode
    if mode == "instance" then
        local inst = SB.GetInstance(state.instance)
        parts[#parts + 1] = inst and inst.raid and "Raids" or "Dungeons"
        parts[#parts + 1] = inst and inst.name or "?"
    else
        for _, t in ipairs(BOTTOM_TABS) do if t.key == mode then parts[#parts + 1] = t.label end end
        if mode == "search" then parts[#parts + 1] = "Search: " .. (state.query or "") end
    end
    local p = state.page
    if p and p.kind ~= "instance" and mode ~= "dungeons" and mode ~= "raids" and mode ~= "settings" then
        parts[#parts + 1] = p.kind == "npc" and SB.NpcName(p.id) or SB.GetItem(p.id).name
    end
    return table.concat(parts, "  >  ")
end

local function DrawBottomTabs()
    local active = state.mode
    if active == "instance" then
        local inst = SB.GetInstance(state.instance)
        active = inst and inst.raid and "raids" or "dungeons"
    end
    for i, t in ipairs(BOTTOM_TABS) do
        if t.key == active then
            if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, ui, i) end
            ui.selectedTab = i
        end
    end
    for _, b in ipairs(ui.bottomTabs) do
        if b.plain then b.sel:SetShown(b.id == ui.selectedTab) end
    end
end

local function GridRows(raid)
    local rows, row = {}, nil
    local perRow = math.max(2, math.floor(((ui.gridList.width or 775) - 10) / 188))
    for _, inst in ipairs(SB.Instances(raid)) do
        if not row or #row.tiles == perRow then
            row = { kind = "tiles", tiles = {}, perRow = perRow }
            rows[#rows + 1] = row
        end
        local first = inst.bosses[1] and SB.GetNpc(inst.bosses[1])
        local map = inst.map
        row.tiles[#row.tiles + 1] = {
            text = inst.name, sub = inst.minLevel and ("Levels " .. inst.minLevel .. "-" .. inst.maxLevel) or "",
            art = inst.art and inst.art.button, portrait = first and first.display, icon = NPC_ICON.boss,
            onClick = function() SB.OpenInstance(map) end,
            tooltip = function(tt)
                tt:AddLine(inst.name, 1, 1, 1)
                if inst.minLevel then tt:AddLine("Mob levels " .. inst.minLevel .. "-" .. inst.maxLevel, 1, 0.82, 0) end
                tt:AddLine(SB.Plural(#inst.bosses, "boss", "bosses") .. ", " .. SB.Plural(#inst.mobs, "inhabitant"), 0.8, 0.8, 0.8)
            end,
        }
    end
    if #rows == 0 then rows[1] = Note(SB.index.ready and "No instances known." or "Reading the database...") end
    return rows
end

local function DrawPageNow(keep)
    if not ui then return end
    local mode = state.mode
    ui.nav:SetText(Breadcrumb())
    DrawBottomTabs()
    ui.grid:Hide(); ui.settingsPage:Hide(); ui.book:Hide()
    if mode == "settings" then
        ui.settingsPage:Show()
        ui.settingsPage:Refresh()
        DrawTabs()
        return
    end
    if mode == "dungeons" or mode == "raids" then
        ui.grid:Show()
        ui.gridTitle:SetText(mode == "raids" and "Raids" or "Dungeons")
        ui.gridList:SetRows(GridRows(mode == "raids"), keep)
        DrawTabs()
        return
    end
    ui.book:Show()
    DrawList(keep)
    local p = state.page
    ui.modelView:Hide(); ui.notes:Hide(); ui.content:Hide()
    if not p then
        ui.rightTitle:SetText("Total Intel")
        Skin.Color(ui.rightTitle, "title")
        ui.rightSub:SetText("")
        ui.rightSubBg:Hide()
        ui.wowhead:Hide(); ui.pin:Hide()
        ui.content:Show()
        ui.content:SetRows({
            Header("Welcome"),
            { kind = "text", text = "Pick a mob on the left, or open Dungeons and Raids below." },
            { kind = "text", text = "Search (top right) finds any mob, NPC or item by name or ID, whether you've seen it or not. /tits <name> does the same." },
            { kind = "text", text = "Alt-click any mob in the world, a nameplate, your target frame, or any item, to open it here." },
            { kind = "text", text = "Inside dungeons and raids the game hides which mob you're looking at from addons, so use the Dungeons and Raids pages there." },
        })
        DrawTabs()
        return
    end
    DrawHeader()
    DrawTabs()
    local rows
    if p.kind == "npc" then
        local n = SB.GetNpc(p.id)
        if state.tab == "model" then ShowModel(n) return end
        if state.tab == "notes" then
            ui.notes:Show()
            local m = SB.db.mobs[p.id]
            ui.notes.edit:SetText(m and m.n or "")
            Skin.Color(ui.notes.edit, "text")
            return
        end
        if state.tab == "loot" then rows = NpcLoot(p.id, n)
        elseif state.tab == "sells" then rows = NpcSells(p.id)
        elseif state.tab == "teaches" then rows = NpcTeaches(p.id)
        elseif state.tab == "abilities" then rows = NpcAbilities(p.id)
        elseif state.tab == "quests" then rows = NpcQuests(p.id, n)
        else rows = NpcOverview(p.id, n) end
    elseif p.kind == "item" then
        if state.tab == "droppedby" then rows = ItemDroppedBy(p.id)
        elseif state.tab == "crafted" then rows = ItemCrafted(p.id)
        elseif state.tab == "quests" then rows = ItemQuests(p.id)
        elseif state.tab == "vendors" then rows = ItemVendors(p.id)
        else rows = ItemOverview(p.id) end
    else
        if state.tab == "loot" then rows = InstanceLoot(p.id) else rows = InstanceOverview(p.id) end
    end
    ui.content:Show()
    ui.content:SetRows(rows, keep)
end

-- A page that fails to draw is reported (once) instead of leaving a silent, half-empty window.
local reported = {}
function DrawPage(keep)
    local ok, err = pcall(DrawPageNow, keep)
    if ok then return end
    SB.Error("window", err)
    if not reported[tostring(err)] then
        reported[tostring(err)] = true
        SB.Print("|cffff5555couldn't draw this page.|r Type |cffffd100/tits status|r and send the error to the author.")
    end
end

function SB.Redraw(keep) DrawPage(keep) end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function TabButton(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(63, 57)
    b:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
    b.bg = Skin.New(b, "TabUnselected", "BACKGROUND")
    b.bg:SetAllPoints()
    local hl = Skin.New(b, "TabHighlight", "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetPoint("CENTER", 4, 0)
    b:SetScript("OnClick", function(self)
        if not self.def then return end
        state.tab = self.def.key
        DrawPage()
    end)
    b:SetScript("OnEnter", function(self)
        if self.def then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.def.tip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function CreateUI()
    local tpl
    ui, tpl = W.CreateWithTemplate("Frame", "TotalIntelFrame", UIParent, { "PortraitFrameTemplate", "ButtonFrameTemplate", "BasicFrameTemplateWithInset" })
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
    tinsert(UISpecialFrames, "TotalIntelFrame")
    if ui.SetTitle then ui:SetTitle(SB.TITLE) else
        local t = Text(ui, "GameFontNormal"); t:SetPoint("TOP", 0, -5); t:SetText(SB.TITLE)
    end
    if ui.SetPortraitToAsset then pcall(ui.SetPortraitToAsset, ui, SB.ICON)
    elseif ui.PortraitContainer and ui.PortraitContainer.portrait then ui.PortraitContainer.portrait:SetTexture(SB.ICON) end
    if ui.Inset then ui.Inset:Hide() end
    if not tpl then
        local bg = ui:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.06, 0.97)
    end

    -- navigation bar
    ui.back = CreateFrame("Button", nil, ui)
    ui.back:SetSize(28, 28)
    ui.back:SetPoint("TOPLEFT", 62, -30)
    ui.back:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    ui.back:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    ui.back:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    ui.back:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    ui.back:SetScript("OnClick", function() SB.Back() end)
    ui.back:SetScript("OnEnter", function(self) W.Tooltip(self, "Back") end)
    ui.back:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.nav = Text(ui, "GameFontNormal")
    ui.nav:SetPoint("LEFT", ui.back, "RIGHT", 6, 0)
    ui.nav:SetPoint("RIGHT", ui, "TOPRIGHT", -260, -44)
    ui.nav:SetJustifyH("LEFT")
    ui.nav:SetWordWrap(false)

    ui.search = W.Input(ui, 240, "Search mobs, NPCs and items")
    ui.search:SetPoint("TOPRIGHT", -20, -34)
    ui.search:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        local text = self:GetText() or ""
        if #text >= 2 then
            state.mode, state.query = "search", text
            DrawPage()
        end
    end)
    ui.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        for _, row in ipairs(ui.leftList.rows) do
            if row.onClick then row.onClick(row) break end
        end
    end)

    -- the open book
    local info = CreateFrame("Frame", nil, ui)
    info:SetPoint("TOPLEFT", 14, -TOP)
    info:SetPoint("BOTTOMRIGHT", -1, 2)
    local bg = Skin.New(info, "JournalBG", "BACKGROUND")
    bg:SetAllPoints()
    ui.info = info

    local book = CreateFrame("Frame", nil, info)
    book:SetAllPoints()
    ui.book = book

    local left = CreateFrame("Frame", nil, book)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    ui.left = left
    local lh = Skin.New(left, "LeftPageHeader", "BACKGROUND", 3)
    lh:SetPoint("TOPLEFT", 0, -11)
    lh:SetPoint("RIGHT", -6, 0)
    lh:SetHeight(39)
    ui.leftTitle = Text(left, "GameFontNormalLarge")
    ui.leftTitle:SetPoint("TOPLEFT", 32, -24)
    ui.leftTitle:SetPoint("RIGHT", -70, 0)
    ui.leftTitle:SetJustifyH("LEFT")
    ui.leftTitle:SetWordWrap(false)
    Skin.Color(ui.leftTitle, "title")
    ui.leftCount = Text(left, "GameFontNormal")
    ui.leftCount:SetPoint("TOPRIGHT", -34, -26)
    Skin.Color(ui.leftCount, "title")
    ui.leftList = W.Flow(left)
    ui.leftList:SetPoint("TOPLEFT", 16, -60)
    ui.leftList:SetPoint("BOTTOMRIGHT", -22, 12)


    local right = CreateFrame("Frame", nil, book)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetPoint("LEFT", left, "RIGHT")
    ui.right = right
    local rh = Skin.New(right, "RightPageHeader", "BACKGROUND", 3)
    rh:SetPoint("TOPRIGHT", 0, -11)
    rh:SetPoint("LEFT", 6, 0)
    rh:SetHeight(39)
    ui.rightTitle = Text(right, "GameFontNormalLarge")
    ui.rightTitle:SetPoint("TOPLEFT", 34, -24)
    ui.rightTitle:SetPoint("RIGHT", -230, 0)
    ui.rightTitle:SetJustifyH("LEFT")
    ui.rightTitle:SetWordWrap(false)
    ui.rightSub = Text(right, W.Font("GameFontBlackMedium", W.Font("GameFontBlack", "GameFontHighlight")))
    ui.rightSub:SetPoint("TOPLEFT", 34, -60)
    ui.rightSub:SetPoint("RIGHT", -24, 0)
    ui.rightSub:SetJustifyH("LEFT")
    ui.rightSub:SetMaxLines(1)
    ui.rightSubBg = Skin.Paper(right, "BACKGROUND", 4)
    ui.rightSubBg:SetPoint("TOPLEFT", ui.rightSub, "TOPLEFT", -6, 4)
    ui.rightSubBg:SetPoint("BOTTOMRIGHT", ui.rightSub, "BOTTOMRIGHT", 6, -4)
    ui.wowhead = Button(right, "Wowhead", 92, 22, function()
        local p = state.page
        if p then SB.ShowLink(p.kind, p.id, p.kind == "npc" and SB.NpcName(p.id) or SB.GetItem(p.id).name) end
    end)
    ui.wowhead:SetPoint("TOPRIGHT", -18, -19)
    ui.pin = Button(right, "Map pin", 84, 22, function()
        if state.page and state.page.kind == "npc" then SB.SetWaypoint(state.page.id) end
    end)
    ui.pin:ClearAllPoints()
    ui.pin:SetPoint("RIGHT", ui.wowhead, "LEFT", -4, 0)
    ui.content = W.Flow(right)
    ui.content:SetPoint("TOPLEFT", 28, -84)
    ui.content:SetPoint("BOTTOMRIGHT", -12, 12)


    -- model view, like the journal's model tab
    local mv = CreateFrame("Frame", nil, right)
    mv:SetAllPoints()
    mv:SetFrameLevel(right:GetFrameLevel() + 5)
    local mbg = Skin.New(mv, "DungeonBG", "BACKGROUND", 1)
    mbg:SetAllPoints()
    local okModel, model = pcall(CreateFrame, "PlayerModel", nil, mv)
    if not okModel then model = CreateFrame("Frame", nil, mv) end
    model:SetPoint("TOPLEFT", 4, -4)
    model:SetPoint("BOTTOMRIGHT", -4, 4)
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        mv.rotation = (mv.rotation or 0) + (x - self.dragX) / 80
        self.dragX = x
        if self.SetRotation then pcall(self.SetRotation, self, mv.rotation) end
    end)
    mv.model = model
    if not model.ClearModel then model.ClearModel = function() end end
    local paper = Skin.New(mv, "ModelPaperFrame", "OVERLAY")
    paper:SetAllPoints()
    local shadow = Skin.New(mv, "BossNameShadow", "OVERLAY", 1, true)
    shadow:SetPoint("BOTTOM", 0, -2)
    mv.name = Text(mv, "GameFontNormalLarge", "OVERLAY")
    mv.name:SetPoint("BOTTOM", 0, 26)
    mv.name:SetTextColor(1, 0.92, 0.75)
    mv.none = Text(mv, "GameFontHighlight", "OVERLAY")
    mv.none:SetPoint("CENTER")
    mv.none:SetText("No model for this mob.")
    local hint = Text(mv, "GameFontHighlightSmall", "OVERLAY")
    hint:SetPoint("TOP", 0, -20)
    hint:SetText("Drag to turn")
    hint:SetTextColor(0.85, 0.8, 0.7)
    mv:Hide()
    ui.modelView = mv

    -- notes view
    local notes = CreateFrame("Frame", nil, right)
    notes:SetPoint("TOPLEFT", 28, -84)
    notes:SetPoint("BOTTOMRIGHT", -12, 12)
    local nh = CreateFrame("Frame", nil, notes)
    nh:SetPoint("TOPLEFT"); nh:SetPoint("TOPRIGHT"); nh:SetHeight(26)
    Skin.PaperHeader(nh, false)
    local nt = Text(nh, "GameFontNormal")
    nt:SetPoint("LEFT", 12, 0)
    nt:SetText("Your notes (saved for all your characters)")
    local scroll = W.Scroll(notes)
    scroll:SetPoint("TOPLEFT", 8, -36)
    scroll:SetPoint("BOTTOMRIGHT", 0, 6)
    local paper = Skin.Paper(notes)
    paper:SetPoint("TOPLEFT", 0, -30)
    paper:SetPoint("BOTTOMRIGHT")
    local eb = CreateFrame("EditBox", nil, scroll.child)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(W.Font("GameFontBlackMedium", W.Font("GameFontBlack", "ChatFontNormal")))
    eb:SetWidth(340)
    eb:SetPoint("TOPLEFT")
    eb:SetMaxLetters(2000)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnTextChanged", function(self, user)
        scroll.child:SetHeight(math.max(200, (self:GetHeight() or 200)))
        if not user or not state.page or state.page.kind ~= "npc" then return end
        local text = self:GetText() or ""
        local m = SB.Mob(state.page.id, text ~= "")
        if m then m.n = text ~= "" and text or nil end
    end)
    scroll.child:SetWidth(340)
    scroll.child:SetHeight(200)
    notes:EnableMouse(true)
    notes:SetScript("OnMouseDown", function() eb:SetFocus() end)
    notes.edit = eb
    notes:Hide()
    ui.notes = notes

    -- side tabs, hanging off the right edge like the journal's
    ui.sideTabs = {}
    for i = 1, 8 do
        local b = TabButton(ui, i)
        if i == 1 then b:SetPoint("TOPLEFT", ui, "TOPRIGHT", -8, -104)
        else b:SetPoint("TOP", ui.sideTabs[i - 1], "BOTTOM", 0, 2) end
        ui.sideTabs[i] = b
    end

    -- instance grid (both pages)
    local grid = CreateFrame("Frame", nil, info)
    grid:SetAllPoints()
    local gh = Skin.New(grid, "LeftPageHeader", "BACKGROUND", 3)
    gh:SetPoint("TOPLEFT", 0, -11)
    gh:SetSize(386, 39)
    ui.gridTitle = Text(grid, "GameFontNormalLarge")
    ui.gridTitle:SetPoint("TOPLEFT", 26, -24)
    Skin.Color(ui.gridTitle, "title")
    ui.gridList = W.Flow(grid)
    ui.gridList:SetPoint("TOPLEFT", 4, -60)
    ui.gridList:SetPoint("BOTTOMRIGHT", -6, 8)
    grid:Hide()
    ui.grid = grid

    ui.settingsPage = SB.CreateSettingsPage(info)
    ui.settingsPage:SetAllPoints()
    ui.settingsPage:Hide()

    -- bottom tabs
    ui.bottomTabs = {}
    for i, t in ipairs(BOTTOM_TABS) do
        local b, btpl = W.CreateWithTemplate("Button", "TotalIntelFrameTab" .. i, ui, { "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate" })
        b:SetID(i)
        b.id = i
        b:SetText(t.label)
        if not btpl then
            b.plain = true
            b:SetSize(100, 28)
            local tbg = b:CreateTexture(nil, "BACKGROUND")
            tbg:SetAllPoints()
            tbg:SetColorTexture(0.12, 0.08, 0.05, 0.95)
            b.sel = b:CreateTexture(nil, "ARTWORK")
            b.sel:SetPoint("TOPLEFT"); b.sel:SetPoint("TOPRIGHT"); b.sel:SetHeight(2)
            b.sel:SetColorTexture(1, 0.6, 0.2, 1)
            b:SetNormalFontObject("GameFontNormalSmall")
        end
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
        if i == 1 then b:SetPoint("TOPLEFT", ui, "BOTTOMLEFT", 12, 2)
        else b:SetPoint("LEFT", ui.bottomTabs[i - 1], "RIGHT", btpl == "PanelTabButtonTemplate" and 3 or -14, 0) end
        b:SetScript("OnClick", function()
            if t.key == "settings" then SB.OpenSettings() return end
            state.mode = t.key
            ui.search:SetText("")
            ui.search:ClearFocus()
            if (t.key == "recent" or t.key == "zone" or t.key == "bestiary") and state.page and state.page.kind == "instance" then
                state.page = nil
            end
            DrawPage()
        end)
        ui.bottomTabs[i] = b
    end
    if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, ui, #BOTTOM_TABS) end
    ui.selectedTab = 1

    -- resizing: drag the bottom-right corner
    ui:SetResizable(true)
    if ui.SetResizeBounds then ui:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif ui.SetMinResize then ui:SetMinResize(MIN_W, MIN_H); ui:SetMaxResize(MAX_W, MAX_H) end
    local grip = CreateFrame("Button", nil, ui)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel((ui:GetFrameLevel() or 1) + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() ui:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        ui:StopMovingOrSizing()
        SB.db.window = { w = math.floor(ui:GetWidth() + 0.5), h = math.floor(ui:GetHeight() + 0.5) }
        SB.Layout()
        DrawPage(true)
    end)
    grip:SetScript("OnEnter", function(self) W.Tooltip(self, "Drag to resize") end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local saved = SB.db.window
    if saved and saved.w and saved.h then
        ui:SetSize(math.max(MIN_W, math.min(MAX_W, saved.w)), math.max(MIN_H, math.min(MAX_H, saved.h)))
    end
    local relayout
    ui:SetScript("OnSizeChanged", function()
        if relayout then return end
        relayout = true
        SB.After(0.05, function() relayout = false; SB.Layout(); if ui:IsShown() then DrawPage(true) end end)
    end)
    SB.Layout()

    ui:SetScript("OnShow", function() DrawPage(true) end)
end

-- Sizes the two pages and every list to the window.
function SB.Layout()
    if not ui then return end
    local w = (ui:GetWidth() or WIDTH) - 15
    local half = math.floor(w / 2)
    ui.left:SetWidth(half)
    ui.leftList.width = half - 38
    ui.content.width = (w - half) - 40
    ui.gridList.width = w - 10
    if ui.settingsPage.Layout then ui.settingsPage:Layout(half) end
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

SB.unitNames = {}

local function Ensure()
    if not ui then CreateUI() end
    return ui
end

local function Open(kind, id, tab)
    Ensure()
    if state.page and not (state.page.kind == kind and state.page.id == id) then
        table.insert(state.history, { page = state.page, mode = state.mode, instance = state.instance, tab = state.tab })
        if #state.history > 40 then table.remove(state.history, 1) end
    end
    if not state.page or state.page.kind ~= kind then state.tab = "overview" end
    if tab then state.tab = tab end
    state.page = { kind = kind, id = id }
    if state.mode == "settings" or state.mode == "dungeons" or state.mode == "raids" then
        state.mode = (state.instance and kind == "npc") and "instance" or "recent"
    end
    ui:Show()
    DrawPage()
end

function SB.OpenNpc(id) Open("npc", id) end

function SB.OpenItem(id)
    -- crafted items with no known drop open on their recipe
    local tab
    if SB.Crafting.ForItem(id)[1] and #SB.Droppers(id) == 0 then tab = "crafted" end
    Open("item", id, tab)
end

function SB.OpenInstance(map)
    Ensure()
    state.mode, state.instance = "instance", map
    Open("instance", map)
end

function SB.Back()
    local prev = table.remove(state.history)
    if not prev then return end
    state.page, state.mode, state.instance, state.tab = prev.page, prev.mode, prev.instance, prev.tab
    DrawPage()
end

function SB.OpenTarget(fromButton)
    local id = SB.UnitNpcId("target")
    if id then
        local name = SB.Public(UnitName("target"))
        if name then SB.unitNames[id] = name end
        SB.OpenNpc(id)
        return
    end
    local map = SB.CurrentInstance()
    if map then SB.OpenInstance(map) return end
    if fromButton then SB.Print("target a mob first.") return end
    Ensure()
    ui:Show()
    DrawPage()
end

function SB.OpenZone()
    local map = SB.CurrentInstance()
    if map then SB.OpenInstance(map) return end
    Ensure()
    state.mode = "zone"
    ui.search:SetText("")
    ui:Show()
    DrawPage()
end

function SB.OpenDungeons(raid)
    Ensure()
    state.mode = raid and "raids" or "dungeons"
    ui:Show()
    DrawPage()
end

function SB.OpenSearch(text)
    Ensure()
    state.mode, state.query = "search", text
    ui.search:SetText(text)
    ui:Show()
    DrawPage()
    -- a single match opens straight away
    local only, n = nil, 0
    for _, row in ipairs(ui.leftList.rows) do
        if row.onClick then only, n = row, n + 1 end
    end
    if n == 1 then only.onClick(only) end
end

function SB.OpenSettings()
    Ensure()
    if state.mode ~= "settings" then state.beforeSettings = state.mode end
    state.mode = "settings"
    ui:Show()
    DrawPage()
end

function SB.CloseSettings()
    state.mode = state.beforeSettings or "recent"
    if state.mode == "settings" then state.mode = "recent" end
    DrawPage(true)
end

function SB.Toggle()
    if ui and ui:IsShown() then ui:Hide() else SB.OpenTarget() end
end

function SB.IsOpen() return ui and ui:IsShown() end
function SB.CurrentPage() return state.page, state.tab end
function SB.SetTab(tab) state.tab = tab; DrawPage(true) end
function SB.SidebarRows() return ui and ui.leftList.rows end
function SB.ContentRows() return ui and ui.content.rows end
function SB.GridRows() return ui and ui.gridList.rows end

-- Re-skin after the style setting changes.
function SB.Restyle()
    if not ui then return end
    Skin.Refresh(ui)
    Skin.Color(ui.leftTitle, "title"); Skin.Color(ui.leftCount, "title"); Skin.Color(ui.gridTitle, "title")
    DrawPage(true)
end

-- Live refreshes while the window is open
local pending
local function Refresh()
    if pending then return end
    pending = true
    SB.After(0.3, function()
        pending = false
        if ui and ui:IsShown() and state.mode ~= "settings" and state.tab ~= "notes" and state.tab ~= "model" then
            DrawPage(true)
        end
    end)
end
SB.OnQuestLogChanged = Refresh
SB.OnDataChanged = Refresh
SB.OnMobChanged = function(id) if state.page and state.page.id == id then Refresh() end end
SB.OnTargetChanged = function() if state.mode == "recent" then Refresh() end end
SB.On("GET_ITEM_INFO_RECEIVED", Refresh)
SB.On("ZONE_CHANGED_NEW_AREA", function() if state.mode == "zone" then Refresh() end end)

------------------------------------------------------------------------------
-- Alt-click (configurable) to open things
------------------------------------------------------------------------------

local CLICK_MODS = {
    ["ALT"] = function() return IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() end,
    ["CTRL-ALT"] = function() return IsAltKeyDown() and IsControlKeyDown() and not IsShiftKeyDown() end,
    ["SHIFT-ALT"] = function() return IsAltKeyDown() and IsShiftKeyDown() and not IsControlKeyDown() end,
}
local function ClickModHeld()
    local check = CLICK_MODS[SB.db and SB.db.itemClick]
    return check and check() or false
end

-- Items: bags, loot, chat links, the character sheet...
SB.AddLoad(function()
    if not HandleModifiedItemClick then return end
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not ClickModHeld() then return end
        link = SB.Public(link)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then SB.OpenItem(id) end
    end)
end)

-- Mobs and NPCs: in the world, nameplates, the target and focus frames. GLOBAL_MOUSE_UP only
-- reports the click; nothing protected is touched.
local function UnitUnderMouse()
    local foci = GetMouseFoci and GetMouseFoci()
    local focus = (type(foci) == "table" and foci[1]) or (GetMouseFocus and GetMouseFocus())
    if focus and focus ~= WorldFrame then
        local unit = focus.unit or (focus.GetAttribute and focus:GetAttribute("unit"))
        if not unit and focus.GetParent then
            local parent = focus:GetParent()
            unit = parent and (parent.unit or (parent.GetAttribute and parent:GetAttribute("unit")))
        end
        if type(unit) == "string" then return unit end
    end
    -- only a click on the game world itself means "the mob under the mouse"
    if (not focus or focus == WorldFrame) and UnitExists("mouseover") then return "mouseover" end
end

SB.On("GLOBAL_MOUSE_UP", function(button)
    if button ~= "LeftButton" or not ClickModHeld() then return end
    local unit = UnitUnderMouse()
    if not unit or UnitIsPlayer(unit) then return end
    local id = SB.UnitNpcId(unit)
    if id then
        local name = SB.Public(UnitName(unit))
        if name then SB.unitNames[id] = name end
        SB.OpenNpc(id)
    elseif UnitExists(unit) and IsInInstance and IsInInstance() then
        local map = SB.CurrentInstance()
        if map then SB.OpenInstance(map) end
    end
end)
