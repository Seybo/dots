# Pi-specific operating rules

Rules that apply only in the Pi harness. Not part of Claude's rule set.

## Slash commands and skills

When the user asks about a Pi "skill" or `/command`, treat that as any Pi slash command, not only an Agent Skill from `<available_skills>`. Pi slash commands can come from prompt templates (`/name`), Agent Skills (`/skill:name`), extension commands, or built-in commands. If a command appears in Pi autocomplete, it exists even when it is not listed in `<available_skills>`. Do not say a `/command` is unavailable solely because it is absent from `<available_skills>`; ask the user to run it or check prompt templates/commands if needed.

When a user message visibly begins with `/skill:<name>` (or another recognized slash-command prefix), or Pi has expanded that command into a `<skill name="<name>">` block, treat it as an invocation of that skill immediately. Do not downgrade it to a normal request, demand a second invocation, or rely on a skill document that lists only an alias. Follow the invoked skill's workflow and approval gates.

## Command shape for Pi permission checks

- Do not send multiline bash payloads when the same work can be done with separate tool calls or one safe line joined with `;` / `&&`. Pi permission checks handle pipelines/segments better than newline-separated pasted blocks.
- Avoid shell command substitution for file discovery plus reading, such as `cat $(find app -name 'foo.rb' | head -1)`. Run one safe listing command, then use the read tool on the discovered path. (Claude has a hook guarding this pattern; Pi does not.)
