#!/usr/bin/env python3
"""Builds Total Intel's bundled database (Data/*.lua).

Sources (all GPL-3.0, parsed as data, never executed):
  * QuestieDB       https://github.com/Questie/QuestieDB        - WoW: Forever NPCs, items, quests, zones
  * CMaNGOS classic https://github.com/cmangos/classic-db       - drop chances, health, gold, skinning, spell lists
  * CMaNGOS core    https://github.com/cmangos/mangos-classic   - boss abilities from the boss scripts (optional)

usage:
  python3 -I tools/build_data.py --questiedb PATH --cmangos-sql PATH/full.sql [--scripts PATH/mangos-classic] [--out Data]

Forever is the authority for *what exists* (names, levels, quests, who drops what).
CMaNGOS fills in what Forever's data doesn't carry: chances, stats, abilities. Its chances are
Classic numbers, and the addon labels them that way.
"""
import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sources import lua_list, read_questie_table, read_lua_assignment, sql_rows  # noqa: E402

WORLD_POOL_SIZE = 60    # a reference table bigger than this is a random world-drop pool
MAX_LOOT = 60           # loot rows kept per NPC (highest chance first)
MAX_DROPPED_BY = 40     # NPCs kept per item in the "dropped by" index
MAX_VENDORS = 12
MAX_ZONE_POINTS = 1     # representative spawn points kept per zone

ALLIANCE_MASK = 77 | (1 << 32)
HORDE_MASK = 178 | (1 << 33)

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


def L(t):
    return lua_list(t) or []


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
# Zones
# ---------------------------------------------------------------------------

