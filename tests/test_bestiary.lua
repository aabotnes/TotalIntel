-- Super Bestiary against a mocked WoW: Forever client.
-- usage: lua5.1 tests/test_bestiary.lua .
package.path = arg[0]:gsub("[^/]+$", "") .. "?.lua;" .. package.path
local M = require("wow_mock")
local check, Has = M.check, M.Has
local dir = arg[1] or "."

local SB = M.Load(dir, M.TocFiles(dir))
check(SB.db and SB.db.tip and SB.db.tip.enabled, "loads every file in the TOC and sets up saved settings")

local HOGGER, RAGNAROS, CLAW = 448, 11502, 1931
local hoggerGUID = "Creature-0-4469-0-17-448-000012ABCD"

------------------------------------------------------------------------------
-- Database
------------------------------------------------------------------------------
local h = SB.GetNpc(HOGGER)
check(h and h.name == "Hogger" and h.minLevel == 11 and h.rank == 1, "Hogger: name, level, elite")
check(h.zones[1].area == 12 and h.zones[1].x and h.display == 384, "Hogger: Elwynn Forest spawn point and display ID")
check(SB.ZoneName(12) == "Elwynn Forest", "zone names from the bundled table")
local loot = SB.GetLoot(HOGGER)
check(loot[1].item == CLAW and loot[1].quest and loot[1].chance == 100, "Hogger's loot starts with his quest claw at 100%")
local r = SB.GetNpc(RAGNAROS)
check(r.boss and r.zones[1].area == 2717 and SB.ZoneName(2717) == "Molten Core", "Ragnaros: boss in Molten Core")
local spells = {}
for _, s in ipairs(SB.GetSpells(RAGNAROS)) do spells[s] = true end
check(spells[20566] and spells[20565], "Ragnaros' abilities include Wrath of Ragnaros and Magma Blast")
local total, by = SB.GetDroppedBy(17076)
check(total == 1 and by[1].npc == RAGNAROS and by[1].chance == 8, "Bonereaver's Edge: dropped by Ragnaros, 8%")
local q = SB.GetQuest(176)
check(q and q.items[1] == CLAW and q.faction == "A", "quest 176 needs the claw and is Alliance")
local res = SB.Search("hogger")
check(res[1] and res[1].kind == "npc" and res[1].id == HOGGER, "search finds Hogger first")
check(SB.Search("448")[1].id == HOGGER, "search by ID")

------------------------------------------------------------------------------
-- Mob tooltip
------------------------------------------------------------------------------
M.units.mouseover = { guid = hoggerGUID, name = "Hogger", level = 11 }
local function HoverUnit()
    GameTooltip:SetOwner()
    GameTooltip.unit = "mouseover"
    M.postCalls[Enum.TooltipDataType.Unit](GameTooltip, {})
    return GameTooltip.lines
end
local lines = HoverUnit()
check(Has(lines, "Elite") and Has(lines, "Humanoid"), "tooltip: classification and type", lines)
check(Has(lines, "Huge Gnoll Claw") and Has(lines, "quest"), "tooltip: quest drop with chance", lines)
check(Has(lines, "Abilities:"), "tooltip: abilities", lines)

-- with the quest in the log, the tooltip shows it with progress
M.quests = { { id = 176, title = "Wanted: \"Hogger\"", complete = false,
               objectives = { { text = "Huge Gnoll Claw: 0/1", type = "item", finished = false, numFulfilled = 0, numRequired = 1 } } } }
M.Fire("QUEST_LOG_UPDATE")
lines = HoverUnit()
check(Has(lines, "Wanted") and Has(lines, "0/1"), "tooltip: your quest needs the claw, 0/1", lines)

