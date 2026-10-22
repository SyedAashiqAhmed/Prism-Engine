# Notification Content Classification Pilot

## Purpose and status

This document records the agreed first-sprint scope for a content-based
notification classifier. It defines the pilot categories, labeling policy, and
measurable evaluation gates, and documents the current on-device prototype.

The classifier must use the actual message content. An app name, sender, group
name, or channel name is not evidence that a message belongs to a category.
These fields may be retained for provenance and evaluation, but must not make
an otherwise irrelevant message qualify.

For chat apps such as WhatsApp, classification is limited to text the Android
notification exposes. It cannot classify hidden previews, messages that do not
produce notifications, or private chat history.

## Pilot categories

| Category | Include when the content says... | Exclude when... |
|---|---|---|
| **Placement & Jobs** | There is a specific job opening, campus recruitment or hiring drive, internship, eligibility requirement, application or registration deadline, recruitment assessment, interview schedule, shortlist/result, offer, or joining update. | The message is only a greeting, joke, casual conversation, generic career advice, unrelated forward, coaching/course advertisement, or promotion. A group name such as “Placement” does not make it relevant. |
| **Banking & Payments** | A financial transaction or payment state is reported: money sent or received, a debit or credit posted, a card/UPI payment, a refund, reversal, or payment failure. | It is only an OTP, security code, balance/limit notice without a transaction, loan/card promotion, or generic cashback offer. A cashback that is explicitly credited is a transaction and may qualify. |
| **Deliveries & Orders** | An order is placed, confirmed, dispatched, tracked, delayed, delivered, missed, collected, returned, or has a changed fulfilment status. | It is only a product advertisement, recommendation, shopping promotion, or unrelated conversation. |
| **Bills & Due Dates** | An invoice or bill is issued, an amount is due, a payment deadline or overdue state is stated, or a bill reminder is sent (for example, utilities, subscriptions, or card bills). | It is only a generic offer or a payment confirmation that does not identify or update a bill. |
| **Travel & Transport** | A trip, ticket, ride, or transit booking is confirmed, changed, delayed, cancelled, boarding is announced, or travel progress is reported. | It is only a transport advertisement, unrelated location sharing, or ordinary conversation about travel. |
| **Appointments & Reminders** | A non-job, non-travel appointment or scheduled reminder is created, changed, approaching, or cancelled (for example, a medical or service appointment or a calendar reminder). | It is a job interview/recruitment event, a travel itinerary, a bill deadline, a generic alarm/notification with no meaningful event, or unrelated conversation. |

These categories describe the message's intent, not its source. For example,
“Interview at 10:00 tomorrow” is **Placement & Jobs** whether it arrives in a
placement group, a family chat, or a direct message. “Good morning” remains
unclassified even in a group called “Job Updates.”

## Current implementation status

The Android notification listener now applies a local, configurable TF-IDF
prototype to the notification body text and persists category labels, scores,
model version, and the leading score alongside the notification. Notification
title, app name, and group/sender name are not classifier inputs. When no body
text is available, classification falls back to **Unclassified** rather than
using a potentially misleading title. Financial transaction parsing remains a
separate path and can add **Banking & Payments** when it identifies a debit or
credit.

The current configuration is a seed baseline with hand-written prototype
examples and provisional thresholds. TF-IDF similarity scores are not
probabilities and do not provide general semantic understanding. Unit tests
cover representative synthetic examples; they do not establish real-world
precision, recall, multilingual coverage, or production readiness. Thresholds
and examples must be evaluated and tuned using a consented, held-out dataset
before making those claims.

The current `notification-pilot-v2` configuration adds more varied
Placement & Jobs examples for next-stage, shortlist, interview, and assessment
updates, along with hard negatives involving sports, quizzes, and student
council selection. These are regression-test prototypes only, not a labeled
accuracy dataset.

## Label and fallback policy

- Score each category independently against its definition and its own
  confidence threshold.
