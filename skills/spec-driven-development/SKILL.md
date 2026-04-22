---
name: spec-driven-development
description: Creates specs before coding. Use when starting a new project, feature, or significant change and no specification exists yet. Use when requirements are unclear, ambiguous, or only exist as a vague idea.
---

# Spec-Driven Development

## Overview

Write a structured specification before writing any code. The spec is the shared source of truth between you and the human engineer — it defines what we're building, why, and how we'll know it's done. Code without a spec is guessing.

## When to Use

- Starting a new project or feature
- Requirements are ambiguous or incomplete
- The change touches multiple files or modules
- You're about to make an architectural decision
- The task would take more than 30 minutes to implement

**When NOT to use:** Single-line fixes, typo corrections, or changes where requirements are unambiguous and self-contained.

## The Gated Workflow

Spec-driven development has four phases. Do not advance to the next phase until the current one is validated.

```
SPECIFY ──→ PLAN ──→ TASKS ──→ IMPLEMENT
   │          │        │          │
   ▼          ▼        ▼          ▼
 Human      Human    Human      Human
 reviews    reviews  reviews    reviews
```

### Phase 1: Specify

Start with a high-level vision. Ask the human clarifying questions until requirements are concrete.

**Declare the phase first:**

```
[DESIGN] I am clarifying the requirements for [feature]. Can you provide more details on [specific aspect]?
```

**Pre-Modification Review.** Before creating or modifying any spec document, test outline, or design artifact:

- Review existing approved content to confirm the intended content does not already exist (avoid duplication)
- If a related artifact already exists, modify it rather than creating a new one — unless the human explicitly approves a new artifact
- Apply the **Minimal Change Principle**: change only what is strictly necessary to meet the new requirement
- Document the rationale for any modification and reference the original artifact being changed

**Surface assumptions immediately.** Before writing any spec content, list what you're assuming:

```
ASSUMPTIONS I'M MAKING:
1. This is a web application (not native mobile)
2. Authentication uses session-based cookies (not JWT)
3. The database is PostgreSQL (based on existing Prisma schema)
4. We're targeting modern browsers only (no IE11)
→ Correct me now or I'll proceed with these.
```

Don't silently fill in ambiguous requirements. The spec's entire purpose is to surface misunderstandings *before* code gets written — assumptions are the most dangerous form of misunderstanding.

**Write a spec document covering these six core areas:**

1. **Objective** — What are we building and why? Who is the user? What does success look like?

2. **Commands** — Full executable commands with flags, not just tool names.
   ```
   Build: npm run build
   Test: npm test -- --coverage
   Lint: npm run lint --fix
   Dev: npm run dev
   ```

3. **Project Structure** — Where source code lives, where tests go, where docs belong.
   ```
   src/           → Application source code
   src/components → React components
   src/lib        → Shared utilities
   tests/         → Unit and integration tests
   e2e/           → End-to-end tests
   docs/          → Documentation
   ```

4. **Code Style** — One real code snippet showing your style beats three paragraphs describing it. Include naming conventions, formatting rules, and examples of good output.

5. **Testing Strategy** — What framework, where tests live, coverage expectations, which test levels for which concerns.

6. **Boundaries** — Three-tier system:
   - **Always do:** Run tests before commits, follow naming conventions, validate inputs
   - **Ask first:** Database schema changes, adding dependencies, changing CI config
   - **Never do:** Commit secrets, edit vendor directories, remove failing tests without approval

**Spec template:**

```markdown
# Spec: [Project/Feature Name]

## Objective
[What we're building and why. User stories or acceptance criteria.]

## Tech Stack
[Framework, language, key dependencies with versions]

## Commands
[Build, test, lint, dev — full commands]

## Project Structure
[Directory layout with descriptions]

## Code Style
[Example snippet + key conventions]

## Testing Strategy
[Framework, test locations, coverage requirements, test levels]

## Boundaries
- Always: [...]
- Ask first: [...]
- Never: [...]

## Success Criteria
[How we'll know this is done — specific, testable conditions]

## Open Questions
[Anything unresolved that needs human input]
```

**Reframe instructions as success criteria.** When receiving vague requirements, translate them into concrete conditions:

```
REQUIREMENT: "Make the dashboard faster"

REFRAMED SUCCESS CRITERIA:
- Dashboard LCP < 2.5s on 4G connection
- Initial data load completes in < 500ms
- No layout shift during load (CLS < 0.1)
→ Are these the right targets?
```

