# GitHub Starred Repos Recap

A Python script that fetches all your GitHub starred repositories and generates a summary report with statistics and a full listing.

## Features

- Fetches all starred repos (handles pagination automatically)
- Exports to JSON for archival/processing
- Prints formatted report to terminal with:
  - Top languages breakdown
  - Most popular repos you've starred
  - Recently updated repos
  - Common topics/tags
  - Quick stats (orgs vs users, archived count)
  - Full alphabetical listing with descriptions and URLs

## Requirements

- Python 3.6+
- `requests` library
```bash
pip install requests
```

## Configuration

Edit these variables at the top of the script:
```python
GITHUB_USERNAME = "your_username"  # Your GitHub username
GITHUB_TOKEN = None                # Optional: GitHub Personal Access Token
OUTPUT_JSON = "starred_repos.json" # Output filename
```

### GitHub Token (Optional but Recommended)

Without a token, GitHub limits you to 60 API requests per hour. With a token, you get 5,000 requests per hour.

To create a token:
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token (classic)
3. No special scopes needed for public stars (add `repo` scope if you want private repo access)
4. Copy token and set `GITHUB_TOKEN = "ghp_xxxxx"`

## Usage
```bash
python github-stars.py
```

## Output

### Terminal Output
```
+======================================================================+
|  ⭐ GITHUB STARRED REPOS RECAP                                       |
+======================================================================+
|  Total: 42 repositories                                              |
|  Exported: 2025-01-15T10:30:00                                       |
+======================================================================+

+--------------------------------------------------+
|  📊 TOP LANGUAGES                                |
+--------------------------------------------------+
|  Python: 15 ███████████████                      |
|  Go: 8 ████████                                  |
|  JavaScript: 6 ██████                            |
+--------------------------------------------------+

... (additional sections) ...
```

### JSON Output
```json
{
  "exported_at": "2025-01-15T10:30:00.123456",
  "total_count": 42,
  "repositories": [
    {
      "name": "owner/repo-name",
      "description": "Repository description",
      "url": "https://github.com/owner/repo-name",
      "language": "Python",
      "stars": 1234,
      "forks": 567,
      "open_issues": 23,
      "topics": ["cli", "automation", "python"],
      "created_at": "2020-01-15T...",
      "updated_at": "2025-01-10T...",
      "starred_at": "2024-06-15T...",
      "archived": false,
      "owner": "owner",
      "owner_type": "Organization",
      "license": "MIT License",
      "homepage": "https://example.com"
    }
  ]
}
```

## JSON Fields

| Field | Description |
|-------|-------------|
| `name` | Full repository name (owner/repo) |
| `description` | Repository description |
| `url` | GitHub URL |
| `language` | Primary programming language |
| `stars` | Star count |
| `forks` | Fork count |
| `open_issues` | Open issue count |
| `topics` | Repository topics/tags |
| `created_at` | When repo was created |
| `updated_at` | Last update timestamp |
| `starred_at` | When you starred it |
| `archived` | Whether repo is archived |
| `owner` | Owner username/org |
| `owner_type` | "User" or "Organization" |
| `license` | License name |
| `homepage` | Project homepage URL |

## Troubleshooting

### Import Errors

**`ImportError: cannot import name 'idnadata' from 'idna'`**

Corrupted `idna` package. Reinstall:
```bash
pip uninstall idna requests
pip install requests
```

**`ModuleNotFoundError: No module named 'requests'`**

Install the requests library:
```bash
pip install requests
```

For Windows Store Python:
```bash
py -m pip install requests
```

### Certificate Errors

**`OSError: Could not find a suitable TLS CA certificate bundle`**

Reinstall the certificate bundle:
```bash
pip uninstall certifi
pip install certifi
```

Or force reinstall everything:
```bash
pip install --force-reinstall requests certifi urllib3
```

### API Errors

**`requests.exceptions.HTTPError: 403 Forbidden`**

Rate limit exceeded. Either:
- Wait an hour for the limit to reset
- Add a GitHub token to increase your limit from 60 to 5,000 requests/hour

**`requests.exceptions.HTTPError: 404 Not Found`**

Username not found. Check that `GITHUB_USERNAME` is spelled correctly.

**`requests.exceptions.HTTPError: 401 Unauthorized`**

Token is invalid or expired. Generate a new Personal Access Token on GitHub.

### Display Issues

**Box characters or emojis not displaying correctly**

Your terminal may not support Unicode. Options:
- Use Windows Terminal instead of cmd.exe
- Use a terminal with UTF-8 support
- Modify the script to use ASCII-only characters

**Alignment issues in output**

Some terminals render emoji widths differently. The script accounts for most cases, but if alignment is off, you can swap problematic emojis for simpler ones or remove them.

### No Output / Empty Results

**Script runs but shows 0 repositories**

- Verify the username has public starred repos at `https://github.com/USERNAME?tab=stars`
- If starring is private, you'll need a token with appropriate permissions

### Windows-Specific Issues

**`py` command not found**

Use `python` instead of `py`, or ensure Python is in your PATH.

**SSL/TLS errors behind corporate proxy**

You may need to configure proxy settings or disable SSL verification (not recommended for production):
```python
response = requests.get(url, headers=headers, params=params, verify=False)
```

## Notes

- The script uses the `star+json` media type to include the `starred_at` timestamp
- Large star collections may take a moment to fetch (100 repos per API call)
- Rate limit info is printed if you hit GitHub's limits

## License

MIT