-- ═══════════════════════════════════════════════════════════════════════════════
-- Step 10: Adaptive Rules Refactor — new columns & tables
-- Run AFTER 03_adaptive_tables.sql
-- Adds: rescheduled_from, struggling, skip_reason, skipped_at to tasks
-- Adds: eod_summaries table
-- Adds: memories table (episodic)
-- Adds: user_preferences columns for burn-out contract
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Tasks: new columns for rules-first EOD ──────────────────────────────────
alter table tasks
    add column if not exists rescheduled_from date,
    add column if not exists struggling boolean not null default false,
    add column if not exists skip_reason text,
    add column if not exists skipped_at timestamp with time zone;

comment on column tasks.rescheduled_from is 'Original due_date before EOD reschedule; null if never rescheduled';
comment on column tasks.struggling is 'True when task has been rescheduled 2+ times in a row';
comment on column tasks.skip_reason is 'User-provided reason when skipping permanently';
comment on column tasks.skipped_at is 'Timestamp when the task was permanently skipped';

-- ── EOD Summaries ───────────────────────────────────────────────────────────
-- Cached daily summary served instantly to the Today screen.
create table if not exists eod_summaries (
    id            uuid default uuid_generate_v4() primary key,
    user_id       uuid references users(id) on delete cascade not null,
    date          date not null,
    summary_text  text not null default '',
    stats_json    jsonb not null default '{}',
    created_at    timestamp with time zone default timezone('utc'::text, now()) not null,

    constraint eod_summaries_user_date_unique unique (user_id, date)
);

comment on table eod_summaries is 'Pre-computed EOD summary for instant display next morning; no LLM call at read time';

-- ── Episodic Memories ───────────────────────────────────────────────────────
-- Narrative memories created by the rule engine (episode, pattern, insight).
create table if not exists episodic_memories (
    id            uuid default uuid_generate_v4() primary key,
    user_id       uuid references users(id) on delete cascade not null,
    type          text not null,
    content       text not null,
    context_json  jsonb,
    learned_rule  text,
    created_at    timestamp with time zone default timezone('utc'::text, now()) not null,

    constraint episodic_memory_type_check
        check (type in ('episode', 'pattern', 'insight'))
);

comment on table episodic_memories is 'Narrative memories from the adaptive engine: episodes (events), patterns (repeated behavior), insights (learned rules)';

-- ── User Preferences: burn-out contract columns ─────────────────────────────
alter table user_preferences
    add column if not exists auto_reduce_enabled boolean not null default true,
    add column if not exists reduced_until date;

comment on column user_preferences.auto_reduce_enabled is 'User opted in to automatic daily load reduction after 3 consecutive miss days';
comment on column user_preferences.reduced_until is 'If set, tasks_per_day is temporarily reduced until this date';

-- ── Training data tables (Phase 1b) ────────────────────────────────────────
create table if not exists task_completion_predictions (
    id                 uuid default uuid_generate_v4() primary key,
    user_id            uuid references users(id) on delete cascade not null,
    task_id            uuid references tasks(id) on delete cascade not null,
    scheduled_hour     int,
    task_category      text,
    day_of_week        int,
    actual_completed   boolean,
    duration_seconds   int,
    created_at         timestamp with time zone default timezone('utc'::text, now()) not null
);

create table if not exists fatigue_events (
    id            uuid default uuid_generate_v4() primary key,
    user_id       uuid references users(id) on delete cascade not null,
    detected_at   timestamp with time zone default timezone('utc'::text, now()) not null,
    trigger_type  text not null,
    severity      text not null default 'medium',

    constraint fatigue_trigger_type_check
        check (trigger_type in ('dwell', 'skip_peak', 'pause')),
    constraint fatigue_severity_check
        check (severity in ('low', 'medium', 'high'))
);

-- ── Indexes ─────────────────────────────────────────────────────────────────
create index if not exists idx_eod_summaries_user_date on eod_summaries(user_id, date);
create index if not exists idx_episodic_memories_user on episodic_memories(user_id, created_at desc);
create index if not exists idx_tasks_struggling on tasks(plan_id) where struggling = true;
create index if not exists idx_tasks_rescheduled_from on tasks(plan_id, rescheduled_from) where rescheduled_from is not null;
create index if not exists idx_task_completion_predictions_user on task_completion_predictions(user_id, created_at desc);
create index if not exists idx_fatigue_events_user on fatigue_events(user_id, detected_at desc);
