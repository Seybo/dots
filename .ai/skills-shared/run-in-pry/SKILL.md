---
name: run-in-pry
description: >-
  Run Ruby code inside a project's Pry console quickly and directly. Use when the user asks
  to run something "in pry", "from pry", "inside pry", or via a Rails/Ruby console, especially
  when they want a quick one-off command using the current repo's Pry setup.
---

# Run in Pry

Use this skill when the user asks to run Ruby code in Pry or a project console.

## Core rule

Do **not** turn this into a discovery/existence-check task. If the user says Pry exists or asks to
run in Pry, start Pry directly from the repo and feed the requested commands to it.

Avoid these unless a concrete error requires them:

- checking whether `pry` exists;
- checking whether files/folders exist;
- trying `bundle exec pry` first;
- replacing Pry with `ruby -e`;
- adding defensive wrappers around the user's request.

## Default command shape

From the current repo root, run plain Pry with a heredoc:

```bash
pry <<'RUBY'
# user/project commands here
exit
RUBY
```

If the command needs project boot, use the repo's known boot command when obvious from context.
For the GTM repo, use the current checkout when already inside one of these repo roots:

```text
/Volumes/dev/projects/shaka/gtm/1st/
/Volumes/dev/projects/shaka/gtm/2nd/
/Volumes/dev/projects/shaka/gtm/3rd/
```

If the user asks for GTM Pry while outside those checkouts, ask which checkout to use. Then boot GTM with:

```ruby
require './config/boot'
```

Example for GTM from the first checkout:

```bash
cd /Volumes/dev/projects/shaka/gtm/1st && set -a && source hermes-skills/.env && set +a && pry <<'RUBY'
require './config/boot'
response = Instantly::Leads::Api.new.get_campaign(campaign_id: '...', api_key: ENV.fetch('INSTANTLY_API_KEY'))
puts({ id: response['id'], status: response['status'], keys: response.keys.sort }.inspect)
exit
RUBY
```

## Environment variables

If the user asks for code that clearly needs existing `.env` values and the repo has a known env
source from project docs/context, source it directly in the shell command. Do not pre-check it.

For GTM, the known env source is:

```bash
set -a && source hermes-skills/.env && set +a
```

If Pry raises `KeyError`/missing env, then report that specific error and ask whether to source a
specific env file or export the variable.

## Error handling

- If plain `pry` launches, continue using plain `pry`.
- If `require './config/environment'` fails in a non-Rails repo, switch to the repo's boot file when
  known; for GTM that is `require './config/boot'`.
- If the command fails, report the actual error and the exact command shape that was run.
- Do not apologize with guesses like "Pry is missing" unless the error actually says that.

## Output hygiene

- For API calls involving prospects/leads/customers, print only sanitized summary fields unless the
  user explicitly asks for raw output.
- Never print API keys, bearer tokens, raw provider payloads that may include PII, or full lead lists.
