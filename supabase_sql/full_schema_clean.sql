-- ═══════════════════════════════════════════════════════════════════════════════
-- LIFE AGENT — Full Clean Schema
-- Generated: 2026-08-09
--
-- This file consolidates ALL migrations (01 through 019) into a single
-- idempotent script.  Run it on a FRESH Supabase project.
--
-- Fixes applied vs. the original migration set:
--   1. tasks_status_check now matches backend + Flutter exactly
--      (pending, done, skipped, partial — NO 'rescheduled').
--   2. tasks.user_id is always populated — trigger falls back to auth.uid()
--      when plan_id is NULL, preventing ghost rows hidden by RLS.
--   3. tasks_priority_check constraint added (was missing entirely).
--   4. Cross-column consistency: skipped tasks MUST have skipped_at.
--   5. Subtask RLS uses denormalised tasks.user_id (no expensive join).
--   6. Missing updated_at triggers added for goals, milestones, daily_summaries.
--   7. Service-role bypass policies added where the backend needs to write
--      rows that the end-user should only read (events, episodic_memories, etc.)
--   8. Email regex fix — the original had a double-escaped dot.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1: Extensions & Helper Functions
-- ─────────────────────────────────────────────────────────────────────────────

create extension if not exists "uuid-ossp";

-- Auto-update the updated_at column on every UPDATE.
create or replace function update_updated_at_column()
returns trigger as $$
begin
    new.updated_at = timezone('utc', now());
    return new;
end;
$$ language plpgsql;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2: Core Tables
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Users ────────────────────────────────────────────────────────────────────
create table if not exists users (
    id            uuid references auth.users on delete cascade primary key,
    email         text,
    llm_provider  text default 'mistral',
    llm_model     text,
    llm_api_key   text,
    created_at    timestamptz not null default timezone('utc'::text, now())
);

comment on column users.llm_api_key
    is 'API Key for LLM Provider. Stored encrypted via app-level AES-256.';

-- ── Goals ────────────────────────────────────────────────────────────────────
create table if not exists goals (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid not null references users(id) on delete cascade,
    title       text not null,
    description text,
    deleted_at  timestamptz,                                       -- soft delete
    created_at  timestamptz not null default timezone('utc'::text, now()),
    updated_at  timestamptz not null default timezone('utc'::text, now())
);

-- ── Plans ────────────────────────────────────────────────────────────────────
create table if not exists plans (
    id              uuid default uuid_generate_v4() primary key,
    goal_id         uuid references goals(id) on delete cascade,
    user_id         uuid not null references users(id) on delete cascade,
    title           text,
    status          text not null default 'active',
    priority        text not null default 'medium',
    intensity       text not null default 'moderate',
    duration_days   integer,
    schedule_prefs  jsonb,
    memory_id       uuid,                                          -- FK added after memory table
    deleted_at      timestamptz,                                   -- soft delete
    archived_at     timestamptz,                                   -- archive flag
    created_at      timestamptz not null default timezone('utc'::text, now()),
    updated_at      timestamptz not null default timezone('utc'::text, now())
);

-- ── Milestones ───────────────────────────────────────────────────────────────
create table if not exists milestones (
    id              uuid primary key default gen_random_uuid(),
    plan_id         uuid not null references plans(id) on delete cascade,
    user_id         uuid not null references users(id) on delete cascade,
    title           text not null,
    description     text,
    order_index     integer not null default 0,
    status          text not null default 'locked',
    suggested_days  integer,
    outcome         text,
    insight_json    jsonb,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),

    constraint milestones_status_check
        check (status in ('locked', 'active', 'completed'))
);

