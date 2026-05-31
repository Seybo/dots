---
name: explain-flow
description: >
  Explain how one specific flow or feature works by tracing its execution path
  through the code, from the trigger that starts it to the outcome it produces.
  Use when the user asks what happens when they perform an action, hit an endpoint,
  run a job/command, or use a feature in an unfamiliar codebase ("what happens when
  a user signs up?", "how does the import job run?", "walk me through checkout").
  Leads with a plain-language walkthrough, then reveals deeper layers on request,
  stopping after each so the user can digest, ask questions, or redirect.
---

# explain-flow

Trace one flow from trigger to outcome by **reading** the code path, revealing it
from high-level to specific with a stop after every layer.

## When to use / when not

Use this when the user wants to follow what *happens* for one named scenario —
the ordered path of execution.

Boundary vs sibling skills (keep these distinct):

- **explain-flow** traces the execution path *by reading* the code. ← this skill
- **explain-behavior** establishes behavior *by running* it (tests, inputs, observed output).
- **explain-architecture** maps *static structure* — components, dependencies, boundaries — not a single path.
- **explain-bottom-up** starts from one confusing file/function and expands outward, rather than following a flow forward.

If the user hasn't named a single flow (they want "the whole system" or "this one
file"), this is the wrong skill — say so and point to explain-architecture or
explain-bottom-up.

## Inputs

Before tracing, you need:

1. **The flow** — what behavior to follow (the feature, action, or scenario).
2. **The trigger** — what starts it: an HTTP route, a CLI command, a queue/event
   handler, a UI action, a cron job, or a public method.
3. **The outcome** — what the user considers the end (a response, a DB write, a
   sent message, a returned value).

Optional: a starting file, route, or symbol the user already suspects.

**If the flow is ambiguous, ask before tracing** — do not guess and trace the wrong
path. Specifically ask when: the named feature maps to several entry points; the
trigger is unclear; or "the outcome" could be one of multiple endpoints. One round
of clarifying questions, then proceed.

## Investigation workflow

1. **Find the entry point.** Search for where the trigger is registered — route
   tables, CLI command definitions, event/handler bindings, public method names
   that match the feature. Confirm the entry point with the user if more than one
   plausible candidate exists.
2. **Trace forward by reading.** From the entry point, follow calls/usages along the
   path. Read only the files on the path. Do **not** run the code (that is
   explain-behavior) and do **not** scan the whole project — broad search is allowed
   only to locate the entry point, not to narrate the flow.
3. **Stay on one path.** Follow the main scenario first. Note branches and error
   paths, but don't chase every branch until the user asks for that drill-down.
4. **Track proven vs inferred.** Anything read in code is proven — cite it as
   `file:line`. Anything you're guessing (a value's origin, an external system's
   response, a config default) is inferred — label it as such.
5. **Keep a question log.** Maintain a running list of unknowns (a symbol you
   couldn't resolve, config you couldn't find, an external call whose behavior isn't
   in this repo). Surface it at each stop instead of papering over it.

## Explanation structure — reveal in layers

Each layer ends with a **stop** (see the interaction protocol). Do not pour all
layers out at once.

**Layer 0 — Plain-language walkthrough.** This is the default first result and the
most important layer — for many users it is the whole answer. Tell the entire flow
as a short narrative in everyday language:

- Walk the steps **in order as cause and effect** — a numbered story of what happens
  and why, not a list of function names.
- Name actors by their **role** — "the main agent", "the child agents", "the
  database", "the search step before this one" — never by symbol or file path.
  **No `file:line` citations in this layer**; they clutter the story.
