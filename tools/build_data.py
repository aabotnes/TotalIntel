#!/usr/bin/env python3
"""Builds Total Intel's bundled Classic reference numbers (Data/*.lua).

Everything about WoW: Forever itself (NPCs, spawns, quests, items, who drops and sells what,
zones, recipes) is read live in the game from the QuestieDB addon and the client. What no live
source has are Classic reference numbers, so only those are bundled:

  * CMaNGOS classic https://github.com/cmangos/classic-db       - drop chances, health, mana, coin,
                                                                   creature type, skinning, pickpocket,
                                                                   spell lists, bosses, display IDs
  * CMaNGOS core    https://github.com/cmangos/mangos-classic   - boss abilities from the boss scripts (optional)

Both are GPL-3.0 and parsed as data, never executed.

usage:
  python3 -I tools/build_data.py --cmangos-sql PATH/full.sql [--scripts PATH/mangos-classic] [--out Data]
"""
import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sources import sql_rows  # noqa: E402

WORLD_POOL_SIZE = 60    # a reference table bigger than this is a random world-drop pool
MAX_LOOT = 60           # loot rows kept per NPC (highest chance first)

NPC_FLAG_VENDOR = 0x4 | 0x80 | 0x100 | 0x200 | 0x400 | 0x800  # vendor variants on 1.12
NPC_FLAG_TRAINER = 0x10 | 0x20 | 0x40
NPC_FLAG_FLIGHT = 0x8
NPC_FLAG_INNKEEPER = 0x10000 | 0x80
NPC_FLAG_BANKER = 0x20000
NPC_FLAG_REPAIR = 0x4000

# boss-script spell constants that are never something a player would call an ability
SPELL_NOISE = re.compile(r"VISUAL|DUMMY|CREDIT|DESPAWN|_KILL$|KILL_CREDIT|TRIGGER|CLEAR|_AURA_|BIRTH|TELEPORT_VISUAL|"
                         r"SUBMERGE|EMERGE|STEALTH_DETECT|SPAWN|INVIS|_PASSIVE|EVADE|IMMUNE|ROOT_SELF|STUN_SELF|"
                         r"TRANSFORM_VISUAL|DESTROY_ALL|SUICIDE|_INTRO|_OUTRO|_RP$|DEBUG|COSMETIC")


def num(v, default=0):
    return v if isinstance(v, (int, float)) else default


def fmt_chance(c):
    c = round(c, 2)
    if c >= 10:
        c = round(c, 1)
    s = ("%.2f" % c).rstrip("0").rstrip(".")
    return s if s else "0"


def clean(s):
    return (s or "").replace("^", "").replace("|", "/").replace("\n", " ").strip()


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


# ---------------------------------------------------------------------------
# CMaNGOS loot
# ---------------------------------------------------------------------------

def index_loot(rows):
    t = collections.defaultdict(list)
    for r in rows:
        t[r["entry"]].append(r)
    return t


def resolve_loot(entry, table, refs, depth=0):
    """Returns ({item: (chance %, questOnly)}, worldDropPoolSize) for one loot entry.

    CMaNGOS rules: ungrouped rows roll on their own; a group drops at most one item, rows with
    chance 0 share whatever chance the group's explicit rows leave. A negative chance is a
    quest-only drop. mincountOrRef < 0 rolls a reference table `maxcount` times.
    """
    out = {}
    world = 0
    rows = table.get(entry, [])
    groups = collections.defaultdict(list)
    for r in rows:
        groups[r["groupid"]].append(r)

    def add(item, chance, quest):
        old = out.get(item)
        if old:
            chance = min(100.0, old[0] + chance)
            quest = old[1] and quest
        out[item] = (min(100.0, chance), quest)

    for gid, grows in groups.items():
        explicit = sum(abs(num(r["ChanceOrQuestChance"])) for r in grows if num(r["ChanceOrQuestChance"]) != 0)
        zeros = [r for r in grows if num(r["ChanceOrQuestChance"]) == 0]
        share = max(0.0, 100.0 - explicit) / len(zeros) if (gid and zeros) else 0.0
        for r in grows:
            raw = num(r["ChanceOrQuestChance"])
            chance = abs(raw) if raw != 0 else share
            quest = raw < 0
            ref = num(r["mincountOrRef"])
            if ref < 0:
                if depth > 3:
                    continue
                times = max(1, num(r["maxcount"], 1))
                sub, sub_world = resolve_loot(-ref, refs, refs, depth + 1)
                if len(sub) > WORLD_POOL_SIZE:
                    world += len(sub)
                    continue
                world += sub_world
                for item, (c, q) in sub.items():
                    add(item, (chance / 100.0) * c * times, q or quest)
            else:
                if chance > 0:
                    add(r["item"], chance, quest)
    return out, world


