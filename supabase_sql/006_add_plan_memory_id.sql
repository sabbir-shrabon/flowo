-- ═══════════════════════════════════════════════════════════════════════════════
-- Step 6: Add the plan-to-memory relationship
-- The duration_days and schedule_prefs columns are created in 02_core_tables.sql.
-- ═══════════════════════════════════════════════════════════════════════════════

alter table plans add column if not exists memory_id uuid references memory(id) on delete set null;
