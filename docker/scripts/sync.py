#!/usr/bin/env python3
"""Sync an S3 prefix locally, compress it, and publish it to the Nginx web root."""
import json
import os
import subprocess
import sys
import tarfile
import time
from datetime import datetime, timezone

S3_BUCKET = os.environ.get("S3_BUCKET")
S3_PREFIX = os.environ.get("S3_PREFIX", "")
WORK_DIR = os.environ.get("WORK_DIR", "/tmp/s3-sync")
WEB_ROOT = os.environ.get("WEB_ROOT", "/usr/share/nginx/html")
SYNC_INTERVAL = int(os.environ.get("SYNC_INTERVAL", "300"))
ARCHIVE_NAME = os.environ.get("ARCHIVE_NAME", "archive.tar.gz")


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def log(msg: str) -> None:
    print(f"[{now()}] {msg}", flush=True)


def write_status(result: str, size: int, files: int) -> None:
    status = {
        "last_run": now(),
        "result": result,
        "archive": ARCHIVE_NAME,
        "size_bytes": size,
        "file_count": files,
        "source": f"s3://{S3_BUCKET}/{S3_PREFIX}",
    }
    tmp = os.path.join(WEB_ROOT, ".status.json.tmp")
    with open(tmp, "w") as f:
        json.dump(status, f)
    os.replace(tmp, os.path.join(WEB_ROOT, "status.json"))


def sync_once() -> None:
    data_dir = os.path.join(WORK_DIR, "data")
    os.makedirs(data_dir, exist_ok=True)

    log(f"Syncing s3://{S3_BUCKET}/{S3_PREFIX}")
    subprocess.run(
        ["aws", "s3", "sync", f"s3://{S3_BUCKET}/{S3_PREFIX}", data_dir,
         "--delete", "--only-show-errors"],
        check=True,
    )

    # Compress to a temp file, then rename so Nginx never serves a partial archive.
    tmp_archive = os.path.join(WORK_DIR, ARCHIVE_NAME + ".tmp")
    with tarfile.open(tmp_archive, "w:gz") as tar:
        tar.add(data_dir, arcname=".")
    final = os.path.join(WEB_ROOT, ARCHIVE_NAME)
    os.replace(tmp_archive, final)

    size = os.path.getsize(final)
    files = sum(len(names) for _, _, names in os.walk(data_dir))
    write_status("success", size, files)
    log(f"Published {ARCHIVE_NAME} ({size} bytes, {files} files)")


def run_once() -> bool:
    try:
        sync_once()
        return True
    except Exception as exc:  # report any failure in status.json, keep the loop alive
        log(f"Sync failed: {exc}")
        write_status("failure", 0, 0)
        return False


def main() -> int:
    if not S3_BUCKET:
        print("S3_BUCKET is required", file=sys.stderr)
        return 2

    mode = sys.argv[1] if len(sys.argv) > 1 else "loop"
    if mode == "once":
        return 0 if run_once() else 1
    if mode == "loop":
        while True:
            run_once()
            time.sleep(SYNC_INTERVAL)
    print(f"usage: {sys.argv[0]} [once|loop]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
