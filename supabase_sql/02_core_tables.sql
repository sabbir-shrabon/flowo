-- ═══════════════════════════════════════════════════════════════════════════════
-- Step 2: Core Tables
-- Run AFTER 01_extensions_and_helpers.sql
-- Tables: users, goals, plans, tasks, roadmap_folders, roadmaps,
--         conversations, llm_test_logs
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Users profile table ───────────────────────────────────────────────────
-- Mirrors auth.users so we can store extra profile data later.
-- id is the same UUID as auth.users(id).
create table if not exists users (
    id          uuid references auth.users on delete cascade primary key,
    email       text,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Goals table ───────────────────────────────────────────────────────────
create table if not exists goals (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade,
    title       text not null,
    description text,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Plans table ───────────────────────────────────────────────────────────
-- Includes adaptive columns (status, priority, title, intensity, updated_at)
-- so no ALTER TABLE is needed on a fresh database.
create table if not exists plans (
    id              uuid default uuid_generate_v4() primary key,
    goal_id         uuid references goals(id) on delete cascade,
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

-- ── Tasks table ───────────────────────────────────────────────────────────
-- Includes adaptive columns (carry_over_count, difficulty, updated_at)
-- and uses 'pending' as the default status (migrated from 'todo').
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
    created_at       timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at       timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Roadmap Folders table ─────────────────────────────────────────────────
create table if not exists roadmap_folders (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade,
    name        text not null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── Roadmaps table ────────────────────────────────────────────────────────
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

-- ── Conversations table ───────────────────────────────────────────────────
-- Each row = one full chat session. messages stored as JSONB array.
create table if not exists conversations (
    id          uuid default uuid_generate_v4() primary key,
    user_id     uuid references users(id) on delete cascade not null,
    title       text not null default 'New Conversation',
    messages    jsonb not null default '[]'::jsonb,
    archived    boolean not null default false,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

-- ── LLM test logs ─────────────────────────────────────────────────────────
-- Diagnostic records from the unauthenticated /api/test-llm endpoint.
create table if not exists llm_test_logs (
    id          uuid default uuid_generate_v4() primary key,
    role        text not null,
    content     text not null,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null
);