- Assign every category whose threshold is met. Multiple labels are allowed
  only when each label independently meets its threshold.
- If no category meets its threshold, assign **Unclassified**.
- Do not use the highest score alone to force a label. Similarity scores are
  not probabilities unless and until they are calibrated and evaluated as such.
- If classification is unavailable or fails, retain the notification as
  **Unclassified** and record the failure; do not silently drop it or guess.
- App, group, sender, and channel names are context/provenance only for this
  pilot. They must not override message content or independently cause a label.

Examples of legitimate multiple labels:

- “Your electricity bill of ₹1,200 is due Friday” → **Bills & Due Dates**.
- “₹1,200 payment received for your electricity bill” → **Banking & Payments**
  and **Bills & Due Dates**, because it reports both a transaction and the bill
  state.
- “Campus hiring drive: eligible students take the online assessment Friday”
  → **Placement & Jobs**. It is not also **Appointments & Reminders** merely
  because it contains a date.

## Initial success criteria

Evaluate each category separately on a held-out, human-labeled test set:

| Measure | Initial gate | Definition |
|---|---:|---|
| Precision | **≥ 95% per category** | True positive labels divided by all labels the classifier assigned to that category. This is the false-positive control, including messages from misleading group names. |
| Recall | **≥ 80% per category** | Correctly assigned relevant labels divided by all human-labeled relevant messages for that category. |
| Classification latency | **< 250 ms p95** | From normalized notification text being ready to category labels being returned, measured on a declared representative mid-range Android phone. Report cold-start latency separately. |

Report the sample counts and a confidence interval with each metric; do not
claim a category passed based on an under-sized or unrepresentative sample.
As a minimum pilot check, target at least 100 held-out relevant examples and
100 hard-negative examples for each category. This is an initial floor, not a
claim of statistical certainty or production readiness. A category without
enough examples remains **not yet validated**.

Also report a confusion table and false-positive/false-negative examples for
every category. Overall accuracy alone is not an acceptance measure because a
large number of irrelevant messages can make accuracy look high while the
classifier misses useful notifications.

## Evaluation-set rules

1. Use consented, privacy-safe examples or clearly marked synthetic examples.
   Do not upload personal notification content to a service as part of this
   pilot.
2. Remove or replace phone numbers, account/card identifiers, OTPs, addresses,
   names, transaction references, and other direct personal identifiers before
   sharing or committing examples. Keep source data local with access limited
   to the people preparing the set.
3. Have two people label ambiguous examples independently where practical;
   resolve disagreements and record the agreed rationale. Label the message
   content, not the group name or sender.
4. Include hard negatives: greetings and chatter in groups whose names imply a
   category, generic forwards, promotions, spam, and messages containing
   category keywords without the category's actual intent.
5. Include varied positive wording, sources, and languages expected in the
   pilot. Record unsupported languages rather than implying they were tested.
6. Split data by conversation/source and time, and keep duplicates or
   near-duplicates in the same split. Do not randomly distribute messages from
   one conversation across development and held-out test sets.
7. Freeze the held-out set before threshold/model tuning. Any changes after
   inspecting its results require a fresh held-out evaluation set.

## Definition of done for category planning

- The six category definitions, inclusions, and exclusions above are approved.
- Multi-label thresholding and the **Unclassified** fallback are specified as
  the agreed labeling policy.
- The precision, recall, latency, sample-size, and evaluation-set rules above
  are recorded for the next implementation sprint.
- No classifier is considered production-ready until it is evaluated against
  these gates on a representative held-out set and on the target Android
  device.

## Remaining validation work

- Collecting and labeling the representative held-out evaluation dataset.
- Measuring per-category precision, recall, confidence intervals, and p95
  latency on the target Android device.
- Tuning thresholds and prototype examples against development data without
  inspecting held-out examples.
- Collecting or committing real personal messages.
- Claiming that the proposed thresholds have already been achieved.
