# Porting Agent Babysitter to Windows

Written 2026-07-23 against v0.11.3. Strategy: **prep now, port later** — do the
refactors that are worth doing on macOS anyway, and leave the port itself as a
decided, costed piece of work rather than a vague intention.

## Verdict

The engine ports. The app does not.

| | Lines | Files | Assessment |
|---|---:|---:|---|
| `AgentBabysitterCore` | 7,225 | 56 | **50 of 56 files need no platform work at all** — pure Foundation |
| `AgentBabysitterCore` tests | 6,440 | 44 | Port with the core; they inject fakes, not the OS |
| `App` | 5,344 | 21 | **Rewrite.** SwiftUI ×10, AppKit ×8, Charts, Carbon — none exist on Windows |

So roughly 58% of the codebase (core + tests) is a port, and the 5,344-line UI
layer is a from-scratch build against whatever Windows UI stack gets chosen.
That ratio is the whole argument for having kept agent logic out of the views.

## Already done (this is the prep)

**`PlatformPaths.swift`** — every OS-specific location now resolves in one
file. Before, thirteen files hardcoded `~/Library/Application Support/…` and
`homeDirectoryForCurrentUser`. Three shapes:

- **dot-directories** (`~/.claude`, `~/.codex`, `~/.hermes`) — agents use the
  same layout on every platform, only "home" differs. Zero-cost port.
- **application support** — genuinely per-OS: macOS `~/Library/Application
  Support`, Windows `%APPDATA%`, Linux `$XDG_DATA_HOME`. The Windows and Linux
  branches are already written.
- **iCloud Drive** — `URL?`, because there is no equivalent off Apple
  platforms. `StatsSync` already treated a missing folder as "no syncing", so
  nil needs no new handling.

`PlatformPathsTests` pins the macOS answers to the exact literals the adapters
used before the indirection — both the helper and each adapter's default root.
A port can add branches; it cannot silently move a macOS path.

## The six files that need real work

Everything platform-bound is in these. Nothing else in core imports anything
Apple-only.

### 1. `Process/ProcessWatcher.swift` — the hard one

Shells out to `/bin/ps` twice (`pid=,comm=` and `pid=,args=`) to find agent
pids, then one `/usr/sbin/lsof -d cwd` pass to resolve every pid's working
directory.

**Good news:** the seam already exists. `ProcessScanning` is a protocol, and
tests already inject a fake. A Windows port is a new conformer —
`WindowsProcessScanner` — and *nothing else in core changes*. The adapters'
`agentPIDs(psComm:psArgs:)` parsing can be fed synthesized `ps`-shaped strings,
so even the per-adapter matching logic survives untouched.

- pid + executable + full command line → `CreateToolhelp32Snapshot`, or WMI
  `Win32_Process` (which hands you `CommandLine` and `ExecutablePath`
  directly, closest to `ps -o args=`).
- **working directory → this is the risk.** Windows has no `lsof`. Another
  process's cwd lives in its PEB and needs `NtQueryInformationProcess` +
  `ReadProcessMemory` with `PROCESS_VM_READ`. Same-user processes are usually
  readable without elevation, but this is undocumented-ish territory, it is
  bitness-sensitive (a 32-bit reader cannot read a 64-bit PEB), and AV/EDR
  software treats cross-process memory reads as suspicious.

cwd is not optional: it is how sessions are matched to processes, and how
`claimsProcess(cwd:)` stops OpenClaw's SDK surface from stealing every plain
`claude`. **Prototype this before committing to the port** — if cwd proves
unreliable, matching has to fall back to command-line arguments alone, which
changes behaviour and needs its own design.

### 2. `Process/ProcessNetworkSampler.swift`

Runs `/usr/bin/nettop` for per-process network bytes — a liveness signal for
agents whose files don't record turn completion. Windows equivalent is the IP
Helper API (`GetPerTcpConnectionEStats`) or ETW, both substantially more work
than parsing nettop.

This is the **best candidate to ship without**. It is already optional
(`liveNetworkBytes(pid:)` returns `nil` by default, and `usesNetworkActivity`
is opt-in per adapter). Return `nil` on Windows for v1 and the app degrades to
file-activity heuristics — exactly what it does today for adapters that don't
opt in.

