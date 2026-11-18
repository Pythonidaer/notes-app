# Local comedy reaction analysis

Status: proposed experimental feature. Depends on [managed audio](voice-recorder.md); manual labeling can precede any model.

## Goal and limits

Open a recorded comedy set, mark the performance start/end, inspect a waveform with audience-reaction overlays, and compare each minute. The system proposes timestamps; the user can add, delete, split, merge, or relabel them.

Use an audio event detector/classifier, not a text LLM, to find laughter. A transcript helps link a joke to a reaction but cannot reliably reveal audience sounds. A local LLM may summarize reviewed results later.

“Hard laugh” and “chuckle” are subjective intensity labels. A loud recording can reflect microphone placement rather than a stronger response. Model scores are not calibrated probabilities or a universal comedy-quality score. A groan may be playful or negative; do not count it as positive automatically.

## Build in stages and learn the workflow

1. Import one set and label reaction intervals manually. Establish useful metrics before training.
2. Run a pretrained audio-event baseline, such as YAMNet, on local decoded audio.
3. Review its proposals alongside listening; export corrected annotations.
4. Collect varied sets with positive and negative examples.
5. Extract pretrained embeddings and train a small classification head locally in a separate Python research environment.
6. Evaluate on entire held-out sets/venues; compare with the unchanged baseline.
7. Package a versioned model for local inference only if quality and performance pass.

YAMNet's existing labels are a starting point, not evidence it can distinguish comedy-specific intensity or groans reliably. Define that taxonomy with labeled examples. Do not train a large language model from scratch. Training and app inference are different workloads; start training on the Mac, keep iOS analysis optional.

## Annotation and storage contract

ReactionEvent: UUID, setID, sourceAssetID/sourceHash, startMilliseconds, endMilliseconds, reactionType (laughter/groan/applause/cheer/other/uncertain), laughterIntensity (chuckle/hard/unspecified), detectorScore, origin (manual/model), reviewStatus, modelVersion, annotationVersion.

Intensity only applies to laughter; overlapping types are allowed. User corrections are durable and never overwritten by rerunning a model. Predictions belong to an AnalysisRun with model hash, parameters, input hash, status, timing, and cancellation state. Keep runs comparable.

SetAnalysis: UUID, audioAssetID, performanceStart, performanceEnd, annotationRevision, metricPolicyVersion. Store joke/punchline annotations separately with optional transcript segment links. A clip remembers its source offset. All time intervals are half-open [start,end).

## Detection pipeline

Decode incrementally → channel selection/downmix → model-specific resampling → window inference → threshold/hysteresis → merge candidate windows → review.

For the YAMNet baseline use mono 16 kHz float samples in [-1,1], following its documented input contract. Its overlapping windows do not represent distinct laughs. Tune onset/offset thresholds, minimum duration, and gap merge on validation data and save those settings with each run. Initial experimental settings might be 0.4 s minimum duration and a 0.5 s merge gap; these are tunable defaults, not established comedy standards.

Preserve the original recording. Do not assume speech removal improves detection: separation can erase laughter and create artifacts. Evaluate original channels and optional processed variants against the same labels. Audience microphone and performer microphone need separate testing.

Proposed components: ReactionDetector protocol, AnalysisCoordinator for jobs, ReactionRepository for reviewed labels, pure ReactionMetrics for calculations, and WaveformCache for display. Keep Python tooling under a future research directory; never make the shipped app depend on a developer's Python environment. Test Core ML conversion or another supported runtime for output parity before selecting a shipping adapter.

## Metric definitions

Calculate over an explicitly selected performance interval of D seconds. Exclude pre/post-show audio by selecting boundaries, not by silently removing quiet setups. Display provisional metrics when unreviewed predictions are included.

