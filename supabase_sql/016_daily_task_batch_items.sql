-- Step 16: Normalize daily task batch membership
-- One row represents one task in a locked daily batch.

create table if not exists daily_task_batch_items (
    batch_id     uuid not null references daily_task_batches(id) on delete cascade,
    task_id      uuid not null references tasks(id) on delete cascade,
    is_extra     boolean not null default false,
    order_index  integer not null,
    created_at   timestamptz not null default now(),
    primary key (batch_id, task_id),
    constraint daily_task_batch_items_order_check check (order_index >= 0)
);

create index if not exists idx_daily_task_batch_items_task
    on daily_task_batch_items(task_id);

create index if not exists idx_daily_task_batch_items_batch_order
    on daily_task_batch_items(batch_id, order_index);

alter table daily_task_batch_items enable row level security;

drop policy if exists "Users can manage own daily task batch items"
    on daily_task_batch_items;
create policy "Users can manage own daily task batch items"
    on daily_task_batch_items for all
    using (
        exists (
            select 1
            from daily_task_batches b
            where b.id = batch_id
              and b.user_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1
            from daily_task_batches b
            where b.id = batch_id
              and b.user_id = auth.uid()
        )
    );

-- Backfill existing batches. The JSONB columns remain temporarily for
-- backward compatibility until the application is migrated to this table.
insert into daily_task_batch_items (batch_id, task_id, is_extra, order_index)
select b.id, item.task_id, item.is_extra, item.order_index
from daily_task_batches b
cross join lateral (
    select value::uuid as task_id, false as is_extra, ordinality - 1 as order_index
    from jsonb_array_elements_text(coalesce(b.task_ids, '[]'::jsonb))
    with ordinality
    union all
    select value::uuid as task_id, true as is_extra, ordinality - 1 as order_index
    from jsonb_array_elements_text(coalesce(b.extra_task_ids, '[]'::jsonb))
    with ordinality
) item
on conflict (batch_id, task_id) do update
set is_extra = excluded.is_extra;
