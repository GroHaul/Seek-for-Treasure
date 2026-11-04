#!/usr/bin/env python3
"""
Seek for Treasure - roll + progression simulation (Phase 1 design tool).

This is NOT game code. It mirrors the numeric tables in SeekForTreasure_GDD.md so
the economy can be tuned before any Luau is written. Phase 2's shared Config
modules must carry exactly these numbers.

Usage:
  python3 tools/economy_sim.py                 # everything (roll check + all scenarios)
  python3 tools/economy_sim.py --runs 300      # more Monte-Carlo runs per scenario
  python3 tools/economy_sim.py --rolls 1000000 # size of the roll-distribution check
"""
from __future__ import annotations

import argparse
import math
import random
import statistics
from dataclasses import dataclass, field

# --------------------------------------------------------------------------------------
# DATA (must match the GDD tables 1:1)
# --------------------------------------------------------------------------------------

# name, base "1 in N" (Common = remainder), base cash/sec (segment multiplier 1)
RARITIES = [
    ("Common", None, 1),
    ("Uncommon", 4, 3),
    ("Rare", 12, 10),
    ("Epic", 50, 40),
    ("Legendary", 250, 200),
    ("Mythic", 1_500, 1_500),
    ("Divine", 10_000, 12_000),
    ("Celestial", 75_000, 100_000),
    ("Cosmic", 500_000, 900_000),
    ("Secret", 5_000_000, 10_000_000),
]
NAMES = [r[0] for r in RARITIES]
ONE_IN = [r[1] for r in RARITIES]
BASE_CPS = [r[2] for r in RARITIES]
MYTHIC = 5  # index of Mythic

LUCK_CAP = 25.0

# Mutation families. (name, multiplier, weight within family)
FINISH = [("Golden", 2.0, 55), ("Crystal", 3.0, 25), ("Rainbow", 5.0, 12), ("Shadow", 7.0, 6), ("Prismatic", 10.0, 2)]
AURA = [("Glowing", 1.5, 50), ("Blazing", 2.0, 30), ("Electric", 2.5, 15), ("Starlit", 3.0, 5)]
FINISH_BASE_CHANCE = 0.04
AURA_BASE_CHANCE = 0.015
MUTATION_CHANCE_CAP = 0.5
MUTATION_TOTAL_CAP = 10.0

# Pity: (min tier index guaranteed, Nth dry search is forced)
PITY = [(3, 120), (4, 800), (5, 5_000)]  # Epic+, Legendary+, Mythic+

# Segments: id, income multiplier, tool price multiplier, unlock cost, treasures per rarity
SEGMENTS = [
    ("pets", 1, 1, 0),
    ("fish", 10, 25, 1_500_000),
    ("cars", 100, 625, 600_000_000),
    ("anime", 1_000, 15_625, 250_000_000_000),
]
TREASURES_PER_RARITY = [2, 2, 1, 1, 1, 1, 1, 1, 1, 1]  # 12 per segment

# Tool tiers (same shape in every segment): search interval s, luck x, mutation x, base price
TOOLS = [
    (3.00, 1.00, 1.00, 0),
    (2.60, 1.10, 1.00, 1_000),
    (2.25, 1.25, 1.10, 2_500),
    (1.95, 1.45, 1.25, 15_000),
    (1.65, 1.70, 1.40, 70_000),
    (1.40, 2.00, 1.60, 250_000),
    (1.20, 2.30, 1.80, 900_000),
    (1.00, 2.60, 2.00, 3_000_000),
]
MIN_SEARCH_INTERVAL = 0.5

# Plot slots
START_SLOTS = 6
MAX_SLOTS = 20
SLOT_BASE_PRICE = 1_000
SLOT_GROWTH = 2.25


def slot_price(current_slots: int) -> float:
    """Price of the next slot when the plot currently has `current_slots`."""
    n = current_slots - START_SLOTS  # 0 for the 7th slot
    return SLOT_BASE_PRICE * SLOT_GROWTH ** n


# Rebirth
REBIRTH_BASE_COST = 2_500_000_000
REBIRTH_GROWTH = 12
MVP_REBIRTH_BASE_COST = 400_000_000  # Pets-only MVP build (one segment), tuned to the same 3 h target
REBIRTH_CASH_BONUS = 0.5  # +50% cash per rebirth (additive)
REBIRTH_LUCK_BONUS = 0.10  # +10% luck per rebirth (additive)
KEEP_ON_REBIRTH_MIN_RARITY = MYTHIC  # Mythic+ treasures are kept