| Metric | Definition and interpretation |
| --- | --- |
| Set LPM | Count of distinct accepted laughter events × 60 / D; do not count model frames or individual people |
| Per-minute counts | Event onsets in [0,60), [60,120), etc., relative to performance start |
| Partial-minute rate | Count × 60 / actual bin seconds; show raw count and bin length too |
| Laugh duration | End minus start for each event; report median and distribution |
| Laughter occupancy | Duration of union of laughter intervals clipped to performance / D × 100 |
| PAR-style response | Union duration of laughter, applause, and cheers / D × 100, using an explicit inclusion policy |
| Positive seconds/minute | Positive union duration × 60 / D |
| Hit rate | Manually attributed landed punchlines / annotated attempted punchlines; unavailable without joke annotations |
| Set economy | Manually annotated setup/transition/filler seconds divided by D; audio reaction detection alone cannot infer it |

A laugh crossing a minute boundary counts once in the onset bin; duration is split across both bins. Clip intervals to performance bounds first; an event already active at the selected start counts once at zero. Merge duplicate overlapping laughter labels before counting. For PAR and occupancy use interval union, so overlapping laughter/applause never double-count seconds. Groans are excluded unless the user explicitly marks one as positive and the policy records that choice. Zero duration yields no rate.

Example: first full minute has 4 distinct laughs and second full minute has 2 → 4 LPM versus 2 LPM. It establishes frequency, not automatically that the first minute was artistically better. A final 30-second bin with 2 laughs is “2 laughs / 30 s; equivalent 4 LPM.” A laugh from 59–63 seconds counts once in minute one and contributes 1 and 3 duration seconds respectively.

Treat the supplied 4–6 LPM and 30% PAR figures as coaching context, not validated thresholds. No default pass/fail ranking. The supplied claims about a creator or world record are unnecessary to the architecture and have not been established here.

## Labeling and evaluation

Create a written label guide with short examples of chuckle, sustained/hard laugh, groan, speech, performer laughter, cough, clapping, music, and silence. Label start/end and uncertainty. Audience event count is a convention: many people laughing together are one response interval.

Use recordings the user can use for this purpose; track dataset source and usage terms. Collect examples across venues, audience sizes, phones, distances, and levels. Split by whole recording/session (prefer venue separation too), never adjacent windows from the same file across training/test. Save dataset manifest, random seed, model version, and annotation version. Have a second listener label a subset to expose ambiguous boundaries.

Report event precision/recall/F1 with one-to-one matches (proposed onset tolerance ±0.5 s plus interval overlap), false positives per minute, boundary error, subtype confusion matrix, and absolute per-minute count error. Also inspect misses in speech-over-laughter and gain/noise variation. Tune thresholds only on validation data.

Proposed release gates, to revise after pilot labeling: overall event precision and recall ≥0.85, mean absolute count error ≤1 laugh per full minute, and acceptable results in each held-out recording condition. If the test set is too small or subtypes fail, keep the feature experimental and hide unreliable subtype aggregates. No accuracy promise before evaluation.

## Waveform and UI

Display downsampled peak/RMS bins with multiresolution cache keyed by source hash. Waveform amplitude is not a laugh label. Draw reviewed and unreviewed event spans differently, with non-color labels. Click a span to play; edit boundaries with keyboard-accessible time fields. Toggle overlays and waveform independently; provide an event list for accessibility.

Summary shows per-minute raw counts, duration, and review status. Long files decode in chunks; inference is cancellable and progress is visible. If audio changes, invalidate derived waveform/predictions and preserve the prior analysis as linked history rather than reusing stale timings.

## Acceptance checks

Hand-calculated fixtures cover boundary-spanning laughs, overlap union, partial bins, groans, no laughs, zero duration, selected start offsets, and duplicate detections. Test annotation edits/restart, model rerun preserving corrections, cancelled jobs, corrupted audio, and source hash changes. Benchmark a representative long set on the target Mac before setting memory/time budgets.

## Primary references

- YAMNet architecture/input contract and transfer-learning tutorial: https://www.tensorflow.org/tutorials/audio/transfer_learning_audio
- Model and label map: https://github.com/tensorflow/models/tree/master/research/audioset/yamnet