def zone_tables(qdb):
    zdir = os.path.join(qdb, "support", "Forever", "Zones")
    names, uimap, alias, inst = {}, {}, {}, {}
    text = open(os.path.join(zdir, "areaIdToUiMapId.lua"), encoding="utf-8").read()
    for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+),\s*--\s*([^\n]+)", text):
        area, ui, comment = int(m.group(1)), int(m.group(2)), m.group(3).strip()
        if ui:
            uimap.setdefault(area, ui)
        nm = comment.split("->")[0].strip()
        if nm and not nm.lower().startswith(("existing", "synthetic", "referenced", "legacy", "retain")) and ":" not in nm:
            names.setdefault(area, nm)
    dtext = open(os.path.join(zdir, "dungeons.lua"), encoding="utf-8").read()
    for m in re.finditer(r"\[(\d+)\]\s*=\s*\{\"([^\"]+)\",(nil|\{[\d,\s]*\})", dtext):
        area, nm, alts = int(m.group(1)), m.group(2), m.group(3)
        names[area] = nm
        if alts != "nil":
            for a in re.findall(r"\d+", alts):
                alias[int(a)] = area
    enum = open(os.path.join(qdb, "src", "corrections", "enum", "zones.lua"), encoding="utf-8").read()
    for m in re.finditer(r"^\s*([A-Z0-9_]+)\s*=\s*(\d+),", enum, re.M):
        area = int(m.group(2))
        if area not in names and "PROTOTYPE" not in m.group(1):
            names[area] = m.group(1).replace("_", " ").title().replace("'S ", "'s ")
    itext = open(os.path.join(zdir, "instanceIdToAreaId.lua"), encoding="utf-8").read()
    zone_ids = {m.group(1): int(m.group(2)) for m in re.finditer(r"^\s*([A-Z0-9_]+)\s*=\s*(\d+),", enum, re.M)}
    for m in re.finditer(r"\[(\d+)\]\s*=\s*ZoneDB\.zoneIDs\.([A-Z0-9_]+)", itext):
        if m.group(2) in zone_ids:
            inst[int(m.group(1))] = zone_ids[m.group(2)]
    return names, uimap, alias, inst


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True)
    ap.add_argument("--cmangos-sql", required=True)
    ap.add_argument("--scripts")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Data"))
    a = ap.parse_args()

    fdir = os.path.join(a.questiedb, "data", "Forever")
    qnpc = read_questie_table(os.path.join(fdir, "foreverNpcDB.lua"), "QuestieDB.npcData")
    qitem = read_questie_table(os.path.join(fdir, "foreverItemDB.lua"), "QuestieDB.itemData")
    qquest = read_questie_table(os.path.join(fdir, "foreverQuestDB.lua"), "QuestieDB.questData")
    print("questie: %d npcs, %d items, %d quests" % (len(qnpc), len(qitem), len(qquest)))

    sql = open(a.cmangos_sql, encoding="utf-8", errors="replace").read()
    ctpl = {r["Entry"]: r for r in sql_rows(sql, "creature_template")}
    citem = {r["entry"]: r for r in sql_rows(sql, "item_template")}
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
    print("cmangos: %d creatures, %d items, %d loot entries" % (len(ctpl), len(citem), len(loot)))
    scripts = scan_scripts(a.scripts)
    print("boss scripts with spells: %d" % len(scripts))
    znames, uimap, zalias, inst = zone_tables(a.questiedb)

    # ---- items: names / quality ------------------------------------------------
    items = {}
    for iid, r in qitem.items():
        r = L(r)
        items[iid] = {"name": clean(r[0]), "ilvl": num(r[8]), "req": num(r[9]), "cls": num(r[11]), "sub": num(r[12])}
    for iid, it in items.items():
        c = citem.get(iid)
        it["q"] = num(c["Quality"], -1) if c else -1

    def ensure_item(iid):
        if iid not in items and iid in citem:
            c = citem[iid]
            items[iid] = {"name": clean(c["name"]), "ilvl": num(c["ItemLevel"]), "req": num(c["RequiredLevel"]),
                          "cls": num(c["class"]), "sub": num(c["subclass"]), "q": num(c["Quality"], -1)}
        return iid in items

    # ---- quests ------------------------------------------------------------------
    quests = {}
    npc_kill_for = collections.defaultdict(set)    # npc -> quests that need it killed
    item_obj_for = collections.defaultdict(set)    # item -> quests that need it
    for qid, r in qquest.items():
        r = L(r)
        r += [None] * (30 - len(r))
        races = num(r[5])
        fac = ""
        if races:
            a_ok, h_ok = bool(races & ALLIANCE_MASK), bool(races & HORDE_MASK)
            fac = "A" if a_ok and not h_ok else ("H" if h_ok and not a_ok else "")
        sb, fb = L(r[1]), L(r[2])
        starts = [x for x in L(sb[0] if sb else None) if x]
        ends = [x for x in L(fb[0] if fb else None) if x]
        obj = L(r[9])
        obj += [None] * (6 - len(obj))
        creatures = [L(o)[0] for o in L(obj[0]) if o and L(o)]
        objitems = [L(o)[0] for o in L(obj[2]) if o and L(o)]
        for kc in L(obj[4]):
            kc = L(kc)
            if kc:
                ids = [x for x in L(kc[0]) if x]
                creatures += ids
                if len(kc) > 1 and kc[1]:
                    creatures.append(kc[1])
        srcitems = [x for x in L(r[20]) if x]
        text = clean(" ".join(x for x in L(r[7]) if isinstance(x, str)))
        if len(text) > 400:
            text = text[:397] + "..."
        quests[qid] = {"name": clean(r[0]), "lvl": num(r[4]), "req": num(r[3]), "fac": fac,
                       "cls": num(r[6]), "text": text, "starts": starts, "ends": ends,
                       "kill": sorted(set(x for x in creatures if x)), "items": sorted(set(x for x in objitems if x))}
        for c in quests[qid]["kill"]:
            npc_kill_for[c].add(qid)
        for i in quests[qid]["items"] + srcitems:
            item_obj_for[i].add(qid)

    # ---- NPC loot ----------------------------------------------------------------
    npc_ids = set(qnpc.keys())
    npc_loot, npc_world = {}, {}
    for nid in npc_ids:
        t = ctpl.get(nid)
        if t and num(t["LootId"]):
            got, world = resolve_loot(t["LootId"], loot, refs)
            npc_loot[nid] = dict(got)
            npc_world[nid] = world
        else:
            npc_loot[nid] = {}
    # Forever's own "who drops this" list is the authority on presence; add what CMaNGOS lacks
    forever_only = 0
    for iid, r in qitem.items():
        for nid in L(L(r)[1]):
            if nid in npc_loot and iid not in npc_loot[nid]:
                npc_loot[nid][iid] = (None, iid in item_obj_for)
                forever_only += 1
    print("loot rows only in Forever data (no chance): %d" % forever_only)

    drop_sources = collections.defaultdict(set)
    for nid, d in npc_loot.items():
        for iid in d:
            drop_sources[iid].add(nid)

    def loot_string(d, limit=MAX_LOOT):
        rows = []
        for iid, (c, q) in d.items():
            if not ensure_item(iid):
                continue
            rows.append((-(c if c is not None else -1), iid, c, q))
        rows.sort()
        parts = []
        for _, iid, c, q in rows[:limit]:
            cs = "" if c is None else fmt_chance(c)
            parts.append("%d:%s%s" % (iid, cs, ":q" if q else ""))
        return ",".join(parts)

    # ---- per-NPC records -------------------------------------------------------
    npc_out, loot_out, extra_out, spell_out = {}, {}, {}, {}
    drop_for = collections.defaultdict(list)   # item -> [(chance, npc)]
    for nid in sorted(npc_ids):
        r = L(qnpc[nid])
        r += [None] * (16 - len(r))
        name = clean(r[0])
        if not name or "(Only GM" in name or name.startswith("[DND]"):
            continue
        t = ctpl.get(nid) or {}
        npcflags = num(r[14]) or num(t.get("NpcFlags"))
        flags = ""
        if nid in bosses or (t.get("ScriptName") or "").startswith("boss_") or num(r[5]) == 3:
            flags += "B"
        if num(t.get("SkinningLootId")):
            flags += "S"
        if num(t.get("PickpocketLootId")):
            flags += "P"
        if npcflags & NPC_FLAG_VENDOR:
            flags += "V"
        if npcflags & NPC_FLAG_TRAINER:
            flags += "T"
        if npcflags & NPC_FLAG_FLIGHT:
            flags += "F"
        if npcflags & NPC_FLAG_REPAIR:
            flags += "R"
        zones = []
        spawns = r[6] if isinstance(r[6], dict) else {}
        for area, pts in spawns.items():
            pts = [L(p) for p in L(pts) if isinstance(p, dict)]
            pts = [p for p in pts if len(p) >= 2 and isinstance(p[0], (int, float)) and p[0] >= 0]
            if not pts:
                zones.append((0, area, None))
                continue
            cx = sum(p[0] for p in pts) / len(pts)
            cy = sum(p[1] for p in pts) / len(pts)
            best = min(pts, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
            zones.append((-len(pts), area, best))
        zones.sort(key=lambda z: (z[0], z[1]))
        zstr = ",".join("%d:%s:%s:%d" % (area, ("%.1f" % p[0]) if p else "", ("%.1f" % p[1]) if p else "", -cnt)
                        for cnt, area, p in zones)
        if not zones and num(r[8]):
            zstr = "%d:::0" % num(r[8])
        elif not zones and creature_maps.get(nid):
            # instance mobs have no world spawns in Questie; place them in their instance
            areas = [inst[m] for m, _ in creature_maps[nid].most_common() if m in inst]
            if areas:
                zstr = "%d:::%d" % (areas[0], sum(creature_maps[nid].values()))
        rank = num(r[5]) if r[5] is not None else num(t.get("Rank"))
        hmin, hmax = num(t.get("MinLevelHealth")), num(t.get("MaxLevelHealth"))
        # quest relations
        starts = [x for x in L(r[9]) if x]
        ends = [x for x in L(r[10]) if x]
        kill = sorted(npc_kill_for.get(nid, ()))
        drops_for = []
        for iid, (c, q) in npc_loot[nid].items():
            # only real quest drops: quest-only rolls, quest-class items, or items few mobs drop.
            # (Linen Cloth is a turn-in objective but not a reason to call every humanoid "quest relevant")
            if not (q or items.get(iid, {}).get("cls") == 12 or len(drop_sources.get(iid, ())) <= 20):
                continue
            for qid in sorted(item_obj_for.get(iid, ())):
                drops_for.append("%d/%d" % (qid, iid))
        fields = [
            name, clean(r[13] or t.get("SubName") or ""), str(num(r[3])), str(num(r[4])), str(rank),
            str(num(t.get("CreatureType"))), str(num(t.get("Family"))), str(hmin), str(hmax),
            str(num(t.get("MaxLevelMana"))), str(num(t.get("MinLootGold"))), str(num(t.get("MaxLootGold"))),
            flags, zstr, r[12] or "",
            ",".join(map(str, starts)), ",".join(map(str, ends)), ",".join(map(str, kill)), ",".join(sorted(set(drops_for))),
            str(npc_world.get(nid, 0)), "1" if nid in ctpl else "0",
            str(next((num(t.get("ModelId%d" % k)) for k in (1, 2, 3, 4) if num(t.get("ModelId%d" % k))), 0)),
        ]
        npc_out[nid] = "^".join(fields)
        if npc_loot[nid]:
            loot_out[nid] = loot_string(npc_loot[nid])
            for iid, (c, q) in npc_loot[nid].items():
                drop_for[iid].append((c if c is not None else -1, nid))
        ex = []
        if num(t.get("SkinningLootId")):
            s, _ = resolve_loot(t["SkinningLootId"], skin, refs)
            if s:
                ex.append("s=" + loot_string(s, 8))
        if num(t.get("PickpocketLootId")):
            p, _ = resolve_loot(t["PickpocketLootId"], pick, refs)
            if p:
                ex.append("p=" + loot_string(p, 12))
        if ex:
            extra_out[nid] = ";".join(ex)
        spells = []
        for sid in ([s for _, s in sorted(spell_lists.get(num(t.get("SpellList")), []))] + tpl_spells.get(nid, []) +
                    eai.get(nid, []) + scripts.get(t.get("ScriptName") or "", [])):
            if sid and sid not in spells:
                spells.append(sid)
        if spells:
            spell_out[nid] = ",".join(map(str, spells[:20]))

    # ---- item index ------------------------------------------------------------
    item_out, dropby_out, itemq_out = {}, {}, {}
    for iid, r in qitem.items():
        r = L(r)
        r += [None] * (16 - len(r))
        parts = []
        objq = sorted(item_obj_for.get(iid, ()))
        if objq:
            parts.append("o=" + ",".join(map(str, objq)))
        if num(r[4]):
            parts.append("s=%d" % num(r[4]))
        rew = [x for x in L(r[5]) if x]
        if rew:
            parts.append("r=" + ",".join(map(str, rew[:12])))
        ven = [x for x in L(r[13]) if x]
        if ven:
            parts.append("v=%d|" % len(ven) + ",".join(map(str, ven[:MAX_VENDORS])))
        cont = [x for x in L(r[3]) if x]
        if cont:
            parts.append("c=" + ",".join(map(str, cont[:12])))
        objs = [x for x in L(r[2]) if x]
        if objs:
            parts.append("g=%d" % len(objs))
        if parts:
            itemq_out[iid] = ";".join(parts)
    for iid, lst in drop_for.items():
        lst.sort(key=lambda x: (-x[0], x[1]))
        dropby_out[iid] = "%d|" % len(lst) + ",".join(
            "%d:%s" % (n, "" if c < 0 else fmt_chance(c)) for c, n in lst[:MAX_DROPPED_BY])
    for iid, it in items.items():
        item_out[iid] = "^".join([it["name"], str(it["q"]), str(it["ilvl"]), str(it["req"]), str(it["cls"]), str(it["sub"])])

    quest_out = {}
    for qid, q in quests.items():
        quest_out[qid] = "^".join([q["name"], str(q["lvl"]), str(q["req"]), q["fac"], str(q["cls"]), q["text"],
                                   ",".join(map(str, q["starts"])), ",".join(map(str, q["ends"])),
                                   ",".join(map(str, q["kill"])), ",".join(map(str, q["items"]))])

    # ---- write -----------------------------------------------------------------
    os.makedirs(a.out, exist_ok=True)

    def write(fname, var, table, comment, numeric_values=False):
        path = os.path.join(a.out, fname)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("-- Generated by tools/build_data.py - do not edit by hand.\n-- %s\n" % comment)
            f.write("local _, SB = ...\nSB.D.%s = {\n" % var)
            for k in sorted(table):
                v = table[k]
                f.write("[%s]=%s,\n" % (k, v if numeric_values else lua_str(v)))
            f.write("}\n")
        print("  %-14s %6d rows %8.0f KB" % (fname, len(table), os.path.getsize(path) / 1024))

    print("writing %s" % a.out)
    write("Npcs.lua", "npc", npc_out, "NPC records. Fields: see Database.lua (NPC_FIELDS).")
    write("Loot.lua", "loot", loot_out, "Loot per NPC: item:chance[:q], highest first. Chance is CMaNGOS Classic; empty = Forever lists it without a chance.")
    write("LootExtra.lua", "lootx", extra_out, "Skinning (s=) and pickpocket (p=) loot per NPC.")
    write("Spells.lua", "spells", spell_out, "Spells each NPC casts (spell lists, EventAI and boss scripts).")
    write("Items.lua", "item", item_out, "Items: name^quality^itemLevel^requiredLevel^class^subclass. Quality -1 = ask the game.")
    write("DroppedBy.lua", "dropby", dropby_out, "Item -> total|npc:chance, highest chance first.")
    write("ItemQuests.lua", "itemq", itemq_out, "Item uses: o=objective of, s=starts, r=reward of, v=vendors, c=found in, g=objects.")
    write("Quests.lua", "quest", quest_out, "Quests: name^level^reqLevel^faction^classMask^text^starters^enders^killNpcs^items.")
    zones = {k: lua_str(v) for k, v in znames.items()}
    path = os.path.join(a.out, "Zones.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tools/build_data.py - do not edit by hand.\nlocal _, SB = ...\n")
        for var, table in (("zoneName", zones), ("uiMap", uimap), ("zoneAlias", zalias), ("instanceArea", inst)):
            f.write("SB.D.%s = {\n" % var)
            for k in sorted(table):
                f.write("[%d]=%s,\n" % (k, table[k]))
            f.write("}\n")
    print("  Zones.lua      %8.0f KB" % (os.path.getsize(path) / 1024))


if __name__ == "__main__":
    main()
