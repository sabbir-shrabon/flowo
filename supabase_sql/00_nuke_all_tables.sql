-- ═══════════════════════════════════════════════════════════════════════════════
-- NUKE SCRIPT — Drops ALL Life Agent tables from Supabase
--
-- ⚠️  THIS IS DESTRUCTIVE. All data will be permanently lost.
-- Run this in the Supabase SQL Editor, then run full_schema_clean.sql.
-- ═══════════════════════════════════════════════════════════════════════════════

-- Drop tables in reverse dependency order.
-- CASCADE ensures dependent objects (policies, triggers, indexes) are removed too.

drop table if exists daily_task_batch_items   cascade;
drop table if exists daily_task_batches       cascade;
drop table if exists task_completion_predictions cascade;
drop table if exists fatigue_events           cascade;
drop table if exists job_queue                cascade;
drop table if exists conversation_messages    cascade;
drop table if exists task_history             cascade;
drop table if exists episodic_memories        cascade;
drop table if exists daily_summaries          cascade;
drop table if exists eod_summaries            cascade;  -- legacy name if rename never ran
drop table if exists adjustment_suggestions   cascade;
drop table if exists events                   cascade;
drop table if exists memory                   cascade;
drop table if exists user_preferences         cascade;
drop table if exists subtasks                 cascade;
drop table if exists tasks                    cascade;
drop table if exists milestones               cascade;
drop table if exists llm_test_logs            cascade;
drop table if exists chat_history             cascade;  -- legacy name if rename never ran
drop table if exists conversations            cascade;
drop table if exists roadmaps                 cascade;
drop table if exists roadmap_folders          cascade;
drop table if exists plans                    cascade;
drop table if exists goals                    cascade;
drop table if exists users                    cascade;

-- Drop the helper function (will be recreated by full_schema_clean.sql)
drop function if exists update_updated_at_column() cascade;
drop function if exists set_task_user_id()        cascade;

-- Done. Now run full_schema_clean.sql to rebuild everything.
