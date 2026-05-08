# Implementation Plan

[Overview]
Implement a new read-only “Task Completion History” system that records every final **done** completion with exact timestamps, supports undo by deleting the record, and displays grouped history in a History pop-up (Today/Yesterday/older calendar dates), sorted by most recent completion time.

This replaces the current drawer **History** section (chat conversations) with a task-completion log. The History button stays in the drawer as-is; tapping it opens a pop-up screen that loads from the backend (not Today-screen cache), supports search by completed task name snapshot, and groups results by plan and completion date as required.

[Types]
Add backend + frontend types/DTOs for task completion history records, including snapshot fields (task name, plan name, milestone name at completion time), plus working-day index derived from existing scheduler logic.

Backend data structures:
- `TaskCompletionHistoryRow`
  - `id: UUID`
  - `user_id: UUID`
  - `task_id: UUID`
  - `plan_id: UUID`
  - `plan_name: str` (snapshot at completion time)
  - `milestone_id: UUID | null`
  - `milestone_name: str | null` (snapshot; null allowed)
  - `task_name: str` (snapshot at completion time)
  - `working_day_index: int` (1-indexed working day relative to plan start; **0 if before plan start**)
  - `calendar_date: date` (derived from completion timestamp)
  - `completed_at: datetime` (store exact completion timestamp)
  - `created_at: datetime`

API response structures:
- `TaskCompletionHistoryEntry`
  - Same snapshot fields as above (typically `created_at` omitted or included; UI needs `completed_at`, `calendar_date`, grouping fields)
- `TaskCompletionHistoryDateGroup`
  - `label: str` (“Today”, “Yesterday”, or `YYYY-MM-DD`)
  - `date: date`
  - `entries: list[TaskCompletionHistoryEntry]`
- `TaskCompletionHistoryPlanGroup`
  - `plan_id: UUID`
  - `plan_name: str`
  - `is_completed: bool` (plan.status == completed)
  - `date_groups: list[TaskCompletionHistoryDateGroup]`

Flutter DTOs:
- `HistoryPlanGroup`, `HistoryDateGroup`, `HistoryEntry`
- Search filters by `HistoryEntry.taskName` (snapshot)

Validation rules:
- Insert a history record **only when** a task transitions into `TaskStatus.done`.
- Undo behavior: when a task transitions to `TaskStatus.pending`, delete the corresponding history record.
- Final-state correctness: if a user re-done later, insert a new record with a new timestamp.
- Idempotency: enforce at most one history record per `(user_id, task_id)` at any time using a uniqueness constraint; undo deletes the record, re-done inserts a new one.
- Working day index computation uses existing scheduler rules:
  - Plan start date = `schedule_prefs.start_date` (or `adapt_start_date`) else `plan.created_at` date
  - Working days = `schedule_prefs.working_days` else Mon–Fri `[0..4]`
  - working_day_index = inclusive count of working days from plan start through `completed_at.date()`, 1-indexed; returns 0 if completed date < plan start.

[Files]
Create new backend routes/services + add Supabase migration + replace Flutter drawer History section.

New files to be created:
- `backend/adaptive/routes/history.py`
  - API endpoints: list completed task history grouped for UI (+ optional search)
- `backend/adaptive/services/history_service.py`
  - DB insert/delete/list/grouping logic
- `life_agent_flutter/lib/screens/history/task_history_screen.dart`
  - History pop-up UI (Today/Yesterday labeling, plan/date grouping, read-only entries, search bar)
- `life_agent_flutter/lib/models/history_models.dart`
  - Flutter DTOs for history API responses

Existing files to be modified:
- `supabase_sql/013_task_completion_history.sql` (new migration file)
  - Create table `task_completion_history`, RLS, indexes, uniqueness constraints
- `backend/adaptive/routes/router.py`
  - Update `/api/adaptive/tasks/update` to write/delete history records on done/pending transitions
  - Add GET endpoint for history listing (e.g. `/api/adaptive/history/completed-tasks`)
- `backend/adaptive/db.py`
  - Add mapper methods for new history table (create/delete/list)
- `life_agent_flutter/lib/widgets/app_drawer.dart`
  - Replace conversations-based History UI with a trigger that opens `TaskHistoryScreen`
- `life_agent_flutter/lib/services/adaptive_service.dart`
  - Add `listTaskCompletionHistory(...)` method(s)
- (If needed) `life_agent_flutter/lib/screens/main_shell.dart`
  - If the project has a central popup/dialog router pattern; otherwise not needed.

Files to delete or move:
- None.

