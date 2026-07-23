-- Clean migration runner for psql/Supabase CLI.
-- Run from the supabase_sql directory. Unlike the old runner, this does not
-- drop existing tables and contains no merge-conflict artifacts.

\set ON_ERROR_STOP on
\ir 01_extensions_and_helpers.sql
\ir 02_core_tables.sql
\ir 03_adaptive_tables.sql
\ir 004_add_milestones.sql
\ir 005_add_task_detail_and_duration.sql
\ir 006_add_plan_memory_id.sql
\ir 007_add_milestone_suggested_days_outcome.sql
\ir 008_add_milestone_insight_json.sql
\ir 009_memory_phase1_structured_rows.sql
\ir 010_adaptive_rules_refactor.sql
\ir 011_eod_to_daily_summaries.sql
\ir 012_daily_task_batches.sql
\ir 014_task_history.sql
\ir 015_subtasks.sql
\ir 016_daily_task_batch_items.sql
\ir 017_migrate_chat_history.sql
\ir 018_production_hardening.sql
\ir 04_constraints_indexes_triggers.sql
\ir 05_rls_policies.sql
