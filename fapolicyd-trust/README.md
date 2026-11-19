# fapolicyd-trust

Build and maintain a fapolicyd trust list from what is actually running on a RHEL system.

The RHEL STIG profile installs and starts fapolicyd, which ships **enforcing** with trust
sourced from the RPM database. Anything not installed by rpm (vendor agents, in-house apps)
stops working the moment the service starts. This tool builds the allow-list from the
software that is genuinely present and running, so the control can be met without taking
the system down.

## Modes

| Flag | What it does |
|------|--------------|
| *(none)* | Discover and report; changes nothing |
| `--generate` | Write the trust file(s); does not tell the daemon |
| `--apply` | Generate and reload trust; **stays permissive** |
| `--enforce` | Flip to enforcing behind an auto-revert timer |
| `--verify` | Report drift between the trust file and disk |
| `--status` | Show current state |

`-n/--name` names the trust file, `-p/--path` adds an application path (repeatable).
Run `./fapolicyd-trust.sh --help` for the full list.

Measured on RHEL 8.10 with fapolicyd 1.3.2. The NOTES section at the bottom of the script
covers the fapolicyd behaviours that drove the design; several of them are traps.
