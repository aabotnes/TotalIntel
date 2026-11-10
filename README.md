# Super Bestiary

*by Soeta*

Wowhead in your game. Hover a mob to see its best drops with their drop chance, its abilities, and the quests you need it for, with your progress. Open the bestiary window for its full loot table, abilities, quests, where it spawns, and everything you've killed, looted and seen it cast yourself. It's made for WoW: Forever (interface 16001).

The game doesn't let addons go online, so the database ships inside the addon (about 10,000 mobs, 15,000 items and 4,000 quests). Your own kills and loot are added as you play.

## Install

Download the addon and unzip it into `Interface\AddOns`. You should end up with `Interface\AddOns\SuperBestiary\SuperBestiary.toc`. The folder must be named exactly `SuperBestiary`. Restart the game and make sure **Super Bestiary** is ticked in the AddOns list.

## Tooltips

Hover any mob in the world:

- **Type and rank**: *Elite · Humanoid*, *Beast · Wolf · Skinnable*, and *Pickpocket* for rogues.
- **Your quests**: every quest in your log where you kill this mob or loot something from it, with your progress, e.g. *Wanted: "Hogger" · Huge Gnoll Claw 100% 0/1*.
- **Quest giver**: quests the NPC starts that you can still do, and *Turn in* lines for quests in your log.
- **Notable drops**: its best drops with their drop chance. Quest drops always show. Once you've looted it 5 times, your own count shows next to each drop, e.g. *you 2/12*.
- **Abilities**: the spells it casts, with icons.
- **You**: how many you've killed and looted.

Hover an item to see the quests that need it (with progress), the quest it starts, the mobs with the best chance to drop it, a vendor that sells it, and the mob you've looted it from most.

Every line can be turned on or off. You can also show the lines only while Shift, Ctrl or Alt is held. See [Settings](#settings).

## The bestiary window (`/sb`)

`/sb` opens the window on your target. On the left:

- **Recent**: mobs you've targeted lately.
- **Zone**: every mob in your zone, with bosses first. Inside a dungeon or raid, it lists that instance's mobs and bosses.
- **Bestiary**: every mob you've killed, most kills first.
- **Search**: type part of a name, or an ID, to find any mob or item.

A mob's page shows its 3D model and five tabs:

- **Overview**: level, rank, type, health, mana, coin, services (vendor, trainer, flight master), where it spawns, your record (kills, corpses looted, first and last seen), and its best drops. Click a zone to put a pin on the map at its spawns.
- **Loot**: the whole loot table with each item's drop chance next to *your* rate on Forever, e.g. *3 (25%)* of 12 corpses. Also items you've looted that the database doesn't list, and skinning and pickpocket loot.
- **Abilities**: the spells it casts, with full spell tooltips and how many times you've seen each. Spells you see a mob cast are added, even if the database doesn't list them.
- **Quests**: on your quests (with progress), needed for, starts, turn in here.
- **Notes**: your own notes on the mob, saved for all your characters.

Items have pages too: **Overview**, **Dropped by** (every mob, with chances and your own counts), **Quests**, and **Sold by**.

Click an item or mob anywhere in the window to open its page, and **< Back** to go back. Shift-click an item or spell to link it in chat.

**Wowhead link**: the game can't open a browser, so this shows the mob's, item's, quest's or spell's Wowhead link, ready to copy with Ctrl+C. Choose *wowhead.com/forever* or */classic* in the settings.

**Alt-click** an item in your bags, the loot window or a chat link to open its page. You can change this in the settings.

## Settings

Open the settings with `/sb options`, the **Settings** button in the window, right-click on the minimap button, or the game's **Options → AddOns → Super Bestiary**.

**Mob tooltips**
- Add Super Bestiary lines to tooltips, either always or only while Shift, Ctrl or Alt is held
- Type, rank and skinning
- Your quests that need it
- Quests it gives and turn-ins
- Notable drops: how many (1-10) and the lowest quality worth showing
- Abilities: how many (1-10)
- Your kills and loot
- Health and mana, coin it drops, NPC ID, the hint line

**Item tooltips**
- Quests that use it, dropped by (how many mobs to list), sold by, where you looted it, item ID

**General**
- Which Wowhead the links point to
- The click that opens an item's page (Alt, Ctrl+Alt or Shift+Alt, or off)
- Record kills, loot and spells
- Minimap button
- Reset tooltip settings, and *Forget my bestiary* to wipe what you've recorded

## Commands and key bindings

| Command | What it does |
|---|---|
| `/sb` | open the window on your target |
| `/sb <name>` | search mobs and items, e.g. `/sb hogger`. A single match opens straight away. |
| `/sb zone` | mobs in your zone or instance |
| `/sb options` | settings |
| `/sb link` | Wowhead link for your target |
| `/sb learn` | turn recording kills, loot and spells on or off |
| `/sb minimap` | hide or show the minimap button |

`/bestiary` works too. Under **Key Bindings → AddOns** you can bind *Open for target*, *Open for mouseover* and *Toggle window*.

## Good to know

- **Drop chances are Classic numbers.** They come from the CMaNGOS Classic database, because Forever doesn't have published drop rates yet. Forever's own data decides *which* mobs drop *which* items. If Forever lists a drop that Classic doesn't have, it's marked *Forever*, with no chance. That's why the window shows your own rate next to every chance.
- **Dungeons and raids:** inside instances, Forever hides from addons which mob a tooltip belongs to. Mob tooltips there have no extra lines, and the game won't tell the addon who your target is. Use the **Zone** list instead: it lists the instance's bosses and mobs. Open-world mobs work normally, even in combat.
- **What it records:** kills (yours and your group's), every corpse you loot and what was on it, skinning, mining and herbing loot, pickpocketing (while stealthed), and spells mobs cast near you. It's saved for your whole account. Turn it off with `/sb learn`.
- **New in Forever:** a mob or quest that isn't in the database still gets a page, and still records your kills, loot and spells. Quests not in the database are still matched to mobs by name.

## Data and license

Super Bestiary is GPL-3.0. Its database is built from [QuestieDB](https://github.com/Questie/QuestieDB) (WoW: Forever NPCs, quests, items and zones) and [CMaNGOS](https://github.com/cmangos) (drop chances, stats, spell lists and boss scripts), both GPL-3.0. Thanks to both projects. See [tools/README.md](tools/README.md) to rebuild it.

Super Bestiary is not affiliated with Wowhead or Blizzard.