# ---------------------------------------------------------------------------
# Boss scripts (ScriptDev2 in mangos-classic): ScriptName -> spells the AI casts
# ---------------------------------------------------------------------------

CAST_CALL = re.compile(r"(?:DoCastSpellIfCan|DoCastSpell|CastSpell|DoCast|AddSpellToCast|"
                       r"SpellListEntry|AddCombatAction)\s*\(([^;]*?)\)\s*[;{]", re.S)
SPELL_CONST = re.compile(r"\b(SPELL_[A-Z0-9_]+)\b")


def struct_body(src, name):
    m = re.search(r"struct\s+%s\b[^{;]*\{" % re.escape(name), src)
    if not m:
        return None
    i, depth = m.end(), 1
    while i < len(src) and depth:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return src[m.end():i]


def scan_scripts(root):
    by_script = {}
    if not root:
        return by_script
    base = os.path.join(root, "src", "game", "AI", "ScriptDevAI", "scripts")
    for dirpath, _, files in os.walk(base):
        for fn in files:
            if not fn.endswith(".cpp"):
                continue
            src = open(os.path.join(dirpath, fn), encoding="utf-8", errors="replace").read()
            src_nc = re.sub(r"//[^\n]*|/\*.*?\*/", "", src, flags=re.S)
            consts = {}
            for m in re.finditer(r"\b(SPELL_[A-Z0-9_]+)\s*=\s*(\d+)", src_nc):
                consts.setdefault(m.group(1), int(m.group(2)))
            if not consts:
                continue
            # script name -> AI struct, via GetAI_xxx factories
            factories = {}
            for m in re.finditer(r"\b(GetAI_\w+)\s*\([^)]*\)\s*\{(.*?)\}", src_nc, re.S):
                sm = re.search(r"new\s+(\w+)\s*\(", m.group(2))
                if sm:
                    factories[m.group(1)] = sm.group(1)
            for m in re.finditer(r'->Name\s*=\s*"(\w+)"\s*;(.*?)->RegisterSelf', src_nc, re.S):
                script, block = m.group(1), m.group(2)
                struct = None
                gm = re.search(r"GetAI\s*=\s*&(\w+)", block)
                if gm and gm.group(1) in factories:
                    struct = factories[gm.group(1)]
                else:
                    gm = re.search(r"GetNewAIInstance<(\w+)>", block)
                    if gm:
                        struct = gm.group(1)
                body = struct_body(src_nc, struct) if struct else None
                if not body:
                    continue
                spells = []
                for cm in CAST_CALL.finditer(body):
                    for name in SPELL_CONST.findall(cm.group(1)):
                        if name in consts and not SPELL_NOISE.search(name) and consts[name] not in spells:
                            spells.append(consts[name])
                # combat-action scripts cast through a switch on ACTION_ ids; catch remaining casts
                if not spells:
                    for name in SPELL_CONST.findall(body):
                        if name in consts and not SPELL_NOISE.search(name) and consts[name] not in spells:
                            spells.append(consts[name])
                if spells:
                    by_script[script] = spells[:16]
    return by_script


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cmangos-sql", required=True)
    ap.add_argument("--scripts")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Data"))
    a = ap.parse_args()

    sql = open(a.cmangos_sql, encoding="utf-8", errors="replace").read()
    ctpl = {r["Entry"]: r for r in sql_rows(sql, "creature_template")}
    loot = index_loot(sql_rows(sql, "creature_loot_template"))
    refs = index_loot(sql_rows(sql, "reference_loot_template"))
    skin = index_loot(sql_rows(sql, "skinning_loot_template"))
    pick = index_loot(sql_rows(sql, "pickpocketing_loot_template"))
    spell_lists = collections.defaultdict(list)
    for r in sql_rows(sql, "creature_spell_list"):
        spell_lists[r["Id"]].append((r["Position"], r["SpellId"]))
    tpl_spells = collections.defaultdict(list)
    for r in sql_rows(sql, "creature_template_spells"):
        for i in range(1, 11):
            if num(r.get("spell%d" % i)):
                tpl_spells[r["entry"]].append(r["spell%d" % i])
    eai = collections.defaultdict(list)
    for r in sql_rows(sql, "creature_ai_scripts"):
        for n in (1, 2, 3):
            if r["action%d_type" % n] == 11 and num(r["action%d_param1" % n]):
                eai[r["creature_id"]].append(r["action%d_param1" % n])
    creature_maps = collections.defaultdict(collections.Counter)
    for r in sql_rows(sql, "creature"):
        creature_maps[r["id"]][r["map"]] += 1
    bosses = set()
    encounter_map = {r["Id"]: r["MapId"] for r in sql_rows(sql, "instance_dungeon_encounters")}
    for r in sql_rows(sql, "instance_encounters"):
        if r["creditType"] == 0:
            bosses.add(r["creditEntry"])
            if r["entry"] in encounter_map and not creature_maps.get(r["creditEntry"]):
                creature_maps[r["creditEntry"]][encounter_map[r["entry"]]] += 1  # summoned bosses
    instance_maps = {r["map"] for r in sql_rows(sql, "instance_template")}
    print("cmangos: %d creatures, %d loot entries" % (len(ctpl), len(loot)))
    scripts = scan_scripts(a.scripts)
    print("boss scripts with spells: %d" % len(scripts))

    def loot_string(d, limit=MAX_LOOT):
        rows = sorted(((-c, iid, c, q) for iid, (c, q) in d.items()))
        return ",".join("%d:%s%s" % (iid, fmt_chance(c), ":q" if q else "") for _, iid, c, q in rows[:limit])

    cm_out, loot_out, extra_out, spell_out = {}, {}, {}, {}
    for nid, t in sorted(ctpl.items()):
        flags = ""
        if nid in bosses or (t.get("ScriptName") or "").startswith("boss_") or num(t.get("Rank")) == 3:
            flags += "B"
        if num(t.get("SkinningLootId")):
            flags += "S"
        if num(t.get("PickpocketLootId")):
            flags += "P"
        world = 0
        if num(t.get("LootId")):
            got, world = resolve_loot(t["LootId"], loot, refs)
            if got:
                loot_out[nid] = loot_string(got)
        display = next((num(t.get("ModelId%d" % k)) for k in (1, 2, 3, 4) if num(t.get("ModelId%d" % k))), 0)
        imap = next((m for m, _ in creature_maps.get(nid, collections.Counter()).most_common() if m in instance_maps), 0)
        cm_out[nid] = "^".join(str(x) for x in (
            num(t.get("Rank")), num(t.get("CreatureType")), num(t.get("Family")),
            num(t.get("MinLevelHealth")), num(t.get("MaxLevelHealth")), num(t.get("MaxLevelMana")),
            num(t.get("MinLootGold")), num(t.get("MaxLootGold")), flags, display, world, imap))
        ex = []
        if num(t.get("SkinningLootId")):
            sk, _ = resolve_loot(t["SkinningLootId"], skin, refs)
            if sk:
                ex.append("s=" + loot_string(sk, 8))
        if num(t.get("PickpocketLootId")):
            pp, _ = resolve_loot(t["PickpocketLootId"], pick, refs)
            if pp:
                ex.append("p=" + loot_string(pp, 12))
        if ex:
            extra_out[nid] = ";".join(ex)
        spells = []
        for sid in ([s for _, s in sorted(spell_lists.get(num(t.get("SpellList")), []))] + tpl_spells.get(nid, []) +
                    eai.get(nid, []) + scripts.get(t.get("ScriptName") or "", [])):
            if sid and sid not in spells:
                spells.append(sid)
        if spells:
            spell_out[nid] = ",".join(map(str, spells[:20]))

    # trainers: shared templates plus each trainer's own spells -> "spell:cost:level:skillValue"
    def trainer_list(rows):
        rows = sorted(rows, key=lambda r: (num(r["reqlevel"]), num(r["reqskillvalue"]), r["spell"]))
        return ",".join("%d:%d:%d:%d" % (r["spell"], num(r["spellcost"]), num(r["reqlevel"]), num(r["reqskillvalue"]))
                        for r in rows)
    tpl_rows = collections.defaultdict(list)
    for r in sql_rows(sql, "npc_trainer_template"):
        tpl_rows[r["entry"]].append(r)
    own_rows = collections.defaultdict(list)
    for r in sql_rows(sql, "npc_trainer"):
        own_rows[r["entry"]].append(r)
    ttpl_out = {k: trainer_list(v) for k, v in tpl_rows.items()}
    trainer_out = {}
    for nid, t in ctpl.items():
        parts = []
        if num(t.get("TrainerTemplateId")) in ttpl_out:
            parts.append("t%d" % num(t["TrainerTemplateId"]))
        if own_rows.get(nid):
            parts.append(trainer_list(own_rows[nid]))
        if parts:
            trainer_out[nid] = ";".join(parts)

    os.makedirs(a.out, exist_ok=True)
    for old in ("Npcs.lua", "Items.lua", "ItemQuests.lua", "Quests.lua", "Zones.lua", "DroppedBy.lua"):
        if os.path.exists(os.path.join(a.out, old)):
            os.remove(os.path.join(a.out, old))

    def write(fname, var, table, comment):
        path = os.path.join(a.out, fname)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("-- Generated by tools/build_data.py from CMaNGOS (Classic) - do not edit by hand.\n-- %s\n" % comment)
            f.write("local _, SB = ...\nSB.D.%s = {\n" % var)
            for k in sorted(table):
                f.write("[%s]=%s,\n" % (k, lua_str(table[k])))
            f.write("}\n")
        print("  %-14s %6d rows %8.0f KB" % (fname, len(table), os.path.getsize(path) / 1024))

    print("writing %s" % a.out)
    write("Classic.lua", "cm", cm_out, "rank^type^family^hpMin^hpMax^mana^goldMin^goldMax^flags(Boss,Skinnable,Pickpocket)^displayID^worldDropPool^instanceMap")
    write("Loot.lua", "loot", loot_out, "Loot per NPC: item:chance[:q], highest first (q = only drops while on the quest).")
    write("LootExtra.lua", "lootx", extra_out, "Skinning (s=) and pickpocket (p=) loot per NPC.")
    write("Spells.lua", "spells", spell_out, "Spells each NPC casts (spell lists, EventAI and boss scripts).")
    write("Trainers.lua", "trainer", trainer_out, "What each trainer teaches: tN = template N; spell:cost:level:skill,...")
    write("TrainerTemplates.lua", "ttpl", ttpl_out, "Shared trainer lists: spell:cost(copper):level:skill,...")


if __name__ == "__main__":
    main()
