# Total Intel on Targets & Spoils

*by Soeta* · `/tits`

An Adventure Guide for every mob and item in WoW: Forever. Hover a mob to see its best drops, its abilities and the quests you need it for. Alt-click any mob or item to open its page in a journal styled like the game's own Adventure Guide. There you'll find loot with drop chances, abilities, quests, where it spawns, how an item is crafted, and everything you've killed, looted and seen yourself.

## Where the data comes from

Total Intel reads live sources first, so it follows the current version of Forever. It also carries a snapshot of Forever's NPC, quest and item data, so it works on its own when no Questie database is installed:

| What | Where it comes from |
|---|---|
| NPCs, levels, spawn points, quests, who drops and sells each item, zones, instances | **Questie's database**, read live in the game when it's installed: the QuestieDB addon, or the database built into Questie. Otherwise the **bundled snapshot** of QuestieDB's Forever data. `/tits status` says which one is in use and how old the snapshot is. |
| Which quests a mob is for | also the **game client**: the quest lines on a mob's tooltip carry quest IDs, so every mob you target or mouse over teaches Total Intel its quests, Forever-only ones included |
| Item names, quality, item levels (Forever-only items included), spells, zone names | the **game client** |
| Recipes: profession, skill, reagents, how it's learned | the **game client's profession window**: see [Crafting](#crafting) |
| What vendors sell and trainers teach | the **game client**, read when you open their window (prices, stock, level and skill). Before your first visit: Questie's vendor lists, and the Classic trainer lists (CMaNGOS). |
| Dungeon and raid artwork and lore | the game's **Adventure Guide** |
| Drop chances for quest items | Wowhead's rates, shipped by QuestieDB |
| Other drop chances, mob health, abilities | **Classic reference numbers** (CMaNGOS), bundled because nothing in the game provides them. They're labeled *Classic*. Your own looted rate is shown next to every chance. |

## Install

1. Unzip Total Intel into `Interface\AddOns`. You should end up with `Interface\AddOns\TotalIntel\TotalIntel.toc`.
2. Restart the game and make sure **Total Intel on Targets & Spoils** is ticked in the AddOns list.

Nothing else is required. If you also run Questie (or the QuestieDB addon), Total Intel reads its database instead of the bundled snapshot, so new quests and NPCs show up as soon as Questie updates.

## Opening things

- **Alt-click** a mob in the world, a nameplate, your target or focus frame, or any item (bags, loot, chat links, character sheet) to open its page. You can change the key in the settings.
- `/tits` opens the journal on your target. Inside a dungeon or raid it opens that instance's page.
- Key bindings: *Open for target*, *Open for mouseover*, *Toggle window*.

## The journal

It's an open book, like the Adventure Guide:

- **Left page:** a list. **Recent** (your recent targets), **Zone**, **Bestiary** (everything you've killed), search results, or an instance's bosses and inhabitants. Each mob has its portrait.
- **Zone** lists every mob in the zone you're in, grouped: *For your quests* first, then *Bosses, elites & rares*, *Creatures* and *Friendly NPCs*. Mobs you've seen there are always included, even ones no database knows.
- **Right page:** the mob, item or instance you picked, with the journal's tabs down the right edge.
- **Search** (top right): any mob, NPC or item by name or ID, whether you've seen it or not. Results are grouped into *Mobs and NPCs* and *Items*. `/tits <name>` does the same from chat.
- **Bottom tabs:** Recent, Zone, Bestiary, **Dungeons**, **Raids** and Settings. Dungeons and Raids show every instance as a tile with the Adventure Guide's artwork. Click one for its bosses, its other inhabitants and its boss loot.
- **Back arrow** (top left) and the path next to it show where you are.
- **Resize** the journal by dragging its bottom-right corner. It remembers the size.

**Mob tabs**
- **Overview:** type, health, mana, coin, services, where it spawns (click a zone for a map pin), your record, and its best drops.
- **Loot:** every drop with its chance and where the chance comes from, next to *your* rate on Forever (e.g. *you 3 of 12 (25%)*). It also lists skinning and pickpocket loot, and items you've looted that no database lists. **Filter by rarity** with the chips at the top: click *Poor*, *Common*, *Uncommon*... to hide or show that rarity, and **Reset filter** to show everything again. The filter is remembered.
- **Abilities:** Adventure Guide-style ability headers. Click one for its description. Spells you see a mob cast are added, with how often.
- **Sells** (vendors): every item, with price and limited stock once you've opened that vendor. Before that it shows Questie's list.
- **Teaches** (trainers): one row per spell or recipe, with its cost in coins (red if you can't afford it) and what it requires, in green if you meet it and red if you don't. Your own skill is shown as a bar on top, e.g. *Your Fishing 37 / 75*, or *Not learned*. It's read from the trainer window when you visit; before that it shows the Classic trainer list.
- **Model:** the mob in 3D. Drag to turn it.
- **Quests:** on your quests (with progress), needed for, starts, and turn in here.
- **Notes:** your own notes, saved for all your characters.

**Item tabs:** Overview, **Dropped by** (every mob, no "+23 more"), **Crafted**, **Quests** and **Sold by** (every vendor).

**Instance tabs:** Overview (Adventure Guide lore, level range, bosses) and Loot (each boss's drops).

**Wowhead link** shows the page's Wowhead link, ready to copy with Ctrl+C, because the game can't open a browser.

## Crafting

Recipes come straight from the game client. Whenever a profession window opens, Total Intel reads every recipe in it with the client's profession API: what it makes, the reagents, the profession, how it's learned (e.g. *Requires Tailoring (165)*) and when it turns grey. That includes:

- your own professions, on any character
- someone else's profession link in chat. Click their **[Tailoring]** link and their whole recipe list is read.

Recipes are saved for your whole account and read again each time a window opens, so they stay current with Forever's patches. A crafted item's page then opens on its **Crafted** tab, with the profession, skill, reagents and which of your characters know the recipe. Its tooltip says *Crafted: Tailoring (165)*. Reagents also list what they're used in.

## Tooltips

**Mobs:** type and rank, your quests that need it (with progress), quests it gives and turn-ins, notable drops with chances, abilities, and your kills.

**Items:** quests that need it, the quest it starts, how it's crafted, the mobs most likely to drop it, a vendor, and the mob you've looted it from most.

Every line can be turned off, or shown only while Shift, Ctrl or Alt is held.

## Settings

Open them with `/tits options`, the Settings tab, or **Options → AddOns**. They're on two pages: mob tooltips on the left, item tooltips and general settings on the right.

- Each tooltip line on or off, how many drops and abilities to list, and the lowest quality worth showing.
- **Window style:** Adventure Guide (parchment) or Dark.
- **Open with:** Alt-click, Ctrl+Alt-click, Shift+Alt-click, or off.
- **Wowhead links:** wowhead.com/forever or /classic.
- Record kills, loot and spells. Minimap button. Reset tooltips. Forget my bestiary.

## Commands

| Command | What it does |
|---|---|
| `/tits` | open the journal on your target (or your instance) |
| `/tits <name>` | search mobs and items, e.g. `/tits hogger`. A single match opens straight away. |
| `/tits zone` | mobs in your zone or instance |
| `/tits dungeons`, `/tits raids` | the instance journal |
| `/tits options` | settings |
| `/tits link` | Wowhead link for your target |
| `/tits learn` | turn recording kills, loot and spells on or off |
| `/tits status` | which database is in use, what's loaded, and any errors the addon caught (handy for bug reports) |
| `/tits minimap` | hide or show the minimap button |

`/totalintel` works too.

## Good to know

- **Dungeons and raids:** inside instances, Forever hides from addons which mob a tooltip or your target is. Mob tooltips there get no extra lines, and the target can't be identified. Use the instance's page instead: `/tits` opens it.
- **Kills** are counted when a mob you fought dies on your target or nameplates, and when you loot its corpse. Forever reserves the combat log for Blizzard's own UI, so addons can't use it.
- **What's recorded:** kills, every corpse you loot and what was on it, skinning, mining and herbing loot, pickpocketing (while stealthed), spells mobs cast near you, mobs' names and levels, and recipes. It's all saved for your whole account. Turn recording off with `/tits learn`.

## Data and license

Total Intel is GPL-3.0. Its bundled data is built from [QuestieDB](https://github.com/Questie/QuestieDB) (the Forever snapshot) and [CMaNGOS](https://github.com/cmangos) (Classic reference numbers), both GPL-3.0. See [tools/README.md](tools/README.md) to rebuild it. Thanks to both projects.

Total Intel is not affiliated with Wowhead or Blizzard.
