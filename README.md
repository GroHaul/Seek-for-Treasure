# Seek for Treasure

Idle RNG collection tycoon for Roblox. Design: [`SeekForTreasure_GDD.md`](SeekForTreasure_GDD.md).

## Layout (Rojo: `default.project.json`)

| Folder | Roblox location | Contents |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | `Config/` (all game data), `Types`, `Catalog` (lookups), `RollMath`, `EconomyMath`, `Net`, `Format`, `Util/` |
| `src/server` | `ServerScriptService.Server` | `init.server.luau` bootstrap, `Services/`, `Data/` (profile template, migrations, session store, mock store), `Util/` |
| `src/secrets` | `ServerStorage.Secrets` | server-only data (code strings) |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | client bootstrap and controllers |
| `tests/studio` | `ServerStorage.SFT_Tests` | Studio test specs (run through the Studio MCP or the command bar) |
| `tools/` | — | `economy_sim.py` (economy tuning) and its output |
| `tests/verify_config.py` | — | Config matches GDD + sim (static) |

## Working in Studio

Toolchain is pinned in `rokit.toml` (`rokit install`). Live sync:

```bash
rojo serve --port 34872
```

Then click **Connect** in the Rojo plugin in Studio.

Without a published place, Studio has no DataStore access, so `DataService` falls back to an in-memory `MockStore` (printed in Output; nothing persists between playtests). Live servers always use the real DataStore.

## Checks

```bash
bash scripts/check.sh
```

Runs StyLua, Selene, strict `luau-lsp` type checking and a Rojo build.

```bash
python3 tests/verify_config.py
```

Studio specs (Edit mode, command bar or MCP):

```lua
require(game.ServerStorage.SFT_Tests["Config.spec"]:Clone())()
require(game.ServerStorage.SFT_Tests["RollMath.spec"]:Clone())()
require(game.ServerStorage.SFT_Tests["SessionStore.spec"]:Clone())()
```

UI layout check (Studio, during a playtest, client side):

```lua
local gui = game.Players.LocalPlayer.PlayerGui.SFT_UI
gui:SetAttribute("EmulateViewport", Vector2.new(844, 354)) -- lay out as a landscape phone
gui:SetAttribute("EmulateZoom", 0.5) -- optional: draw smaller (e.g. to preview 1080p)
```

During a playtest, the Studio-only `ServerStorage.SFT_TestHook` BindableFunction reads live server state (`profile`, `searching`, `plot`, `rejoin`, `mock`, `dev`, `find` (forced rarity/mutation for reveal tests), `friends`, `telemetry`, ...). It's created only when `RunService:IsStudio()`.

## Phase 2 status

| Step | Status | Evidence (Studio, 2026-11-07) |
|---|---|---|
| 1. Shared Config modules | ✅ | `Config.spec` 110/110; `verify_config.py` 181/181 |
| 2. DataService | ✅ on the mock store | `SessionStore.spec` 31/31 (lock, stale takeover, lost lock, retries, failed load leaves data unchanged, newer schema read-only, NaN refused, migrations). Live: failing store → 6 tries each for release and load, kick, 0 writes. Real DataStore needs a published place. |
| 3. Search | ✅ | 10 s in zone = 3 searches at 3.0 s; 6 s outside = 0. Forced Uncommon+ on #3 and Rare+ on #8; pity 119/799/4999 → Epic/Legendary/Mythic; luck/interval modifiers and the 25x cap. `RollMath.spec`: 1M rolls all within ±5%, mutation cap 10.0x. |
| 4. Plot | ✅ (single client) | Claim + spawn on plot, auto-fill, Place Best, place/remove validation, vault accrual at server rate, own-pad collect only, offline 1 h = base × 3600 × 50%, 10 h capped at 2 h, Cash potion excluded; data survives a simulated rejoin. |
| 5. Shop, potions, rebirth, codes | ✅ (single client) | All fired from the real client. Tools: next tier only, exact price, equip-lower is cosmetic. Slots: $1,000 → $2,250, new slots auto-fill. Potions: price = max(min, seconds × base income), +10 min per buy, refused past 60 min (no charge). Rebirth: $1 short refused; double-fire = 1 rebirth; resets cash/vault/tools/slots, keeps treasures/pity/potions/stats; next cost $4.8B. Codes: `SEEKATREASURE` trimmed + case-insensitive → 2 Luck + 2 Cash doses; reuse refused; 10 failures → 10-min lockout. |
| Remote fuzz (acceptance) | ✅ | 3,798 events across all 14 C→S remotes (wrong types, negatives, NaN/inf, 5,000-char strings, tables, Instances, 400× spam bursts): profile fingerprint identical before/after, no handler errors in Output. |
| 6. UI and models | ✅ UI (native, Sunny Toybox style); ⛔ ForgeGUI art blocked | HUD (cash, income, vault, luck/speed/mutation/friend chips, potion timers, search bar, pity meter), toasts, Welcome-back popup, Shop (Tools/Potions/Upgrades), Bag (place/remove/sell/Place Best), Rebirth confirm, Codes, Settings, 5-step tutorial with arrow beam, code board, client idle bob + hue cycle. Layout audit with `EmulateViewport`: iPhone SE 667×339, iPhone 14 844×354, iPad 1024×732, 1080p 1920×1022 — every button ≥ 48 px (smallest 48.4), no HUD overlaps, every panel fits. Placing Storm Pony from the Bag raised income 35 → 234/s on the server. ~2.5 min soak with panels cycling: no errors. ForgeGUI images can't be used: the Roblox publishing connection is `needs_validation / asset_permission_missing`; 3D generation is locked on the plan. `src/client/UI/Assets.luau` takes the image ids once uploads work; emoji glyphs stand in until then. |
| 7. Index, reveal, banner, friend boost | ✅ (single client) | **Index:** finds recorded with mutation bitmask; 6/12 → luck ×1.02, 9/12 → ×1.05, 12/12 → ×1.10; panel shows found ×n, mutations seen, silhouettes + odds for unfound. **Reveal:** R0 toast through R8 Secret fake-out (Cosmic plate → crack/glitch → silence → rainbow shatter), center-50% composition, mutation stamp, skip per Config, queue of 3 with "+N more finds" merge; Reduce screen shake: camera offset 0.225 studs → 0. **Banner:** Mythic+ to every client, delayed for the finder until their own cinematic ends (no spoiler). **Friend boost:** +10%/friend, cap +50% (0/1/3/5/7 friends → ×1.0/1.1/1.3/1.5/1.5), base/offline income excludes it, HUD chip; tested through a Studio-only seam since real friendships need two befriended accounts. **Telemetry:** AnalyticsService funnel steps 1–10, economy sources/sinks (collect and sell batched every 30 s), RareFind / PityTriggered / Mutation / Rebirth / IndexMilestone custom events. Layout audit re-run on 4 devices with the Index button and banner: all buttons ≥ 48 px, no overlaps. ~1 min normal-play soak: no errors. |
