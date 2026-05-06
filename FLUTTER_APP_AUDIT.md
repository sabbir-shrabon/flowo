# Life Agent — Flutter-first audit (V1 roadmap + extraction plan)

## Inputs used

- **Product spec source**: `AI Life Coach App Development Strategy.txt`
- **Flutter app audited**: `life_agent_flutter/` (Riverpod + GoRouter + Supabase + Dio).

## What exists today (high-signal summary)

- **Auth (Supabase) + route guards**: `lib/providers/auth_provider.dart`, `lib/app.dart`
- **Navigation**: GoRouter + tab shell `Today / Plans / Chat` via `ShellRoute`: `lib/app.dart`, `lib/screens/main_shell.dart`
- **Core screens present**:
  - Today: `lib/screens/today/today_screen.dart`
  - Plans list: `lib/screens/plans/plans_screen.dart`
  - Plan detail (+ milestones + plan chat): `lib/screens/plans/plan_detail_screen.dart`
  - Milestone insight: `lib/screens/plans/milestone_insight_screen.dart`
  - Task detail (+ inline coaching chat): `lib/screens/task_detail/task_detail_screen.dart`
  - Chat (guided entry + chat + “save as plan” flow): `lib/screens/chat/chat_screen.dart`
- **Theme + reusable UI**: `lib/theme/app_theme.dart`, plus `lib/widgets/*`
- **API client + service layer**:
  - Auth-attaching API client: `lib/services/api_service.dart`
  - “Adaptive” API surface (tasks/plans/milestones/memory/conversations/chat): `lib/services/adaptive_service.dart`
- **Memory extraction (backend-driven)**: Chat triggers `/api/adaptive/extract-memory` and renders detected fields in UI: `lib/screens/chat/chat_screen.dart`, `lib/widgets/chat_message_bubble.dart`

## Spec → Flutter module matrix (Implemented / Partial / Missing)

Legend: **Implemented** = shipped end-to-end in Flutter; **Partial** = UI or API exists but not complete vs spec; **Missing** = not present in Flutter (or only implied).

| Spec area | Status | Current Flutter module(s) | Notes / gaps |
|---|---|---|---|
| Auth + route guards | Implemented | `lib/providers/auth_provider.dart`, `lib/app.dart`, `lib/screens/auth/*` | Needs session-expiry UX polish; signup/login show raw `e.toString()` (should use `friendlyErrorMessage`). |
| Tab shell navigation | Implemented | `lib/screens/main_shell.dart`, `lib/app.dart` | Solid foundation. |
| Onboarding journey (domain-based) | Partial | `lib/widgets/guided_entry_panel.dart`, `lib/screens/chat/chat_screen.dart` | Guided entry exists but **not a true onboarding** (no profile capture, no progressive disclosure, no persisted baseline). |
| Daily execution (Today) | Partial | `lib/screens/today/today_screen.dart` | Good loading/error/empty patterns + busy/reschedule hook. Missing energy inputs, missed-task explanations, proactive nudges. |
| Plan creation (HITL approvals) | Partial | `lib/screens/chat/chat_screen.dart` + plan setup endpoints in `lib/services/adaptive_service.dart` | “Save as Plan” + quick-options setup exists. Missing explicit approvals/citations/why, edit-review step, domain scoping UI. |
| Progress visualization | Partial | `lib/screens/plans/plan_detail_screen.dart` | Progress bar + milestone list exist; missing weekly/monthly review analytics, richer “life journey” views. |
| Coaching chat | Partial | `lib/screens/chat/chat_screen.dart`, `lib/screens/task_detail/task_detail_screen.dart`, `lib/screens/plans/plan_detail_screen.dart` | Chat works; missing trust UX (why/citations), tool/action confirmations, “assistant thinks/searches” transparency beyond simple “Thinking…”. |
| Persistent memory (structured) | Partial | Memory models + extraction UI: `lib/models/memory_models.dart`, `lib/services/adaptive_service.dart`, `lib/widgets/chat_message_bubble.dart` | No “memory management” screen; no Phase-1 policy UX (“silent vs confirm”); no user-visible fields like `importance/confidence/user_visible`. |
| Strategic direction | Missing | — | No “north star” / goals dashboard; no explicit direction-setting flow. |
| Proactive engagement | Missing | — | No notifications/reminders; no background tasks; no proactive check-ins. |
| Adaptive replanning | Partial | Today shows rescheduled hint; busy button sends message | No explicit missed-task handling UX, redistribution preview/approval, or energy-aware scheduling UI. |
| Entities: user | Partial | Supabase auth user only | No profile/preferences schema surfaced in Flutter. |
| Entities: plans/milestones/tasks | Implemented | `lib/models/*`, `lib/screens/plans/*`, `lib/screens/today/*`, `lib/screens/task_detail/*` | CRUD is partial (pause/resume/delete/rename exists; creation flows via chat). |
| Entities: memories | Partial | extraction + list/delete API in `lib/services/adaptive_service.dart` | No UI list/manage; no type/source enums in UI. |
| Entities: conversations | Implemented | Drawer history + CRUD: `lib/widgets/app_drawer.dart`, `lib/services/adaptive_service.dart` | Good; could add search/filter. |
| NFR: env switching (dev/prod) | Missing | `lib/config/api_config.dart`, `lib/config/supabase_config.dart` | Hardcoded base URLs + **hardcoded Supabase anon key in repo**. Needs secure config & environment handling. |
| NFR: security/RLS assumptions | Partial | Supabase auth token is attached to API via `Authorization: Bearer` | No UI for privacy/trust; no explicit RLS posture documented/validated from Flutter side. |
| NFR: transparency/trust UX | Missing/Partial | Minimal “Thinking…” only | Needs citations/why, action confirmation, memory visibility controls. |
| NFR: background agents/notifications | Missing | — | Not implemented. |

