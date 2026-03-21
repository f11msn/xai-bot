# Research Proposals: External Models & Datasets for Ius

Prepared for architecture review.
Based on analysis of BERT-base-NER, Legal-BERT, Russian legal NLP ecosystem
and current natasha-ex/ius codebase.

## Context

Current pipeline metrics (15-doc corpus, grammar-only):
- P=64%, R=49%, F1=55%
- Top error source: `ungrounded_fact` (41%), `incomplete_burden` (22%)

Current pipeline metrics (LLM):
- P=93%, R=90%, F1=91%

Current NLP stack: FRIDA (0.8B T5, general-purpose) + Slovnet (CNN+CRF, PER/LOC/ORG) + Yargy grammars.

---

## Proposal 1: Replace FRIDA with ruBERT-ruLaw for claim classification

### Source
- Model: [TryDotAtwo/ruBERT-ruLaw](https://huggingface.co/TryDotAtwo/ruBERT-ruLaw)
- Base: DeepPavlov/rubert-base-cased, continued pretraining on RusLawOD
- Paper: pending (arXiv, по словам автора)
- Training: 3× H200, 40K steps, batch 160, BF16

### What it is
RuBERT fine-tuned on 304K текстов федерального законодательства РФ (RusLawOD corpus).
MLM pretrain, не sentence embeddings. 180M параметров.

### Benchmark (автора модели)
На судебных решениях (sud-resh-benchmark), masked token prediction:

| Mask % | ruBERT-ruLaw Top-1 | ruBERT Top-1 | Legal-BERT(en) Top-1 |
|:------:|:------------------:|:------------:|:--------------------:|
| 10%    | **81.0%**          | 73.0%        | 45.3%                |
| 20%    | **76.3%**          | 53.8%        | 45.0%                |
| 40%    | **62.9%**          | 6.0%         | 41.9%                |

### Hypothesis
Embeddings из ruBERT-ruLaw лучше разделяют юридические claim types
(fact/demand/norm/evidence/qualification/procedural/computation), чем
FRIDA general-purpose embeddings. Улучшение classifier accuracy → меньше
misclassified sentences → меньше `ungrounded_fact` FN (~5 из 19).

### How it would integrate
```
Ius.NLP.Classifier
  current: FRIDA (ai-forever/FRIDA, 0.8B T5) → [CLS] embedding → cosine similarity
  proposed: ruBERT-ruLaw (180M BERT) → mean pooling / [CLS] → cosine similarity
```
Замена модели в `Classifier.load/1`. Centroid recomputation на 262 gold sentences.
Bumblebee уже поддерживает BERT — не нужен новый inference runtime.

### Metrics to validate
1. LOO-CV classification accuracy на 262 gold sentences (baseline: 78.4% FRIDA)
2. Pipeline F1 на 15-doc corpus (baseline: 55% grammar)
3. Inference latency per batch of 11 sentences (baseline: 19ms FRIDA on EMLX Metal)

### Architectural fit
| Criterion | Score | Notes |
|-----------|:-----:|-------|
| Runs on CPU/BEAM via Nx | ✅ | Bumblebee + EXLA, same as FRIDA |
| Model size | ✅ | 180M < FRIDA 800M. Less RAM, faster |
| Юридический домен | ✅ | Trained on real RF legislation |
| Sentence embeddings | ⚠️ | MLM pretrain, not contrastive. May need fine-tuning or mean pooling experiment |
| Maintenance/stability | ⚠️ | Single author, 68 downloads/month, no paper yet |
| EMLX Metal support | ❓ | Needs verification (BERT architecture, should work) |

### Estimated effort
- Experiment (swap model, recompute centroids, run eval): 0.5 day
- If better: integrate + update tests: 0.5 day

### Risk
Medium. May not beat FRIDA for sentence-level similarity despite better
token-level legal understanding. Quick to validate — just swap and eval.

### Decision needed
Run the experiment? Y/N. If ruBERT-ruLaw doesn't beat FRIDA on LOO-CV
by ≥3pp, keep FRIDA.

---

## Proposal 2: Import RusLawOD into law store

### Source
- Dataset: [irlspbru/RusLawOD](https://huggingface.co/datasets/irlspbru/RusLawOD)
- 304,382 texts, 194M tokens, 6.17 GB
- All federal RF legislation 1991-2025 with CONLL-U markup
- Paper: arXiv:2406.04855

### What it gives
Current law store: **27 laws, 5,319 articles** (hand-imported via Garant API).
RusLawOD: **304K documents** covering all federal legislation.

### Problem it solves
PLAN.md: "Import 353-ФЗ, 323-ФЗ → fixes 2 LLM FN (unknown_norm)".
With RusLawOD, we'd never hit `unknown_norm` again. Citations check
covers all federal legislation, not just 27 cherry-picked laws.

### How it would integrate
```
Ius.Laws.Importer  — new import source alongside Garant
  RusLawOD XML → parse articles → Ius.Laws.Store (SQLite)
```
Selective import: `is_widely_used=1` flag filters core ~5K acts.
Full import: 304K (but need article-level splitting, not all are structured).

### Architectural fit
| Criterion | Score | Notes |
|-----------|:-----:|-------|
| Data format | ⚠️ | XML with custom schema, not the same as Garant JSON |
| Article-level granularity | ⚠️ | RusLawOD is document-level; article splitting needed |
| Currency (актуальность) | ✅ | Last scrape 2024, covers through 2025 |
| Overlap with existing store | ✅ | Can augment, not replace — use for gap-filling |
| SQLite size after import | ❓ | Estimate: 200-500 MB for full text, ~50 MB for widely_used |

### Estimated effort
- Parse RusLawOD XML, map to existing schema: 2-3 days
- Article-level splitting (нетривиально — нужен парсер структуры закона): 2-3 days
- Validate against existing 27 laws (no regressions): 0.5 day

### Risk
Low-medium. Main risk: article splitting quality. Laws have inconsistent
formatting. Garant API already solves this — RusLawOD may need same level
of parsing.

### Alternative
Keep Garant API as primary, use RusLawOD only for discovery
("which laws exist?") and full-text search. Import article text from
Garant on demand.

### Decision needed
Full import or gap-filling only? Article splitting in-house or rely on Garant?

---

## Proposal 3: RuLegalNER for domain-specific NER

### Source
- Dataset: [RuLegalNER](https://github.com/zeino8/rulegalner) — 100K Russian court documents
- Paper: doi:10.17586/2226-1494-2023-23-4-854-857 (ITMO, 2023)
- Fine-tuned model: [lebeda/bert-finetuned-on-RuLegalNer](https://huggingface.co/lebeda/bert-finetuned-on-RuLegalNer) (12M params)
- Related: [Gherman/bert-base-NER-Russian](https://huggingface.co/Gherman/bert-base-NER-Russian) (F1=98.8%, general Russian NER, 378K downloads/month)

### What it gives
5 юридических entity types: Individual, Legal Entity, Penalty, Crime, Law.
Current Slovnet: PER, LOC, ORG (general). EntityDetector heuristically
reclassifies into court/government_body/address/organization — fragile.

### Problem it solves
1. EntityDetector has 50+ lines of heuristic reclassification (noise filters,
   government_body MapSet, court matcher). Domain NER replaces all of it.
2. New types (Penalty, Crime) useful for analysis modules:
   - Penalty amounts → cross-check with demand amounts
   - Crime references → relevant for 013_employment, 014_medical corpus docs
3. `missing_entity` findings (3 FN) could be recovered.

### Integration options

**Option A: Direct ONNX inference (Bumblebee)**
```
lebeda/bert-finetuned-on-RuLegalNer (12M) → ONNX → Bumblebee token classification
Replace Slovnet in EntityDetector, keep Yargy grammars as primary
```
Pro: immediate, small model. Con: sparse annotations, unknown quality.

**Option B: Distillation into CNN+CRF (Slovnet architecture)**
```
Train on RuLegalNER → distill RuBERT teacher → CNN+CRF student
Ship as new Slovnet model variant (slovnet_legal_ner_v1.tar)
```
Pro: stays on CPU, no Bumblebee dep. Con: significant ML engineering effort.

**Option C: Benchmark only**
```
Run lebeda model on 15-doc ius corpus. Compare spans with current
Slovnet + heuristic. Quantify gap. Decide later.
```
Pro: zero risk, fast. Con: doesn't improve anything yet.

### Architectural fit
| Criterion | Score | Notes |
|-----------|:-----:|-------|
| Runs on CPU via Nx | ✅ (Option A) / ✅ (Option B) | |
| Entity types coverage | ⚠️ | No LOC/address. Would need Slovnet + Legal NER combo |
| Annotation quality | ⚠️ | Rule-based annotation, sparse. 860 unique entities |
| Model maturity | ⚠️ | 7 downloads/month, no model card filled |
| Compatibility with Yargy grammars | ✅ | Yargy stays primary, NER fills gaps |

### Estimated effort
- Option A: 2 days (Bumblebee pipeline + entity mapping)
- Option B: 1-2 weeks (distillation pipeline, training, eval)
- Option C: 0.5 day

### Risk
Medium. Sparse annotations → model may have low recall on ius-domain
texts. Court decisions ≠ pre-trial claims (different entity distribution).

### Decision needed
Option A, B, or C? Start with C (benchmark)?

---

## Proposal 4: Grammars extraction from ius to yargy

### What
Move reusable grammars from `lib/ius/grammars/` to `yargy` hex package:
- `LawRef` → `Yargy.Grammars.LawRef`
- `Party` → `Yargy.Grammars.Party`
- `ContractRef` → `Yargy.Grammars.ContractRef`

### Why
1. Other Elixir projects can use legal grammars without depending on ius
2. Better isolation and testing (yargy has its own test suite + benchmarks)
3. Follows pattern: Person, Date, Amount already in yargy

### Blocker
`LawRef` depends on `Ius.Laws.Abbreviations` (list of law codes, codex
adjective map, titled law map). Options:
- A) Move abbreviations into yargy as `Yargy.Data.LegalAbbreviations`
- B) Make LawRef grammar configurable: `LawRef.extract(text, abbreviations: ...)`
- C) Keep abbreviations in ius, LawRef in yargy takes them as compile-time config

### Estimated effort
- 1 day (move + adapt deps + tests)

### Risk
Low. Pure refactoring. No behavior change.

### Decision needed
Where do abbreviations live? Option A, B, or C?

---

## Proposal 5: Slovnet batch inference + entity normalization

### What
1. Add `Slovnet.NER.extract_batch/2` — process list of sentences in one
   Nx call (padded tensor, single forward pass)
2. Add entity normalization via morph_ru: «Ангелой Меркель» → «Ангела Меркель»

### Why (batch)
Current: `Slovnet.NER.extract/2` handles one text. For a 50-sentence document,
that's 50 separate Nx forward passes. Batching → single pass with padding.

Measured: ~460μs/sentence. Batch of 50 with padding overhead should be ~2ms
total vs ~23ms sequential. Not critical, but cleaner.

### Why (normalization)
Coreference depends on matching entity strings. «Ивановым» ≠ «Иванов»
breaks deduplication. Python natasha normalizes via syntax + morph.
morph_ru is already a dependency of yargy → zero new deps.

### Architectural fit
| Criterion | Score | Notes |
|-----------|:-----:|-------|
| New dependency | ✅ | morph_ru already in yargy dep tree |
| API change | ⚠️ | New function, non-breaking |
| PR target | slovnet + ius | slovnet gets batch API, ius gets normalization |

### Estimated effort
- Batch: 1 day (padding logic, reshape, tests)
- Normalization: 1 day (morph_ru integration, PER/LOC/ORG case handling)

### Risk
Low. Batch is pure optimization. Normalization may fail on foreign names
(not in OpenCorpora dictionary) — needs unknown-word fallback.

---

## Proposal 6: Coreference — implement TODO

### What
`Ius.NLP.Coreference` line ~110 has:
```elixir
# TODO: implement party inference heuristics
```
Implicit bindings (Покупатель without «далее — ...») return empty map.

### Impact
Without implicit coreference, ~40% of party references are unresolved.
Affects: entity consistency check, claim attribution, report readability.

### Proposed heuristics (priority order)
1. **Parenthetical binding**: «ООО «Ромашка» (Покупатель)» → Покупатель = Ромашка
2. **Singleton**: one Покупатель + one ООО in text → bind
3. **Proximity**: Покупатель after «ООО «Ромашка»» in same sentence → bind
4. **Role inference**: Истец = first party mentioned. Ответчик = second.

### Estimated effort
- Heuristics 1-2: 0.5 day
- Heuristics 3-4: 1 day (proximity requires sentence-level context)
- Tests against 15-doc corpus: 0.5 day

### Risk
Medium. Rule 4 is wrong for counterclaims. Rules 1-2 are safe.

### Decision needed
Implement rules 1-2 first (safe), defer 3-4?

---

## Proposal 7: Semantic contradictions — threshold + verb-role fix

### What
2 FP: same verb in different semantic roles flagged as contradiction.
2 FN in doc 010: embedding similarity below 0.55 threshold.

### Fix
- Lower `@similarity_threshold` to 0.45 for better recall
- Add verb-role filter: skip if verb forms match but subjects differ
  (requires POS-level check, not full syntax parsing)

### Estimated effort
- 0.5 day

### Risk
Low. Threshold change increases candidate pairs (O(n²)) but fact count
per document is 10-30 — negligible performance impact.

---

## Proposal 8: Lazy FRIDA loading

### What
ClassifierServer loads FRIDA at application start → 30s cold start.
Move to lazy: load on first `classify/2` call.

### Impact
- App start: 30s → 1s
- Test suite: significantly faster (tests that don't use classifier skip loading)
- First classification call: +30s (one-time)

### Estimated effort
- 0.5 day

### Risk
None. Standard pattern. Already works this way for NERServer when model
files are missing.

---

## Priority Matrix

Proposals ranked by: impact on pipeline F1 × likelihood of success ÷ effort.

| # | Proposal | F1 impact | Effort | Risk | Depends on | Recommendation |
|:-:|----------|:---------:|:------:|:----:|:----------:|:--------------:|
| 1 | ruBERT-ruLaw experiment | +5-10pp? | 0.5d | 🟡 | — | **Run experiment** |
| 6 | Coreference TODO | indirect | 1d | 🟡 | — | **Do it** |
| 8 | Lazy FRIDA loading | DX only | 0.5d | 🟢 | — | **Do it** |
| 7 | Semantic contradictions | +4 TP | 0.5d | 🟢 | — | **Do it** |
| 4 | Grammars → yargy | reusability | 1d | 🟢 | abbreviations decision | **Do it** |
| 5 | Slovnet batch + normalize | perf + quality | 2d | 🟢 | — | Plan for next cycle |
| 2 | RusLawOD import | -2 FN (unknown_norm) | 5d | 🟡 | article splitting | Discuss scope |
| 3 | RuLegalNER | speculative | 0.5-14d | 🟡 | — | Start with benchmark (Option C) |

### Suggested sprint
**Week 1**: Proposals 8, 7, 6 (quick wins, 2 days total)
**Week 2**: Proposal 1 experiment (0.5 day) + Proposal 4 (1 day)
**Later**: Proposals 2, 3, 5 based on experiment results

---

## Open Questions for Architect

1. **FRIDA vs ruBERT-ruLaw**: готовы ли мы к смене embedding model, если
   эксперимент покажет +3pp? Или FRIDA зафиксирована как архитектурное решение?

2. **Law store strategy**: Garant API (точные статьи, платный) vs RusLawOD
   (полный корпус, free, нужен парсинг) vs гибрид? Что приоритетнее:
   полнота покрытия или точность article splitting?

3. **Grammars ownership**: LawRef/Party/ContractRef — в yargy (reusable)
   или в ius (domain-specific)? Если yargy — куда abbreviations?

4. **NER roadmap**: расширять Slovnet (CNN+CRF, наш контроль) или
   переходить на внешние BERT-NER модели (Bumblebee, чужая модель)?
   Или гибрид: Slovnet base + Bumblebee legal layer?

5. **Gold corpus scaling**: 262 sentences — потолок для ML.
   Аннотация новых документов (ручная, ~2ч/документ) vs
   semi-automated (pipeline + human correction)? Budget?

6. **Scope of grammar pipeline**: целевой F1 для grammar-only?
   55%→70% (IMPROVEMENT_PLAN) или 55%→80%? Стоит ли вкладываться
   в grammar pipeline, если LLM уже даёт 91%?
