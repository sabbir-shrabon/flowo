<<<<<<< D:/my projects/my research/life agent/supabase_sql/03_adaptive_tables.sql
-- ═══════════════════════════════════════════════════════════════════════════════
-- Step 3: Adaptive Planning Tables
-- Run AFTER 02_core_tables.sql
-- Tables: user_preferences, memory, events, adjustment_suggestions
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── User Preferences ─────────────────────────────────────────────────────
-- Lightweight scheduler preferences per user.
create table if not exists user_preferences (
    id                 uuid default uuid_generate_v4() primary key,
    user_id            uuid references users(id) on delete cascade not null unique,
    max_tasks_per_day  int not null default 4,
    created_at         timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at         timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Memory ────────────────────────────────────────────────────────────────
-- Structured user goals & profile extracted from chat.
create table if not exists memory (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade not null,
    key         text not null,
    value       text not null,
    source      text not null default 'chat_extraction',
    goal_id     uuid references goals(id) on delete set null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null,

    constraint memory_key_check check (key in ('goal', 'constraint', 'preference', 'context', 'milestone'))
);

-- ── Events ────────────────────────────────────────────────────────────────
-- Track task actions and user feedback.
create table if not exists events (
    id               uuid default uuid_generate_v4() primary key,
    user_id          uuid references users(id) on delete cascade not null,
    task_id          uuid references tasks(id) on delete cascade not null,
    plan_id          uuid references plans(id) on delete cascade not null,
    event_type       text not null,
    feedback_rating  int,
    feedback_text    text,
    created_at       timestamp with time zone default timezone('utc'::text, now()) not null,

    constraint events_event_type_check
        check (event_type in ('done', 'skipped', 'partial', 'feedback', 'rescheduled')),
    constraint events_rating_range_check
        check (feedback_rating is null or (feedback_rating >= 1 and feedback_rating <= 5))
);

-- ── Adjustment Suggestions ───────────────────────────────────────────────
-- LLM-proposed, user-approved plan adjustments.
create table if not exists adjustment_suggestions (
    id               uuid default uuid_generate_v4() primary key,
    user_id          uuid references users(id) on delete cascade not null,
    plan_id          uuid references plans(id) on delete cascade not null,
    reason           text not null,
    suggested_tasks  jsonb not null,
    status           text not null default 'pending',
    created_at       timestamp with time zone default timezone('utc'::text, now()) not null,
    resolved_at      timestamp with time zone,

    constraint adjustment_status_check
        check (status in ('pending', 'approved', 'dismissed'))
);
=======
-- ═══════════════════════════════════════════════════════════════════════════════
-- Step 3: Adaptive Planning Tables
-- Run AFTER 02_core_tables.sql
-- Tables: user_preferences, memory, events, adjustment_suggestions
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── User Preferences ─────────────────────────────────────────────────────
-- Lightweight scheduler preferences per user.
create table if not exists user_preferences (
    id                 uuid default uuid_generate_v4() primary key,
    user_id            uuid references users(id) on delete cascade not null unique,
    max_tasks_per_day  int not null default 4,
    created_at         timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at         timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Memory ────────────────────────────────────────────────────────────────
-- Structured user goals & profile extracted from chat.
create table if not exists memory (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade not null,
    key         text not null,
    value       text not null,
    source      text not null default 'chat_extraction',
    goal_id     uuid references goals(id) on delete set null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null,

    constraint memory_key_check check (key in ('goal', 'deadline', 'constraint', 'preference', 'pattern', 'schedule_habit', 'context', 'milestone'))
);

-- ── Events ────────────────────────────────────────────────────────────────
-- Track task actions and user feedback.
create table if not exists events (
    id               uuid default uuid_generate_v4() primary key,
    user_id          uuid references users(id) on delete cascade not null,
    task_id          uuid references tasks(id) on delete cascade not null,
    plan_id          uuid references plans(id) on delete cascade not null,
    event_type       text not null,
    feedback_rating  int,
    feedback_text    text,
    created_at       timestamp with time zone default timezone('utc'::text, now()) not null,

    constraint events_event_type_check
        check (event_type in ('done', 'skipped', 'partial', 'feedback', 'rescheduled')),
    constraint events_rating_range_check
        check (feedback_rating is null or (feedback_rating >= 1 and feedback_rating <= 5))
);

-- ── Adjustment Suggestions ───────────────────────────────────────────────
-- LLM-proposed, user-approved plan adjustments.
create table if not exists adjustment_suggestions (
    id               uuid default uuid_generate_v4() primary key,
    user_id          uuid references users(id) on delete cascade not null,
    plan_id          uuid references plans(id) on delete cascade not null,
    reason           text not null,
    suggested_tasks  jsonb not null,
    status           text not null default 'pending',
    created_at       timestamp with time zone default timezone('utc'::text, now()) not null,
    resolved_at      timestamp with time zone,

    constraint adjustment_status_check
        check (status in ('pending', 'approved', 'dismissed'))
);
>>>>>>> C:/Users/sabbi/.windsurf/worktrees/life agent/life agent-aec6c350/supabase_sql/03_adaptive_tables.sql
