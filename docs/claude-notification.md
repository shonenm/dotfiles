# Claude Code Notification System

A system that visualizes Claude Code events (completion, approval pending, input waiting, etc.) through Slack notifications + SketchyBar/tmux badges.

## Overview

- **Slack Notifications**: Notify Claude Code state changes via Slack Webhook
- **SketchyBar Badges**: Display badges on Aerospace workspaces
- **tmux Badges**: Display per-window badges on tmux status bar
- **4 Environment Support**: Works on Local / Local Container / Cloud / Cloud Container
- **Editor Independent**: Works with VS Code / Terminal / Ghostty+tmux

## Supported Environments

| Environment | Editor | Method |
|-------------|--------|--------|
| **Local** | Terminal / VS Code | Direct detection |
| **Local Container** | Terminal | `dexec` + bind mount |
| **Local Container** | VS Code | `DEVCONTAINER_NAME` + bind mount |
| **Remote** | Terminal | `rssh` + SSH + inotifywait |
| **Remote** | VS Code | Direct detection |
| **Remote Container** | Terminal | `rssh` + `dexec` + bind mount |
| **Remote Container** | VS Code | `DEVCONTAINER_NAME` + bind mount |

## Supported Editors/Terminals

Workspace search supports the following applications:

| App | Retrieved from Window Title |
|-----|---------------------------|
| **VS Code** | Container name (`Dev Container: xxx @`) or project name (`— xxx [`) |
| **Ghostty** | Directory name |
| **Terminal.app** | Directory name |
| **iTerm2** | Directory name |
| **Alacritty** | Directory name |
| **WezTerm** | Directory name |
| **kitty** | Directory name |
| **Warp** | Directory name |

## Manual Workspace Registration

Since it's impossible to 100% accurately determine which Aerospace workspace a CLI application is running in (especially with tmux's client/server model), you can manually register the mapping.

### The `/register-workspace` Command

Use this command in Claude Code to register the current environment to a specific workspace:

```
/register-workspace <workspace_number>
```

Example:
```
/register-workspace 3
```

This saves a mapping in `/tmp/claude_workspace_map.json`:
```json
{
  "tmux_MAIN_1": {
    "workspace": "3",
    "window_id": "48208",
    "registered_at": "1768789301"
  }
}
```

### How It Works

1. **Environment Key**: Generated from tmux session/window (`tmux_SESSION_WINDOW`) or VS Code PID (`vscode_PID`)
2. **Window ID**: Retrieved from the specified workspace using `aerospace list-windows`
3. **Priority**: Manual mapping takes precedence over automatic detection

### When to Use

- When running Claude in multiple tmux windows simultaneously
- When automatic workspace detection produces incorrect results
- When you want explicit control over notification placement

## Architecture

### 1. Local (Mac directly)

```
Claude Code (hooks)
    ↓ ai-notify.sh <tool> <event>
    ↓ claude-status.sh set <project> <status>
/tmp/claude_status/*.json
    ↓ sketchybar --trigger claude_status_change
SketchyBar badge update
```

### 2. Local Container (Docker on Mac)

```
Claude Code (hooks) @ Container
    ↓ ai-notify.sh (file write)
/tmp/claude_status/*.json @ Container
    ↓ bind mount (docker run -v /tmp/claude_status:/tmp/claude_status)
/tmp/claude_status/*.json @ Mac
    ↓ sketchybar --trigger (ai-notify.sh executes directly)
SketchyBar badge update
```

### 3. Cloud (Remote Server)

```
Claude Code (hooks) @ Remote
    ↓ ai-notify.sh (file write)
/tmp/claude_status/*.json @ Remote
    ↓ inotifywait (file change detection)
    ↓ Persistent SSH connection
Mac (claude-status-watch.sh)
    ↓ claude-status.sh set
/tmp/claude_status/*.json @ Mac
    ↓ sketchybar --trigger
SketchyBar badge update
```

### 4. Cloud Container (Remote Dev Container)

```
Claude Code (hooks) @ Container
    ↓ ai-notify.sh (file write)
/tmp/claude_status/*.json @ Container
    ↓ bind mount (configured in devcontainer.json)
/tmp/claude_status/*.json @ Remote Host
    ↓ inotifywait (file change detection)
    ↓ Persistent SSH connection
Mac (claude-status-watch.sh)
    ↓ claude-status.sh set
/tmp/claude_status/*.json @ Mac
    ↓ sketchybar --trigger
SketchyBar badge update
```

