---
type: adr
subject: The Agent answers GetStatus with the conditions that affect the caller, and shows file names to root only
artifact: adr
status: accepted
owner: "@atterdag"
concepts: [dbus, status, conditions, doctor, lock-screen, one-way-door]
tags: [adr, one-way-door, dbus, ux]
sources: ["0014-agent-bus.md", "0023-pam-module-and-login-failure.md", "https://github.com/LinuxHello/linux-hello/issues/214", "https://github.com/LinuxHello/linux-hello/issues/155", "https://github.com/LinuxHello/linux-hello/issues/156", "https://github.com/LinuxHello/linux-hello/issues/192", "https://github.com/LinuxHello/linux-hello/issues/213"]
date: 2026-11-17
---

# ADR-0024: The Agent's status interface

## Status

Accepted, 2026-11-17, on the maintainer's decision the same day (proposed 2026-11-17). Answers [linux-hello#214](https://github.com/LinuxHello/linux-hello/issues/214), the interface behind [#155](https://github.com/LinuxHello/linux-hello/issues/155) (the offline `linuxhello-ctl status` and `doctor`, built) and [#213](https://github.com/LinuxHello/linux-hello/issues/213) (status on the login and lock screens). A new D-Bus method is a one-way door (AGENTS.md invariant 7), so it needed the maintainer's decision, which is given. Amendment accepted 2026-11-21, on the maintainer's standing approval of the lead's recommendations (proposed 2026-11-21): the conditions at a sign-in prompt, `GetPromptStatus` (see *Amendment 2026-11-21*).

## Context

`linuxhello-ctl status` and `doctor` read the policy files and report conditions: `policy-pin-only`, `context-unsatisfiable: <context>`, `status-fact-unreadable: the state directory`. Each has a stable code, a severity and one fixed sentence, and `status` never prints a file name. That works offline, for an administrator, from the files alone. It cannot say what only the running Agent knows (the PIN is locked for this user, the TPM is unavailable), and a user at the login or lock screen cannot read the admin policy directory at all. The screens need the same conditions from the Agent, over the bus, scoped to the person looking.

The bus policy lets any user call the Agent's methods and **denies reading properties** (checked on a real system bus by the confinement run), so a `Status` property is not available without changing that rule.

| Option | Pros | Cons |
| :-- | :-- | :-- |
| **A. A method `GetStatus` that returns the caller's conditions** | One call; answers from what the Agent knows; scoped by the caller's uid like every other call; no change of bus policy | A new method on the interface |
| B. A property with `PropertiesChanged` | Change notification for free | The bus policy denies property reads; opening it widens the policy for every user |
| C. Each client computes status from the files, as `linuxhello-ctl` does | No new method | A user cannot read the admin layers, and no client knows the lock or TPM state |

## Decision

**Option A.**

