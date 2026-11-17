# Experimental drift-off trials

Open **Reminders & bedtime → Experimental → Drift-off trial** on the Watch.
Start while awake, and stay awake for the first five minutes to establish the
baseline. Allow notifications, motion access, and heart-rate reading when asked.
This is a user-started 30-minute smart-alarm session, not all-day monitoring.

For initial evaluation, remove your lenses first. The app's “lenses in” status can
be used as a test flag. Never depend on this prototype to prevent sleeping in contacts.

## What the rule actually does

Version `experimental-hr-motion-v2` is an unvalidated hypothesis. It requires:

- At least three Watch heart-rate samples in the first five minutes, spanning two minutes.
- At least three subsequent samples in the last three minutes, spanning one minute;
  the newest must be no older than one minute.
- A recent median heart rate at least 8% below the initial median.
- Two minutes of low wrist movement with no sampling gap greater than three seconds.

Movement alone does not trigger a candidate. Neither does heart rate alone.
The rule does not measure HRV or call Apple's sleep classifier. It cannot distinguish
being relaxed from approaching sleep. Watch removal can produce misleading signals.
HealthKit queries read available samples; they do not force continuous heart-rate
measurement. If data is absent, denied, sparse, or stale, the screen says there is
no estimate. Lack of an alert is not evidence of wakefulness.

At minute 30 a local timed backup is scheduled independently of the rule. During
a running smart-alarm session, the app also requests the system alarm before expiry.
The backup is explicitly not a candidate detection. Notification sound follows device
settings. System scheduling, permissions, and termination can affect delivery.
Marking lenses out stops an active check and cancels its pending backup.

## Review and export

After a candidate, mark **I was awake**, **I felt drowsy**, or leave it unreviewed.
After stopping, optionally record estimated sleep onset within the monitored interval.
The summary counts self-reported misses when there was no candidate in the ten minutes
before that reported onset; late alerts count as misses. Unknown outcomes are not counted
as successes. These labels measure user reports, not clinically verified sleep onset.

Records contain timestamped heart samples, 30-second movement summaries, cumulative
motion coverage, candidate/backup times, rule version, outcome labels, and end reasons.
Coverage is time with received motion samples, not proof that the Watch was worn or that
heart-rate coverage was continuous. Interrupted trials are marked incomplete. Up to
30 trials are retained locally; delete old trials explicitly to make room.

Completed trials are saved to a persistent outgoing queue and transfer to the paired companion app when WatchConnectivity is active. Failed transfers retry on the next app activation or manual retry. Acquisition and review edits are merged separately so older transfers cannot erase newer feedback.
Use **Send to iPhone again** if needed. Open **Trial results & export** on iPhone to
review and export an individual JSON file through the share sheet. No server or cloud
upload is implemented. A deleted local trial is suppressed from later incoming transfers, but can still have copies on the other device
or in exports. Trial exports contain health data.

## Checks and remaining validation

Run the deterministic checks from the project root:

    cat Shared/DriftTrial.swift Shared/EEGSleepReference.swift Shared/PersonalLearning.swift Checks/DriftRuleChecks.swift Checks/EEGReferenceChecks.swift Checks/LearningChecks.swift > /tmp/DriftRuleChecks.swift
    swift -module-cache-path /tmp/lens-swift-cache /tmp/DriftRuleChecks.swift

These checks cover missing/stale/sparse samples, movement-only rejection, gaps,
combined-rule triggering, late alerts, label handling, and JSON round trips. They
check software behavior, not predictive accuracy. Build with the RemoveLensesWatch
scheme. A real Watch with an appropriate HealthKit provisioning profile is needed
to validate sensor delivery, screen-off runtime, permission denial, alarms, and
transfer to a paired iPhone. Simulator runs cannot establish any of those properties.
External sleep-onset reference measurements are needed before claiming actual accuracy.

Notification mutations are serialized so a delayed installation cannot overtake a later
cancellation. Snoozing a trial ends its repeating system haptics. The independent local
backup is set for minute 30, while the running trial requests its final reminder in the
last minute; this gives it time to cancel the local backup instead of sounding both.