- State **where data lives and what is the source of truth** in plain terms (e.g.
  "the database holds the real verdicts; the files are just reports that can be
  rebuilt at any time").
- Bring in the **step right before** as the origin of the input and the **step
  right after** as the destination of the output when that is where the data comes
  from or goes — even though they sit outside the traced flow, naming them makes the
  story land. Prefer plain words like "the earlier step" / "the next step" over
  jargon like "upstream" / "downstream".
- Close with a one-sentence **"shape of the whole thing"** recap.

Keep it accurate — it rests on the code you read — but free of jargon. A non-expert
should be able to follow it end to end. Length follows the flow: a few sentences for
a simple one, a short numbered narrative for a multi-stage one.

Example of the register (a signup flow): *"When someone submits the signup form, the
web server hands the request to the accounts service. That service checks the
database to make sure the email is not already taken; if it is free, it creates the
new user row and then asks the email service to send a confirmation link. The
database now holds the new account; the confirmation email is what the user sees. In
short: form submit → validate → create the user in the database → send
confirmation."*

→ stop, and offer a diagram or the technical spine (Layer 1) as the next step.

**Layer 1 — The spine (technical map).** The same flow as Layer 0, now as the
ordered execution path at the level of functions/services, not lines:
`entry point → step → step → outcome`. Each step is one line naming the responsible
function/service and the file it lives in. This is the code-level map of the whole
flow. When the flow is multi-actor or non-linear, draw the spine as an ASCII diagram
(see Diagrams); otherwise keep the one-line-per-step list. → stop.

**Layer 2+ — Drill-down (one segment at a time).** For the segment the user picks,
go specific:

- what the code in this segment does,
- **data in / out** — what it receives and what it passes on, and any transformation,
- **side effects** — DB writes, external calls, enqueued jobs, emitted events, state changes,
- **branches & errors** — the conditionals and failure paths for this segment,
- **key files** — `file:line` references touched here,
- **proven vs inferred** — explicit for anything not read directly,
- **suggested next drill-downs** — which adjacent segments are worth zooming into.

A small ASCII data-flow or sequence diagram scoped to this segment is welcome when
it clarifies a transformation or hand-off (see Diagrams).

→ stop after each segment.

## Diagrams (ASCII)

Draw an ASCII diagram when it carries information a linear list flattens — not by
default. It earns its place when:

- **multiple actors interleave** (e.g. caller, service, worker, external API) — a
  swimlane or sequence shows who does what, and when;
- **data crosses a boundary more than once** (e.g. DB → file → DB → file) — a
  data-flow diagram makes the round-trip visible;
- **the control flow branches, fans out/in, or has gates/pauses** (approval stops,
  retries, waves) — a flow diagram shows the shape;
- the user is visibly tracking the wrong mental model of one of the above.

Skip it when the flow is a short linear chain — the Layer 1 spine list already is
the diagram. One diagram that answers the current question beats several decorative
ones.

Rendering and form:

- **ASCII renders directly** in a terminal and in markdown — make it the default
  visual.
- **Mermaid does not render** in a plain terminal (it shows as a code block). Offer
  a Mermaid version only when the user views output in a GitHub/IDE markdown
  preview, or when they ask.
- Keep diagrams under ~80 columns so they don't wrap. Boxes hold names, not prose;
  label edges with the function/command/event that performs the transition.
- A diagram **supplements** the traced steps — it never replaces `file:line`
  citations, and an inferred edge must still be marked inferred.

## Interaction protocol (the stops)

After Layer 0, after Layer 1, and after every Layer 2+ segment, **stop and ask what
to do next**. Offer these choices explicitly:

- **continue** — go to the next step on the spine,
- **zoom** — drill into a specific step,
- **diagram** — render or redraw an ASCII diagram of the current spine or segment (offer this when the flow is multi-actor, multi-hop, or gated; see Diagrams),
- **tests** — show the tests that exercise this segment (read them to confirm behavior; hand off to explain-behavior if the user wants to *run* them),
- **redirect** — change direction, follow a branch, or jump to a different part of the flow.

Never advance past a stop on your own, even if the next step seems obvious. The point
of the stops is to let the user set the pace.

## Uncertainty handling

- Cite `file:line` for everything proven.
- Label every inference as inferred and say what would confirm it.
- If the path leaves this repo (external service, vendored dependency, generated
  code), say where it goes and stop tracing there unless the user wants to follow.
- If you can't find the entry point, say so and report what you searched — do not
  invent a plausible-sounding path.

## Self-review checklist (before considering an explanation done)

- Did it focus on **one** flow, not the whole system?
- Did it **lead with the plain-language walkthrough** — role-named actors, cause-and-effect, where data lives, no `file:line` — so a non-expert could follow it?
- Did it go **abstract → specific** (plain-language walkthrough → spine → segments), not dump everything?
- Did it **stop** at every layer and let the user steer?
- For a multi-actor or multi-hop flow, did it offer or draw an ASCII diagram instead of leaning on prose alone?
- Is every claim either cited (`file:line`) or labeled inferred?
- Would someone unfamiliar with the app now know where this flow lives and how it runs?
