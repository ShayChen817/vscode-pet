# CR7 Codex Pet

A polished animated Windows desktop pet with five Ronaldo-inspired fan-art skins, 25 real animation frames per skin, WPF per-pixel transparency, and system-aware celebrations.

## Start

- Double-click `Start-CR7-Pet.vbs` for a clean launch without a console window.
- Run `Install-Desktop-Shortcut.ps1` once to add the English desktop shortcut and current-user sign-in startup shortcut.
- Drag the character with the left mouse button.
- Move the pointer over the character to play one restrained standing sway; it is completely still otherwise.
- Click without dragging to play Point > Ground > SIU.
- Double-click to play the five-frame shirt-rip celebration and open Visual Studio Code only when it is not already running.
- Right-click for the full English action menu.
- Press global `7` or `Numpad 7` to cycle skins. The key is passed through to the active app.
- Press global `Enter` for SIU and global `Backspace` for the bicycle kick. Both keys continue to the active app.

## Skins

1. Purple Noodle
2. Young Ronaldo
3. Juventus Half & Half
4. Portugal Euro Red
5. White & Gold

Every skin uses the same 25-frame animation rig, timing, floor line, and motion easing.

## Automatic actions

| Trigger | Animation |
| --- | --- |
| Pet startup, or Codex/ChatGPT opens while the pet is running | Five-frame bicycle kick |
| Mute | Five-frame bicycle kick |
| Volume down without mute | Calma palms-down gesture |
| Volume up | Eyes-closed, hands-over-chest sleeping meditation celebration |
| Built-in display brightness reaches 100% from below | Five-frame shirt-rip power celebration |
| Pointer enters the pet while it is resting | One very subtle two-sway standing idle; then a still frame |

Brightness monitoring uses Windows `WmiMonitorBrightness`. Some external monitors do not expose it; all other features continue to work.

## Verification and demo

```powershell
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File .\CR7Pet.ps1 -SelfTest
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File .\CR7Pet.ps1 -DebugWindow -Demo
```

The self-test validates all 125 frames, transparent corners, global `7` / `Enter` / `Backspace` hooks, Core Audio, WMI brightness, UI language, and the WPF engine. Runtime logs are stored in `logs\cr7-pet.log`.

## Design and asset notes

- Five intentional low-frame sequences are combined with WPF scale, rotation, translation, easing, anticipation, landing squash, and recovery motion.
- The generated near-white backgrounds, including enclosed pockets in the bicycle landing and between arms, torso, and shirt, are converted to real alpha and edge-decontaminated by `tools\build_animation_assets.py`.
- Kits are generic fan-art silhouettes with no club crest, sponsor, manufacturer logo, or competition badge.
- The generated-art briefs are recorded in `ASSET_PROMPTS.md`.

This is an unofficial local fan-art project and is not endorsed by the player, any club, sponsor, or competition.
