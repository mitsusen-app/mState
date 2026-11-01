# mState

**English** | [繁體中文](README.zh-TW.md)

A small menu bar system monitor for Mac: CPU, GPU, memory, per-core load, network, battery, power, and CPU/GPU temperature.

## Install

Download `mState-<version>.dmg` from [Releases](https://github.com/mitsusen-app/mState/releases/latest) and drag mState to Applications.

mState isn't signed with an Apple Developer ID yet, so macOS blocks the first launch. To allow it, open System Settings → Privacy & Security and choose Open Anyway, or run:

```bash
xattr -dr com.apple.quarantine /Applications/mState.app
```

Needs macOS 14 or later.

## Install with an AI agent

Paste this into a coding agent that can run shell commands on your Mac:

```text
Install mState on this Mac by following the "Steps for agents" section of
https://raw.githubusercontent.com/mitsusen-app/mState/main/README.md
```

### Steps for agents

1. Run `sw_vers -productVersion` and stop if the version is below 14.
2. Tell the user that mState isn't signed with an Apple Developer ID and reads sensors through private APIs. Continue only if they agree.
3. Install the latest release:

   ```bash
   set -e
   pkill -x mState || true
   WORK=$(mktemp -d)
   URL=$(curl -fsSL https://api.github.com/repos/mitsusen-app/mState/releases/latest | grep -o 'https://[^"]*\.dmg' | head -1)
   curl -fsSL "$URL" -o "$WORK/mState.dmg"
   hdiutil attach -nobrowse -readonly -mountpoint "$WORK/mnt" "$WORK/mState.dmg"
   ditto "$WORK/mnt/mState.app" /Applications/mState.app
   hdiutil detach "$WORK/mnt"
   rm -rf "$WORK"
   ```

4. Start it and confirm that it's running:

   ```bash
   open /Applications/mState.app
   pgrep -x mState
   ```

5. Ask the user to check the right side of the menu bar. The status item has no Dock icon, and it can be hidden behind the notch when the menu bar is full.

Don't use `sudo`. If copying to `/Applications` fails, ask the user what to do. If macOS blocks the launch, ask the user before removing the quarantine attribute with the command in [Install](#install).

## Use with AI agents

Agents can read mState's metrics, but they can't change anything through it. MCP and the Skill are both optional, and nothing is set up by default.

### MCP server

1. Turn on **Agent access** at the bottom of the mState panel. It's off by default, and `get_metrics` returns an error while it's off. The switch applies right away, so you can use it to pause access.
2. Add the server to your agent client. For Claude Code:

   ```bash
   claude mcp add mstate -- /Applications/mState.app/Contents/MacOS/mState --mcp
   ```

   For clients with a JSON config:

   ```json
   {
     "mcpServers": {
       "mstate": {
         "command": "/Applications/mState.app/Contents/MacOS/mState",
         "args": ["--mcp"]
       }
     }
   }
   ```

To remove it from Claude Code, run `claude mcp remove mstate`.

The server has one tool, `get_metrics`, which returns the same data as `--json`. It runs over stdio and opens no network port. The app doesn't need to be running. It works with MCP 2026-07-28 and with clients that still use `initialize`.

### Skill

The [mState Skill](skills/mstate/SKILL.md) teaches an agent when to check the metrics and how to read them. To install it for Claude Code:

```bash
mkdir -p ~/.claude/skills/mstate
curl -fsSL https://raw.githubusercontent.com/mitsusen-app/mState/main/skills/mstate/SKILL.md -o ~/.claude/skills/mstate/SKILL.md
```

To remove it, delete `~/.claude/skills/mstate`. The Skill uses the MCP server if it's set up, and falls back to the command line.

### Command line

```bash
/Applications/mState.app/Contents/MacOS/mState --json
```

Prints one reading as JSON. It takes about a second, and the Agent access setting doesn't apply to it.

### Privacy

Readings contain the chip name and system-wide totals. They don't contain process names, file paths, network addresses, or usernames.

Agent access only controls the MCP server. It isn't a security boundary: any program running under your account can run `--json` or change the setting.

## Compatibility

| Mac | Build | Tested on hardware |
|---|---|---|
| M5 Max | universal | Yes |
| M3 Ultra | universal | Yes |
| Intel | universal | Yes. GPU and temperature use Intel paths |
| M1, M2, M4, other M3 models | universal | No. Sensor keys come from the [Stats](https://github.com/exelban/stats) project |
| M6 | universal | No. Uses M5 keys, then scans for sensors |

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
swift run mState --json         # print one reading as JSON
swift run mState --mcp          # run the MCP server on stdio
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
| `Sources/mState` | SwiftUI app: `MenuBarLabel` (status item), `PanelView` (popover), `MetricsStore` (1 s loop + 60 s history). `Entry` routes `--json` and `--mcp`; `MCPServer` is the stdio server |
| `Sources/sensor-probe` | CLI for mapping temperature sensors on a new chip |
| `skills/mstate` | Agent Skill for reading mState's metrics |

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
