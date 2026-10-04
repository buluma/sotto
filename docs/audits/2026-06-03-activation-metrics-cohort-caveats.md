# Activation metrics — cohort and event caveats

> Status: **ACTIVE** — Required reading before interpreting onboarding activation
> from D1 or `/api/stats`. Prevents false “76% never activate” / “7d activation
> doubled” conclusions.
>
> Verified: D1 `sotto-telemetry`, 2026-06-03.

## TL;DR for agents

| Do | Don't |
|----|--------|
| Use **`dictation_completed`** in the **same session** as `onboarding_completed` for T0 activation (stable ~**45–48%** since at least Apr 2026). | Divide rolling-30d `first_dictation_completed` by rolling-30d `onboarding_completed` and call the gap “% who never activate.” |
| Restrict **`first_dictation_completed`** analysis to cohorts with `onboarding_completed` **on or after 2026-05-23** (event ship date). | Compare 7d vs 30d `first_dictation` rates and infer product improvement. |
| Treat **`session`** (per launch) and **install** (UserDefaults one-shots) as different units. | Equate `app_launched` sessions with new installs. |

**Product headline (as of 2026-06-03):** About **half** of users who finish onboarding do **not** get a successful dictation in that **first launch session** (`dictation_completed` in the onboarding session ≈ 48%). That is the real activation gap — not a telemetry artifact.

---

## `first_dictation_completed` ship date

| Item | Value |
|------|--------|
| Event added | PR **#330** — merged **2026-05-22** |
| First D1 row | **2026-05-23T22:41:58Z** |
| Emission | Once per install on **first successful** dictation (`AppEnvironment` → `markFirstDictationCompleted`) |
| Does **not** count | Cancel, empty, or failed attempts |

Code: `Sources/Sotto/App/AppEnvironment.swift` (`markFirstDictationCompleted`), `Sources/SottoCore/AppRuntimePreferences.swift` (`hasCompletedFirstDictation`).

---

## The common mistake (2026-06-03 review)

**Wrong:**

```text
30d: 902 onboarding_completed, 215 first_dictation_completed
→ 215/902 = 24% activate → “76% never activate”
7d:  46% same-session first_dictation vs 18% on 30d → “activation improved recently”
```

**Why it’s wrong:**

1. **525 / 902** onboardings in the 30d window happened **before 2026-05-23**. Those installs could complete dictation (`dictation_completed`) but **cannot** emit `first_dictation_completed` retroactively.
2. Pre-event cohort (verified): **254** same-session `dictation_completed`, **0** `first_dictation_completed`.
3. Post-event cohort only: **164 / 378 ≈ 43%** same-session `first_dictation_completed` — matches **7d ≈ 45%**, not 18%.

The **46% vs 18%** gap was mostly **event availability**, not a weekly product win.

---

## Correct metrics (definitions)

| Metric | Definition | Typical use |
|--------|------------|-------------|
| **T0 try rate** | Same session as `onboarding_completed`: share with `dictation_started` | “Did they attempt dictation before quitting?” (~58%) |
| **T0 success rate** | Same session: share with `dictation_completed` | **Primary activation KPI** (~45–48%); history predates `first_dictation_completed` |
| **First-value milestone** | `first_dictation_completed` (install-scoped) | Time-to-value buckets (`activation_window`); **only for onboard ≥ 2026-05-23** |
| **Funnel abandon** | `onboarding_step` without `onboarding_completed` | Setup drop-off (~38% of starters) |

`first_dictation_completed` ⊆ successful completions, but **not equal** to same-session `dictation_completed` (multi-completion per session, timing across sessions).

---

## Reference SQL (D1, GUI)

**Same-session T0 success (preferred KPI):**

```sql
WITH onboard AS (
  SELECT session FROM events
  WHERE event = 'onboarding_completed'
    AND surface = 'gui'
    AND ts >= datetime('now', '-30 days')
)
SELECT
  COUNT(DISTINCT o.session) AS completers,
  COUNT(DISTINCT CASE WHEN e.event = 'dictation_completed' THEN e.session END) AS completed_same_session
FROM onboard o
LEFT JOIN events e ON e.session = o.session AND e.surface = 'gui';
```

**`first_dictation_completed` — post-ship cohort only:**

```sql
-- Denominator: onboard completions on/after ship date
SELECT COUNT(*) FROM events
WHERE event = 'onboarding_completed' AND surface = 'gui'
  AND ts >= '2026-05-23T00:00:00Z';
```

**Do not** mix pre-2026-05-23 `onboarding_completed` into the denominator for `first_dictation_completed` rate without labeling the metric invalid.

---

## Verified snapshot (2026-06-03)

| Cohort | Completers | Same-session `dictation_completed` | Same-session `first_dictation_completed` |
|--------|------------|-----------------------------------|------------------------------------------|
| 30d all onboard | 903 | 434 (**48%**) | 164 (**18%** of all — **misleading**) |
| 30d onboard **before** 2026-05-23 | 525 | 254 (**48%**) | **0** (event did not exist) |
| 30d onboard **on/after** 2026-05-23 | 378 | 180 (**48%**) | 164 (**43%**) |
| 7d onboard | 274 | 124 (**45%**) | 123 (**45%**) |

**Takeaway:** Same-session success was flat ~48% pre- and post-event. `first_dictation` rate aligns with that only after the ship-date cutoff.

---

## Monitoring / agent review guidance

- **`GET /api/stats` → `activation`** (30d GUI) surfaces T0 success, post-ship
  `first_dictation_completed`, and setup abandon on the public stats dashboard.
- **`pnpm telemetry:review`** and dashboard “new users” tiles use `onboarding_completed` counts — not install IDs.
- When writing activation summaries, cite **`dictation_completed` same-session** for trends; cite **`first_dictation_completed`** only with a **post-2026-05-23** cohort label.
- Phrases to **avoid** unless cohort is defined: “76% never activate,” “activation doubled in the last week,” “only 24% activate after onboarding.”
- Phrases that are **fair**: “~half of onboarding completers don’t complete a dictation in the first session,” “~43% hit `first_dictation_completed` in-session among post-ship onboardings.”

---

## Related docs

- [`docs/telemetry.md`](../telemetry.md) — event catalog; see **Activation analytics caveats**
- [`spec/adr/005-onboarding-first-run.md`](../../spec/adr/005-onboarding-first-run.md) — product onboarding ADR
- Onboarding deep-dive context: `journal/2026-06-03-telemetry-review.md` (gitignored ops journal)
