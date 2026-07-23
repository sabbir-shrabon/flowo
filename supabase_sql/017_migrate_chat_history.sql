-- Step 17: Replace the legacy chat_history table.
-- Existing diagnostic rows are preserved under the new table name.

do $$
begin
    if to_regclass('public.chat_history') is not null
       and to_regclass('public.llm_test_logs') is null then
        alter table chat_history rename to llm_test_logs;
    end if;
end $$;

-- Ensure the replacement table exists for fresh or partially migrated databases.
create table if not exists llm_test_logs (
    id          uuid default uuid_generate_v4() primary key,
    role        text not null,
    content     text not null,
    created_at  timestamptz not null default now()
);

alter table llm_test_logs enable row level security;
