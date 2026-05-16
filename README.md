# Distortionz CAD

> Full Computer-Aided Dispatch / MDT for Qbox — citizen & vehicle search, criminal records, warrants, BOLOs, incident reports, live dispatch with unit status, and a central call hub the rest of the stack feeds into. Police-only.

![FiveM](https://img.shields.io/badge/FiveM-cerulean-yellow?style=flat-square&labelColor=181b20)
![Qbox](https://img.shields.io/badge/Qbox-required-red?style=flat-square&labelColor=dfb317)
![License](https://img.shields.io/badge/License-MIT-brightgreen?style=flat-square)
![Version](https://img.shields.io/github/v/release/Distortionzz/Distortionz_CAD?style=flat-square&color=d4aa62&label=version)

---

## Overview

Open with `/cad`. Gated to law enforcement (qbx job type `leo`, or job
names in `Config.Access`). Premium Distortionz dark/red NUI with four
tabs:

- **Dispatch** — live active-call feed (priority-colour-coded), unit
  roster with 10-code status, attach/detach/close, create call, auto
  waypoint + map blips
- **Search** — citizens (name/CID) and vehicles (plate), read live from
  `players` / `player_vehicles`; click a result for a full profile
  (info, active warrants, charge history, registered vehicles)
- **Records** — log charges from preset offences (auto fine + jail
  totals), issue/serve warrants, post/clear BOLOs
- **Reports** — typed incident narratives with involved parties

## Central dispatch hub

Other resources surface as live CAD calls through one entry point:

```lua
-- server-side, from any resource:
exports.distortionz_cad:AddCall({
    code = '10-90', title = 'Bank alarm', location = 'Legion Sq',
    coords = { x = 150.0, y = -1040.0, z = 29.0 }, priority = 1,
})
-- or, fire-and-forget:
TriggerEvent('distortionz_cad:server:addCall', { ... })
```

- `qbx_police`'s `police:server:policeAlert` is **auto-bridged** — no
  wiring needed.
- `distortionz_scrapper`, `distortionz_speedcam` and
  `distortionz_weedfarm` feed the hub on their police-alert path (added
  in their respective versions; no-op if CAD isn't running).

## Dependencies

| Resource | Required | Purpose |
|---|---|---|
| `qbx_core` | yes | Player/job data, LEO gate |
| `ox_lib` | yes | Callbacks, notify |
| `oxmysql` | yes | Records persistence |

## Installation

1. Run `sql/distortionz_cad.sql` once.
2. `server.cfg`:

```cfg
ensure qbx_core
ensure ox_lib
ensure oxmysql
ensure distortionz_cad
```

3. Open with `/cad` (or set `Config.Access.keybind` / `item`).

## Configuration

`config.lua` — access (job types/names, command, item, keybind),
dispatch (10-codes, priorities, blip, expiry), records (preset charges,
BOLO/report types). Live calls are in-memory by design; records persist.

## Credits

- **Author:** Distortionz
- **Framework:** [Qbox Project](https://github.com/Qbox-project)

## License

MIT — see [LICENSE](LICENSE).