## tmux Integration

In Ghostty + tmux environments, badges are displayed on the tmux status bar in addition to SketchyBar.

### Behavior

```
Claude Code (hooks)
    ↓ ai-notify.sh (records tmux_session, tmux_window_index)
/tmp/claude_status/window_*.json
    ↓ tmux refresh-client -S
tmux status bar update
    ↓ tmux-claude-badge.sh (called from window-status-format)
Orange badge display (with notification count)
```

### Badge Display

- **Position**: Right side of each window name
- **Color**: Orange background (`#ff6600`) + white text
- **Shape**: Rounded (Powerline style)
- **Content**: Notification count

### Auto-clear

1. Focus on window and **stay for 6 seconds** → Clear notification
2. Leave window (under 6 seconds) → Keep notification
3. Manual clear with `clear-tmux` command also available

### Configuration Files

Load the following in tmux.conf:

```bash
# ~/.config/tmux/tmux.conf
source-file ~/.config/tmux/claude-hooks.tmux
```

## Components

### CLAUDE_CONTEXT Environment Variable

Environment variable for properly handling notifications inside containers. Automatically set by `dexec`.

```json
{
  "project": "my-project",
  "device": "matsushima-mbp",
  "window_id": "12345",
  "tmux_session": "main",
  "tmux_window": "0"
}
```

| Field | Description |
|-------|-------------|
| `project` | Project name (shown in Slack notification) |
| `device` | Device name (shown in Slack notification) |
| `window_id` | Aerospace window ID (for SketchyBar) |
| `tmux_session` | tmux session name |
| `tmux_window` | tmux window index |

### dexec (shell function)

Helper function that automatically sets `CLAUDE_CONTEXT` when entering Docker containers.

```bash
# Usage
dexec <container> [command...]

# Examples
dexec my-container bash
dexec my-container zsh
CLAUDE_PROJECT=custom-name dexec my-container bash
```

**Features**:
- When used locally: Generates new context
- When used remotely: Inherits `CLAUDE_CONTEXT` from `rssh`

**Definition location**: `~/.zshrc.common`

### rssh (shell function)

Helper function that automatically sets `CLAUDE_CONTEXT` for remote SSH connections. No sshd_config changes required.

```bash
# Usage
rssh [ssh-options] <host> [command]

# Examples: Interactive connection
rssh remote-server
rssh -p 2222 user@remote-server

# Examples: Command execution
rssh remote-server "cd /app && ls"
```

