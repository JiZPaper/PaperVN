#!/usr/bin/env python3
"""Collect a resumable Paparu visual-novel image dataset.

The existing vndb_id_connector.json is the only source of cross-service IDs.
Entries are grouped by VNDB ID, so multiple Steam or Bangumi releases remain
attached to one visual novel instead of becoming duplicate training classes.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import http.client
import json
import re
import shutil
import socket
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Iterator


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MAPPING = PROJECT_ROOT / "PaperVN" / "Resources" / "vndb_id_connector.json"
DEFAULT_OUTPUT = PROJECT_ROOT / ".build" / "paparu-vision-dataset"
VNDB_API = "https://api.vndb.org/kana"
STEAM_DETAILS_API = "https://store.steampowered.com/api/appdetails"
BANGUMI_SUBJECT_API = "https://api.bgm.tv/v0/subjects"
USER_AGENT = "PaperVN-PaparuVisionDataset/1.0"
VNDB_FIELDS = (
    "id,title,titles{lang,title,latin,official,main},aliases,"
    "image{id,url,thumbnail,dims,sexual,violence},"
    "screenshots{id,url,thumbnail,dims,sexual,violence},"
    "va{character{id,name,original,aliases,image{url,sexual,violence}}}"
)
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif"}
MAX_IMAGE_BYTES = 30 * 1024 * 1024


@dataclass
class TitleMapping:
    vndb_id: str
    selection_index: int
    steam_ids: list[str] = field(default_factory=list)
    bangumi_ids: list[str] = field(default_factory=list)
    names: list[str] = field(default_factory=list)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect Paparu's visual-novel image dataset."
    )
    parser.add_argument("--mapping", type=Path, default=DEFAULT_MAPPING)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--limit",
        type=int,
        default=200,
        help="Number of unique VNDB works to select (default: 200).",
    )
    parser.add_argument(
        "--request-delay",
        type=float,
        default=1.2,
        help="Delay between requests to each public service.",
    )
    parser.add_argument(
        "--refresh-sources",
        action="store_true",
        help="Fetch source metadata again instead of reusing saved responses.",
    )
    parser.add_argument(
        "--retry-failed",
        action="store_true",
        help="Retry assets previously marked as failed.",
    )
    parser.add_argument(
        "--skip-steam",
        action="store_true",
        help="Do not request Steam store data.",
    )
    parser.add_argument(
        "--skip-bangumi",
        action="store_true",
        help="Do not request Bangumi subject data.",
    )
    parser.add_argument(
        "--skip-download",
        action="store_true",
        help="Collect URLs and metadata without downloading image files.",
    )
    parser.add_argument(
        "--download-workers",
        type=int,
        default=4,
        help="Concurrent image downloads (default: 4).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print the selected works; do not access the network.",
    )
    return parser.parse_args()


def normalized_ids(value: Any) -> list[str]:
    if value is None:
        return []
    return re.findall(r"\d+", str(value))


def load_mappings(path: Path, limit: int) -> list[TitleMapping]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    grouped: dict[str, TitleMapping] = {}
    for entry in payload.get("entries", []):
        vndb_id = str(entry.get("vndb", "")).strip().lower()
        if not re.fullmatch(r"v\d+", vndb_id):
            continue
        mapping = grouped.get(vndb_id)
        if mapping is None:
            mapping = TitleMapping(
                vndb_id=vndb_id,
                selection_index=len(grouped),
            )
            grouped[vndb_id] = mapping
        for steam_id in normalized_ids(entry.get("steam")):
            if steam_id not in mapping.steam_ids:
                mapping.steam_ids.append(steam_id)
        for bangumi_id in normalized_ids(entry.get("bangumi")):
            if bangumi_id not in mapping.bangumi_ids:
                mapping.bangumi_ids.append(bangumi_id)
        for name in entry.get("names", []):
            value = str(name).strip()
            if value and value not in mapping.names:
                mapping.names.append(value)

    selected = [
        mapping
        for mapping in grouped.values()
        if mapping.steam_ids or mapping.bangumi_ids
    ][:limit]
    for index, mapping in enumerate(selected):
        mapping.selection_index = index
    return selected


class DatasetStore:
    def __init__(self, output: Path) -> None:
        self.output = output
        self.output.mkdir(parents=True, exist_ok=True)
        self.images = output / "images"
        self.manual = output / "manual"
        self.images.mkdir(exist_ok=True)
        self.manual.mkdir(exist_ok=True)
        self.connection = sqlite3.connect(output / "dataset.sqlite3")
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("PRAGMA synchronous=NORMAL")
        self.connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS titles (
                vndb_id TEXT PRIMARY KEY,
                selection_index INTEGER NOT NULL,
                steam_ids_json TEXT NOT NULL,
                bangumi_ids_json TEXT NOT NULL,
                names_json TEXT NOT NULL,
                vndb_payload_json TEXT,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS external_payloads (
                provider TEXT NOT NULL,
                external_id TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY(provider, external_id)
            );
            CREATE TABLE IF NOT EXISTS characters (
                character_id TEXT PRIMARY KEY,
                title_id TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS assets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                vndb_id TEXT NOT NULL,
                provider TEXT NOT NULL,
                kind TEXT NOT NULL,
                source_id TEXT NOT NULL DEFAULT '',
                url TEXT NOT NULL,
                thumbnail_url TEXT,
                local_path TEXT,
                sha256 TEXT,
                status TEXT NOT NULL DEFAULT 'pending',
                error TEXT,
                UNIQUE(vndb_id, provider, kind, url)
            );
            CREATE INDEX IF NOT EXISTS assets_status_idx ON assets(status);
            CREATE INDEX IF NOT EXISTS assets_title_idx ON assets(vndb_id);
            """
        )
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()

    def save_title(self, mapping: TitleMapping, payload: dict[str, Any] | None) -> None:
        self.connection.execute(
            """
            INSERT INTO titles(
                vndb_id, selection_index, steam_ids_json, bangumi_ids_json,
                names_json, vndb_payload_json
            ) VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(vndb_id) DO UPDATE SET
                selection_index=excluded.selection_index,
                steam_ids_json=excluded.steam_ids_json,
                bangumi_ids_json=excluded.bangumi_ids_json,
                names_json=excluded.names_json,
                vndb_payload_json=COALESCE(excluded.vndb_payload_json, titles.vndb_payload_json),
                updated_at=CURRENT_TIMESTAMP
            """,
            (
                mapping.vndb_id,
                mapping.selection_index,
                json.dumps(mapping.steam_ids, separators=(",", ":")),
                json.dumps(mapping.bangumi_ids, separators=(",", ":")),
                json.dumps(mapping.names, ensure_ascii=False, separators=(",", ":")),
                None
                if payload is None
                else json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            ),
        )
        self.connection.commit()

    def title_payload(self, vndb_id: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            "SELECT vndb_payload_json FROM titles WHERE vndb_id = ?", (vndb_id,)
        ).fetchone()
        if row is None or not row[0]:
            return None
        return json.loads(row[0])

    def save_external(self, provider: str, external_id: str, payload: dict[str, Any]) -> None:
        self.connection.execute(
            """
            INSERT INTO external_payloads(provider, external_id, payload_json)
            VALUES(?, ?, ?)
            ON CONFLICT(provider, external_id) DO UPDATE SET
                payload_json=excluded.payload_json,
                updated_at=CURRENT_TIMESTAMP
            """,
            (
                provider,
                external_id,
                json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            ),
        )
        self.connection.commit()

    def has_external(self, provider: str, external_id: str) -> bool:
        return self.connection.execute(
            "SELECT 1 FROM external_payloads WHERE provider = ? AND external_id = ?",
            (provider, external_id),
        ).fetchone() is not None

    def external_payload(self, provider: str, external_id: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            "SELECT payload_json FROM external_payloads WHERE provider = ? AND external_id = ?",
            (provider, external_id),
        ).fetchone()
        if row is None:
            return None
        return json.loads(row[0])

    def save_character(self, character_id: str, title_id: str, payload: dict[str, Any]) -> None:
        self.connection.execute(
            """
            INSERT INTO characters(character_id, title_id, payload_json)
            VALUES(?, ?, ?)
            ON CONFLICT(character_id) DO UPDATE SET
                title_id=excluded.title_id,
                payload_json=excluded.payload_json,
                updated_at=CURRENT_TIMESTAMP
            """,
            (
                character_id,
                title_id,
                json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            ),
        )

    def add_asset(
        self,
        *,
        vndb_id: str,
        provider: str,
        kind: str,
        source_id: str,
        url: str,
        thumbnail_url: str | None,
    ) -> None:
        if not url:
            return
        self.connection.execute(
            """
            INSERT OR IGNORE INTO assets(
                vndb_id, provider, kind, source_id, url, thumbnail_url
            ) VALUES(?, ?, ?, ?, ?, ?)
            """,
            (vndb_id, provider, kind, source_id, url, thumbnail_url),
        )

    def commit(self) -> None:
        self.connection.commit()

    def pending_assets(self, retry_failed: bool) -> Iterator[sqlite3.Row]:
        statuses = "('pending','failed')" if retry_failed else "('pending')"
        cursor = self.connection.execute(
            f"SELECT * FROM assets WHERE status IN {statuses} ORDER BY id"
        )
        yield from cursor

    def mark_asset(
        self,
        asset_id: int,
        *,
        status: str,
        local_path: str | None = None,
        sha256: str | None = None,
        error: str | None = None,
    ) -> None:
        self.connection.execute(
            """
            UPDATE assets
            SET status = ?, local_path = COALESCE(?, local_path),
                sha256 = COALESCE(?, sha256), error = ?
            WHERE id = ?
            """,
            (status, local_path, sha256, error, asset_id),
        )
        self.connection.commit()

    def import_manual_asset(
        self,
        *,
        vndb_id: str,
        source: Path,
        destination: Path,
        digest: str,
    ) -> None:
        url = f"file://{source.resolve()}"
        self.add_asset(
            vndb_id=vndb_id,
            provider="manual",
            kind="manual",
            source_id=source.name,
            url=url,
            thumbnail_url=None,
        )
        self.connection.execute(
            """
            UPDATE assets
            SET local_path = ?, sha256 = ?, status = 'downloaded', error = NULL
            WHERE vndb_id = ? AND provider = 'manual' AND kind = 'manual' AND url = ?
            """,
            (str(destination.relative_to(self.output)), digest, vndb_id, url),
        )
        self.connection.commit()

    def export_jsonl(self) -> None:
        exports = {
            "titles.jsonl": "SELECT * FROM titles ORDER BY selection_index",
            "assets.jsonl": "SELECT * FROM assets ORDER BY id",
            "characters.jsonl": "SELECT * FROM characters ORDER BY character_id",
            "external-payloads.jsonl": "SELECT * FROM external_payloads ORDER BY provider, external_id",
        }
        for filename, query in exports.items():
            temporary = self.output / f".{filename}.partial"
            with temporary.open("w", encoding="utf-8") as file:
                for row in self.connection.execute(query):
                    file.write(json.dumps(dict(row), ensure_ascii=False, separators=(",", ":")))
                    file.write("\n")
            temporary.replace(self.output / filename)