def rebirth_cost(rebirths: int) -> float:
    base = MVP_REBIRTH_BASE_COST if len(SEGMENTS) == 1 else REBIRTH_BASE_COST
    return base * REBIRTH_GROWTH ** rebirths


# Index milestones per segment: fraction discovered -> permanent luck bonus
INDEX_MILESTONES = [(0.50, 0.02), (0.75, 0.03), (1.00, 0.05)]

# Selling, offline, onboarding, potions
SELL_SECONDS = 10  # sell value = 10 s of the treasure's base income
OFFLINE_RATE = 0.5
OFFLINE_CAP_S = 2 * 3600
ONBOARDING_FORCED = {3: 1, 8: 2}  # search #3 -> Uncommon+, search #8 -> Rare+
POTION_DURATION = 600
POTION_PRICE_SECONDS = {"luck": 150, "speed": 150, "mutation": 120, "cash": 240}
POTION_MIN_PRICE = {"luck": 250, "speed": 250, "mutation": 200, "cash": 400}

# Player behaviour model
START_WALK_S = 8  # spawn -> search zone on foot
FIRST_COLLECT_AT = 40  # tutorial sends you to the Collect pad at ~40 s
COLLECT_MIN_GAP = 20  # won't walk back more often than this
COLLECT_MAX_GAP = 120  # always collects at least this often
COLLECT_WALK_S = 6  # seconds of no searching per collect trip

# --------------------------------------------------------------------------------------
# ROLL MATH (the algorithm the Luau RollService will implement)
# --------------------------------------------------------------------------------------

_prob_cache: dict[float, list[float]] = {}


def prob_table(luck: float) -> list[float]:
    """Exact probability of each tier for a given total luck.

    p_i = luck / N_i for every tier above Common, assigned from the rarest tier down;
    each p_i is clamped so the running total never exceeds 1. Common takes the
    remainder. Sum is exactly 1 by construction.
    """
    luck = max(1.0, min(LUCK_CAP, luck))
    cached = _prob_cache.get(luck)
    if cached is not None:
        return cached
    probs = [0.0] * len(RARITIES)
    total = 0.0
    for i in range(len(RARITIES) - 1, 0, -1):
        p = min(luck / ONE_IN[i], 1.0 - total)
        probs[i] = max(0.0, p)
        total += probs[i]
    probs[0] = max(0.0, 1.0 - total)
    _prob_cache[luck] = probs
    return probs


def roll_tier(rng: random.Random, luck: float, min_tier: int = 0) -> int:
    probs = prob_table(luck)
    if min_tier > 0:
        span = sum(probs[min_tier:])
        u = rng.random() * span
    else:
        u = rng.random()
    acc = 0.0
    for i in range(len(probs) - 1, min_tier - 1, -1):
        acc += probs[i]
        if u < acc:
            return i
    return min_tier


def roll_family(rng: random.Random, family, chance: float):
    if rng.random() >= min(MUTATION_CHANCE_CAP, chance):
        return None
    total = sum(w for _, _, w in family)
    u = rng.random() * total
    for name, mult, w in family:
        u -= w
        if u < 0:
            return (name, mult)
    return family[-1][0], family[-1][1]


def mutation_multiplier(finish, aura) -> float:
    m = (finish[1] if finish else 1.0) * (aura[1] if aura else 1.0)
    return min(MUTATION_TOTAL_CAP, m)


# --------------------------------------------------------------------------------------
# PLAYER MODEL
# --------------------------------------------------------------------------------------


@dataclass
class Treasure:
    income: float  # base income incl. segment + mutation (before rebirth/boosts)
    tier: int


