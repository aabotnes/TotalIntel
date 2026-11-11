# Tests

Headless tests that run the addon against a mocked WoW: Forever client (`wow_mock.lua`) and a small stand-in for the QuestieDB addon (`fake_questiedb.lua`, with real Forever records). No game needed.

```bash
lua5.1 tests/test_totalintel.lua .
```

They cover:
- live data from QuestieDB merged with the Classic reference numbers
- mob and item tooltips, including secret values (nothing is added when the game hides a mob's identity)
- quest progress
- recording kills, loot and spells, without the combat log
- crafting read from the client's profession API
- the journal: pages and side tabs, every vendor and dropper listed, the Crafted tab, the Dungeons and Raids grids, instance pages, map pins, search, Alt-click on items and mobs, and the style switch
- the bundled Forever snapshot when no Questie database is installed, and switching to a live one
- expandable quests: text, required items with progress and bag counts, kills, quest givers, rewards (items, experience at your level, money, reputation)
- tabs hidden when they have nothing to show; the zone directory and picking another zone
- the Loot rarity filter, Teaches rows with your skill, Sells, and coin prices
