--- Step 12: Daily Quota Lock
--- Stores the first Today-screen task decision for each user/date.

CREATE TABLE IF NOT EXISTS daily_task_batches (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid references users(id) on delete cascade not null,
    date            date not null,
    daily_limit     int not null default 0,
    task_ids        jsonb not null default '[]'::jsonb,
    extra_task_ids  jsonb not null default '[]'::jsonb,
    metadata        jsonb not null default '{}'::jsonb,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    unique (user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_daily_task_batches_user_date
    ON daily_task_batches(user_id, date);

DROP TRIGGER IF EXISTS daily_task_batches_updated_at ON daily_task_batches;
CREATE TRIGGER daily_task_batches_updated_at
    BEFORE UPDATE ON daily_task_batches
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE daily_task_batches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own daily task batches" ON daily_task_batches;
CREATE POLICY "Users can manage own daily task batches"
    ON daily_task_batches FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

COMMENT ON TABLE daily_task_batches IS 'Locked Today-screen task batch for a user/date; prevents automatic refill after completion.';
COMMENT ON COLUMN daily_task_batches.daily_limit IS 'Initial calculated quota for the day before manual extra pulls.';
COMMENT ON COLUMN daily_task_batches.task_ids IS 'Ordered task IDs visible in the daily batch, including manual extras.';
COMMENT ON COLUMN daily_task_batches.extra_task_ids IS 'Ordered task IDs manually added through the overachiever flow.';
