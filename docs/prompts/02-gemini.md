# 02 — Gemini: keys, generation, scanning, grading

> Assumes `00-shared-context.md` and a finished `01-exam-results-foundation.md`.
> This is the whole AI surface in one prompt. Build it in the section order
> below — each section is shippable on its own behind `kAiEnabled`.

## Goal

The parent brings their own Google AI Studio API key (or several). With it the
app can:

- generate practice papers, quizzes, worksheets and revision notes from the
  child's own attachments;
- read a photographed exam paper into structured questions and produce a
  worked answer key;
- read a photographed report card into an `ExamResult`;
- grade a *completed* paper question by question and feed the result into the
  weak-subject analytics from prompt `01`;
- explain the weak subjects and propose a focus plan.

**Hard rule:** the model extracts, drafts and explains. It never decides who is
weak, never writes to Firestore without a human confirming, and every artefact
it produces is labelled as AI-generated.

---

## A. Key management

### Storage

Add `flutter_secure_storage: ^11.2.0` — Android Keystore / iOS Keychain. Keys are
**never** written to `SharedPreferences`, Firestore, Crashlytics, Analytics or a
log line, and never leave the device except in the `x-goog-api-key` header to
`generativelanguage.googleapis.com`.

Store one JSON blob under a single secure key (`ai.keys.v1`) so metadata and
secret stay together and a partial read is impossible:

```dart
class GeminiKey {
  final String id;              // uuid
  final String label;           // 'Personal', 'Work' — parent-supplied
  final String secret;          // never rendered, never logged
  final KeyStatus status;       // active | invalid | exhausted | disabled
  final DateTime? cooldownUntil;// set when a 429 exhausts it
  final DateTime? lastUsedAt, lastErrorAt;
  final int requestCount, failureCount;
  final String? lastErrorMessage;

  String get masked;            // 'AIza••••••7f2c' — first 4 + last 4 only
}
```

`lib/core/services/ai/gemini_key_store.dart` — a `ChangeNotifier` owning the
list: `load()`, `add()`, `rename()`, `remove()`, `setEnabled()`, `reorder()`,
`markUsed()`, `markExhausted(Duration)`, `markInvalid(String reason)`,
`nextHealthy()`. It is constructed once and reached through `AppState.aiKeys`.

### Rotation policy

- `nextHealthy()` returns the first key in parent order that is `active` and
  past its `cooldownUntil`; ties break by least-recently-used, so two keys
  actually share load instead of one being hammered.
