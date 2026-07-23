-- Step 18: Production hardening
-- Additive migration: existing API columns are retained for compatibility.

-- Fast ownership checks for task RLS.
alter table tasks add column if not exists user_id uuid references users(id) on delete cascade;
update tasks t
set user_id = p.user_id
from plans p
where p.id = t.plan_id
  and t.user_id is null;

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
    return new;
end;
$$;

drop trigger if exists tasks_set_user_id on tasks;
create trigger tasks_set_user_id
before insert or update of plan_id on tasks
for each row execute function set_task_user_id();

create index if not exists idx_tasks_user_id on tasks(user_id);
create index if not exists idx_tasks_user_status_due_date
    on tasks(user_id, status, due_date);
create index if not exists idx_events_user_type_created_at
    on events(user_id, event_type, created_at desc);
create index if not exists idx_memory_user_key_importance
    on memory(user_id, key, importance desc);

-- Soft deletion and plan archiving.
alter table goals add column if not exists deleted_at timestamptz;
alter table plans add column if not exists deleted_at timestamptz;
alter table plans add column if not exists archived_at timestamptz;
alter table tasks add column if not exists deleted_at timestamptz;

create index if not exists idx_goals_active_user
    on goals(user_id) where deleted_at is null;
create index if not exists idx_plans_active_user
    on plans(user_id) where deleted_at is null and archived_at is null;
create index if not exists idx_tasks_active_plan
    on tasks(plan_id) where deleted_at is null;

-- Validation checks are NOT VALID so existing bad rows do not block deployment.
alter table plans drop constraint if exists plans_duration_days_positive;
alter table plans add constraint plans_duration_days_positive
    check (duration_days is null or duration_days > 0) not valid;

alter table tasks drop constraint if exists tasks_carry_over_count_nonnegative;
alter table tasks add constraint tasks_carry_over_count_nonnegative
    check (carry_over_count >= 0) not valid;

alter table users drop constraint if exists users_email_format_check;
alter table users add constraint users_email_format_check
    check (email is null or email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$') not valid;

-- Durable asynchronous work queue for adaptive/LLM jobs.
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

create index if not exists idx_job_queue_claim
    on job_queue(status, available_at, created_at)
    where status in ('pending', 'failed');
create index if not exists idx_job_queue_user on job_queue(user_id);

alter table job_queue enable row level security;
drop policy if exists "Users can view own jobs" on job_queue;
create policy "Users can view own jobs" on job_queue for select
using (auth.uid() = user_id or auth.role() = 'service_role');

-- Normalized conversation messages. The JSONB column remains until the app is migrated.
create table if not exists conversation_messages (
    id               uuid primary key default gen_random_uuid(),
    conversation_id  uuid not null references conversations(id) on delete cascade,
    message_key      text,
    role             text not null check (role in ('system', 'user', 'assistant', 'tool')),
    content          text not null,
    created_at       timestamptz not null default now()
);

create index if not exists idx_conversation_messages_conversation_time
    on conversation_messages(conversation_id, created_at, id);

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

-- Backfill messages when the JSONB format contains role/content objects.
insert into conversation_messages (conversation_id, message_key, role, content, created_at)
select c.id,
       nullif(m.item->>'id', ''),
       m.item->>'role',
       m.item->>'content',
       coalesce((m.item->>'createdAt')::timestamptz, c.created_at)
from conversations c
cross join lateral jsonb_array_elements(coalesce(c.messages, '[]'::jsonb)) m(item)
where jsonb_typeof(m.item) = 'object'
  and m.item->>'role' in ('system', 'user', 'assistant', 'tool')
  and m.item->>'content' is not null
  and not exists (
      select 1 from conversation_messages cm
      where cm.conversation_id = c.id
        and cm.message_key is not distinct from nullif(m.item->>'id', '')
        and cm.role = m.item->>'role'
        and cm.content = m.item->>'content'
  );

-- Replace the correlated IN policy with the indexed ownership column.
drop policy if exists "Users can manage tasks in own plans" on tasks;
create policy "Users can manage tasks in own plans"
on tasks for all
using (user_id = auth.uid())
with check (user_id = auth.uid());