**Features**:
- Generates `CLAUDE_CONTEXT` on Mac side and injects during SSH command execution
- No `sshd_config` changes required (doesn't use SendEnv/AcceptEnv)
- Using `dexec` on remote automatically inherits the context

**Definition location**: `~/.zshrc.common`

### scripts/ai-notify.sh

Main notification script. Called from Claude Code hooks.

```bash
# Usage
ai-notify.sh <tool> <event>
ai-notify.sh --setup <tool>       # Webhook cache + setup notification
ai-notify.sh --refresh-cache      # Update all tool webhook caches
ai-notify.sh --clear-cache        # Clear cache

# tool: claude | codex | gemini
# event: stop | complete | permission | idle | error
```

**Features**:
- Retrieves context from `CLAUDE_CONTEXT` environment variable (for containers)
- Fallback: Local detection (for local Mac)
- Retrieves and caches Webhook URLs from 1Password
- Sends Slack notifications (toggles mention based on event)
- Updates SketchyBar state

### scripts/claude-status.sh

Project state management. Works with Aerospace/tmux to identify workspaces.

```bash
claude-status.sh set <project> <status> [session_id] [tty] [window_id] [container_name] [tmux_session] [tmux_window_index]
claude-status.sh get <window_id>
claude-status.sh list
claude-status.sh clear <window_id>
claude-status.sh clear-tmux <tmux_session> <tmux_window_index>  # Clear tmux window notification
claude-status.sh cleanup          # Delete items not updated for 1+ hours
claude-status.sh find-workspace <window_id>
```

**Workspace search logic**:
1. Search VS Code window title for container name/project name
2. Search terminal window title
3. Identify Aerospace workspace from window ID

### scripts/register-workspace.sh

Manually registers the current environment (tmux window / VS Code) to an Aerospace workspace.

```bash
register-workspace.sh <workspace_number>
```

Saves mapping to `/tmp/claude_workspace_map.json`. This mapping takes priority over automatic detection in `ai-notify.sh`.

### scripts/claude-status-watch.sh

Monitors `/tmp/claude_status/` on remote host and transfers changes to Mac.

```bash
claude-status-watch.sh <remote-host>
```

Runs as a launchd daemon with persistent SSH connection.

### common/sketchybar/.config/sketchybar/plugins/claude.sh

SketchyBar plugin. Controls workspace badge visibility.

**Triggers**:
- `claude_status_change`: On state file change
- `front_app_switched`: On focus change (clears notification)
- `aerospace_workspace_change`: On workspace change

### templates/com.user.claude-status-watch.plist

launchd configuration template for remote monitoring.

### scripts/tmux-claude-badge.sh

Badge display script for tmux status bar. Called from `window-status-format`.

```bash
tmux-claude-badge.sh window <window_index> [focused]
```

- Counts notifications for specified window and outputs badge
- When `focused` specified, displays in lighter color

### scripts/tmux-claude-focus.sh

Notification clearing process when focusing tmux window. Called from `session-window-changed` hook.

- Auto-clear with 6 second timer
- Timer cancels if window is left

### common/tmux/.config/tmux/claude-hooks.tmux

tmux hooks configuration file.

```bash
# Execute focus processing on window switch
set-hook -g session-window-changed 'run-shell -b "~/dotfiles/scripts/tmux-claude-focus.sh"'
set-hook -g client-session-changed 'run-shell -b "~/dotfiles/scripts/tmux-claude-focus.sh"'
```

## Setup

### Prerequisites (Mac)

- 1Password CLI (`op`)
- jq
- SketchyBar
- Aerospace

### Common Configuration

1. **Register Webhook URL in 1Password**

   - Save Slack Webhook URL to `op://Personal/Claude Webhook/password`

2. **Configure Claude Code hooks** (`~/.claude/settings.json`)

   ```json
   {
     "hooks": {
       "Stop": [
         {
           "matcher": "",
           "hooks": ["~/dotfiles/scripts/ai-notify.sh claude stop"]
         }
       ],
       "Notification": [
         {
           "matcher": "",
           "hooks": ["~/dotfiles/scripts/ai-notify.sh claude $CLAUDE_NOTIFICATION_TYPE"]
         }
       ]
     }
   }
   ```

3. **Initial Setup (Webhook Cache)**

   ```bash
   ai-notify.sh --setup claude
   ```

---

### 1. Local (Mac directly)

No additional configuration needed. Only the common configuration above is required.

---

### 2. Local Container (Docker on Mac)

#### Method A: Using dexec (Recommended)

Enter the container with `dexec` command, and `CLAUDE_CONTEXT` environment variable is automatically set.

```bash
# Basic usage
dexec my-container bash

# Explicitly specify project name
CLAUDE_PROJECT=my-project dexec my-container zsh
```

**Prerequisites**:
- Add bind mount:
  ```bash
  docker run -v /tmp/claude_status:/tmp/claude_status ...
  ```

#### Method B: Using VS Code Dev Container

1. **Add bind mount** (docker-compose.yml or devcontainer.json)

   ```yaml
   # docker-compose.yml
   volumes:
     - /tmp/claude_status:/tmp/claude_status
   ```

2. **Set DEVCONTAINER_NAME environment variable**

   ```yaml
   environment:
     - DEVCONTAINER_NAME=my-project
   ```

---

### 3. Remote (Remote Server)

#### Connecting from Terminal

Connect with `rssh`, and `CLAUDE_CONTEXT` is automatically set.

```bash
# Connect to remote with rssh
rssh remote-server

# Use Claude on remote
claude
```

#### Remote Side Preparation

1. **Install inotify-tools on remote**

   ```bash
   # If apt is available
   sudo apt install inotify-tools

   # If no sudo, build from source
   cd /tmp
   curl -LO https://github.com/inotify-tools/inotify-tools/archive/refs/tags/4.23.9.0.tar.gz
   tar xzf 4.23.9.0.tar.gz
   cd inotify-tools-4.23.9.0
   ./autogen.sh && ./configure --prefix=$HOME/.local && make && make install
   ```

2. **Configure launchd on Mac**

   ```bash
   # Copy template and edit hostname
   cp ~/dotfiles/templates/com.user.claude-status-watch.plist \
      ~/Library/LaunchAgents/

   # Change <remote-host> to actual SSH config hostname
   vim ~/Library/LaunchAgents/com.user.claude-status-watch.plist

   # Start
   launchctl load ~/Library/LaunchAgents/com.user.claude-status-watch.plist
   ```

---

### 4. Remote Container (Remote Dev Container)

In addition to Remote configuration:

#### Connecting from Terminal

Enter container with `rssh` + `dexec`, and `CLAUDE_CONTEXT` is inherited.

```bash
# Connect to remote with rssh
rssh remote-server

# Enter container with dexec (CLAUDE_CONTEXT is inherited)
dexec my-container bash

# Use Claude inside container
claude
```

**Prerequisites**:
- Add bind mount to container:
  ```bash
  docker run -v /tmp/claude_status:/tmp/claude_status ...
  ```

#### Connecting from VS Code Dev Container

1. **Add bind mount in devcontainer.json**

   ```json
   {
     "mounts": [
       "source=/tmp/claude_status,target=/tmp/claude_status,type=bind"
     ]
   }
   ```

2. **Set DEVCONTAINER_NAME environment variable**

   ```json
   {
     "containerEnv": {
       "DEVCONTAINER_NAME": "my-project"
     }
   }
   ```

   This matches the VS Code window title `Dev Container: my-project @...` and displays badges on the correct workspace.

## Usage

### Event Types

| Event | Slack Notification | Mention | Badge Color |
|-------|-------------------|---------|-------------|
| permission | Yes | @here | Yellow |
| idle | Yes | @here | Blue |
| error | Yes | @here | Red |
| complete | Yes | None | Green |
| stop | No | - | - |

### Manual Commands

```bash
# Check status
claude-status.sh list

# Status of specific project
claude-status.sh get my-project

# Manually set status (for testing)
claude-status.sh set my-project complete

# Cleanup old status
claude-status.sh cleanup
```

### Workspace Registration (Claude Code)

In Claude Code, use the `/register-workspace` command to manually map the current environment to a workspace:

```
/register-workspace 3
```

Or run the script directly:

```bash
# Register current tmux window to workspace 3
~/dotfiles/scripts/register-workspace.sh 3

# Check current mappings
cat /tmp/claude_workspace_map.json | jq .
```

### Service Mode Commands

Enter Service Mode with Aerospace `alt+shift+;`:

| Key | Action |
|-----|--------|
| c | Clear all badges |

## Troubleshooting

### Badge Not Displaying

1. Check status file:
   ```bash
   ls -la /tmp/claude_status/
   cat /tmp/claude_status/*.json
   ```

2. Test workspace search:
   ```bash
   claude-status.sh find-workspace my-project
   ```

3. Manually trigger SketchyBar:
   ```bash
   sketchybar --trigger claude_status_change
   ```

### Remote Notifications Not Arriving

1. Check SSH connection:
   ```bash
   ssh remote-host 'echo ok'
   ```

2. Check inotifywait:
   ```bash
   ssh remote-host 'which inotifywait || ls ~/.local/bin/inotifywait'
   ```

3. Check launchd logs:
   ```bash
   cat /tmp/claude-status-watch.err
   ```

4. Check bind mount:
   ```bash
   # From inside Container
   ls -la /tmp/claude_status/

   # From Remote host
   ls -la /tmp/claude_status/
   ```

### Cannot Retrieve Webhook

1. Sign in to 1Password:
   ```bash
   eval $(op signin)
   ```

2. Update cache:
   ```bash
   ai-notify.sh --refresh-cache
   ```

3. Check cache:
   ```bash
   ls -la ~/.local/share/ai-notify/
   ```

## File Structure

```
dotfiles/
├── scripts/
│   ├── ai-notify.sh                # Main notification script (CLAUDE_CONTEXT support)
│   ├── claude-status.sh            # State management
│   ├── claude-status-watch.sh      # Remote monitoring (SSH + inotifywait)
│   ├── claude-status-local-watch.sh # Local container monitoring (launchd WatchPaths)
│   ├── tmux-claude-badge.sh        # tmux badge display
│   └── tmux-claude-focus.sh        # tmux focus processing
├── common/zsh/.zshrc.common        # _claude_context, dexec, rssh function definitions
├── common/sketchybar/.config/sketchybar/
│   └── plugins/
│       └── claude.sh               # SketchyBar plugin
├── common/tmux/.config/tmux/
│   └── claude-hooks.tmux           # tmux hooks configuration
└── templates/
    └── com.user.claude-status-watch.plist  # launchd template
```

## Related Configuration

- `~/.claude/settings.json` - Claude Code hooks configuration
- `~/.local/share/ai-notify/` - Webhook cache
- `/tmp/claude_status/` - State files
