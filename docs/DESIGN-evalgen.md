# evalgen — design doc

*nadir's evaluation & generation engine: the software analog of a chess engine's eval
bar and principal variation, attached to canonical asm. Evaluation precedes and
disciplines generation.*

Status: draft v0.2 · adopted into nadir (from `villen-evalgen1` draft v0.1) · companion
to [DESIGN-nadir.md](DESIGN-nadir.md)

---

## 0. Provenance and placement

Originated as **villen-evalgen1**; adopted into **nadir** because everything that
makes the engine tractable is a nadir thesis: the intent↔instruction bijection
(DESIGN §1) is what lets contracts attach at labels and proofs stay per-block;
intent-map's immutable keys are what make the cache sound (§3.4); the nadir call
convention (DESIGN §2.2) is the default `regmap`; and the Win64 in-seam invariants
that *a passing run does not verify*
([asm-debugging-guide.md](asm-debugging-guide.md)) are exactly what L1's lints check —
evalgen is the machine that walks the arithmetic. **villen becomes the first
downstream consumer**, taking nadir (and with it evalgen) as a dependency; the Deck
survives below as reference deployment, not owner.

Placement: the **tooling stratum** (DESIGN §8), not a §4 capability — the capability
table is the thin waist, and evalgen never widens it. Structurally it is the
mechanization of the reconcile loop (DESIGN §6.1): L1 mechanizes the brushing, L2
falsification, the generator proposal, while acceptance stays a human act. The engine
is modular C++ behind a thin corpus-authored verb (`nadir eval`, §5.2) — the same seam
nasm occupies behind `nadir build`: self-hosting covers verbs, not the engines they
drive, and the corpus stays buildable and testable without the observatory (§5).

---

## 1. Vision

evalgen is a live evaluation and generation engine for intent-native assembly. The
`.asm` stays canonical (DESIGN §1); what changes is the *strength* of the intent
projection. Today intent is a falsifiable projection reconciled by hand (DESIGN §6);
evalgen makes it **contractual** — score-bearing at L1, machine-checkable at L2, and
generative on demand. Assembly blocks, hand-written or generated, are judged as search
output against label-level intent contracts. The engine evaluates continuously and
cheaply, escalates to formal proving on demand, and proposes regenerated candidates
when asked. Generation proposes; the human accepts; the accepted bytes are the
canonical artifact. Canonicity is about which artifact is the source of truth, not how
it was authored. *Die Stellung bewerten, bevor man zieht.*

The name encodes the architecture: evaluation precedes and disciplines generation. A
generator without a strong evaluator is a random mover; the eval is the engine.

### Long-horizon goals (not in scope for v1, but shape the design)

1. **Intent editor.** A code editor whose primary editable artifact is the intent DAG.
   Manually written asm shows live per-line/per-block eval scores in the gutter; the
   user can invoke the generator to propose a regeneration of any block against its
   intent, then accept/reject like a code review.
2. **Self-modifying villen.** A villen instance on Steam Deck hardware that uses evalgen
   to modify its own blocks toward a goal in a game-engine context — closed-loop
   intent → generate → eval → prove → install. evalgen v1 is the trust-building
   substrate: every capability here must be reliable enough to eventually run without a
   human in the loop for low-stakes blocks.

For now: dream tools, built honestly.

---

## 2. Core model

### 2.1 Intent layer as the contract language

Architecture and robustness live in the **intent DAG** — but the DAG remains a
projection onto canonical asm, per nadir's thesis. Each label carries an intent;
intents compose: the post-intent of block A must entail the pre-intent of every
successor B. This interface-consistency check replaces OOP encapsulation with explicit,
checkable contracts.

Intents come in two tiers, mapping onto intent-map's existing tiers (§5.1):

- **Prose intent** — human-readable purpose statement (the `summary` tier). Judged
  fuzzily (LLM-as-judge, on demand, cloud-side).
