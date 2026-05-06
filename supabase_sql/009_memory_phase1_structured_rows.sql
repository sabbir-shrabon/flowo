-- ═══════════════════════════════════════════════════════════════════════════════
-- 009: Phase 1 Memory (Structured Rows, no vectors)
-- Adds: importance, confidence, user_visible
-- Expands allowed memory.key values to include: pattern, schedule_habit, deadline
-- Safe to run on existing DB.
-- ═══════════════════════════════════════════════════════════════════════════════

-- Add columns (idempotent)
alter table if exists memory
    add column if not exists importance int not null default 0;

alter table if exists memory
    add column if not exists confidence real not null default 0.5;

alter table if exists memory
    add column if not exists user_visible boolean not null default true;

-- Expand key check constraint
alter table if exists memory
    drop constraint if exists memory_key_check;

alter table if exists memory
    add constraint memory_key_check
        check (
            key in (
                'goal',
                'deadline',
                'constraint',
                'preference',
                'pattern',
                'schedule_habit',
                'context',
                'milestone'
            )
        );
