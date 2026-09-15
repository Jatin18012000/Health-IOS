# The AI layer

## The central constraint

Four years of health data does not fit in a context window. 664,515 samples is
on the order of 40 million tokens — no model, no quantisation, no machine.

And language models are unreliable at exactly the operations this app needs:
averaging a few hundred numbers, computing a percentage change, judging whether
a correlation is real. A companion that tells you your resting heart rate
improved when it didn't is not a bug — it is misinformation about your own body,
delivered warmly and confidently.

**So the division of labour is fixed:**

- `AURAAnalytics` computes. Deterministic Swift, unit-tested against the real
  export as a fixture.
- `AURAIntelligence` narrates. The model receives a `HealthBrief` of finished
  figures and turns them into warm, specific, plain language.

The rule that has to hold: **if a number appears in what she says, it was
computed in Swift and passed in.** She is never asked to derive one.

This is also why she's fast. A brief is a few hundred tokens, so the first token
arrives in well under a second instead of after a multi-thousand-token prompt.

## Model

Default: **MLX**, weights loaded in-process. One app, one process, no daemon,
fully offline. An 8B-class model at 4-bit runs at conversational speed on an M5;
measure on your machine and pick the largest that keeps first-token latency
under ~0.5 s, since that is what the conversation budget allows
(`VERDICT.md` §4).

Alternative: **Ollama** over local HTTP, for trying models without touching the
app.

There is deliberately no hosted-API conformer in the default build.

## Brief construction

For a question, `AURAAnalytics` assembles:

- the figures relevant to the window, with deltas against the comparison window
- personal percentiles — **never population norms**, which would turn a
  companion into an unlicensed diagnostician
- observations with an explicit confidence
- `missingDays`, so she can say "I only have four days of this week" instead of
  quietly averaging over a gap

### On correlations

With 1,450 days almost any pair of metrics correlates weakly. Surfacing
`r = 0.11` as an insight is how a health dashboard starts telling people
comforting nonsense. `Observation.confidence` carries the strength so she can
hedge honestly — "this might be nothing, but" — rather than either dropping a
real finding or overselling a coincidence.

## Output guard

Two distinct failure modes, checked before anything is spoken:

**Clinical overreach** — diagnosis, prescription, "you should stop taking".
She observes and encourages; she does not practise medicine.

**Fabricated figures** — a number in the output that wasn't in the brief. This
is the one that actually erodes trust, because it is plausible, specific and
wrong. `OutputGuard` cross-checks every numeral in the output against the brief
and rewrites or blocks on a mismatch.

## Memory

Without persistent memory she is a chatbot with a dashboard bolted on. Every
conversation starts cold, she can't refer to last week, and the illusion of a
companion never forms.

`memory.sqlite` holds two things:

- **Conversation history**, summarised rather than replayed verbatim — older
  exchanges compress into a running summary so context stays bounded.
- **Noted facts** — things she's learned and confirmed with you: "training for
  something in March", "sleep is worse when travelling", "shin splints in
  February". These are what let her connect a dip to a reason instead of
  narrating a decline.

Facts are written explicitly, never silently inferred, and are editable and
deletable. A companion that quietly accumulates conclusions about you is
unsettling; one that says "should I remember that?" is not.

## Proactive moments

The mockup greets you by name in the morning — which only works if she can
initiate. A scheduled morning brief, generated from the overnight data, is what
makes her feel present when you weren't looking. Keep these rare and genuinely
informative; a companion who interrupts constantly gets muted.