- **Predicate intent** — machine-checkable pre/post conditions over registers, flags,
  and memory (a fenced block inside the `detail` tier). Judged exactly (SMT). Drafted
  by the agent from prose intent, reviewed by the human — nadir's reconcile loop
  (DESIGN §6.1) applied to specs.

**Predicate contract, concretely.** A block contract is a 4-tuple
⟨pre, post, modifies, regmap⟩:

- **State vocabulary:** 64-bit GPRs; flags individually (ZF, CF, SF, OF; PF/AF only when
  referenced); memory as a byte-addressable array with named regions declared in the
  intent map (e.g., `buf`, `len`), so predicates say `buf[i]` rather than raw addresses.
  `regmap` records the register convention in force (§2.2) — "x lives in r12" is part
  of the contract, not a comment.
- **Logic fragment:** QF_ABV (quantifier-free bitvectors + arrays), written in SMT-LIB2.
  Z3-native, no translation layer; bounded quantification over declared region lengths
  is expanded, not quantified.
- **Two-state form:** post-conditions reference entry values via `old(x)`. The
  `modifies` clause lists clobbered registers/regions; **everything unlisted is
  implicitly framed (preserved)**. Frame clauses are load-bearing — they are what make
  interface entailment local and the cache sound.
- **Interface entailment:** per CFG edge A→B, check post(A) ∧ edgecond(A→B) ⊨ pre(B),
  where edgecond is the branch predicate in the same vocabulary. This is the
  architecture-soundness check, run over the intent DAG independently of any code.
- **Loop-head contracts** are inductive invariants; v1 proves partial correctness only
  (termination/ranking functions deferred to a later version).
- **Reviewability:** every predicate conjunct carries a back-reference to the prose
  sentence it formalizes. Human review is a bijection check — each prose claim has a
  formal counterpart and vice versa — so the reviewer audits *meaning*, never raw
  SMT-LIB.
- **Canonical form** (alpha-renaming, sorted conjuncts, normalized bitwidths) is defined
  so that hash(canonical(pre)) is stable — this is the cache-key input from §3.4.

**Loop-head labels carry a strengthened obligation:** their intent must be *inductive* —
(a) established on entry, (b) preserved by one body iteration, (c) invariant ∧
exit-condition ⊨ post-intent. This is a strength requirement on one class of labels, not
a new annotation site; loop heads are already labeled by convention. The prover's "can't
establish preservation" failure is itself the feedback loop for strengthening.

### 2.2 Register discipline as interface contracts

nadir already made the central move here: between nadir-to-nadir labels **one internal
convention** is in force (args `rdi/rsi/rdx/rcx`, return `rax`, callee-saved
`rbx/rbp/r12–r15`, `rsp ≡ 0 (mod 16)` at every call — DESIGN §2.2,
[src/nadir.inc](../src/nadir.inc), recorded in the `abi:nadir-call` binding). That
convention is evalgen's **default regmap**: a contract that says nothing about registers
inherits it.

Beyond the default, a contract may declare deviations per label region — "x lives in
r12; ZF carries the comparison result." Custom per-region conventions are a first-class
optimization surface — something compilers barely exploit. Target ABIs bind only where
nadir already concentrates them: inside `cap_*` realizations and at OS entries, and
those boundaries are exactly the labels whose bindings carry the `abi:*` concept keys.
For in-seam blocks the ABI duties become *checkable obligations* in the contract:
shadow space allocated before any Win64 call and `rsp mod 16` discipline — the two
invariants [asm-debugging-guide.md](asm-debugging-guide.md) documents as invisible to
passing runs — plus the extended Win64 callee-saved set (DESIGN §2.2, the
`abi:callee-saved` binding).

**One interface, two proof obligations at the seam.** A capability like `cap_write` has
one nadir-level interface contract (pre/post in nadir-convention vocabulary) and two
hand-written bodies. Each body is verified against the same interface plus its own
target's internal obligations — the "one intent, two realizations" discipline mirrored
into the proof layer, and the same behavioral-test contract (DESIGN §6.2) restated
statically.

### 2.3 Concurrency stance

