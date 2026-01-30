# Starship Prompt Configuration

Starship configuration for customizing shell prompts. Modern prompt based on the Dracula theme.

## Overview

- **Two-line Prompt**: Separates information display from command input
- **Dracula Theme**: Unified color palette
- **Git Integration**: Displays branch, status, file count and diff line counts
- **Context Information**: OS, directory, execution time, time, username

## UI Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  󰉖 ~/dotfiles   main ⇡1  󰊤 3f +10/-5 ─────────────  25ms  󰙦 14:30   user │
│ ❯❯                                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
   ↑       ↑         ↑       ↑           ↑            ↑       ↑       ↑
  OS   Directory   Branch  Status   Git Diff       Duration Time  Username
```

| Element | Description | Color |
|---------|-------------|-------|
| **OS** | OS icon (macOS: 󰊠) | Red |
| **Directory** | Current directory (up to 2 levels) | Pink |
| **Git Branch** | Current branch name | Green |
| **Git Status** | ahead/behind/diverged state | Green (background) |
| **Git Diff** | File count + added/deleted lines | Cyan |
| **Duration** | Command execution time (500ms+) | Orange |
| **Time** | Current time (HH:MM) | Purple |
| **Username** | Username | Yellow |
| **Character** | Input prompt (❯❯) | Green/Red |

## Module Details

### OS

```
┌──────────┐
│  󰊠      │  ← macOS
└──────────┘
```

Displays OS identification icon. Supported OS:
- macOS: 󰊠
- Linux: 󰌽
- Ubuntu: 󰕈
- Debian: 󰣚
- Arch: 󰣇
- Alpine, CentOS, Fedora

### Directory

```
┌────────────────────┐
│ 󰉖 ~/dotfiles      │
└────────────────────┘
```

- Home directory shown as `~/`
- Shows up to 2 levels, truncates with ` ` beyond that
- Read-only directories show 󱞵 icon

### Git Branch

```
┌─────────────────┐
│  main          │
└─────────────────┘
```

Displays current Git branch. Hidden outside repositories.

### Git Status

```
┌────────────────────┐
│ ⇡1                │  ← 1 commit ahead of remote
│ ⇣2                │  ← 2 commits behind remote
│ ⇕⇡1⇣2             │  ← Diverged state
└────────────────────┘
```

Displays diff state from remote.

### Git Diff

```
┌──────────────────┐
│ 󰊤 3f +10/-5     │
└──────────────────┘
```

Displays file count, added lines, and deleted lines for current changes (`git diff HEAD`).
Custom module using `scripts/starship-git-diff.sh`.

### Command Duration

```
┌──────────────┐
│  25ms       │
└──────────────┘
```

Displays execution time for commands taking 500ms or more.

### Time

```
┌────────────┐
│ 󰙦 14:30   │
└────────────┘
```

Displays current time in 24-hour format.

### Username

```
┌────────────┐
│  user     │
└────────────┘
```

Always displays current username.

### Character

```
┌────────────┐
│ ❯❯        │  ← Success (green)
│ ❯❯        │  ← Error (red)
└────────────┘
```

Color changes based on previous command's exit code.

## Color Palette (Dracula)

| Name | Color | HEX | Usage |
|------|-------|-----|-------|
| foreground | White | `#F8F8F2` | Text |
| background | Dark Gray | `#282A36` | Background |
| current_line | Gray | `#44475A` | Separator lines, box backgrounds |
| primary | Black | `#1E1F29` | Icon backgrounds |
| red | Red | `#FF5555` | OS |
| pink | Pink | `#FF79C6` | Directory |
| green | Green | `#50FA7B` | Git Branch, success |
| cyan | Cyan | `#8BE9FD` | Git Diff |
| orange | Orange | `#FFB86C` | Duration |
| purple | Purple | `#BD93F9` | Time |
| yellow | Yellow | `#F1FA8C` | Username |

## Configuration File

```
~/.config/starship.toml  ← dotfiles/common/starship/.config/starship.toml
```

### Structure

```toml
# Format definition
format = """
$os\
$directory\
$git_branch\
$git_status\
${custom.git_diff}\
..."""

# Palette selection
palette = 'dracula'

# Color palette definition
[palettes.dracula]
foreground = '#F8F8F2'
...

# Module settings
[os]
[directory]
[git_branch]
[git_status]
[custom.git_diff]  # scripts/starship-git-diff.sh
...
```

## Setup

### Installation

```bash
# Install Starship
brew install starship

# Install dotfiles
./install.sh
```

### Shell Configuration

The following is required in zshrc (included in dotfiles):

```bash
eval "$(starship init zsh)"
```

## Customization

### Change Directory Display Depth

```toml
[directory]
truncation_length = 3  # Show up to 3 levels
```

### Change Time Format

```toml
[time]
time_format = '%Y-%m-%d %H:%M:%S'  # Also show date
```

### Disable Modules

```toml
[custom.git_diff]
disabled = true  # Hide Git Diff
```

## Troubleshooting

### Icons Display as Garbled Text

Nerd Font is not installed:

```bash
# Install Nerd Font
brew install --cask font-hack-nerd-font

# Select Nerd Font in terminal font settings
```

### Prompt Not Displaying

```bash
# Check Starship
which starship

# Check shell configuration
grep starship ~/.zshrc
```

### Git Information Not Displaying

```bash
# Verify you're inside a Git repository
git status

# Check Starship configuration
starship explain
```

### Colors Look Wrong

Verify terminal supports True Color:

```bash
# True Color test
printf "\x1b[38;2;255;100;0mTrue Color\x1b[0m\n"
```

## Related Documentation

- [Starship Official Documentation](https://starship.rs/)
- [Dracula Theme](https://draculatheme.com/)
