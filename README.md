<p align="center">
  <img src="assets/skins/purple-noodle/frames/01_idle_01.png" width="190" alt="VS Code Pet — Purple Noodle skin">
</p>

<h1 align="center">VS Code Pet</h1>

<p align="center">
  <strong>A Ronaldo-inspired animated control surface for Claude Code and Codex inside VS Code.</strong>
</p>

<p align="center">
  Five fan-art eras, expressive low-frame animation, system-aware celebrations, and a guarded one-click AI prompt bridge — all running locally on Windows.
</p>

<p align="center">
  <img alt="Windows" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows11&logoColor=white">
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white">
  <img alt="UI engine" src="https://img.shields.io/badge/UI-WPF-6A5ACD">
  <img alt="VS Code" src="https://img.shields.io/badge/VS%20Code-Claude%20%2B%20Codex-23A8F2?logo=visualstudiocode&logoColor=white">
  <img alt="Animations" src="https://img.shields.io/badge/animation%20frames-125-F4B942">
</p>

---

## The character, across five eras

<table align="center">
  <tr>
    <td align="center"><img src="assets/skins/purple-noodle/frames/01_idle_01.png" width="120" alt="Purple Noodle"><br><strong>Purple Noodle</strong></td>
    <td align="center"><img src="assets/skins/young-ronaldo/frames/01_idle_01.png" width="120" alt="Young Ronaldo"><br><strong>Young Ronaldo</strong></td>
    <td align="center"><img src="assets/skins/juventus-half/frames/01_idle_01.png" width="120" alt="Juventus Half and Half"><br><strong>Juventus Half &amp; Half</strong></td>
    <td align="center"><img src="assets/skins/portugal-euro/frames/01_idle_01.png" width="120" alt="Portugal Euro Red"><br><strong>Portugal Euro Red</strong></td>
    <td align="center"><img src="assets/skins/white-gold/frames/01_idle_01.png" width="120" alt="White and Gold"><br><strong>White &amp; Gold</strong></td>
  </tr>
</table>

Press global **7** or **Numpad 7** to move between all five skins. Every era has its own hair, face, kit, color treatment, and the same complete 25-frame motion system.

## Experience at a glance

| Interaction | Result |
| --- | --- |
| **Single-click the pet with a verified Claude or Codex input focused** | Submit the prompt and play Point → Ground → SIU |
| **Single-click while VS Code is not active** | Play SIU only; no key is sent to another app |
| **Single-click over a non-AI VS Code control** | Block submission and show **FOCUS CLAUDE OR CODEX** |
| **Double-click** | Play the shirt-rip celebration and open VS Code only if it is not already running |
| **Hover while resting** | Play one restrained standing sway, then become still again |
| **Left-drag** | Reposition the pet anywhere on the desktop |
| **Right-click** | Open the English action menu, including explicit Claude and Codex submit actions |
| **7 / Numpad 7** | Cycle to the next character era while passing the key through |
| **Enter** | Play SIU while allowing Enter to continue to the active app |
| **Backspace** | Play the bicycle kick while allowing Backspace to continue to the active app |

The window is always-on-top but deliberately **non-activating**. Clicking the character does not steal keyboard focus from the prompt you are writing in VS Code.

## Guarded AI prompt bridge

VS Code Pet turns the character into a small, focus-preserving submit control for the installed **Claude Code** and **Codex** VS Code experiences. It uses Windows UI Automation to inspect the control that already owns keyboard focus; it does not guess from screen coordinates.

```mermaid
flowchart LR
    A["Click the pet"] --> B{"VS Code active?"}
    B -- No --> C["SIU only"]
    B -- Yes --> D["Inspect focused UI control"]
    D --> E{"Claude or Codex input?"}
    E -- No --> F["Block and show focus guidance"]
    E -- Yes --> G{"Permission or confirmation control?"}
    G -- Yes --> H["Block the submission"]
    G -- No --> I["Send Enter or Ctrl+Enter"]
    I --> J["Show SENT status and play SIU"]
```

### What the bridge verifies

- VS Code is the active application, or was the immediately preceding foreground window before the non-activating pet click.
- The focused accessibility element belongs to a recognized Claude Code or Codex surface.
- The focused element is an editable prompt surface, not a button, menu item, checkbox, link, dialog, or window.
- No permission, approval, command-run, accept/reject, or confirmation language appears in the focused control hierarchy.
- The appropriate send shortcut is used from the current VS Code user settings.

The integration currently respects:

- `chatgpt.composerEnterBehavior`
- `claudeCode.useTerminal`
- `claudeCode.useCtrlEnterToSend`

Successful actions report **SENT / CLAUDE** or **SENT / CODEX** in the status bubble. Unsafe or ambiguous states report a clear English message such as **FOCUS CLAUDE OR CODEX** or **CONFIRMATION BLOCKED**.

> The bridge is intentionally manual. It never submits on a timer, never stores or transmits prompt content, and never turns a permission dialog into an automatic approval.

### Claude confirmation state

When a visible Claude Code permission or command confirmation takes focus, the pet enters a dedicated action-required state:

- Calma plays immediately, then repeats at a restrained interval while Claude is waiting;
- a persistent warm-toned status card displays **CLAUDE NEEDS CONFIRMATION** and **Review the request in VS Code**;
- the card remains visible when another app briefly receives focus and clears only after the request disappears or VS Code closes;
- clicking the pet refreshes the Calma response but never approves the request automatically.

