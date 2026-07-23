-- ═══════════════════════════════════════════════════════════════════════════════
-- Step 5: Row Level Security Policies
-- Run AFTER 04_constraints_indexes_triggers.sql
--
-- The backend uses the service_role key which bypasses RLS, so most tables
-- don't need policies. Conversations is the exception — the frontend may
-- access it directly via the anon key for real-time chat.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Conversations RLS ─────────────────────────────────────────────────────
alter table conversations enable row level security;

drop policy if exists "Users own conversations" on conversations;
create policy "Users own conversations"
    on conversations for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Users RLS ─────────────────────────────────────────────────────────────
alter table users enable row level security;

drop policy if exists "Users can read own profile" on users;
create policy "Users can read own profile"
    on users for select
    using (auth.uid() = id);

drop policy if exists "Users can insert own profile" on users;
create policy "Users can insert own profile"
    on users for insert
    with check (auth.uid() = id);

-- ── Goals RLS ─────────────────────────────────────────────────────────────
alter table goals enable row level security;

drop policy if exists "Users can manage own goals" on goals;
create policy "Users can manage own goals"
    on goals for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Plans RLS ─────────────────────────────────────────────────────────────
alter table plans enable row level security;

drop policy if exists "Users can manage own plans" on plans;
create policy "Users can manage own plans"
    on plans for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Tasks RLS ─────────────────────────────────────────────────────────────
alter table tasks enable row level security;

drop policy if exists "Users can manage tasks in own plans" on tasks;
create policy "Users can manage tasks in own plans"
    on tasks for all
    using (plan_id in (select id from plans where user_id = auth.uid()))
    with check (plan_id in (select id from plans where user_id = auth.uid()));

-- ── Roadmap Folders RLS ──────────────────────────────────────────────────
alter table roadmap_folders enable row level security;

drop policy if exists "Users can manage own roadmap folders" on roadmap_folders;
create policy "Users can manage own roadmap folders"
    on roadmap_folders for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Roadmaps RLS ─────────────────────────────────────────────────────────
alter table roadmaps enable row level security;

drop policy if exists "Users can manage own roadmaps" on roadmaps;
create policy "Users can manage own roadmaps"
    on roadmaps for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── User Preferences RLS ────────────────────────────────────────────────
alter table user_preferences enable row level security;

drop policy if exists "Users can manage own preferences" on user_preferences;
create policy "Users can manage own preferences"
    on user_preferences for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Memory RLS ───────────────────────────────────────────────────────────
alter table memory enable row level security;

drop policy if exists "Users can manage own memory" on memory;
create policy "Users can manage own memory"
    on memory for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Events RLS ───────────────────────────────────────────────────────────
alter table events enable row level security;

drop policy if exists "Users can manage own events" on events;
create policy "Users can manage own events"
    on events for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Adjustment Suggestions RLS ───────────────────────────────────────────
alter table adjustment_suggestions enable row level security;

drop policy if exists "Users can manage own suggestions" on adjustment_suggestions;
create policy "Users can manage own suggestions"
    on adjustment_suggestions for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── LLM test logs RLS ────────────────────────────────────────────────────
-- This table is written by the server with the service role and is not
-- exposed to authenticated client users.
alter table llm_test_logs enable row level security;
