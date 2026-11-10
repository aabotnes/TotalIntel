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
-- No Questie installed: the bundled Forever snapshot
------------------------------------------------------------------------------
local saved = LibQuestieDB
LibQuestieDB = nil
SB.ResetSources()
SB.BuildIndex(true)
check(SB.QDB() and SB.dataSource == "bundled", "without Questie, the bundled snapshot of Forever data is used")
local MURLOC = 735
local murloc = SB.GetNpc(MURLOC)
check(murloc.name == "Murloc Streamrunner" and murloc.minLevel == 6 and murloc.zones[1].area == 12 and murloc.zones[1].count == 20,
    "Murloc Streamrunner: level and Elwynn Forest spawns from the snapshot")
local forQuests = {}
for _, d in ipairs(SB.DropFor(MURLOC)) do forQuests[d.quest] = d.item end
check(forQuests[112] == 1256 and forQuests[150] == 1468, "it drops items for Collecting Kelp and Murloc Poachers")
SB.OpenNpc(MURLOC)
SB.SetTab("quests")
check(Content("Needed for") and Content("Collecting Kelp") and Content("Murloc Poachers"), "its Quests tab lists them")
SB.SetTab("loot")
check(Content("Crystal Kelp Frond") and Content("%(Wowhead%)"), "its loot has the quest items with Wowhead rates")
check(SB.Search("murloc streamr")[1].id == MURLOC, "search finds a mob you've never seen")
SlashCmdList.TOTALINTEL("murloc streamrunner")
check(SB.CurrentPage().kind == "npc" and SB.CurrentPage().id == MURLOC, "/tits <name> opens it")
SlashCmdList.TOTALINTEL("murloc")
local sr = SB.SidebarRows()
check(sr[1].kind == "header" and sr[1].text == "Mobs and NPCs" and RowsHave(sr, "Items"), "search results are grouped into mobs and items")
check(SB.ZoneName(40) == "Westfall", "zone names fall back to the snapshot")
local deadmines
for _, inst in ipairs(SB.Instances(false)) do if inst.map == 36 then deadmines = inst end end
check(deadmines and #deadmines.bosses >= 5 and deadmines.name == "The Deadmines", "dungeons come from the snapshot (" .. (deadmines and #deadmines.bosses or 0) .. " Deadmines bosses)")
lines = HoverUnit()
check(Has(lines, "Abilities:"), "tooltips work on the snapshot", lines)
LibQuestieDB = saved
SB.ResetSources()
check(SB.QDB() and SB.dataSource == "QuestieDB", "a live QuestieDB is preferred when it's installed")

------------------------------------------------------------------------------
-- Loot tab: filter by rarity
------------------------------------------------------------------------------
SB.BuildIndex(true)
SB.OpenNpc(HOGGER)
SB.SetTab("loot")
local function Chips() for _, r in ipairs(SB.ContentRows()) do if r.kind == "filters" then return r.chips end end end
local function Chip(pattern) for _, c in ipairs(Chips()) do if c.text:find(pattern) then return c end end end
local function ItemCount() local n = 0 for _, r in ipairs(SB.ContentRows()) do if r.kind == "item" then n = n + 1 end end return n end
local allItems = ItemCount()
check(Chip("Common") and Chip("Uncommon") and not Chip("Reset"), "loot tab has a chip per rarity present, and no Reset while nothing is hidden")
check(Content("Item #818"), "an uncommon drop is listed")
Chip("Uncommon").onClick()
check(not Content("Item #818") and ItemCount() < allItems and Content("Huge Gnoll Claw"), "clicking Uncommon hides the uncommon drops only")
check(SB.ContentRows()[1].right:find(" of "), "the header shows how many are shown (" .. SB.ContentRows()[1].right .. ")")
check(not Chip("Uncommon").on and Chip("Reset"), "the chip turns off and Reset appears")
Chip("Common").onClick()
check(ItemCount() == 0 and Content("hidden by the rarity filter"), "hiding every rarity explains the empty list")
Chip("Reset").onClick()
check(ItemCount() == allItems and not Chip("Reset"), "Reset filter shows everything again")

------------------------------------------------------------------------------
-- Sells and Teaches
------------------------------------------------------------------------------
SB.BuildIndex(true)
local VENDOR = 90001
check(SB.Sells(VENDOR)[1] and SB.Sells(VENDOR)[1].item == 17033, "Sells: QuestieDB's vendor list")
SB.OpenNpc(VENDOR)
SB.SetTab("sells")
check(SB.CurrentPage() and select(2, SB.CurrentPage()) == "sells" and Content("Symbol of Divinity"), "Sells tab lists the items")
-- open the merchant in the game: prices and stock replace the database list
M.units.npc = { guid = "Creature-0-1-0-1-90001-0000000003", name = "Reagent Vendor 1" }
GetMerchantNumItems = function() return 2 end
GetMerchantItemID = function(i) return ({ 17033, 4306 })[i] end
C_MerchantFrame = { GetItemInfo = function(i) return ({ { price = 2500, stackCount = 1, numAvailable = -1 }, { price = 600, stackCount = 5, numAvailable = 3 } })[i] end }
M.Fire("MERCHANT_SHOW")
M.Advance(1)
local sells, src = SB.Sells(VENDOR)
check(src == "game" and #sells == 2 and sells[2].limited and sells[2].stack == 5, "Sells: read from the merchant window, with stock")
SB.SetTab("sells")
check(Content("25|T.*SilverIcon") and Content("x5, limited"), "Sells tab shows prices in coins and limited stock")

local TRAINER = 198
local teach, tsrc = SB.Teaches(TRAINER)
check(tsrc == "classic" and teach[1] and teach[1].spell == 1472, "Teaches: Classic trainer list as the fallback")
SB.OpenNpc(TRAINER)
SB.SetTab("teaches")
local row = Content("Spell1142")
check(SB.Money(21897) == "2|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 18|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 97|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
    "money is shown with coin icons, like the bag window")
check(row and row.kind == "teach" and row.sub:find("level 4") and row.mid == "|cffff4040" .. SB.Money(100) .. "|r",
    "Teaches: one row per spell with its requirement, and the cost in red when you can't afford it")

-- a fishing trainer: your skill bar on top, requirements green or red against your skill
local FISHER = 1651
C_SkillInfo = { GetSkillLineInfoByID = function(sid)
    if sid == 356 then return { skillID = 356, name = "Fishing", rank = M.fishing or 0, maxRank = M.fishing and 75 or 0 } end
end }
M.money = 10000
SB.OpenNpc(FISHER)
SB.SetTab("teaches")
local bar = Content("Your Fishing")
check(bar and bar.kind == "bar" and bar.value == nil, "Teaches: a skill bar that says when you haven't learned the profession")
local journeyman = Content("Spell7734")
check(journeyman.sub:find("|cffff4040Fishing 50", 1, true) and journeyman.mid == SB.Money(500) and journeyman.mid:find("^5|T.*SilverIcon"), "Journeyman Fishing: requirement in red without the skill, cost in coins")
M.fishing = 37
SB.SetTab("teaches")
bar = Content("Your Fishing")
check(bar.value == 37 and bar.max == 75, "skill bar shows 37 / 75")
check(Content("Spell7734").sub:find("|cffff4040Fishing 50", 1, true), "still red at 37 of 50")
M.fishing = 60
SB.SetTab("teaches")
check(Content("Spell7734").sub:find("|cff40e040Fishing 50", 1, true), "green once your skill is high enough")
local apprentice = Content("Spell7733")
check(apprentice.sub:find("|cff40e040level 5", 1, true), "level requirements are colored too")
M.units.npc = { guid = "Creature-0-1-0-1-198-0000000004", name = "Khelden Bremen" }
local services = { { "Arcane Intellect", "Rank 1", "available", 10, 1 }, { "Frostbolt", "Rank 2", "unavailable", 100, 8 } }
GetNumTrainerServices = function() return #services end
GetTrainerServiceInfo = function(i) return services[i][1], services[i][2], services[i][3] end
GetTrainerServiceCost = function(i) return services[i][4] end
GetTrainerServiceLevelReq = function(i) return services[i][5] end
GetTrainerServiceSkillReq = function() return nil end
local filters = { available = 1, unavailable = 0, used = 0 }
GetTrainerServiceTypeFilter = function(f) return filters[f] == 1 end
local filterChanges = 0
SetTrainerServiceTypeFilter = function(f, v) filters[f] = v; filterChanges = filterChanges + 1; M.Fire("TRAINER_UPDATE") end
M.Fire("TRAINER_SHOW")
M.Advance(1)
M.Advance(1)
teach, tsrc = SB.Teaches(TRAINER)
check(tsrc == "game" and #teach == 2 and teach[2].name == "Frostbolt" and teach[2].level == 8, "Teaches: read from the trainer window")
check(filters.unavailable == 0 and filters.used == 0 and filterChanges == 4, "trainer filters are restored, without a read loop (" .. filterChanges .. ")")
M.units.npc = nil

------------------------------------------------------------------------------
-- Questie's built-in database (Questie releases without the separate QuestieDB addon)
------------------------------------------------------------------------------
saved = LibQuestieDB
LibQuestieDB = nil
local ready = false
local qdbModule = { NPCPointers = { [448] = 1, [240] = 1 }, ItemPointers = { [1931] = 1 }, QuestPointers = { [176] = 1 } }
qdbModule.QueryNPCSingle = function(id, key) if not ready then error("not initialized") end return saved.Npc.Get(id, key) end
qdbModule.QueryItemSingle = function(id, key) return saved.Item.Get(id, key) end
qdbModule.QueryQuestSingle = function(id, key) return saved.Quest.Get(id, key) end
QuestieLoader = { ImportModule = function(_, name)
    if name == "QuestieDB" then return qdbModule end
    return saved.Support.Get(name)
end }
SB.ResetSources()
check(SB.QDB() and SB.dataSource == "bundled", "until Questie has loaded its database, the bundled snapshot is used")
ready = true
M.Advance(4)
check(SB.QDB() and SB.dataSource == "Questie", "Questie's built-in database takes over once it's ready")
SB.BuildIndex(true)
check(SB.GetNpc(HOGGER).zones[1].area == 12 and SB.GetQuest(176).items[1] == CLAW, "spawns and quests read through Questie's database")
QuestieLoader = nil
LibQuestieDB = saved
SB.ResetSources()
SB.BuildIndex(true)

------------------------------------------------------------------------------
-- Quests the game shows on a mob's tooltip
------------------------------------------------------------------------------
C_TooltipInfo = { GetUnit = function(unit)
    if unit == "target" then return { lines = { { type = 2 }, { type = 17, id = 99001 }, { type = 8 } } } end
end }
M.units.target = { guid = "Creature-0-1-0-1-735-0000000002", name = "Murloc Streamrunner", level = 6 }
M.quests[#M.quests + 1] = { id = 99001, title = "Forever: Murloc Menace", complete = false,
    objectives = { { text = "Murloc Streamrunner slain: 2/8", type = "monster", finished = false, numFulfilled = 2, numRequired = 8 } } }
M.Fire("QUEST_LOG_UPDATE")
M.Fire("PLAYER_TARGET_CHANGED")
check(SB.db.mobs[735].q and SB.db.mobs[735].q[99001], "learns quest IDs from the game's tooltip data")
local rel = SB.QuestLog.ForNpc(735)
check(rel[1] and rel[1].entry.id == 99001 and SB.QuestLog.ObjectiveText(rel[1].objective) == "2/8", "a Forever-only quest is matched with its progress")

------------------------------------------------------------------------------
-- Zone list without any database: mobs you've seen there, grouped
------------------------------------------------------------------------------
saved = LibQuestieDB
LibQuestieDB = nil
SB.ResetSources()
SB.BuildIndex(true)
SB.OpenZone()
local zoneRows = SB.SidebarRows()
check(RowsHave(zoneRows, "For your quests") and RowsHave(zoneRows, "Murloc Streamrunner"), "zone list groups mobs you've seen there, quest mobs first")
LibQuestieDB = saved
SB.ResetSources()

print("ALL TESTS PASSED")
