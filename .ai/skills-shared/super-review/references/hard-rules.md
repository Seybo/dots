# HARD RULES BLOCK

Paste this entire block into EVERY reviewer prompt — all seven Phase 1 reviewers and both Phase 2 adjudicators, regardless of selected agent mode. Replace `<WORKTREE_DIR>` with the absolute worktree path.

```
LOCATION CITATIONS - HARD RULE:
- ALWAYS open the actual file via Read tool before citing a location.
- Cite file-line numbers from the actual file as it exists in the worktree.
- NEVER cite diff hunk positions, diff line numbers, or "+N" annotations.
- If the diff shows a change without showing the surrounding file, OPEN the file first.
- Format: `path/to/file.rb:NN-MM` (range OK) or `path/to/file.rb:NN`.
- Wrong: "spec/foo.rb:4075" if the file is only 300 lines long.
- All file paths are relative to the worktree root: <WORKTREE_DIR>
- This is non-negotiable: bad line numbers waste reviewer time and undermine trust.

FORMAT OF EACH FINDING - HARD RULE (no one-liners):
[SEVERITY][category] path/to/file.ext:NN-MM - short headline (one sentence)

What: 2-4 sentences. Quote the actual code (1-3 lines) so the reader sees the
issue without opening the file. Explain the contradiction or failure scenario in
concrete terms. If the bug is conditional, state the conditions.

Why it matters: 1-2 sentences. Real consequence (data loss, double-spend, P0
silent failure, regression on documented behavior). Skip "could be cleaner".

Fix: concrete code-level suggestion. Not "consider X" - say "change Y to Z" or
"add CHECK constraint on (col1, col2)" or "rewrite as multi_insert_conflict".

If you cannot follow this format, your finding will be dropped at synthesis.

INTENT VERIFICATION:
For ANY behavior change in the diff that is NOT explicitly called out in the PR
description (constants, defaults, thresholds, validity periods, retry counts,
log levels, environment variable names, default scopes), surface as:
  [INTENT-VERIFY] file:line - "<old value> → <new value>" not mentioned in PR
  description. Confirm intent with author.
This is mandatory even if the change looks safe. The PR description is the
author's contract - silent changes need explicit confirmation.

DOMAIN KNOWLEDGE:
If the PR touches a well-known third-party API/SDK, think about KNOWN limits
and quirks BEFORE checking generic correctness. Examples:
- Apollo.io: 50k results / 500-page hard cap, after ~25k results duplicates
  and garbage. /mixed_companies/search requires X-Api-Key header.
- Stripe: idempotency keys live 24h, webhooks need signature verification.
- GitHub API: 5000 req/h authenticated, secondary rate limits, conditional
  requests via ETag/If-None-Match.
- OpenAI: tokens != characters, response truncation at max_tokens, streaming
  needs reconnect logic.
- AWS SDK: pagination via continuation tokens, S3 eventual consistency on
  list-after-write, IAM permission boundary subtleties.
If PR uses one of these without respecting the limit/quirk, flag it.

CROSS-FIELD CONSISTENCY:
Look for cases where two related operations use DIFFERENT fields to identify
the same thing. Examples:
- Approval gate filters by `campaign_id` but idempotency key is built from
  `campaign_id + config_hash + page + per_page` - one approval covers infinite
  filter changes.
- Reservation uses `idempotency_key` but reuse check uses `request_hash` -
  cache inconsistency.
- Write to column A, read from column B.
- Cache key includes timestamp but lookup omits it.
Surface these as [HIGH] - they are the kind of bug that survives review by
single-lens specialists.

SELF-CORROBORATING DIFF - HARD RULE (the oracle moved with the code):
A diff can be internally consistent and still wrong. When the SAME change edits
both a behavior AND the thing that would otherwise prove it wrong, that thing
stops being evidence. Passing specs, a matching comment, a green fixture prove
NOTHING when they were rewritten in the same diff to agree with the new code.
Watch for these paired edits and treat the "confirming" side as suspect, not
as proof:
- Code changed AND its test/fixture/expected-output/snapshot changed together
  -> a green suite only proves the test now matches the code, not that either
  is correct. The specs were moved to bless the behavior.
- Code changed AND the comment / docstring / doc that describes it changed
  together -> the comment corroborates the code because the same author wrote
  both from the same assumption; it is not independent confirmation.
- A constant / threshold / enum changed AND the assertion checking it changed.
- A parser/validator NARROWED (fields dropped, a branch removed, a nil
  hardcoded) AND the sample input it reads edited to no longer contain the
  dropped data.
The rule: when behavior and its oracle move in the same direction in one diff,
you MUST find an oracle OUTSIDE the diff before trusting it. Options, best
first:
0. THE TASK / PR DESCRIPTION + AC YOU WERE ALREADY GIVEN. Check this FIRST -
   it is free and already in your prompt (Step 2 passes it to every reviewer).
   Does the change contradict a stated design decision, requirement, or
   acceptance criterion? Silent removal of an AC-required behavior, or code
   that does the OPPOSITE of what the description says, is a finding on its own
   - you do not need any external system to confirm it. Also surface it as
   [INTENT-VERIFY]. CAVEAT: the AC/description can SHARE the author's false
   premise and argue FOR the bug (e.g. an AC that says "delete X, it's
   redundant" when X was load-bearing) - so oracle-0 is necessary, NOT
   sufficient. When the change touches an external-API shape or deletes code,
   always also run oracles 1-3.
1. The vendor's real API output / official docs (never a fixture as proof of an
   external shape - a fixture is an assumption, and a sanitized/redacted sample
   is NEVER the real shape).
2. An independent existing caller / consumer that the diff did NOT touch.
3. The pre-diff version in git history - does the change DELETE data or a code
   path the rest of the system still relies on?
If the only thing vouching for a change is something the same change edited,
flag it:
  [HIGH][unverified-by-construction] file:line - behavior X and its <test/
  fixture/comment> were changed together; correctness is unconfirmed because
  nothing outside this diff vouches for it. Verify <field/value> against
  <AC item / external source>.
This is the class that defeats convergence AND a green suite: every automated
signal comes back green because the check was edited to pass. Typical shape: a
parser is narrowed on a premise about the payload, and the SAME diff rewrites
the fixture to match the premise - so specs, lint, and comment all agree while
production breaks on the real payload.

IN-CODE TELLS the premise is unverified (spot these, then verify via oracle 1 -
the vendor output, NOT the fixture):
- Multi-fallback access on a provider payload for ONE value
  (resp['a'] || resp['b'] || resp['c']) = the author doesn't know the real
  field. Confirm the field EXISTS in vendor output before trusting any read of
  it; a passing fixture only proves the fixture was written to match.
- A fallback sourced from somewhere OTHER than that response (a second lookup, a
  source table) = the code admitting the payload is too thin to rely on.

DELETED CODE IS EVIDENCE - HARD RULE:
When a diff DELETES a file/service/branch citing "redundant / superseded /
dead", read the deleted code's OWN comments/docstring FIRST and test the removal
rationale against what it says it did - especially whether it ran at a DIFFERENT
pipeline stage or on DIFFERENT data than the thing claimed to subsume it (same
algorithm != same effect). Reviewing a deletion ONLY for dangling references
(callers/requires) misses this. The removal rationale - even when it lives in
the AC/PR description - is the CLAIM UNDER TEST, not an oracle. Watch for a
deletion whose own docstring describes a purpose the surviving code does NOT
cover: after the delete every remaining file agrees, because the one file that
dissented is gone.

REACHABILITY EVIDENCE GATE - HARD RULE:
Phase 1 may emit an uncertain candidate so downstream review can investigate it.
Phase 2 may answer AGREE only when the trigger is reachable according to at
least one independent evidence source:
- task_contract: task/PR acceptance criteria require or permit the scenario
- vendor_contract: official provider documentation or real provider output permits it
- existing_untouched_code: a caller, configuration, or persisted-data path outside
  this diff constructs it
- reproduction: a concrete reproduction through the existing public interface
- schema_invariant: the current schema and write paths demonstrably permit it

These are NOT reachability evidence:
- an imagined direct caller or future writer
- absence of a value from vendor documentation
- a test, fixture, comment, or documentation changed in the same diff
- reviewer agreement or convergence
- impact alone

Every Phase 2 AGREE decision must state the exact trigger, mechanism,
reachability_source, and concrete evidence. If evidence is missing, answer
NEEDS_CONTEXT and name what would prove or disprove the trigger. Never convert
"the contract does not prove X" into "the contract proves not-X". Phase 3 must
not surface NEEDS_CONTEXT candidates as actionable findings.

PRECONDITION & SEVERITY DISCIPLINE - HARD RULE:
For ANY finding that depends on control flow, exception handling, or a state
machine ("the error is swallowed", "the call is left in state X", "this masks
the real error", "X is lost"):
1. Trace the NORMAL path first, then state the EXACT trigger in one line:
   "Triggers only when: <condition>." If it needs a SECOND simultaneous failure
   (a compound failure - e.g. the error-recording write ITSELF raises), say so.
2. Severity = likelihood(precondition) x impact, NOT impact alone. A real bug
   gated behind a rare/compound precondition is at most Medium, NOT High.
3. Verify language semantics before naming a consequence. Do NOT write
   "lost"/"swallowed"/"never"/"silently" unless confirmed. (Ruby: raising inside
   a `rescue` auto-sets the new exception's `.cause` to the original - so it is
   NOT lost, only possibly not surfaced by the error formatter. Also check
   ensure-blocks, retry order, transaction/rollback order.) Use precise wording
   like "not surfaced to the operator (preserved as `.cause`)".
If you cannot state the precondition crisply in one line, you have NOT verified
it - downgrade or move to "Verify Manually"; do not flag it High.

COVERAGE OVER SELF-CENSORSHIP (PHASE 1 ONLY):
Phase 1 should report every candidate it finds, including uncertain ones, and
mark them `[confidence: low]`. Do NOT silently drop a candidate because you
doubt its importance: Phase 2 investigates it, and a candidate dropped at the
source is unrecoverable. This rule does not authorize Phase 2 AGREE or Phase 3
surfacing without the reachability evidence required above. (The SKIP LIST
below excludes noise classes, not uncertain candidates. PRECONDITION discipline
still applies: state the trigger honestly and downgrade severity.)

SKIP LIST (do not surface these as findings):
- Formatting, whitespace, line breaks (linter catches)
- Naming preferences (Rubocop/eslint catches)
- "Consider adding a comment"
- "Could be extracted to a helper" (unless 4+ duplications)
- Suggestions to add tests for trivial getters
- Pre-existing bugs not introduced by THIS diff
```
