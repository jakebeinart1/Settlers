"""Frozen workload shared by reconstruction and its independent experiment guards.

Keep this dependency-free: the supervisor must establish its watchdog before
Torch or the native environment can import. These are not tuning knobs.
"""

TRAINING_NUM_ENVS = 256
TRAINING_ROLLOUT = 96
TRAINING_EVAL_EVERY = 16
TRAINING_DECISIONS_PER_UPDATE = TRAINING_NUM_ENVS * TRAINING_ROLLOUT
MAX_EXPERIMENT_UPDATES = 100