def request_json(
    url: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    delay: float,
    retries: int = 5,
) -> dict[str, Any]:
    body = None
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    if payload is not None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        headers["Content-Type"] = "application/json"
    backoff = max(3.0, delay)
    for attempt in range(retries + 1):
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                result = json.load(response)
            if delay > 0:
                time.sleep(delay)
            return result
        except urllib.error.HTTPError as error:
            if error.code == 404:
                raise
            temporary = error.code in {408, 425, 429, 500, 502, 503, 504}
            if not temporary or attempt >= retries:
                raise
            retry_after = error.headers.get("Retry-After")
            wait = max(backoff, float(retry_after or 0))
            print(f"HTTP {error.code}; retrying in {wait:.0f}s", file=sys.stderr)
            time.sleep(wait)
            backoff = min(300.0, backoff * 1.8)
        except (
            TimeoutError,
            socket.timeout,
            http.client.IncompleteRead,
            http.client.RemoteDisconnected,
            ConnectionResetError,
            urllib.error.URLError,
            json.JSONDecodeError,
        ) as error:
            if attempt >= retries:
                raise
            print(
                f"Temporary {type(error).__name__}; retrying in {backoff:.0f}s",
                file=sys.stderr,
            )
            time.sleep(backoff)
            backoff = min(300.0, backoff * 1.8)
    raise RuntimeError("request retry loop ended unexpectedly")


