-- ═══════════════════════════════════════════════════════════════════════════════
-- Task History Table
-- Stores a record for every task marked as done, with snapshot of task details
-- Records are deleted when a task is unmarked (status changes from done to pending)
-- ═══════════════════════════════════════════════════════════════════════════════

-- Drop existing table if it doesn't have the expected schema
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'task_history') THEN
        -- Check if calendar_date column exists; if not, drop and recreate
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'task_history' AND column_name = 'calendar_date'
        ) THEN
            DROP TABLE task_history CASCADE;
        END IF;
    END IF;
END $$;

create table if not exists task_history (
    id                  uuid default uuid_generate_v4() primary key,
    user_id             uuid references users(id) on delete cascade not null,
    task_id             uuid references tasks(id) on delete cascade not null unique,
    task_index          int not null,                     -- 1-based position in the plan roadmap
    task_name           text not null,                    -- snapshot of task title at completion time
    milestone_id        uuid references milestones(id) on delete set null,
    milestone_name      text,                             -- snapshot of milestone title
    plan_id             uuid references plans(id) on delete cascade not null,
    plan_name           text not null,                    -- snapshot of plan title at completion time
    plan_completed      boolean default false,            -- true if plan was completed when this task was done
    working_day_index   int,                              -- which working day of the plan this was completed on
    calendar_date       date not null,                    -- the actual calendar date of completion
    completed_at        timestamp with time zone default timezone('utc'::text, now()) not null,  -- exact timestamp
    created_at          timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Add task_index column to existing table if missing
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'task_history') THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'task_history' AND column_name = 'task_index'
        ) THEN
            ALTER TABLE task_history ADD COLUMN task_index int NOT NULL DEFAULT 0;
        END IF;
    END IF;
END $$;

-- Indexes for efficient querying
create index if not exists idx_task_history_user_id on task_history(user_id);
create index if not exists idx_task_history_plan_id on task_history(plan_id);
create index if not exists idx_task_history_calendar_date on task_history(calendar_date);
create index if not exists idx_task_history_completed_at on task_history(completed_at desc);
create index if not exists idx_task_history_task_id on task_history(task_id);

-- RLS policies
alter table task_history enable row level security;

drop policy if exists "Users can view their own task history" on task_history;
create policy "Users can view their own task history"
    on task_history for select
    using (auth.uid() = user_id);

drop policy if exists "Service role can manage all task history" on task_history;
create policy "Service role can manage all task history"
    on task_history for all
    using (auth.role() = 'service_role');