Additional reminder ordering checks:

    cat Shared/ReminderWorkQueue.swift Checks/ReminderQueueChecks.swift > /tmp/ReminderQueueChecks.swift
    swift -module-cache-path /tmp/lens-swift-cache /tmp/ReminderQueueChecks.swift

## EEG report references

On iPhone, choose **Sleep trial → a completed trial → Add EEG reference**.
Enter a scored EEG report's source, recording period, report time zone, and either
its first scored sleep-onset time or an explicit awake-throughout result. Seconds
can be entered separately. This feature does not record EEG, import EDF/raw EEG,
score stages, or verify a report. Aligned report entries can be used by opt-in personal-threshold learning as described below.

Confirm timestamp alignment only after checking that the report's clock matches
the Watch trial; correct any device clock difference before entering timestamps.
Unconfirmed references remain saved but are excluded from comparisons. A recording
must overlap the trial, and any sleep-onset time must lie inside the recording.
EEG reference fields are separate from subjective sleep estimates, included in JSON
exports, and merged independently across paired devices (including removal).

The ten-minute warning criterion is a prototype evaluation definition, not a medical
standard. EEG-onset misses are evaluated only for reported onsets inside the trial.
False alarms require the recording to cover the candidate and its following ten
minutes and establish wakefulness through that window. Partial coverage and alerts
after the report's first sleep onset are unknown. Do not interpret a count without
its evaluated denominator. References are user-entered, not independently verified.

## Optional personal-threshold learning

On iPhone choose **Sleep trial → Learn my patterns**, and enable the switch. It is
off by default. Fitting happens on iPhone without a server. This is a bounded grid
search over heart-rate drops of 6%, 8%, 10%, or 12% and continuous low-movement
thresholds of 90, 120, 150, or 180 seconds. It is not a neural network, clinical
sleep model, or guarantee of better detection.

Learning uses live five-second feature records from new trials, not retrospective
reconstruction using heart samples delivered later. Legacy trials without those
records are excluded. An aligned, valid EEG report takes priority; otherwise the
user's sleep-onset estimate or explicit **I stayed awake throughout** outcome is
used. Drowsy/awake feedback at a single alert is insufficient to label a trial.
Attached but unaligned EEG references are excluded rather than silently replaced
with subjective labels.

At least eight usable training trials are required, including two sleep and two
awake trials. Every grid setting must be evaluable on the same training trials.
Only the latest 20 usable examples are fitted. A fitted proposal is frozen and
recorded with training IDs/fingerprints. Later edits or deletion invalidate it.
It controls no alerts while being tested on trials started strictly after fitting.

A candidate can be adopted only after at least three later sleep and three later
awake trials are evaluable for both versions, with fewer total errors and no
increase in either missed onsets or false alarms. Misses receive twice the fitting
penalty of false alarms. The small minimum counts are prototype safeguards, not a
statistical confidence guarantee. A failed candidate is discarded, and fitting waits
for new or changed reviewed data. Performance on the same people/observational
trials is not clinical validation; alerts themselves may change subsequent sleep.

Comparisons operate on live-observed, usable data after calibration/readiness, not
on periods with missing features. A silent no-alert awake trial requires at least
five minutes of usable coverage through trial end, with no gaps over 15 seconds.
Early-stopped/censored records can be unknown for one version; such trials are
excluded from both paired scores. Unknown is never treated as a correct prediction.
Sensor collection can continue after the first alert until stop/removal/expiry to
support later comparison. The system's Stop action can still end it. Do not delay
lens removal to gather data: test with lenses already removed as explained above.

Adopted settings are queued to the paired Watch and captured only at the next trial
start; an ongoing trial keeps its original settings, which are included in its
export. The Watch's Learning screen shows its received settings. Reset on iPhone
disables learning, restores standard settings, discards the proposal, and queues the
reset to Watch; it preserves trial records and their annotations.
