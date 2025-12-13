#!/usr/bin/env python3
"""Recap of GitHub starred repositories."""

import requests
import json
from collections import Counter
from datetime import datetime
from pathlib import Path
import unicodedata

# Configure these
GITHUB_USERNAME = "your_username"
# Optional: Use a token for higher rate limits and access to private stars
GITHUB_TOKEN = None  # or "ghp_xxxxx"

# Output file
OUTPUT_JSON = "starred_repos.json"


def get_starred_repos(username, token=None):
    """Fetch all starred repositories for a user."""
    repos = []
    page = 1
    headers = {"Accept": "application/vnd.github.v3.star+json"}  # Includes starred_at timestamp
    
    if token:
        headers["Authorization"] = f"token {token}"
    
    while True:
        url = f"https://api.github.com/users/{username}/starred"
        params = {"page": page, "per_page": 100}
        
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        
        data = response.json()
        if not data:
            break
        
        repos.extend(data)
        page += 1
        print(f"Fetched page {page - 1} ({len(repos)} repos so far)")
    
    return repos


def export_to_json(repos, filename):
    """Export repos to JSON file."""
    # Create a cleaner export format
    export_data = {
        "exported_at": datetime.now().isoformat(),
        "total_count": len(repos),
        "repositories": []
    }
    
    for item in repos:
        # Handle both formats (with and without starred_at)
        if "repo" in item:
            r = item["repo"]
            starred_at = item.get("starred_at")
        else:
            r = item
            starred_at = None
        
        repo_data = {
            "name": r["full_name"],
            "description": r.get("description"),
            "url": r["html_url"],
            "language": r.get("language"),
            "stars": r.get("stargazers_count", 0),
            "forks": r.get("forks_count", 0),
            "open_issues": r.get("open_issues_count", 0),
            "topics": r.get("topics", []),
            "created_at": r.get("created_at"),
            "updated_at": r.get("updated_at"),
            "starred_at": starred_at,
            "archived": r.get("archived", False),
            "owner": r.get("owner", {}).get("login"),
            "owner_type": r.get("owner", {}).get("type"),
            "license": r.get("license", {}).get("name") if r.get("license") else None,
            "homepage": r.get("homepage"),
        }
        export_data["repositories"].append(repo_data)
    
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(export_data, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Exported to {filename}")
    return export_data


def display_width(s):
    """Calculate display width accounting for emoji widths."""
    width = 0
    for char in s:
        # Variation selectors have zero width
        if '\uFE00' <= char <= '\uFE0F':
            continue
        # Zero-width joiners
        if char == '\u200D':
            continue
        if unicodedata.east_asian_width(char) in ('W', 'F'):
            width += 2
        elif ord(char) > 0x1F300:  # Most emojis
            width += 2
        else:
            width += 1
    return width


def pad_line(content, total_width):
    """Pad a line to exact width accounting for emojis."""
    current_width = display_width(content)
    padding_needed = total_width - current_width
    return content + " " * padding_needed


def print_recap(export_data):
    """Print a nicely formatted recap to screen."""
    repos = export_data["repositories"]
    
    # Header
    print("\n")
    print("+" + "=" * 70 + "+")
    print("|" + pad_line("  ⭐ GITHUB STARRED REPOS RECAP", 70) + "|")
    print("+" + "=" * 70 + "+")
    print("|" + pad_line(f"  Total: {len(repos)} repositories", 70) + "|")
    print("|" + pad_line(f"  Exported: {export_data['exported_at'][:19]}", 70) + "|")
    print("+" + "=" * 70 + "+")
    
    # Languages breakdown
    languages = Counter(r["language"] for r in repos if r["language"])
    print("\n+" + "-" * 50 + "+")
    print("|" + pad_line("  📊 TOP LANGUAGES", 50) + "|")
    print("+" + "-" * 50 + "+")
    for lang, count in languages.most_common(10):
        bar = "█" * min(count, 20)
        line = f"  {lang}: {count} {bar}"
        print("|" + pad_line(line, 50) + "|")
    print("+" + "-" * 50 + "+")
    
    # Most popular repos
    by_stars = sorted(repos, key=lambda r: r["stars"], reverse=True)[:10]
    print("\n+" + "-" * 70 + "+")
    print("|" + pad_line("  🔥 MOST POPULAR REPOS YOU'VE STARRED", 70) + "|")
    print("+" + "-" * 70 + "+")
    for r in by_stars:
        name = r['name'][:45]
        stars = f"{r['stars']:,}"
        line = f"  {name:<45} ⭐ {stars:>10}"
        print("|" + pad_line(line, 70) + "|")
    print("+" + "-" * 70 + "+")
    
    # Recently updated
    by_updated = sorted(repos, key=lambda r: r["updated_at"] or "", reverse=True)[:10]
    print("\n+" + "-" * 70 + "+")
    print("|" + pad_line("  🕐 RECENTLY UPDATED", 70) + "|")
    print("+" + "-" * 70 + "+")
    for r in by_updated:
        updated = (r["updated_at"] or "")[:10]
        name = r['name'][:55]
        line = f"  {name:<55} {updated}"
        print("|" + pad_line(line, 70) + "|")
    print("+" + "-" * 70 + "+")
    
    # Topics
    all_topics = []
    for r in repos:
        all_topics.extend(r.get("topics") or [])
    topics = Counter(all_topics)
    if topics:
        print("\n+" + "-" * 50 + "+")
        print("|" + pad_line("  🔖 TOP TOPICS", 50) + "|")
        print("+" + "-" * 50 + "+")
        for topic, count in topics.most_common(15):
            line = f"  {topic}: {count}"
            print("|" + pad_line(line, 50) + "|")
        print("+" + "-" * 50 + "+")
    
    # Stats summary
    archived = sum(1 for r in repos if r["archived"])
    orgs = sum(1 for r in repos if r["owner_type"] == "Organization")
    users = len(repos) - orgs
    
    print("\n+" + "-" * 40 + "+")
    print("|" + pad_line("  📈 QUICK STATS", 40) + "|")
    print("+" + "-" * 40 + "+")
    print("|" + pad_line(f"  👥 Organizations: {orgs}", 40) + "|")
    print("|" + pad_line(f"  👤 Users: {users}", 40) + "|")
    print("|" + pad_line(f"  📦 Archived: {archived}", 40) + "|")
    print("|" + pad_line(f"  💻 Languages: {len(languages)}", 40) + "|")
    print("|" + pad_line(f"  🔖 Topics: {len(topics)}", 40) + "|")
    print("+" + "-" * 40 + "+")
    
    # Full list
    print("\n")
    print("+" + "=" * 78 + "+")
    print("|" + pad_line("  📋 ALL STARRED REPOS", 78) + "|")
    print("+" + "=" * 78 + "+")
    
    for r in sorted(repos, key=lambda r: r["name"].lower()):
        print()
        print(f"  📁 {r['name']}")
        if r["description"]:
            desc = r["description"][:74]
            print(f"     {desc}{'...' if len(r['description']) > 74 else ''}")
        lang = r['language'] or 'N/A'
        stats = f"     ⭐ {r['stars']:,}  🍴 {r['forks']:,}  💻 {lang}"
        if r["archived"]:
            stats += "  📦 ARCHIVED"
        print(stats)
        print(f"     🔗 {r['url']}")
    
    print("\n" + "-" * 78)
    print(f"⭐ Total: {len(repos)} starred repositories")
    print("-" * 78)


def main():
    print(f"Fetching starred repos for {GITHUB_USERNAME}...")
    repos = get_starred_repos(GITHUB_USERNAME, GITHUB_TOKEN)
    
    # Export to JSON
    export_data = export_to_json(repos, OUTPUT_JSON)
    
    # Print formatted recap
    print_recap(export_data)


if __name__ == "__main__":
    main()