# mState

[English](README.md) | **繁體中文**

Mac 選單列上的小型系統監控工具，可查看 CPU、GPU、記憶體、各核心負載、網路、電池、功耗，以及 CPU／GPU 溫度。

## 安裝

到 [Releases](https://github.com/mitsusen-app/mState/releases/latest) 下載 `mState-<版本>.dmg`，再把 mState 拖到「應用程式」資料夾。

mState 目前還沒有 Apple Developer ID 簽章，所以 macOS 會擋下第一次開啟。要允許開啟，請到「系統設定」→「隱私權與安全性」選擇「強制打開」，或執行：

```bash
xattr -dr com.apple.quarantine /Applications/mState.app
```

需要 macOS 14 或更新版本。

## 用 AI agent 安裝

把下面這段貼給能在你的 Mac 上執行 shell 指令的 coding agent：

```text
請依照以下檔案中「給 agent 的步驟」一節，在這台 Mac 上安裝 mState：
https://raw.githubusercontent.com/mitsusen-app/mState/main/README.zh-TW.md
```

### 給 agent 的步驟

1. 執行 `sw_vers -productVersion`，版本低於 14 就停止。
2. 告訴使用者：mState 沒有 Apple Developer ID 簽章，並透過私有 API 讀取感測器。使用者同意後才繼續。
3. 安裝最新版本：

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

4. 啟動並確認正在執行：

   ```bash
   open /Applications/mState.app
   pgrep -x mState
   ```

5. 請使用者查看選單列右側。mState 沒有 Dock 圖示；選單列太滿時，圖示可能被瀏海遮住。

不要使用 `sudo`。如果無法複製到 `/Applications`，請詢問使用者如何處理。如果 macOS 擋下啟動，請先徵得使用者同意，再用[安裝](#安裝)一節的指令移除 quarantine 屬性。

## 搭配 AI agent 使用

Agent 可以讀取 mState 的數據，但無法透過它改動任何東西。MCP 和 Skill 都是選用功能，預設都沒有設定。

### MCP 伺服器

1. 在 mState 面板底部開啟 **Agent access**。它預設關閉，關閉時 `get_metrics` 會回傳錯誤。開關會立即生效，想暫停存取時直接關掉即可。
2. 把伺服器加入 agent 客戶端。Claude Code 的做法：

   ```bash
   claude mcp add mstate -- /Applications/mState.app/Contents/MacOS/mState --mcp
   ```

   使用 JSON 設定檔的客戶端：

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

要從 Claude Code 移除，請執行 `claude mcp remove mstate`。

伺服器只有一個工具 `get_metrics`，回傳的數據與 `--json` 相同。它透過 stdio 運作，不開任何網路埠，也不需要先開啟 app。支援 MCP 2026-07-28，以及仍在使用 `initialize` 的客戶端。

### Skill

[mState Skill](skills/mstate/SKILL.md) 會教 agent 何時該查看數據，以及如何解讀。安裝到 Claude Code：

```bash
mkdir -p ~/.claude/skills/mstate
curl -fsSL https://raw.githubusercontent.com/mitsusen-app/mState/main/skills/mstate/SKILL.md -o ~/.claude/skills/mstate/SKILL.md
```

要移除時，刪除 `~/.claude/skills/mstate` 即可。Skill 會優先使用已設定的 MCP 伺服器，沒有的話就改用命令列。

### 命令列

```bash
/Applications/mState.app/Contents/MacOS/mState --json
```

以 JSON 輸出一筆讀數，大約需要 1 秒，不受 Agent access 開關影響。

### 隱私

讀數只包含晶片名稱和整台電腦的總量，不含程序名稱、檔案路徑、網路位址或使用者名稱。

Agent access 只控制 MCP 伺服器，並不是安全邊界：以你的帳號執行的任何程式，都能執行 `--json` 或更改這個設定。

## 相容性

| Mac | 組建 | 實機測試 |
|---|---|---|
| M5 Max | universal | 有 |
| M3 Ultra | universal | 有 |
| Intel | universal | 有。GPU 和溫度走 Intel 專用路徑 |
| M1、M2、M4、其他 M3 機型 | universal | 沒有。感測器鍵值取自 [Stats](https://github.com/exelban/stats) 專案 |
| M6 | universal | 沒有。先用 M5 的鍵值，再掃描感測器 |

如果你的 Mac 讀數看起來不對，歡迎開 issue 並附上 `swift run sensor-probe` 的輸出。

只有 Mac 提供資料時，才會顯示各元件的功耗：

- **Intel**：沒有功耗卡片。
- **M5 Max、macOS 27**：只有系統和 GPU 功耗。CPU、ANE 和 DRAM 計數器沒有 root 權限就不會更新，所以顯示「—」。
- **M1–M4**：應該會顯示 CPU、ANE 和 DRAM，但尚未測試。app 偵測到計數器凍結時會隱藏這些項目。

## 從原始碼建置

```bash
scripts/bundle.sh --open        # universal release 組建 → build/mState.app，然後啟動
scripts/bundle.sh --dmg         # 另外產生 dist/mState-<版本>.dmg
swift run mState                # 不打包，直接以 debug 模式執行
swift run mState --json         # 以 JSON 輸出一筆讀數
swift run mState --mcp          # 用 stdio 執行 MCP 伺服器
swift run sensor-probe          # 列出所有 HID/SMC 溫度感測器
swift run sensor-probe --groups # 依鍵值前綴顯示 SMC 平均值（比較閒置與高負載）
swift run sensor-probe --power 5      # 連續 5 秒顯示 IOReport 能耗通道和換算後的瓦數
swift run sensor-probe --smc-prefix P # 列出所有以 P 開頭的浮點 SMC 鍵值（功耗）
```

只需要 Command Line Tools 就能建置，不用安裝 Xcode。

## 專案結構

| 路徑 | 內容 |
|---|---|
| `Sources/MonitorCore` | 取樣器，不含 UI。每種指標一個類別，都有 `sample()` |
| `Sources/mState` | SwiftUI app：`MenuBarLabel`（狀態列項目）、`PanelView`（彈出面板）、`MetricsStore`（1 秒迴圈與 60 秒歷史）。`Entry` 負責分派 `--json` 和 `--mcp`；`MCPServer` 是 stdio 伺服器 |
| `Sources/sensor-probe` | 用來對應新晶片溫度感測器的命令列工具 |
| `skills/mstate` | 讓 agent 讀取 mState 數據的 Agent Skill |

## 資料來源

| 指標 | 來源 | 私有 API |
|---|---|---|
| CPU | `host_processor_info`；叢集資訊來自 `hw.perflevelN` | 否 |
| GPU | IOAccelerator `PerformanceStatistics` | 否 |
| 記憶體 | `host_statistics64`、`kern.memorystatus_vm_pressure_level` | 否 |
| 網路 | `NET_RT_IFLIST2` 64 位元計數器，只計 `en*` | 否 |
| 電池 | IOPowerSources 與 `AppleSmartBattery` | 否 |
| 溫度 | 依晶片世代對應的 SMC 鍵值（`TemperatureSampler.swift`）；備援為 HID | 是 |
| 系統功耗 | SMC `PSTR` | 是 |
| GPU 功耗 | IOReport「Energy Model」→ `GPU Energy`（來自 GPU 驅動程式） | 是 |
| CPU／ANE／DRAM 功耗 | IOReport「Energy Model」PMGR 通道；**在 M5 Max／macOS 27 上沒有 root 權限時會凍結**，顯示為「—」 | 是 |

因為使用私有 API，mState 無法上架 Mac App Store，也不能在沙盒中執行。

## 不用螢幕錄製的 UI 截圖

```bash
MSTATE_SNAPSHOT=/tmp/shots swift run mState
```

取樣 6 秒後寫出 `menubar.png`、`panel-light.png` 和 `panel-dark.png`，然後結束。

`MSTATE_WINDOW=1` 會改用一般視窗顯示面板，方便測量開啟時的資源用量（例如用 `top -pid`）。目標是面板開啟或關閉時，CPU 用量都約 1–2%。

## 授權

MIT。詳見 [LICENSE](LICENSE)。
