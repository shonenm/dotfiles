# SketchyBar + AeroSpace Integration

A system that integrates the macOS tiling window manager AeroSpace with the status bar SketchyBar to visualize workspaces and applications.

## Overview

- **Workspace Display**: Dynamically shows only active workspaces
- **App Display**: Shows apps in the focused workspace as icons
- **Mode Display**: Visualizes AeroSpace binding modes (Main/Service/Pomodoro)
- **Pomodoro Timer**: Keyboard-only operable timer feature
- **Layout Popup**: Popup display showing all workspaces
- **Notification Badges**: Displays Claude Code notifications per workspace

## UI Layout

```
┌────────────────────────────────────────────────────────────────┐
│ [MODE] │ [1] [2●] [T] │ [App] [App] [App]                     │
│  MAIN  │ Workspaces   │ Apps in workspace                     │
└────────────────────────────────────────────────────────────────┘
   Left side
```

| Element | Description |
|---------|-------------|
| **Mode Indicator** | Shows current mode (MAIN/SERVICE/POMO) with icon and color |
| **Workspaces** | Shows only non-empty workspaces, highlights focused one, includes notification badges |
| **Apps** | Shows apps in current workspace as icons |

## Mode Display

AeroSpace has 3 binding modes:

### Main Mode (Normal)

```
┌──────────────┐
│ 󰍹  MAIN     │  ← Accent color (blue)
└──────────────┘
```

- Normal operation mode
- Window operations and workspace navigation available

### Service Mode (Settings)

```
┌──────────────┐
│ ⚙  SERVICE  │  ← Warning color (orange)
└──────────────┘
```

When entering Service Mode, the entire UI changes to orange:
- Workspace borders
- App borders
- Focused highlight
- Window borders (JankyBorders)

Additionally, keybinding help is displayed on the right:

```
┌─────────────────────────────────────────────────────────────┐
│ esc:exit  a:reload  r:reset  f:float  c:clear-badges  ⌫:close-others │
└─────────────────────────────────────────────────────────────┘
```

### Pomodoro Mode (Timer)

```
┌──────────────┐
│ 󰔛  POMO     │  ← Pomodoro color (green)
└──────────────┘
```

When entering Pomodoro Mode, the entire UI changes to green.
Operate the Pomodoro timer using only the keyboard.

Keybinding help is displayed on the right:

```
┌────────────────────────────────────────────────────────────────┐
│ esc:exit  s:start/pause  r:reset  1:5m 2:15m 3:25m 4:45m 5:60m │
└────────────────────────────────────────────────────────────────┘
```

## Workspace Display

```
┌─────────────────────────┐
│ [1]  [2]  [T]  [C]     │
│      ↑                  │
│   Focused              │
└─────────────────────────┘
```

- Shows **only non-empty workspaces** (empty ones hidden)
- Focused workspace is **highlighted with mode color**
- **Click to switch workspaces**
- **Badge shows notification count** when notifications exist

### Notification Badges

```
┌───────────┐
│ [1] ●2    │  ← 2 notifications on workspace 1
└───────────┘
```

Notifications from Claude Code (permission, idle, complete) are displayed as badges per workspace.

## App Display

```
┌─────────────────────────────────┐
│ [󰈹]  [󰨞]  [󰙯]  [  Ghostty  ] │
│  ↑    ↑    ↑         ↑         │
│ Firefox VS Code Discord  Focused │
└─────────────────────────────────┘
```

- Shows **all apps in current workspace as icons**
- Focused app shows **icon + label + highlight**
- Icon mapping supports over 1000 apps

## Layout Popup

Press `alt+shift+/` to show a popup of all workspaces:

```
┌────────────────────────────────────┐
│ 󰄯  1  │  Firefox  VS Code         │  ← Focused
│ 󰄰  2  │  Slack  Discord           │
│ 󰄰  T  │  Ghostty                  │
│ 󰄰  C  │  Cron                     │
└────────────────────────────────────┘
```

- **Shows all workspaces and their apps**
- Focused shown as 󰄯, others as 󰄰
- **Click to switch workspaces**
- **Toggle behavior** (press again to close)

## Key Bindings

### Main Mode

