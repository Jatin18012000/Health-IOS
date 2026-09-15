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

## Model choice

Two models, not one. They do different jobs and the reasons to pick them are
different — trying to serve both with a single model is what produces either a
companion that sounds robotic or one that quietly invents figures.

### The extractor — Apple Foundation Models (~3B, built into macOS 26)

Used for everything structured: routing a question to the right analysis,
pulling entities out of what you said, classifying an annotation, deciding which
metrics a brief needs.

It is the right tool for this specifically because of **guided generation**. You
annotate a Swift type with `@Generable`, and the framework uses *constrained
decoding* to guarantee the output matches that schema — malformed output is not
unlikely, it is structurally impossible. There is no JSON parsing, no retry
loop, no "the model returned prose again" failure mode. You get a typed Swift
value or an error.

It costs nothing, downloads nothing, and is already on the machine. For a
3B model it is weak at open-ended prose, which is why it does not do that job.

### The narrator — Qwen3.x via MLX

Used for the writing: turning a `HealthBrief` into something warm and specific,
and holding a conversation. Apache 2.0, so no licence entanglement.

**Target machine: MacBook M5, 24 GB unified memory, 1 TB SSD.**
The model tier is settled by that, and the reasoning is worth keeping because it
is the constraint that decides whether she stutters.

macOS hands the GPU roughly two-thirds to three-quarters of unified memory, so
the real budget is ~16-18 GB, not 24. And during a spoken exchange four things
are resident at once, not one:

| Resident | Size |
|---|---|
| Qwen3.x 14B, 4-bit weights | ~8-9 GB |
| KV cache @ 16K context | ~2-3 GB |
| Neural TTS (Kokoro class) | ~0.3 GB |
| WhisperKit (base/small) | ~0.2-0.5 GB |
| App, SwiftUI, character stage | ~0.5-1 GB |
| **Total** | **~12-14 GB** |

That leaves real headroom inside the ~16-18 GB the GPU actually gets. Comfortable,
not tight.

### Why not go bigger

A 27B-class model at 4-bit is ~18 GB of weights alone — at or past the GPU
allocation before the KV cache, the TTS model or the app exist. It would load,
then swap, and the symptom is not "slower": it is her pausing mid-sentence,
which destroys the illusion far more than slightly plainer prose would.

**14B at 4-bit is the right call on this machine, and the ceiling on it.**

### Context budget

Cap the chat at ~16K tokens. This costs nothing here, and that is the payoff of
the `HealthBrief` design: a brief is a few hundred tokens because the arithmetic
already happened in Swift. An architecture that fed raw data to the model would
need every token of context it could buy — this one never does.

### Disk

Trivial against 1 TB: ~34 MB of health data, ~10-12 GB of model weights,
a few hundred MB of character assets. Storage is not a constraint on this
project at any point.

MLX is the right runtime on Apple Silicon — measurably faster than the
alternatives for models under ~14B, and it loads weights in-process so there is
no daemon to manage. An `OllamaModel` conformer stays useful for trying a
different model without touching the app.

Do not pick the largest model that technically loads. First-token latency is
what makes her feel present (`docs/VOICE.md`), and a model that swaps to disk
misses the budget entirely.

## Why hallucination is mostly an architecture problem here

The instinct is to pick the model that hallucinates least. That matters, but it
is the smaller lever. Three structural choices do more:

1. **She is never asked to do arithmetic.** Every figure is computed in Swift
   and passed in. The most common way a health assistant lies is getting a
   number wrong, and that failure mode is designed out rather than mitigated.
2. **Structured output is constrained, not requested.** Guided generation makes
   schema violations impossible instead of unlikely.
3. **`OutputGuard` cross-checks every numeral** in the generated text against
   the brief. A figure that was not passed in cannot reach you.

What remains is ordinary prose unreliability — hedging, tone, over-confidence —
which is what model quality actually buys, and why the narrator tier is worth
spending memory on.

## Brief construction

For a question, `AURAAnalytics` assembles:

- the figures relevant to the window, with deltas against the comparison window
- personal percentiles against the last 365 days — **never population norms**,
  which would turn a companion into an unlicensed diagnostician. Suppressed
  below 14 readings, since ranking a day against three others says nothing.
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

## Speaking before the answer is finished

Two requirements in this project are in direct conflict:

- `docs/VOICE.md`: she must **start speaking before generation finishes**. The
  budget is about 1.5 seconds and waiting for a complete response blows it alone.
- This document: **nothing is spoken before the guard has checked it.**

Guarding only the finished text satisfies the second and breaks the first.
Speaking tokens as they arrive does the reverse — by the time the guard rejects
a figure, she has already said it out loud.

**The sentence is the unit of release.** Each complete sentence is guarded the
moment it closes, then either spoken or withheld. She begins after the first
sentence rather than the last, and nothing unchecked reaches the speaker.

That makes sentence boundaries safety-critical, which matters more than it
sounds, because health prose is full of decimals. `SentenceStream` uses one
rule: **a terminator only ends a sentence when the next character is
whitespace.** In "23.8 ms" the period is followed by a digit, so it is never a
boundary. And mid-stream the buffer genuinely reads "Your HRV was 23." a moment
before the next token makes it "23.8" — that is held, not released, which is the
case that would otherwise speak a truncated number.

A withheld sentence is never shown as her words and never silently swallowed:
the transcript says one was held back and why. Otherwise it reads as her
trailing off mid-thought.

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
