<<<<<<< D:/my projects/my research/life agent/supabase_sql/00_run_all.sql
-- ═══════════════════════════════════════════════════════════════════════════════
-- COMPLETE SCHEMA — Life Agent
-- Copy this ENTIRE file into the Supabase SQL Editor and click Run.
-- It drops old tables first, then creates everything from scratch.
-- ⚠️  This DELETES all existing data — only run on a fresh/reset database.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  0. CLEANUP — drop all existing tables (reverse dependency order)        ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

drop table if exists adjustment_suggestions cascade;
drop table if exists events cascade;
drop table if exists memory cascade;
drop table if exists user_preferences cascade;
drop table if exists chat_history cascade;
drop table if exists conversations cascade;
drop table if exists roadmaps cascade;
drop table if exists roadmap_folders cascade;
drop table if exists tasks cascade;
drop table if exists milestones cascade;
drop table if exists plans cascade;
drop table if exists goals cascade;
drop table if exists users cascade;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  1. EXTENSIONS & HELPERS                                                  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create extension if not exists "uuid-ossp";

create or replace function update_updated_at_column()
returns trigger as $$
begin
    new.updated_at = timezone('utc', now());
    return new;
end;
$$ language plpgsql;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  2. CORE TABLES                                                          ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- ── Users ──────────────────────────────────────────────────────────────────
create table if not exists users (
    id          uuid references auth.users on delete cascade primary key,
    email       text,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Goals ──────────────────────────────────────────────────────────────────
create table if not exists goals (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade,
    title       text not null,
    description text,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Plans (includes adaptive columns) ──────────────────────────────────────
create table if not exists plans (
    id              uuid default uuid_generate_v4() primary key,
    goal_id         uuid references goals(id) on delete cascade,
    memory_id       uuid references memory(id) on delete set null,
    user_id         uuid references users(id) on delete cascade,
    title           text,
    status          text not null default 'active',
    priority        text not null default 'medium',
    intensity       text not null default 'moderate',
    duration_days   integer,
    schedule_prefs  jsonb,
    created_at      timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at      timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Milestones ──────────────────────────────────────────────────────────────
create table if not exists milestones (
    id              uuid default uuid_generate_v4() primary key,
    plan_id         uuid not null references plans(id) on delete cascade,
    user_id         uuid not null references users(id) on delete cascade,
    title           text not null,
    description     text,
    order_index     integer not null default 0,
    status          text not null default 'locked' check (status in ('locked', 'active', 'completed')),
    suggested_days  integer,
    outcome         text,
    insight_json    jsonb,
    created_at      timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at      timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Tasks (includes adaptive columns) ──────────────────────────────────────
create table if not exists tasks (
    id               uuid default uuid_generate_v4() primary key,
    plan_id          uuid references plans(id) on delete cascade,
    title            text not null,
    due_date         date,
    status           text not null default 'pending',
    priority         text not null default 'medium',
    difficulty       text not null default 'intermediate',
    parent_id        uuid references tasks(id) on delete cascade,
    carry_over_count int not null default 0,
    milestone_id     uuid references milestones(id) on delete set null,
    order_index      integer not null default 0,
    description      text,
    detail_json      jsonb,
    duration_minutes integer,
    created_at       timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at       timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Roadmap Folders ───────────────────────────────────────────────────────
create table if not exists roadmap_folders (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade,
    name        text not null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Roadmaps ──────────────────────────────────────────────────────────────
create table if not exists roadmaps (
    id          uuid default uuid_generate_v4() primary key,
    folder_id   uuid references roadmap_folders(id) on delete set null,
    user_id     uuid references users(id) on delete cascade,
    title       text not null,
    topic       text not null,
    difficulty  text not null,
    provider    text not null,
    data        jsonb not null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Conversations ──────────────────────────────────────────────────────────
create table if not exists conversations (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references auth.users(id) on delete cascade not null,
    title       text not null default 'New Conversation',
    messages    jsonb not null default '[]'::jsonb,
    archived    boolean not null default false,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Chat History (legacy) ────────────────────────────────────────────────
create table if not exists chat_history (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade,
    role        text not null,
    content     text not null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  3. ADAPTIVE PLANNING TABLES                                             ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- ── User Preferences ──────────────────────────────────────────────────────
create table if not exists user_preferences (
    id                 uuid default uuid_generate_v4() primary key,
    user_id            uuid references users(id) on delete cascade not null unique,
    max_tasks_per_day  int not null default 4,
    created_at         timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at         timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Memory ─────────────────────────────────────────────────────────────────
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


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  4. CHECK CONSTRAINTS, INDEXES & TRIGGERS                                ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- ── Plan constraints ──────────────────────────────────────────────────────
alter table plans drop constraint if exists plans_status_check;
alter table plans add constraint plans_status_check
    check (status in ('setup', 'active', 'paused', 'completed'));

alter table plans drop constraint if exists plans_priority_check;
alter table plans add constraint plans_priority_check
    check (priority in ('high', 'medium', 'low'));

alter table plans drop constraint if exists plans_intensity_check;
alter table plans add constraint plans_intensity_check
    check (intensity in ('light', 'moderate', 'intense'));

-- ── Task constraints ──────────────────────────────────────────────────────
alter table tasks drop constraint if exists tasks_status_check;
alter table tasks add constraint tasks_status_check
    check (status in ('pending', 'done', 'skipped', 'partial'));

alter table tasks drop constraint if exists tasks_difficulty_check;
alter table tasks add constraint tasks_difficulty_check
    check (difficulty in ('easy', 'intermediate', 'hard'));

-- ── Indexes ──────────────────────────────────────────────────────────────
create index if not exists idx_memory_user_id on memory(user_id);
create index if not exists idx_memory_user_key on memory(user_id, key);

create index if not exists idx_events_user_id on events(user_id);
create index if not exists idx_events_task_id on events(task_id);
create index if not exists idx_events_plan_id on events(plan_id);
create index if not exists idx_events_type on events(event_type);
create index if not exists idx_events_created_at on events(created_at);

create index if not exists idx_adjustments_user on adjustment_suggestions(user_id);
create index if not exists idx_adjustments_status on adjustment_suggestions(status);

-- ── Triggers (auto updated_at) ────────────────────────────────────────────
drop trigger if exists conversations_updated_at on conversations;
create trigger conversations_updated_at
    before update on conversations
    for each row execute function update_updated_at_column();

drop trigger if exists plans_updated_at on plans;
create trigger plans_updated_at
    before update on plans
    for each row execute function update_updated_at_column();

drop trigger if exists tasks_updated_at on tasks;
create trigger tasks_updated_at
    before update on tasks
    for each row execute function update_updated_at_column();

drop trigger if exists user_preferences_updated_at on user_preferences;
create trigger user_preferences_updated_at
    before update on user_preferences
    for each row execute function update_updated_at_column();

drop trigger if exists memory_updated_at on memory;
create trigger memory_updated_at
    before update on memory
    for each row execute function update_updated_at_column();

drop trigger if exists milestones_updated_at on milestones;
create trigger milestones_updated_at
    before update on milestones
    for each row execute function update_updated_at_column();


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  5. ROW LEVEL SECURITY POLICIES                                          ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Conversations
alter table conversations enable row level security;
drop policy if exists "Users own conversations" on conversations;
create policy "Users own conversations"
    on conversations for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Users
alter table users enable row level security;
drop policy if exists "Users can read own profile" on users;
create policy "Users can read own profile"
    on users for select
    using (auth.uid() = id);
drop policy if exists "Users can insert own profile" on users;
create policy "Users can insert own profile"
    on users for insert
    with check (auth.uid() = id);

-- Goals
alter table goals enable row level security;
drop policy if exists "Users can manage own goals" on goals;
create policy "Users can manage own goals"
    on goals for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Plans
alter table plans enable row level security;
drop policy if exists "Users can manage own plans" on plans;
create policy "Users can manage own plans"
    on plans for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Tasks
alter table tasks enable row level security;
drop policy if exists "Users can manage tasks in own plans" on tasks;
create policy "Users can manage tasks in own plans"
    on tasks for all
    using (plan_id in (select id from plans where user_id = auth.uid()))
    with check (plan_id in (select id from plans where user_id = auth.uid()));

-- Roadmap Folders
alter table roadmap_folders enable row level security;
drop policy if exists "Users can manage own roadmap folders" on roadmap_folders;
create policy "Users can manage own roadmap folders"
    on roadmap_folders for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Roadmaps
alter table roadmaps enable row level security;
drop policy if exists "Users can manage own roadmaps" on roadmaps;
create policy "Users can manage own roadmaps"
    on roadmaps for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- User Preferences
alter table user_preferences enable row level security;
drop policy if exists "Users can manage own preferences" on user_preferences;
create policy "Users can manage own preferences"
    on user_preferences for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Memory
alter table memory enable row level security;
drop policy if exists "Users can manage own memory" on memory;
create policy "Users can manage own memory"
    on memory for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Events
alter table events enable row level security;
drop policy if exists "Users can manage own events" on events;
create policy "Users can manage own events"
    on events for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Milestones
alter table milestones enable row level security;
drop policy if exists "Users can manage own milestones" on milestones;
create policy "Users can manage own milestones"
    on milestones for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Adjustment Suggestions
alter table adjustment_suggestions enable row level security;
drop policy if exists "Users can manage own suggestions" on adjustment_suggestions;
create policy "Users can manage own suggestions"
    on adjustment_suggestions for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Chat History
alter table chat_history enable row level security;
drop policy if exists "Users can manage own chat history" on chat_history;
create policy "Users can manage own chat history"
    on chat_history for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
=======
-- ═══════════════════════════════════════════════════════════════════════════════
-- COMPLETE SCHEMA — Life Agent
-- Copy this ENTIRE file into the Supabase SQL Editor and click Run.
-- It drops old tables first, then creates everything from scratch.
-- ⚠️  This DELETES all existing data — only run on a fresh/reset database.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  0. CLEANUP — drop all existing tables (reverse dependency order)        ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

drop table if exists adjustment_suggestions cascade;
drop table if exists events cascade;
drop table if exists memory cascade;
drop table if exists user_preferences cascade;
drop table if exists chat_history cascade;
drop table if exists conversations cascade;
drop table if exists roadmaps cascade;
drop table if exists roadmap_folders cascade;
drop table if exists tasks cascade;
drop table if exists milestones cascade;
drop table if exists plans cascade;
drop table if exists goals cascade;
drop table if exists users cascade;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  1. EXTENSIONS & HELPERS                                                  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create extension if not exists "uuid-ossp";

create or replace function update_updated_at_column()
returns trigger as $$
begin
    new.updated_at = timezone('utc', now());
    return new;
end;
$$ language plpgsql;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  2. CORE TABLES                                                          ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- ── Users ──────────────────────────────────────────────────────────────────
create table if not exists users (
    id          uuid references auth.users on delete cascade primary key,
    email       text,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Goals ──────────────────────────────────────────────────────────────────
create table if not exists goals (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade,
    title       text not null,
    description text,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Plans (includes adaptive columns) ──────────────────────────────────────
create table if not exists plans (
    id              uuid default uuid_generate_v4() primary key,
    goal_id         uuid references goals(id) on delete cascade,
    memory_id       uuid references memory(id) on delete set null,
    user_id         uuid references users(id) on delete cascade,
    title           text,
    status          text not null default 'active',
    priority        text not null default 'medium',
    intensity       text not null default 'moderate',
    duration_days   integer,
    schedule_prefs  jsonb,
    created_at      timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at      timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Milestones ──────────────────────────────────────────────────────────────
create table if not exists milestones (
    id              uuid default uuid_generate_v4() primary key,
    plan_id         uuid not null references plans(id) on delete cascade,
    user_id         uuid not null references users(id) on delete cascade,
    title           text not null,
    description     text,
    order_index     integer not null default 0,
    status          text not null default 'locked' check (status in ('locked', 'active', 'completed')),
    suggested_days  integer,
    outcome         text,
    insight_json    jsonb,
    created_at      timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at      timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Tasks (includes adaptive columns) ──────────────────────────────────────
create table if not exists tasks (
    id               uuid default uuid_generate_v4() primary key,
    plan_id          uuid references plans(id) on delete cascade,
    title            text not null,
    due_date         date,
    status           text not null default 'pending',
    priority         text not null default 'medium',
    difficulty       text not null default 'intermediate',
    parent_id        uuid references tasks(id) on delete cascade,
    carry_over_count int not null default 0,
    milestone_id     uuid references milestones(id) on delete set null,
    order_index      integer not null default 0,
    description      text,
    detail_json      jsonb,
    duration_minutes integer,
    created_at       timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at       timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Roadmap Folders ───────────────────────────────────────────────────────
create table if not exists roadmap_folders (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade,
    name        text not null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Roadmaps ──────────────────────────────────────────────────────────────
create table if not exists roadmaps (
    id          uuid default uuid_generate_v4() primary key,
    folder_id   uuid references roadmap_folders(id) on delete set null,
    user_id     uuid references users(id) on delete cascade,
    title       text not null,
    topic       text not null,
    difficulty  text not null,
    provider    text not null,
    data        jsonb not null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Conversations ──────────────────────────────────────────────────────────
create table if not exists conversations (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references auth.users(id) on delete cascade not null,
    title       text not null default 'New Conversation',
    messages    jsonb not null default '[]'::jsonb,
    archived    boolean not null default false,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Chat History (legacy) ────────────────────────────────────────────────
create table if not exists chat_history (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade,
    role        text not null,
    content     text not null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  3. ADAPTIVE PLANNING TABLES                                             ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- ── User Preferences ──────────────────────────────────────────────────────
create table if not exists user_preferences (
    id                 uuid default uuid_generate_v4() primary key,
    user_id            uuid references users(id) on delete cascade not null unique,
    max_tasks_per_day  int not null default 4,
    created_at         timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at         timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Memory ─────────────────────────────────────────────────────────────────
create table if not exists memory (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade not null,
    key         text not null,
    value       text not null,
    source      text not null default 'chat_extraction',
    importance  int not null default 0,
    confidence  real not null default 0.5,
    user_visible boolean not null default true,
    goal_id     uuid references goals(id) on delete set null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null,

    constraint memory_key_check check (key in ('goal', 'deadline', 'constraint', 'preference', 'pattern', 'schedule_habit', 'context', 'milestone'))
);

-- ── Events ────────────────────────────────────────────────────────────────
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


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  4. CHECK CONSTRAINTS, INDEXES & TRIGGERS                                ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- ── Plan constraints ──────────────────────────────────────────────────────
alter table plans drop constraint if exists plans_status_check;
alter table plans add constraint plans_status_check
    check (status in ('setup', 'active', 'paused', 'completed'));

alter table plans drop constraint if exists plans_priority_check;
alter table plans add constraint plans_priority_check
    check (priority in ('high', 'medium', 'low'));

alter table plans drop constraint if exists plans_intensity_check;
alter table plans add constraint plans_intensity_check
    check (intensity in ('light', 'moderate', 'intense'));

-- ── Task constraints ──────────────────────────────────────────────────────
alter table tasks drop constraint if exists tasks_status_check;
alter table tasks add constraint tasks_status_check
    check (status in ('pending', 'done', 'skipped', 'partial'));

alter table tasks drop constraint if exists tasks_difficulty_check;
alter table tasks add constraint tasks_difficulty_check
    check (difficulty in ('easy', 'intermediate', 'hard'));

-- ── Indexes ──────────────────────────────────────────────────────────────
create index if not exists idx_memory_user_id on memory(user_id);
create index if not exists idx_memory_user_key on memory(user_id, key);

create index if not exists idx_events_user_id on events(user_id);
create index if not exists idx_events_task_id on events(task_id);
create index if not exists idx_events_plan_id on events(plan_id);
create index if not exists idx_events_type on events(event_type);
create index if not exists idx_events_created_at on events(created_at);

create index if not exists idx_adjustments_user on adjustment_suggestions(user_id);
create index if not exists idx_adjustments_status on adjustment_suggestions(status);

-- ── Triggers (auto updated_at) ────────────────────────────────────────────
drop trigger if exists conversations_updated_at on conversations;
create trigger conversations_updated_at
    before update on conversations
    for each row execute function update_updated_at_column();

drop trigger if exists plans_updated_at on plans;
create trigger plans_updated_at
    before update on plans
    for each row execute function update_updated_at_column();

drop trigger if exists tasks_updated_at on tasks;
create trigger tasks_updated_at
    before update on tasks
    for each row execute function update_updated_at_column();

drop trigger if exists user_preferences_updated_at on user_preferences;
create trigger user_preferences_updated_at
    before update on user_preferences
    for each row execute function update_updated_at_column();

drop trigger if exists memory_updated_at on memory;
create trigger memory_updated_at
    before update on memory
    for each row execute function update_updated_at_column();

drop trigger if exists milestones_updated_at on milestones;
create trigger milestones_updated_at
    before update on milestones
    for each row execute function update_updated_at_column();


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  5. ROW LEVEL SECURITY POLICIES                                          ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Conversations
alter table conversations enable row level security;
drop policy if exists "Users own conversations" on conversations;
create policy "Users own conversations"
    on conversations for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Users
alter table users enable row level security;
drop policy if exists "Users can read own profile" on users;
create policy "Users can read own profile"
    on users for select
    using (auth.uid() = id);
drop policy if exists "Users can insert own profile" on users;
create policy "Users can insert own profile"
    on users for insert
    with check (auth.uid() = id);

-- Goals
alter table goals enable row level security;
drop policy if exists "Users can manage own goals" on goals;
create policy "Users can manage own goals"
    on goals for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Plans
alter table plans enable row level security;
drop policy if exists "Users can manage own plans" on plans;
create policy "Users can manage own plans"
    on plans for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Tasks
alter table tasks enable row level security;
drop policy if exists "Users can manage tasks in own plans" on tasks;
create policy "Users can manage tasks in own plans"
    on tasks for all
    using (plan_id in (select id from plans where user_id = auth.uid()))
    with check (plan_id in (select id from plans where user_id = auth.uid()));

-- Roadmap Folders
alter table roadmap_folders enable row level security;
drop policy if exists "Users can manage own roadmap folders" on roadmap_folders;
create policy "Users can manage own roadmap folders"
    on roadmap_folders for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Roadmaps
alter table roadmaps enable row level security;
drop policy if exists "Users can manage own roadmaps" on roadmaps;
create policy "Users can manage own roadmaps"
    on roadmaps for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- User Preferences
alter table user_preferences enable row level security;
drop policy if exists "Users can manage own preferences" on user_preferences;
create policy "Users can manage own preferences"
    on user_preferences for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Memory
alter table memory enable row level security;
drop policy if exists "Users can manage own memory" on memory;
create policy "Users can manage own memory"
    on memory for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Events
alter table events enable row level security;
drop policy if exists "Users can manage own events" on events;
create policy "Users can manage own events"
    on events for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Milestones
alter table milestones enable row level security;
drop policy if exists "Users can manage own milestones" on milestones;
create policy "Users can manage own milestones"
    on milestones for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Adjustment Suggestions
alter table adjustment_suggestions enable row level security;
drop policy if exists "Users can manage own suggestions" on adjustment_suggestions;
create policy "Users can manage own suggestions"
    on adjustment_suggestions for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Chat History
alter table chat_history enable row level security;
drop policy if exists "Users can manage own chat history" on chat_history;
create policy "Users can manage own chat history"
    on chat_history for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
>>>>>>> C:/Users/sabbi/.windsurf/worktrees/life agent/life agent-aec6c350/supabase_sql/00_run_all.sql
