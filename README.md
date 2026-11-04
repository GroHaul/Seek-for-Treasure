# Seek for Treasure

Idle RNG collection tycoon for Roblox. Design: [`SeekForTreasure_GDD.md`](SeekForTreasure_GDD.md).

## Layout (Rojo: `default.project.json`)

| Folder | Roblox location | Contents |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | `Config/` (all game data), `Types.luau`, `Util/` |
| `src/server` | `ServerScriptService.Server` | server bootstrap and services |
| `src/secrets` | `ServerStorage.Secrets` | server-only data (code strings) |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | client bootstrap and controllers |
| `tools/` | — | `economy_sim.py` (economy tuning) and its output |
| `tests/` | — | `verify_config.py` (Config matches GDD + sim) |

## Checks

```bash
python3 tests/verify_config.py
```

```bash
python3 tools/economy_sim.py --runs 200 --rolls 1000000
```

## Phase 2 status

| Step | Status |
|---|---|
| 1. Shared Config modules | Written; statically verified against the GDD and the sim (181/181). Not yet run in Studio. |
| 2–7 | Not started: needs a session with the Roblox Studio MCP (or a Luau runtime) to test each step. |
