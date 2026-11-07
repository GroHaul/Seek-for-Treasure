# Seek for Treasure — Game Design Document (Phase 1)

| Field | Value |
|---|---|
| Status | **Phase 2 in progress** (approved 2026-11-04). Steps 1–4 verified in Studio on 2026-11-07; see the README status table. |
| Version | GDD v1.0, 2026-11-04 |
| Genre | Idle RNG collection tycoon (auto-search → reveal → place → earn → upgrade → rebirth) |
| Platform focus | Roblox, mobile first (landscape phone), desktop/tablet/console supported |
| Server size | 8 players, 8 plots |
| Economy tool | `tools/economy_sim.py` (run log: `tools/economy_sim_output.md`) |
| MVP segment | **Pets** (Pawprint Meadow), approved |

> **Environment blockers for Phase 2 (found during setup).**
> 1. ~~Roblox Studio MCP is not connected.~~ Resolved 2026-11-07: Phase 2 runs locally with the Studio MCP and Rojo live sync.
> 2. **ForgeGUI → Roblox publishing connection `@GavinForReal` shows `needs_validation / asset_permission_missing`.** Models and images can be generated but not uploaded to Roblox until the API key gets asset permissions.
> 3. **ForgeGUI 3D model generation is locked on the current plan** (`paid_generation_required`). GUI images work. Every treasure model, prop and pedestal needs a plan upgrade (https://forgegui.com/plans).

**How to read this doc.** Each feature is tagged **MVP** (built in Phase 2) or **Backlog** (designed here, not built). The MVP scope is exactly the list in the brief. A few small sub-features it needs are tagged **MVP\*** and listed in §0; you approved them at Checkpoint 1.

---

## 0. MVP scope at a glance

| Area | MVP (Phase 2) | Backlog |
|---|---|---|
| Segments | 1 segment (recommend Pets) with its search area and auto-search | Fish, Cars, Anime |
| RNG | 10 rarities, Luck, pity, Finish + Aura mutations (cap 10x), onboarding forced finds + tutorial | Treasure Storm |
| Plot | Claim on join, place/remove, cash accrual, Collect pad, offline earnings | Showcase pedestal, offline-cap upgrades |
| Shop | One tool line (8 tiers), 4 potions, plot-slot upgrade | Enhancements, walk/search-speed upgrades |
| Meta | Rebirth, saving, Index (+ luck milestones), reveal cinematic, Mythic+ server banner | Sky beam, cross-server Celestial+ banner, badges*, leaderboards |
| Social | Friend boost, codes (launch code `SEEKATREASURE`), "next code at X likes" board with a **live** like counter (pending the approvals in §0.1) | Group reward, playtime gifts, daily streak |
| Monetization | None (needs your approval to create products) | All of §10 |
| Tooling | Dev commands (Studio only, UserId 422765950); AnalyticsService funnel + economy events | — |

**MVP\* (small sub-features the MVP needs; approved 2026-11-04):**

| Sub-feature | Why it is needed |
|---|---|
| New finds auto-fill empty unlocked pedestals; a "Place Best" button | Without it, a mobile player must hand-place every find. It's the "place" half of place/remove. |
| Sell a treasure (10 s of its base income) and a 300-entry inventory cap | Keeps the profile bounded (§11) and lets players clear junk. |
| Settings toggle "Reduce screen shake" | Accessibility for the reveal cinematic. |
| AnalyticsService funnel + economy events (§14) | Measures whether the MVP works. Moved into the MVP. |

### 0.1 Checkpoint 1 decisions (2026-11-04)

| # | Question | Decision | Where it lands |
|---|---|---|---|
| 1 | MVP segment | **Pets** | §4 |
| 2 | Dev UserId | **422765950** | §12 `DevService` |
| 3 | ForgeGUI budget and style | **10,000 credits**; "Sunny Toybox" approved | §13 |
| 4 | Rebirth and treasures | **Keep all treasures** | §7; sim re-run in §8.4 (pacing almost unchanged) |
| 5 | MVP\* helpers | **Yes** (auto-fill + Place Best, Sell + 300 cap, Reduce shake) | §0 |
| 6 | Analytics + onboarding forced finds | **Moved into the MVP** | §9.5, §14 |
| 7 | Server size | **8 players / 8 plots** | §6 |
| 8 | Codes | Launch code **`SEEKATREASURE`**; **live** like counter preferred | §9.7 |

**Still open before Phase 2 can start:**

| Item | Why it blocks | Options |
|---|---|---|
| Published test place + Studio API access | Real DataStore persistence (acceptance: "persist across rejoin in the published test place") | Until then `DataService` uses an in-memory MockStore in Studio (decision 2026-11-07) |
| Server size 8 | Plots are 8 per server; `Players.MaxPlayers` is an Experience setting | Set server size to 8 in Game Settings when publishing |
| ForgeGUI 3D generation | Locked on the current plan | Upgrade the plan, or choose an alternative for models |
| Live like counter | Needs **Allow HTTP Requests** (an Experience setting) and a proxy, because `HttpService` can't call roblox.com directly | (a) public third-party proxy (RoProxy); (b) a small proxy you host (e.g., a Cloudflare Worker). Either needs your approval. |
| `SEEKATREASURE` reward | Not specified | Default: 2 Luck Potions + 2 Cash Potions |
| ForgeGUI → Roblox upload | Connection `@GavinForReal` is `needs_validation / asset_permission_missing` | Re-validate the API key with asset permissions in ForgeGUI |

---

## 1. Core loop and session flow

### 1.1 Core loop

| Step | Player sees | Server does |
|---|---|---|
| 1. Stand in a search area | Whistle/rod/scanner animation, a progress ring on the HUD | Checks the character's position against the area's zone part about 5 times a second |
| 2. Auto-search ticks | Ring fills over the tool's search interval | Builds up search progress only while the character is inside an unlocked zone; resets it to 0 on leaving |
| 3. Reveal | Cinematic scaled to rarity (§9.1) | Rolls rarity → treasure → mutations; updates pity, Index, stats |
| 4. Place | Treasure appears on a pedestal on your plot | Auto-fills an empty slot or keeps it in inventory |
| 5. Earn | The plot vault counter rises ("$/s") | Accrues the vault from server-computed income |
| 6. Collect | Walk onto your Collect pad | Moves vault to wallet when your character is on your own pad |
| 7. Spend | Shop: tools, potions, slots, segment gates | Validates and prices every purchase on the server |
| 8. Rebirth | Big confirm screen with the permanent reward | Resets per §7 and grants permanent multipliers |

### 1.2 First 60 seconds (MVP, Pets)

| Time | Beat | Design intent |
|---|---|---|
| 0–5 s | Spawn on your auto-claimed plot (your name and avatar on the arch). A glowing pawprint trail leads 30 studs to Pawprint Meadow. | Zero menus. One obvious direction. |
| ~8 s | Enter the meadow: the whistle tweets and the search ring starts (3.0 s per search). | Searching needs no tapping. |
| ~11 s | First find (a Common) shows as a toast and auto-fills pedestal 1. "+1 $/s" floats up. | Shows the loop: find → place → earn. |
| ~17 s | Search #3 is a guaranteed Uncommon+. | Early variety. |
| ~32 s | Search #8 is a guaranteed Rare+. Blue card-flip reveal plus a chime. | Guaranteed "first big find" inside 2 minutes (sim: p90 32 s). |
| ~40 s | The HUD vault pulses: "Vault $410: Collect!" with an arrow to the pad. | Teaches the plot walk. |
| ~50 s | Shop button glows: "Buy Wooden Whistle ($1,000)". Sim median for the first upgrade is 50 s. | First purchase in the first minute. |
| 60 s | Back in the meadow; searches now every 2.6 s. | The first upgrade is felt right away. |

### 1.3 First 10 minutes

| Time | What happens (sim medians, full design) |
|---|---|
| 1–3 min | Slots 7–9 bought ($1K → $5K). First Epic. Income about 66 → 200 $/s. |
| ~5 min | First Legendary+ (median 5.1 min, 1-in-250 odds; Legendary pity at 800 is the backstop). Brass/Silver Whistle. About 350 $/s. |
| 5–10 min | Index reaches 6/12 → **+2% luck** milestone toast. Potion shop unlocks a tip ("Try a Luck Potion"). The pity meter shows "Legendary+ in N". |
| ~10 min | Amber Whistle (T5), 12 slots, about 815 $/s. The Fish gate ($1.5M) is visible with a progress bar: the next big goal. |

### 1.4 Day 1 and Day 7 (calendar simulation, §8.4)

| Milestone | Casual (2 sessions/day, 45 min) | Engaged (4 sessions/day, 2.25 h incl. AFK) |
|---|---|---|
| Day 1 | Fish unlocked (segment 2); mid-game Pets tools | Cars unlocked; first rebirth (median day 1.6) |
| Day 3 | First rebirth (median day 3.4); Cars unlocked | About 3 rebirths; Anime unlocked |
| Day 7 | About 3 rebirths, all 4 segments seen | About 5 rebirths, chasing Divine+ and Index completion |
| Between sessions | "Welcome back! +$X while you were away" (50% rate, 2 h cap) | Same; they hit the 2 h cap every gap |

---

## 2. Rarities and the roll

### 2.1 Rarity table

| # | Rarity | Base odds (1 in N) | p at Luck 1 | Color (hex) | Reveal tier (§9.1) | Base cash/sec | Pity |
|---|---|---|---|---|---|---|---|
| 1 | Common | remainder (≈1 in 1.56) | 64.18845% | `#B8C0CC` grey | R0 toast | 1 | — |
| 2 | Uncommon | 4 | 25.0% | `#5BD66B` green | R0 toast + chime | 3 | — |
| 3 | Rare | 12 | 8.3333% | `#49A8FF` blue | R1 card flip | 10 | — |
| 4 | Epic | 50 | 2.0% | `#A25CFF` purple | R2 spin | 40 | Epic+ on 120th dry search |
| 5 | Legendary | 250 | 0.4% | `#FFB52E` gold | R3 roulette + shake | 200 | Legendary+ on 800th |
| 6 | Mythic | 1,500 | 0.06667% | `#FF3E7A` hot pink | R4 + server banner | 1,500 | Mythic+ on 5,000th |
| 7 | Divine | 10,000 | 0.01% | `#FFF3B0` white-gold | R5 slow-mo | 12,000 | — |
| 8 | Celestial | 75,000 | 0.001333% | `#6EF2FF` cyan | R6 hyperspace | 100,000 | — |
| 9 | Cosmic | 500,000 | 0.0002% | `#7B2FFF` → `#FF4FD8` gradient | R7 black hole | 900,000 | — |
| 10 | Secret | 5,000,000 | 0.00002% | `#111111` + animated rainbow edge | R8 fake-out + glitch | 10,000,000 | — |

Base cash/sec is for segment multiplier 1 (Pets) and no mutation. Every treasure of a rarity in a segment has the same base income (`base × segment multiplier`). Treasures inside a rarity are picked uniformly (each config entry has `weight = 1`, so a limited-time treasure can be weighted later).

### 2.2 Roll algorithm (server only)

1. **Total luck** `L = min(25, toolLuck × (1 + 0.10·rebirths + indexBonus) × luckPotion × [Backlog multipliers: 2x Luck pass, Storm, Server Boost])`, and `L ≥ 1`.
2. **Probability table** for `L` (cached per distinct `L`):
   - For tiers *i* = Secret down to Uncommon: `p_i = min(L / N_i, 1 − Σ_{j rarer than i} p_j)`
   - `p_Common = 1 − Σ_{i ≥ Uncommon} p_i`
   - **Luck multiplies every non-Common tier's chance linearly.** "2x luck" really doubles your Mythic odds. Assigning the rarest tiers first and clamping means the total can never pass 1: as luck grows, probability drains from Common, then Uncommon, and so on. The sum is exactly 1 by construction (verified in §2.3).
3. **Pity floor.** If any pity counter is at `N − 1`, this search is forced to at least that tier (the highest triggered floor wins). A forced roll draws `u` over the conditional distribution of tiers ≥ floor (same `L`).
4. **Draw.** `u = rng:NextNumber()` from one server-owned `Random.new()`. Walk the cumulative table from Secret down to Common and pick the first tier where `u < cumulative`.
5. **Pick the treasure** from the segment's pool for that tier (weighted; default uniform).
6. **Mutations** (§3): an independent Finish roll, then an Aura roll.
7. **Book-keeping:** reset each pity counter whose floor ≤ result, increment the others; update Index, stats and rarest-find; log analytics; then fire the Reveal to that client (plus a Banner to all if Mythic+).

The client never sends a roll, a luck value or a result. It only receives the outcome.

### 2.3 Probability per tier vs. total luck (from the sim; every column sums to 1)

| Tier | Luck 1x | Luck 2x | Luck 5x | Luck 10x | Luck 25x (cap) |
|---|---|---|---|---|---|
| Common | 64.2% | 1 in 3.5 | 0 | 0 | 0 |
| Uncommon | 1 in 4.0 | 50.0% | 1 in 2.2 | 0 | 0 |
| Rare | 1 in 12 | 1 in 6 | 1 in 2.4 | 75.2% | 1 in 2.6 |
| Epic | 1 in 50 | 1 in 25 | 1 in 10 | 1 in 5 | 50.0% |
| Legendary | 1 in 250 | 1 in 125 | 1 in 50 | 1 in 25 | 1 in 10 |
| Mythic | 1 in 1,500 | 1 in 750 | 1 in 300 | 1 in 150 | 1 in 60 |
| Divine | 1 in 10,000 | 1 in 5,000 | 1 in 2,000 | 1 in 1,000 | 1 in 400 |
| Celestial | 1 in 75,000 | 1 in 37,500 | 1 in 15,000 | 1 in 7,500 | 1 in 3,000 |
| Cosmic | 1 in 500,000 | 1 in 250,000 | 1 in 100,000 | 1 in 50,000 | 1 in 20,000 |
| Secret | 1 in 5,000,000 | 1 in 2,500,000 | 1 in 1,000,000 | 1 in 500,000 | 1 in 200,000 |
| **Sum** | 1.000000000000 | 1.000000000000 | 1.000000000000 | 1.000000000000 | 1.000000000000 |

**Pre-check of the Phase 2 acceptance test** (same algorithm in Python, 1,000,000 rolls, luck 1, pity off). Every tier with ≥ 1,000 expected hits is within ±5%:

| Tier | Target p | Expected | Observed | Deviation | ±5%? |
|---|---|---|---|---|---|
| Common | 0.6418845 | 641,884.5 | 641,840 | −0.01% | yes |
| Uncommon | 0.2500000 | 250,000.0 | 250,371 | +0.15% | yes |
| Rare | 0.0833333 | 83,333.3 | 83,148 | −0.22% | yes |
| Epic | 0.0200000 | 20,000.0 | 19,970 | −0.15% | yes |
| Legendary | 0.0040000 | 4,000.0 | 3,851 | −3.72% | yes |
| Mythic … Secret | — | < 1,000 each | 682 / 128 / 8 / 2 / 0 | — | n/a |

The Legendary deviation (−3.72%) is about 2.4σ at n = 4,000. The Luau test uses a fixed seed and reports σ alongside the ±5% check.

### 2.4 Luck sources

| Source | Multiplier | Scope | MVP? |
|---|---|---|---|
| Tool tier | 1.00x – 2.60x (§5.1) | per segment's equipped tool | MVP |
| Rebirths | × (1 + 0.10 per rebirth), additive with Index | permanent | MVP |
| Index milestones | +2% / +3% / +5% per segment at 50% / 75% / 100% found | permanent | MVP |
| Luck Potion | ×2 | 10 min, wall-clock | MVP |
| 2x Luck gamepass | ×2 | permanent | Backlog |
| Treasure Storm | ×2 | global event window | Backlog |
| Server Luck Boost (dev product) | ×2 | whole server, 15 min | Backlog |
| **Cap** | **Total ≤ 25x** | Keeps Secret at 1 in 200,000 or rarer | MVP |

---

## 3. Mutations

### 3.1 Families and table

Every find makes two independent rolls: one in the **Finish** family (the material) and one in the **Aura** family (particles). A treasure can have **at most one Finish and one Aura**.

| Family | Base chance per find | Modified by | Per-family cap |
|---|---|---|---|
| Finish | 4.0% | × tool mutation stat (1.0–2.0) × Mutation Potion (×2) | 50% |
| Aura | 1.5% | same modifiers | 50% |

| Mutation | Family | Weight in family | Overall chance at base (1 in N) | Income × | Visual (material / aura / particles) |
|---|---|---|---|---|---|
| Golden | Finish | 55 | 2.20% (1 in 45) | 2 | Material `Metal`, color `#FFC93C`, Reflectance 0.3; small gold sparkle `ParticleEmitter` (Rate 4) |
| Crystal | Finish | 25 | 1.00% (1 in 100) | 3 | Material `Glass`, Transparency 0.25, tint `#9FF3FF`; white facet glints (Rate 3) |
| Rainbow | Finish | 12 | 0.48% (1 in 208) | 5 | Material `Neon` with a client-side hue cycle (6 s loop); rainbow `Trail` under the pedestal |
| Shadow | Finish | 6 | 0.24% (1 in 417) | 7 | Material `SmoothPlastic` `#16121F` + violet `Highlight` outline; low dark-smoke particles (Rate 6) |
| Prismatic | Finish | 2 | 0.08% (1 in 1,250) | 10 | `Glass` + hue-cycling `Highlight`; light-ray `Beam`s rotating behind the model |
| Glowing | Aura | 50 | 0.75% (1 in 133) | 1.5 | `PointLight` (Range 8, rarity color) + soft halo particle ring |
| Blazing | Aura | 30 | 0.45% (1 in 222) | 2 | Orange stylised flame particles from the base (Rate 10, Lifetime 0.8) |
| Electric | Aura | 15 | 0.225% (1 in 444) | 2.5 | Blue spark particles + 2 flickering `Beam` arcs |
| Starlit | Aura | 5 | 0.075% (1 in 1,333) | 3 | Star-shaped particles orbiting (Rate 5) + twinkle |

Chance of any mutation on a base find: 5.44%. The average mutation multiplier per find is about 1.10x.

### 3.2 Stacking rule (the 10x cap)

`mutationMultiplier = min(10, finishMult × auraMult)`. A missing family counts as 1.

| Finish \ Aura | none | Glowing 1.5 | Blazing 2 | Electric 2.5 | Starlit 3 |
|---|---|---|---|---|---|
| none | 1 | 1.5 | 2 | 2.5 | 3 |
| Golden 2 | 2 | 3 | 4 | 5 | 6 |
| Crystal 3 | 3 | 4.5 | 6 | 7.5 | 9 |
| Rainbow 5 | 5 | 7.5 | **10** (cap) | **10** (cap) | **10** (cap) |
| Shadow 7 | 7 | **10** (cap) | **10** (cap) | **10** (cap) | **10** (cap) |
| Prismatic 10 | 10 | **10** (cap) | **10** (cap) | **10** (cap) | **10** (cap) |

- The cap is on the **mutation** multiplier only. Enhancement, rebirth and boosts are separate factors in the income formula (§8.1).
- Mutations don't depend on rarity: a Common can be Prismatic.
- Limited-time weekly mutations (§9.10) join one family with a fixed weight, so the cap still holds.
- The Phase 2 test checks all 30 combinations plus 200,000 forced rolls (the sim already shows max = 10.0x).

---

## 4. Segments

### 4.1 Segment table

Adding a segment means adding one Config module (`Config/Segments/<Name>`), one area with a `SearchZone` part, and its models. No code changes.

| Order | Segment | Area | Area theme | Unlock cost | Income × | Tool price × | Tool line |
|---|---|---|---|---|---|---|---|
| 1 | **Pets** | Pawprint Meadow | Sunny rolling meadow with giant flower bushes, hollow logs, picket fences and a pet-bowl fountain. Search zone is a 60×60-stud flower field. | Free | 1 | 1 | Whistles |
| 2 | Fish | Glimmer Lagoon | Turquoise lagoon, wooden docks, palm trees, glowing coral, a lighthouse. Search zone is the dock edge. | $1.5M | 10 | 25 | Rods |
| 3 | Cars | Scrapyard Canyon | Desert canyon with stacked scrap cars, a crane magnet, tyre towers and neon signs (no brands). Search zone is the scrap field. | $600M | 100 | 625 | Scanners |
| 4 | Anime | Starfall Shrine | Floating sky islands, paper-lantern gates, blossom trees, falling stars. Search zone is the summoning circle. | $250B | 1,000 | 15,625 | Summon Scrolls |

**Why Pets for the MVP:** it appeals to the broadest age range, has the lowest IP-resemblance risk (no brands, no anime look-alikes), and uses the simplest low-poly models, which helps ForgeGUI consistency and mobile triangle budgets. Its mutations also read clearly (a Golden pup, a Rainbow fox). Anime is the strongest TikTok hook, so it stays as the end-game aspiration.

### 4.2 Treasure pools (12 per segment, 48 total: 2 Common, 2 Uncommon, then 1 per rarity)

All designs are original. Every ForgeGUI prompt gets the suffix: *"original design, low-poly stylized toy look, no text, no logos, no real brands, not resembling any existing character or vehicle."*

#### Pets — Pawprint Meadow

| Rarity | Treasure | One-line ForgeGUI model description |
|---|---|---|
| Common | Dust Bunny | Fluffy grey bunny shaped like a puff of dust, button nose, tiny stub feet |
| Common | Pebble Pup | Round puppy with a smooth river-stone spotted coat and floppy ears |
| Uncommon | Sprout Kitten | Green-tabby kitten with a two-leaf sprout growing from its head |
| Uncommon | Puddle Duckling | Yellow duckling with a tiny rain cloud hovering above, dripping on it |
| Rare | Toasty Corgi | Corgi whose body is a golden loaf of toast with a butter-pat saddle |
| Epic | Ember Fox | Orange fox with a faceted low-poly flame tail and ash-grey paws |
| Legendary | Storm Pony | Chubby pony with a thundercloud mane and lightning-bolt hooves |
| Mythic | Crystal Dragonling | Baby dragon with faceted gem spines and stubby translucent wings |
| Divine | Halo Owl | Snow-white owl with a floating golden halo and light-feather wing tips |
| Celestial | Starlight Stag | Midnight-blue fawn with constellation-dot antlers that glow |
| Cosmic | Galaxy Axolotl | Axolotl with swirling purple-pink galaxy skin and star-tipped gills |
| Secret | Eclipse Griffin | Small griffin, half sun-gold and half night-violet feathers, an eclipse ring behind its head |

#### Fish — Glimmer Lagoon

| Rarity | Treasure | One-line ForgeGUI model description |
|---|---|---|
| Common | Bottlecap Minnow | Silver minnow with one round, crimped, bottle-cap-like scale on its side |
| Common | Mud Puffer | Brown round pufferfish with soft blunt spikes and sleepy half-closed eyes |
| Uncommon | Bubble Guppy | Turquoise guppy with a big transparent bubble-shaped tail fin |
| Uncommon | Kelp Eel | Long green eel with a ribbon of kelp trailing from its back |
| Rare | Candy Koi | Koi with red-and-white peppermint candy-stripe scales |
| Epic | Magma Snapper | Black-rock snapper with glowing orange lava cracks |
| Legendary | Thunder Marlin | Sleek marlin with a lightning-bolt bill and electric-blue fins |
| Mythic | Crystal Manta | Manta ray made of faceted aqua crystal |
| Divine | Aurora Jelly | Jellyfish with an aurora-curtain bell and long ribbon tentacles |
| Celestial | Moonphase Serpent | Small sea serpent whose scales show the phases of the moon |
| Cosmic | Comet Narwhal | Navy narwhal whose horn is a blazing comet with a tail |
| Secret | Ghost Coelacanth | Ancient lobe-finned fish with a spectral translucent body and glowing skeleton lines |

#### Cars — Scrapyard Canyon (original vehicles; no real grilles, badges, logos or recognisable silhouettes)

| Rarity | Treasure | One-line ForgeGUI model description |
|---|---|---|
| Common | Rust Bucket | Dented boxy hatchback with mismatched door colors and a rope-tied hood |
| Common | Lawn Kart | Ride-on lawn mower turned go-kart, grass-green with a cushion seat |
| Uncommon | Bubble Buggy | Round two-seat bubble car with porthole windows, mint and cream |
| Uncommon | Sundae Van | Chunky pastel-striped ice-cream van with a giant cone on the roof |
| Rare | Dune Hopper | Lifted desert buggy with balloon tyres, a roll cage and a sand flag |
| Epic | Neon Drifter | Low wedge-shaped coupe with neon underglow and a single fin spoiler |
| Legendary | Thunder Brute | Bulky muscle car with storm-cloud hood scoops and lightning decals |
| Mythic | Glacier GT | Supercar with frosted translucent ice-crystal body panels |
| Divine | Solar Wing | Teardrop hypercar with solar-panel wings that fold upward |
| Celestial | Comet Cruiser | Retro-future hover car with tail fins and a comet-trail exhaust |
| Cosmic | Nebula Racer | Anti-gravity racer with a swirling nebula glass canopy |
| Secret | Paradox Roadster | Roadster split down the middle: front half wooden carriage, back half chrome future |

#### Anime — Starfall Shrine (original characters in a generic anime art style)

| Rarity | Treasure | One-line ForgeGUI model description |
|---|---|---|
| Common | Bento Rookie | Cheerful student holding a two-tier bento box, oversized backpack |
| Common | Paper Ninja | Apprentice ninja in folded origami-paper clothes with a paper-crane mask |
| Uncommon | Cat-Ear Courier | Delivery runner in a cat-ear helmet with a parcel satchel |
| Uncommon | Blossom Ronin | Young wanderer with a petal-pattern scarf and a wooden practice sword |
| Rare | Thunder Idol | Pop idol with a lightning-bolt microphone and star hair clips |
| Epic | Mecha Cadet Nova | Pilot in a chunky white-teal flight suit holding a mini mecha helmet |
| Legendary | Inferno Monk | Bald monk with flaming prayer beads and fire-wrapped fists |
| Mythic | Glacier Empress | Regal figure in an ice-crystal gown with a frozen crown |
| Divine | Sun Oracle | Seer with a sun-disc halo and three floating bronze mirrors |
| Celestial | Starweaver | Girl weaving glowing constellation threads on a loom of light |
| Cosmic | Void Samurai | Armored warrior with cracks of starry void running through the armor |
| Secret | The Unwritten | A hero drawn in unfinished ink-sketch lines, half colored, pages fluttering around them |

**Originality guardrails (Anime and Cars):** no straw hats with a red vest, no orange jumpsuits with forehead protectors, no spiky glowing gold hair, no famous mascot silhouettes, no real car grilles, badges or body lines, and no text. Every model gets a human review against the top-50 known characters and vehicles before upload.

---

## 5. Shop

### 5.1 Tools (one 8-tier line per segment; MVP builds the Pets line)

| Tier | Search interval (s) | Luck × | Mutation × | Base price (× segment tool price) |
|---|---|---|---|---|
| T1 | 3.00 | 1.00 | 1.00 | Free (starter) |
| T2 | 2.60 | 1.10 | 1.00 | 1,000 |
| T3 | 2.25 | 1.25 | 1.10 | 2,500 |
| T4 | 1.95 | 1.45 | 1.25 | 15,000 |
| T5 | 1.65 | 1.70 | 1.40 | 70,000 |
| T6 | 1.40 | 2.00 | 1.60 | 250,000 |
| T7 | 1.20 | 2.30 | 1.80 | 900,000 |
| T8 | 1.00 | 2.60 | 2.00 | 3,000,000 |

| Tier | Pets (Whistles) | $ | Fish (Rods) | $ | Cars (Scanners) | $ | Anime (Summon Scrolls) | $ |
|---|---|---|---|---|---|---|---|---|
| T1 | Tin Whistle | 0 | Twig Rod | 0 | Rusty Detector | 0 | Paper Charm | 0 |
| T2 | Wooden Whistle | 1,000 | Bamboo Rod | 25,000 | Pocket Scanner | 625,000 | Ink Scroll | 15.6M |
| T3 | Brass Whistle | 2,500 | Fiberglass Rod | 62,500 | Turbo Scanner | 1.56M | Jade Scroll | 39.1M |
| T4 | Silver Whistle | 15,000 | Carbon Rod | 375,000 | Nitro Radar | 9.38M | Spirit Scroll | 234M |
| T5 | Amber Whistle | 70,000 | Coral Rod | 1.75M | Chrome Radar | 43.8M | Thunder Scroll | 1.09B |
| T6 | Opal Whistle | 250,000 | Abyss Rod | 6.25M | Quantum Scanner | 156M | Moon Scroll | 3.91B |
| T7 | Starlight Whistle | 900,000 | Tidecaller Rod | 22.5M | Hyperdrive Array | 563M | Sun Scroll | 14.1B |
| T8 | Aurora Whistle | 3,000,000 | Leviathan Rod | 75M | Singularity Array | 1.88B | Infinity Scroll | 46.9B |

Rules: tiers are bought in order (next tier only). The highest owned tier is equipped automatically, and you can manually equip a lower one (cosmetic). A tool works only in its own segment. Search interval floor is 0.5 s.

### 5.2 Potions (MVP: all 4, bought with cash)

| Potion | Effect | Duration | Price (server-computed) | Stacking |
|---|---|---|---|---|
| Luck | Luck ×2 | 10 min | max($250, 150 s × base plot income) | Same type adds +10 min (max 60 min remaining), effect doesn't compound with itself |
| Speed | Search interval ÷ 1.5 | 10 min | max($250, 150 s × base plot income) | same |
| Mutation | Both mutation chances ×2 | 10 min | max($200, 120 s × base plot income) | same |
| Cash | Plot income ×2 | 10 min | max($400, 240 s × base plot income) | same |

- Different potion types stack with each other, multiplicatively.
- Expiry is a wall-clock Unix timestamp (`os.time()`), so potions keep ticking while you're offline. Offline earnings never use potions.
- "Base plot income" = placed treasures × rebirth multiplier, with no boosts, so prices scale with progress and can't be gamed with boosts. Sim: steady Cash + Luck use cuts first rebirth from 3.16 h to 2.50 h.

### 5.3 Enhancements (all Backlog; schema already supports `level`)

| Enhancement | Effect | Cost | Notes |
|---|---|---|---|
| Level Up | Treasure income × (1 + 0.15 × (level − 1)); Lv 1 → 10 (max 2.35x) | 120 s × treasure base income × 1.8^(level − 1) | Not capped by the mutation cap (separate factor) |
| Finish Reroll | Rerolls the Finish slot with the normal family weights; "keep old / take new" choice | 600 s × the treasure's pre-mutation income | Cash only → not a paid random item; if ever sold for Robux, odds display + PolicyService gate (§10) |
| Aura Infusion | Guarantees an Aura roll (weighted) on a treasure without one | 900 s × pre-mutation income | Same rule |
| Fusion | 3 identical treasures (same id) → 1 with a ★ (+25% income per ★, max ★★★) | Free (consumes items) | Gives duplicates value |

### 5.4 Upgrades

| Upgrade | Levels | Price curve | MVP? |
|---|---|---|---|
| Plot slots | 6 → 20 (+4 via gamepass = 24) | `1,000 × 2.25^n`, n = slots bought so far | **MVP** |
| Offline cap | 2 h → 4 h → 6 h → 8 h | $5M, $500M, $50B | Backlog |
| Offline rate | 50% → 60% → 75% | $50M, $5B | Backlog |
| Search speed (global) | 5 levels, −3% interval each | $1M × 10^n | Backlog |
| Walk speed | 16 → 18 → 20 → 22 → 24 | $10K × 10^n | Backlog |

Plot slot ladder:

| Slot | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Price | 1,000 | 2,250 | 5,062 | 11,391 | 25,629 | 57,665 | 129,746 | 291,929 | 656,841 | 1.48M | 3.33M | 7.48M | 16.8M | 37.9M |

---

## 6. Plot

| Item | Spec |
|---|---|
| Plots per server | 8, one per player. Claimed on join (first free plot), released on leave. The arch shows the owner's DisplayName and headshot. |
| Slots | Grid of 4 × 5 = 20 pedestals (+ a 4-pedestal gamepass row). 6 unlocked at start; locked ones show a padlock and the next price (tap → buy prompt). |
| Pedestal display | Pedestal model by rarity band (stone C/U, bronze R/E, gold L/M, crystal D/Ce, cosmic Co/S). The treasure model idles (bob/spin, client-side). A `BillboardGui` shows name, rarity tag, mutation badges and $/s (`MaxDistance` 60). |
| Placement | New finds auto-fill the lowest-numbered empty unlocked slot (MVP\*). "Place Best" fills slots with the highest-income treasures. Place/Remove per slot via the inventory UI. All validated on the server. |
| Cash accrual | Server keeps `vault += plotIncome × dt` on a 1 s tick. No cap while online. The vault shows on the Collect pad billboard and in the HUD. |
| Collecting | Stand on **your own** Collect pad. The server zone-checks the character position every tick and moves vault → cash. No remote needed. |
| Offline earnings | `offline = basePlotIncome_perm × min(now − lastOnline, cap) × rate`. MVP: `cap = 2 h`, `rate = 0.5`. `basePlotIncome_perm` is computed **on load** from the saved layout with permanent multipliers only (mutation, level, rebirth, and later the 2x Cash pass). No potions, no friend boost. `elapsed` is clamped to `[0, cap]`. Granted once into cash, with a "Welcome back" popup. |
| Idle kick | Never circumvented. AFK players keep searching until Roblox's idle kick; offline earnings are their value afterwards. |

---

## 7. Rebirth

| Item | Spec |
|---|---|
| Cost (full game) | `$2.5B × 12^R` (R = rebirths done): $2.5B, $30B, $360B, $4.32T, $51.8T, … |
| Cost (MVP, Pets only) | `$400M × 12^R`: $400M, $4.8B, $57.6B, … Same 3 h target with one segment. Switches to the full-game table when segment 2 ships. |
| Requirement | Cash ≥ cost. Confirm screen lists exactly what you keep and lose. |
| Resets | Cash, vault, all tools (back to T1), segment unlocks (back to Pets), plot slots (back to 6). Treasures on slots 7+ go back to inventory; Place Best refills them as slots are rebought. |
| Kept | **All treasures**, inventory and plot (decision 2026-11-04). Also kept: Index and its luck bonuses, rebirth count, pity counters, potions (timers keep running), codes redeemed, streak, stats/rarest find, gamepasses. |
| Permanent reward per rebirth | **+50% cash** (`1 + 0.5·R`, additive) and **+10% luck** (`1 + 0.1·R`, additive with Index bonus) |
| Feel | Keeping the whole collection makes every run after the first faster (sim: 2nd rebirth about 1.3 h after the 1st), while the 12x cost growth stretches later runs (3rd about 4 h after the 2nd in an 80-run tuning pass). Keeping everything instead of only Mythic+ barely changes pacing (2nd rebirth 4.47 h vs 4.51 h): only your best 6–20 treasures earn, and by then those are Mythic+ anyway. |

---

## 8. Economy

### 8.1 Income formula

```
treasureIncome = baseCps[rarity] × segmentMult[segment] × min(10, finishMult × auraMult) × (1 + 0.15 × (level − 1))
plotIncome     = Σ(placed treasureIncome) × rebirthMult × boostMult
rebirthMult    = 1 + 0.5 × rebirths
boostMult      = cashPotion(2|1) × friendMult × [Backlog: 2x Cash pass (2|1) × VIP (1.25|1) × group (1.05|1)]
friendMult     = 1 + min(0.50, 0.10 × friendsInServer)
searchInterval = max(0.5, toolInterval ÷ speedPotion(1.5|1) × [Backlog: Fast Search pass 0.8|1])
```

| Factor | Range | Where computed |
|---|---|---|
| base × segment | 1 – 10,000,000,000 /s | Config tables |
| mutation | 1 – 10 (capped) | RollService at find time, stored on the item |
| enhancement | 1 – 2.35 (Backlog) | item `level` |
| rebirth | 1 + 0.5R | profile |
| boosts | potions, friends, passes | PlotService each tick |

Cash is a double. All math happens server-side and NaN/inf are rejected before every save. The UI uses suffixes (K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc). Late-game income stays below 1e15/s for well over 10 rebirths.

### 8.2 Price curves

| Item | Curve | Growth per step |
|---|---|---|
| Tools | `base[tier] × toolPriceMult[segment]` (§5.1) | ×2.5 – ×6 per tier; ×25 per segment |
| Plot slots | `1,000 × 2.25^n` | ×2.25 |
| Segment unlock | $1.5M → $600M → $250B | ×400 per segment (income ×10, carried treasures make up the gap) |
| Potions | seconds-of-income × base plot income (§5.2) | tracks progress |
| Rebirth | `2.5B × 12^R` | ×12 |
| Sell | 10 s × the treasure's base income | — |

### 8.3 Targets and justification

| Milestone | Target (active play, F2P, no potions) | Why |
|---|---|---|
| First upgrade | **45–75 s** (aim 60 s) | Mobile players decide in the first minute. A purchase inside it completes the loop (find → place → collect → buy) and teaches every system once. |
| Second segment (Fish) | **25–35 min** (aim 30 min) | About one long mobile session. New-area novelty lands at the end of session 1 for engaged players and in session 2 for casuals, a reason to come back on Day 1. |
| First rebirth | **2.5–3.5 h** (aim 3 h) | Mid-term hook: casual players (about 45 min/day) reach it around Day 3, engaged players on Day 1–2. Before D7, players have seen rebirth, kept their whole collection, and felt a faster second run. |

### 8.4 Simulation results

Run with `python3 tools/economy_sim.py --runs 200 --rolls 1000000` (≈4 min). Full log: `tools/economy_sim_output.md`.

**Headline (200 Monte-Carlo players each):**

| Milestone | Target | Full design, F2P, no potions | MVP build (Pets only, no onboarding luck) | Met? |
|---|---|---|---|---|
| **Time to first upgrade** | 45–75 s | **50 s** (p10 40 s, p90 65 s) | **59 s** (p10 40 s, p90 79 s) | ✅ |
| **Time to second segment** | 25–35 min | **34.9 min** (p10 22.3, p90 45.9) | n/a (one segment) | ✅ (upper edge) |
| **Time to first rebirth** | 2.5–3.5 h | **3.16 h** (p10 2.10, p90 4.03) | **3.19 h** (p10 1.92, p90 4.33) | ✅ |

**Full design, F2P, no potions (the tuning target):**

| Milestone | p10 | Median | p90 |
|---|---|---|---|
| First Rare+ find | 11 s | 23 s | 32 s |
| First upgrade (Wooden Whistle) | 40 s | 50 s | 65 s |
| First Legendary+ | 58 s | 5.1 min | 12.4 min |
| First Mythic+ | 4.8 min | 19.0 min | 44.3 min |
| Fish unlocked | 22.3 min | 34.9 min | 45.9 min |
| Cars unlocked | 83.0 min | 2.06 h | 2.71 h |
| First rebirth | 2.10 h | 3.16 h | 4.03 h |
| Second rebirth | 3.06 h | 4.47 h | 5.65 h |

**Potion user (keeps Cash + Luck potions running):** Fish 34.3 min, Cars 104.6 min, first rebirth **2.50 h**, second 3.28 h. Potions are worth buying but not required.

**MVP build (Pets only):** Legendary+ 5.3 min, Mythic+ 19.3 min, rebirth 3.19 h, second rebirth 7.99 h (189/200 within 12 h).

**Income curve (median, full design, F2P):**

| Active time | Cash/sec | Slots | Pets tool | Segment | Rebirths |
|---|---|---|---|---|---|
| 1 min | 66 | 6 | T2 | Pets | 0 |
| 5 min | 350 | 10 | T4 | Pets | 0 |
| 10 min | 815 | 12 | T5 | Pets | 0 |
| 30 min | 5,355 | 16 | T7 | Pets | 0 |
| 1 h | 51,400 | 19 | T7 | Fish | 0 |
| 2 h | 298,950 | 20 | T7 | Fish | 0 |
| 3 h | 2,255,000 | 20 | T7 | Cars | 0 |
| 4 h | 8,325,000 | 20 | T7 | Cars | 1 |

**Calendar scenarios (offline earnings 50%, 2 h cap between sessions):**

| Profile | Day 1 | Day 3 | Day 7 | First rebirth (median day) |
|---|---|---|---|---|
| Casual: 2 sessions/day (20 + 25 min) | 0 rebirths, 2 segments, 49K/s | 1 rebirth, 3 segments, 3.2M/s | 3 rebirths, 4 segments, 110M/s | Day 3.4 (p10 2.4, p90 4.0) |
| Engaged: 4 sessions/day (2.25 h incl. AFK) | 1 rebirth, 3 segments, 2.2M/s | 3 rebirths, 4 segments, 156M/s | 5 rebirths, 4 segments, 2.0B/s | Day 1.6 (p10 1.6, p90 2.0) |
| Engaged, MVP build | 0 rebirths, 70K/s | 2 rebirths, 425K/s | 3 rebirths, 1.5M/s | Day 2.0 (p10 1.6, p90 2.2) |

**Model assumptions:**

| Assumption | Value |
|---|---|
| Movement | 8 s spawn → zone walk. Always searches in the highest unlocked segment. |
| Collecting | First collect ≥ 40 s (tutorial). After that, collects when vault + cash ≥ the cheapest next purchase, 20–120 s apart. Each trip costs 6 s of searching. |
| Spending | Buys the cheapest available of next tool / next slot / next segment. Rebirths as soon as affordable. |
| Placement | Highest-income treasures fill the slots. Finds outside the best 20 are sold for 10 s of income, except Mythic+, which are never auto-sold. |
| Included | Pity, mutations, Index luck milestones, rebirth bonuses, keep-all-treasures rebirth; onboarding forced finds (full-design rows only) |
| Excluded | Friend boost, gamepasses, codes, Storm, enhancements; potions (except the potion-user run) |

**Tuning log:**

| Pass | Change | First upgrade | Fish | First rebirth |
|---|---|---|---|---|
| 1 | First guesses: Wooden Whistle $75, slot $150, rebirth $4M ×6, ×2 beginner luck for 10 min | 30 s | 26.8 min | **36 min** (far too fast) |
| 2 | Rebirth $2.5B ×12; Whistle $350; slot $500; beginner luck removed (40 runs) | 30 s | 29.3 min | 2.92 h |
| 3 | Modeled the spawn walk and tutorial collect; Whistle and slot $750 (200 runs) | 44 s (just under target) | 32.4 min | 3.11 h |
| 4 (final) | Whistle and first slot $1,000 (200 runs) | **50 s** | **34.9 min** | **3.16 h** |
| 5 | Rebirth keeps all treasures (Checkpoint 1 decision; 200 runs) | 50 s | 34.9 min | 3.16 h (2nd rebirth 4.47 h, was 4.51 h) |
| MVP | Pets-only rebirth cost sweep (40 runs): $50M → 1.6 h, $150M → 2.1 h, **$400M → 3.0 h** (chosen) | — | — | — |

---

## 9. Player-attraction features

### 9.1 Reveal cinematic (MVP)

Built to be clipped. The core composition stays inside the **center 50% of the screen width** so a 9:16 crop of a landscape phone recording keeps the whole reveal. Big rarity title plus **"1 in N" odds text**, so viewers instantly know how rare it is.

| Tier | Rarities | Length | Suspense beat | Screen shake | Sound | Skippable |
|---|---|---|---|---|---|---|
| R0 | Common, Uncommon | 1.2 s toast (no interruption) | — | none | soft pop / chime | n/a |
| R1 | Rare | 0.8 s | Card flip, blue flash | none | bright ding | yes |
| R2 | Epic | 1.4 s | 3-card shuffle spin, purple burst | 2 px, 0.15 s | whoosh + sparkle | yes |
| R3 | Legendary | 2.2 s | Silhouette roulette slows and stops, gold rays | 4 px | drumroll → cymbal | after 1 s |
| R4 | Mythic | 3.0 s | Screen dims, silhouette rumbles, pink burst | 6 px | choir hit | no |
| R5 | Divine | 4.0 s | Slow-motion, white-out flash, halo rings | 8 px | heavenly choir | no |
| R6 | Celestial | 5.0 s | Stars rush past (hyperspace), cyan nova | 10 px | orchestral swell | no |
| R7 | Cosmic | 6.0 s | Black-hole implosion → galaxy explosion | 12 px | deep bass drop | no |
| R8 | Secret | 7.5 s | **Fake-out**: shows a Cosmic plate, it cracks, VHS glitch, a beat of silence, rainbow shatter | 14 px | unique stinger | no |

Mutations add a second "+GOLDEN!" stamp beat (+0.5 s). "Reduce screen shake" setting (MVP\*). The server keeps searching during the cinematic. The client queues reveals and merges lower ones into a "+3 more finds" toast.

### 9.2 Banners and beams

| Feature | Trigger | Spec | MVP? |
|---|---|---|---|
| Server banner | Mythic+ | Top banner for all players in the server: "⭐ *DisplayName* found **Crystal Dragonling** [Mythic] (1 in 1,500)!", rarity-colored, 5 s, queue of 3 | **MVP** |
| Sky beam | Mythic+ | Rarity-colored `Beam` from the finder up into the sky for 10 s, visible across the map | Backlog |
| Cross-server announcement | Celestial+ | `MessagingService` topic `GlobalFind` with `{displayName, treasureId, rarity, mutation}`, no free text; smaller banner in every server; publish rate-limited to 1 per 10 s per server | Backlog |

### 9.3 Collection Index (MVP)

| Item | Spec |
|---|---|
| Layout | One page per segment. Unfound entries show as silhouettes with "1 in N" odds; found ones show the thumbnail, count found and the best mutation seen. |
| Completion rewards | 50% found → **+2% luck**; 75% → **+3% luck**; 100% → **+5% luck** + badge. Permanent and additive across segments (max +40%). |
| Badge | The badge must be created in Experience settings, so **I'll ask first** (the MVP awards luck without it until you approve). |
| Mutation Index | Each Finish/Aura seen per treasure (bitmask in the save) for extra rewards. Backlog. |

### 9.4 Pity counter (MVP)

| Floor | Guaranteed on dry search # | Base expected wait | Chance you ever need it |
|---|---|---|---|
| Epic+ | 120 | 40 | ≈5% |
| Legendary+ | 800 | 209 | ≈2% |
| Mythic+ | 5,000 | 1,278 | ≈2% |

Counters are global (all segments), saved, and kept on rebirth. The HUD shows the nearest one: "Legendary+ in 312". Divine+ has no pity, so it stays special and the economy stays safe.

### 9.5 Onboarding luck and tutorial (MVP)

Search #3 is forced Uncommon+ and search #8 is forced Rare+ (about 32 s in). The tutorial has 5 arrow steps: walk → watch → collect → buy → back. Skippable, under 60 s (§1.2). The full-design sim includes it. The "MVP build" sim rows were run without it, so the real MVP's first minute will be slightly faster (first Rare+ by 32 s at p90, instead of 68 s).

### 9.6 Treasure Storm (Backlog)

Global ×2 luck plus a storm skybox for 10 min every 2 h. Active when `os.time() % 7200 < 600`, so every server agrees with no messaging. A HUD countdown reads "Storm in 12:34".

### 9.7 Social rewards

| Feature | Spec | MVP? |
|---|---|---|
| Friend boost | +10% cash per friend in the server, capped at +50% (5 friends). Server checks `Player:IsFriendsWith` on join/leave, cached per pair. HUD chip "👥 +30%". | **MVP** |
| Group reward | +5% cash while a member, plus a one-time 3 Luck Potions. Verified on the server with `Player:IsInGroupAsync(groupId)` on join and via a "Verify" button (rate-limited, 1 per 30 s). | Backlog |
| Codes | Code strings live **server-only** (`ServerStorage`), so they can't be datamined. Input is trimmed, case-insensitive, 1–20 characters, `[A-Za-z0-9]`. Each code has a reward and an optional expiry; once per profile. Brute-force guard: 10 failures per 10 min → 10-min cooldown. **Launch code: `SEEKATREASURE`** (default reward 2 Luck + 2 Cash Potions until you pick one). | **MVP** |
| "Next code at X likes" board | In-world board by spawn: "👍 12,345 / 15,000 likes, next code at 15K!" Milestones come from Config. If the live count is unavailable, it falls back to static text. | **MVP** |
| Live like/visit counter | `LikeCounterService` polls the experience's up-votes (and visits) every 5 min per server, caches the value, and pushes it to the board. Needs **Allow HTTP Requests** (Experience setting) and a proxy, because `HttpService` can't call roblox.com directly. Options: a public proxy (RoProxy) or one you host. Both need your approval before I touch them. | **MVP** (pending approval) |

### 9.8 Playtime gifts, daily streak, leaderboards (Backlog)

| Feature | Spec |
|---|---|
| Playtime gifts | Session gifts at 5 / 10 / 15 / 25 / 40 / 60 min: potions and "N minutes of income" cash. Resets each session. |
| Daily streak | 7-day ladder; day 7 = Mutation Potion ×3 + 30 min of income. Saved as `{day, lastDay}` (UTC day number). Missing a day resets to 1. |
| Lobby leaderboards | Three `OrderedDataStore`s: lifetime cash earned, rebirths, rarest find (score = `rarity × 100 + mutation weight`). Written on save, read every 120 s, top 50 on in-world boards. |

### 9.9 Plot showcase (Backlog)

A showcase pedestal at the plot entrance facing the street automatically shows your rarest treasure under a spotlight with your name, so it's on display to everyone walking to the search areas.

### 9.10 Weekly content plan (Backlog; one limited item per update)

| Week | Update | Limited item | Type |
|---|---|---|---|
| 1 | Launch | Launch code "TREASURE" | — |
| 2 | Harvest Week | **Harvest** Finish (×4, amber-leaf material), weight 8, 7 days | Mutation |
| 3 | Fish segment | **Lucky Lantern Koi** (Fish, Legendary pool, weight 0.5) | Treasure |
| 4 | Frost Week | **Frostbite** Aura (×2.5, snow particles) | Mutation |
| 5 | Holiday | **Gift-Box Mimic** (Pets, Mythic pool) | Treasure |
| 6 | New Year | **Firework** Aura (×3, burst particles) | Mutation |
| 7 | Cars segment | **Sleigh Racer** (Cars, Divine pool) | Treasure |
| 8 | Lunar Week | **Jade** Finish (×6) | Mutation |

Limited items stay in Config with `availableFrom` / `availableUntil` Unix timestamps. Once found, they're kept forever (FOMO plus Index flex).

---

## 10. Monetization (all Backlog; creating any product needs your approval)

### 10.1 Gamepasses

| Gamepass | Price (R$) | Effect |
|---|---|---|
| 2x Cash | 249 | Plot income ×2 (also applies to offline) |
| 2x Luck | 299 | Luck ×2 (still within the 25x cap) |
| Auto-Collect | 149 | Vault goes straight to the wallet, no pad walk |
| +4 Plot Slots | 199 | Unlocks the 4-pedestal row (20 → 24) |
| VIP | 399 | +25% cash, offline cap +4 h and 75% offline rate, VIP chat tag, VIP lounge |
| Fast Search | 199 | Search interval ×0.8 |

### 10.2 Developer products

| Product | Price (R$) | Effect |
|---|---|---|
| Luck Potion ×3 | 39 | 3 × 10 min |
| Mega Potion Pack | 129 | 3 of each potion |
| Server Luck Boost | 99 | ×2 luck for **everyone in the server** for 15 min (stacks duration). Banner: "🍀 *DisplayName* boosted the server's luck!" |
| Cash Pouch / Chest | 49 / 149 | 30 min / 2 h of current base income |

### 10.3 Paid-random compliance

- Any Robux purchase whose outcome is random (e.g., a future Robux Finish Reroll or mystery chest) shows the **exact odds table before purchase**.
- It's hidden for players where `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted` is true. The lookup is cached per player and **fails closed** (treated as restricted on error).
- Robux luck boosts change the odds of free rolls. To be conservative, they show the boosted odds table and use the same gate.
- `ProcessReceipt` is idempotent: receipt IDs are stored in the profile (last 100). It returns `NotProcessedYet` until the profile is loaded and grants only after the save succeeds.

---

## 11. Data schema

### 11.1 Profile v1 (one key per player, `DataStore "SFT_Profiles_v1"`, key `u_<UserId>`)

```lua
type InventoryEntry = {
    id: string,            -- "pets_ember_fox"
    segment: string,       -- "pets"  (redundant with id; validated against Config on load)
    rarity: number,        -- 1..10
    mutation: { string },  -- 0..2 ids, e.g. { "golden", "blazing" } (one Finish + one Aura max)
    level: number,         -- 1..10 (enhancement; MVP always 1)
    t: number,             -- unix time found
}
type Profile = {
    schema: number,                                 -- 1
    cash: number, vault: number, lifetimeEarned: number,
    rebirths: number,
    inventory: { [string]: InventoryEntry },        -- key = uid "t<n>"; cap 300 entries
    nextUid: number,
    plot: { slots: number, layout: { [string]: string } },   -- "1".."24" -> uid (string keys: no sparse arrays)
    tools: { [string]: { owned: number, equipped: number } }, -- per segment, tier numbers
    segments: { [string]: boolean },
    potions: { luck: number, speed: number, mutation: number, cash: number },  -- unix expiry, 0 = none
    pity: { epic: number, legendary: number, mythic: number },
    index: { [string]: { n: number, m: number } },  -- treasureId -> count found, mutation bitmask seen
    indexRewards: { [string]: number },             -- segment -> highest milestone claimed (0..3)
    codes: { [string]: number },                    -- code -> unix time redeemed
    streak: { day: number, lastDay: number },
    stats: { searches: number, playtime: number, rarest: { id: string, rarity: number, mutation: { string } }? },
    purchases: { [string]: number },                -- receipt id -> unix time (last 100)
    settings: { reduceShake: boolean, music: boolean, sfx: boolean },
    flags: { tutorialDone: boolean },             -- added in Phase 2 (tutorial completion)
    lastOnline: number,
    _lock: { jobId: string, t: number }?,           -- session lock (§11.3)
}
```

### 11.2 Maximum size vs. the 4 MB limit

| Component | Worst case | JSON bytes |
|---|---|---|
| Inventory | 300 entries with the longest ids, 2 mutations, level 10 | 40,201 |
| Index | 160 entries (40 per segment, room for limited items) | 7,241 |
| Codes | 200 redeemed | 6,801 |
| Purchases | 100 receipts | 4,601 |
| Everything else | plot (24 slots), tools, potions, pity, stats, lock | 1,237 |
| **Total** | measured with `json.dumps` on a generated worst-case profile | **60,125 B = 1.43% of the 4,194,304-character limit** |

Caps are enforced on the server: inventory 300 (overflow below Legendary is auto-sold; Legendary+ overflow sells the lowest unplaced item instead), purchases trimmed to 100, codes ≤ 200.

### 11.3 Saving rules (roblox-datastores)

| Rule | Spec |
|---|---|
| All calls | `pcall` + retries with backoff 1, 2, 4, 8, 16 s (max 5); `UpdateAsync` only (never `SetAsync`) |
| Session lock | On load, `UpdateAsync` stamps `_lock = {jobId = game.JobId, t = os.time()}` only if it's empty, ours, or stale (> 300 s old; autosave refreshes it). If it's held by a live server, retry 5 times (about 31 s), then kick with "Your data is still saving in another server, please rejoin." |
| Autosave | Every 90 s per player, staggered by join time (inside the 60–120 s window); refreshes `lastOnline` and the lock |
| Leave | Final save on `PlayerRemoving` and clear `_lock` in the same `UpdateAsync` |
| Shutdown | `BindToClose` saves all players in parallel (`task.spawn`) and waits up to 25 s |
| Failed load | Profile is marked `loaded = false`; **never saved**; player is kicked with a retry message. Stored data is untouched. |
| Callback purity | `UpdateAsync` callbacks don't yield and have no side effects. They return `nil` to abort if the stored lock isn't ours. |
| Budget | 8 players × 1 save / 90 s ≈ 5.3 `UpdateAsync`/min, far below the per-server limit (60 + 10 × players) |
| RTBF | `RemoveAsync("u_<UserId>")` plus ordered-store entries (when leaderboards exist) |

### 11.4 Migration plan

1. Every profile carries `schema`. The server has `CURRENT_SCHEMA` and an ordered `Migrations[from] = function(p) → p` list.
2. On load: run migrations from `p.schema` up to `CURRENT`, then **reconcile** with the default template (deep fill of missing fields, drop unknown top-level keys into `p._legacy` for one version).
3. Unknown treasure ids (removed from Config) go through `Config.Renames` if present; otherwise they're converted to cash (60 s of their stored income) and logged.
4. **Newer-than-code** (`p.schema > CURRENT`, e.g. during a rolling update): load **read-only**, never save, show "Update available, please rejoin."
5. Migrations are pure functions with unit tests (fixture profile per version). Keep `DataStoreKeyInfo` versions so `GetVersionAsync` can roll back a bad deploy.

---

## 12. Architecture (Rojo-friendly; mirrored in Studio via the MCP)

```text
ReplicatedStorage/
  Shared/
    Config/                 -- ALL game data; adding a segment = data + area
      Rarities.luau         -- §2.1
      Mutations.luau        -- §3.1 (families, weights, caps)
      Pity.luau             -- §9.4
      Potions.luau          -- §5.2
      Upgrades.luau         -- §5.4 (slot curve)
      Rebirth.luau          -- §7
      Economy.luau          -- §8.1 constants (offline rate/cap, sell seconds, luck cap, friend boost)
      Index.luau            -- milestones
      Reveal.luau           -- §9.1 timings per tier
      Social.luau           -- friend boost, code-board text (NOT code strings)
      Segments/
        init.luau           -- ordered list of segment modules
        Pets.luau           -- area id, unlock cost, multipliers, tool line, treasure pool
        (Fish, Cars, Anime) -- Backlog
    Types.luau              -- Profile, InventoryEntry, remote payloads
    Net.luau                -- remote name list + typed wrappers
    RollMath.luau           -- pure: probTable(L), pickTier(u, table), mutationMultiplier
    EconomyMath.luau        -- pure: treasureIncome, plotIncome, prices, offline earnings
    Format.luau             -- 1.23M style formatting
  Assets/ Treasures/<segment>/<id>, Pedestals, VFX, Sounds
ServerScriptService/Server/
  init.server.luau          -- the only Script: two-phase init/start
  Services/
    DataService.luau        -- load/lock/autosave/release/migrate
    ZoneService.luau        -- 5 Hz character-position checks (search zones, collect pads)
    SearchService.luau      -- tick loop, roll, pity, modifiers
    InventoryService.luau   -- add/sell/caps
    PlotService.luau        -- claim, place/remove, vault accrual, collect, offline
    ShopService.luau        -- tools, slots, segment unlock
    PotionService.luau
    RebirthService.luau
    IndexService.luau
    CodeService.luau
    SocialService.luau      -- friend boost
    AnnounceService.luau    -- Mythic+ banner
    TelemetryService.luau   -- AnalyticsService wrapper (MVP)
    LikeCounterService.luau -- live like count for the code board (pending HTTP + proxy approval)
    DevService.luau         -- Studio-only, UserId 422765950
  Util/ RateLimiter.luau, Guard.luau, Retry.luau, Signal.luau
ServerStorage/
  Secrets/Codes.luau        -- code strings + rewards (never replicated)
StarterPlayer/StarterPlayerScripts/Client/
  init.client.luau          -- the only LocalScript
  Controllers/ State, HUD, Shop, Inventory, Index, Reveal, Banner, PlotVisuals, Sound, Settings
  UI/ Theme.luau, Components/ (Button, Panel, RarityFrame, MutationBadge, Toast)
Workspace/World/
  Lobby/, CodeBoard, Plots/Plot_01..08 (Pedestals/P01..P24, CollectPad, Arch),
  Segments/Pets/ (Area, SearchZone [attr SegmentId="pets"], Gate)
```

### 12.1 Remotes (all `RemoteEvent`, created by the server from `Net`'s list)

| Remote | Dir | Args | Server validation | Rate limit |
|---|---|---|---|---|
| `Plot_Place` | C→S | `slot: number, uid: string` | integer 1..slots, not NaN/inf; uid string ≤ 12, owned, not already placed | 5/s, burst 10 |
| `Plot_Remove` | C→S | `slot: number` | integer 1..slots, occupied | 5/s, burst 10 |
| `Plot_PlaceBest` | C→S | — | profile loaded | 1/s |
| `Inv_Sell` | C→S | `uid: string` | owned, not placed | 5/s, burst 10 |
| `Shop_BuyTool` | C→S | `toolId: string` | exists, segment unlocked, exactly next tier, affordable | 2/s |
| `Shop_EquipTool` | C→S | `toolId: string` | owned | 2/s |
| `Shop_BuyPotion` | C→S | `potionId: string` | exists; price computed on server | 2/s |
| `Shop_BuySlot` | C→S | — | slots < 20, affordable | 2/s |
| `Segment_Unlock` | C→S | `segmentId: string` | exactly the next segment, affordable | 1/s |
| `Rebirth_Request` | C→S | — | cash ≥ cost | 1 / 2 s |
| `Code_Redeem` | C→S | `code: string` | length 1..20, alnum, not redeemed, exists, not expired, failure lockout | 1 / 2 s, burst 3 |
| `Settings_Set` | C→S | `key: string, value: boolean` | key in `settings`, boolean | 2/s |
| `Tutorial_Done` | C→S | — | profile loaded | 1 / 5 s |
| `Dev_Command` | C→S | `cmd: string, arg: number?` | **Created only if `RunService:IsStudio()`**; UserId must equal the dev id | 5/s |
| `State_Snapshot` | S→C | public profile view | on load | — |
| `State_Delta` | S→C | changed fields | batched ≤ 4 Hz | — |
| `Search_State` | S→C | `{active, segmentId, interval, startedAt}` | on change | — |
| `Search_Reveal` | S→C | `{uid, treasureId, rarity, mutation, pity}` | per find | — |
| `Announce_Banner` | S→all | `{displayName, treasureId, rarity, mutation}` | Mythic+ | — |
| `Notify` | S→C | `{kind, key, args}` | — | — |

Every handler starts with `RateLimiter.allow` → type check → range/NaN check → permission check → plausibility check, and silently drops anything that fails (logged with a counter, never auto-ban). Clients never send prices, amounts, positions or results.

---

## 13. ForgeGUI asset list

### 13.1 Style guide: "Sunny Toybox"

| Element | Rule |
|---|---|
| Shape language | Chunky low-poly, soft bevels, toy proportions (big heads, short limbs), flat shading with gentle vertex-color gradients; no photoreal textures |
| Texture | One palette-atlas texture ≤ 512² per model; no baked text |
| Palette tokens | Sky `#49B6FF`, Sun `#FFD23F`, Leaf `#5BD66B`, Coral `#FF6B6B`, Grape `#8E5CFF`, Cream `#FFF4DF`, Ink `#1D2340` (outlines/text), Cash `#3DDC84` |
| UI panels | Cream fill, 3 px Ink `UIStroke`, corner radius 0.2 of the short side, inner top highlight, drop shadow (0, 4) Ink at 30% |
| Buttons | Pill shape; primary Sun, secondary Sky, danger Coral; pressed = 0.94 scale + darker; disabled = 50% desaturated |
| Fonts | Headings `Enum.Font.FredokaOne`; numbers Builder Sans Bold |
| Icons | 256² transparent PNG, 12% padding, thick Ink outline, 2-tone fill |
| Lighting | Future, warm sun, light atmosphere, low bloom |
| Motion | `FAST` 0.15 s Quad, `BOUNCY` 0.3 s Back, `REVEAL` per §9.1 |

### 13.2 UI kit

| Asset | Count | Notes |
|---|---|---|
| HUD: cash pill, vault pill, search ring, stat chips (luck/speed/mutation), potion timer chips, pity meter, friend chip | 1 set | Scale-based; tested at phone, tablet and 1080p |
| HUD buttons: Shop, Inventory, Index, Rebirth, Codes, Settings | 6 icons | ≥ 48 dp touch targets, bottom-left / right thumb zones |
| Panels: Shop (Tools / Potions / Upgrades tabs), Inventory grid, Index grid, Rebirth confirm, Codes, Settings, Welcome-back | 7 | 9-slice panel + tab art |
| Rarity frames | 10 | 9-slice 512². Ornament escalates: plain → leaf corners → gem corners → double border → gold filigree → flame edge → wings → star border → galaxy fill → glitch-rainbow edge |
| Mutation badges | 9 | 128² icons (Golden, Crystal, Rainbow, Shadow, Prismatic, Glowing, Blazing, Electric, Starlit) |
| Potion icons | 4 | Luck, Speed, Mutation, Cash |
| Tool icons | 8 (MVP: Whistles) | +24 for the other segments (Backlog) |
| Currency icon, padlock, "NEW!" stamp, odds tag | 4 | — |
| Reveal kit: ray burst (white, tinted at runtime), star burst, 10 rarity title plates, banner strip | 13 | — |

### 13.3 Treasure models (low-poly stylized)

| Rarity band | Triangle budget | Notes |
|---|---|---|
| Common / Uncommon | ≤ 1,500 | — |
| Rare / Epic | ≤ 2,500 | — |
| Legendary / Mythic | ≤ 3,500 | — |
| Divine / Celestial | ≤ 5,000 | — |
| Cosmic / Secret | ≤ 6,000 | — |
| **Worst case in view** | about 8 plots × 20 × 2,500 avg ≈ 400K tris server-wide; StreamingEnabled + `RenderFidelity.Automatic` keep about 2–3 plots on screen | Mutations are runtime material/color/particle overlays, so there are **no extra models per mutation** |

Count: 12 per segment, **12 in the MVP** and 36 in the Backlog. Pipeline: `generation_model_3d` (style-locked) → `asset_prepare` (measure tris, `bounds_bottom_center` pivot, scale to a 4-stud height) → human originality review → `artifact_publish` (needs a valid Roblox connection and **your go-ahead**).

### 13.4 Area props and plot pedestals (MVP = Pets + plots)

| Asset | Count | Budget |
|---|---|---|
| Plot base (floor + border + owner arch) | 1 (instanced ×8) | ≤ 4,000 tris |
| Pedestals: stone, bronze, gold, crystal, cosmic | 5 | ≤ 800 each |
| Collect pad | 1 | ≤ 600 |
| Meadow kit: flower bush ×3, hollow log, picket fence, pet-bowl fountain, signpost, rock ×2 | 9 | ≤ 1,500 each |
| Segment gate (price sign) | 1 | ≤ 2,000 |
| Code board | 1 | ≤ 1,000 |
| Spawn plaza centerpiece (treasure chest statue) | 1 | ≤ 3,000 |
| Sounds: 9 reveal stingers, search tick, collect, buy, error | 13 | via `generation_sound_effect` |
| Backlog: Lagoon, Scrapyard and Shrine kits (about 9 each), skyboxes, music | — | — |

### 13.5 Game icon and thumbnails

| Asset | Size | Concept |
|---|---|---|
| Icon | 512² | An open treasure chest bursting with light; the Crystal Dragonling, Comet Narwhal, Neon Drifter and Starweaver peek out; rainbow rays. Logo text added as a separate GUI layer (no AI text). |
| Thumbnail A "The Reveal" | 1920×1080 | Avatar silhouette facing a giant SECRET reveal burst with "1 in 5,000,000" |
| Thumbnail B "The Plot" | 1920×1080 | A plot packed with glowing mutated treasures on pedestals at golden hour |
| Thumbnail C "Four Worlds" | 1920×1080 | Diagonal 4-way split: Meadow, Lagoon, Scrapyard, Shrine, each with its Mythic |

**Generation estimate (MVP):** about 12 models + 19 props/pedestals + about 50 GUI images + 13 SFX + 4 key art ≈ **98 generations**, with up to ×1.5 for retries. Budget: **10,000 credits** (approved). ForgeGUI job results don't show a credit amount (billing is deferred), so spend is tracked on the ForgeGUI dashboard.

### 13.6 Style test (2026-11-04)

Style identity **Sunny Toybox**: `771db88d-81d1-41e5-9e05-cc70571707ec`, v1. ForgeGUI run: `974c4428-9111-4352-b24b-a6ae673d047f`.

| # | Asset | Tool | Result | Artifact |
|---|---|---|---|---|
| 1 | Shop HUD icon | `generation_gui` (icon) | ✅ generated | [image](https://azyjlkhpdgafuobyxoax.supabase.co/storage/v1/object/public/asset-images/ddbf3f20-babe-49f8-8941-ee1ca2e76629/mcp/1cff7c6a-0fb5-4e90-9386-3afe297fcaac-0.png) · `mcp-artifact:1cff7c6a-0fb5-4e90-9386-3afe297fcaac:0` |
| 2 | Legendary rarity frame | `generation_gui` (frame) | ✅ generated | [image](https://azyjlkhpdgafuobyxoax.supabase.co/storage/v1/object/public/asset-images/ddbf3f20-babe-49f8-8941-ee1ca2e76629/mcp/dda4c44b-84d6-459e-ac1c-362e63fff676-0.png) · `mcp-artifact:dda4c44b-84d6-459e-ac1c-362e63fff676:0` |
| 3 | Shop panel | `generation_gui` (panel) | ✅ generated | [image](https://azyjlkhpdgafuobyxoax.supabase.co/storage/v1/object/public/asset-images/ddbf3f20-babe-49f8-8941-ee1ca2e76629/mcp/88cb1436-dd93-4909-91fd-8e2de7511785-0.png) · `mcp-artifact:88cb1436-dd93-4909-91fd-8e2de7511785:0` |
| 4 | Toasty Corgi (Rare) | `generation_model_3d` | ⛔ refused: `paid_generation_required` | — |
| 5 | Crystal Dragonling (Mythic) | `generation_model_3d` | ⛔ refused: `paid_generation_required` | — |
| 6 | Gold pedestal | `generation_model_3d` | ⛔ refused: `paid_generation_required` | — |

This cloud session's network policy blocks the image host, so the three images still need **your** visual review. The 3D half of the test reruns after the plan upgrade.

---

## 14. Analytics (AnalyticsService, MVP)

### 14.1 Onboarding funnel (`LogOnboardingFunnelStepEvent`, once per player)

| Step | Name | Fired when |
|---|---|---|
| 1 | `Loaded` | Profile loaded, plot claimed |
| 2 | `EnteredSearchZone` | First zone entry |
| 3 | `FirstFind` | First reveal |
| 4 | `FirstRarePlus` | First Rare+ |
| 5 | `FirstPlaced` | First treasure on a pedestal |
| 6 | `FirstCollect` | First vault collect |
| 7 | `FirstToolBought` | Wooden Whistle |
| 8 | `FirstPotion` | Any potion bought |
| 9 | `Session5Min` | 5 min in session |
| 10 | `Session10Min` | 10 min in session |

### 14.2 Economy events (`LogEconomyEvent`, currency "Cash")

| Flow | Transaction type | itemSku | Logged |
|---|---|---|---|
| Source | Gameplay | `Collect` | per collect (not per tick) |
| Source | TimedReward | `Offline` | on join |
| Source | Gameplay | `Sell_<rarity>` | per sell (batched per 10 s) |
| Source | TimedReward | `Code_<code>` | per redeem |
| Sink | Shop | `Tool_<id>` | per purchase |
| Sink | Shop | `Potion_<type>` | per purchase |
| Sink | Shop | `Slot_<n>` | per purchase |
| Sink | Gameplay | `Segment_<id>` | per unlock |
| Sink | Gameplay | `Rebirth_<n>` | cash wiped at rebirth |

Custom/progression events (low cardinality): `RareFind` (rarity ≥ Mythic, segment), `PityTriggered` (floor), `Mutation` (family, id), `Rebirth` (count), progression path `Segments` levels 1–4, `FriendBoost` (count bucket).

---

## 15. Risks and open questions

### 15.1 Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **Studio MCP not connected** (Phase 2 blocker) | Can't build or test | Run Phase 2 in Claude Code on the computer that has Studio |
| **ForgeGUI 3D locked on the current plan** (Phase 2 blocker) | No treasure models, props or pedestals | Upgrade the plan; no 3D calls until then |
| ForgeGUI publish connection invalid | Generated models can't be uploaded | Fix the API-key permissions in ForgeGUI `/forge-mcp`; I ask before any upload |
| IP resemblance (Anime, Cars) | Takedown / moderation | Guardrail prompts (§4.2), human review, Pets first |
| Style drift across ~100 generations | Looks cheap, hurts virality | One ForgeGUI style id + reference images; a 6-asset style test before bulk generation |
| Mobile performance (models + particles) | Low FPS, churn | Triangle budgets, StreamingEnabled, particle caps, billboard `MaxDistance` |
| Economy inflation and luck variance | Pacing breaks | Sim-tuned curves, 25x luck cap, no pity above Mythic, keep the sim as the source of truth for Config |
| DataStore failures and dupes | Data loss | §11.3 session lock, UpdateAsync-only, never save after a failed load |
| Engagement-incentive policy (like-milestone codes) | Policy strike | Codes are community-wide (no per-user "like to unlock"); re-check Roblox policy before launch |
| Paid random items | Compliance | Odds shown, PolicyService gate that fails closed (§10.3) |
| MVP rebirth cost changes when Fish ships | Early rebirths feel cheap | Keep the MVP private/test-only, or accept and message it |

### 15.2 Open questions

All 8 Checkpoint 1 questions were answered on 2026-11-04; see §0.1. The items still open before Phase 2 are listed in §0.1 under "Still open".