- `429` / `RESOURCE_EXHAUSTED` → `markExhausted` until the next **UTC midnight**
  (when Google's free-tier daily quota resets), then fail over to the next key
  and retry the same request once per remaining healthy key.
- `400 API_KEY_INVALID`, `403 PERMISSION_DENIED` → `markInvalid`, do not retry
  with the same key, surface the key's label in the error so the parent knows
  which one to fix.
- `503 UNAVAILABLE` / `500` → exponential backoff with jitter, 3 attempts on the
  same key (250ms, 1s, 3s), then fail over.
- Every key exhausted → `AppFailure(FailureKind.quota, "Every Gemini key has hit
  today's limit. Add another key or try after midnight UTC.")`.

### Settings UI

New route `Routes.aiSettings`, reached from **More → a new "AI" group**:

- Master switch **Use Gemini AI** (`kAiEnabled` in prefs, default off).
- **API keys** — list with label, masked key, status pill
  (`Active` / `Invalid` / `Daily limit reached` / `Off`), requests this month,
  drag to reorder priority, swipe/menu to rename, disable, delete.
- **Add key** sheet: paste field (obscured, paste button, trims whitespace),
  label field, and a **Verify** action that calls `GET /v1beta/models` and only
  saves on a 200 — an invalid key must never be stored as working. Link out to
  `https://aistudio.google.com/apikey` with a one-line explainer that the key is
  free-tier and stays on this phone.
- **Models** — per-task model choice, populated from the live `models.list`
  response (cached 24h) filtered to those supporting `generateContent`. Defaults **as of
  September 2026** — re-check them against
  `https://ai.google.dev/gemini-api/docs/models` on the day you build, because
  this lineup moves every few months:

  | Task | Default |
  | --- | --- |
  | Generation (papers, quizzes, plans) | `gemini-3.8-flash` |
  | Vision (paper scan, report card) | `gemini-3.8-flash` |
  | Classification (notice extraction, prompt `03`) | `gemini-3.5-flash-lite` |
  | "Best quality" opt-in | `gemini-2.5-pro` |

  Never hardcode a model name as the only option: the picker is populated from
  the live `models.list` response and these are only the fallbacks when that
  call fails. A model id that 404s must surface as "That model is no longer
  available — pick another", not as a generic failure.
- **AI activity** — the log from §G.
- **Privacy & consent** — the consent screen from §G, re-openable.

---

## B. The client

`lib/core/services/ai/gemini_client.dart`. Add `http: ^1.6.0`.

**Why raw REST and not a package:** the parent supplies their own key, so
`firebase_ai` (which bills the Firebase project and has no user-key path) is
wrong, and the standalone `google_generative_ai` Dart package is no longer the
recommended route. A ~300-line REST client against
`https://generativelanguage.googleapis.com/v1beta` is smaller than the
dependency and gives direct control of retries and key rotation.

```dart
class GeminiRequest {
  final String model;
  final List<GeminiPart> parts;     // text, inlineData, fileData
  final String? systemInstruction;
  final Map<String, Object?>? responseSchema;  // structured output
  final double temperature;
  final int? maxOutputTokens;
  final Duration timeout;           // default 90s, 180s for vision batches
}

class GeminiClient {
  Future<T> generate<T>(GeminiRequest request, {
    required T Function(Map<String, Object?> json) parse,
    CancellationToken? cancel,
  });
  Future<int> countTokens(GeminiRequest request);
  Future<List<GeminiModel>> listModels();
  Future<String> uploadFile(File file, {required String mimeType}); // Files API
}
```

Requirements:

1. **Structured output everywhere.** Set `responseMimeType: "application/json"`
   and a `responseSchema` on every call. Parse defensively; on a malformed body,
   retry **once** with the raw text plus "Return only valid JSON matching this
   schema" appended, then fail with
   `AppFailure(FailureKind.unknown, "Gemini returned something the app couldn't
   read. Try again.")`.
2. **Blocked responses.** Handle `promptFeedback.blockReason` and a `finishReason`
   of `SAFETY`, `RECITATION` or `MAX_TOKENS` as distinct, explained failures —
   `MAX_TOKENS` in particular should suggest asking for fewer questions.
3. **Attachments.** Images ≤ 6MB after downscaling go inline as base64.
   Anything larger, and every PDF, goes through the **Files API**
   (`POST /upload/v1beta/files`, resumable) and is referenced by `fileData.fileUri`.
   Cache `attachmentId → (fileUri, expiresAt)` for 47h in
   `SharedPreferences`, because uploaded files live 48h and a second generation
   from the same worksheets must not re-upload them.
4. **Downscale before sending.** Reuse `ImageService`, but with a 1600px long
   edge and quality 75 for AI requests — legibility for a model, not for a
   parent zooming in. Never send the Storage original.
5. **Request caps.** Refuse, with a clear message, a request carrying more than
   **12 images** or **40 PDF pages** or **20MB** total. Before any request over
   6 images, run `countTokens` and show a confirm sheet:
   "This will read {n} pages from {subject}. Continue?"
6. **Cancellation.** Every long call takes a `CancellationToken`; the progress
   UI has a Cancel that actually aborts the HTTP request.
7. **Offline.** `ConnectivityService.offline` short-circuits before the request
   with `FailureKind.offline` — no spinner, no timeout wait.
8. **Redaction.** A `GeminiException` never carries the key. Assert this in a
   test.

---

## C. Practice papers, quizzes and worksheets

### Entry points

- Subject detail → **Generate practice**
- Performance tab weak-subject card → **Generate practice** (pre-filled with
  the subject and its `focusChapters`)
- Add sheet → **AI practice paper**
- Worksheet detail → **Make a similar worksheet**

### The generator screen (`Routes.aiGenerate`)

Source picking, all pre-filled from context so the common path is two taps:

| Field | Default |
| --- | --- |
| Child | active child |
| Subject | from the entry point |
| Chapters | the subject's `focusChapters`, else all chapters seen this year |
| Source records | the last 8 worksheet/classwork records for that subject+chapters, each shown as a togglable thumbnail row with page count |
| Output | Practice paper · Quiz (MCQ) · Worksheet · Flashcards · Revision notes |
| Question mix | per type counts — MCQ / short / long / fill-in / match / true-false |
| Difficulty | Same as source · Easier · Harder · Mixed |
| Total marks & duration | derived from the mix, editable |
| Language | English · Hindi · Gujarati (default from the source material) |
| Include answer key | on |

Grade and board context come from `Child.grade` and `Child.school`; include them
in the prompt so a Class 4 paper does not read like a Class 8 one.

### Output schema

```jsonc
{
  "title": "Class 4 · Mathematics · Fractions practice",
  "subject": "Mathematics", "grade": "Class 4",
  "durationMinutes": 40, "totalMarks": 25,
  "instructions": ["All questions are compulsory."],
  "sections": [{
    "name": "Section A — Multiple choice", "instructions": "…",
    "questions": [{
      "number": 1, "type": "mcq", "text": "…",
      "options": ["…","…","…","…"], "answer": "B",
      "explanation": "…", "marks": 1,
      "chapter": "Chapter 4", "difficulty": "easy",
      "sourceRef": "attachmentId or 'derived'"
    }]
  }]
}
```

### System instruction (use this, adapted)

> You are an experienced {grade} {subject} teacher preparing practice material
> for one student, working only from the attached pages of that student's own
> classwork and worksheets. Match the syllabus, notation, vocabulary and
> question style visible in the attachments. Do not introduce topics that do not
> appear in them. Every question must be answerable from the attached material.
> Where the source is handwritten and unclear, leave that topic out rather than
> guessing. Write in {language}. Return JSON matching the schema exactly.

### Review and save

A preview screen renders the paper as it will print. Per question: edit text,
regenerate just that question (a small follow-up call carrying the paper's
context and the question to replace), delete, or flag. A visible banner:
**"AI-generated — check the questions before your child sits down with them."**

On **Save**:

1. Render a PDF with `pdf: ^3.13.0` + `printing: ^5.15.0` — Figtree embedded,
   answer key as a separate trailing section that can be excluded. This is what
   makes the feature real: a parent wants paper, not a screen.
2. Store the structured JSON at
   `users/{uid}/children/{childId}/generated/{id}` (new collection, new rules
   block, `isDeleted` soft delete, `searchTerms`).
3. Create a normal `DiaryRecord` of `type: worksheet` with the PDF as its
   attachment, `title` from the paper, the chapters tagged, and a new
   `origin: RecordOrigin.ai` field on `DiaryRecord` (`manual | share | ai |
   notification`, defaulting to `manual` so old documents parse). It then flows
   through `UploadQueue`, the timeline, search and reminders like anything else
   — one source of truth, no parallel universe of AI artefacts.
4. Offer **Print / Share** immediately via `printing` and the existing
   `share_plus` path.

Timeline and lists show an `AI` badge for `origin == ai` records.

### Offline and failure

Generation requires a network — say so up front and disable the action rather
than queueing it. A failed generation keeps the configuration so **Try again**
is one tap, and a partially returned paper is shown with the missing sections
marked rather than discarded.

---

## D. Scanning an exam paper → answer key

### Flow

1. **Capture** — reuse `ImageService.capture()` / `pickFromGallery` /
   `pickFiles`, multi-page, with drag-to-reorder and rotate (`ImageService.rotate`)
   before sending. Page order matters; state it in the prompt too.
2. **Extract** — one vision call returning:

```jsonc
{
  "detected": { "subject": "Science", "examType": "Unit Test 2",
                "date": "2026-09-12", "grade": "Class 4",
                "totalMarks": 30, "durationMinutes": 60,
                "confidence": 0.86 },
  "sections": [{ "name": "Section A", "instructions": "…",
    "questions": [{ "number": "1(a)", "text": "…", "type": "short",
                    "marks": 2, "options": [], "pageIndex": 0,
                    "confidence": 0.93, "needsReview": false,
                    "studentAnswer": null }] }],
  "unreadableRegions": [{ "pageIndex": 1, "note": "bottom third is cut off" }]
}
```

3. **Review screen** — questions listed with the page thumbnail beside them.
   Anything with `confidence < 0.75` or `needsReview` is highlighted and sorted
   to the top. The parent fixes, then confirms. **Nothing is written before this
   confirmation.**
4. **Save** — an exam `DiaryRecord` (this is why prompt `01`'s rules fix is a
   prerequisite) with the page images as attachments, the structured questions
   stored alongside at `users/{uid}/children/{childId}/generated/{id}` with
   `kind: scannedPaper`, linked by `examRecordId`.
5. **Generate answer key** — a second call over the *structured questions*, not
   the images, so it is cheap and repeatable:

```jsonc
{ "answers": [{ "number": "1(a)", "answer": "…",
                "workedSolution": ["step 1", "step 2"],
                "markingScheme": [{"points": 1, "for": "correct formula"}],
                "commonMistakes": ["…"], "confidence": 0.9 }] }
```

   Saved as the record's `answerKey` attachment — render the key to PDF the same
   way as §C and attach it, so the existing `hasAnswerKey` surfaces light up
   with no UI change. Badge it **AI-generated · verify before use** wherever it
   is shown, and never overwrite an answer key the parent attached themselves
   (offer "Replace" explicitly).

### Grading a completed paper — the missing link

When the captured pages carry the child's handwritten answers, offer **Grade
this paper**. It fills `studentAnswer` during extraction and then, per question,
returns `{ number, awarded, outOf, verdict: correct|partial|incorrect|blank,
reason, topic }`.

The result screen shows the total, the per-question breakdown, and a
**Save as result** action that creates an `ExamResult` (source `scanned`,
`needsReview: true`) through prompt `01`'s repository — which is what makes
"scan a paper" and "find weak subjects" the same feature rather than two.

Be explicit in the UI: handwriting recognition is imperfect, the grade is a
draft, and the parent confirms every mark before it is saved.

### Edge cases

- Mixed printed question + handwritten answer on the same page.
- Math notation: ask for plain Unicode where possible and LaTeX only inside
  `$…$`; render LaTeX with a small inline parser or show it verbatim — do not
  add a math-rendering dependency for this pass, note it as a follow-up.
- Rotated or skewed photos: instruct the model to read them as-is, and offer
  rotate in the capture step.
- Multi-column papers, two questions per line, question numbers restarting per
  section.
- A paper in Gujarati or Hindi — the schema stays English, the content does not.

---

## E. Report cards and results

Entry: **Add result → Scan report card**, and the same flow from a shared image.

Extraction schema mirrors `ExamResult`:

```jsonc
{ "examLabel": "Term 1", "date": "2026-09-30", "confidence": 0.88,
  "attendancePercent": 94, "teacherRemarks": "…",
  "scores": [{ "subject": "Mathematics", "marks": 68, "maxMarks": 100,
               "grade": "B1", "classRank": null, "remarks": "…",
               "absent": false, "confidence": 0.91 }] }
```

Rules:

- Subject names are normalised against the child's own `Subject` list by the
  **app**, not the model: fuzzy-match case-insensitively, offer
  "Maths → Mathematics?" as a confirmable mapping, and let unknown names save as
  free text with an "Add as subject" action.
- Marks and max marks are validated in Dart (`0 <= marks <= maxMarks`); a row
  that fails is flagged for review, not silently dropped.
- Grades resolve through `GradeScale` from prompt `01`, never by asking the
  model for a percentage.
- Saves with `needsReview: true` until the parent confirms; the Performance tab
  shows unconfirmed results with a dotted border and excludes them from
  `subjectInsights` until confirmed.

---

## F. Focus plan (the parent-facing explanation)

The weak-subject **ranking** comes from `01`'s `subjectInsights`. Gemini's job
is only to turn it into something a parent can act on. Send the insight objects
plus the chapter list — **no attachments, no child name, no school** — and get:

```jsonc
{ "summary": "2–3 sentences in plain language",
  "subjects": [{ "subject": "Mathematics",
    "why": "one sentence referencing the actual numbers",
    "focusChapters": ["Chapter 4"],
    "plan": [{ "week": 1, "actions": ["…","…"] }],
    "practiceSuggestion": { "type": "quiz", "chapters": ["Chapter 4"],
                            "questionCount": 10 } }] }
```

`practiceSuggestion` is a one-tap hand-off into §C with the config pre-filled.
The screen shows the deterministic numbers first and the generated prose second,
clearly attributed, so the parent can see that the verdict is arithmetic and
only the advice is AI.

---

## G. Consent, privacy, cost and observability

1. **Consent gate.** The first AI action in the app opens a full-screen
   explainer, not a dialog: what leaves the device (the selected pages and their
   text), where it goes (Google's Gemini API, under the parent's own key), what
   is never sent (the child's name, school, photo, or any page they did not
   select), that Google's free tier may use submitted data to improve its
   models — link `https://ai.google.dev/gemini-api/terms` — and that paid tier
   does not. Accept is stored with a timestamp and version; a version bump
   re-asks. **Revoke** in AI settings wipes keys, cached file URIs and the
   activity log.
2. **Minimise by default.** Strip EXIF before upload. Never put the child's
   name, school, GR number or date of birth in a prompt; use "the student" and
   the grade. Keep this in one `AiRedaction` helper with a test.
3. **AI activity log** — last 100 entries in `SharedPreferences`:
   timestamp, feature, model, key label, prompt/response token counts, duration,
   outcome. Shown in settings with a monthly total and a **Clear** action. This
   is the cost-control surface; there is no billing API to read.
4. **Telemetry** — add `Telemetry.aiRequested(feature, model)`,
   `aiSucceeded(feature, tokens)`, `aiFailed(feature, kind)`. Never log key,
   prompt or response content.
5. **Kill switch** — `kAiEnabled` off hides every AI entry point, and the app
   must build and pass tests with it off. Everything AI lives under
   `lib/core/services/ai/` and `lib/features/ai/` so it can be lifted out.

---

## H. Files to create

```
lib/core/services/ai/
  gemini_key_store.dart      keys, rotation, health
  gemini_client.dart         REST, retries, files API, structured output
  gemini_schemas.dart        every responseSchema in one place
  ai_prompts.dart            every system instruction in one place, versioned
  ai_redaction.dart          what must never be sent
  ai_activity_log.dart
  paper_pdf.dart             GeneratedPaper / AnswerKey → PDF
lib/data/models_ai.dart      GeneratedPaper, ScannedPaper, GradedPaper, FocusPlan
                             (pure Dart; mapped in mappers.dart)
lib/data/repositories/generated_repository.dart
lib/features/ai/
  ai_settings_page.dart      keys, models, activity, consent
  ai_consent_page.dart
  generate_paper_page.dart   config
  generate_progress_page.dart
  paper_preview_page.dart    review, per-question edit, save
  scan_paper_page.dart       capture → extract → review
  answer_key_page.dart
  grade_paper_page.dart
  scan_result_page.dart      report card review
  focus_plan_page.dart
```

Routes: `aiSettings`, `aiConsent`, `aiGenerate`, `paperPreview`, `scanPaper`,
`answerKey`, `gradePaper`, `scanResult`, `focusPlan`.

## I. Tests

No test may touch the network.

- `gemini_key_store_test.dart` — rotation order, 429 cooldown to UTC midnight,
  invalid key is skipped, all-exhausted throws `FailureKind.quota`, a key never
  appears in `toString()` or an exception message.
- `gemini_client_test.dart` — with a mocked `http.Client`: schema-conforming
  parse, malformed-JSON repair retry, `SAFETY` block, `MAX_TOKENS`, timeout,
  cancellation, 503 backoff, file-URI cache hit inside 47h and miss after.
- `ai_redaction_test.dart` — a prompt built from a `Child` with a name, school
  and GR number contains none of them.
- `paper_pdf_test.dart` — a golden PDF page count and non-empty text for a
  fixture `GeneratedPaper`.
- Parser fixtures: check in 6–8 realistic model responses (a clean paper, a
  paper with an unparsable question, a report card with grades only, a report
  card with an absent row, a graded paper) under `test/fixtures/ai/` and assert
  the mapping into models.
- Widget: the AI settings page with zero keys shows the empty state; with
  `kAiEnabled` false, no AI entry point is reachable from Home, Subject,
  Performance or the Add sheet.

## J. Deliverable

A summary naming: the models chosen and where they are configurable, the exact
rotation behaviour, the consent copy as shipped, the per-request caps, the new
collections with their rules and indexes, and an honest list of what is
approximate (handwriting, grades-to-percent, AI answer keys).