This lets you loop, retry, and problem-solve toward a clear goal rather than guessing what "faster" means.

**Human Approval.** Design must be approved by the human programmer before proceeding to Phase 2. Present the spec with:

```
[DESIGN] I have completed the design for [feature]. Please review and approve.
Here is the detailed design document: [link/details].
```

Do not proceed until explicit human approval is received. Then commit the design documentation and the draft test cases:

```
docs: design and test plan for [feature] — approved
```

### Phase 2: Plan

With the validated spec, generate a technical implementation plan:

1. Identify the major components and their dependencies
2. Determine the implementation order (what must be built first)
3. Note risks and mitigation strategies
4. Identify what can be built in parallel vs. what must be sequential
5. Define verification checkpoints between phases

The plan should be reviewable: the human should be able to read it and say "yes, that's the right approach" or "no, change X."

### Phase 3: Tasks

Break the plan into discrete, implementable tasks:

- Each task should be completable in a single focused session
- Each task has explicit acceptance criteria
- Each task includes a verification step (test, build, manual check)
- Tasks are ordered by dependency, not by perceived importance
- No task should require changing more than ~5 files

**Task template:**
```markdown
- [ ] Task: [Description]
  - Acceptance: [What must be true when done]
  - Verify: [How to confirm — test command, build, manual check]
  - Files: [Which files will be touched]
```

### Phase 4: Implement

Execute tasks one at a time following `incremental-implementation` and `test-driven-development` skills. Use `context-engineering` to load the right spec sections and source files at each step rather than flooding the agent with the entire spec.

## Iterative Refinement Cycle

After implementation, follow the TDD iterative cycle until all requirements are met:

```
Design ──→ Development ──→ Testing ──→ Verification
   ▲                            │           │
   └────────────────────────────┘           │
         (if design changes needed)         │
   ▲                                        │
   └────────────────────────────────────────┘
         (if verification reveals gaps)
```

- **Development:** Implement against the approved spec. No scope deviation without human approval.
- **Testing:** Execute tests against the implementation. Do not modify code during the testing phase — only report results and identify deviations. Commit the test results (pass or fail) before moving to Verification.
- **Verification:** Evaluate test results. Suggest *minimal* design changes supported by concrete test evidence. Obtain human approval before applying changes. Commit the approved design modifications.
- **Refinement:** Apply approved design changes, then restart Development → Testing → Verification. Each cycle gets its own commit.

**Evidence-Based Modifications:** Any proposed design change during Verification must cite the specific failing test(s), the exact deviation from the expected behavior, and the smallest adjustment that would correct it. Never suggest broad rewrites based on a single test failure.

## Phase Communication Protocol

Declare the current phase at the start of **every** interaction. This prevents scope confusion and ensures the human always knows what kind of response is appropriate.

**Phase declarations (use exactly these formats):**

```
"[DESIGN] I am in the Design phase. I am clarifying the requirements for [feature].
 Can you provide more details on [specific aspect]?"

"[DESIGN] I have completed the design for [feature]. Please review and approve.
 Here is the detailed design document: [link/details]."

"[DEVELOPMENT] I am in the Development phase. I am implementing the code based on
 the approved design document. Is there any clarification required?"

"[DEVELOPMENT] The development based on the approved design document for [feature]
 is done and includes the unit tests. Please review and give sign-off.
 The source code and tests are here: [link/details]."

"[TESTING] I am in the Testing phase. I am running the unit tests for [feature]."

"[TESTING] The test failed for [test name]. Here is the error description: [details].
 This might relate to [potential part of design]."

"[VERIFICATION] I am in the Verification phase. After testing, I noticed that the
 design needs to be changed slightly in [specific area]. Here is the suggestion:
 [details] and rationale: [details]."

"[VERIFICATION] Here is the modified design suggestion for [feature]. Please approve
 to proceed. The modification is [details], based on test results."
```

**Feedback gate:** Whenever human action is required before proceeding, MUST state:
1. What decision or input is needed
2. Why it is needed
3. What will happen next once the human responds

```
"Before proceeding to development: the spec references 'user authentication' but does not
 specify whether to use session cookies or JWTs. This affects the DB schema and security model.
 Please confirm the approach so I can finalize the spec and begin implementation."
```

**Design adherence:** During Development, if the implementation reveals that the approved design is incomplete or contradictory, stop and raise it:

```
"[DEVELOPMENT — BLOCKER] The approved design specifies X, but the existing code enforces Y,
 making X impossible without modifying [module]. I am not proceeding. Please advise."
```

