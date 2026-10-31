# mState

A small menu bar system monitor for Mac: CPU, GPU, memory, per-core load, network, battery, power, and CPU/GPU temperature.

## Install

Download `mState-<version>.dmg` from Releases and drag mState to Applications.

mState isn't signed with an Apple Developer ID yet, so macOS blocks the first launch. To allow it, open System Settings → Privacy & Security and choose Open Anyway, or run:

```bash
xattr -dr com.apple.quarantine /Applications/mState.app
```

Needs macOS 14 or later.

## Compatibility

| Mac | Build | Tested on hardware |
|---|---|---|
| M5 Max | universal | Yes |
| M1, M2, M3, M4 | universal | No. Sensor keys come from the [Stats](https://github.com/exelban/stats) project |
| M6 | universal | No. Uses M5 keys, then scans for sensors |
| Intel | universal | No. CPU, memory, network, and battery use the same code; GPU and temperature use Intel paths |

If a reading looks wrong on your Mac, please open an issue with the output of `swift run sensor-probe`.

Power is per-component only where the Mac exposes it:

- **Intel**: no power card.
- **M5 Max on macOS 27**: system and GPU power only. CPU, ANE, and DRAM counters don't update without root, so they show "—".
- **M1–M4**: CPU, ANE, and DRAM should appear, but that's untested. The app detects frozen counters and hides them.

## Build from source

```bash
scripts/bundle.sh --open        # universal release build → build/mState.app, then launch it
scripts/bundle.sh --dmg         # also write dist/mState-<version>.dmg
swift run mState                # debug run without bundling
swift run sensor-probe          # list every HID/SMC temperature sensor
swift run sensor-probe --groups # SMC averages per key prefix (run idle vs. under load)
swift run sensor-probe --power 5      # IOReport energy channels + parsed watts for 5 s
swift run sensor-probe --smc-prefix P # every float SMC key starting with P (power)
```

Builds with the Command Line Tools alone; Xcode isn't required.

## Layout

| Path | What |
|---|---|
| `Sources/MonitorCore` | Samplers, no UI. One class per metric, each with `sample()` |
| `Sources/mState` | SwiftUI app: `MenuBarLabel` (status item), `PanelView` (popover), `MetricsStore` (1 s loop + 60 s history) |
| `Sources/sensor-probe` | CLI for mapping temperature sensors on a new chip |

## Data sources

| Metric | Source | Private API |
|---|---|---|
| CPU | `host_processor_info`; clusters from `hw.perflevelN` | no |
| GPU | IOAccelerator `PerformanceStatistics` | no |
| Memory | `host_statistics64`, `kern.memorystatus_vm_pressure_level` | no |
| Network | `NET_RT_IFLIST2` 64-bit counters, `en*` only | no |
| Battery | IOPowerSources + `AppleSmartBattery` | no |
| Temperature | SMC keys per chip generation (`TemperatureSampler.swift`); HID fallback | yes |
| System power | SMC `PSTR` | yes |
| GPU power | IOReport "Energy Model" → `GPU Energy` (from the GPU driver) | yes |
| CPU / ANE / DRAM power | IOReport "Energy Model" PMGR channels; **frozen without root on M5 Max / macOS 27**, shown as "—" | yes |

The private APIs mean this can't ship on the Mac App Store and can't be sandboxed.

## UI snapshots without screen recording

```bash
MSTATE_SNAPSHOT=/tmp/shots swift run mState
```

Samples for 6 seconds, writes `menubar.png`, `panel-light.png`, and `panel-dark.png`, then quits.

`MSTATE_WINDOW=1` shows the panel in a regular window instead, to measure its cost while open
(e.g. with `top -pid`). Target: about 1–2% CPU with the panel open or closed.

## License

MIT. See [LICENSE](LICENSE).