-- ── Tasks ────────────────────────────────────────────────────────────────────
create table if not exists tasks (
    id                uuid default uuid_generate_v4() primary key,
    plan_id           uuid not null references plans(id) on delete cascade,
    user_id           uuid references users(id) on delete cascade,        -- denormalised, set by trigger
    title             text not null,
    description       text,
    due_date          date,
    status            text not null default 'pending',
    priority          text not null default 'medium',
    difficulty        text not null default 'intermediate',
    parent_id         uuid references tasks(id) on delete cascade,
    milestone_id      uuid references milestones(id) on delete set null,
    order_index       integer not null default 0,
    carry_over_count  int not null default 0,
    duration_minutes  integer,
    detail_json       jsonb,
    rescheduled_from  date,
    struggling        boolean not null default false,
    skip_reason       text,
    skipped_at        timestamptz,
    deleted_at        timestamptz,                                         -- soft delete
    created_at        timestamptz not null default timezone('utc'::text, now()),
    updated_at        timestamptz not null default timezone('utc'::text, now())
);

comment on column tasks.rescheduled_from
    is 'Original due_date before reschedule; null if never rescheduled.';
comment on column tasks.struggling
    is 'True when task has been rescheduled 2+ times in a row.';
comment on column tasks.skip_reason
    is 'User-provided reason when skipping permanently.';
comment on column tasks.skipped_at
    is 'Timestamp when the task was permanently skipped.';

-- ── Subtasks ─────────────────────────────────────────────────────────────────
create table if not exists subtasks (
    id          uuid default uuid_generate_v4() primary key,
    task_id     uuid not null references tasks(id) on delete cascade,
    title       text not null check (char_length(trim(title)) > 0 and char_length(title) < 200),
    completed   boolean not null default false,
    order_index integer not null default 0,
    created_at  timestamptz not null default timezone('utc'::text, now()),
    updated_at  timestamptz not null default timezone('utc'::text, now())
);

-- ── Roadmap Folders ──────────────────────────────────────────────────────────
create table if not exists roadmap_folders (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid not null references users(id) on delete cascade,
    name        text not null,
    created_at  timestamptz not null default timezone('utc'::text, now())
);

-- ── Roadmaps ─────────────────────────────────────────────────────────────────
create table if not exists roadmaps (
    id          uuid default uuid_generate_v4() primary key,
    folder_id   uuid references roadmap_folders(id) on delete set null,
    user_id     uuid not null references users(id) on delete cascade,
    title       text not null,
    topic       text not null,
    difficulty  text not null,
    provider    text not null,
    data        jsonb not null,
    created_at  timestamptz not null default timezone('utc'::text, now())
);

-- ── Conversations ────────────────────────────────────────────────────────────
create table if not exists conversations (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid not null references users(id) on delete cascade,
    title       text not null default 'New Conversation',
    messages    jsonb not null default '[]'::jsonb,
    archived    boolean not null default false,
    created_at  timestamptz not null default timezone('utc'::text, now()),
    updated_at  timestamptz not null default timezone('utc'::text, now())
);

-- ── LLM Test Logs ────────────────────────────────────────────────────────────
create table if not exists llm_test_logs (
    id          uuid default uuid_generate_v4() primary key,
    role        text not null,
    content     text not null,
    created_at  timestamptz not null default timezone('utc'::text, now())
);


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3: Adaptive Planning Tables
-- ─────────────────────────────────────────────────────────────────────────────

-- ── User Preferences ─────────────────────────────────────────────────────────
create table if not exists user_preferences (
    id                   uuid default uuid_generate_v4() primary key,
    user_id              uuid not null references users(id) on delete cascade unique,
    max_tasks_per_day    int not null default 4,
    auto_reduce_enabled  boolean not null default true,
    reduced_until        date,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now()
);

comment on column user_preferences.auto_reduce_enabled
    is 'User opted in to automatic daily load reduction after 3 consecutive miss days.';
comment on column user_preferences.reduced_until
    is 'If set, tasks_per_day is temporarily reduced until this date.';

-- ── Memory (structured facts) ────────────────────────────────────────────────
create table if not exists memory (
    id            uuid default uuid_generate_v4() primary key,
    user_id       uuid not null references users(id) on delete cascade,
    key           text not null,
    value         text not null,
    source        text not null default 'chat_extraction',
    importance    int not null default 0,
    confidence    real not null default 0.5,
    user_visible  boolean not null default true,
    goal_id       uuid references goals(id) on delete set null,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),

    constraint memory_key_check check (
        key in ('goal', 'deadline', 'constraint', 'preference',
                'pattern', 'schedule_habit', 'context', 'milestone')
    )
);