## Production-Grade Elegance

Every design must aim for elegance before being marked approved:

- **Small, well-defined interfaces** — each function/class does one thing, has a narrow surface area, and a predictable contract
- **Clear separation of concerns** — boundaries between layers are explicit; no business logic in infrastructure, no infrastructure details in domain code
- **Predictable failure modes** — every error path is defined; no silent failures; errors propagate cleanly to the caller
- **Minimal surface area** — expose only what callers need; default to private/internal; add `public` only when justified

Before approving a design, evaluate it: "Would a staff engineer reading this say it is production-ready?"

## Design for Production

Every spec approved for implementation must address these items (or explicitly justify their omission):

```markdown
## Production-Readiness (required before design approval)

### Acceptance Criteria & Metrics
- SLOs/SLAs: [latency targets, availability targets, error budget]
- Success verification: [how we confirm the feature is working in production]

### API Contracts & Versioning
- Request/response schemas with types
- Versioning strategy (e.g., path versioning, header versioning)
- Backward-compatibility guarantees

### Error Modes & Recovery
- Expected error classes and their HTTP/gRPC status codes
- Retry and backoff strategy
- Idempotency requirements
- Graceful degradation behavior when dependencies are unavailable

### Observability
- Key metrics to emit (counters, histograms, gauges)
- Structured log fields for this feature
- Tracing spans required
- Expected dashboards and alert thresholds

### Performance Budget
- Throughput target (requests/sec or jobs/sec)
- Latency target (p50, p95, p99)
- Resource limits (CPU, memory, DB connections)
- Scaling assumptions

### Security & Dependencies
- Threat model: who can call this? what can they do?
- Required security reviews (auth, authz, data validation)
- New dependencies: license checked, vulnerability scan passed

### Deployment & Rollback
- Canary / blue-green / feature-flag strategy
- Data migration plan (if applicable)
- Rollback procedure and maximum time-to-rollback

### Test Matrix
- Unit tests: [scope]
- Integration tests: [scope]
- End-to-end tests: [critical flows only]
- Performance tests: [thresholds]
- Security tests: [attack surfaces]

### Runbook Outline
- How to detect this feature is broken
- Key dashboards and log queries
- Rollback steps
- On-call escalation path
```

These items must be present or explicitly waived (with human approval) before a design is marked approved.

## Keeping the Spec Alive

The spec is a living document, not a one-time artifact:

- **Update when decisions change** — If you discover the data model needs to change, update the spec first, then implement.
- **Update when scope changes** — Features added or cut should be reflected in the spec.
- **Commit the spec** — The spec belongs in version control alongside the code.
- **Reference the spec in PRs** — Link back to the spec section that each PR implements.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "This is simple, I don't need a spec" | Simple tasks don't need *long* specs, but they still need acceptance criteria. A two-line spec is fine. |
| "I'll write the spec after I code it" | That's documentation, not specification. The spec's value is in forcing clarity *before* code. |
| "The spec will slow us down" | A 15-minute spec prevents hours of rework. Waterfall in 15 minutes beats debugging in 15 hours. |
| "Requirements will change anyway" | That's why the spec is a living document. An outdated spec is still better than no spec. |
| "The user knows what they want" | Even clear requests have implicit assumptions. The spec surfaces those assumptions. |

## Red Flags

- Starting to write code without any written requirements
- Asking "should I just start building?" before clarifying what "done" means
- Implementing features not mentioned in any spec or task list
- Making architectural decisions without documenting them
- Skipping the spec because "it's obvious what to build"
- Creating a new spec artifact when a relevant one already exists (Pre-Modification Review violation)
- Advancing to Development without explicit human approval of the design

## Verification

Before proceeding to implementation, confirm:

- [ ] Pre-Modification Review performed (no duplicate spec artifacts created)
- [ ] The spec covers all six core areas
- [ ] The human has reviewed and **explicitly approved** the spec
- [ ] Success criteria are specific and testable
- [ ] Boundaries (Always/Ask First/Never) are defined
- [ ] The spec is saved to a file in the repository
- [ ] Design documentation and test case outlines are committed after approval
- [ ] Production-Readiness section is present or each item is explicitly waived with human approval
- [ ] Design evaluated against Production-Grade Elegance criteria
- [ ] Phase Communication Protocol in use (phase declared at start of each interaction)
- [ ] Any design changes during Verification are evidence-based (cite failing tests) and minimal