## Missing-to-ship backlog (prioritized, phased V1)

Each item includes: **Target module**, **API deps**, **Acceptance criteria**, **Risks/unknowns**.

### Phase 0 — Stabilize foundations (Flutter-first)

#### 0A) Environment/config (dev/prod base URLs, secrets handling)

- **Item P0A-1 — Remove hardcoded Supabase secrets**
  - **Target**: `lib/config/supabase_config.dart`, `.env.example` (existing), app bootstrap (`lib/main.dart`)
  - **API deps**: none
  - **Acceptance criteria**:
    - No Supabase keys committed in Dart sources.
    - App reads Supabase URL/anon key from env/build-time config.
    - CI/build docs show how to run dev vs prod configs.
  - **Risk/unknowns**: Decide config mechanism (`--dart-define`, dotenv, flavors) and how you want to handle local overrides.

- **Item P0A-2 — Explicit base URL env switching**
  - **Target**: `lib/config/api_config.dart`, `lib/services/api_service.dart`
  - **API deps**: none
  - **Acceptance criteria**:
    - `dev`/`prod` selectable without code changes.
    - Android emulator/physical device rules documented.
  - **Risk/unknowns**: Whether backend is public URL, local-only, or behind gateway.

#### 0B) Auth hardening + session expiry UX

- **Item P0B-1 — Friendly auth errors + email confirmation UX**
  - **Target**: `lib/screens/auth/login_screen.dart`, `lib/screens/auth/signup_screen.dart`, `lib/utils/error_handler.dart`
  - **API deps**: Supabase auth (existing)
  - **Acceptance criteria**:
    - Login/signup errors use `friendlyErrorMessage`.
    - “Email not confirmed” has a clear call-to-action.
    - Session expiry leads to a single consistent sign-in prompt (no silent failures).
  - **Risk/unknowns**: Whether Supabase email confirmation is enabled in your project.

#### 0C) Consistent loading/empty/error patterns

- **Item P0C-1 — Standardize page-level states**
  - **Target**: `TodayScreen`, `PlansScreen`, `PlanDetailScreen`, `TaskDetailScreen`, `ChatScreen`, `MilestoneInsightScreen`
  - **API deps**: none
  - **Acceptance criteria**:
    - Each screen has: skeleton → loaded → empty → error with retry.
    - Errors route through a single helper (`showErrorSnackBar` + page-level state message).
  - **Risk/unknowns**: Some screens already do this well; unify without losing bespoke UX.

### Phase 1 — Memory-first foundation (structured, no vectors yet)

- **Item P1-1 — Add “Memory” management screen (list + delete + explain)**
  - **Target**: new `lib/screens/memory/memory_screen.dart` + route + drawer entry
  - **API deps**:
    - `GET /api/adaptive/memory` (already used via `listMemory()`)
    - `DELETE /api/adaptive/memory/:id` (already used via `deleteMemory()`)
  - **Acceptance criteria**:
    - User can view saved memories, type/source, timestamp.
    - User can delete a memory and see immediate UI update.
    - Clear “what is memory?” explanation and transparency language.
  - **Risk/unknowns**: Backend payload shape vs desired schema fields (importance/confidence/user_visible).

