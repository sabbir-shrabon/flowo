-- ═══════════════════════════════════════════════════════════════════════════════
-- Step 4: Check Constraints, Indexes & Triggers
-- Run AFTER 03_adaptive_tables.sql
-- ═══════════════════════════════════════════════════════════════════════════════

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

-- ── Indexes ───────────────────────────────────────────────────────────────

-- Memory indexes
create index if not exists idx_goals_user_id on goals(user_id);
create index if not exists idx_plans_goal_id on plans(goal_id);
create index if not exists idx_plans_user_id on plans(user_id);
create index if not exists idx_tasks_plan_id on tasks(plan_id);
create index if not exists idx_tasks_parent_id on tasks(parent_id);
create index if not exists idx_roadmap_folders_user_id on roadmap_folders(user_id);
create index if not exists idx_roadmaps_folder_id on roadmaps(folder_id);
create index if not exists idx_roadmaps_user_id on roadmaps(user_id);
create index if not exists idx_conversations_user_id on conversations(user_id);

create index if not exists idx_memory_user_id on memory(user_id);
create index if not exists idx_memory_user_key on memory(user_id, key);
create index if not exists idx_memory_goal_id on memory(goal_id);
create index if not exists idx_plans_memory_id on plans(memory_id);

-- Event indexes
create index if not exists idx_events_user_id on events(user_id);
create index if not exists idx_events_task_id on events(task_id);
create index if not exists idx_events_plan_id on events(plan_id);
create index if not exists idx_events_type on events(event_type);
create index if not exists idx_events_created_at on events(created_at);

-- Adjustment suggestion indexes
create index if not exists idx_adjustments_user on adjustment_suggestions(user_id);
create index if not exists idx_adjustments_plan_id on adjustment_suggestions(plan_id);
create index if not exists idx_adjustments_status on adjustment_suggestions(status);

-- ── Triggers (updated_at) ────────────────────────────────────────────────

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
