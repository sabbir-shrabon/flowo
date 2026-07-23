-- ═══════════════════════════════════════════════════════════════════════════════
-- Step 4: Add Milestones layer between Plans and Tasks
-- Run AFTER 03_adaptive_tables.sql
-- Tables: milestones, ALTER tasks (add milestone_id, order_index)
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Milestones table ──────────────────────────────────────────────────────
-- Groups tasks within a plan into sequential milestones.
create table if not exists milestones (
    id           uuid primary key default gen_random_uuid(),
    plan_id      uuid not null references plans(id) on delete cascade,
    user_id      uuid not null references users(id) on delete cascade,
    title        text not null,
    description  text,
    order_index  integer not null default 0,
    status       text not null default 'locked' check (status in ('locked', 'active', 'completed')),
    created_at   timestamptz default now(),
    updated_at   timestamptz default now()
);

-- ── Add milestone_id and order_index to tasks ─────────────────────────────
alter table tasks add column if not exists milestone_id uuid references milestones(id) on delete set null;
alter table tasks add column if not exists order_index integer not null default 0;

create index if not exists idx_milestones_plan_id on milestones(plan_id);
create index if not exists idx_milestones_user_id on milestones(user_id);
create index if not exists idx_tasks_milestone_id on tasks(milestone_id);

-- ── Milestones RLS ────────────────────────────────────────────────────────
alter table milestones enable row level security;

drop policy if exists "Users can manage own milestones" on milestones;
create policy "Users can manage own milestones"
    on milestones for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── Update Tasks RLS to also allow access via milestone ownership ─────────
-- (existing policy checks via plans; milestone_id is optional so existing
--  policy remains valid. No change needed for tasks RLS.)
