# Rebuilding the database

`Data/*.lua` is generated. Don't edit it by hand: change `build_data.py` and run it again.

## Sources

All three are GPL-3.0, which is why Super Bestiary is GPL-3.0 too. The generator reads them as plain data and never runs their code.

| Source | Used for |
|---|---|
| [Questie/QuestieDB](https://github.com/Questie/QuestieDB) (`data/Forever`, `support/Forever/Zones`, `src/corrections/enum/zones.lua`) | WoW: Forever's NPCs, levels, spawn points, quests, items, who drops what, vendors, zones and instances |
| [cmangos/classic-db](https://github.com/cmangos/classic-db) (`Full_DB/*.sql.gz`) | drop chances (creature, reference, skinning and pickpocket loot), health, mana, coin, creature type and family, spell lists, EventAI casts, boss encounters, display IDs |
| [cmangos/mangos-classic](https://github.com/cmangos/mangos-classic) (`src/game/AI/ScriptDevAI/scripts`), optional | boss abilities, taken from the spells each boss script casts |

Forever decides what exists. CMaNGOS fills in the numbers Forever's data doesn't have. Its drop chances are Classic numbers, and the addon labels them that way.

## Run

```bash
git clone --depth 1 https://github.com/Questie/QuestieDB
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/cmangos/classic-db
(cd classic-db && git checkout HEAD -- Full_DB)
zcat classic-db/Full_DB/*.sql.gz > full.sql
git clone --depth 1 --filter=blob:none --sparse https://github.com/cmangos/mangos-classic
(cd mangos-classic && git sparse-checkout set src/game/AI/ScriptDevAI/scripts)

python3 -I tools/build_data.py --questiedb QuestieDB --cmangos-sql full.sql --scripts mangos-classic
```

It takes about 15 seconds and prints row counts and file sizes.

## Record formats

Each `Data/*.lua` file starts with a comment that describes its format. NPC records are `^`-separated, in the field order listed at the top of `Database.lua`.
