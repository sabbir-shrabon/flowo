#**make subtasks for every tasks, that can be made by ai or manual**
    manual tasks: tasks that need human intervention to be made
    ai tasks: "tasks that can be made by ai"


# Subtask System — How to Think About This

---

## The Mental Model First

A task in your current system is a unit of work inside a milestone. A subtask is a unit of clarity inside a task. The distinction matters because subtasks are not progress markers in the same way tasks are — they are a breakdown of *how* to execute a single task. When someone sees a task called "Set up authentication" they might not know where to start. Subtasks answer the question "what does doing this actually look like step by step." So the subtask layer is a comprehension and execution aid, not a planning layer.

This means subtasks should never affect the milestone pressure calculation or the today screen task count. A task is either done or not done at the milestone level. Subtasks are internal to that task. Completing all subtasks should mark the parent task as done automatically, but an incomplete subtask should never block the task from being manually marked done if the user chooses to do so.

---

## Two Ways to Create Subtasks

**Manual creation** is when the user knows what they need to do and just wants to break it down themselves. They type each subtask one by one. This should be fast — a simple text input inside the task detail card, press enter to add, no friction. Manual subtasks have no description, no detail, just a title and a checkbox.

**AI generation** is when the user does not know how to approach the task and wants the system to break it down for them. They tap a button, the API is called with the task title and the parent plan context, and the system returns 4 to 7 concrete actionable subtasks. The user sees them appear, can edit any of them, delete ones they do not want, or add their own on top. This is the same pattern as how the roadmap itself is generated — AI produces a starting structure, human refines it.

---

## How the UI Should Look

The task detail card currently exists as a screen the user lands on when they tap a task. This is where subtasks live. The card has the task title at the top, a description area below it, and then a section called "How to do this" or simply "Steps" where subtasks appear as a checklist.

At the bottom of the subtask list there are two options sitting side by side — a text field that says "Add a step" for manual entry and a button that says "Generate steps with AI" for API generation. These two options are always visible at the bottom of the card so the user never has to search for how to add subtasks.

Each subtask row is a simple checkbox on the left, the subtask title in the middle, and a delete icon on the right that appears only when the user long presses or enters an edit mode. The checkboxes are large and tappable. When a subtask is checked it gets a strikethrough style and moves to the bottom of the list, keeping the unchecked ones at the top so the user always sees remaining work first.

A small progress indicator sits at the top of the subtask section showing something like "3 of 7 steps done" as a fraction or a thin progress bar. This gives the user a sense of momentum without being heavy-handed about it.

---

## What Happens When All Subtasks Are Checked

When the last subtask is checked, the system shows a brief confirmation moment — something subtle like the task card title area getting a soft green tint — and automatically marks the parent task as done. This triggers the existing task completion flow: the task moves to the completed section on the today screen, the milestone completion check runs, and if all tasks in the milestone are done the milestone auto-completes. The subtask layer plugs directly into the existing completion chain without breaking anything.

If the user marks the parent task as done manually without completing all subtasks, the subtasks stay as they are. They are not force-completed. The user simply chose to call the task done at the parent level. The subtask data is preserved in case the user unchecks the task later.

---

## The AI Generation Flow in Detail

When the user taps "Generate steps with AI" the button shows a loading state. The API call sends the task title, the milestone title it belongs to, and the overall plan goal as context. This context is important — generating subtasks for "Write unit tests" inside a "Build backend API" milestone inside a "Launch a SaaS product" plan should produce different subtasks than generating them for the same task title in a different context.

The API returns a list of 4 to 7 subtasks as plain text strings. They appear in the UI one by one with a subtle animation so it feels responsive. Each generated subtask has a small edit icon next to it so the user can immediately rename any of them before saving. At the bottom of the generated list there are two buttons — "Save all" and "Edit before saving." Save all commits them directly. Edit before saving lets the user tap each one to rename, drag to reorder, or swipe to delete before committing.

If the user already has manually created subtasks and then taps generate, the system asks whether to replace existing subtasks or add the generated ones below the existing ones. Never silently overwrite what the user already typed.

---

## Data Structure to Think About

Each subtask needs a parent task ID, an order index so they stay in the user's arranged sequence, a title, a completed boolean, a created-at timestamp, and a source field that records whether it was created manually or by AI. The source field is useful later for the memory layer — if AI-generated subtasks get deleted frequently it is a signal the generation quality needs improvement for that task category.

---

## What This Changes About the Today Screen

Nothing changes about the today screen task cards at the surface level. A task still appears as a single card. But the card can now show the subtask progress fraction below the task title — "2 of 5 steps done" in small text under the task name. This is optional and should only appear if the task actually has subtasks. Tasks with no subtasks look exactly as they do today. Tapping the task still navigates to the task detail card where the full subtask list lives.

---

## What This Does Not Do

Subtasks do not appear on the today screen as individual items. They are never pulled into the daily task count formula. They do not create their own rollover behavior. They do not have their own due dates. They are entirely contained within their parent task. The today screen remains clean and the adaptive engine remains unaffected. Subtasks are purely a feature of the task detail view — a tool for execution, not for planning.




Today Screen
  └─ User taps a task card
       └─ Opens NEW FULL SCREEN (Task Detail Screen)
            ├─ Top: Task Title (tappable → opens bottom drawer with AI chat details)
            ├─ Middle: Subtasks Section
            │    ├─ Manual: "+" button → user types subtask → adds to list
            │    └─ AI: "Tell AI to make subtasks" button → API call → subtasks appear
            └─ Bottom: Back navigation


new screen:
┌──────────────────────────────────┐
│  ← Back                          │
├──────────────────────────────────┤
│                                  │
│  Task Title (tappable)           │
│  ─────────────────────────       │
│                                  │
│  Progress: 3 of 7 steps done     │
│  ████████████░░░░░░░░  43%       │
│                                  │
│  ☑ Install dependencies          │  ← checked, strikethrough
│  ☑ Set up project structure      │  ← checked, strikethrough
│  ☐ Configure environment         │  ← unchecked, at top
│  ☐ Write main logic              │
│  ☐ Write unit tests              │
│  ☐ Deploy to staging             │
│  ☐ Run integration tests         │
│                                  │
│  ┌──────────────────────────┐    │
│  │ + Add a step...          │    │  ← manual input
│  └──────────────────────────┘    │
│                                  │
│  ┌──────────────────────────┐    │
│  │ 🤖 Tell AI to make steps │    │  ← AI generation button
│  └──────────────────────────┘    │
│                                  │
└──────────────────────────────────┘

When user taps task title:
┌──────────────────────────────────┐
│  (Bottom Drawer slides up)       │
│  Task details / AI chat          │
│  ┌────────────────────────┐      │
│  │ AI: Here's how to      │      │
│  │ approach this task...  │      │
│  └────────────────────────┘      │
│  [Chat input]                    │
└──────────────────────────────────┘