- **Item P1-2 — Memory saving policy UX (silent vs confirm)**
  - **Target**: `ChatScreen` (and later onboarding/today/plans/task detail sources)
  - **API deps**: likely needs backend support to mark extracted items as “pending confirmation” vs “saved”
  - **Acceptance criteria**:
    - For `preference/pattern/schedule_habit`: saves automatically with a non-intrusive toast + undo.
    - For `goal/deadline/constraint`: user sees a confirmation card (Approve / Edit / Reject).
  - **Risk/unknowns**: Requires backend changes if not already present.

- **Item P1-3 — Add enums + fields to memory UI**
  - **Target**: `lib/models/memory_models.dart`, memory UI components
  - **API deps**: backend memory schema (`type/source/importance/confidence/user_visible`)
  - **Acceptance criteria**:
    - Memory entries render type + source labels.
    - Hide non-user-visible memories unless a “Show hidden” toggle is enabled.
  - **Risk/unknowns**: Backend schema alignment.

### Phase 2 — Career growth vertical slice (first domain)

- **Item P2-1 — True onboarding flow for “career” domain**
  - **Target**: new onboarding route(s), persists baseline context
  - **API deps**: memory save/retrieve (Phase 1), user profile endpoint (if added)
  - **Acceptance criteria**:
    - On first login: guided capture of baseline career context.
    - Data becomes retrievable “memory” used by plan generation.
  - **Risk/unknowns**: What exact onboarding questions/fields you want.

- **Item P2-2 — HITL plan generation with approvals**
  - **Target**: `ChatScreen` “plan setup” flow + a review screen
  - **API deps**:
    - `POST /api/adaptive/plans/setup/start`
    - `POST /api/adaptive/plans/:planId/setup/*`
    - (likely new) “preview plan” endpoint or richer setup response
  - **Acceptance criteria**:
    - Before plan creation, user can preview milestones/tasks and approve/edit.
    - Each AI suggestion includes “why” summary.
  - **Risk/unknowns**: Backend currently returns quick options; may need a richer plan-draft object.

- **Item P2-3 — Coaching chat integrated with plan/tasks (actions, citations/why)**
  - **Target**: `PlanDetailScreen` and `TaskDetailScreen` chat sections
  - **API deps**: chat endpoints return citations/why + structured actions
  - **Acceptance criteria**:
    - Action requests (e.g., “skip task”, “add task”) show a confirm step.
    - Responses optionally include citations (even if “system citations” first).
  - **Risk/unknowns**: Citation format and whether backend supports it.

### Phase 3 — Adaptive replanning + proactive engagement

- **Item P3-1 — Missed-task handling + redistribution UX**
  - **Target**: `TodayScreen` + a “Reschedule review” modal/screen
  - **API deps**: endpoint that returns a reschedule plan + apply action
  - **Acceptance criteria**:
    - When carry-over occurs, user can review what changed and why.
    - User can accept or tweak reschedule.
  - **Risk/unknowns**: Backend reschedule mechanism.

- **Item P3-2 — Energy-aware scheduling inputs**
  - **Target**: Today header controls + persisted memory/preference
  - **API deps**: save preference memory; task ordering endpoint supports energy
  - **Acceptance criteria**:
    - Quick energy input (low/medium/high) affects suggestions/order.
  - **Risk/unknowns**: Backend support.

- **Item P3-3 — Notifications/reminders hooks**
  - **Target**: platform notifications + settings
  - **API deps**: server-driven schedule/reminder rules (or local-only MVP)
  - **Acceptance criteria**:
    - Daily reminder + task nudges configurable.
  - **Risk/unknowns**: iOS/Android permission flows; background scheduling.

### Phase 4 — Visualization of life journey

- **Item P4-1 — Milestones/roadmap visualization**
  - **Target**: new “Roadmap” view (could live under Plans or new tab)
  - **API deps**: plan/milestone list already exists; might need richer timeline fields
  - **Acceptance criteria**:
    - Visual timeline of milestones with progress + ETA.
  - **Risk/unknowns**: Data fields available for visualization.

- **Item P4-2 — Progress analytics (weekly/monthly reviews)**
  - **Target**: new review screen(s)
  - **API deps**: analytics endpoints or client-side aggregation
  - **Acceptance criteria**:
    - Weekly summary, streaks, completion rates, insights.
  - **Risk/unknowns**: Whether backend stores enough historical events.

