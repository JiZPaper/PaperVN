#!/usr/bin/env python3
"""Build PaperVN's downloadable recommendation corpus and collaborative embedding.

The crawler is deliberately slow and resumable. VN and character pages are
deduplicated in SQLite. The public vote dump is factorized with shuffled
per-vote SGD (user and item biases plus a low-rank interaction), and the
result is evaluated on held-out public users exactly the way the app folds a
library in. The build fails instead of publishing a model that does not beat
the bias-only baseline. No VNDB user IDs are published in the model.
"""

from __future__ import annotations

import argparse
import gzip
import heapq
import http.client
import json
import math
import operator
import os
import random
import sqlite3
import socket
import statistics
import sys
import tempfile
import time
import urllib.error
import urllib.request
from array import array
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Iterator


API_ROOT = "https://api.vndb.org/kana"
VOTES_URL = "https://dl.vndb.org/dump/vndb-votes-latest.gz"
VN_FIELDS = (
    "title,titles{lang,title,latin,official,main},released,languages,platforms,"
    "image{url,thumbnail,sexual,violence},length,"
    "length_minutes,rating,votecount,tags{id,name,rating,spoiler,lie,category},"
    "developers{id,name},relations{id,relation,relation_official}"
)
CHARACTER_FIELDS = (
    "name,image{url,dims,sexual,violence},vns{spoiler,role,id,title},"
    "traits{spoiler,lie,id,name,group_name,sexual}"
)
VN_CONTENT_SCHEMA_VERSION = "2"
CHARACTER_CONTENT_SCHEMA_VERSION = "3"

# The app only uses item factors when the model header carries this block;
# models from older builders were untrained noise.
COLLABORATIVE_MODEL_VERSION = 1
LEARNING_RATE = 0.015
BIAS_LEARNING_RATE = 0.01
LEARNING_RATE_DECAY = 0.96
FACTOR_REGULARIZATION = 0.03
BIAS_REGULARIZATION = 0.01
USER_INITIAL_SCALE = 0.1
# Items start near zero, so titles with only a few votes stay short instead of
# keeping a random direction. This replaces any minimum vote count.
ITEM_INITIAL_SCALE = 0.01
# In units of the unscaled factors; multiplied by factorScale² after scaling.
USER_REGULARIZATION_CANDIDATES = (0.5, 1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0)
INTERCEPT_REGULARIZATION = 0.01
# The app scores titles by p·q + biasWeight × item bias. Weight 0 keeps only
# the personal part; larger weights push the same well-liked titles to
# everyone (on held-out users, 0.25 put one title into 76% of top-20 lists),
# so the weight with the best held-out recall is chosen from these.
BIAS_WEIGHT_CANDIDATES = (0.0, 0.0625, 0.125)
# Item biases of titles with few votes come from a handful of fans and are
# extreme (a 22-vote title had the second-largest bias). Shrink them like a
# Bayesian average worth this many votes.
BIAS_SHRINKAGE_VOTES = 50
RECALL_DEPTH = 100
LIKED_SIGNAL = 0.3
# VNDB本地推荐算法V2 treats a collaborative score of 0.72 as reliable
# evidence; calibrate so a typical user's top 0.1% of titles reaches it.
RELIABLE_COLLABORATIVE_SCORE = 0.72
RELIABLE_SCORE_QUANTILE = 0.001
SERIES_RELATIONS = {"seq", "preq", "fan", "side", "ser"}
EVALUATION_USERS_FILENAME = "evaluation-users.json.gz"


def parse_arguments() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Build the offline PaperVN recommendation model."
    )
    parser.add_argument(
        "--work-directory",
        type=Path,
        default=root / ".build" / "vndb-recommendation-model",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=(
            root
            / ".build"
            / "vndb-recommendation-model"
            / "VNDBRecommendationModel.json.gz"
        ),
    )
    parser.add_argument("--request-delay", type=float, default=3.2)
    parser.add_argument("--factors", type=int, default=48)
    parser.add_argument(
        "--epochs",
        type=int,
        default=25,
        help="Shuffled SGD passes over the public votes.",
    )
    parser.add_argument(
        "--holdout-users",
        type=int,
        default=3_000,
        help="Public users whose votes are partly held out to evaluate the model.",
    )
    parser.add_argument("--seed", type=int, default=20_261_005)
    parser.add_argument(
        "--base-model",
        type=Path,
        help=(
            "Reuse the visual novels and characters of an existing model file "
            "instead of crawling the API; only the collaborative part is retrained."
        ),
    )
    parser.add_argument(
        "--refresh-content",
        action="store_true",
        help="Discard content page checkpoints and fetch all pages again.",
    )
    parser.add_argument(
        "--refresh-votes",
        action="store_true",
        help="Download the latest public vote dump even if one is present.",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help=(
            "Train on synthetic votes with a planted structure and check that it "
            "is recovered, without network access."
        ),
    )
    return parser.parse_args()