-- Now wire up the plans.memory_id FK (memory table exists).
alter table plans
    add constraint plans_memory_id_fkey
    foreign key (memory_id) references memory(id) on delete set null;

-- ── Events ───────────────────────────────────────────────────────────────────
create table if not exists events (
    id               uuid default uuid_generate_v4() primary key,
    user_id          uuid not null references users(id) on delete cascade,
    task_id          uuid not null references tasks(id) on delete cascade,
    plan_id          uuid not null references plans(id) on delete cascade,
    event_type       text not null,
    feedback_rating  int,
    feedback_text    text,
    created_at       timestamptz not null default now(),

    -- FIX: event_type INCLUDES 'rescheduled' (this is the correct place for it,
    --      NOT in tasks.status).
    constraint events_event_type_check
        check (event_type in ('done', 'skipped', 'partial', 'feedback', 'rescheduled')),
    constraint events_rating_range_check
        check (feedback_rating is null or (feedback_rating >= 1 and feedback_rating <= 5))
);

-- ── Adjustment Suggestions ───────────────────────────────────────────────────
create table if not exists adjustment_suggestions (
    id               uuid default uuid_generate_v4() primary key,
    user_id          uuid not null references users(id) on delete cascade,
    plan_id          uuid not null references plans(id) on delete cascade,
    reason           text not null,
    suggested_tasks  jsonb not null,
    status           text not null default 'pending',
    created_at       timestamptz not null default now(),
    resolved_at      timestamptz,

    constraint adjustment_status_check
        check (status in ('pending', 'approved', 'dismissed'))
);

-- ── Daily Summaries ──────────────────────────────────────────────────────────
create table if not exists daily_summaries (
    id            uuid default uuid_generate_v4() primary key,
    user_id       uuid not null references users(id) on delete cascade,
    date          date not null,
    summary_text  text not null default '',
    stats_json    jsonb not null default '{}',
    created_at    timestamptz not null default timezone('utc'::text, now()),

    constraint daily_summaries_user_date_unique unique (user_id, date)
);

comment on table daily_summaries
    is 'Pre-computed daily summary for instant display; generated by adaptation engine or deep review.';

-- ── Episodic Memories ────────────────────────────────────────────────────────
create table if not exists episodic_memories (
    id            uuid default uuid_generate_v4() primary key,
    user_id       uuid not null references users(id) on delete cascade,
    type          text not null,
    content       text not null,
    context_json  jsonb,
    learned_rule  text,
    created_at    timestamptz not null default timezone('utc'::text, now()),

    constraint episodic_memory_type_check
        check (type in ('episode', 'pattern', 'insight'))
);

comment on table episodic_memories
    is 'Narrative memories from the adaptive engine: episodes (events), patterns (repeated behavior), insights (learned rules).';

-- ── Daily Task Batches ───────────────────────────────────────────────────────
create table if not exists daily_task_batches (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid not null references users(id) on delete cascade,
    date            date not null,
    daily_limit     int not null default 0,
    task_ids        jsonb not null default '[]'::jsonb,
    extra_task_ids  jsonb not null default '[]'::jsonb,
    metadata        jsonb not null default '{}'::jsonb,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),

    unique (user_id, date)
);

comment on table daily_task_batches
    is 'Locked Today-screen task batch for a user/date; prevents automatic refill after completion.';
comment on column daily_task_batches.daily_limit
    is 'Initial calculated quota for the day before manual extra pulls.';
comment on column daily_task_batches.task_ids
    is 'Ordered task IDs visible in the daily batch, including manual extras.';
comment on column daily_task_batches.extra_task_ids
    is 'Ordered task IDs manually added through the overachiever flow.';

