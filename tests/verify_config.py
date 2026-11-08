#!/usr/bin/env python3
"""
Static check for Phase 2 Step 1: the Luau Config modules must match the GDD tables
and the numbers the economy simulation was tuned with (tools/economy_sim.py).

This parses the Luau table literals directly (no Luau runtime needed), so it
verifies DATA, not Roblox behaviour. Run: python3 tests/verify_config.py
Exit code 0 = every check passed.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import economy_sim as SIM  # noqa: E402

CONFIG = ROOT / "src" / "shared" / "Config"
GDD = (ROOT / "SeekForTreasure_GDD.md").read_text(encoding="utf-8")

# ----------------------------------------------------------------------------- parser

TOKEN = re.compile(
    r"""
    (?P<ws>\s+)
  | (?P<lcomment>--\[\[.*?\]\])
  | (?P<comment>--[^\n]*)
  | (?P<string>"(?:\\.|[^"\\])*")
  | (?P<number>\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[{}\[\]=,;().:<>|?*+/-])
    """,
    re.VERBOSE | re.DOTALL,
)


def tokenize(src: str):
    pos = 0
    out = []
    while pos < len(src):
        m = TOKEN.match(src, pos)
        if not m:
            raise ValueError(f"unexpected character {src[pos]!r} at {pos}")
        pos = m.end()
        kind = m.lastgroup
        if kind in ("ws", "comment", "lcomment"):
            continue
        out.append((kind, m.group(kind)))
    return out


class Parser:
    def __init__(self, tokens):
        self.t = tokens
        self.i = 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else (None, None)

    def take(self, value=None):
        tok = self.t[self.i]
        if value is not None and tok[1] != value:
            raise ValueError(f"expected {value!r}, got {tok[1]!r}")
        self.i += 1
        return tok

    def value(self):
        kind, val = self.peek()
        if val == "{":
            return self.table()
        self.take()
        if kind == "string":
            return bytes(val[1:-1], "utf-8").decode("unicode_escape")
        if kind == "number":
            n = float(val.replace("_", ""))
            return int(n) if n.is_integer() and "." not in val else n
        if val == "true":
            return True
        if val == "false":
            return False
        if val == "nil":
            return None
        raise ValueError(f"unsupported value token {val!r}")

    def table(self):
        self.take("{")
        result: dict = {}
        n = 0
        while self.peek()[1] != "}":
            kind, val = self.peek()
            if val == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                result[key] = self.value()
            elif kind == "name" and self.peek(1)[1] == "=":
                self.take()
                self.take("=")
                result[val] = self.value()
            else:
                n += 1
                result[n] = self.value()
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        if result and all(isinstance(k, int) for k in result) and list(result) == list(range(1, len(result) + 1)):
            return [result[k] for k in range(1, len(result) + 1)]
        return result


def load(module: str):
    src = (CONFIG / module).read_text(encoding="utf-8")
    m = re.search(r"local\s+\w+\s*:\s*[^=]+=\s*\{", src)
    if not m:
        raise ValueError(f"{module}: no 'local X: T = {{' data literal found")
    tokens = tokenize(src[m.end() - 1 :])
    p = Parser(tokens)
    return p.table()


# ----------------------------------------------------------------------------- GDD tables


def gdd_table_after(heading: str) -> list[list[str]]:
    """Rows (as cell lists) of the first markdown table after `heading`."""
    start = GDD.index(heading)
    rows = []
    started = False
    for line in GDD[start:].splitlines()[1:]:
        if line.startswith("|"):
            started = True
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not all(re.fullmatch(r":?-+:?", c) for c in cells):
                rows.append(cells)
        elif started:
            break
    return rows[1:]  # drop the header row


# ----------------------------------------------------------------------------- checks

results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = ""):
    results.append((name, bool(ok), detail))


def close(a, b, eps=1e-9):
    return abs(float(a) - float(b)) <= eps * max(1.0, abs(float(b)))


# Rarities vs sim + GDD §2.1
rar = load("Rarities.luau")
check("Rarities: 10 tiers", len(rar) == 10, f"{len(rar)}")
for i, r in enumerate(rar):
    name, one_in, cps = SIM.RARITIES[i]
    check(f"Rarity {i + 1} name", r["name"] == name, f"{r['name']} vs {name}")
    check(f"Rarity {r['name']} odds", r["oneIn"] == (one_in or 0), f"{r['oneIn']} vs {one_in}")
    check(f"Rarity {r['name']} base cash/s", r["baseCps"] == cps, f"{r['baseCps']} vs {cps}")
    check(f"Rarity {r['name']} order", r["order"] == i + 1)
gdd_rar = gdd_table_after("### 2.1 Rarity table")
reveal_tier = {"R0": 0, "R1": 1, "R2": 2, "R3": 3, "R4": 4, "R5": 5, "R6": 6, "R7": 7, "R8": 8}
for r, row in zip(rar, gdd_rar):
    hexes = re.findall(r"#[0-9A-F]{6}", row[4])
    check(f"Rarity {r['name']} color = GDD", hexes and hexes[0] == r["color"], f"{r['color']} vs {hexes}")
    if len(hexes) > 1:
        check(f"Rarity {r['name']} gradient end = GDD", r.get("colorEnd") == hexes[1], f"{r.get('colorEnd')} vs {hexes[1]}")
    tier = re.match(r"R\d", row[5]).group(0)
    check(f"Rarity {r['name']} reveal tier = GDD", r["revealTier"] == reveal_tier[tier], f"{r['revealTier']} vs {tier}")
check("Rarity Secret rainbow edge", rar[9].get("rainbowEdge") is True)

# Mutations vs sim
mut = load("Mutations.luau")
check("Mutations: total cap", mut["totalCap"] == SIM.MUTATION_TOTAL_CAP)
fam = {f["id"]: f for f in mut["families"]}
for fid, sim_list, chance in (("finish", SIM.FINISH, SIM.FINISH_BASE_CHANCE), ("aura", SIM.AURA, SIM.AURA_BASE_CHANCE)):
    f = fam[fid]
    check(f"Mutations {fid}: base chance", close(f["baseChance"], chance), f"{f['baseChance']} vs {chance}")
    check(f"Mutations {fid}: chance cap", close(f["chanceCap"], SIM.MUTATION_CHANCE_CAP))
    check(f"Mutations {fid}: count", len(f["entries"]) == len(sim_list))
    for e, (n, m, w) in zip(f["entries"], sim_list):
        check(f"Mutation {n}", e["name"] == n and close(e["mult"], m) and e["weight"] == w and e["family"] == fid,
              f"{e['name']} x{e['mult']} w{e['weight']}")
bits = [e["bit"] for f in mut["families"] for e in f["entries"]]
check("Mutation bits unique powers of two", len(set(bits)) == len(bits) and all(b & (b - 1) == 0 for b in bits), str(bits))
worst = max(min(mut["totalCap"], fm * am) for fm in [1] + [e["mult"] for e in fam["finish"]["entries"]]
            for am in [1] + [e["mult"] for e in fam["aura"]["entries"]])
check("Mutation cap holds for every combination", worst <= 10, f"max {worst}")

# Pity vs sim (sim tiers are 0-based)
pity = load("Pity.luau")
check("Pity floors", [(p["minRarity"], p["guaranteeAt"]) for p in pity] == [(t + 1, n) for t, n in SIM.PITY],
      str([(p["minRarity"], p["guaranteeAt"]) for p in pity]))

# Tools vs sim + GDD §5.1 Pets names
tools = load("Tools.luau")
check("Tools: min interval", close(tools["minSearchInterval"], SIM.MIN_SEARCH_INTERVAL))
check("Tools: 8 tiers", len(tools["tiers"]) == len(SIM.TOOLS))
for t, (iv, lk, mu, pr) in zip(tools["tiers"], SIM.TOOLS):
    check(f"Tool T{t['tier']}", close(t["interval"], iv) and close(t["luck"], lk) and close(t["mutation"], mu) and t["basePrice"] == pr,
          f"{t['interval']}s L{t['luck']} M{t['mutation']} ${t['basePrice']}")

# Pets segment vs sim + GDD
pets = load("Segments/Pets.luau")
sim_pets = SIM.SEGMENTS[0]
check("Pets: id/income/tool price/unlock", (pets["id"], pets["incomeMult"], pets["toolPriceMult"], pets["unlockCost"]) == sim_pets,
      str((pets["id"], pets["incomeMult"], pets["toolPriceMult"], pets["unlockCost"])))
# the second table under 5.1 holds the per-segment names and prices
sec = GDD[GDD.index("| Tier | Pets (Whistles) |"):]
name_rows = [[c.strip() for c in l.strip().strip("|").split("|")] for l in sec.splitlines()[2:10]]
for t, row in zip(pets["tools"], name_rows):
    price = tools["tiers"][t["tier"] - 1]["basePrice"] * pets["toolPriceMult"]
    gdd_price = int(row[2].replace(",", ""))
    check(f"Pets tool T{t['tier']} name/price = GDD", t["name"] == row[1] and price == gdd_price, f"{t['name']} ${price} vs {row[1]} ${gdd_price}")
gdd_pets = gdd_table_after("#### Pets — Pawprint Meadow")
check("Pets: 12 treasures", len(pets["treasures"]) == 12 == len(gdd_pets))
rarity_by_name = {r["name"]: r["order"] for r in rar}
for tr, row in zip(pets["treasures"], gdd_pets):
    check(f"Treasure {tr['name']} = GDD", tr["name"] == row[1] and tr["description"] == row[2] and tr["rarity"] == rarity_by_name[row[0]],
          f"{tr['name']} r{tr['rarity']}")
counts = [sum(1 for tr in pets["treasures"] if tr["rarity"] == i + 1) for i in range(10)]
check("Pets: treasures per rarity = sim", counts == SIM.TREASURES_PER_RARITY, str(counts))
ids = [tr["id"] for tr in pets["treasures"]] + [t["id"] for t in pets["tools"]]
check("Pets: ids unique", len(set(ids)) == len(ids))

# Potions vs sim
pot = load("Potions.luau")
check("Potions: max remaining 60 min", pot["maxRemainingSeconds"] == 3600)
by_id = {p["id"]: p for p in pot["list"]}
# the sim models the four MVP potions; the Diamond Potion (GDD §15.3) has no cash effect
check("Potions: luck/speed/mutation/cash + diamond", sorted(by_id) == sorted(list(SIM.POTION_PRICE_SECONDS) + ["diamond"]))
check("Potions: 5-min restock, every potion in the stock table",
      pot["restockSeconds"] == 300 and sorted(s["id"] for s in pot["stock"]) == sorted(by_id))
for s in pot["stock"]:
    check(f"Stock {s['id']} chance/range", 0 < s["chance"] <= 1 and 1 <= s["min"] <= s["max"])
for pid, p in by_id.items():
    if pid == "diamond":
        continue
    check(f"Potion {pid}", p["durationSeconds"] == SIM.POTION_DURATION and p["priceSeconds"] == SIM.POTION_PRICE_SECONDS[pid]
          and p["minPrice"] == SIM.POTION_MIN_PRICE[pid], f"{p['durationSeconds']}s {p['priceSeconds']}s ${p['minPrice']}")
check("Potion multipliers (luck 2, speed 1.5, mutation 2, cash 2)",
      [by_id[k]["multiplier"] for k in ("luck", "speed", "mutation", "cash")] == [2, 1.5, 2, 2])

# Upgrades vs sim
up = load("Upgrades.luau")["slots"]
check("Slots", (up["start"], up["max"], up["basePrice"], up["growth"]) == (SIM.START_SLOTS, SIM.MAX_SLOTS, SIM.SLOT_BASE_PRICE, SIM.SLOT_GROWTH),
      str(up))
prices_row = GDD[GDD.index("Plot slot ladder:"):].splitlines()[4]
cfg_ladder = [up["basePrice"] * up["growth"] ** n for n in range(up["max"] - up["start"])]
gdd_ladder_cells = [c.strip() for c in prices_row.strip().strip("|").split("|")][1:]


def parse_money(s: str) -> float:
    s = s.replace(",", "")
    mult = 1.0
    if s.endswith("M"):
        mult, s = 1e6, s[:-1]
    return float(s) * mult


ok = all(abs(parse_money(g) - c) / c < 0.01 for g, c in zip(gdd_ladder_cells, cfg_ladder)) and len(gdd_ladder_cells) == len(cfg_ladder)
check("Slot price ladder = GDD (within display rounding)", ok, f"{len(gdd_ladder_cells)} prices")

# Rebirth vs sim
rb = load("Rebirth.luau")
check("Rebirth costs/growth", (rb["baseCost"], rb["mvpBaseCost"], rb["growth"]) == (SIM.REBIRTH_BASE_COST, SIM.MVP_REBIRTH_BASE_COST, SIM.REBIRTH_GROWTH), str(rb))
check("Rebirth bonuses", close(rb["cashBonusPerRebirth"], SIM.REBIRTH_CASH_BONUS) and close(rb["luckBonusPerRebirth"], SIM.REBIRTH_LUCK_BONUS))
check("Rebirth keeps all treasures (decision)", rb["keepAllTreasures"] is True and SIM.KEEP_ALL_TREASURES_ON_REBIRTH is True)

# Economy vs sim
eco = load("Economy.luau")
check("Economy luck cap", eco["luckCap"] == SIM.LUCK_CAP)
check("Economy sell seconds", eco["sellSeconds"] == SIM.SELL_SECONDS)
check("Economy offline rate/cap", close(eco["offlineRate"], SIM.OFFLINE_RATE) and eco["offlineCapSeconds"] == SIM.OFFLINE_CAP_S)
check("Economy inventory cap 300 / auto-sell below Legendary", eco["inventoryCap"] == 300 and eco["autoSellBelowRarity"] == 5)

# Plot
plot = load("Plot.luau")
check("Plot: 8 plots, 4x5 grid = max slots", plot["plotsPerServer"] == 8 and plot["gridColumns"] * plot["gridRows"] == SIM.MAX_SLOTS)
check("Plot: pedestal band per rarity", len(plot["pedestalByRarity"]) == 10)

# Index vs sim
idx = load("Index.luau")
check("Index milestones", [(m["fraction"], m["luckBonus"]) for m in idx["milestones"]] == SIM.INDEX_MILESTONES,
      str([(m["fraction"], m["luckBonus"]) for m in idx["milestones"]]))

# Onboarding vs sim (sim tiers 0-based)
onb = load("Onboarding.luau")
check("Onboarding forced finds", onb["forcedMinRarity"] == {k: v + 1 for k, v in SIM.ONBOARDING_FORCED.items()}, str(onb["forcedMinRarity"]))
check("Onboarding: 5 tutorial steps", len(onb["tutorialSteps"]) == 5)

# Reveal vs GDD §9.1
rev = load("Reveal.luau")
gdd_rev = gdd_table_after("### 9.1 Reveal cinematic (MVP)")
check("Reveal: 9 tiers", len(rev["tiers"]) == 9 == len(gdd_rev))
for t, row in zip(rev["tiers"], gdd_rev):
    secs = float(re.match(r"[\d.]+", row[2]).group(0))
    shake = 0 if row[4] == "none" else int(re.match(r"\d+", row[4]).group(0))
    check(f"Reveal R{t['tier']} length/shake = GDD", close(t["seconds"], secs) and t["shakePx"] == shake, f"{t['seconds']}s {t['shakePx']}px")
check("Reveal banner Mythic+ 5 s queue 3", rev["banner"] == {"minRarity": 6, "seconds": 5, "queueMax": 3})

# Social vs GDD §9.7
soc = load("Social.luau")
check("Friend boost +10%/friend cap +50%", close(soc["friendBoost"]["perFriend"], 0.1) and close(soc["friendBoost"]["cap"], 0.5))
check("Codes: 1-20 chars, 10 fails / 10 min -> 10 min cooldown",
      soc["codes"] == {"maxLength": 20, "maxFailures": 10, "failureWindowSeconds": 600, "cooldownSeconds": 600})
check("Live like counter disabled until approved", soc["likeCounter"]["enabled"] is False and soc["likeCounter"]["proxyBaseUrl"] == "")

# No code strings may live in shared (client-readable) config
shared_src = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "src" / "shared").rglob("*.luau"))
check("No code strings in ReplicatedStorage", "SEEKATREASURE" not in shared_src.upper())

# Every Config module is strict and frozen
for p in sorted(CONFIG.rglob("*.luau")):
    txt = p.read_text(encoding="utf-8")
    rel = p.relative_to(CONFIG)
    check(f"{rel}: --!strict", txt.startswith("--!strict"))
    if p.name != "Pets.luau":  # Pets is frozen by Segments/init
        check(f"{rel}: DeepFreeze", "DeepFreeze(" in txt)

# ----------------------------------------------------------------------------- report
failed = [r for r in results if not r[1]]
for name, ok, detail in results:
    if not ok:
        print(f"FAIL  {name}  {detail}")
print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
sys.exit(1 if failed else 0)