def request_bytes(url: str, delay: float) -> tuple[bytes, str | None]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=180) as response:
        content_type = response.headers.get_content_type()
        chunks: list[bytes] = []
        size = 0
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_IMAGE_BYTES:
                raise ValueError(f"image exceeds {MAX_IMAGE_BYTES} bytes")
            chunks.append(chunk)
    if delay > 0:
        time.sleep(delay)
    return b"".join(chunks), content_type


def image_url(value: Any) -> tuple[str, str | None]:
    if not isinstance(value, dict):
        return "", None
    return str(value.get("url") or ""), value.get("thumbnail")


def vndb_id_filter(ids: list[str]) -> list[Any]:
    predicates: list[list[str]] = [["id", "=", value] for value in ids]
    if len(predicates) == 1:
        return predicates[0]
    return ["or", *predicates]


def record_vndb_payload(
    store: DatasetStore,
    mapping: TitleMapping,
    payload: dict[str, Any],
) -> None:
    store.save_title(mapping, payload)
    cover_url, cover_thumbnail = image_url(payload.get("image"))
    store.add_asset(
        vndb_id=mapping.vndb_id,
        provider="vndb",
        kind="cover",
        source_id=str(payload.get("image", {}).get("id", "")),
        url=cover_url,
        thumbnail_url=cover_thumbnail,
    )
    for screenshot in payload.get("screenshots", []) or []:
        url, thumbnail = image_url(screenshot)
        store.add_asset(
            vndb_id=mapping.vndb_id,
            provider="vndb",
            kind="screenshot",
            source_id=str(screenshot.get("id", "")),
            url=url,
            thumbnail_url=thumbnail,
        )
    for voice_actor in payload.get("va", []) or []:
        character = voice_actor.get("character") or {}
        character_id = str(character.get("id") or "")
        if not character_id:
            continue
        store.save_character(character_id, mapping.vndb_id, character)
        url, thumbnail = image_url(character.get("image"))
        store.add_asset(
            vndb_id=mapping.vndb_id,
            provider="vndb",
            kind="character",
            source_id=character_id,
            url=url,
            thumbnail_url=thumbnail,
        )


