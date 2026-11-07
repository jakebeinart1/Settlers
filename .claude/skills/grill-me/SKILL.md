---
name: grill-me
description: Stress-test a feature, plan, or design through a decision-tree interview. Use when Alex asks to grill an idea, use Matt Pocock's grill-me workflow, or work through unresolved product choices. Every question includes Context, Question, Option A, Option B, and Recommendation.
license: MIT
---

# Grill a plan before building it

Interview the user until there is a shared understanding of the plan. Map a
**design tree**: decisions and the later decisions that depend on them.
Challenge assumptions and explain tradeoffs plainly; do not substitute your
preferences for the user's decisions.

## Prepare from evidence

- Define the scope from the current request and preserve previously settled
  decisions. Distinguish confirmed requirements, proposals, facts and unknowns.
- Find discoverable facts yourself: inspect the relevant code, documentation
  and tools. Delegate independent fact-finding where useful. Do not ask the
  user a question that repository evidence can answer.
- A fact still being investigated is an unsettled prerequisite. Continue with
  independent questions while that investigation runs.

## Work in rounds

The **frontier** is every unresolved decision whose prerequisites are settled.
Ask the whole current frontier as numbered questions, then wait for answers.
Questions depending on another unanswered question belong to a later round.
After each answer, record the decision, recompute the frontier and resolve any
contradictions before proceeding. A recommendation is not an accepted answer;
silence and elapsed time are not decisions.

Use this format for **every** question, including follow-up questions:

```text
Q1 — Short decision title
Context: Relevant facts, constraints and why this decision matters.
Question: One concrete decision the user needs to make.
Option A: A viable choice and its meaningful tradeoff.
Option B: A different viable choice and its meaningful tradeoff.
Recommendation: A or B, with the reason it fits this user's goals.
```

Keep context concise and recommendations specific. Use balanced alternatives,
not a deliberately bad option to steer the answer. For a decision that cannot
honestly fit two options, narrow the question and retain the other branches for
later; do not conceal alternatives. The user can propose a different answer.
When using a question tool, keep the full format in its question text and make
the suggested answers correspond to A and B, with the recommendation first.

Probe motivations, rules, interactions, edge cases and acceptance criteria as
their prerequisites become settled. Reuse evidence rather than repeatedly
asking the same question. Keep a concise decision record with open branches;
for repository planning, update the relevant document in `docs/AI_summaries/`.

## Finish with shared understanding

When the frontier is empty, summarize the agreed plan, material tradeoffs and
acceptance criteria. Check that nothing material was silently assumed.
**Do not implement the plan being grilled until the user confirms the shared
understanding.** A direct instruction to build the agreed plan counts as that
confirmation. This applies to the interviewed plan, not unrelated work or
already-authorized setup, research and documentation; do not introduce an
extra repository-wide approval requirement.

## Attribution and license

Adapted from Matt Pocock's [grilling skill](https://github.com/mattpocock/skills/blob/3cca18b368ae95cdbdebbff572ccafa662551015/skills/productivity/grilling/SKILL.md)
at commit `3cca18b368ae95cdbdebbff572ccafa662551015`. The adaptation preserves
decision-tree rounds and agent fact-finding, changes the question format at
Alex's request, and clarifies the scope of the shared-understanding checkpoint.
It is self-contained and does not require Claude's `Skill` tool or the upstream
`grill-me` wrapper. The upstream MIT notice follows.

MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