Configuration file updates:
- None (no new dependencies expected).

[Functions]
Add history service functions, modify task update route, and add Flutter API/UI functions.

New backend functions:
- `HistoryService.create_history_record(user_id: UUID, task: TaskRow, plan: PlanRow, milestone: MilestoneRow|None, completed_at: datetime) -> TaskCompletionHistoryRow`
  - Computes snapshots + working_day_index using scheduler logic
- `HistoryService.delete_history_record(user_id: UUID, task_id: UUID) -> bool`
  - Deletes the current record for undo
- `HistoryService.list_completed_history(user_id: UUID, search: str|None) -> grouped structure`
  - Returns plan->date groups and entries sorted correctly

Modified backend functions:
- `update_task_status` in `backend/adaptive/routes/router.py`
  - Required changes:
    1) Load `previous_task = adaptive_store.get_task(payload.task_id)` before status update logic
    2) Detect transition:
       - If `payload.status == TaskStatus.done` AND previous status != done: insert history record
       - If `payload.status == TaskStatus.pending` AND previous status == done: delete history record
    3) Keep existing EventType recording + milestone completion + skip behavior intact

New/modified endpoints:
- `GET /api/adaptive/history/completed-tasks`
  - Optional query params: `search`
  - Returns plan groups ordered by most recent completion timestamp among their tasks; within plan, date groups ordered most recent first; within date group, entries most recent first.

Modified Flutter functions:
- `AppDrawer` History button onTap:
  - Open pop-up screen `TaskHistoryScreen`
- `adaptive_service.dart`:
  - `Future<List<HistoryPlanGroup>> listTaskCompletionHistory({String? search})`
- `TaskHistoryScreen`:
  - Fetch from backend on open; render grouped read-only entries; apply search filtering in real time (either client-side or by re-fetch with debounce).

[Classes]
Add new backend service and new Flutter screen; update existing drawer.

New classes:
- `HistoryService` (`backend/adaptive/services/history_service.py`)
- `TaskHistoryScreen` (`life_agent_flutter/lib/screens/history/task_history_screen.dart`)
- Flutter DTO models in `life_agent_flutter/lib/models/history_models.dart`

Modified classes:
- `AdaptiveStore` (`backend/adaptive/db.py`)
  - Add history CRUD/list methods
- `AppDrawer` (`life_agent_flutter/lib/widgets/app_drawer.dart`)
  - Remove `_fetchConversations()` usage from History section and replace with popup navigation

Removed classes:
- None.

[Dependencies]
No new app/runtime dependencies. Supabase migration introduces a new table and indexes only.

[Testing]
Backend:
- Add tests in `backend/adaptive/tests/` validating:
  - Mark done => history record inserted with correct `completed_at` and `working_day_index`
  - Undo pending => record deleted
  - Re-done creates new record with later timestamp
  - Ordering/grouping and search filtering are correct

Frontend:
- Widget tests / manual smoke:
  - History pop-up shows “Today/Yesterday” labels based on local date derived from backend timestamps (UTC timestamps converted to device local time for grouping labels)
  - Search filters by task title snapshot
  - Read-only behavior enforced (no toggles/undo actions in history)

[Implementation Order]
1) Create Supabase migration for `task_completion_history` table with RLS + uniqueness constraint `(user_id, task_id)` and indexes for listing by user, plan, completed_at.
2) Implement `HistoryService` and `AdaptiveStore` DB mapper methods.
3) Update `/api/adaptive/tasks/update` to insert/delete history records on done/pending transitions (capture previous status before update).
4) Add backend endpoint to list grouped history with optional search.
5) Implement Flutter DTOs + add API call in `adaptive_service.dart`.
6) Implement `TaskHistoryScreen` UI (search bar, grouped plan headers, date grouping Today/Yesterday/older, entries sorted by completed time most-recent-first).
7) Replace `AppDrawer` History section to open the pop-up screen instead of loading conversations.
8) Add/execute tests and run existing test suite.

task_progress Items:
- [ ] Step 1: Investigate/lock backend data model and scheduler working-day index logic
- [ ] Step 2: Create Supabase table + RLS + indexes for task completion history
- [ ] Step 3: Implement backend history service + DB methods + API endpoint
- [ ] Step 4: Wire history write/delete into `/api/adaptive/tasks/update` toggle flow
- [ ] Step 5: Build Flutter task history pop-up UI + search + grouping/sorting
- [ ] Step 6: Replace Flutter drawer History section to open pop-up screen
- [ ] Step 7: Add tests and verify end-to-end behavior
