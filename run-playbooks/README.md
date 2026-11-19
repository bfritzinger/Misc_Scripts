# run-playbooks

Run several Ansible playbooks, from any directories, against one shared inventory file.

Edit the `PLAYBOOKS=(...)` list at the top of the script (the shipped entries are
placeholders), then:

```bash
./run-playbooks.sh                     # run every playbook in the list
./run-playbooks.sh a.yml b.yml         # run just these instead
./run-playbooks.sh -c -d -l web01      # check + diff mode, one host
```

Options go **before** playbook paths.

| Option | Meaning |
|--------|---------|
| `-i INVENTORY` | Inventory file (default: `inventory.txt` next to the script) |
| `-f` | Fail fast: stop at the first failing playbook (default: continue) |
| `-c` / `-d` | Check mode / diff mode |
| `-L TAGS` / `-S TAGS` | `--tags` / `--skip-tags` |
| `-l HOSTS` | `--limit` |
| `-e KEY=VALUE` | Extra vars (repeatable) |
| `-v` | Verbose (repeatable) |

Exit status: `0` only if every playbook ran and passed, `1` if any failed or was missing,
`2` on a usage error.
