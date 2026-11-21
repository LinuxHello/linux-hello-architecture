---
type: adr
subject: The Agent calls that the System Settings page needs to show the PIN, enrol and remove fingers and the face, and reset after a forgotten PIN
artifact: adr
status: accepted
owner: "@atterdag"
concepts: [dbus, settings, kcm, fprintd, howdy, polkit, reset, enrolment, one-way-door]
tags: [adr, one-way-door, dbus, ux, security]
sources: ["0003-destructive-reset.md", "0014-agent-bus.md", "0015-face-capture-and-enrolment.md", "0021-pin-transport.md", "0023-pam-module-and-login-failure.md", "0024-agent-status-interface.md", "0026-clients-reach-the-agent-directly.md", "../notes/ui-proposals-2026-11.md", "https://github.com/LinuxHello/linux-hello/issues/312"]
date: 2026-11-22
---

# ADR-0027: The Agent calls of the settings page

## Status

Accepted, 2026-11-22, on the maintainer's standing approval of the lead's recommendations (proposed 2026-11-22). Answers [linux-hello#312](https://github.com/LinuxHello/linux-hello/issues/312). New D-Bus methods and signals cannot be taken back once a client uses them (invariant 7 of `linux-hello`'s AGENTS.md), so their shapes are decided here before the code. Built: nothing yet. The implementation issues are [#313](https://github.com/LinuxHello/linux-hello/issues/313) (the PIN's state), [#314](https://github.com/LinuxHello/linux-hello/issues/314) (fingerprints), [#315](https://github.com/LinuxHello/linux-hello/issues/315) (the face) and [#316](https://github.com/LinuxHello/linux-hello/issues/316) (the reset).

## Context

Linux Hello will have a page in KDE's System Settings, next to the Users page, where a person sets their PIN, adds and removes fingers, records their face, chooses where each method may be used, and starts over when they have forgotten their PIN. The maintainer chose its layout in the [UI proposals of November 2026](../notes/ui-proposals-2026-11.md) (settings proposal A).

The page may not run a program to do any of this ([ADR-0026](0026-clients-reach-the-agent-directly.md)): not `fprintd-enroll`, the command that enrols a finger with fprintd (the Linux service that reads fingerprint sensors), not `howdy add`, the command that records a face for Howdy (the Linux program that recognises a face with an infrared camera), and not `linuxhello-ctl`. It talks only to the Agent, the Linux Hello system service, over the Agent's D-Bus interface `io.github.LinuxHello.Agent1` (D-Bus is the message service that desktop programs use to call each other), and it sends a PIN only over the Agent's PIN socket ([ADR-0021](0021-pin-transport.md)). Running a program would be slower, would let whoever controls `PATH` choose what runs, and would put a second program between the page and the Agent.

The Agent already answers most of what the page shows: the conditions (`GetStatus`, [ADR-0024](0024-agent-status-interface.md)), the PIN rules and the effective policy (`GetPinRules`, `GetEffectivePolicy`, [ADR-0014](0014-agent-bus.md)), the person's own rules (`GetUserPolicy`, `SetUserPolicy`), and setting and changing the PIN (`SetPin`, `ChangePin`). Four things have no call:

1. **Whether a PIN is set, and when it was last changed.** A new person is led through setting a PIN first; someone with a PIN sees "PIN set on 3 November".
2. **Fingers:** which are enrolled, adding one (which takes several touches of the sensor), and removing one.
3. **The face:** whether one is recorded, recording it, testing it, and deleting it.
4. **The reset** after a forgotten PIN, which [ADR-0003](0003-destructive-reset.md) defines: it deletes the person's root key in the TPM and every passkey bound to it, so that a new PIN can be set. The TPM, the Trusted Platform Module, is the chip that keeps the keys so that no program can copy them.

Two questions cut across all four.

**Who may add a way in.** A finger or a face, once enrolled, signs the person in. Someone who finds the session unlocked for a minute could enrol their own finger and later open the lock screen with it. Windows Hello asks for the PIN before it adds a finger, for this reason. fprintd's own rule lets anyone in the active session enrol for themselves without a check.

**How long-running work reports.** Enrolling a finger takes several touches over many seconds, and the page shows each one ("Lift your finger and touch again, 3 of 8"). Setting a PIN already works as a *prompt*, the Agent's word for one attempt: the page opens a prompt, calls `SetPin(prompt_id)`, which returns at once, and the Agent reports the outcome with the `Result` signal to the connection that subscribed. The same shape fits enrolment, with one more signal for each step.

| Option | Pros | Cons |
| :-- | :-- | :-- |
| **A. Prompt-based calls, one per action; enrolment asks for the PIN on the PIN socket first; the reset is authorised by polkit with the account password** | Reuses the prompt, `Result` and the PIN socket the page already uses for `ChangePin`; a finger or a face can only be added by someone who knows the PIN; the reset follows ADR-0003, which names the account password | A new signal, `EnrolProgress`; the Agent becomes a client of polkit |
| B. One call that returns everything (`GetEnrolment`) and one that does everything (`Enrol(kind, …)`) | Fewer members | One call depends on fprintd, Howdy and the TPM at once, and fails as a whole when one is missing; a generic call has arguments that mean different things per kind |
| C. Enrolment without the PIN, as fprintd allows | Simpler; one step fewer for the person | Anyone at an unlocked session adds a way in |

## Decision

**Option A.** In plain words: every action of the page is one Agent call on a prompt, as setting the PIN already is; adding a finger or a face needs the PIN first, and the reset needs the account password through polkit.

All names below are on `io.github.LinuxHello.Agent1`. Every call answers only for the caller's own user, read from the bus credentials as for every other call (the uid, [ADR-0014](0014-agent-bus.md), amendment of 2026-11-16), except where root is named. Errors come from the closed set of ADR-0014 (amendment of 2026-11-17): `Denied`, `LimitReached`, `InvalidArgument`, `InvalidPolicy`, `Unavailable`, `Damaged`. Each call is named in the list of `GetCapabilities` once it is built, so the page can hide a section the Agent cannot serve.

### 1. The PIN's state

`GetPinState() -> (b is_set, t changed_at)`. `is_set` says whether the caller has a PIN record. `changed_at` is when the PIN was set or last changed, in seconds since 1 January 1970 (UTC), the value the Agent already keeps for the PIN's expiry ([ADR-0021](0021-pin-transport.md), amendment of 2026-11-21); it is `0` when no PIN is set. A record the Agent cannot read is `Damaged`. Nobody learns anything about another user's PIN: there is no argument, and root asking gets root's own answer.

Test names: `pin_state_says_whether_the_callers_pin_is_set`, `pin_state_is_only_the_callers_own`.

### 2. Fingers

The finger names are fprintd's closed set of ten: `left-thumb`, `left-index-finger`, `left-middle-finger`, `left-ring-finger`, `left-little-finger`, and the same five for `right-`. Any other name is `InvalidArgument`.

- `ListFingerprints() -> as`: the caller's enrolled fingers, in the order above. `Unavailable` when fprintd or a reader is not there.
- `EnrolFingerprint(s prompt_id, s finger)`: on a prompt the caller opened for itself, the Agent first waits for the caller's PIN on the PIN socket (the caller sends `ExpectPin(prompt_id)` and the PIN, as for `ChangePin`) and checks it through the TPM, counting a wrong PIN like any other. Only then does it claim the reader for the caller and start fprintd's enrolment. It returns at once. Each step of the enrolment is an `EnrolProgress` signal (point 4) and the end is the `Result` signal: `success`, or `failure` with a reason. A finger that is already enrolled is enrolled again (fprintd replaces it).
- `DeleteFingerprint(s finger)`: deletes one of the caller's fingers and returns when it is done. It needs no PIN: removing a way in cannot let anyone in, and fprintd already lets the person do it. Deleting a finger that is not enrolled succeeds and changes nothing.

The Agent reaches fprintd as it does for checking a finger ([ADR-0023](0023-pam-module-and-login-failure.md), amendment of 2026-11-19): it claims the default device for the user's name, calls `EnrollStart(finger)`, reads the `EnrollStatus` signal and always calls `EnrollStop` and `Release`. The polkit rule that Linux Hello ships for the Agent's own user (polkit is the service that decides whether a program may do a privileged action) is widened by the action `net.reactivated.fprint.device.enroll`, which fprintd checks for enrolling and deleting. fprintd's D-Bus interface was read from its documentation, not yet from the version on Ubuntu 26.04; the implementation checks it there.

Test names: `enrolment_asks_for_the_pin_first`, `a_wrong_pin_starts_no_enrolment_and_counts`, `enrolment_reports_each_touch`, `a_caller_enrols_and_deletes_only_its_own_fingers`, `an_unknown_finger_name_is_invalid`.

### 3. The face

The face calls stand on the privileged helper of [ADR-0015](0015-face-capture-and-enrolment.md), which runs Howdy's commands as root on the Agent's behalf ([#272](https://github.com/LinuxHello/linux-hello/issues/272), not built). There is no live camera picture; the page shows guided text and the result of a test, as ADR-0015 decided.

- `HasFace() -> b`: whether the caller has at least one face model. `Unavailable` without the helper or without Howdy.
- `EnrolFace(s prompt_id)`: PIN first on the PIN socket, exactly as for `EnrolFingerprint`; then the helper records a face model for the caller. Steps are `EnrolProgress` signals and the end is `Result`. A new model is added next to those that exist, as `howdy add` does.
- `TestFace(s prompt_id)`: one recognition attempt for the caller, ending in `Result` (`success`, or `failure` with `no-face`, `too-dark` or `not-recognised`). It needs no PIN: it lets nobody in, because it is not a sign-in and answers only the person at the page.
- `DeleteFace()`: deletes every face model of the caller. No PIN, for the reason given for fingers.

Test names: `face_enrolment_asks_for_the_pin_first`, `a_face_test_signs_nobody_in`, `a_caller_deletes_only_its_own_face`.

### 4. The progress signal

`EnrolProgress(s prompt_id, s step, u done, u needed)`, sent only to the connections that subscribed to the prompt (unicast, as every signal of the Agent). `done` and `needed` count the touches or pictures; `needed` is `0` when the method does not say. `step` is a closed set; a new step is an additive change:

| `step` | Meaning | Comes from |
| :-- | :-- | :-- |
| `waiting` | Touch the sensor, or look at the camera | before the first touch, and after each passed one |
| `passed` | One touch or picture was taken | fprintd `enroll-stage-passed`; the helper |
| `retry` | Touch again, the same way | fprintd `enroll-retry-scan` |
| `too-short` | The swipe was too short | fprintd `enroll-swipe-too-short` |
| `not-centred` | Put the finger in the middle of the sensor | fprintd `enroll-finger-not-centered` |
| `lift` | Lift the finger and touch again | fprintd `enroll-remove-and-retry` |
| `too-dark` | The camera sees too little | the helper |
| `no-face` | The camera sees no face | the helper |

The end of the enrolment is never a progress step; it is the `Result` signal. Its reason gains three words, an additive change to the closed set of ADR-0014: `duplicate` (fprintd `enroll-duplicate`, the finger is already enrolled for another user or another finger), `storage-full` (fprintd `enroll-data-full`) and `device-gone` (fprintd `enroll-disconnected`). Any other failure of fprintd or the helper is `failure` with no reason.

Test name: `progress_steps_are_a_closed_set`.

### 5. The reset after a forgotten PIN

`Reset(s prompt_id)`: on a prompt for the caller's own user, the Agent asks polkit whether the caller may do the action `io.github.LinuxHello.reset`, with the caller's bus connection as the subject (polkit's `system-bus-name` subject, which a process cannot fake by reusing a process id) and with interaction allowed. polkit's agent in the person's session, which KDE ships, then asks for the account password, and the default of the action is `auth_self`: the person proves who they are with the account password, as ADR-0003 says. The call returns at once; the end is the `Result` signal. Root may call it on a prompt it opened for any user, with no polkit check, so that `sudo linuxhello-ctl reset --user anna` works for an administrator.

When it is authorised, the Agent, in this order:

1. deletes every device-bound passkey of the user in the TPM provider;
2. deletes the PIN record and the wrapped root key;
3. clears the user's count of wrong PINs and their lockout.

It keeps the user's own policy layer, the enrolled fingers (they are fprintd's, and they can sign in again only once a new PIN exists, because the PIN is the root, invariant 1) and the face models. It does not set a new PIN; the page calls `SetPin` next. A reset that stops half way is reported as `failure`, and a second reset finishes it; each step deletes only what is still there.

The page shows what will be lost before it calls `Reset`, from the warning list of [#157](https://github.com/LinuxHello/linux-hello/issues/157). How many passkeys that is, the Agent does not say in this decision; a count call is left to #157.

Test names: `reset_needs_polkit_or_root`, `reset_deletes_what_adr_0003_says_and_nothing_else`, `reset_keeps_fingers_face_and_policy`, `a_half_done_reset_is_finished_by_the_next`.

### 6. What this decision does not change

`SetUserPolicy` still needs no proof of who the caller is; that is [#131](https://github.com/LinuxHello/linux-hello/issues/131), which may later require the PIN as `EnrolFingerprint` does. The PIN dialog keeps `SetPin`, `ChangePin`, `ExpectPin` and `GetPinRules` as they are.

## Consequences

**Easier:**

- The settings page does everything over one bus connection and the PIN socket, with no program started and nothing parsed from text.
- A finger or a face can be added only by someone who knows the PIN, so an unlocked session left alone for a minute does not give a stranger a way in.
- The reset uses the account password through polkit, the dialog every KDE user already knows, and the Agent never sees that password.
- Each section of the page can be hidden by `GetCapabilities` when its service (fprintd, the Howdy helper) is missing.

**Harder:**

- Eight new members and one signal to confine and test; the Agent's AppArmor profile and bus policy need polkit's `CheckAuthorization` and fprintd's enrolment calls.
- The Agent becomes a client of polkit, and Linux Hello ships a polkit action file for `io.github.LinuxHello.reset`.
- The face calls wait for the Howdy helper (#272).
- `linuxhello-ctl` needs the same reset for an administrator, as root, and a person at a text console has no polkit agent, so they cannot reset their own enrolment without an administrator.
