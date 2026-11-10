# Rebuilding the Classic reference numbers

Total Intel reads everything about WoW: Forever live in the game, from QuestieDB and the client (see the main README). Only Classic reference numbers that no live source has are bundled in `Data/*.lua`:

| File | Contents |
|---|---|
| `Classic.lua` | per NPC: rank, creature type, family, health, mana, coin, flags (boss, skinnable, pickpocket), display ID, world-drop pool size, instance map |
| `Loot.lua` | per NPC: item:chance, best first (`:q` = only while on the quest) |
| `LootExtra.lua` | skinning and pickpocket loot |
| `Spells.lua` | spells each NPC casts (spell lists, EventAI and boss scripts) |

They're generated: don't edit them by hand. Change `build_data.py` and run it again.

## Sources

Both are GPL-3.0, which is why Total Intel is GPL-3.0 too. The generator reads them as plain data and never runs their code.

- [cmangos/classic-db](https://github.com/cmangos/classic-db) (`Full_DB/*.sql.gz`): loot tables, creature templates, spell lists, EventAI, boss encounters
- [cmangos/mangos-classic](https://github.com/cmangos/mangos-classic) (`src/game/AI/ScriptDevAI/scripts`), optional: boss abilities from the spells each boss script casts

## Run

```bash
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/cmangos/classic-db
(cd classic-db && git checkout HEAD -- Full_DB)
zcat classic-db/Full_DB/*.sql.gz > full.sql
git clone --depth 1 --filter=blob:none --sparse https://github.com/cmangos/mangos-classic
(cd mangos-classic && git sparse-checkout set src/game/AI/ScriptDevAI/scripts)

python3 -I tools/build_data.py --cmangos-sql full.sql --scripts mangos-classic
```

It takes about 10 seconds and prints row counts and file sizes.
