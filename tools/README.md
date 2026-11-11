# Rebuilding the bundled data

`Data/*.lua` is generated. Don't edit it by hand: change `build_data.py` and run it again. There are two sets:

- **Forever snapshot** (`Forever*.lua`): QuestieDB's WoW: Forever NPCs, quests, items, zones and Wowhead quest-drop rates. The addon uses it only when no live Questie database is installed in the game. Rebuild it to pick up new Forever content.
- **Classic reference numbers** (the other files): what no live source has.

| File | Contents |
|---|---|
| `Classic.lua` | per NPC: rank, creature type, family, health, mana, coin, flags (boss, skinnable, pickpocket), display ID, world-drop pool size, instance map |
| `Loot.lua` | per NPC: item:chance, best first (`:q` = only while on the quest) |
| `LootExtra.lua` | skinning and pickpocket loot |
| `Spells.lua` | spells each NPC casts (spell lists, EventAI and boss scripts) |
| `QuestDetails.lua` | each quest's full text, how many of each item, mob and object it needs, and its reward items, money and reputation |
| `Trainers.lua`, `TrainerTemplates.lua` | what each trainer teaches: spell, cost, level and skill (the fallback until you visit the trainer in the game) |
| `ForeverNpcs.lua`, `ForeverItems.lua`, `ForeverQuests.lua` | the Forever snapshot: names, levels, spawn zones with a central point, quest links, drops, vendors |
| `ForeverRates.lua` | Wowhead drop rates for quest items |
| `ForeverQuestXP.lua` | experience each quest gives |
| `ForeverZones.lua` | zone names, map IDs, dungeons, and the QuestieDB commit and date the snapshot was built from |

## Sources

All are GPL-3.0, which is why Total Intel is GPL-3.0 too. The generator reads them as plain data and never runs their code.

- [Questie/QuestieDB](https://github.com/Questie/QuestieDB) (`data/Forever`, `support/Forever`): the Forever snapshot
- [cmangos/classic-db](https://github.com/cmangos/classic-db) (`Full_DB/*.sql.gz`): loot tables, creature templates, spell lists, EventAI, boss encounters
- [cmangos/mangos-classic](https://github.com/cmangos/mangos-classic) (`src/game/AI/ScriptDevAI/scripts`), optional: boss abilities from the spells each boss script casts

## Run

```bash
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/cmangos/classic-db
(cd classic-db && git checkout HEAD -- Full_DB)
zcat classic-db/Full_DB/*.sql.gz > full.sql
git clone --depth 1 --filter=blob:none --sparse https://github.com/cmangos/mangos-classic
(cd mangos-classic && git sparse-checkout set src/game/AI/ScriptDevAI/scripts)

git clone --depth 1 https://github.com/Questie/QuestieDB

python3 -I tools/build_data.py --cmangos-sql full.sql --scripts mangos-classic --questiedb QuestieDB
```

It takes about 15 seconds and prints row counts and file sizes. Leave out `--questiedb` to rebuild only the Classic numbers.
