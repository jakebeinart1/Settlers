# Empires simulator lifecycle

Apply this policy before every simulator create or boot, including implicit boots
and clones started by `xcodebuild test`, `scripts/gate.sh`, `scripts/verify.sh`,
or the pre-push hook. Empires and Settlers are one logical project across all
checkouts, branches, worktrees, and agents. Its limit is **three booted devices
in total**, including parallel-test clones; a worktree gets no separate budget.

## Inventory and ownership

Immediately before each operation, read fresh state:

```bash
xcrun simctl list devices -j
xcrun simctl list runtimes -j
ps -axo pid,ppid,etime,command
git worktree list --porcelain
```

Build a project-wide table of UDID, ownership evidence, runtime, current state,
latest known use, and active task/build/test. Connect running `xcodebuild`
destinations, test-runner descendants, and clone UDIDs to their parent workflow.
Inspect installed app identity and the built artifact's `CFBundleIdentifier`;
Empires can use Jake's default or Alex's local signing override. Keep ownership
receipts and actual use in existing task evidence or handoffs so another
worktree can identify the device later.

Establish ownership through a recorded project UDID/workflow or creation receipt,
corroborated by its app/bundle identity when available. An installed app alone
shows association, not exclusive ownership or authority to mutate a shared
device. Names such as `Empires QA`, `iPhone`, and `Clone N` are only hints.
A shared/user device or a device with uncertain ownership stays protected.
Concrete unresolved project-association evidence occupies a conservative project
slot until resolved; a name-only match does not establish that association.
Confirm idle status against builds, tests, capture sessions, user review, and
recent activity. A completed parent command or Shutdown state alone does not
prove the device is unused. Coordinate when another task may still need it.

## Reserve capacity, then create or boot

Use one host-wide Empires allocation lock for every checkout/worktree. Acquire
it atomically, for example with `mkdir "$HOME/Library/Caches/empires-simulator-allocation.lock"`.
Record the owning task/PID. If occupied, wait or coordinate with its owner;
an unfamiliar/stale-looking lock is not permission to remove it. Hold the lock
through fresh inventory, any idle shutdown, the final recheck, create/boot,
readiness, and state/count readback; then release only the lock you acquired.
For a launcher that boots clones internally, retain the lock through the test
run so another worktree cannot allocate against an incomplete clone inventory.

1. Reuse a compatible, idle project device first. A requested device already
   Booted can be reused at the limit without stopping another device, provided
   it is available to this task. Reset/fresh-install work uses a confirmed
   dedicated QA device; preserve manual-play saves.
   `scripts/select-qa-simulator.py` can **create**, so inventory before calling
   it, then verify its returned UDID's ownership/runtime/state before reset or
   boot. Pin a confirmed reserved QA UDID with `SETTLERS_QA_SIMULATOR_ID` when
   the selector would otherwise choose another task's device. Runtime
   compatibility and task ownership outrank its name.
2. If more than three project devices are booted, shut down idle project devices
   in order of least recent use until the count is at most three. If active
   builds/tests/user sessions prevent that, wait or coordinate; preserve them.
3. Before booting a fourth device, shut down the least recently used **idle**
   project device and confirm Shutdown. If all three are busy, wait or
   coordinate. Create only when existing compatible devices cannot serve the
   task, and establish its ownership and eventual boot capacity first.
4. Still holding the lock, refresh inventory immediately before create/boot and
   confirm the projected booted total is at most three. Boot a Shutdown device
   explicitly with `xcrun simctl boot <UDID>`; an already Booted device needs
   no boot command. Preserve genuine errors. Confirm readiness with
   `xcrun simctl bootstatus <UDID>` and read back state/count before releasing
   the lock. Resolve idle excess before proceeding; protect busy devices.

Parallel test workers consume this same budget. Count existing project devices,
the destination if it will boot, and all worker clones that can boot. Use serial
testing (`-parallel-testing-enabled NO -parallel-testing-worker-count 1`) when
additional clones would exceed the limit. `GATE_TEST_WORKERS=1` selects that
serial gate path; its default of two is not permission to exceed three.
Serialize gate/test runs because the dedicated QA app container is shared.

The existing selector, gate, verification script, and push hook do not enforce
this policy themselves. Inspect their launch stages before invoking them;
supervise and refresh inventory at each create/boot/test stage while holding the
shared allocation lock. Use the manual verification rungs when a wrapper cannot
provide that control. A serial worker setting alone does not make a busy QA
device safe to reset.

## Finish and storage retention

When the task finishes, shut down any temporary project device this workflow
booted, once it is idle, unless ongoing work explicitly needs it. Record the
shutdown/use time and confirm state. Preserve devices belonging to another task
or a user. **Shutdown frees RAM; erase/delete frees storage and loses state.**

During authorized storage cleanup, delete only an unused, project-owned device
whose last actual known use is **strictly more than 48 hours ago**. Re-read its
current state, `lastBootedAt`, device.plist state-change modification time,
recorded use/shutdown times, and recent CoreSimulator/device log activity.
Use the **latest** credible activity time as the retention clock. A simulator
booted three days ago but shut down or used today must stay. Missing or ambiguous
activity/ownership evidence means keep it; `lastBootedAt` alone is insufficient.

Acquire the same project allocation lock for deletion. Hold it through a fresh
Shutdown/reservation/activity/age check, delete, and inventory readback so another
worktree cannot reserve or boot the device between those steps. Confirm no
build/test/user/task claim and the age condition again immediately before delete.
`xcrun simctl delete <UDID>` removes installed apps
and app/test data; preserve still-needed state first. Use individual verified
UDIDs, never a blanket delete/erase/shutdown across projects. Loading this policy
does not initiate unrequested cleanup. Preserve runtimes needed by active work.
