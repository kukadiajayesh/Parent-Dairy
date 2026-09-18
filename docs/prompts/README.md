# Implementation prompts

Four prompts that turn the feature wishlist into buildable work for
**Parent Academic Diary** (`com.parent.academic.diary`, Flutter + Firebase).

Each prompt is self-contained apart from `00-shared-context.md`, which every
one of them assumes. Paste `00` first in a fresh session, then the feature
prompt.

| # | File | Covers | Depends on |
| --- | --- | --- | --- |
| 00 | `00-shared-context.md` | Architecture, conventions, guardrails, definition of done | — |
| 01 | `01-exam-results-foundation.md` | Exam + marks domain, result capture, deterministic weak-subject analytics, `kShowExamMarks` | 00 |
| 02 | `02-gemini.md` | **All AI work**: multi-key management, client, practice-paper/quiz generator, exam-paper scan + answer key, report-card OCR, focus plan | 00, 01 |
| 03 | `03-notification-reader.md` | Android notification capture, per-app opt-in, date extraction, auto-reminders | 00 (02 optional) |
| 04 | `04-ui-and-performance.md` | Deep UI audit, accessibility, rebuild/scroll/image performance | 00 (run last) |

## Suggested order

```
00 → 01 → 02 → 03 → 04
```

`01` before `02` because the weak-subject ranking must be deterministic Dart —
the model extracts and explains, it never decides. `04` last so the audit covers
the screens the other three add.

## What was added to the original wishlist

The original list had nine bullets. These are the gaps the prompts close, so
nothing below comes as a surprise mid-build:

1. **Exam records cannot be written today.** `firestore.rules` restricts
   `data.type` to `['worksheet', 'classwork']`, so every `RecordType.exam`
   write is rejected by the server. `01` fixes the rules first.
2. **There is no marks model at all.** Weak-subject detection needs somewhere
   to put scores. `01` adds a `results` collection rather than bolting numbers
   onto `DiaryRecord`.
3. **"Weak subject" was undefined.** `01` specifies an exact, testable rule so
   two parents with the same marks always see the same verdict.
4. **The generated paper needs to become a real artefact.** `02` renders a PDF
   and files it as a normal worksheet record, so AI output lands on the same
   timeline as everything else instead of in a side pocket.
5. **Scanning a *completed* paper** was the missing link between "scan the exam
   paper" and "auto-detect weak subjects" — `02` specs per-question grading
   that feeds straight into `01`'s analytics.
6. **A notification listener keeps running when Flutter is dead.** `03` buffers
   captures natively and drains them on next app start, instead of assuming a
   live Dart isolate.
7. **Consent, privacy and Play policy.** Both AI and notification capture ship
   their own consent screen; `NotificationListenerService` additionally needs a
   Play Console declaration and a privacy-policy line. Called out in `02` §G
   and `03` §H.
8. **Confidence and review.** Nothing the model extracts is written straight to
   the database — every extraction lands in a review screen with per-field
   confidence, because a wrong exam date is worse than no exam date.
9. **Cost control.** Key rotation, request caps, image downscaling and a
   visible AI activity log, so a parent's free-tier key is not burned by one
   careless tap.
