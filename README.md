# Lenses

Lenses is an iPhone and Apple Watch prototype that reminds you to remove contact lenses before sleep. It is built with SwiftUI in Xcode.

© 2026 Shubh Butani. All rights reserved. See [COPYRIGHT](COPYRIGHT).

## Presentation

Read the [16-slide project presentation](docs/Lenses-Project-Presentation.pdf). It covers the app, why lens removal matters, sourced health-risk statistics, the proposed machine-learning pipeline, and future scope. The PDF is a visual snapshot of the presentation, including its reference slides. The editable original remains in the project's Codex chat.

## Current features

- Set nightly reminders and custom one-time or daily reminders.
- Choose quick reminders from one second to fifteen minutes.
- Confirm lens removal on iPhone or Watch, with an undo option.
- Start an experimental 30-minute Watch trial that combines available heart-rate readings and wrist movement.
- Review trial outcomes, manually enter sleep times from scored EEG reports, and export individual trial records.
- Optionally personalise the experimental rule's thresholds using reviewed trials and later comparison trials.

Reminder settings currently remain separate on each device. Notification delivery, sounds, and Watch vibrations depend on permissions, device settings, and system runtime.

## Open in Xcode

1. Open `RemoveLenses.xcodeproj`.
2. Select the `RemoveLenses` scheme for iPhone, or `RemoveLensesWatch` for Watch.
3. Choose a compatible simulator and run the app. The deployment targets are iOS 18 and watchOS 11.
4. For a physical device, select your development team under Signing & Capabilities and configure the required HealthKit permissions and provisioning.

A physical Watch is necessary to evaluate real sensor delivery, background operation, alarms, battery use, and transfers to the paired iPhone. The simulator cannot establish those properties.

## Sleep research and limitations

The current candidate-alert rule and optional threshold learning are experimental. They are not a fully trained sleep-detection model, and their predictive accuracy has not been established. Relaxation can resemble sleep. Missing data produces no estimate; the absence of an alert does not prove that a user is awake.

The proposed full machine-learning pipeline is future work. It would require reliable sleep labels, aligned sensor recordings, separate training and testing participants, and evaluation of false alarms, missed episodes, alert timing, and sensor coverage. Detecting existing sleep and predicting future sleep onset are separate tasks.

For initial research tests, remove lenses before starting. Do not rely on this prototype to prevent sleeping in contact lenses. Follow your eye-care professional's prescribed lens-wearing schedule.

See [TRIALS.md](TRIALS.md) for recording methods, evaluation definitions, personal learning, and data handling. EEG references are manual report entries; the app does not record or interpret raw EEG.

## Data handling

Trials remain in local app storage and can transfer to the paired iPhone. The app has no implemented server upload. Trial exports contain health data and should be kept private. Real recordings, exports, build products, and signing credentials should not be committed to this repository.

## Run the software checks

From the project directory, run:

```sh
cat Shared/DriftTrial.swift Shared/EEGSleepReference.swift Shared/PersonalLearning.swift Checks/DriftRuleChecks.swift Checks/EEGReferenceChecks.swift Checks/LearningChecks.swift > /tmp/LensesLearningChecks.swift
swift -module-cache-path /tmp/lens-swift-cache /tmp/LensesLearningChecks.swift

cat Shared/ReminderWorkQueue.swift Checks/ReminderQueueChecks.swift > /tmp/LensesReminderQueueChecks.swift
swift -module-cache-path /tmp/lens-swift-cache /tmp/LensesReminderQueueChecks.swift
```

These deterministic checks verify software behaviour. They do not measure sleep-detection accuracy or demonstrate that the app reduces infections.