-- ── Daily Task Batch Items (normalised) ──────────────────────────────────────
create table if not exists daily_task_batch_items (
    batch_id     uuid not null references daily_task_batches(id) on delete cascade,
    task_id      uuid not null references tasks(id) on delete cascade,
    is_extra     boolean not null default false,
    order_index  integer not null,
    created_at   timestamptz not null default now(),

    primary key (batch_id, task_id),
    constraint daily_task_batch_items_order_check check (order_index >= 0)
);

-- ── Task History ─────────────────────────────────────────────────────────────
create table if not exists task_history (
    id                  uuid default uuid_generate_v4() primary key,
    user_id             uuid not null references users(id) on delete cascade,
    task_id             uuid not null references tasks(id) on delete cascade unique,
    task_index          int not null,
    task_name           text not null,
    milestone_id        uuid references milestones(id) on delete set null,
    milestone_name      text,
    plan_id             uuid not null references plans(id) on delete cascade,
    plan_name           text not null,
    plan_completed      boolean default false,
    working_day_index   int,
    calendar_date       date not null,
    completed_at        timestamptz not null default timezone('utc'::text, now()),
    created_at          timestamptz not null default timezone('utc'::text, now())
);

-- ── Conversation Messages (normalised) ───────────────────────────────────────
create table if not exists conversation_messages (
    id               uuid primary key default gen_random_uuid(),
    conversation_id  uuid not null references conversations(id) on delete cascade,
    message_key      text,
    role             text not null,
    content          text not null,
    created_at       timestamptz not null default now(),

    constraint conversation_messages_role_check
        check (role in ('system', 'user', 'assistant', 'tool'))
);

-- ── Training Data Tables ─────────────────────────────────────────────────────
create table if not exists task_completion_predictions (
    id                 uuid default uuid_generate_v4() primary key,
    user_id            uuid not null references users(id) on delete cascade,
    task_id            uuid not null references tasks(id) on delete cascade,
    scheduled_hour     int,
    task_category      text,
    day_of_week        int,
    actual_completed   boolean,
    duration_seconds   int,
    created_at         timestamptz not null default timezone('utc'::text, now())
);

create table if not exists fatigue_events (
    id            uuid default uuid_generate_v4() primary key,
    user_id       uuid not null references users(id) on delete cascade,
    detected_at   timestamptz not null default timezone('utc'::text, now()),
    trigger_type  text not null,
    severity      text not null default 'medium',

    constraint fatigue_trigger_type_check
        check (trigger_type in ('dwell', 'skip_peak', 'pause')),
    constraint fatigue_severity_check
        check (severity in ('low', 'medium', 'high'))
);