- **Item P4-3 — Trust UI patterns (“assistant thinks/searches”)**
  - **Target**: chat UIs, plan/task coaching UIs
  - **API deps**: optional streaming/status metadata
  - **Acceptance criteria**:
    - Clear separation between “thinking”, “searching”, “acting”, “saving memory”.
  - **Risk/unknowns**: Backend support for intermediate states.

### Phase 5 — Expansion beyond career (Wheel of Life)

- **Item P5-1 — Domain system + shared primitives**
  - **Target**: models + navigation + onboarding; expand `GuidedEntryPanel`
  - **API deps**: domain-aware memory + plan generation
  - **Acceptance criteria**:
    - Add health/finance/relationships with same primitives and UI.
  - **Risk/unknowns**: How domains map to schemas and permissions.

- **Item P5-2 — Cross-domain insights/conflicts**
  - **Target**: insights screen + notifications
  - **API deps**: cross-domain reasoning endpoint(s)
  - **Acceptance criteria**:
    - Conflicts are detected and explained; user can resolve.
  - **Risk/unknowns**: Reasoning approach and data requirements.

## Extractable Flutter modules (clean foundation candidates)

These are already well-structured enough to lift into a fresh “frontend foundation” app.

### 1) Theme + semantic colors + typography

- **Files**: `life_agent_flutter/lib/theme/app_theme.dart`, `life_agent_flutter/lib/utils/plan_colors.dart`
- **Dependencies**: `google_fonts`
- **Integration notes**: Keep the `context.colors` extensions and semantic tokens; swap brand accent + surfaces as needed.
- **Inputs needed from you**: brand palette + typography decision (keep Inter via GoogleFonts or local fonts).

### 2) Router + auth redirect pattern

- **Files**: `life_agent_flutter/lib/app.dart`, `life_agent_flutter/lib/providers/auth_provider.dart`
- **Dependencies**: `go_router`, `flutter_riverpod`, `supabase_flutter`
- **Integration notes**:
  - `_AuthNotifierStream` + `redirect` are a good template.
  - Replace initial route and add onboarding routes in Phase 2.

### 3) API service + auth interceptor

- **Files**: `life_agent_flutter/lib/services/api_service.dart`, `life_agent_flutter/lib/config/api_config.dart`
- **Dependencies**: `dio`, `supabase_flutter`
- **Integration notes**:
  - Keep auth header injection and 401 sign-out behavior.
  - Replace config with environment-driven base URL.
- **Inputs needed from you**: target backend base URLs and environment strategy.

### 4) Screen scaffolds (shell + tabs) + Drawer patterns

- **Files**: `life_agent_flutter/lib/screens/main_shell.dart`, `life_agent_flutter/lib/widgets/app_drawer.dart`
- **Dependencies**: `go_router`, `flutter_riverpod`
- **Integration notes**: The drawer already includes history + rename/archive/delete flows for conversations and plan rename/delete. Lift as a reusable “workspace drawer” pattern.

### 5) Reusable widgets (UI primitives)

- **Files**:
  - Animations: `life_agent_flutter/lib/widgets/animations.dart`
  - Chat bubble: `life_agent_flutter/lib/widgets/chat_message_bubble.dart`
  - Guided entry: `life_agent_flutter/lib/widgets/guided_entry_panel.dart`
  - Cards/sections: `life_agent_flutter/lib/widgets/task_card.dart`, `life_agent_flutter/lib/widgets/plan_section.dart`
  - Skeletons: `life_agent_flutter/lib/widgets/shimmer_loading.dart`
  - Task guide: `life_agent_flutter/lib/widgets/task_guide_widget.dart`
- **Dependencies**: mostly core Flutter; shimmer is custom (no external package)
- **Integration notes**: These are largely endpoint-agnostic; keep them and rewire data models as backend evolves.

### 6) Models + serialization patterns

- **Files**: `life_agent_flutter/lib/models/*.dart`
- **Integration notes**: Patterns are consistent (`fromJson/toJson`, enums). Expect refactors once Phase-1 memory schema is finalized.

## Immediate “do-this-next” (highest ROI)

1) **Fix secrets + env switching (Phase 0A)** — unblock safe collaboration and deployment.
2) **Add Memory screen + memory policy UX (Phase 1)** — matches the “memory-first” spec and builds user trust.
3) **Upgrade plan setup to HITL approvals (Phase 2)** — improves plan quality and transparency.