1. **The method.** `GetStatus()` on `io.github.LinuxHello.Agent1` returns `a(sss)`: a list of conditions, each `(code, severity, sentence)`. An empty list means nothing to report. It always answers a caller whose uid the bus gave, whatever is wrong: a fault is a condition, not an error. A caller without a readable uid is refused like every other call (P-02).
2. **Whose conditions.** Those that affect the caller: the caller's own policy layer and PIN lock, and machine-wide faults that change what the caller can do (an admin policy that failed to load, a context that cannot be satisfied, the TPM unavailable). It never names another user and never says whether another user exists.
3. **Codes.** A closed, stable set of lowercase words in kebab case, optionally followed by one parameter from a closed set (a context name such as `login`, `unlock`, `sudo`). A code is never renamed; a new one is an additive change. A client that does not know a code shows the sentence. The first codes are those of `linuxhello-ctl status`; `tpm-locked` follows with #215.
4. **Severity.** One of `info`, `warning`, `severe`. `severe` is the word `linuxhello-ctl` prints today.
5. **Sentence.** One fixed English sentence per code, written for the user. It carries no file name, no path and no text from any file; a number the Agent computes (minutes of lockout) is the one thing that may vary. A client may translate by code.
6. **File names.** `GetStatusDetails()` returns `a(ssss)`: the same conditions plus a fourth field with the detail the loader gives (the file and what is wrong with it). Only root may call it (uid 0, from the bus credentials); any other caller is refused with the same `AccessDenied` as for any request that is not theirs. `GetStatus` never carries the detail field, so no caller learns a path by omission or by error text.
7. **Health call (#192).** `GetStatus` is the Agent's health call. Liveness stays the standard `org.freedesktop.DBus.Peer.Ping`, which the watchdog of #191 already uses. `linuxhello-ctl status` calls `GetStatus` when the Agent answers and falls back to the offline files when it does not; the fallback adds `agent-unreachable` (severe), a condition **the client** computes, never the Agent.
8. **Errors and version (#156).** `GetStatus` follows the error names and the capability call decided for #156; it adds none of its own. The capability list names `GetStatus` and `GetStatusDetails`.
9. **No signal in this decision.** A client calls `GetStatus` when it shows the screen and after the restart rule (`linuxhello_dbus::restart`). A `StatusChanged` signal can be added later without breaking anything; it would carry no payload and be unicast.
10. **Tests the code will name:** `status_is_scoped_to_the_caller`, `status_never_carries_a_file_name`, `status_details_are_for_root_only`, `status_codes_are_a_closed_set`, and a bus test that a user and root get the answers above.

### Amendment 2026-11-20 (accepted): two codes for the PIN path, `tpm-dictionary-limit-low` and `tpm-cleared`

Point 3 left "the exact list of codes" open and said a new code is an additive change. The PIN path now reports two more, and codes cannot be renamed once shipped, so this fixes them.

In plain words: the Trusted Platform Module (TPM, the chip that keeps the keys) has two properties that a person using a PIN should be told about. It locks every key after a number of wrong tries counted for all users together, so Linux Hello keeps its own limit below that number; when it has had to lower the limit, `GetStatus` says so. And when the chip was cleared or replaced, the key that the user's PIN opens is gone with it, so the PIN can no longer be used; `GetStatus` says that too, without anyone typing a PIN to find out.

1. **`tpm-dictionary-limit-low`**, severity `warning`. Reported to every user while the Agent runs with a limit lowered because of the TPM's: "The TPM locks every PIN after N wrong tries, so Linux Hello allows only M wrong PINs before its own lockout." N is the TPM's number and M the Agent's. The Agent reads the TPM's number once, when it starts. It carries no detail.
2. **`tpm-cleared`**, severity `severe`. Reported to a user who has a PIN record when the TPM does not hold the key of that record: "The TPM no longer holds the key that your PIN opens (it was cleared or replaced), so your PIN cannot be used until your enrolment is reset." The check asks the TPM provider to load the user's wrapped root key without a PIN. A cleared TPM has a new storage seed, so the wrapped key fails its integrity check; that counts nothing in the TPM's attempt counter. A damaged record gives the same answer, and the sentence says "cleared or replaced" because the check cannot tell these apart.
3. **What is not claimed.** If the provider cannot be reached, or the user has no record, nothing is reported: an unknown answer is not a cleared TPM. A user sees only their own condition (point 2 of the ADR).
4. **What the user can do.** Until the reset of [ADR-0003](0003-destructive-reset.md) is built, the sentence says the enrolment must be reset; the way to do that is the administrator's.
5. **`doctor`.** `linuxhello-ctl doctor` reads files and runs no PIN probe, so it does not report `tpm-cleared`; `status` does, by the Agent's answer. A `doctor` that reports it for every user would need the Agent's root-only details call and is left for a later change.
6. **Tests the code names:** `status_says_when_the_tpm_lowered_the_pin_limit`, `status_says_when_the_tpm_no_longer_holds_the_pin_key`, `a_key_from_a_tpm_that_was_cleared_is_told_apart_from_a_wrong_pin`, `a_pin_key_that_the_tpm_does_not_hold_is_told_apart_from_a_key_that_it_does`, `a_provider_that_is_not_there_claims_nothing_about_the_key`.

### Amendment 2026-11-21 (accepted): the conditions at a sign-in prompt, `GetPromptStatus`

The maintainer asked that the login screen and the lock screen show what Linux Hello knows about the person signing in, not only `linuxhello-ctl status` ([#213](https://github.com/LinuxHello/linux-hello/issues/213)). This amendment decides how those screens get the conditions.

In plain words: when someone signs in, the program that asks for the PIN is the PAM module, the piece that the login screen, the lock screen and `sudo` load to check a person ([ADR-0023](0023-pam-module-and-login-failure.md)). Pluggable Authentication Modules (PAM) is the Linux system that lets these programs ask a module instead of checking passwords themselves. A PAM module can hand the screen a line of text to show, and every login screen and lock screen already shows such lines. So the module asks the Agent what to say about the person signing in, and passes it on. When the TPM no longer holds the user's key, the lock screen then says "The TPM no longer holds the key that your PIN opens…" above the password field, instead of leaving the person to guess why the PIN fails.

`GetStatus` cannot do this. It answers for the caller, and the caller here is not the person: the login screen runs the module as root, and `sudo` is a program that runs as root too. `GetStatus` would describe root's conditions.

| Option | Pros | Cons |
| :-- | :-- | :-- |
| **A. A method `GetPromptStatus(prompt_id, context)` that answers for the prompt's user, to the program that opened the prompt** | Uses the access rule every prompt call already has; the Agent decides what may be shown before and after sign-in; works on every screen through PAM's text lines | A new method on the interface |
| B. Root may call `GetStatus` for any user | No new method | Every root process learns every user's conditions, which nothing needs; the filtering for "before sign-in" would be on each client |
| C. A part inside Plasma's login and lock screens that calls the Agent | Could show the conditions with icons and layout | Two Plasma parts to build and confine before anything is shown; nothing for `sudo` or a text console |

**Option A.** Option C can be added later for a richer layout; it would call the same method.

1. **The method.** `GetPromptStatus(s prompt_id, s context)` on `io.github.LinuxHello.Agent1` returns `a(sss)`, the same `(code, severity, sentence)` as `GetStatus`, with the same codes and sentences. The capability list names it.
2. **Who may call it.** Only the connection that opened the prompt, for a prompt that has a user, exactly as for `Authenticate`. Anything else is `Denied`, with one text for all, so nothing is told about other prompts. `context` must be one of the four contexts (`login`, `unlock`, `sudo`, `session`), or the call is `InvalidArgument`.
3. **Whose conditions.** Those of the prompt's user (the uid given to `OpenPrompt`), not the caller's.
4. **Before the person has signed in,** only the conditions that explain why Linux Hello may not be able to sign them in: `policy-pin-only`, `context-unsatisfiable: <context>` for this prompt's context only, `pin-lock-damaged` and `tpm-cleared`. Anyone at the screen who types a user name could learn these, so this list is kept to what that person would find out anyway by trying. The PIN lock is not in it, because the `Result` signal already says how long the lock lasts (`locked-out`, with the seconds) the moment a PIN is tried. `tpm-dictionary-limit-low` is a note for the administrator and is not shown at a prompt.
5. **After the prompt's result is `success`,** `pin-expires-soon` and `pin-expired` as well. How old a person's PIN is is told only to someone who just proved to be that person.
6. **The PAM module** calls `GetPromptStatus` once after `OpenPrompt`, and once more after a `success` before `ClosePrompt`. It shows each sentence as a PAM text message: `PAM_ERROR_MSG` for `severe`, `PAM_TEXT_INFO` otherwise. A call that fails or passes its deadline (the call deadline of the amendment of 2026-11-21 to ADR-0023, 2 s) is ignored: the status never changes the answer of the sign-in and never adds a question. `sudo` calls PAM silently by default, so `sudo` shows nothing; `linuxhello-ctl status` is the place to look there.
7. **What the screens show is not checked here.** That SDDM, the login screen of Plasma, and the Plasma lock screen display PAM text messages is what their documentation and source say. It is an assumption until the maintainer's test of the prototype on a real desktop confirms it; the test VM checks the messages at the PAM conversation, through pamtester.
8. **Tests the code will name:** `prompt_status_answers_for_the_prompts_user`, `prompt_status_is_only_for_the_prompts_opener`, `prompt_status_before_sign_in_says_only_why_it_may_fail`, `prompt_status_tells_the_expiry_only_after_success`, `prompt_status_names_only_this_context`, and in the PAM module `the_conditions_are_shown_as_pam_messages`, `a_failed_status_call_changes_nothing`.

## Consequences

**Easier:** the login and lock screens, the Settings page and `linuxhello-ctl` show one set of conditions with one vocabulary; a user sees what concerns them and nothing about anyone else; the interface stays additive.

**Harder:**

- Every condition now has two producers: the offline files (`linuxhello-ctl`) and the running Agent. They must keep the same codes and sentences; one table in `linuxhello_dbus` is the source for both.
- The sentences are English only; a translation is the client's job by code.
- Without a signal, a screen that stays open shows stale status until it asks again.
- `GetStatusDetails` is a second method to confine; it needs the same bus-policy and profile coverage as the first (both are on the interface the profile already names).

Not decided here: the exact list of codes beyond the three above and the lockout seconds in `tpm-locked`. How the greeter and the lock screen get the conditions is decided in the amendment of 2026-11-21 (`GetPromptStatus`); a richer layout inside Plasma is not.