@dataclass
class Player:
    rng: random.Random
    onboarding: bool = True
    potions: bool = False
    t: float = 0.0
    cash: float = 0.0
    vault: float = 0.0
    rebirths: int = 0
    unlocked: int = 1
    seg: int = 0
    tools: list[int] = field(default_factory=lambda: [0, 0, 0, 0])
    slots: int = START_SLOTS
    owned: list[Treasure] = field(default_factory=list)  # best MAX_SLOTS (+ heirlooms)
    searches_total: int = 0
    pity: list[int] = field(default_factory=lambda: [0 for _ in PITY])
    discovered: list[set] = field(default_factory=lambda: [set(), set(), set(), set()])
    index_bonus: float = 0.0
    last_collect: float = 0.0
    potion_until: dict = field(default_factory=lambda: {"luck": 0.0, "speed": 0.0, "mutation": 0.0, "cash": 0.0})
    spent_potions: float = 0.0
    events: dict = field(default_factory=dict)

    # ---- derived values ------------------------------------------------------------
    def tool(self):
        return TOOLS[self.tools[self.seg]]

    def luck(self) -> float:
        _, tool_luck, _, _ = self.tool()
        l = tool_luck * (1 + REBIRTH_LUCK_BONUS * self.rebirths + self.index_bonus)
        if self.potion_until["luck"] > self.t:
            l *= 2
        return min(LUCK_CAP, l)

    def interval(self) -> float:
        iv = self.tool()[0]
        if self.potion_until["speed"] > self.t:
            iv /= 1.5
        return max(MIN_SEARCH_INTERVAL, iv)

    def mut_mult(self) -> float:
        m = self.tool()[2]
        if self.potion_until["mutation"] > self.t:
            m *= 2
        return m

    def base_plot_cps(self) -> float:
        placed = sorted((tr.income for tr in self.owned), reverse=True)[: self.slots]
        return sum(placed) * (1 + REBIRTH_CASH_BONUS * self.rebirths)

    def cps(self) -> float:
        c = self.base_plot_cps()
        if self.potion_until["cash"] > self.t:
            c *= 2
        return c

    # ---- actions -------------------------------------------------------------------
    def mark(self, key: str):
        if key not in self.events:
            self.events[key] = self.t

    def search(self):
        self.searches_total += 1
        forced = 0
        if self.onboarding and self.rebirths == 0:
            forced = ONBOARDING_FORCED.get(self.searches_total, 0)
        for k, (tier_min, n) in enumerate(PITY):
            if self.pity[k] + 1 >= n:
                forced = max(forced, tier_min)
        tier = roll_tier(self.rng, self.luck(), forced)
        for k, (tier_min, _) in enumerate(PITY):
            self.pity[k] = 0 if tier >= tier_min else self.pity[k] + 1
        mm = self.mut_mult()
        finish = roll_family(self.rng, FINISH, FINISH_BASE_CHANCE * mm)
        aura = roll_family(self.rng, AURA, AURA_BASE_CHANCE * mm)
        seg_id, seg_mult, _, _ = SEGMENTS[self.seg]
        income = BASE_CPS[tier] * seg_mult * mutation_multiplier(finish, aura)
        variant = self.rng.randrange(TREASURES_PER_RARITY[tier])
        self.discovered[self.seg].add((tier, variant))
        self.update_index()
        if tier >= 2:
            self.mark("first_rare")
        if tier >= 4:
            self.mark("first_legendary")
        if tier >= MYTHIC:
            self.mark("first_mythic")
        self.add_treasure(Treasure(income, tier))

    def update_index(self):
        total = sum(TREASURES_PER_RARITY)
        bonus = 0.0
        for found in self.discovered:
            frac = len(found) / total
            for need, b in INDEX_MILESTONES:
                if frac >= need:
                    bonus += b
        self.index_bonus = bonus

    def add_treasure(self, tr: Treasure):
        self.owned.append(tr)
        if len(self.owned) > MAX_SLOTS:
            self.owned.sort(key=lambda x: x.income, reverse=True)
            # keep top MAX_SLOTS plus any heirlooms; sell the rest
            keep, sell = [], []
            for i, x in enumerate(self.owned):
                (keep if i < MAX_SLOTS or x.tier >= KEEP_ON_REBIRTH_MIN_RARITY else sell).append(x)
            self.owned = keep
            self.vault += sum(x.income for x in sell) * SELL_SECONDS

    def price_list(self):
        items = []
        nxt = self.tools[self.seg] + 1
        if nxt < len(TOOLS):
            items.append(("tool", TOOLS[nxt][3] * SEGMENTS[self.seg][2]))
        if self.slots < MAX_SLOTS:
            items.append(("slot", slot_price(self.slots)))
        if self.unlocked < len(SEGMENTS):
            items.append(("segment", SEGMENTS[self.unlocked][3]))
        return items

    def potion_price(self, kind: str) -> float:
        return max(POTION_MIN_PRICE[kind], POTION_PRICE_SECONDS[kind] * self.base_plot_cps())

    def buy_potions(self):
        # "potion user" policy: keep Cash + Luck potions running once the first tools are bought
        if not self.potions or self.tools[0] < 2:
            return
        for kind in ("cash", "luck"):
            if self.potion_until[kind] <= self.t:
                price = self.potion_price(kind)
                if self.cash >= price and price <= 0.5 * self.cash:
                    self.cash -= price
                    self.spent_potions += price
                    self.potion_until[kind] = self.t + POTION_DURATION

    def shop(self, allow_rebirth: bool):
        self.buy_potions()
        bought = True
        while bought:
            bought = False
            if allow_rebirth and self.cash >= rebirth_cost(self.rebirths):
                self.do_rebirth()
                bought = True
                continue
            items = sorted(self.price_list(), key=lambda x: x[1])
            if items and self.cash >= items[0][1]:
                kind, price = items[0]
                self.cash -= price
                if kind == "tool":
                    self.tools[self.seg] += 1
                    self.mark("first_upgrade")
                    self.mark(f"{SEGMENTS[self.seg][0]}_tool_{self.tools[self.seg] + 1}")
                elif kind == "slot":
                    self.slots += 1
                    self.mark("first_upgrade")
                    self.mark(f"slots_{self.slots}")
                else:
                    self.unlocked += 1
                    self.seg = self.unlocked - 1
                    self.mark(f"unlock_{SEGMENTS[self.seg][0]}")
                bought = True

    def do_rebirth(self):
        self.rebirths += 1
        self.mark(f"rebirth_{self.rebirths}")
        self.cash = 0.0
        self.vault = 0.0
        self.unlocked = 1
        self.seg = 0
        self.tools = [0, 0, 0, 0]
        self.slots = START_SLOTS
        self.owned = [x for x in self.owned if x.tier >= KEEP_ON_REBIRTH_MIN_RARITY]

    def next_target(self, allow_rebirth: bool) -> float:
        items = [p for _, p in self.price_list()]
        if allow_rebirth:
            items.append(rebirth_cost(self.rebirths))
        return min(items) if items else math.inf

    def collect(self):
        self.cash += self.vault
        self.vault = 0.0
        self.last_collect = self.t
        self.mark("first_collect")

    # ---- simulation ----------------------------------------------------------------
    def run_active(self, seconds: float, allow_rebirth: bool = True, stop_at: str | None = None):
        """Play `seconds` of active (in-zone) time."""
        end = self.t + seconds
        next_search = self.t + self.interval() + (START_WALK_S if self.t == 0 else 0)
        while self.t < end:
            # next event is either a search or a collect check (1 s granularity)
            step_to = min(next_search, self.t + 1.0, end)
            dt = step_to - self.t
            self.vault += self.cps() * dt
            self.t = step_to
            if self.t >= next_search:
                self.search()
                next_search = self.t + self.interval()
            gap = self.t - self.last_collect
            ready = self.t >= FIRST_COLLECT_AT and gap >= COLLECT_MIN_GAP
            if ready and (gap >= COLLECT_MAX_GAP or self.cash + self.vault >= self.next_target(allow_rebirth)):
                self.collect()
                self.shop(allow_rebirth)
                # walking to the plot and back costs search time
                next_search = max(next_search, self.t + COLLECT_WALK_S)
            if stop_at and stop_at in self.events:
                return

    def go_offline(self, seconds: float):
        """Logged out: offline earnings only (permanent multipliers, no potions)."""
        earned = self.base_plot_cps() * min(seconds, OFFLINE_CAP_S) * OFFLINE_RATE
        self.cash += self.vault + earned
        self.vault = 0.0
        self.t += seconds  # potion expiries are wall-clock timestamps, so they lapse offline
        self.last_collect = self.t