Single-threaded semantics are fully transparent (no hidden control flow, destructors,
or copies) — and the nadir corpus is single-threaded today. Concurrency is
**explicit-but-hard**: memory-ordering obligations (store visibility, fence placement)
must be stated in intents rather than hidden behind language semantics. x86-TSO's
strength is a deliberate reason to start on x86. evalgen v1 checks single-threaded block
semantics; ordering intents are recorded but only lint-checked (fence-presence
heuristics).

---

## 3. Engine architecture

Three layers, mapping onto the chess-engine decomposition. Each layer answers a
different question at a different cost.

| Layer | Question | Cost | Runs |
|---|---|---|---|
| L1 Fast eval | "Does this line/block look wrong?" | ms, local | continuously, on save |
| L2 Proving | "Does this block satisfy its intent?" | ms–s, local SMT | on demand / stakes-triggered |
| L3 Refutation | "Show me the input that punishes it" | falls out of L2 | on L2 failure |

### 3.1 L1 — Fast eval (the NNUE layer)

Amortized pattern evaluation, no execution. Three signal families, fused into a
per-line score vector (not a scalar — perf/correctness-risk/intent-fit are separate
gutter channels):

1. **Static cost model.** llvm-mca in v1 (per-block subprocess; its AMD scheduling
   models fit Zen 2 — the Deck's silicon — and it needs no per-µarch tuning). uiCA is a
   later option where Intel-µarch precision earns a second subprocess (~1% error vs
   llvm-mca's ~10–20%, but Intel-only). Output: cycles/bottleneck-port per line.
2. **Dataflow lints.** Capstone-based def-use analysis per block: dead register writes,
   EFLAGS clobber-before-read, partial-register stalls, writes violating the block's
   declared regmap. A few hundred lines of dataflow over existing label boundaries.
   **nadir-specific lint set:** callee-saved (`rbx/rbp/r12–r15`) preservation per the
   nadir convention; `rsp ≡ 0 (mod 16)` tracked at every call site; shadow space
   allocated before any call inside `cap_*` win64 bodies. This tier absorbs and
   supersedes DESIGN §6.2's grep-level static-lint net — the "two or three trivially
   matchable, expensively debuggable" invariants become real dataflow checks.
3. **Intent-incongruence (conditional surprisal).** A local 7B code model
   (Qwen2.5-Coder-7B, Q4/Q5 quant, llama.cpp resident in the daemon) scores each
   instruction twice: s₁ = surprisal given block-so-far only, s₂ = surprisal given
   block-so-far + intent string (the binding's `summary`). The signal is the pattern,
   not either score alone: (s₁ high, s₂ low) = unusual but justified by intent →
   **silent**; (s₁ low, s₂ high) = conventional-looking code contradicting its stated
   intent → **strong flag** (the canonical example: scanning right-to-left where the
   intent implies leftmost match — perfectly normal code, wrong for the purpose);
   (both high) = generically odd → weak flag. This 2×2 is the precision mechanism: the
   justified-by-intent quadrant is where naive detectors bleed false positives. Logprob
   scoring needs no generation quality — quantization degrades ranking gracefully, and
   two prefill passes per block remain sub-second.

**Precision discipline (anti-linter-fatigue):** L1 flags are thresholded aggressively.
The target is the human reviewer's precision profile — flag two things, both real.
Threshold tuning is a first-class config, and per-project priors live in a persisted
rules file that surprisal and lints condition on. A rule given twice by a human becomes
a lint.

### 3.2 L2 — Proving mode

Per-block bounded verification: pre-intent predicates ⊢ post-intent predicates, over
the block's instruction semantics.

- **Symbolic execution:** Triton (lighter per-block driving) or angr, over single basic
  blocks / label-bounded segments. Blocks are short; queries are milliseconds.
- **Solver:** Z3.
- **Semantics ground truth:** the K-framework x86-64 user-mode semantics (Dasgupta et
  al., ~3,000 instructions) as the reference for instruction meaning; Triton's own
  semantics for the execution engine, with K as the arbiter when they disagree.
- **Loops:** inductive invariants at loop-head labels turn unbounded queries into two
  bounded ones (establishment + preservation).

Escalation is **stakes-triggered, not uniform** — clock management. The user (or later,
the agent) marks blocks as prove-required; everything else rides on L1. Natural
first-round prove-required set for nadir: the `cap_*` seam bodies and any promoted
label (DESIGN §6.4) — blocks already declared test targets.

L2 complements, never replaces, the behavioral tests (DESIGN §6.2): proving is
per-block and static; the tests pin both realizations to one observable contract
dynamically, across both targets. *Ein Test, zwei Backends* stays the ground truth.

### 3.3 L3 — Refutation PV

On an L2 failure, Z3's model *is* a concrete register/memory state violating the
intent. Rendered as "this input punishes this line" — the principal variation, not just
a score. Free once L2 works.

### 3.4 Incrementality (the efficiently-updatable property)

Intent contracts are the memoization boundary, with **per-layer keys** so no layer
recomputes for an edit that cannot affect it:

```
L1 cost/lints    ← hash(block_bytes, regmap, rules_hash)
L1 incongruence  ← hash(block_bytes, summary_text, rules_hash)
L2/L3            ← hash(block_bytes, canonical(pre, post, modifies, regmap))
```

A prose-only `summary` edit re-runs surprisal but not the prover; a `pre`/`post`/
`modifies` edit re-runs the prover but not the cost model (a `regmap` edit re-runs both
the prover and the L1 lints, since `regmap` keys them too); a byte edit invalidates the
block. (The
binding's `modified_at` is the cheap change *detector* that triggers re-keying; the
content hashes decide what actually recomputes.)

Invalidation propagates to successors **only if the block's interface (post-intent)
changed** — CFG-local recomputation, NNUE's incremental accumulator realized
structurally. Intent-map labels are already the cut points, so incrementality costs
nothing beyond the cache. Blocks inside the seam carry one leg per target (§5.4);
each leg caches independently.

---

## 4. Generator (evalgen's second half)

The generator is **search guided by eval** — STOKE's architecture with two upgrades:
the spec is the intent contract (not test-case equivalence), and candidates come from
an LLM (not random mutation), searching a vastly smarter proposal distribution.
Structurally it is **CEGIS with a learned proposer**: counterexample-guided synthesis
where L3's refutation models drive the next sampling round.

### 4.1 Proposal conditioning

The proposer sees, per block: the contract 4-tuple ⟨pre, post, modifies, regmap⟩
(§2.1), the prose intent, predecessor/successor interfaces (so register conventions
line up), the µarch cost of the current block from L1 (the number to beat), the
project-priors rules file (§3.1), and 1–3 few-shot exemplars of (contract, accepted
block) pairs from evalgen's accepted-block corpus (§4.4). **The incumbent never conditions the proposer by
default** — its *text* stays out of the prompt (its quality is arbitrary, and the
program is prompted by intent, not by another program); only its measured L1 cost is
passed, as the number to beat. It instead enters the tournament as **candidate zero**:
scored, proved, and ranked
identically to generated candidates (an engine happily evaluates a suggested move — it
just enters as one line among the candidates, never as guidance to search). This makes
acceptance monotone: the proposed winner is ≥ incumbent under the eval by construction.
An opt-in *incumbent-guided* flag additionally includes the incumbent as a few-shot
exemplar, spending prompt budget on it like any other.

### 4.2 Sampling and pruning

1. Sample k=8–16 candidates from the local 7B on a temperature ladder (e.g.,
   0.2 / 0.6 / 1.0 split) — diversity from temperature, not prompt mutation. Dedup by
   canonical instruction-sequence hash before scoring.
2. **L1 pruning is lexicographic, not scalar:** (a) hard lints and contract violations
   are disqualifying — a candidate writing outside its `modifies` clause is dead on
   arrival, no score redeems it; (b) survivors rank by intent-incongruence; (c) ties
   break on cost model. The eval vector stays a vector; lexicographic order encodes
   "correct before fast."
3. Top 1–3 survivors go to L2 if the block is prove-required; otherwise top-of-beam is
   proposed directly.

### 4.3 CEGIS repair loop

On L2 failure, the L3 counterexample (concrete state violating post-intent) is appended
to the next round's prompt as a refutation exemplar: "previous candidate fails on this
input; required post-state is X." Iterate up to R=3 rounds. This is what lets a 7B
punch above its weight — each round's search is conditioned on exactly where the last
one broke, the same front-loading move as debugging from a month of crash logs before a
one-character fix.

**Budget escalation (clock management):** after R local rounds with no L2-passing
candidate, escalate the identical conditioning package to a frontier model — explicit,
logged, off the hot path. If that also fails, flag the block "needs human or stronger
spec" rather than looping: persistent synthesis failure is usually a contract problem,
not a search problem.

### 4.4 Presentation and acceptance

Passing candidates render as a diff against the incumbent with both eval vectors side
by side; if several pass L2 with incomparable cost profiles (lower latency vs. lower
port pressure), present the small Pareto set rather than force-ranking. Human
accepts/rejects — **generation never installs itself in v1.** Acceptance is nadir's
reconcile fixpoint (DESIGN §6.1) with better instruments: the accepted block is
committed as canonical `.asm`, exactly as if hand-written. Every accepted
(contract, block) pair joins the few-shot corpus, so acceptance compounds: the
proposer's distribution drifts toward house style.

**Outcome diagnostics.** Two results are signals, not just verdicts: (1) *incumbent
wins the tournament* → either search weakness or the contract undersells the block —
goodness lives in the code, unexpressed in the intent; surface a "consider
strengthening the intent" prompt. (2) *Human rejects an eval-winning candidate in favor
of the incumbent* → a preference exists that neither contract nor eval vector captures;
log it as a spec/eval-gap event. These override events are the highest-value data the
system produces — each one localizes exactly where the formalization leaks.

### 4.5 Division of labor

Fixed by capability boundaries: the local 7B does surprisal scoring and candidate
sampling (logits and sampling suffice; no judgment required); frontier models draft
predicate intents from prose, judge prose intents, and serve as the escalation
proposer — all on-demand, offline-tolerable, never on the hot path.

---

## 5. Deployment and system interfaces

Everything in L1 and L2 runs locally — dev box or Steam Deck; the engine is sized so
the Deck (villen's host, the weakest machine in the fleet) can carry it, which any dev
box then can too. No network dependency in the core loop — the philosophy villen
carries forward from nadir: *klein aber mein*. Cloud calls (frontier drafting/judging,
escalation proposer) are optional, explicit, and never on the hot path.

**Optionality is a hard requirement:** the nadir corpus must remain buildable and
testable with scons + nasm + pytest alone (DESIGN §8). evalgen deepens confidence; it
must never become a build dependency.

### 5.1 intent-map interface

intent-map is already nadir's intent store: the pinned submodule at
[opt/intent-map](../opt/intent-map), the canonical DB at
[docs/nadir.intent.db](nadir.intent.db), SQLite (WAL), opaque label keys bound to
`summary` (glance tier) + `detail` (commit tier), driven through one binary with a
sigil-based line grammar. evalgen adds no second store and no sidecar files.

- **Label convention:** the `<file>:<symbol>` convention nadir already uses, with bare
  filenames (`cap_write.asm:cap_write`). A label equal to the bare filename is the
  file-level note — named memory-region declarations live there.
- **Tier mapping:** `summary` = prose intent (the incongruence conditioning string,
  §3.1). `detail` = durable elaboration **plus the predicate contract**, embedded under
  a `%%contract … %%end` fence containing the ⟨pre, post, modifies, regmap⟩ 4-tuple
  (§2.1) in SMT-LIB2 with `old()` sugar. Named memory regions are declared once in the
  file-level binding's contract fence and referenced by block contracts. Agent-drafted
  predicates flow through the existing `annotate` verb.
- **Read path:** WAL explicitly supports concurrent readers alongside the single
  writer, so the daemon holds a **read-only SQLite connection** for hot-path lookups;
  all mutations go through the binary's verbs (`allocate`/`annotate`/`retire`),
  preserving its durability invariants. `modified_at` is the change detector feeding
  the per-layer cache keys (§3.4).
- **Immutability alignment:** intent-map keys are burned forever (tombstone-only
  deletion, no remap) — which matches the contract-as-cache-key design: a renamed asm
  label is a *new* interface, correctly forcing new allocation + retirement of the old
  binding.
- **Mirror discipline:** contract fences are plain text inside `detail`, so nadir's
  backup mirror (`python scripts/backup_intent_maps.py` →
  [nadir.intent.db.md](nadir.intent.db.md)) carries them for free — which makes
  **contract diffs reviewable in git**, a first answer to risk #5 (§8). The existing
  rule holds: after any `annotate`, regenerate the mirror and commit both files.

### 5.2 Process architecture — one core, two frontends, one verb

The engine is a modular C++ component, **libevalgen**, embedding its dependencies —
libllama (the resident 7B; model load cost alone forces the resident design), Capstone
(lints/dataflow), Triton's C++ API + Z3 C API (L2), SQLite (read-only intent-map
connection + evalgen's own cache db). nasm and llvm-mca are the two subprocesses (nasm
assembles each block to bytes with the SConstruct flags; llvm-mca scores them — both
per-block, results cached by block hash). Two thin frontends share the core:

- **evalgend** — the resident daemon for the editor hot path. Internal job queue with
  a small worker pool; blocks currently visible in the editor (client-hinted) jump the
  queue. IPC: µWS serving JSON over localhost WebSocket — the transport villen already
  uses, so the future intent editor and any LSP shim are just two clients of the same
  socket.
- **evalgen (one-shot CLI)** — the same pipeline in batch mode: take file paths, emit
  the §5.3 JSON to stdout, exit nonzero on any disqualifying lint or refuted
  prove-required contract. This is the frontend `nadir eval` spawns, and what a CI leg
  would call.

**`nadir eval` — the verb seam.** nadir's verb discipline (DESIGN §8) applies
unchanged: a corpus-authored verb is thin orchestration over a spawned external
engine, exactly as `nadir build` shells out to nasm and the linker. `nadir eval` needs
only `spawn` + `write` — spawn the one-shot CLI, forward the report, propagate the
exit code — so it rides on capabilities `nadir build` already forces. Like every verb
it is earned pull-based: it lands when the E-track produces an engine worth calling
from the corpus workflow, not before.

The engine itself is deliberately **not** a nadir program (§0): self-hosting covers
the verbs, and C++ is the right tool for the observatory. Pin its tool stack the way
intent-map is pinned — versioned under `opt/`, reproducible from a checkout.

### 5.3 Output protocol

The daemon's native protocol is JSON per block — the source of truth; LSP is an
adapter, not the format:

```json
{"label": "m1_fold.asm:m1_fold", "range": [l0, l1],
 "target": "win64",
 "cost":  {"cycles": 14.2, "bottleneck": "p1", "per_line": [...]},
 "lints": [{"line": 7, "kind": "eflags_clobber", "sev": "error"}],
 "incongruence": {"line": 9, "s1": 2.1, "s2": 7.8, "quadrant": "contradicts_intent"},
 "l2": {"status": "refuted", "counterexample": {"rax": "0x0", "buf": "..."}},
 "cache": {"hit": false}}
```

The LSP adapter maps: disqualifying lints → Error; contradicts-intent quadrant → Warning;
cost → Hint with the full vector in the diagnostic's `data` field; L3 counterexamples →
`relatedInformation`. The three gutter channels survive in `data` even where an editor
renders only severity — no information is destroyed to fit LSP, only down-rendered.

### 5.4 Triggers, target legs, and desync semantics

Three artifacts change independently: asm files (watch on save, ~200 ms debounce), the
intent store (watch the db/WAL file mtime), and the project-priors rules file (§3.1),
whose content hash folds into the L1 cache keys (§3.4) so a rules edit flushes exactly
the L1 layers that condition on it. Portable-stratum blocks yield one
(target, bytes) leg; blocks under `%ifdef WIN64` / seam bodies yield **one leg per
target** (assembled with the same flags the SConstruct uses), each leg evaluated and
cached independently under the same label — the report carries a `target` field.

On any event, reconcile by joining parsed asm labels against intent-map keys for that
file; four states:

1. **Label + binding** → full pipeline. Recompute iff the per-layer cache keys changed
   (§3.4); intent-edited-but-bytes-unchanged recomputes exactly the layers the edit
   touches.
2. **Label, no binding** → L1 cost + lints only; incongruence disabled (nothing to
   condition on); gutter shows a neutral "no intent" marker — absence is a state, not
   an error.
3. **Binding, no label (dangling)** → file-level drift diagnostic prompting the
   sanctioned workflow: allocate new key + retire old (keys never remap) — the same
   discipline CLAUDE.md already prescribes.
4. **Contract parse failure** (malformed `%%contract` fence) → block downgrades to
   prose-tier with an explicit spec-error diagnostic; never silently proceeds as if
   verified.

Blocks re-evaluate in CFG topological order so interface-entailment checks (§2.1)
always consume fresh post-intents.

---

## 6. Milestones — the E-track

evalgen milestones are numbered **E0–E5** to keep the namespace disjoint from nadir's
M-track (DESIGN §7); the tracks proceed independently. E0 is useful the day it lands;
nothing in the M-track blocks on any E milestone.

**E0 — Gutter (target: one focused weekend).** No LLM, no SMT — forces the plumbing to
exist before anything interesting depends on it. Task list:

1. Asm parser: label-bounded block splitter over NASM syntax (v1 scope; GAS deferred),
   emitting (label, byte range, line range, CFG edges from branch targets). NASM local
   labels join as `file.asm:global.local`, matching NASM's own qualified-name scheme.
   The sentinel comments (`@ret`/`@end`, DESIGN §6.4) parse as span metadata for free —
   the splice anchors double as block-exit markers. `%ifdef` blocks produce per-target
   legs (§5.4).
2. intent-map join: read-only SQLite connection to `docs/nadir.intent.db`,
   `<file>:<symbol>` key lookup, the four desync states of §5.4 as an enum with the
   "no intent" neutral marker.
3. evalgend skeleton: single C++ binary, file watcher with debounce, serial job queue
   (worker pool deferred), µWS localhost socket emitting the §5.3 JSON.
4. Cost pipeline: assemble with nasm (per-target flags from the SConstruct) → decode
   bytes with Capstone → emit canonical text for llvm-mca (mca does not parse NASM
   dialect; bytes are the ground truth anyway). Per-block invocation, output parsed
   into per-line cycles + bottleneck port, memoized by block hash (naive map; the real
   cache is E5).
5. Capstone dataflow lints: dead register write, EFLAGS clobber-before-read,
   partial-register stall, write-outside-declared-regmap (contract-lite: regmap parsed
   from the fence if present, defaulting to the nadir convention otherwise), plus the
   nadir set — callee-saved preservation, `rsp mod 16` at call sites, shadow space in
   `cap_*` win64 bodies (§3.1).
6. Optional stretch: 50-line LSP shim translating the socket JSON per §5.3's severity
   mapping.

*Success: open [cap_write.asm](../src/cap_write.asm), see honest per-line cost in the
gutter — and a deliberately removed `sub rsp, 32` in the win64 body fires the
shadow-space lint that behavioral tests provably cannot catch.*

**E1 — Surprisal.** Link libllama into evalgend (resident Qwen2.5-Coder-7B, Q4/Q5);
two-pass conditional scoring per §3.1 with `summary` as the conditioning string;
threshold tuning against a small corpus of known-good and known-bad blocks harvested
from the git history of the `.asm` files joined with the intent DB at each commit. *Success: the detector flags a real intent-incongruent instruction
(conventional code contradicting its stated intent) without flagging ten
justified-but-unusual ones.*

**E2 — First proved block.** `%%contract` fence parser (§5.1) → canonical form (§2.1) →
Triton+Z3 per-block query, one hand-written contract verified end-to-end. Natural
first target: `m1_fold.asm:m1_fold` — already behaviorally pinned by the asymmetric
fold and register canary, so the contract formalizes invariants the test suite
already trusts. A deliberately introduced bug produces a concrete refutation model
rendered through the JSON `l2.counterexample` field. *Success: the PV renders in the
gutter.*

**E3 — Invariant loop.** One loop verified via inductive loop-head intent, including
one full round of "preservation fails → strengthen invariant" feedback, plus the
interface-entailment check (post ⊨ pre) across at least one CFG edge.

**E4 — Generator v0.** The §4 loop end-to-end: contract-conditioned sampling on the
temperature ladder, lexicographic L1 prune, incumbent as candidate zero, one CEGIS
repair round, diff presentation with side-by-side eval vectors. *Success: accept one
generated block that beats the incumbent on the cost bar and passes L2 — and log one
incumbent-wins event to prove the diagnostics path.*

**E5 — Cache + incrementality.** Per-layer memoization per §3.4 replacing E0's naive
map, invalidation propagating only on post-intent change. *Success: edit one block,
watch only its dependents recompute.*

E0–E2 constitute the proof of concept. E4 is where evalgen earns its name.

---

## 7. Non-goals (v1)

Whole-program verification; multi-threaded memory-model proving (ordering intents are
recorded, lint-only); additional ISAs (ARM/RISC-V have official Sail semantics and are
natural second targets once x86 validates the architecture); self-installation of
generated code; any network requirement in the core loop.

And, per placement (§0): evalgen is **not** a §4 capability and never enters the
capability table; it is **not** a build or test dependency of the corpus — behavioral
tests (DESIGN §6.2) remain the cross-target ground truth with or without it; and the
*engine* is **not** self-hosted — corpus authorship stops at the thin `nadir eval`
verb (§5.2); the observatory stays outside the artifact it observes.

---

## 8. Risks and open questions

1. **Predicate-authoring cost.** Mitigated by LLM drafting + human review, but the
   ratio of prose-only to predicate-bearing labels in real projects is unknown. Measure
   during E2–E3. At the seam the cost doubles honestly: one interface contract, two
   per-target obligation sets (§2.2).
2. **Surprisal precision on asm.** Asm token distributions are thin even in code
   models. If E1 precision disappoints, a LoRA on (intent, block) pairs harvested from
   the corpus's git history joined with the intent DB is the cheap sharpening path — and it bakes in project priors no
   pretrained model has.
3. **Semantics gaps.** Triton/angr instruction coverage vs. what real blocks use (esp.
   AVX-512 subsets). K semantics arbitration adds integration cost; may defer to "trust
   Triton, flag unmodeled instructions" in v1. The nadir corpus's smallness is an ally:
   the instruction vocabulary in actual use is enumerable.
4. **Eval-vector fusion.** Perf, risk, and intent-fit resist a single scalar. v1 keeps
   them as separate gutter channels; any learned fusion (the true NNUE) waits for
   labeled data from actual use.
5. **Intent-writing style as the new attack surface.** Vague intents are the new
   spaghetti. The reviewable artifact shifts to the intent diff; the two-phase review
   habit covers this. The git-diffable mirror (§5.1) makes intent diffs first-class
   today; dedicated intent-diff tooling can follow.
6. **Tool-stack weight vs. nadir's minimalism.** llama.cpp + Triton + Z3 + Capstone +
   mca + model weights is the heaviest thing in the project by orders of magnitude.
   The §0 placement is the containment: optional, outside the corpus closure, pinned
   under `opt/` like intent-map. If the corpus ever *requires* the observatory to be
   trusted, the thesis has inverted — that is the line to watch.
