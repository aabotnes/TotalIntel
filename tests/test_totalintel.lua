-- Total Intel against a mocked WoW: Forever client and a small stand-in QuestieDB.
-- usage: lua5.1 tests/test_totalintel.lua .
package.path = arg[0]:gsub("[^/]+$", "") .. "?.lua;" .. package.path
local M = require("wow_mock")
require("fake_questiedb")
local check, Has = M.check, M.Has
local dir = arg[1] or "."

local SB = M.Load(dir, M.TocFiles(dir))
check(SB.db and SB.db.tip and SB.db.tip.enabled, "loads every file in the TOC and sets up saved settings")
check(not M.registered("COMBAT_LOG_EVENT_UNFILTERED"), "never registers the combat log (restricted on Forever)")
SB.BuildIndex(true)
check(SB.index.ready, "background index builds")

local HOGGER, RAGNAROS, CLAW = 448, 11502, 1931
local hoggerGUID = "Creature-0-4469-0-17-448-000012ABCD"

------------------------------------------------------------------------------
-- Live data (QuestieDB) + Classic reference numbers
------------------------------------------------------------------------------
local h = SB.GetNpc(HOGGER)
check(h and h.name == "Hogger" and h.minLevel == 11 and h.rank == 1, "Hogger's name and level come from QuestieDB")
check(h.type == 7 and h.hpMax == 666 and h.display == 384, "type, health and display ID come from the Classic reference data")
check(h.zones[1].area == 12 and h.zones[1].x and h.zones[1].count == 5, "spawn point in Elwynn Forest from QuestieDB's spawns")
check(SB.UiMapForArea(12) == 1429, "zone to map from QuestieDB's ZoneDB")
local loot = SB.GetLoot(HOGGER)
check(loot[1].item == CLAW and loot[1].chance == 98.5 and loot[1].src == "wowhead", "quest drop uses QuestieDB's Wowhead rate")
local r = SB.GetNpc(RAGNAROS)
check(r.boss and r.zones[1].area == 2717 and SB.ZoneName(2717) == "Molten Core", "Ragnaros: a boss, placed in Molten Core")
local spells = {}
for _, s in ipairs(SB.GetSpells(RAGNAROS)) do spells[s] = true end
check(spells[20566] and spells[20565], "Ragnaros' abilities include Wrath of Ragnaros and Magma Blast")
local total, by = SB.GetDroppedBy(17076)
check(total == 1 and by[1].npc == RAGNAROS and by[1].chance == 8, "Bonereaver's Edge: dropped by Ragnaros, 8%")
local q = SB.GetQuest(176)
check(q and q.items[1] == CLAW and q.enders[1] == 240 and SB.QuestForMe(q), "quest 176 from QuestieDB, Alliance can do it")
M.faction = "Horde"
check(not SB.QuestForMe(q), "quest 176 isn't for the Horde (race masks above 32 bits)")
M.faction = nil
check(SB.Search("hogger")[1].id == HOGGER, "search finds Hogger first")
check(SB.Search("448")[1].id == HOGGER, "search by ID")
check(#SB.KillFor(HOGGER) == 0 and SB.DropFor(HOGGER)[1].quest == 176, "Hogger is needed for quest 176 (drops the claw)")

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
M.quests = { { id = 176, title = "Wanted: \"Hogger\"", complete = false,
               objectives = { { text = "Huge Gnoll Claw: 0/1", type = "item", finished = false, numFulfilled = 0, numRequired = 1 } } } }
M.Fire("QUEST_LOG_UPDATE")
lines = HoverUnit()
check(Has(lines, "Wanted") and Has(lines, "0/1"), "tooltip: your quest needs the claw, 0/1", lines)
M.secret[hoggerGUID] = true
check(#HoverUnit() == 0, "tooltip: nothing added when the game hides the mob's identity")
M.secret[hoggerGUID] = nil
SB.db.tip.modifier = "SHIFT"
check(#HoverUnit() == 0, "tooltip: hidden until Shift is held")
M.shift = true
check(#HoverUnit() > 0, "tooltip: shown while Shift is held")
M.shift = false
SB.db.tip.modifier = "NONE"

------------------------------------------------------------------------------
-- Learning
------------------------------------------------------------------------------
M.units.target = { guid = hoggerGUID, name = "Hogger", level = 11, combat = true }
M.Fire("PLAYER_TARGET_CHANGED")
check(SB.db.recent[1] == HOGGER and SB.db.mobs[HOGGER].name == "Hogger", "targeting records Hogger as recent, with its name")
M.Fire("UNIT_SPELLCAST_START", "target", "Cast-1", 6016)
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-1", 6016)
local m = SB.db.mobs[HOGGER]
check(m.s[6016] == 1, "spells: a cast is counted once")
M.loot = { { link = "|cffffffff|Hitem:1931::::::::11:::::|h[Huge Gnoll Claw]|h|r", qty = 1, sources = { hoggerGUID, 1 } } }
M.Fire("LOOT_READY")
M.Fire("LOOT_READY")
check(m.c == 1 and m.i[CLAW] == 1 and m.k == 1, "loot: corpse, item and kill recorded once")
local hogger2 = "Creature-0-4469-0-17-448-000099FFFF"
M.units.target = { guid = hogger2, name = "Hogger", level = 11, combat = true }
M.Fire("UNIT_HEALTH", "target")
M.units.target.dead = true
M.Fire("UNIT_HEALTH", "target")
M.Fire("UNIT_HEALTH", "target")
check(m.k == 2, "kills: a mob you fought dying on your target counts once")
M.units.target = { guid = hoggerGUID, name = "Hogger", level = 11 }

-- a mob the database doesn't know still gets a name from what you saw
M.units.target = { guid = "Creature-0-1-0-1-777001-0000000001", name = "Skyborne Sentinel", level = 14 }
M.Fire("PLAYER_TARGET_CHANGED")
check(SB.NpcName(777001) == "Skyborne Sentinel" and SB.GetNpc(777001).maxLevel == 14, "unknown mobs use the name and level you saw")
M.units.target = { guid = hoggerGUID, name = "Hogger", level = 11 }

------------------------------------------------------------------------------
-- Crafting, read from the client's profession API
------------------------------------------------------------------------------
local LEGGINGS, RECIPE = 286990, 9001
local leggingsInfo = { "Arcane Remnant Leggings", "|cff0070dd|Hitem:286990::::::::|h[Arcane Remnant Leggings]|h|r", 3, 33, 28 }
C_Item.GetItemInfo = function(id) if id == LEGGINGS then return unpack(leggingsInfo) end end
C_TradeSkillUI = {
    GetAllRecipeIDs = function() return { RECIPE } end,
    GetRecipeSchematic = function(id)
        if id ~= RECIPE then return nil end
        return { name = "Arcane Remnant Leggings", outputItemID = LEGGINGS, quantityMin = 1, quantityMax = 1, icon = 134586,
                 reagentSlotSchematics = { { reagents = { { itemID = 4306 } }, quantityRequired = 6, reagentType = 1 } } }
    end,
    GetRecipeInfo = function(id) return { name = "Arcane Remnant Leggings", learned = true, maxTrivialLevel = 185 } end,
    GetProfessionInfoByRecipeID = function() return { professionName = "Tailoring" } end,
    GetRecipeSourceText = function() return "|cffffd200Trainer:|r Tailoring trainers. Requires Tailoring (165)" end,
    IsTradeSkillLinked = function() return false end,
    GetBaseProfessionInfo = function() return { professionName = "Tailoring", skillLevel = 170 } end,
}
UnitName = (function(orig) return function(u) if u == "player" then return "Soeta" end return orig(u) end end)(UnitName)
M.Fire("TRADE_SKILL_SHOW")
M.Advance(1)
local recipes = SB.Crafting.ForItem(LEGGINGS)
check(recipes[1] and recipes[1].profession == "Tailoring" and recipes[1].skill == 165, "recipe read from the client: Tailoring (165)")
check(recipes[1].reagents[1][1] == 4306 and recipes[1].reagents[1][2] == 6, "reagents: 6 Silk Cloth")
check(recipes[1].known[1] == "Soeta", "remembers which character knows it")
GameTooltip:SetOwner()
M.postCalls[Enum.TooltipDataType.Item](GameTooltip, { id = LEGGINGS })
check(Has(GameTooltip.lines, "Crafted:.*Tailoring %(165%)"), "item tooltip: Crafted by Tailoring (165)", GameTooltip.lines)

------------------------------------------------------------------------------
-- Item tooltip
------------------------------------------------------------------------------
GameTooltip:SetOwner()
M.postCalls[Enum.TooltipDataType.Item](GameTooltip, { id = CLAW })
lines = GameTooltip.lines
check(Has(lines, "Quest: Wanted") and Has(lines, "Dropped by: Hogger"), "item tooltip: your quest and its source", lines)

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------
local function RowsHave(rows, pattern)
    for _, row in ipairs(rows or {}) do
        local t = table.concat({ tostring(row.key or ""), tostring(row.text or ""), tostring(row.sub or ""),
                                 tostring(row.mid or ""), tostring(row.right or "") }, " ")
        if t:find(pattern) then return row end
    end
end
local function Content(p) return RowsHave(SB.ContentRows(), p) end

SB.OpenTarget()
local page = SB.CurrentPage()
check(SB.IsOpen() and page.kind == "npc" and page.id == HOGGER, "/tits opens the journal on your target")
check(Content("Elwynn Forest") and Content("Kills"), "overview: where it spawns and your record")
SB.SetTab("loot")
check(Content("Huge Gnoll Claw") and Content("98.5%% %(Wowhead%)") and Content("you 1 of 1"), "loot tab: chance with its source, next to your own rate")
SB.SetTab("abilities")
local ability = Content("Spell6016")
check(ability and ability.kind == "spell" and ability.right == "1x", "abilities tab: journal-style ability headers with how often you saw them")
ability.onClick(ability)
local after
for i, row in ipairs(SB.ContentRows()) do if row.kind == "spell" and row.id == 6016 then after = SB.ContentRows()[i + 1] end end
check(after and after.kind == "text", "clicking an ability opens its description")
SB.SetTab("quests")
check(Content("Wanted"), "quests tab: your active quest")

SB.SetTab("overview")
local zoneRow
for _, row in ipairs(SB.ContentRows()) do if row.text == "Elwynn Forest" then zoneRow = row end end
UiMapPoint = { CreateFromCoordinates = function(mp, x, y) return { mp, x, y } end }
local pin
C_Map.SetUserWaypoint = function(p) pin = p end
zoneRow.onClick(zoneRow)
check(pin and pin[1] == 1429, "clicking a zone puts a map pin on the spawn")

SB.SetTab("loot")
local clawRow = Content("Huge Gnoll Claw")
clawRow.onClick(clawRow)
page = SB.CurrentPage()
check(page.kind == "item" and page.id == CLAW, "clicking a loot row opens the item page")
SB.SetTab("droppedby")
check(Content("Hogger"), "item page: dropped by Hogger")
SB.Back()
check(SB.CurrentPage().id == HOGGER, "Back returns to Hogger")

-- every vendor, not a capped list
SB.OpenItem(17033)
SB.SetTab("vendors")
local vendorRows = 0
for _, row in ipairs(SB.ContentRows()) do if row.kind == "npc" then vendorRows = vendorRows + 1 end end
check(vendorRows == 35, "Sold by lists all 35 vendors (" .. vendorRows .. ")")

-- a crafted Forever item opens on its recipe
SB.OpenItem(LEGGINGS)
local p2, tab = SB.CurrentPage()
check(p2.id == LEGGINGS and tab == "crafted", "a crafted item with no drops opens on the Crafted tab")
check(Content("Tailoring %(165%)") and Content("Silk Cloth") and Content("x6") and Content("Soeta"), "crafted tab: profession, skill, reagents and who knows it")

-- search through the slash command
SlashCmdList.TOTALINTEL("bonereaver")
page = SB.CurrentPage()
check(page.kind == "item" and page.id == 17076, "/tits bonereaver opens the only match")

-- zone list
SB.OpenZone()
check(RowsHave(SB.SidebarRows(), "Hogger"), "zone list: Hogger is in Elwynn Forest")

-- dungeons grid and an instance
SB.OpenDungeons(false)
local tiles = SB.GridRows()[1]
check(tiles and tiles.kind == "tiles" and tiles.tiles[1].text == "The Deadmines", "Dungeons tab: a grid with The Deadmines")
tiles.tiles[1].onClick(tiles.tiles[1])
local left = SB.SidebarRows()
check(left[1].kind == "header" and left[1].text == "Bosses" and RowsHave(left, "Edwin VanCleef"), "instance page: bosses first, with VanCleef")
check(SB.CurrentPage().kind == "instance" and Content("Bosses"), "instance overview on the right page")
SB.OpenDungeons(true)
check(SB.GridRows()[1].tiles[1].text == "Molten Core", "Raids tab: Molten Core")

-- inside an instance, /tits opens that instance
M.inInstance = true
GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
M.units.target = nil
SB.OpenTarget()
check(SB.CurrentPage().kind == "instance" and SB.CurrentPage().id == 36, "in a dungeon, /tits opens its journal page")
M.inInstance = false
M.units.target = { guid = hoggerGUID, name = "Hogger", level = 11 }

-- alt-click an item, and a mob in the world
M.alt = true
HandleModifiedItemClick("|cffffffff|Hitem:2589::::::::11:::::|h[Linen Cloth]|h|r")
check(SB.CurrentPage().id == 2589, "alt-click on an item opens its page")
WorldFrame = M.NewWidget()
GetMouseFoci = function() return { WorldFrame } end
M.Fire("GLOBAL_MOUSE_UP", "LeftButton")
check(SB.CurrentPage().kind == "npc" and SB.CurrentPage().id == HOGGER, "alt-click on a mob in the world opens it")
SB.OpenItem(2589)
local bagButton = M.NewWidget()
GetMouseFoci = function() return { bagButton } end
M.Fire("GLOBAL_MOUSE_UP", "LeftButton")
check(SB.CurrentPage().kind == "item", "alt-click in your bags doesn't open the mob under the mouse")
local targetFrame = M.NewWidget()
targetFrame.unit = "target"
GetMouseFoci = function() return { targetFrame } end
M.Fire("GLOBAL_MOUSE_UP", "LeftButton")
check(SB.CurrentPage().kind == "npc", "alt-click on the target frame opens the target")
M.alt = false

-- settings, style, links
SB.OpenSettings()
SB.db.style = "dark"
SB.Restyle()
SB.db.style = "journal"
SB.Restyle()
SB.CloseSettings()
check(true, "settings page and style switch work")
SB.ShowLink("npc", HOGGER, "Hogger")
check(TotalIntelLinkFrame and TotalIntelLinkFrame.edit:GetText() == "https://www.wowhead.com/forever/npc=448", "Wowhead link popup")

C_TooltipInfo = { GetHyperlink = function(link)
    if link:find("%-11867%-") then return { lines = { { leftText = "Woo Ping" } } } end
end }
check(SB.NpcName(11867) == "Woo Ping", "names the database lacks come from the client's creature cache")
SB.OpenNpc(999999)
check(SB.CurrentPage().id == 999999, "unknown NPC page doesn't error")
M.Advance(5)

------------------------------------------------------------------------------
-- Without QuestieDB: Classic reference data still works
------------------------------------------------------------------------------
local saved = LibQuestieDB
LibQuestieDB = nil
SB.ResetSources()
SB.BuildIndex(true)
local bare = SB.GetNpc(RAGNAROS)
check(bare and bare.boss and SB.GetLoot(RAGNAROS)[1], "without QuestieDB: Classic loot and boss flag still there")
lines = HoverUnit()
check(Has(lines, "Abilities:"), "without QuestieDB: tooltips still show abilities", lines)
LibQuestieDB = saved
SB.ResetSources()

print("ALL TESTS PASSED")