# --------------------------------------------------------------------------------------
# REPORTS
# --------------------------------------------------------------------------------------


def fmt_time(s: float | None) -> str:
    if s is None or s == math.inf:
        return "not reached"
    if s < 120:
        return f"{s:.0f} s"
    if s < 7200:
        return f"{s / 60:.1f} min"
    return f"{s / 3600:.2f} h"


def pct(values, q):
    if not values:
        return None
    v = sorted(values)
    k = (len(v) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def roll_check(n: int, seed: int):
    rng = random.Random(seed)
    counts = [0] * len(RARITIES)
    for _ in range(n):
        counts[roll_tier(rng, 1.0)] += 1
    probs = prob_table(1.0)
    print(f"\n### Roll-distribution check ({n:,} rolls, luck 1.0, pity off)\n")
    print("| Tier | Target p | Expected hits | Observed | Deviation | Within ±5%? |")
    print("|---|---|---|---|---|---|")
    for i, name in enumerate(NAMES):
        exp = probs[i] * n
        dev = (counts[i] - exp) / exp if exp else 0.0
        check = ("yes" if abs(dev) <= 0.05 else "NO") if exp >= 1000 else "n/a (<1,000 expected)"
        print(f"| {name} | {probs[i]:.7f} | {exp:,.1f} | {counts[i]:,} | {dev:+.2%} | {check} |")


def luck_tables():
    print("\n### Probability per tier at different total luck (sums to 1)\n")
    lucks = [1, 2, 5, 10, 25]
    print("| Tier | " + " | ".join(f"Luck {l}x" for l in lucks) + " |")
    print("|---|" + "---|" * len(lucks))
    tables = [prob_table(l) for l in lucks]
    for i, name in enumerate(NAMES):
        cells = []
        for t in tables:
            p = t[i]
            cells.append("0" if p == 0 else (f"1 in {1 / p:,.1f}" if p < 0.5 else f"{p:.1%}"))
        print(f"| {name} | " + " | ".join(cells) + " |")
    print("| **Sum** | " + " | ".join(f"{sum(t):.12f}" for t in tables) + " |")


def mutation_cap_check(seed: int):
    worst = 0.0
    for f in [None] + [(n, m) for n, m, _ in FINISH]:
        for a in [None] + [(n, m) for n, m, _ in AURA]:
            worst = max(worst, mutation_multiplier(f, a))
    rng = random.Random(seed)
    sampled = 0.0
    for _ in range(200_000):
        f = roll_family(rng, FINISH, 1.0)
        a = roll_family(rng, AURA, 1.0)
        sampled = max(sampled, mutation_multiplier(f, a))
    print(f"\nMutation cap check: max over all {len(FINISH) + 1}x{len(AURA) + 1} combinations = {worst}x; "
          f"max over 200,000 forced rolls = {sampled}x (cap {MUTATION_TOTAL_CAP}x)")


STOP_AT = "rebirth_2"


def scenario_active(runs: int, seed: int, onboarding: bool, potions: bool, segments: int, horizon_h: float):
    global SEGMENTS
    saved = SEGMENTS
    SEGMENTS = saved[:segments]
    results = []
    try:
        for r in range(runs):
            p = Player(rng=random.Random(seed + r), onboarding=onboarding, potions=potions)
            p.run_active(horizon_h * 3600, stop_at=STOP_AT)
            results.append(p)
    finally:
        SEGMENTS = saved
    return results


def summarize(label: str, players: list[Player], keys: list[tuple[str, str]]):
    print(f"\n### {label} ({len(players)} runs)\n")
    print("| Milestone | p10 | Median | p90 | Reached |")
    print("|---|---|---|---|---|")
    for key, title in keys:
        vals = [p.events[key] for p in players if key in p.events]
        reached = f"{len(vals)}/{len(players)}"
        print(f"| {title} | {fmt_time(pct(vals, 0.1))} | {fmt_time(pct(vals, 0.5))} | {fmt_time(pct(vals, 0.9))} | {reached} |")


def income_snapshot(runs: int, seed: int, checkpoints_min: list[int]):
    print("\n### Income snapshot, full design, F2P (median of runs)\n")
    print("| Active time | Cash/sec | Slots | Pets tool | Segment | Rebirths |")
    print("|---|---|---|---|---|---|")
    snaps = {c: [] for c in checkpoints_min}
    for r in range(runs):
        p = Player(rng=random.Random(seed + r))
        last = 0
        for c in checkpoints_min:
            p.run_active((c - last) * 60)
            last = c
            snaps[c].append((p.cps(), p.slots, p.tools[0] + 1, p.seg, p.rebirths))
    for c in checkpoints_min:
        rows = snaps[c]
        med = lambda i: statistics.median(x[i] for x in rows)
        seg_mode = statistics.mode(SEGMENTS[x[3]][0] for x in rows)
        print(f"| {fmt_time(c * 60)} | {med(0):,.0f} | {med(1):.0f} | T{med(2):.0f} | {seg_mode} | {med(4):.0f} |")


def scenario_calendar(runs: int, seed: int, sessions: list[tuple[int, int]], days: int, label: str, segments: int = 4):
    """sessions = [(active_min, offline_min_after), ...] repeated each day."""
    global SEGMENTS
    saved = SEGMENTS
    SEGMENTS = saved[:segments]
    day_state = {d: [] for d in (1, 3, 7)}
    first_rebirth_day = []
    try:
        for r in range(runs):
            p = Player(rng=random.Random(seed + r))
            active_total = 0
            for d in range(1, days + 1):
                for act, off in sessions:
                    p.run_active(act * 60)
                    active_total += act
                    p.go_offline(off * 60)
                if d in day_state:
                    day_state[d].append((p.rebirths, p.unlocked, p.cps()))
            if "rebirth_1" in p.events:
                first_rebirth_day.append(p.events["rebirth_1"] / 86400 + 1)
    finally:
        SEGMENTS = saved
    print(f"\n### Calendar scenario: {label} ({runs} runs, {segments} segment(s))\n")
    print("| Day | Median rebirths | Median segments unlocked | Median cash/sec at end of day |")
    print("|---|---|---|---|")
    for d, rows in day_state.items():
        print(f"| Day {d} | {statistics.median(x[0] for x in rows):.0f} | {statistics.median(x[1] for x in rows):.0f} | "
              f"{statistics.median(x[2] for x in rows):,.0f} |")
    if first_rebirth_day:
        print(f"\nFirst rebirth reached by {len(first_rebirth_day)}/{runs} players; median on day "
              f"{statistics.median(first_rebirth_day):.1f} (p10 {pct(first_rebirth_day, 0.1):.1f}, "
              f"p90 {pct(first_rebirth_day, 0.9):.1f}).")
    else:
        print(f"\nFirst rebirth not reached within {days} days.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=200)
    ap.add_argument("--rolls", type=int, default=1_000_000)
    ap.add_argument("--seed", type=int, default=20261104)
    ap.add_argument("--quick", action="store_true", help="fewer runs, for tuning")
    args = ap.parse_args()
    runs = 60 if args.quick else args.runs

    luck_tables()
    roll_check(args.rolls, args.seed)
    mutation_cap_check(args.seed)

    keys_full = [
        ("first_collect", "First collect"),
        ("first_rare", "First Rare+ find"),
        ("first_upgrade", "**First upgrade (any purchase)**"),
        ("pets_tool_2", "First tool upgrade (Wooden Whistle)"),
        ("first_legendary", "First Legendary+"),
        ("unlock_fish", "**Second segment unlocked (Fish)**"),
        ("first_mythic", "First Mythic+"),
        ("unlock_cars", "Third segment unlocked (Cars)"),
        ("rebirth_1", "**First rebirth**"),
        ("rebirth_2", "Second rebirth"),
    ]
    full = scenario_active(runs, args.seed, onboarding=True, potions=False, segments=4, horizon_h=12)
    summarize("Active play, full 4-segment design, F2P, no potions (TUNING TARGET)", full, keys_full)
    eng = scenario_active(runs, args.seed + 7, onboarding=True, potions=True, segments=4, horizon_h=12)
    summarize("Active play, full design, buys Cash + Luck potions", eng, keys_full)
    mvp_keys = [k for k in keys_full if not k[0].startswith("unlock")]
    mvp = scenario_active(runs, args.seed + 13, onboarding=False, potions=False, segments=1, horizon_h=12)
    summarize("Active play, MVP build (Pets only, no onboarding luck), F2P", mvp, mvp_keys)

    income_snapshot(min(runs, 100), args.seed + 21, [1, 5, 10, 30, 60, 120, 180, 240])

    cal_runs = min(runs, 100)
    scenario_calendar(cal_runs, args.seed + 31, [(20, 9 * 60), (25, 14 * 60 + 15)], 7,
                      "Casual - 2 sessions/day (20 + 25 min)")
    scenario_calendar(cal_runs, args.seed + 41, [(30, 4 * 60), (30, 4 * 60), (30, 4 * 60), (45, 10 * 60 + 15)], 7,
                      "Engaged - 4 sessions/day (2.25 h/day incl. AFK)")
    scenario_calendar(cal_runs, args.seed + 51, [(30, 4 * 60), (30, 4 * 60), (30, 4 * 60), (45, 10 * 60 + 15)], 7,
                      "Engaged, MVP build (Pets only)", segments=1)


if __name__ == "__main__":
    main()
