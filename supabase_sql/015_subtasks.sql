-- Step 15: Subtasks for task workspace
-- Adds an ordered checklist under each parent task.

create table if not exists subtasks (
    id          uuid default uuid_generate_v4() primary key,
    task_id     uuid not null references tasks(id) on delete cascade,
    title       text not null check (char_length(trim(title)) > 0 and char_length(title) < 200),
    completed   boolean not null default false,
    order_index integer not null default 0,
    created_at  timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at  timestamp with time zone default timezone('utc'::text, now()) not null
);

create index if not exists idx_subtasks_task_id on subtasks(task_id);

drop trigger if exists subtasks_updated_at on subtasks;
create trigger subtasks_updated_at
    before update on subtasks
    for each row execute function update_updated_at_column();

alter table subtasks enable row level security;
drop policy if exists "Users can manage subtasks in own tasks" on subtasks;
create policy "Users can manage subtasks in own tasks"
    on subtasks for all
    using (
        task_id in (
            select tasks.id
            from tasks
            join plans on plans.id = tasks.plan_id
            where plans.user_id = auth.uid()
        )
    )
    with check (
        task_id in (
            select tasks.id
            from tasks
            join plans on plans.id = tasks.plan_id
            where plans.user_id = auth.uid()
        )
    );