def collect_vndb(
    store: DatasetStore,
    mappings: list[TitleMapping],
    delay: float,
    refresh: bool,
) -> None:
    ids = [mapping.vndb_id for mapping in mappings]
    for start in range(0, len(ids), 100):
        chunk = ids[start : start + 100]
        if not refresh and all(store.title_payload(vndb_id) for vndb_id in chunk):
            for mapping in mappings[start : start + len(chunk)]:
                payload = store.title_payload(mapping.vndb_id)
                if payload is not None:
                    record_vndb_payload(store, mapping, payload)
            store.commit()
            print(f"VNDB: using saved batch {start + 1}-{start + len(chunk)}")
            continue
        response = request_json(
            f"{VNDB_API}/vn",
            method="POST",
            payload={
                "filters": vndb_id_filter(chunk),
                "fields": VNDB_FIELDS,
                "results": len(chunk),
                "count": False,
            },
            delay=delay,
        )
        by_id = {str(item.get("id")): item for item in response.get("results", [])}
        for mapping in mappings[start : start + len(chunk)]:
            payload = by_id.get(mapping.vndb_id)
            if payload is None:
                store.save_title(mapping, None)
                print(f"VNDB: {mapping.vndb_id} was not returned", file=sys.stderr)
                continue
            record_vndb_payload(store, mapping, payload)
        store.commit()
        print(f"VNDB: processed {start + len(chunk)}/{len(ids)} works")