| Key | Action |
|-----|--------|
| `alt+1-9` | Move to workspace 1-9 |
| `alt+t/c/f/g/b/v` | Move to workspace T/C/F/G/B/V |
| `alt+h/j/k/l` | Move focus (left/down/up/right) |
| `alt+shift+h/j/k/l` | Move window |
| `alt+shift+1-9` | Move window to workspace |
| `alt+/` | Switch layout (tiles/accordion) |
| `alt+shift+/` | Show layout popup |
| `alt+s` | Toggle SketchyBar visibility |
| `alt+tab` | Return to previous workspace |
| `alt+shift+;` | Enter Service Mode |
| `alt+shift+p` | Enter Pomodoro Mode |
| `ctrl+alt+←/→` | Move between non-empty workspaces |

### Service Mode

| Key | Action |
|-----|--------|
| `esc` | Return to Main Mode (reload config) |
| `a` | Reload AeroSpace config |
| `r` | Reset layout |
| `f` | Toggle floating/tiling |
| `c` | Clear all notification badges |
| `backspace` | Close all other windows |

### Pomodoro Mode

| Key | Action |
|-----|--------|
| `esc` | Return to Main Mode |
| `s` | Start/pause timer |
| `r` | Reset timer |
| `1` | Set to 5 minutes |
| `2` | Set to 15 minutes |
| `3` | Set to 25 minutes |
| `4` | Set to 45 minutes |
| `5` | Set to 60 minutes |
| `alt+shift+/` | Show layout popup |

## Configuration Files

### SketchyBar

```
~/.config/sketchybar/
├── sketchybarrc          # Main configuration
└── plugins/
    ├── workspaces.sh     # Workspace display
    ├── workspace_apps.sh # App display
    ├── mode.sh           # Mode display
    ├── aerospace.sh      # Workspace focus
    ├── show_layout.sh    # Layout popup
    ├── claude.sh         # Notification badges
    ├── accent_color.sh   # Color definitions
    ├── icon_map.sh       # App icon mapping
    ├── toggle_bar.sh     # Bar visibility toggle
    └── pomodoro.sh       # Pomodoro timer display
```

### AeroSpace

```
~/.config/aerospace/
└── aerospace.toml        # Window manager configuration
```

## Event Flow

### On Workspace Change

```
AeroSpace (workspace change)
    ↓ exec-on-workspace-change
sketchybar --trigger aerospace_workspace_change
    ↓
workspaces.sh  → Update workspace list
workspace_apps.sh → Update app list
claude.sh → Update badges
```

### On Mode Change

```
AeroSpace (alt+shift+;)
    ↓ on-mode-changed
sketchybar --trigger aerospace_mode_change
    ↓
mode.sh → Update mode display
        → Change all UI colors
        → Show/hide keybinding help
        → Change JankyBorders color
```

### On Focus Change

```
macOS (app focus change)
    ↓ front_app_switched
workspace_apps.sh → Highlight focused app
claude.sh → Clear notifications if editor/terminal
```

## Color Scheme

| Usage | Color | Value |
|-------|-------|-------|
| Accent color (Main Mode) | Blue | `0xff0055bb` |
| Service color (Service Mode) | Orange | `0xffff6600` |
| Pomodoro color (Pomodoro Mode) | Green | `0xff28a745` |
| Background | Transparent/Dark | `0x00000000` / `0xff1e1f29` |
| Text | White | `0xffffffff` |

## Performance Optimization

- **State file-based differential updates**
  - `/tmp/sketchybar_workspaces_state` - Workspace state
  - `/tmp/sketchybar_apps_state` - App state
  - Skip UI rebuild if no changes

- **Dynamic item management**
  - Show only non-empty workspaces
  - Update app list only on workspace change

## Troubleshooting

### SketchyBar Not Displaying

```bash
# Restart SketchyBar
brew services restart sketchybar

# Reload configuration
sketchybar --reload
```

### Workspaces Not Updating

```bash
# Check AeroSpace state
aerospace list-workspaces --all

# Manual trigger
sketchybar --trigger aerospace_workspace_change
```

### Icons Not Displaying

```bash
# Check if sketchybar-app-font is installed
ls ~/Library/Fonts/ | grep -i sketchybar
```

### Mode Changes Not Reflected

```bash
# Reload AeroSpace config
aerospace reload-config

# Manual trigger
sketchybar --trigger aerospace_mode_change
```