class CorpusStore:
    def __init__(self, path: Path) -> None:
        self.connection = sqlite3.connect(path)
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("PRAGMA synchronous=NORMAL")
        self.connection.execute(
            "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
        )
        self.connection.execute(
            "CREATE TABLE IF NOT EXISTS visual_novels "
            "(id TEXT PRIMARY KEY, payload TEXT NOT NULL)"
        )
        self.connection.execute(
            "CREATE TABLE IF NOT EXISTS characters "
            "(id TEXT PRIMARY KEY, payload TEXT NOT NULL)"
        )
        self.connection.commit()

    def metadata(self, key: str) -> str | None:
        row = self.connection.execute(
            "SELECT value FROM metadata WHERE key = ?", (key,)
        ).fetchone()
        return None if row is None else str(row[0])

    def set_metadata(self, key: str, value: str) -> None:
        self.connection.execute(
            "INSERT OR REPLACE INTO metadata(key, value) VALUES(?, ?)",
            (key, value),
        )
        self.connection.commit()

    def reset_endpoint(self, name: str, table: str) -> None:
        self.connection.execute(f"DELETE FROM {table}")
        self.connection.execute(
            "DELETE FROM metadata WHERE key IN (?, ?)",
            (f"{name}.next_page", f"{name}.complete"),
        )
        self.connection.commit()

    def require_endpoint_schema(
        self,
        name: str,
        table: str,
        version: str,
    ) -> None:
        key = f"{name}.schema_version"
        if self.metadata(key) == version:
            return
        if self.count(table) > 0:
            print(
                f"{name}: saved content schema is stale; "
                "refetching this endpoint."
            )
            self.reset_endpoint(name, table)
        self.set_metadata(key, version)

    def store_page(self, table: str, items: Iterable[dict[str, Any]]) -> int:
        rows = [
            (
                str(item["id"]),
                json.dumps(item, ensure_ascii=False, separators=(",", ":")),
            )
            for item in items
        ]
        self.connection.executemany(
            f"INSERT OR REPLACE INTO {table}(id, payload) VALUES(?, ?)", rows
        )
        self.connection.commit()
        return len(rows)

    def rows(self, table: str) -> Iterator[dict[str, Any]]:
        cursor = self.connection.execute(
            f"SELECT payload FROM {table} ORDER BY CAST(SUBSTR(id, 2) AS INTEGER)"
        )
        for (payload,) in cursor:
            yield json.loads(payload)

    def count(self, table: str) -> int:
        return int(self.connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])


class StoreContent:
    """Visual novels and characters crawled into the SQLite corpus."""

    def __init__(self, store: CorpusStore) -> None:
        self.store = store

    def visual_novels(self) -> Iterator[dict[str, Any]]:
        return self.store.rows("visual_novels")

    def characters(self) -> Iterator[dict[str, Any]]:
        for item in self.store.rows("characters"):
            yield {
                "id": item["id"],
                "name": item["name"],
                "image": item.get("image"),
                "visualNovels": item.get("vns") or [],
                "traits": item.get("traits") or [],
            }

    def release(self) -> None:
        pass