def collect_steam(
    store: DatasetStore,
    mappings: list[TitleMapping],
    delay: float,
    refresh: bool,
) -> None:
    steam_to_titles: dict[str, list[str]] = {}
    for mapping in mappings:
        for steam_id in mapping.steam_ids:
            steam_to_titles.setdefault(steam_id, []).append(mapping.vndb_id)
    for index, steam_id in enumerate(steam_to_titles, 1):
        data = None if refresh else store.external_payload("steam", steam_id)
        if data is None:
            url = f"{STEAM_DETAILS_API}?appids={urllib.parse.quote(steam_id)}&l=english&cc=us"
            try:
                response = request_json(url, delay=delay)
            except urllib.error.HTTPError as error:
                print(f"Steam: app {steam_id} failed with HTTP {error.code}", file=sys.stderr)
                continue
            except Exception as error:
                print(
                    f"Steam: app {steam_id} failed with {type(error).__name__}: {error}",
                    file=sys.stderr,
                )
                continue
            app = response.get(steam_id, {})
            data = app.get("data") if app.get("success") else None
        if not isinstance(data, dict):
            print(f"Steam: app {steam_id} has no store data", file=sys.stderr)
            continue
        if refresh or not store.has_external("steam", steam_id):
            store.save_external("steam", steam_id, data)
        for vndb_id in steam_to_titles[steam_id]:
            for screenshot in data.get("screenshots", []) or []:
                url_value = str(screenshot.get("path_full") or "")
                thumbnail = screenshot.get("path_thumbnail")
                store.add_asset(
                    vndb_id=vndb_id,
                    provider="steam",
                    kind="screenshot",
                    source_id=str(screenshot.get("id", "")),
                    url=url_value,
                    thumbnail_url=thumbnail,
                )
            for key in ("header_image", "capsule_image", "capsule_imagev5"):
                url_value = str(data.get(key) or "")
                store.add_asset(
                    vndb_id=vndb_id,
                    provider="steam",
                    kind="cover",
                    source_id=key,
                    url=url_value,
                    thumbnail_url=None,
                )
        store.commit()
        print(f"Steam: processed {steam_id} ({index}/{len(steam_to_titles)})")


def collect_bangumi(
    store: DatasetStore,
    mappings: list[TitleMapping],
    delay: float,
    refresh: bool,
) -> None:
    bangumi_to_titles: dict[str, list[str]] = {}
    for mapping in mappings:
        for bangumi_id in mapping.bangumi_ids:
            bangumi_to_titles.setdefault(bangumi_id, []).append(mapping.vndb_id)
    for index, bangumi_id in enumerate(bangumi_to_titles, 1):
        data = None if refresh else store.external_payload("bangumi", bangumi_id)
        if data is None:
            try:
                data = request_json(f"{BANGUMI_SUBJECT_API}/{bangumi_id}", delay=delay)
            except urllib.error.HTTPError as error:
                print(f"Bangumi: subject {bangumi_id} failed with HTTP {error.code}", file=sys.stderr)
                continue
            except Exception as error:
                print(
                    f"Bangumi: subject {bangumi_id} failed with {type(error).__name__}: {error}",
                    file=sys.stderr,
                )
                continue
            store.save_external("bangumi", bangumi_id, data)
        images = data.get("images") or {}
        for vndb_id in bangumi_to_titles[bangumi_id]:
            url_value = str(images.get("large") or images.get("common") or "")
            if url_value:
                store.add_asset(
                    vndb_id=vndb_id,
                    provider="bangumi",
                    kind="cover",
                    source_id=bangumi_id,
                    url=url_value,
                    thumbnail_url=images.get("medium") or images.get("small"),
                )
        store.commit()
        print(f"Bangumi: processed {bangumi_id} ({index}/{len(bangumi_to_titles)})")