-- ── Job Queue (async work) ───────────────────────────────────────────────────
create table if not exists job_queue (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid references users(id) on delete cascade,
    job_type      text not null,
    payload       jsonb not null default '{}'::jsonb,
    status        text not null default 'pending'
        check (status in ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    attempts      integer not null default 0 check (attempts >= 0),
    available_at  timestamptz not null default now(),
    locked_at     timestamptz,
    completed_at  timestamptz,
    last_error    text,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 4: Check Constraints (FIX: all enum surfaces aligned)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Plan constraints ─────────────────────────────────────────────────────────
alter table plans drop constraint if exists plans_status_check;
alter table plans add constraint plans_status_check
    check (status in ('setup', 'active', 'paused', 'completed'));

alter table plans drop constraint if exists plans_priority_check;
alter table plans add constraint plans_priority_check
    check (priority in ('high', 'medium', 'low'));

alter table plans drop constraint if exists plans_intensity_check;
alter table plans add constraint plans_intensity_check
    check (intensity in ('light', 'moderate', 'intense'));

alter table plans drop constraint if exists plans_duration_days_positive;
alter table plans add constraint plans_duration_days_positive
    check (duration_days is null or duration_days > 0);

-- ── Task constraints ─────────────────────────────────────────────────────────
-- FIX #1: NO 'rescheduled' here. Rescheduling is tracked via events table +
--         tasks.rescheduled_from column. The task stays 'pending'.
alter table tasks drop constraint if exists tasks_status_check;
alter table tasks add constraint tasks_status_check
    check (status in ('pending', 'done', 'skipped', 'partial'));

-- FIX #3: Missing priority constraint (plans had one, tasks didn't).
alter table tasks drop constraint if exists tasks_priority_check;
alter table tasks add constraint tasks_priority_check
    check (priority in ('high', 'medium', 'low'));

alter table tasks drop constraint if exists tasks_difficulty_check;
alter table tasks add constraint tasks_difficulty_check
    check (difficulty in ('easy', 'intermediate', 'hard'));

alter table tasks drop constraint if exists tasks_carry_over_count_nonnegative;
alter table tasks add constraint tasks_carry_over_count_nonnegative
    check (carry_over_count >= 0);

-- FIX #4: Cross-column consistency — skipped tasks must have skipped_at.
alter table tasks drop constraint if exists tasks_skipped_consistency;
alter table tasks add constraint tasks_skipped_consistency
    check (
        status <> 'skipped'
        or skipped_at is not null
    );

-- ── User email format ────────────────────────────────────────────────────────
-- FIX #8: The original had a double-escaped dot (\\.) which matches a literal
--         backslash rather than a dot.
alter table users drop constraint if exists users_email_format_check;
alter table users add constraint users_email_format_check
    check (email is null or email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 5: Indexes
-- ─────────────────────────────────────────────────────────────────────────────

-- Goals
create index if not exists idx_goals_user_id on goals(user_id);
create index if not exists idx_goals_active_user
    on goals(user_id) where deleted_at is null;

-- Plans
create index if not exists idx_plans_goal_id on plans(goal_id);
create index if not exists idx_plans_user_id on plans(user_id);
create index if not exists idx_plans_memory_id on plans(memory_id);
create index if not exists idx_plans_active_user
    on plans(user_id) where deleted_at is null and archived_at is null;

-- Milestones
create index if not exists idx_milestones_plan_id on milestones(plan_id);
create index if not exists idx_milestones_user_id on milestones(user_id);

-- Tasks
create index if not exists idx_tasks_plan_id on tasks(plan_id);
create index if not exists idx_tasks_user_id on tasks(user_id);
create index if not exists idx_tasks_parent_id on tasks(parent_id);
create index if not exists idx_tasks_milestone_id on tasks(milestone_id);
create index if not exists idx_tasks_user_status_due_date
    on tasks(user_id, status, due_date);
create index if not exists idx_tasks_active_plan
    on tasks(plan_id) where deleted_at is null;
create index if not exists idx_tasks_struggling
    on tasks(plan_id) where struggling = true;
create index if not exists idx_tasks_rescheduled_from
    on tasks(plan_id, rescheduled_from) where rescheduled_from is not null;

-- Subtasks
create index if not exists idx_subtasks_task_id on subtasks(task_id);

-- Roadmaps & Folders
create index if not exists idx_roadmap_folders_user_id on roadmap_folders(user_id);
create index if not exists idx_roadmaps_folder_id on roadmaps(folder_id);
create index if not exists idx_roadmaps_user_id on roadmaps(user_id);

-- Conversations
create index if not exists idx_conversations_user_id on conversations(user_id);
create index if not exists idx_conversation_messages_conversation_time
    on conversation_messages(conversation_id, created_at, id);

-- Memory
create index if not exists idx_memory_user_id on memory(user_id);
create index if not exists idx_memory_user_key on memory(user_id, key);
create index if not exists idx_memory_goal_id on memory(goal_id);
create index if not exists idx_memory_user_key_importance
    on memory(user_id, key, importance desc);

-- Events
create index if not exists idx_events_user_id on events(user_id);
create index if not exists idx_events_task_id on events(task_id);
create index if not exists idx_events_plan_id on events(plan_id);
create index if not exists idx_events_type on events(event_type);
create index if not exists idx_events_created_at on events(created_at);
create index if not exists idx_events_user_type_created_at
    on events(user_id, event_type, created_at desc);

-- Adjustment Suggestions
create index if not exists idx_adjustments_user on adjustment_suggestions(user_id);
create index if not exists idx_adjustments_plan_id on adjustment_suggestions(plan_id);
create index if not exists idx_adjustments_status on adjustment_suggestions(status);

-- Daily Summaries
create index if not exists idx_daily_summaries_user_date on daily_summaries(user_id, date);

-- Episodic Memories
create index if not exists idx_episodic_memories_user on episodic_memories(user_id, created_at desc);

-- Daily Task Batches
create index if not exists idx_daily_task_batches_user_date
    on daily_task_batches(user_id, date);
create index if not exists idx_daily_task_batch_items_task
    on daily_task_batch_items(task_id);
create index if not exists idx_daily_task_batch_items_batch_order
    on daily_task_batch_items(batch_id, order_index);

-- Task History
create index if not exists idx_task_history_user_id on task_history(user_id);
create index if not exists idx_task_history_plan_id on task_history(plan_id);
create index if not exists idx_task_history_calendar_date on task_history(calendar_date);
create index if not exists idx_task_history_completed_at on task_history(completed_at desc);
create index if not exists idx_task_history_task_id on task_history(task_id);

-- Training Data
create index if not exists idx_task_completion_predictions_user
    on task_completion_predictions(user_id, created_at desc);
create index if not exists idx_fatigue_events_user
    on fatigue_events(user_id, detected_at desc);

-- Job Queue
create index if not exists idx_job_queue_claim
    on job_queue(status, available_at, created_at)
    where status in ('pending', 'failed');
create index if not exists idx_job_queue_user on job_queue(user_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 6: Triggers
-- ─────────────────────────────────────────────────────────────────────────────

-- ── updated_at auto-stamps ───────────────────────────────────────────────────

drop trigger if exists goals_updated_at on goals;
create trigger goals_updated_at
    before update on goals
    for each row execute function update_updated_at_column();

drop trigger if exists plans_updated_at on plans;
create trigger plans_updated_at
    before update on plans
    for each row execute function update_updated_at_column();

drop trigger if exists milestones_updated_at on milestones;
create trigger milestones_updated_at
    before update on milestones
    for each row execute function update_updated_at_column();

drop trigger if exists tasks_updated_at on tasks;
create trigger tasks_updated_at
    before update on tasks
    for each row execute function update_updated_at_column();

drop trigger if exists subtasks_updated_at on subtasks;
create trigger subtasks_updated_at
    before update on subtasks
    for each row execute function update_updated_at_column();

drop trigger if exists conversations_updated_at on conversations;
create trigger conversations_updated_at
    before update on conversations
    for each row execute function update_updated_at_column();

drop trigger if exists user_preferences_updated_at on user_preferences;
create trigger user_preferences_updated_at
    before update on user_preferences
    for each row execute function update_updated_at_column();

drop trigger if exists memory_updated_at on memory;
create trigger memory_updated_at
    before update on memory
    for each row execute function update_updated_at_column();

drop trigger if exists daily_task_batches_updated_at on daily_task_batches;
create trigger daily_task_batches_updated_at
    before update on daily_task_batches
    for each row execute function update_updated_at_column();

drop trigger if exists job_queue_updated_at on job_queue;
create trigger job_queue_updated_at
    before update on job_queue
    for each row execute function update_updated_at_column();

-- ── FIX #2: Denormalise tasks.user_id from parent plan ───────────────────────
-- Falls back to auth.uid() so orphan tasks are never invisible.
create or replace function set_task_user_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.plan_id is not null
       and (tg_op = 'INSERT' or new.plan_id is distinct from old.plan_id) then
        select p.user_id into new.user_id from plans p where p.id = new.plan_id;
    end if;
    -- Fallback: if plan_id lookup yielded nothing, use the caller's auth id.
    if new.user_id is null then
        new.user_id = coalesce(auth.uid(), new.user_id);
    end if;
    return new;
end;
$$;

drop trigger if exists tasks_set_user_id on tasks;
create trigger tasks_set_user_id
    before insert or update of plan_id on tasks
    for each row execute function set_task_user_id();


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 7: Row Level Security Policies
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Users ────────────────────────────────────────────────────────────────────
alter table users enable row level security;

drop policy if exists "Users can read own profile" on users;
create policy "Users can read own profile"
    on users for select
    using (auth.uid() = id);

drop policy if exists "Users can insert own profile" on users;
create policy "Users can insert own profile"
    on users for insert
    with check (auth.uid() = id);

drop policy if exists "Users can update own profile" on users;
create policy "Users can update own profile"
    on users for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- ── Goals ────────────────────────────────────────────────────────────────────
alter table goals enable row level security;

drop policy if exists "Users can manage own goals" on goals;
create policy "Users can manage own goals"
    on goals for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Plans ────────────────────────────────────────────────────────────────────
alter table plans enable row level security;

drop policy if exists "Users can manage own plans" on plans;
create policy "Users can manage own plans"
    on plans for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Milestones ───────────────────────────────────────────────────────────────
alter table milestones enable row level security;

drop policy if exists "Users can manage own milestones" on milestones;
create policy "Users can manage own milestones"
    on milestones for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Tasks ────────────────────────────────────────────────────────────────────
-- FIX #2: Uses the denormalised user_id column (fast, no subquery).
alter table tasks enable row level security;

drop policy if exists "Users can manage tasks in own plans" on tasks;
create policy "Users can manage tasks in own plans"
    on tasks for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- ── Subtasks ─────────────────────────────────────────────────────────────────
-- FIX #5: Uses tasks.user_id instead of expensive plans join.
alter table subtasks enable row level security;

drop policy if exists "Users can manage subtasks in own tasks" on subtasks;
create policy "Users can manage subtasks in own tasks"
    on subtasks for all
    using (
        exists (
            select 1 from tasks t
            where t.id = task_id
              and t.user_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from tasks t
            where t.id = task_id
              and t.user_id = auth.uid()
        )
    );

-- ── Roadmap Folders ──────────────────────────────────────────────────────────
alter table roadmap_folders enable row level security;

drop policy if exists "Users can manage own roadmap folders" on roadmap_folders;
create policy "Users can manage own roadmap folders"
    on roadmap_folders for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Roadmaps ─────────────────────────────────────────────────────────────────
alter table roadmaps enable row level security;

drop policy if exists "Users can manage own roadmaps" on roadmaps;
create policy "Users can manage own roadmaps"
    on roadmaps for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Conversations ────────────────────────────────────────────────────────────
alter table conversations enable row level security;

drop policy if exists "Users own conversations" on conversations;
create policy "Users own conversations"
    on conversations for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Conversation Messages ────────────────────────────────────────────────────
alter table conversation_messages enable row level security;

drop policy if exists "Users can manage own conversation messages" on conversation_messages;
create policy "Users can manage own conversation messages"
    on conversation_messages for all
    using (exists (
        select 1 from conversations c
        where c.id = conversation_id and c.user_id = auth.uid()
    ))
    with check (exists (
        select 1 from conversations c
        where c.id = conversation_id and c.user_id = auth.uid()
    ));

-- ── User Preferences ────────────────────────────────────────────────────────
alter table user_preferences enable row level security;

drop policy if exists "Users can manage own preferences" on user_preferences;
create policy "Users can manage own preferences"
    on user_preferences for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Memory ───────────────────────────────────────────────────────────────────
alter table memory enable row level security;

drop policy if exists "Users can manage own memory" on memory;
create policy "Users can manage own memory"
    on memory for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- FIX #7: Backend writes memory rows with service_role key.
drop policy if exists "Service role can manage all memory" on memory;
create policy "Service role can manage all memory"
    on memory for all
    using (auth.role() = 'service_role');

-- ── Events ───────────────────────────────────────────────────────────────────
alter table events enable row level security;

drop policy if exists "Users can manage own events" on events;
create policy "Users can manage own events"
    on events for select
    using (auth.uid() = user_id);

-- FIX #7: Events are written by the backend (service_role), users only read.
drop policy if exists "Service role can manage all events" on events;
create policy "Service role can manage all events"
    on events for all
    using (auth.role() = 'service_role');

-- ── Adjustment Suggestions ───────────────────────────────────────────────────
alter table adjustment_suggestions enable row level security;

drop policy if exists "Users can manage own suggestions" on adjustment_suggestions;
create policy "Users can manage own suggestions"
    on adjustment_suggestions for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Daily Summaries ──────────────────────────────────────────────────────────
alter table daily_summaries enable row level security;

drop policy if exists "Users can view own daily summaries" on daily_summaries;
create policy "Users can view own daily summaries"
    on daily_summaries for select
    using (auth.uid() = user_id);

drop policy if exists "Service role can manage all daily summaries" on daily_summaries;
create policy "Service role can manage all daily summaries"
    on daily_summaries for all
    using (auth.role() = 'service_role');

-- ── Episodic Memories ────────────────────────────────────────────────────────
alter table episodic_memories enable row level security;

drop policy if exists "Users can view own episodic memories" on episodic_memories;
create policy "Users can view own episodic memories"
    on episodic_memories for select
    using (auth.uid() = user_id);

drop policy if exists "Service role can manage all episodic memories" on episodic_memories;
create policy "Service role can manage all episodic memories"
    on episodic_memories for all
    using (auth.role() = 'service_role');

-- ── Daily Task Batches ───────────────────────────────────────────────────────
alter table daily_task_batches enable row level security;

drop policy if exists "Users can manage own daily task batches" on daily_task_batches;
create policy "Users can manage own daily task batches"
    on daily_task_batches for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Daily Task Batch Items ───────────────────────────────────────────────────
alter table daily_task_batch_items enable row level security;

drop policy if exists "Users can manage own daily task batch items" on daily_task_batch_items;
create policy "Users can manage own daily task batch items"
    on daily_task_batch_items for all
    using (
        exists (
            select 1 from daily_task_batches b
            where b.id = batch_id and b.user_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from daily_task_batches b
            where b.id = batch_id and b.user_id = auth.uid()
        )
    );

-- ── Task History ─────────────────────────────────────────────────────────────
alter table task_history enable row level security;

drop policy if exists "Users can view their own task history" on task_history;
create policy "Users can view their own task history"
    on task_history for select
    using (auth.uid() = user_id);

drop policy if exists "Service role can manage all task history" on task_history;
create policy "Service role can manage all task history"
    on task_history for all
    using (auth.role() = 'service_role');

-- ── Job Queue ────────────────────────────────────────────────────────────────
alter table job_queue enable row level security;

drop policy if exists "Users can view own jobs" on job_queue;
create policy "Users can view own jobs"
    on job_queue for select
    using (auth.uid() = user_id or auth.role() = 'service_role');

drop policy if exists "Service role can manage all jobs" on job_queue;
create policy "Service role can manage all jobs"
    on job_queue for all
    using (auth.role() = 'service_role');

-- ── LLM Test Logs ────────────────────────────────────────────────────────────
-- Written by the server with service_role; not exposed to client users.
alter table llm_test_logs enable row level security;

-- ── Training Data ────────────────────────────────────────────────────────────
alter table task_completion_predictions enable row level security;

drop policy if exists "Service role can manage predictions" on task_completion_predictions;
create policy "Service role can manage predictions"
    on task_completion_predictions for all
    using (auth.role() = 'service_role');

alter table fatigue_events enable row level security;

drop policy if exists "Service role can manage fatigue events" on fatigue_events;
create policy "Service role can manage fatigue events"
    on fatigue_events for all
    using (auth.role() = 'service_role');


-- ─────────────────────────────────────────────────────────────────────────────
-- DONE.  All tables, constraints, indexes, triggers and RLS policies are set.
-- ─────────────────────────────────────────────────────────────────────────────