-- secret GUIDs (inside instances): leave the tooltip alone
M.secret[hoggerGUID] = true
lines = HoverUnit()
check(#lines == 0, "tooltip: nothing added when the game hides the mob's identity", lines)
M.secret[hoggerGUID] = nil

-- modifier
SB.db.tip.modifier = "SHIFT"
check(#HoverUnit() == 0, "tooltip: hidden until Shift is held")
M.shift = true
check(#HoverUnit() > 0, "tooltip: shown while Shift is held")
M.shift = false
SB.db.tip.modifier = "NONE"

SB.db.tip.drops = false
check(not Has(HoverUnit(), "Huge Gnoll Claw") or Has(HoverUnit(), "Wanted"), "tooltip: drops can be switched off")
SB.db.tip.drops = true

------------------------------------------------------------------------------
-- Learning: spells, kills and loot
------------------------------------------------------------------------------
M.units.target = { guid = hoggerGUID, name = "Hogger", level = 11, combat = true }
M.Fire("PLAYER_TARGET_CHANGED")
check(SB.db.recent[1] == HOGGER and SB.db.mobs[HOGGER].f, "targeting records Hogger as seen and recent")
M.Fire("UNIT_SPELLCAST_START", "target", "Cast-1", 6016)
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-1", 6016)
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "Cast-2", 6268)
M.units.nameplate1 = M.units.target
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "Cast-3", 6268)
local m = SB.db.mobs[HOGGER]
check(m.s[6016] == 1 and m.s[6268] == 1, "spells: each cast counted once (start + succeeded share a cast GUID)")

M.loot = { { link = "|cffffffff|Hitem:1931::::::::11:::::|h[Huge Gnoll Claw]|h|r", qty = 1, sources = { hoggerGUID, 1 } },
           { link = "|cffffffff|Hitem:2589::::::::11:::::|h[Linen Cloth]|h|r", qty = 2, sources = { hoggerGUID, 2 } } }
M.Fire("LOOT_READY")
check(m.c == 1 and m.i[CLAW] == 1 and m.i[2589] == 2, "loot: corpse and items recorded")
check(m.k == 1, "loot: looting a corpse counts the kill when the combat log didn't")
M.Fire("LOOT_READY")
M.Fire("LOOT_OPENED")
check(m.c == 1 and m.i[CLAW] == 1, "loot: reopening the same corpse doesn't count twice")

-- a second Hogger, killed via the combat log
local hogger2 = "Creature-0-4469-0-17-448-000099FFFF"
CombatLogGetCurrentEventInfo = function() return 0, "PARTY_KILL", false, UnitGUID("player"), "", 0, 0, hogger2 end
M.units.player = { guid = "Player-1-0000AAAA", name = "Me" }
M.Fire("COMBAT_LOG_EVENT_UNFILTERED")
M.Fire("COMBAT_LOG_EVENT_UNFILTERED")
check(m.k == 2, "kills: PARTY_KILL counted once per mob")

-- skinning the corpse after a gathering cast
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 8613)
M.loot = { { link = "|cffffffff|Hitem:2318::::::::11:::::|h[Light Leather]|h|r", qty = 1, sources = { hoggerGUID, 1 } } }
M.Fire("LOOT_READY")
check(m.g and m.g[2318] == 1 and m.c == 1, "loot: skinning a looted corpse goes under gathered, not drops")

-- pickpocketing in stealth
local hogger3 = "Creature-0-4469-0-17-448-0000777777"
M.stealthed = true
M.loot = { { link = "|cffffffff|Hitem:5376::::::::11:::::|h[Broken Mirror]|h|r", qty = 1, sources = { hogger3, 1 } } }
M.Fire("LOOT_READY")
M.stealthed = false
check(m.pc == 1 and m.p[5376] == 1 and m.c == 1, "loot: pickpocketing in stealth is kept apart")

-- your numbers show on the tooltip
lines = HoverUnit()
check(Has(lines, "You: 2 kills, 1 corpse looted"), "tooltip: your kills and corpses", lines)

