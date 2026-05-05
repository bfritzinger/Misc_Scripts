# VS Code Extensions Bootstrap

Standardized VS Code extension setup for dev team. Run one script and your editor matches the rest of the team's tooling. 

## Quick start

**Linux / macOS**

```bash
chmod +x install-extensions.sh uninstall-extensions.sh
./install-extensions.sh
```

**Windows**

Easiest path — double-click or run the `.bat` wrapper:

```cmd
install-extensions.bat
```

The wrapper invokes the PowerShell script with `-ExecutionPolicy Bypass` so you don't have to deal with execution policy or "mark of the web" errors. If you'd rather call PowerShell directly, see [Troubleshooting](#troubleshooting) below.

That's it — both scripts read `extensions.txt`, skip anything already installed, and install the rest with `--force` so reinstalls are idempotent.

## What's in this package

| File | Purpose |
|------|---------|
| `extensions.txt` | Canonical list of extensions — **the only file you usually edit** |
| `install-extensions.sh` | Installer for Linux/macOS |
| `install-extensions.ps1` | Installer for Windows |
| `install-extensions.bat` | Windows wrapper that runs the `.ps1` with `-ExecutionPolicy Bypass` |
| `uninstall-extensions.sh` | Uninstaller for Linux/macOS |
| `uninstall-extensions.ps1` | Uninstaller for Windows |
| `uninstall-extensions.bat` | Windows wrapper for the uninstaller |

Both installers behave identically: parse the list, snapshot the currently installed extensions (with versions), and install only what's missing or out-of-version.

## The extensions list

`extensions.txt` is plain text. One extension ID per line. Comments start with `#`. To pin a version, append `@<version>`:

```
ms-python.python@2024.0.1
golang.go
```

Without `@version`, the latest is installed. Pin versions when the team needs identical tooling — for example after an extension ships a regression and you want to lock everyone to the last known-good build.

### Updating the list

To capture your current setup as the new baseline, on a reference machine:

```bash
code --list-extensions --show-versions > extensions.txt
```

Then trim, group, comment, and commit. Strip the `@version` suffix from any extension you'd rather track at "latest".

## Options

Both installers and uninstallers accept the same set of flags. Long names shown for clarity; short forms work in bash.

| Bash | PowerShell | Description |
|------|------------|-------------|
| `-f, --file PATH` | `-File PATH` | Use a different extensions list |
| `-c, --cmd CMD` | `-CodeCmd CMD` | Use a different CLI (`code-insiders`, `cursor`, or a full path) |
| `-n, --dry-run` | `-DryRun` | Print what would happen without doing it |
| `-h, --help` | `Get-Help .\install-extensions.ps1` | Show usage |

Uninstallers add one more:

| Bash | PowerShell | Description |
|------|------------|-------------|
| `-a, --all` | `-All` | Uninstall **every** installed extension (full reset, prompts for confirmation) |

## Examples

Preview what would be installed without making changes:

```bash
./install-extensions.sh --dry-run
```

```powershell
.\install-extensions.ps1 -DryRun
```

Use the scripts with Cursor instead of VS Code:

```bash
./install-extensions.sh --cmd cursor
```

```powershell
.\install-extensions.ps1 -CodeCmd cursor
```

Remove only the team's standard extensions:

```bash
./uninstall-extensions.sh
```

Nuke everything for a clean reset:

```bash
./uninstall-extensions.sh --all
```

```powershell
.\uninstall-extensions.ps1 -All
```

## Troubleshooting

**`code: command not found` (macOS)**

Open VS Code, press `Cmd+Shift+P`, run **Shell Command: Install 'code' command in PATH**. Then restart your terminal.

**`code: command not found` (Linux)**

The `code` symlink is normally created by the VS Code installer. Restart your shell first; if it's still missing, check `which code` and verify your PATH includes `/usr/bin` or wherever VS Code installed.

**`code` not on PATH (Windows)**

The PowerShell installer falls back to checking these locations automatically:

- `%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd`
- `%ProgramFiles%\Microsoft VS Code\bin\code.cmd`
- `%ProgramFiles(x86)%\Microsoft VS Code\bin\code.cmd`

If you installed VS Code somewhere else, pass the full path:

```powershell
.\install-extensions.ps1 -CodeCmd "D:\Tools\VSCode\bin\code.cmd"
```

**Cursor / VS Code Insiders**

Pass `-c cursor` (bash) or `-CodeCmd cursor` (PowerShell). Both forks ship CLIs with the same `--install-extension` / `--list-extensions` / `--uninstall-extension` flags.

**PowerShell: "file is not digitally signed" / execution policy errors**

Windows tags downloaded files with a "mark of the web" identifier. Combined with the default `RemoteSigned` execution policy, that blocks unsigned downloaded scripts like ours.

The simplest fix is to run `install-extensions.bat` instead of `install-extensions.ps1` — the wrapper passes `-ExecutionPolicy Bypass` to PowerShell and avoids the issue entirely.

If you'd rather invoke the `.ps1` directly, you have three options:

```powershell
# Cleanest: strip the download mark from this file (one-time, persists)
Unblock-File .\install-extensions.ps1
Unblock-File .\uninstall-extensions.ps1

# Or invoke PowerShell with an explicit bypass each time:
powershell -ExecutionPolicy Bypass -File .\install-extensions.ps1

# Or relax policy for just the current PowerShell session:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Avoid changing execution policy at the machine or user scope just for this — the per-process or per-file approach keeps your security posture intact.

**An extension fails to install**

Run with `--dry-run` to confirm the ID is correct. Extension IDs are case-insensitive but must match the publisher exactly (`ms-python.python`, not `python.python`). The marketplace page shows the ID under "More Info → Identifier".

## Project-specific recommendations

For extensions that should only be suggested when a developer opens a particular repo, use VS Code's built-in mechanism instead of these scripts. Drop a `.vscode/extensions.json` in the repo root:

```json
{
  "recommendations": [
    "publisher.extension-id"
  ]
}
```

VS Code prompts contributors to install them on workspace open. That's the right tool for repo-scoped tooling; this package is for the global team baseline.