class ModelContent:
    """Visual novels and characters taken from a previously built model."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._model: dict[str, Any] | None = None

    def _load(self) -> dict[str, Any]:
        if self._model is None:
            with gzip.open(self.path, "rt", encoding="utf-8") as file:
                self._model = json.load(file)
        return self._model

    def visual_novels(self) -> Iterator[dict[str, Any]]:
        return iter(self._load()["visualNovels"])

    def characters(self) -> Iterator[dict[str, Any]]:
        return iter(self._load()["characters"])

    def release(self) -> None:
        self._model = None


def request_json(
    endpoint: str,
    payload: dict[str, Any],
    delay: float,
) -> dict[str, Any]:
    encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        f"{API_ROOT}/{endpoint}",
        data=encoded,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "PaperVN-OfflineRecommendationBuilder/1.0",
        },
        method="POST",
    )
    backoff = max(delay, 3.0)
    while True:
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                result = json.load(response)
            time.sleep(max(0, delay))
            return result
        except urllib.error.HTTPError as error:
            if error.code not in {429, 500, 502, 503, 504}:
                raise
            retry_after = error.headers.get("Retry-After")
            wait = max(backoff, float(retry_after or 0))
        except (
            TimeoutError,
            socket.timeout,
            http.client.IncompleteRead,
            http.client.RemoteDisconnected,
            ConnectionResetError,
            urllib.error.URLError,
            json.JSONDecodeError,
        ) as error:
            wait = backoff
            print(
                "Request response was interrupted or invalid; "
                f"retrying after {wait:.0f}s ({type(error).__name__})."
            )
            time.sleep(wait)
            backoff = min(300.0, backoff * 1.8)
            continue
        print(f"Request paused for {wait:.0f}s after a temporary failure.")
        time.sleep(wait)
        backoff = min(300.0, backoff * 1.8)


def fetch_endpoint(
    store: CorpusStore,
    name: str,
    table: str,
    endpoint: str,
    fields: str,
    filters: Any,
    delay: float,
    refresh: bool,
) -> None:
    if refresh:
        store.reset_endpoint(name, table)
    if store.metadata(f"{name}.complete") == "1":
        print(f"{name}: using {store.count(table)} saved records.")
        return

    page = int(store.metadata(f"{name}.next_page") or "1")
    while True:
        response = request_json(
            endpoint,
            {
                "filters": filters,
                "fields": fields,
                "sort": "id",
                "reverse": False,
                "results": 100,
                "page": page,
                "count": False,
            },
            delay,
        )
        count = store.store_page(table, response.get("results", []))
        more = bool(response.get("more", False))
        store.set_metadata(f"{name}.next_page", str(page + 1))
        print(
            f"{name}: page {page}, {count} records, "
            f"{store.count(table)} unique total."
        )
        if not more:
            store.set_metadata(f"{name}.complete", "1")
            return
        page += 1


def download_votes(destination: Path, refresh: bool) -> None:
    if destination.exists() and not refresh:
        print(f"votes: using {destination}.")
        return
    partial = destination.with_suffix(destination.suffix + ".partial")
    backoff = 10.0
    print("votes: downloading the VNDB public vote dump...")
    while True:
        offset = partial.stat().st_size if partial.exists() else 0
        headers = {"User-Agent": "PaperVN-OfflineRecommendationBuilder/1.0"}
        if offset:
            headers["Range"] = f"bytes={offset}-"
        request = urllib.request.Request(VOTES_URL, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=900) as response:
                resumed = offset > 0 and response.getcode() == 206
                if not resumed:
                    offset = 0
                mode = "ab" if resumed else "wb"
                expected_total: int | None = None
                content_range = response.headers.get("Content-Range")
                if content_range and "/" in content_range:
                    total_text = content_range.rsplit("/", 1)[1]
                    if total_text.isdigit():
                        expected_total = int(total_text)
                elif response.headers.get("Content-Length", "").isdigit():
                    expected_total = offset + int(response.headers["Content-Length"])
                with partial.open(mode) as file:
                    while chunk := response.read(1024 * 1024):
                        file.write(chunk)
                if expected_total is not None and partial.stat().st_size < expected_total:
                    raise ConnectionError(
                        f"download ended at {partial.stat().st_size} bytes; "
                        f"expected {expected_total}"
                    )
            os.replace(partial, destination)
            return
        except urllib.error.HTTPError as error:
            if error.code == 416 and partial.exists():
                partial.unlink()
                continue
            if error.code not in {429, 500, 502, 503, 504}:
                raise
            print(
                f"votes: temporary HTTP {error.code}; retrying after "
                f"{backoff:.0f}s."
            )
        except (
            TimeoutError,
            socket.timeout,
            http.client.IncompleteRead,
            http.client.RemoteDisconnected,
            ConnectionResetError,
            ConnectionError,
            urllib.error.URLError,
        ) as error:
            print(
                "votes: response was interrupted; "
                f"retrying after {backoff:.0f}s ({type(error).__name__})."
            )
        time.sleep(backoff)
        backoff = min(300.0, backoff * 1.8)


def vote_rows(path: Path) -> Iterator[tuple[int, int, int]]:
    with gzip.open(path, "rt", encoding="ascii", errors="strict") as file:
        for line in file:
            fields = line.split()
            if len(fields) < 3:
                continue
            try:
                yield int(fields[0].lstrip("v")), int(fields[1].lstrip("u")), int(fields[2])
            except ValueError:
                continue


def numeric_id(value: str) -> int | None:
    digits = "".join(character for character in value if character.isdigit())
    return int(digits) if digits else None


def related_title_pairs(visual_novels: Iterable[dict[str, Any]]) -> list[tuple[int, int]]:
    """Official sequels, prequels, fandiscs and side stories, used to check the embedding."""
    pairs: set[tuple[int, int]] = set()
    for item in visual_novels:
        source = numeric_id(str(item["id"]))
        for relation in item.get("relations") or []:
            if not relation.get("relation_official") or relation.get("relation") not in SERIES_RELATIONS:
                continue
            target = numeric_id(str(relation["id"]))
            if source is None or target is None or source == target:
                continue
            pairs.add((min(source, target), max(source, target)))
    return sorted(pairs)


def _median_of_sorted(values: list[float]) -> float:
    middle = len(values) // 2
    if len(values) % 2 == 0:
        return (values[middle - 1] + values[middle]) / 2
    return float(values[middle])


def rating_signal_parameters(votes: list[int]) -> tuple[float, float, float]:
    """Center, scale and confidence for one user's votes.

    VNDB离线低秩推荐算法 applies the same transform to the app user's library,
    so training targets and fold-in targets share one scale.
    """
    ordered = sorted(votes)
    if len(ordered) < 5:
        return 70.0, 15.0, 0.75
    median = _median_of_sorted(ordered)
    deviation = _median_of_sorted(sorted(abs(vote - median) for vote in ordered))
    return median, max(10.0, 1.4826 * deviation), 1.0


@dataclass
class VoteDataset:
    item_ids: list[int]
    item_vote_counts: list[int]
    user_count: int
    users: array
    items: array
    signals: array
    # Evaluation users: visible training votes and hidden votes, as (item, signal).
    observed: dict[int, list[tuple[int, float]]]
    held_out: dict[int, list[tuple[int, float]]]
    # The same users as raw (VN number, vote) pairs, for the offline evaluator.
    evaluation_votes: list[tuple[list[tuple[int, int]], list[tuple[int, int]]]]


@dataclass
class CollaborativeModel:
    item_ids: list[int]
    item_vote_counts: list[int]
    factors: list[list[float]]
    biases: list[float]
    parameters: dict[str, Any]
    evaluation_votes: list[tuple[list[tuple[int, int]], list[tuple[int, int]]]]


def load_votes(path: Path, holdout_users: int, seed: int) -> VoteDataset:
    by_user: dict[int, list[tuple[int, int]]] = {}
    for vn_id, user_id, vote in vote_rows(path):
        by_user.setdefault(user_id, []).append((vn_id, vote))
    if not by_user:
        raise RuntimeError(
            "The VNDB public vote dump contained no parseable ratings. "
            "The dump format may have changed."
        )

    rng = random.Random(seed)
    eligible = sorted(user for user, votes in by_user.items() if len(votes) >= 20)
    evaluation = set(rng.sample(eligible, min(holdout_users, len(eligible))))
    item_index: dict[int, int] = {}
    users, items, signals = array("i"), array("i"), array("d")
    observed: dict[int, list[tuple[int, float]]] = {}
    held_out: dict[int, list[tuple[int, float]]] = {}
    evaluation_votes: list[tuple[list[tuple[int, int]], list[tuple[int, int]]]] = []
    user_count = 0
    for user_id in sorted(by_user):
        votes = by_user[user_id]
        if len(votes) < 2:
            continue
        hidden: list[tuple[int, int]] = []
        if user_id in evaluation:
            votes = votes[:]
            rng.shuffle(votes)
            cut = max(2, len(votes) // 5)
            hidden, votes = votes[:cut], votes[cut:]
        center, scale, confidence = rating_signal_parameters([vote for _, vote in votes])
        user = user_count
        user_count += 1
        visible: list[tuple[int, float]] = []
        for vn_id, vote in votes:
            item = item_index.setdefault(vn_id, len(item_index))
            signal = math.tanh((vote - center) / scale) * confidence
            users.append(user)
            items.append(item)
            signals.append(signal)
            visible.append((item, signal))
        if hidden:
            evaluation_votes.append((list(votes), list(hidden)))
            observed[user] = visible
            held_out[user] = [
                (
                    item_index.setdefault(vn_id, len(item_index)),
                    math.tanh((vote - center) / scale) * confidence,
                )
                for vn_id, vote in hidden
            ]
    if not signals:
        raise RuntimeError(
            "The VNDB public vote dump contained no users with at least two ratings."
        )

    item_ids = [0] * len(item_index)
    for vn_id, index in item_index.items():
        item_ids[index] = vn_id
    counts = [0] * len(item_index)
    for item in items:
        counts[item] += 1
    return VoteDataset(
        item_ids=item_ids,
        item_vote_counts=counts,
        user_count=user_count,
        users=users,
        items=items,
        signals=signals,
        observed=observed,
        held_out=held_out,
        evaluation_votes=evaluation_votes,
    )


def train_factors(
    dataset: VoteDataset,
    factor_count: int,
    epochs: int,
    seed: int,
) -> tuple[list[list[float]], list[float]]:
    """Per-vote SGD on signal = mean + user bias + item bias + p_u . q_i.

    Every vote updates its own rows, and the order is reshuffled every epoch.
    The global mean and user biases are not shipped; the app fits a per-user
    intercept that absorbs them.
    """
    rng = random.Random(seed)
    total = len(dataset.signals)
    mean = sum(dataset.signals) / total
    user_factors = [
        [rng.gauss(0.0, USER_INITIAL_SCALE) for _ in range(factor_count)]
        for _ in range(dataset.user_count)
    ]
    item_factors = [
        [rng.gauss(0.0, ITEM_INITIAL_SCALE) for _ in range(factor_count)]
        for _ in dataset.item_ids
    ]
    user_bias = [0.0] * dataset.user_count
    item_bias = [0.0] * len(dataset.item_ids)
    users, items, signals = dataset.users, dataset.items, dataset.signals
    order = list(range(total))
    rate, bias_rate = LEARNING_RATE, BIAS_LEARNING_RATE
    print(
        f"factors: shuffled SGD over {total:,} votes "
        f"({epochs} epochs, rank {factor_count})."
    )
    for epoch in range(epochs):
        started = time.time()
        rng.shuffle(order)
        squared_error = 0.0
        for index in order:
            user = users[index]
            item = items[index]
            p = user_factors[user]
            q = item_factors[item]
            error = signals[index] - (
                mean + user_bias[user] + item_bias[item] + sum(map(operator.mul, p, q))
            )
            squared_error += error * error
            user_bias[user] += bias_rate * (error - BIAS_REGULARIZATION * user_bias[user])
            item_bias[item] += bias_rate * (error - BIAS_REGULARIZATION * item_bias[item])
            user_factors[user] = [
                a + rate * (error * b - FACTOR_REGULARIZATION * a) for a, b in zip(p, q)
            ]
            item_factors[item] = [
                b + rate * (error * a - FACTOR_REGULARIZATION * b) for a, b in zip(p, q)
            ]
        rate *= LEARNING_RATE_DECAY
        bias_rate *= LEARNING_RATE_DECAY
        print(
            f"factors: epoch {epoch + 1}/{epochs}, training RMSE "
            f"{math.sqrt(squared_error / total):.4f} ({time.time() - started:.0f}s)."
        )
    return item_factors, item_bias


def shrink_biases(biases: list[float], counts: list[int]) -> list[float]:
    return [
        bias * count / (count + BIAS_SHRINKAGE_VOTES)
        for bias, count in zip(biases, counts)
    ]


def scale_for_released_apps(factors: list[list[float]], counts: list[int]) -> float:
    """Released app versions read min(1, |q|) as item confidence.

    Scale every vector so a typical title with 100+ votes has length 1. The
    current app's fold-in is scale-free because the regularization is chosen
    after scaling.
    """
    norms = [
        math.sqrt(sum(value * value for value in vector))
        for vector, count in zip(factors, counts)
        if count >= 100
    ]
    typical = statistics.median(norms) if norms else 0.0
    if typical <= 1e-9:
        return 1.0
    scale = 1.0 / typical
    for index, vector in enumerate(factors):
        factors[index] = [value * scale for value in vector]
    return scale


def _cholesky_solve(matrix: list[list[float]], vector: list[float]) -> list[float]:
    """Solve a symmetric positive definite system; only the lower triangle is read."""
    size = len(vector)
    lower = [[0.0] * size for _ in range(size)]
    for column in range(size):
        diagonal = matrix[column][column] - sum(
            lower[column][k] * lower[column][k] for k in range(column)
        )
        lower[column][column] = math.sqrt(max(diagonal, 1e-12))
        for row in range(column + 1, size):
            lower[row][column] = (
                matrix[row][column]
                - sum(lower[row][k] * lower[column][k] for k in range(column))
            ) / lower[column][column]
    forward = [0.0] * size
    for row in range(size):
        forward[row] = (
            vector[row] - sum(lower[row][k] * forward[k] for k in range(row))
        ) / lower[row][row]
    solution = [0.0] * size
    for row in reversed(range(size)):
        solution[row] = (
            forward[row]
            - sum(lower[k][row] * solution[k] for k in range(row + 1, size))
        ) / lower[row][row]
    return solution


def _normal_equations(
    factors: list[list[float]],
    biases: list[float],
    observations: list[tuple[int, float]],
    dimension: int,
) -> tuple[list[list[float]], list[float]]:
    size = dimension + 1
    matrix = [[0.0] * size for _ in range(size)]
    vector = [0.0] * size
    for item, signal in observations:
        features = factors[item] + [1.0]
        target = signal - biases[item]
        for row in range(size):
            value = features[row]
            vector[row] += target * value
            matrix_row = matrix[row]
            for column in range(row + 1):
                matrix_row[column] += value * features[column]
    return matrix, vector


def fold_in_user(
    matrix: list[list[float]],
    vector: list[float],
    regularization: float,
    dimension: int,
) -> tuple[list[float], float]:
    """Ridge fit of a user vector and intercept, as VNDB离线低秩推荐算法 does in the app."""
    system = [row[:] for row in matrix]
    for index in range(dimension):
        system[index][index] += regularization
    system[dimension][dimension] += INTERCEPT_REGULARIZATION
    solution = _cholesky_solve(system, vector)
    return solution[:dimension], solution[dimension]


def _dot(lhs: list[float], rhs: list[float]) -> float:
    return sum(map(operator.mul, lhs, rhs))


def _cosine(lhs: list[float], rhs: list[float]) -> float:
    lhs_norm = math.sqrt(_dot(lhs, lhs))
    rhs_norm = math.sqrt(_dot(rhs, rhs))
    if lhs_norm <= 1e-12 or rhs_norm <= 1e-12:
        return 0.0
    return _dot(lhs, rhs) / (lhs_norm * rhs_norm)


def evaluate_collaborative_model(
    dataset: VoteDataset,
    factors: list[list[float]],
    biases: list[float],
    dimension: int,
    related_pairs: Iterable[tuple[int, int]],
    seed: int,
    factor_scale: float = 1.0,
) -> dict[str, Any]:
    """Fold held-out users in like the app does and compare against baselines."""
    candidates = {
        round(regularization * factor_scale * factor_scale, 4): Counter()
        for regularization in USER_REGULARIZATION_CANDIDATES
    }
    for user, hidden in dataset.held_out.items():
        visible = dataset.observed.get(user) or []
        if not visible:
            continue
        matrix, vector = _normal_equations(factors, biases, visible, dimension)
        baseline = sum(signal - biases[item] for item, signal in visible) / (
            len(visible) + INTERCEPT_REGULARIZATION
        )
        for regularization, totals in candidates.items():
            user_vector, intercept = fold_in_user(matrix, vector, regularization, dimension)
            predictions = []
            for item, signal in hidden:
                interaction = _dot(user_vector, factors[item])
                full = intercept + biases[item] + interaction
                plain = baseline + biases[item]
                totals["squared"] += (signal - full) ** 2
                totals["baseline_squared"] += (signal - plain) ** 2
                totals["votes"] += 1
                predictions.append((signal, full, plain, interaction))
            for higher in predictions:
                for lower in predictions:
                    if higher[0] - lower[0] <= 0.15:
                        continue
                    totals["pairs"] += 1
                    totals["correct"] += higher[1] > lower[1]
                    totals["baseline_correct"] += higher[2] > lower[2]
                    totals["interaction_correct"] += higher[3] > lower[3]

    regularization, best = max(
        candidates.items(),
        key=lambda entry: entry[1]["correct"] / max(1, entry[1]["pairs"]),
    )
    if best["votes"] == 0 or best["pairs"] == 0:
        raise RuntimeError("No held-out votes were available to evaluate the model.")

    # Rank every unseen title for a sample of users, as the app does.
    rng = random.Random(seed)
    sample = rng.sample(sorted(dataset.held_out), min(400, len(dataset.held_out)))
    rankings = []
    for user in sample:
        visible = dataset.observed.get(user) or []
        if not visible:
            continue
        matrix, vector = _normal_equations(factors, biases, visible, dimension)
        user_vector, _ = fold_in_user(matrix, vector, regularization, dimension)
        seen = {item for item, _ in visible}
        personal = [_dot(user_vector, item_vector) for item_vector in factors]
        liked = {item for item, signal in dataset.held_out[user] if signal > LIKED_SIGNAL}
        rankings.append((personal, seen, liked))
    counts = dataset.item_vote_counts

    def recall(score: Any) -> float:
        hits = total = 0
        for personal, seen, liked in rankings:
            if not liked:
                continue
            top = heapq.nlargest(
                RECALL_DEPTH,
                (item for item in range(len(factors)) if item not in seen),
                key=lambda item: score(personal, item),
            )
            hits += len(liked.intersection(top))
            total += len(liked)
        return hits / max(1, total)

    def top_title_share(weight: float) -> float:
        """Share of users whose top 20 contains the single most common title."""
        appearances: Counter[int] = Counter()
        for personal, seen, _ in rankings:
            appearances.update(heapq.nlargest(
                20,
                (item for item in range(len(factors)) if item not in seen),
                key=lambda item: personal[item] + weight * biases[item],
            ))
        return max(appearances.values(), default=0) / max(1, len(rankings))

    recalls = {
        weight: recall(lambda personal, item, weight=weight: personal[item] + weight * biases[item])
        for weight in BIAS_WEIGHT_CANDIDATES
    }
    bias_weight = max(recalls, key=recalls.get)
    upper_scores = []
    for personal, seen, _ in rankings:
        scores = sorted(
            (
                personal[item] + bias_weight * biases[item]
                for item in range(len(factors))
                if item not in seen
            ),
            reverse=True,
        )
        upper_scores.append(scores[int(len(scores) * RELIABLE_SCORE_QUANTILE)])
    score_scale = statistics.median(upper_scores) / RELIABLE_COLLABORATIVE_SCORE

    index_of = {vn_id: index for index, vn_id in enumerate(dataset.item_ids)}
    related = [
        _cosine(factors[index_of[lhs]], factors[index_of[rhs]])
        for lhs, rhs in related_pairs
        if lhs in index_of
        and rhs in index_of
        and counts[index_of[lhs]] >= 30
        and counts[index_of[rhs]] >= 30
    ]
    supported = [index for index, count in enumerate(counts) if count >= 30]
    unrelated = [
        _cosine(factors[lhs], factors[rhs])
        for lhs, rhs in (rng.sample(supported, 2) for _ in range(20_000))
    ] if len(supported) >= 2 else [0.0]

    return {
        "userRegularization": regularization,
        "biasWeight": bias_weight,
        "scoreScale": score_scale,
        "recallAt100": recalls[bias_weight],
        "topTitleShare": top_title_share(bias_weight),
        "personalOnlyRecallAt100": recalls[0.0],
        "biasOnlyRecallAt100": recall(lambda personal, item: biases[item]),
        "popularityRecallAt100": recall(lambda personal, item: counts[item]),
        "heldOutUsers": len(dataset.held_out),
        "heldOutVotes": best["votes"],
        "rmse": math.sqrt(best["squared"] / best["votes"]),
        "baselineRMSE": math.sqrt(best["baseline_squared"] / best["votes"]),
        "pairwiseAccuracy": best["correct"] / best["pairs"],
        "baselinePairwiseAccuracy": best["baseline_correct"] / best["pairs"],
        "interactionPairwiseAccuracy": best["interaction_correct"] / best["pairs"],
        "relatedPairs": len(related),
        "relatedTitleCosine": statistics.mean(related) if related else 0.0,
        "randomTitleCosine": statistics.mean(unrelated),
    }


def require_quality(metrics: dict[str, Any]) -> None:
    """Refuse to publish factors that do not carry taste information."""
    failures = []
    if not metrics["rmse"] < metrics["baselineRMSE"]:
        failures.append(
            f"held-out RMSE {metrics['rmse']:.4f} is not below the bias-only "
            f"baseline {metrics['baselineRMSE']:.4f}"
        )
    if metrics["pairwiseAccuracy"] < metrics["baselinePairwiseAccuracy"] + 0.005:
        failures.append(
            f"pairwise accuracy {metrics['pairwiseAccuracy']:.4f} does not beat the "
            f"bias-only baseline {metrics['baselinePairwiseAccuracy']:.4f}"
        )
    if metrics["interactionPairwiseAccuracy"] < 0.55:
        failures.append(
            "the personal part alone orders held-out votes no better than chance "
            f"({metrics['interactionPairwiseAccuracy']:.4f})"
        )
    if not metrics["recallAt100"] > metrics["biasOnlyRecallAt100"]:
        failures.append(
            f"held-out recall@{RECALL_DEPTH} {metrics['recallAt100']:.4f} does not beat "
            f"ranking everyone by item bias ({metrics['biasOnlyRecallAt100']:.4f})"
        )
    if metrics["relatedPairs"] < 50:
        failures.append(
            f"only {metrics['relatedPairs']} related title pairs to check the embedding"
        )
    elif metrics["relatedTitleCosine"] - metrics["randomTitleCosine"] < 0.15:
        failures.append(
            "official sequels and fandiscs are not closer than random titles "
            f"({metrics['relatedTitleCosine']:+.3f} vs {metrics['randomTitleCosine']:+.3f})"
        )
    if failures:
        raise RuntimeError(
            "The collaborative model failed the quality gate: " + "; ".join(failures)
        )


def build_collaborative_model(
    votes_path: Path,
    factor_count: int,
    epochs: int,
    holdout_users: int,
    seed: int,
    related_pairs: list[tuple[int, int]],
) -> CollaborativeModel:
    dataset = load_votes(votes_path, holdout_users, seed)
    print(
        f"factors: {len(dataset.signals):,} training votes from "
        f"{dataset.user_count:,} public users on {len(dataset.item_ids):,} titles; "
        f"{len(dataset.held_out):,} users are partly held out for evaluation."
    )
    factors, biases = train_factors(dataset, factor_count, epochs, seed)
    biases = shrink_biases(biases, dataset.item_vote_counts)
    factor_scale = scale_for_released_apps(factors, dataset.item_vote_counts)
    metrics = evaluate_collaborative_model(
        dataset, factors, biases, factor_count, related_pairs, seed, factor_scale
    )
    print(
        "evaluation: "
        f"RMSE {metrics['rmse']:.4f} (bias-only {metrics['baselineRMSE']:.4f}), "
        f"pairwise {metrics['pairwiseAccuracy']:.4f} "
        f"(bias-only {metrics['baselinePairwiseAccuracy']:.4f}, "
        f"personal part {metrics['interactionPairwiseAccuracy']:.4f}), "
        f"related titles {metrics['relatedTitleCosine']:+.3f} "
        f"vs random {metrics['randomTitleCosine']:+.3f}, "
        f"recall@{RECALL_DEPTH} {metrics['recallAt100']:.4f} "
        f"(personal only {metrics['personalOnlyRecallAt100']:.4f}, "
        f"bias only {metrics['biasOnlyRecallAt100']:.4f}, "
        f"popularity {metrics['popularityRecallAt100']:.4f}), "
        f"most common title in {metrics['topTitleShare']:.0%} of top-20 lists, "
        f"regularization {metrics['userRegularization']}, "
        f"bias weight {metrics['biasWeight']}, score scale {metrics['scoreScale']:.4f}."
    )
    require_quality(metrics)
    evaluation = {
        key: round(value, 5) if isinstance(value, float) else value
        for key, value in metrics.items()
        if key not in {"userRegularization", "biasWeight", "scoreScale"}
    }
    return CollaborativeModel(
        item_ids=dataset.item_ids,
        item_vote_counts=dataset.item_vote_counts,
        factors=factors,
        biases=biases,
        parameters={
            "version": COLLABORATIVE_MODEL_VERSION,
            "userRegularization": metrics["userRegularization"],
            "interceptRegularization": INTERCEPT_REGULARIZATION,
            "biasWeight": metrics["biasWeight"],
            "scoreScale": round(metrics["scoreScale"], 6),
            "factorScale": round(factor_scale, 6),
            "evaluation": evaluation,
        },
        evaluation_votes=dataset.evaluation_votes,
    )


def run_self_test() -> None:
    """Plant a known taste structure in synthetic votes and require it back."""
    rng = random.Random(7)
    true_rank, item_count, user_count, factor_count = 6, 300, 4_000, 12
    truth = [[rng.gauss(0.0, 1.0) for _ in range(true_rank)] for _ in range(item_count + 1)]
    popularity = [1 / (index ** 0.9) for index in range(1, item_count + 1)]
    rows = []
    for user in range(1, user_count + 1):
        taste = [rng.gauss(0.0, 1.0) for _ in range(true_rank)]
        offset = rng.gauss(0.0, 8.0)
        size = min(item_count - 1, max(5, int(rng.lognormvariate(3.2, 0.6))))
        chosen: set[int] = set()
        while len(chosen) < size:
            chosen.add(rng.choices(range(1, item_count + 1), weights=popularity)[0])
        for item in chosen:
            affinity = _dot(taste, truth[item]) / math.sqrt(true_rank)
            vote = max(10, min(100, round(70 + offset + 12 * affinity + rng.gauss(0.0, 6.0))))
            rows.append((item, user, vote))
    rows.sort()
    with tempfile.TemporaryDirectory(prefix="papervn-collaborative-self-test-") as directory:
        path = Path(directory) / "votes.gz"
        with gzip.open(path, "wt", encoding="ascii") as file:
            for item, user, vote in rows:
                file.write(f"{item} {user} {vote} 2026-01-01\n")
        dataset = load_votes(path, holdout_users=300, seed=1)
    factors, biases = train_factors(dataset, factor_count, epochs=25, seed=1)
    factor_scale = scale_for_released_apps(factors, dataset.item_vote_counts)

    index_of = {vn_id: index for index, vn_id in enumerate(dataset.item_ids)}
    supported = [
        vn_id for vn_id in range(1, item_count + 1)
        if vn_id in index_of and dataset.item_vote_counts[index_of[vn_id]] >= 30
    ]
    planted, learned = [], []
    for _ in range(4_000):
        lhs, rhs = rng.sample(supported, 2)
        planted.append(_cosine(truth[lhs], truth[rhs]))
        learned.append(_cosine(factors[index_of[lhs]], factors[index_of[rhs]]))
    correlation = statistics.correlation(planted, learned)
    if correlation < 0.8:
        raise RuntimeError(
            f"Self-test failed: learned item similarity tracks the planted one "
            f"with correlation {correlation:.3f} (expected at least 0.8)."
        )

    related = [
        (lhs, rhs)
        for lhs in supported
        for rhs in supported
        if lhs < rhs and _cosine(truth[lhs], truth[rhs]) > 0.75
    ]
    require_quality(
        evaluate_collaborative_model(
            dataset, factors, biases, factor_count, related, seed=1, factor_scale=factor_scale
        )
    )
    noise = [[rng.gauss(0.0, 0.3) for _ in range(factor_count)] for _ in dataset.item_ids]
    try:
        require_quality(
            evaluate_collaborative_model(
                dataset, noise, biases, factor_count, related, seed=1, factor_scale=factor_scale
            )
        )
    except RuntimeError:
        pass
    else:
        raise RuntimeError("Self-test failed: the quality gate accepted random item factors.")
    print(
        f"Self-test passed: learned similarity correlation {correlation:.3f}, "
        "the quality gate accepts the trained model and rejects random factors."
    )


def write_evaluation_users(
    output: Path,
    evaluation_votes: list[tuple[list[tuple[int, int]], list[tuple[int, int]]]],
) -> None:
    """Held-out users for Tools/推荐离线评估. Their hidden votes were not trained on.

    Only (VN number, vote) pairs are written; no VNDB user IDs.
    """
    with gzip.open(output, "wt", encoding="utf-8") as file:
        json.dump(
            {
                "users": [
                    {
                        "visible": [[vn_id, vote] for vn_id, vote in visible],
                        "hidden": [[vn_id, vote] for vn_id, vote in hidden],
                    }
                    for visible, hidden in evaluation_votes
                ]
            },
            file,
            separators=(",", ":"),
        )
    print(f"evaluation: wrote {len(evaluation_votes)} held-out users to {output}.")


def write_array_item(file: Any, value: Any, first: bool) -> bool:
    if not first:
        file.write(",")
    json.dump(value, file, ensure_ascii=False, separators=(",", ":"))
    return False


def write_model(
    content: StoreContent | ModelContent,
    output: Path,
    collaborative: CollaborativeModel,
    factor_count: int,
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".partial")
    tag_frequencies: Counter[str] = Counter()
    trait_frequencies: Counter[str] = Counter()
    visual_novel_count = 0
    character_count = 0
    factor_index = {
        vn_id: index
        for index, vn_id in enumerate(collaborative.item_ids)
        if collaborative.item_vote_counts[index] > 0
    }
    generated_at = (
        datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )

    with gzip.open(temporary, "wt", encoding="utf-8", compresslevel=9) as file:
        # The app reads everything before "visualNovels" as the manifest.
        file.write(
            json.dumps(
                {
                    "formatVersion": 2,
                    "generatedAt": generated_at,
                    "factorCount": factor_count,
                    "collaborative": collaborative.parameters,
                },
                separators=(",", ":"),
            )[:-1]
        )

        file.write(',"visualNovels":[')
        first = True
        for item in content.visual_novels():
            for tag in item.get("tags") or []:
                if not tag.get("lie", False):
                    tag_frequencies[str(tag["id"])] += 1
            visual_novel_count += 1
            first = write_array_item(file, item, first)
        file.write("]")

        file.write(',"characters":[')
        first = True
        for item in content.characters():
            for trait in item.get("traits") or []:
                if not trait.get("lie", False):
                    trait_frequencies[str(trait["id"])] += 1
            character_count += 1
            first = write_array_item(file, item, first)
        file.write("]")

        file.write(',"itemFactors":[')
        first = True
        for item in content.visual_novels():
            vn_id = numeric_id(str(item["id"]))
            index = factor_index.get(vn_id) if vn_id is not None else None
            if index is None:
                continue
            first = write_array_item(
                file,
                {
                    "visualNovelID": item["id"],
                    "values": [round(value, 6) for value in collaborative.factors[index]],
                    "bias": round(collaborative.biases[index], 6),
                },
                first,
            )
        file.write("]")

        file.write(',"tagFrequencies":')
        json.dump(dict(tag_frequencies), file, separators=(",", ":"))
        file.write(',"traitFrequencies":')
        json.dump(dict(trait_frequencies), file, separators=(",", ":"))
        file.write(f',"visualNovelCount":{visual_novel_count}')
        file.write(f',"characterCount":{character_count}}}')

    os.replace(temporary, output)
    size = output.stat().st_size / (1024 * 1024)
    print(f"model: wrote {output} ({size:.1f} MiB).")


def main() -> int:
    arguments = parse_arguments()
    if not 8 <= arguments.factors <= 64:
        print("--factors must be between 8 and 64.", file=sys.stderr)
        return 2
    if not 1 <= arguments.epochs <= 60:
        print("--epochs must be between 1 and 60.", file=sys.stderr)
        return 2
    if arguments.self_test:
        try:
            run_self_test()
        except RuntimeError as error:
            print(str(error), file=sys.stderr)
            return 2
        return 0
    arguments.work_directory.mkdir(parents=True, exist_ok=True)

    try:
        content: StoreContent | ModelContent
        if arguments.base_model is not None:
            print(f"content: reusing visual novels and characters from {arguments.base_model}.")
            content = ModelContent(arguments.base_model)
        else:
            store = CorpusStore(arguments.work_directory / "corpus.sqlite3")
            store.require_endpoint_schema(
                "visual_novels",
                "visual_novels",
                VN_CONTENT_SCHEMA_VERSION,
            )
            store.require_endpoint_schema(
                "characters",
                "characters",
                CHARACTER_CONTENT_SCHEMA_VERSION,
            )
            fetch_endpoint(
                store,
                "visual_novels",
                "visual_novels",
                "vn",
                VN_FIELDS,
                ["and", ["released", "<=", "today"], ["devstatus", "!=", 2]],
                arguments.request_delay,
                arguments.refresh_content,
            )
            fetch_endpoint(
                store,
                "characters",
                "characters",
                "character",
                CHARACTER_FIELDS,
                [
                    "or",
                    ["role", "=", "main"],
                    ["role", "=", "primary"],
                ],
                arguments.request_delay,
                arguments.refresh_content,
            )
            content = StoreContent(store)
        related_pairs = related_title_pairs(content.visual_novels())
        content.release()
        votes_path = arguments.work_directory / "vndb-votes-latest.gz"
        download_votes(votes_path, arguments.refresh_votes)
        collaborative = build_collaborative_model(
            votes_path,
            arguments.factors,
            arguments.epochs,
            arguments.holdout_users,
            arguments.seed,
            related_pairs,
        )
        write_model(
            content,
            arguments.output,
            collaborative,
            arguments.factors,
        )
        write_evaluation_users(
            arguments.output.with_name(EVALUATION_USERS_FILENAME),
            collaborative.evaluation_votes,
        )
    except RuntimeError as error:
        print(f"Build failed: {error}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("Interrupted. Content page progress has been saved.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
