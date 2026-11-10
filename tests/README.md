# Tests

Headless tests that run the addon, with its full bundled database, against a mocked WoW: Forever client. No game needed.

```bash
lua5.1 tests/test_totalintel.lua .
```

They cover the database (Hogger, Ragnaros, Bonereaver's Edge), mob and item tooltips, quest progress from the quest log, secret values (nothing is added when the game hides a mob's identity), recording kills, loot, skinning, pickpocketing and spells, and the window: pages, tabs, map pins, search, the zone and instance lists, and alt-click.