The status card uses a compact information hierarchy — provider label, action title, supporting instruction, state icon, accent rail, and shadow — while remaining non-interactive so it never steals the prompt focus.

## System-aware celebrations

The pet listens to a small set of local Windows state changes and maps them to recognizable actions.

| Windows or app event | Character action |
| --- | --- |
| Pet starts, or Codex/ChatGPT opens while the pet is running | Five-frame bicycle kick |
| Claude Code waits for a permission or command confirmation | Persistent action-required card with repeating Calma |
| Audio becomes muted | Five-frame bicycle kick |
| Volume decreases without mute | Calma, with palms moving downward |
| Volume increases | Eyes closed, hands over chest: the meditation celebration |
| Built-in display brightness reaches 100% from below | Five-frame shirt-rip power celebration |

Brightness monitoring uses Windows `WmiMonitorBrightness`. Some external monitors do not expose that interface; the rest of the pet continues to work normally when brightness data is unavailable.

## Animation direction

This is a low-frame character system by design, not a slideshow of unrelated pictures. Each skin supplies **25 transparent PNG frames** across idle, SIU, bicycle kick, meditation, calma, and shirt-rip sequences. WPF adds the motion language between those drawings:

- anticipation before large actions;
- eased translation, scale, and rotation;
- landing squash and recovery after the bicycle kick;
- a small hover-only idle sway instead of constant visual noise;
- a shared floor line and stable character proportions across every skin.

Generated near-white backgrounds and enclosed white pockets — including the gaps around arms, shirts, and the bicycle-kick landing pose — are converted to real alpha and edge-decontaminated by `tools/build_animation_assets.py`.

## Start and install

The project is designed for Windows 10 or 11 with Windows PowerShell 5.1 or newer.

1. Double-click **`Start-CR7-Pet.vbs`** for a clean launch without a console window.
2. Run **`Install-Desktop-Shortcut.ps1`** once to create the English desktop shortcut and add a current-user sign-in startup shortcut.
3. Use the character normally; right-click it at any time and choose **Exit VS Code Pet** to close it.

The installer uses the current user's Startup folder, so it does not require a machine-wide service. VS Code Pet also keeps a single running instance to avoid stacked pets and duplicated global key reactions.

## Configuration

Runtime behavior can be tuned in `config.json` without changing the animation assets.

| Setting | Default | Purpose |
| --- | ---: | --- |
| `windowWidth` | `320` | Pet window width in pixels |
| `windowHeight` | `458` | Pet window height in pixels |
| `animationTickMs` | `30` | WPF animation update interval |
| `volumePollMs` | `400` | Audio-state polling interval |
| `brightnessPollMs` | `1200` | Display-brightness polling interval |
| `codexPollMs` | `1600` | VS Code/Codex process-state polling interval |
| `triggerOnCodexOpen` | `true` | Play the opening bicycle kick when the AI app appears |
| `alwaysOnTop` | `true` | Keep the companion above regular windows |

## Right-click action menu

The context menu provides direct access to the complete motion and integration set:

- Submit Focused AI Prompt
- Submit to Focused Claude
- Submit to Focused Codex
- Point > Ground > SIU
- Bicycle Kick
- Sleeping Meditation
- Calma
- Shirt-Rip Power
- Next Skin
- Open VS Code + Shirt-Rip
- Always on Top
- Reset Position
- Exit VS Code Pet

Provider-specific submit commands still use the same focus and confirmation guards. Choosing a provider does not bypass safety validation.

## Verification and demo

Run the built-in validation before packaging or changing assets:

```powershell
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File .\CR7Pet.ps1 -SelfTest
```

The self-test validates:

- the WPF per-pixel-alpha engine and English UI;
- all five skins and all 125 animation frames;
- transparent image corners and missing-frame errors;
- global 7, Enter, and Backspace hooks;
- the guarded VS Code submit bridge;
- Core Audio access and WMI brightness support.

For a visual pass through every animation, use:

```powershell
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File .\CR7Pet.ps1 -DebugWindow -Demo
```

Runtime diagnostics are written to `logs/cr7-pet.log`. Logs and local state are excluded from Git.

## Project map

```text
VS Code Pet/
├── CR7Pet.ps1                  # WPF runtime, animation engine, hooks, and AI bridge
├── config.json                 # Window, timing, polling, and startup behavior
├── Start-CR7-Pet.vbs           # Console-free launcher
├── Install-Desktop-Shortcut.ps1
├── ASSET_PROMPTS.md            # Reproducible fan-art direction
├── assets/
│   ├── skin.json               # Active skin state
│   └── skins/                  # Five 25-frame character sets
└── tools/
    ├── build_animation_assets.py
    └── slice_sprites.py
```

## Local-first privacy and safety

- The runtime makes no external API calls and requires no Claude, Codex, or OpenAI API key.
- It inspects accessibility labels and control IDs only for focus validation; it does not store or transmit prompt text.
- Global 7, Enter, and Backspace hooks trigger animation only and pass the original key through.
- AI submission is allowed only after provider, focus, editable-control, and confirmation checks pass.
- All animations, accessibility inspection, system-state polling, settings reads, and logs stay on the local machine.

## Fan-art notice

The kits use generic fan-art silhouettes without club crests, sponsors, manufacturer marks, or competition badges. This is an unofficial local fan-art project and is not endorsed by Cristiano Ronaldo, any club, sponsor, competition, Anthropic, Microsoft, or OpenAI.