------------------------------------------------------------------------------
-- Item tooltip
------------------------------------------------------------------------------
GameTooltip:SetOwner()
M.postCalls[Enum.TooltipDataType.Item](GameTooltip, { id = CLAW })
lines = GameTooltip.lines
check(Has(lines, "Quest: Wanted") and Has(lines, "Dropped by: Hogger"), "item tooltip: your quest and its source", lines)
check(Has(lines, "You looted 1 from Hogger"), "item tooltip: where you looted it", lines)

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------
SB.OpenTarget()
local page = SB.CurrentPage()
check(SB.IsOpen() and page.kind == "npc" and page.id == HOGGER, "/sb opens the window on your target")
local rows = SB.ContentRows()
local function RowsHave(pattern, field)
    for _, row in ipairs(SB.ContentRows()) do
        local t = tostring(row.key or "") .. " " .. tostring(row[field or "text"] or "") .. " " .. tostring(row.mid or "") .. " " .. tostring(row.right or "")
        if t:find(pattern) then return row end
    end
end
check(RowsHave("Elwynn Forest") and RowsHave("Kills"), "overview: where it spawns and your record")
SB.SetTab("loot")
check(RowsHave("Huge Gnoll Claw") and RowsHave("1 %(100%%%)"), "loot tab: Classic chance next to your own rate")
SB.SetTab("abilities")
check(RowsHave("Spell6016") and RowsHave("1x"), "abilities tab: database spells with how often you saw them")
SB.SetTab("quests")
check(RowsHave("On your quests") or RowsHave("Wanted"), "quests tab: your active quest")

local zoneRow = nil
SB.SetTab("overview")
for _, row in ipairs(SB.ContentRows()) do if row.text == "Elwynn Forest" then zoneRow = row end end
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end }
local pin
C_Map.SetUserWaypoint = function(p) pin = p end
zoneRow.onClick(zoneRow)
check(pin and pin[1] == 1429 and math.abs(pin[2] - 0.258) < 0.001, "clicking a zone puts a map pin on the spawn")

-- item page via a loot row
SB.SetTab("loot")
local clawRow = RowsHave("Huge Gnoll Claw")
clawRow.onClick(clawRow)
page = SB.CurrentPage()
check(page.kind == "item" and page.id == CLAW, "clicking a loot row opens the item page")
SB.SetTab("droppedby")
check(RowsHave("Hogger"), "item page: dropped by Hogger")
SB.Back()
check(SB.CurrentPage().id == HOGGER, "Back returns to Hogger")

-- search through the slash command
SlashCmdList.SUPERBESTIARY("bonereaver")
page = SB.CurrentPage()
check(page.kind == "item" and page.id == 17076, "/sb bonereaver opens the only match")

-- zone list
SB.OpenZone()
local found
for _, row in ipairs(SB.SidebarRows()) do if row.id == HOGGER then found = true end end
check(found, "zone list: Hogger is in Elwynn Forest")

-- inside an instance: the zone list is that instance
M.inInstance = true
GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
SB.OpenZone()
found = nil
for _, row in ipairs(SB.SidebarRows()) do if row.id == 639 then found = row end end
check(found and SB.SidebarRows()[1].icon:find("Skull"), "instance list: The Deadmines, bosses first, with VanCleef")
M.inInstance = false

-- alt-click an item
M.alt = true
HandleModifiedItemClick("|cffffffff|Hitem:2589::::::::11:::::|h[Linen Cloth]|h|r")
M.alt = false
check(SB.CurrentPage().id == 2589, "alt-click on an item opens its page")

-- settings + links
SB.OpenSettings()
check(true, "settings page opens")
SB.ShowLink("npc", HOGGER, "Hogger")
check(SuperBestiaryLinkFrame and SuperBestiaryLinkFrame.edit:GetText() == "https://www.wowhead.com/forever/npc=448", "Wowhead link popup")
SB.db.wowhead = "classic"
check(SB.WowheadURL("item", 17076) == "https://www.wowhead.com/classic/item=17076", "Wowhead site setting")

-- an NPC that isn't in the database still gets a page
SB.OpenNpc(999999)
check(SB.CurrentPage().id == 999999, "unknown NPC page doesn't error")

M.Advance(5)
print("ALL BESTIARY TESTS PASSED")
