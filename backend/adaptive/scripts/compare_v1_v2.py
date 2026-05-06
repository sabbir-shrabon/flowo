"""Comparison script for V1 vs V2 endpoint data consistency.

Hits both /api/adaptive/tasks/today (V1) and /api/adaptive/tasks/today/v2,
then compares the task ordering and IDs to ensure they match exactly.

Also compares /plans/{plan_id}/detail vs /plans/{plan_id}/detail/v2.

Usage:
    python -m backend.adaptive.scripts.compare_v1_v2 --base-url http://localhost:8000 --token <jwt>
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from urllib.request import Request, urlopen
from urllib.error import HTTPError


def _fetch(url: str, token: str) -> dict | list:
    req = Request(url)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urlopen(req) as resp:
            return json.loads(resp.read())
    except HTTPError as e:
        print(f"  HTTP {e.code} from {url}: {e.read().decode()[:200]}")
        return None


def compare_today_tasks(base_url: str, token: str) -> bool:
    """Compare /tasks/today (V1) vs /tasks/today/v2."""
    print("\n=== Comparing Today Tasks (V1 vs V2) ===")

    v1_url = f"{base_url}/api/adaptive/tasks/today"
    v2_url = f"{base_url}/api/adaptive/tasks/today/v2"

    # Measure TTFB for V1
    t0 = time.perf_counter()
    v1_data = _fetch(v1_url, token)
    v1_ms = (time.perf_counter() - t0) * 1000

    # Measure TTFB for V2
    t0 = time.perf_counter()
    v2_data = _fetch(v2_url, token)
    v2_ms = (time.perf_counter() - t0) * 1000

    if v1_data is None or v2_data is None:
        print("  SKIP: One or both endpoints returned errors.")
        return False

    v1_ids = [t["id"] for t in v1_data]
    v2_ids = [t["id"] for t in v2_data]

    print(f"  V1: {len(v1_ids)} tasks in {v1_ms:.0f}ms")
    print(f"  V2: {len(v2_ids)} tasks in {v2_ms:.0f}ms")
    print(f"  Speedup: {v1_ms / v2_ms:.1f}x" if v2_ms > 0 else "  Speedup: N/A")

    if v1_ids == v2_ids:
        print("  ✓ Task IDs match EXACTLY (ordering preserved).")
        return True
    else:
        print("  ✗ MISMATCH!")
        print(f"    V1 IDs: {v1_ids}")
        print(f"    V2 IDs: {v2_ids}")
        # Show which tasks are in one but not the other
        v1_set = set(v1_ids)
        v2_set = set(v2_ids)
        only_v1 = v1_set - v2_set
        only_v2 = v2_set - v1_set
        if only_v1:
            print(f"    Only in V1: {only_v1}")
        if only_v2:
            print(f"    Only in V2: {only_v2}")
        return False


def compare_plan_detail(base_url: str, token: str, plan_id: str | None = None) -> bool:
    """Compare /plans/{plan_id}/detail (V1) vs /plans/{plan_id}/detail/v2."""
    print("\n=== Comparing Plan Detail (V1 vs V2) ===")

    # If no plan_id given, fetch active plans first
    if plan_id is None:
        plans_url = f"{base_url}/api/adaptive/plans"
        plans = _fetch(plans_url, token)
        if not plans:
            print("  SKIP: No active plans found.")
            return True
        plan_id = plans[0]["id"]
        print(f"  Using plan: {plans[0].get('title', plan_id)}")

    v1_url = f"{base_url}/api/adaptive/plans/{plan_id}/detail"
    v2_url = f"{base_url}/api/adaptive/plans/{plan_id}/detail/v2"

    t0 = time.perf_counter()
    v1_data = _fetch(v1_url, token)
    v1_ms = (time.perf_counter() - t0) * 1000

    t0 = time.perf_counter()
    v2_data = _fetch(v2_url, token)
    v2_ms = (time.perf_counter() - t0) * 1000

    if v1_data is None or v2_data is None:
        print("  SKIP: One or both endpoints returned errors.")
        return False

    # Compare stats
    v1_stats = v1_data.get("stats", {})
    v2_stats = v2_data.get("stats", {})
    stats_match = v1_stats == v2_stats

    print(f"  V1: {v1_ms:.0f}ms — stats: {v1_stats}")
    print(f"  V2: {v2_ms:.0f}ms — stats: {v2_stats}")
    print(f"  Speedup: {v1_ms / v2_ms:.1f}x" if v2_ms > 0 else "  Speedup: N/A")

    # Compare milestone task counts
    v1_milestones = v1_data.get("milestones", [])
    v2_milestones = v2_data.get("milestones", [])

    v1_task_count = sum(len(ms.get("tasks", [])) for ms in v1_milestones)
    v2_task_count = sum(len(ms.get("tasks", [])) for ms in v2_milestones)

    all_ok = True

    if stats_match:
        print("  ✓ Stats match exactly.")
    else:
        print("  ✗ Stats MISMATCH!")
        all_ok = False

    if v1_task_count == v2_task_count:
        print(f"  ✓ Task counts match: {v1_task_count} tasks across {len(v1_milestones)} milestones.")
    else:
        print(f"  ✗ Task count MISMATCH: V1={v1_task_count}, V2={v2_task_count}")
        all_ok = False

    # Compare task IDs per milestone
    for i, (ms1, ms2) in enumerate(zip(v1_milestones, v2_milestones)):
        ids1 = [t["id"] for t in ms1.get("tasks", [])]
        ids2 = [t["id"] for t in ms2.get("tasks", [])]
        if ids1 == ids2:
            print(f"  ✓ Milestone {i} ({ms1.get('title', '?')}): {len(ids1)} tasks match.")
        else:
            print(f"  ✗ Milestone {i} ({ms1.get('title', '?')}): MISMATCH")
            print(f"    V1: {ids1}")
            print(f"    V2: {ids2}")
            all_ok = False

    return all_ok


def check_v2_status(base_url: str, token: str) -> None:
    """Check the server-side V2 feature flag status."""
    print("\n=== V2 Server-Side Status ===")
    status = _fetch(f"{base_url}/api/adaptive/admin/v2-status", token)
    if status:
        print(f"  V2 enabled: {status.get('v2_enabled')}")
    else:
        print("  Could not fetch V2 status.")


def main():
    parser = argparse.ArgumentParser(description="Compare V1 vs V2 endpoint data consistency")
    parser.add_argument("--base-url", default="http://localhost:8000", help="Backend base URL")
    parser.add_argument("--token", required=True, help="JWT auth token")
    parser.add_argument("--plan-id", default=None, help="Specific plan ID to compare (defaults to first active plan)")
    args = parser.parse_args()

    check_v2_status(args.base_url, args.token)

    today_ok = compare_today_tasks(args.base_url, args.token)
    detail_ok = compare_plan_detail(args.base_url, args.token, args.plan_id)

    print("\n=== Summary ===")
    print(f"  Today tasks: {'PASS' if today_ok else 'FAIL'}")
    print(f"  Plan detail: {'PASS' if detail_ok else 'FAIL'}")

    if today_ok and detail_ok:
        print("\n✓ All consistency checks PASSED.")
        sys.exit(0)
    else:
        print("\n✗ Some consistency checks FAILED.")
        sys.exit(1)


if __name__ == "__main__":
    main()