def extension_for(url: str, content_type: str | None) -> str:
    suffix = Path(urllib.parse.urlparse(url).path).suffix.lower()
    if suffix in IMAGE_EXTENSIONS:
        return ".jpg" if suffix == ".jpeg" else suffix
    return {
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
        "image/avif": ".avif",
        "image/gif": ".gif",
    }.get(content_type or "", ".img")


def download_one(row: sqlite3.Row, delay: float) -> tuple[int, str, bytes | None, str | None, str | None]:
    try:
        data, content_type = request_bytes(str(row["url"]), delay)
        return int(row["id"]), "downloaded", data, content_type, None
    except urllib.error.HTTPError as error:
        status = "missing" if error.code == 404 else "failed"
        return int(row["id"]), status, None, None, f"HTTP {error.code}"
    except Exception as error:
        return int(row["id"]), "failed", None, None, str(error)


def save_downloaded_asset(
    store: DatasetStore,
    row: sqlite3.Row,
    data: bytes,
    content_type: str | None,
) -> None:
    digest = hashlib.sha256(data).hexdigest()
    existing = store.connection.execute(
        "SELECT local_path FROM assets WHERE sha256 = ? AND status = 'downloaded' LIMIT 1",
        (digest,),
    ).fetchone()
    if existing and existing[0]:
        store.mark_asset(
            int(row["id"]),
            status="downloaded",
            local_path=str(existing[0]),
            sha256=digest,
        )
        return
    relative = Path("images") / str(row["vndb_id"]) / str(row["provider"])
    directory = store.output / relative
    directory.mkdir(parents=True, exist_ok=True)
    filename = f"{int(row['id']):08d}{extension_for(str(row['url']), content_type)}"
    destination = directory / filename
    temporary = destination.with_suffix(destination.suffix + ".partial")
    temporary.write_bytes(data)
    temporary.replace(destination)
    store.mark_asset(
        int(row["id"]),
        status="downloaded",
        local_path=str(destination.relative_to(store.output)),
        sha256=digest,
    )


def download_assets(
    store: DatasetStore,
    delay: float,
    retry_failed: bool,
    workers: int,
) -> None:
    rows = list(store.pending_assets(retry_failed))
    print(f"Images: {len(rows)} pending downloads ({workers} workers)")
    by_id = {int(row["id"]): row for row in rows}
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(download_one, row, delay) for row in rows]
        for position, future in enumerate(as_completed(futures), 1):
            asset_id, status, data, content_type, error = future.result()
            row = by_id[asset_id]
            if status == "downloaded" and data is not None:
                save_downloaded_asset(store, row, data, content_type)
            else:
                store.mark_asset(asset_id, status=status, error=error)
            if position % 25 == 0 or position == len(rows):
                print(f"Images: processed {position}/{len(rows)}")