### 3. `Transcript/FSEventsWatcher.swift` (`import CoreServices`)

FSEvents recursive directory watching. Windows has a clean direct analogue:
`ReadDirectoryChangesW` with `bWatchSubtree = TRUE`. Comparable coalescing
concerns (both fire bursts; the existing debounce logic should carry over).

### 4. `Process/ProcessAncestry.swift` (`import Darwin`)

Walks the pid→parent chain (used to focus the terminal window that owns a
session). Windows: `Process32First/Next` gives `th32ParentProcessID`, so the
walk itself is a direct translation. "Focus the owning window" is a different
problem — `AttachThreadInput` + `SetForegroundWindow`, with Windows' foreground
lock rules to fight.

### 5. `BabysitterLog.swift` (`import os`)

`os.Logger`. Replace with a file log or ETW. Trivial, isolated.

### 6. SQLite (4 files: Cursor, Antigravity, Hermes, Manus adapters)

`import SQLite3` works because macOS ships libsqlite3. Windows does not — the
port must vendor SQLite as a C target in `Package.swift`. Mechanical, but it
is a build-system change, not a code change, and it is easy to forget until
link time.

The WAL-copy dance (copy `.db` + `-wal` + `-shm`, open read-only) is portable
as written, though Windows' mandatory file locking is stricter than macOS' —
copying a database another process holds open may fail where macOS succeeds.
Worth testing early against a running Cursor.

## The app layer

No SwiftUI on Windows, so the 5,344-line UI is a rewrite regardless. Options,
in the order I'd consider them:

1. **Swift core as a library + native Windows UI (WinUI 3 / C#).** The core
   already has no UI dependencies. This is the pragmatic choice: the hard,
   well-tested logic stays Swift and shared; the UI uses a mature, documented
   stack. Cost is a language boundary to design and maintain.
2. **All-Swift with WinRT bindings** (`swift-winrt`). Real precedent exists —
   The Browser Company shipped Arc for Windows this way — but it is a much
   smaller ecosystem, and you'd be an early adopter with the debugging burden
   that implies.
3. **Rewrite wholesale in C#/.NET.** Discards the 7,225 tested lines that
   already work. Only worth it if the Swift-on-Windows toolchain proves
   painful in practice.

Platform pieces the app layer needs, none of which have Swift-on-Windows
answers today:

| macOS | Windows equivalent |
|---|---|
| `NSStatusItem` menu bar extra | System tray icon + flyout window |
| `UserNotifications` | WinRT toast notifications |
| `ServiceManagement` (login item) | `Run` registry key, Startup folder, or Task Scheduler |
| `Carbon.HIToolbox` global hotkey | `RegisterHotKey` |
| Keychain (license storage) | Credential Manager / DPAPI |
| Swift `Charts` | No equivalent — pick a charting library for the chosen UI stack |
| Sparkle (auto-update) | WinSparkle is the direct analogue; MSIX has its own updater |

## Which agents even exist on Windows

The port's value depends entirely on this — a perfect port that monitors
nothing is worthless. **Verify each before starting**, on a real Windows box:

- **dot-directory agents** (Claude Code, Codex, Gemini) — same `~/.foo` layout,
  so `PlatformPaths.homeDirectory` already resolves them. Highest confidence.
- **Electron agents** (Cursor, Antigravity) — put `User/globalStorage` under
  `%APPDATA%`, which `PlatformPaths.applicationSupport` already returns. Verify
  the schema inside `state.vscdb` matches; it should, same app.
- **Hermes, Manus, OpenClaw** — availability unconfirmed. Check before
  budgeting any work for them.

## Suggested order

1. Confirm the agent inventory above on a real Windows machine. If only two
   agents exist there, the port is a much smaller product.
2. Spike `WindowsProcessScanner` — specifically **cwd resolution**. This is the
   one item that could invalidate the design, so it goes first.
3. Get core + its 6,440 lines of tests building and green on Windows (vendored
   SQLite, `os.Logger` replaced, `ProcessNetworkSampler` returning nil).
4. `ReadDirectoryChangesW` watcher, then live-dogfood the core headless —
   sessions discovered, tokens counted, cost priced — before any UI exists.
5. Only then pick the UI stack and build it.

Steps 1–2 are where the real uncertainty lives. Everything after them is
known-shaped work.
