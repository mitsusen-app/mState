---
name: mstate
description: Reads live Mac system metrics through mState, including CPU, GPU, memory, network, battery, power, and temperature. Use when the user asks why their Mac is slow, hot, or loud, whether a task is using the CPU or GPU, how much memory or bandwidth is in use, or what the battery or power draw is doing.
---

# mState

Get one reading from the first source that works:

1. The `get_metrics` tool on the `mstate` MCP server.
2. The command line, which takes about a second:

   ```bash
   /Applications/mState.app/Contents/MacOS/mState --json
   ```

If neither is available, tell the user that mState isn't installed or set up, and point them to https://github.com/mitsusen-app/mState.

If `get_metrics` says agent access is off, ask the user to turn on **Agent access** at the bottom of the mState panel. Don't change that setting yourself. Don't use `--json` to get around it unless the user agrees.

## Reading the numbers

Each reading is one moment, so take a few readings about 5 seconds apart before calling something sustained.

- **Missing fields**: this Mac doesn't expose that value. Say it's unavailable instead of treating it as zero.
- **CPU**: `usage_percent` is the average across all cores, so one maxed-out core can still look low. Check `per_core_percent` and `clusters`.
- **GPU**: `usage_percent` is busy time, not workload. A GPU at a low clock can show a high percentage while drawing about 1 W, so compare it with `power.gpu_watts`.
- **Temperature**: mState shows CPU and GPU temperatures in orange from 90 °C and red from 100 °C. Apple Silicon can run hot under load without a fault.
- **Memory**: judge by `pressure`, not `used_percent`. macOS uses free memory for caches and compression, so a high percentage alone isn't a problem.
- **Network**: rates cover Ethernet and Wi-Fi interfaces (`en*`).
- **Battery**: `watts` is positive while charging and negative while draining. `charging` can be false on AC when a heavy load draws more than the adapter supplies.
- **Power**: `system_watts` is the whole machine. `ane_watts` is often missing because that counter needs root on some Macs.

mState doesn't report which process causes a load. To find one, use `top -l 2 -o cpu -n 10`, and say that you're doing so.