def import_manual_images(store: DatasetStore) -> None:
    count = 0
    for title_directory in sorted(store.manual.iterdir()):
        if not title_directory.is_dir() or not re.fullmatch(r"v\d+", title_directory.name):
            continue
        vndb_id = title_directory.name.lower()
        for source in sorted(title_directory.rglob("*")):
            if not source.is_file() or source.suffix.lower() not in IMAGE_EXTENSIONS:
                continue
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            destination_directory = store.images / vndb_id / "manual"
            destination_directory.mkdir(parents=True, exist_ok=True)
            destination = destination_directory / f"{digest[:24]}{source.suffix.lower()}"
            if not destination.exists():
                shutil.copy2(source, destination)
            store.import_manual_asset(
                vndb_id=vndb_id,
                source=source,
                destination=destination,
                digest=digest,
            )
            count += 1
    if count:
        print(f"Manual: indexed {count} images")


def write_selection(output: Path, mappings: list[TitleMapping]) -> None:
    path = output / "selected_titles.json"
    temporary = path.with_suffix(".json.partial")
    temporary.write_text(
        json.dumps(
            [
                {
                    "vndb_id": mapping.vndb_id,
                    "selection_index": mapping.selection_index,
                    "steam_ids": mapping.steam_ids,
                    "bangumi_ids": mapping.bangumi_ids,
                    "names": mapping.names,
                }
                for mapping in mappings
            ],
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    temporary.replace(path)


def main() -> int:
    arguments = parse_arguments()
    if arguments.limit < 1:
        print("--limit must be at least 1", file=sys.stderr)
        return 2
    if arguments.request_delay < 0:
        print("--request-delay must not be negative", file=sys.stderr)
        return 2
    if arguments.download_workers < 1:
        print("--download-workers must be at least 1", file=sys.stderr)
        return 2
    try:
        mappings = load_mappings(arguments.mapping, arguments.limit)
    except (OSError, json.JSONDecodeError, KeyError) as error:
        print(f"Could not read mapping file: {error}", file=sys.stderr)
        return 2
    if not mappings:
        print("No mapped VNDB works were found.", file=sys.stderr)
        return 2
    print(
        f"Selected {len(mappings)} unique works from {arguments.mapping} "
        f"({sum(bool(item.steam_ids) for item in mappings)} with Steam, "
        f"{sum(bool(item.bangumi_ids) for item in mappings)} with Bangumi)."
    )
    if arguments.dry_run:
        for mapping in mappings[:20]:
            print(
                f"{mapping.selection_index + 1:03d} {mapping.vndb_id} "
                f"steam={','.join(mapping.steam_ids) or '-'} "
                f"bangumi={','.join(mapping.bangumi_ids) or '-'} "
                f"name={mapping.names[0] if mapping.names else '-'}"
            )
        return 0

    store = DatasetStore(arguments.output)
    try:
        write_selection(arguments.output, mappings)
        for mapping in mappings:
            store.save_title(mapping, None)
        if not arguments.skip_download:
            collect_vndb(store, mappings, arguments.request_delay, arguments.refresh_sources)
            if not arguments.skip_steam:
                collect_steam(store, mappings, arguments.request_delay, arguments.refresh_sources)
            if not arguments.skip_bangumi:
                collect_bangumi(store, mappings, arguments.request_delay, arguments.refresh_sources)
        import_manual_images(store)
        if not arguments.skip_download:
            download_assets(
                store,
                arguments.request_delay,
                arguments.retry_failed,
                arguments.download_workers,
            )
        store.export_jsonl()
        title_count = store.connection.execute("SELECT COUNT(*) FROM titles").fetchone()[0]
        asset_count = store.connection.execute("SELECT COUNT(*) FROM assets").fetchone()[0]
        downloaded_count = store.connection.execute(
            "SELECT COUNT(*) FROM assets WHERE status = 'downloaded'"
        ).fetchone()[0]
        print(
            f"Done: {title_count} titles, {asset_count} assets, "
            f"{downloaded_count} downloaded. Output: {arguments.output}"
        )
    except KeyboardInterrupt:
        print("Interrupted. SQLite state is saved; rerun to continue.", file=sys.stderr)
        return 130
    finally:
        store.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
