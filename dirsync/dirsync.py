#!/usr/bin/env python3
"""
dirsync.py - Compare two directories and copy deltas from source to destination.

Usage:
    python3 dirsync.py <source_dir> <dest_dir> [options]

Options:
    --dry-run       Show what would be copied without making changes
    --delete        Remove files in dest that no longer exist in source
    --verbose       Print all compared files, not just changes
    --checksum      Use MD5 checksum for comparison instead of mtime+size
"""

import argparse
import hashlib
import os
import shutil
import sys
from pathlib import Path


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

def md5(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        while data := f.read(chunk):
            h.update(data)
    return h.hexdigest()


def files_differ(src: Path, dst: Path, use_checksum: bool) -> bool:
    """Return True if src and dst are considered different."""
    if not dst.exists():
        return True
    if src.stat().st_size != dst.stat().st_size:
        return True
    if use_checksum:
        return md5(src) != md5(dst)
    # Fall back to mtime comparison (rounded to 2s for FAT tolerance)
    return abs(src.stat().st_mtime - dst.stat().st_mtime) > 2


def relative_files(base: Path):
    """Yield all file paths relative to base."""
    for root, _, filenames in os.walk(base):
        for name in filenames:
            abs_path = Path(root) / name
            yield abs_path.relative_to(base)


# ──────────────────────────────────────────────
# Core logic
# ──────────────────────────────────────────────

def sync(src_dir: Path, dst_dir: Path, dry_run: bool, delete: bool,
         verbose: bool, use_checksum: bool) -> dict:

    stats = {"copied": 0, "skipped": 0, "deleted": 0, "errors": 0}

    src_files = set(relative_files(src_dir))
    dst_files = set(relative_files(dst_dir))

    # ── Copy new / changed files ──────────────────
    for rel in sorted(src_files):
        src = src_dir / rel
        dst = dst_dir / rel

        if files_differ(src, dst, use_checksum):
            reason = "NEW" if not dst.exists() else "CHANGED"
            print(f"  [{reason}] {rel}")
            if not dry_run:
                try:
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src, dst)
                    stats["copied"] += 1
                except Exception as exc:
                    print(f"  [ERROR] Could not copy {rel}: {exc}", file=sys.stderr)
                    stats["errors"] += 1
            else:
                stats["copied"] += 1
        else:
            if verbose:
                print(f"  [OK]    {rel}")
            stats["skipped"] += 1

    # ── Optionally delete orphaned dest files ──────
    if delete:
        for rel in sorted(dst_files - src_files):
            print(f"  [DELETE] {rel}")
            if not dry_run:
                try:
                    (dst_dir / rel).unlink()
                    stats["deleted"] += 1
                except Exception as exc:
                    print(f"  [ERROR] Could not delete {rel}: {exc}", file=sys.stderr)
                    stats["errors"] += 1
            else:
                stats["deleted"] += 1

        # Clean up empty directories left behind
        if not dry_run:
            for root, dirs, files in os.walk(dst_dir, topdown=False):
                for d in dirs:
                    target = Path(root) / d
                    if not any(target.iterdir()):
                        try:
                            target.rmdir()
                        except OSError:
                            pass

    return stats


# ──────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Copy delta files from source directory to destination directory."
    )
    parser.add_argument("source", help="Source directory")
    parser.add_argument("dest",   help="Destination directory")
    parser.add_argument("--dry-run",  action="store_true", help="Simulate without copying")
    parser.add_argument("--delete",   action="store_true", help="Delete files in dest not in source")
    parser.add_argument("--verbose",  action="store_true", help="Show unchanged files too")
    parser.add_argument("--checksum", action="store_true", help="Use MD5 checksum instead of mtime+size")
    args = parser.parse_args()

    src_dir = Path(args.source).resolve()
    dst_dir = Path(args.dest).resolve()

    # Validate
    if not src_dir.is_dir():
        sys.exit(f"ERROR: Source directory does not exist: {src_dir}")
    if src_dir == dst_dir:
        sys.exit("ERROR: Source and destination are the same directory.")

    dst_dir.mkdir(parents=True, exist_ok=True)

    # Header
    print(f"\n{'DRY RUN — ' if args.dry_run else ''}Directory Sync")
    print(f"  Source : {src_dir}")
    print(f"  Dest   : {dst_dir}")
    print(f"  Method : {'checksum (MD5)' if args.checksum else 'mtime + size'}")
    print(f"  Delete : {args.delete}")
    print("─" * 60)

    stats = sync(
        src_dir, dst_dir,
        dry_run=args.dry_run,
        delete=args.delete,
        verbose=args.verbose,
        use_checksum=args.checksum,
    )

    # Summary
    print("─" * 60)
    tag = "(would be)" if args.dry_run else ""
    print(f"  Copied  {tag}: {stats['copied']}")
    print(f"  Skipped      : {stats['skipped']}")
    if args.delete:
        print(f"  Deleted {tag}: {stats['deleted']}")
    if stats["errors"]:
        print(f"  Errors       : {stats['errors']}")
    print()


if __name__ == "__main__":
    main()