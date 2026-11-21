---
type: note
subject: UI proposals for Linux Hello on the KDE Plasma login screen, lock screen and System Settings
artifact: note
status: answered
owner: "@atterdag"
concepts: [plasma, sddm, kscreenlocker, kcm, prompt, status, pam]
tags: [ux, plasma, proposal]
sources: ["../adr/0016-prompt-hosts.md", "../adr/0021-pin-transport.md", "../adr/0023-pam-module-and-login-failure.md", "../adr/0024-agent-status-interface.md", "../arc42/06-runtime-view.md", "../arc42/08-user-experience.md", "../workspace.dsl"]
date: 2026-11-21
---

# UI proposals for Linux Hello on KDE Plasma, November 2026

Linux Hello lets a person sign in to a Linux desktop with a PIN, a fingerprint or their face instead of the account password. This note points to a set of drawn proposals for the three places where a person meets Linux Hello on a KDE Plasma desktop: the login screen, the lock screen and a page in System Settings. It says what each proposal needs that does not exist yet, which one is recommended per place, and which questions are still open. The proposals feed the decision about the Plasma part of Linux Hello ([linux-hello#213](https://github.com/LinuxHello/linux-hello/issues/213) and an ADR, an architecture decision record, for the `plasma` container in [workspace.dsl](../workspace.dsl)).

**State:** nothing here is built. The proposals are mockups in a Plasma-like style; they use no KDE logo and are not KDE's design.

## The rule every proposal follows: no screen part runs a command

The maintainer's requirement is that no part of Linux Hello's user interface starts a shell or any other program: not `linuxhello-ctl`, `busctl`, `fprintd-enroll`, `howdy` or anything else. A screen part talks to the Agent directly, over its D-Bus interface `io.github.LinuxHello.Agent1`, and sends a PIN only over the Agent's PIN socket ([ADR-0021](../adr/0021-pin-transport.md)). There are three reasons. Starting a program for every action is slow. Every extra program is more code that an attacker can use. And a program found by name through `PATH`, the list of folders the system searches, can be replaced by a fake one that sits between the screen and the Agent and reads or changes what passes. Any design that needs a helper command is therefore out, and every proposal names the Agent calls it uses.

What this means for the proposals:

- **Login and lock screens.** In every proposal the PAM module makes the Agent calls, all of which exist: `OpenPrompt`, `Subscribe`, `Authenticate`, `GetPromptStatus`, `ExpectPin` with the PIN on the PIN socket, and `ClosePrompt`. Login proposal B and lock proposal C also call `Ping`, `Subscribe` and `GetState` from the screen itself and listen to the prompt's signals. None of them runs a program.
- **System Settings.** The page uses `GetStatus`, `GetPinRules`, `GetEffectivePolicy`, `GetUserPolicy`, `SetUserPolicy`, and `OpenPrompt` with `SetPin` or `ChangePin`, `ExpectPin` and `ClosePrompt`, which exist. Enrolling fingers and setting up the face need **new Agent calls**, because the page may not run `fprintd-enroll` or `howdy add` itself. Whether a PIN is set and the reset after a forgotten PIN need new calls too. The calls table on the board names placeholders such as `EnrolFingerprint` and `EnrolFace`; their names and shapes are not decided.
- **Fingerprint setup moves into Linux Hello's page.** The earlier plan (UX7 in [section 8](../arc42/08-user-experience.md)) was to link to KDE's own fingerprint window on the Users page. Under this rule the page enrols fingers through the Agent instead.
- **Sentences that name a command.** `pin-expires-soon` and `pin-expired` say "Change it with linuxhello-ctl pin change." A screen shows its own words for these codes, such as "Change it in System Settings", and never runs the command.

## Where the proposals are

All proposals are on one design canvas: [Linux Hello on Plasma — UI proposals](https://claude.ai/artifact/C4tvVvhmrPhuc13DeBW9ij). The link is private to the maintainer's account until it is shared from the page. The canvas has four pages:

| Page | What you find there |
| :-- | :-- |
| [Read me and recommendation](https://claude.ai/artifact/C4tvVvhmrPhuc13DeBW9ij#page-overview) | How to read a proposal, the terms used, what was checked in KDE's and SDDM's source code, and the recommendation per place. |
| [Login screen (SDDM)](https://claude.ai/artifact/C4tvVvhmrPhuc13DeBW9ij#page-login) | Three proposals for SDDM, the login screen Plasma uses. |
| [Lock screen](https://claude.ai/artifact/C4tvVvhmrPhuc13DeBW9ij#page-lock) | Three proposals for kscreenlocker, Plasma's lock screen. |
| [System Settings page](https://claude.ai/artifact/C4tvVvhmrPhuc13DeBW9ij#page-settings) | Two proposals for Linux Hello's own page in System Settings (a KCM, a KDE Configuration Module), each with a table of the Agent calls it needs. |

Every login and lock-screen proposal shows the same nine screens in the same order, so they can be compared square by square: the question while PIN, fingerprint and face all run; a finger or face being checked; success; a wrong PIN; a finger or face not recognised; a lockout; Linux Hello unavailable, so the account password is asked; a condition before sign-in (the TPM, the Trusted Platform Module that holds the PIN's key, was cleared); and a condition after sign-in (the PIN expires soon). A *condition* is a fact that the Agent, Linux Hello's system service, reports with a severity and one fixed sentence ([ADR-0024](../adr/0024-agent-status-interface.md)).

## The proposals

Each login and lock-screen proposal is tagged with what it needs: only the PAM text lines that work today (PAM, Pluggable Authentication Modules, is the Linux system through which a login screen asks a module to check a person), a screen part in QML (the language Plasma screens are made of) that calls the Agent, or a change that KDE or SDDM must accept first.

| Place | Proposal | Idea in one sentence | Needs |
| :-- | :-- | :-- | :-- |
| Login screen | A. Message line | Linux Hello's own SDDM theme labels the field "PIN", prints a fixed hint and shows every PAM line of the attempt. | PAM text only, plus the own theme already decided in [ADR-0016](../adr/0016-prompt-hosts.md). |
| Login screen | B. Live method row | The same theme plus the shared Auth Prompt, one QML part that every Linux Hello screen imports; it follows the Agent's signals about the sign-in attempt and shows each method's state. | QML that calls the Agent from the greeter, the program that draws the login screen. |
| Login screen | C. Methods start at once | SDDM holds a real PAM conversation and starts the attempt when an account is picked; the module waits briefly for a finger or face. | A change in SDDM (and in the Plasma Login Manager). |
| Lock screen | A. Inside the password service | `pam_linuxhello`, Linux Hello's PAM module, runs all methods inside KDE's `kde` PAM service; the lock screen prints its lines. | PAM text only. |
| Lock screen | B. KDE's own method rows | On Plasma 6.8, `pam_linuxhello` runs in `kde`, `kde-fingerprint` and `kde-face`, each limited to one method; KDE draws the rows. | PAM text only, plus a new module argument. |
| Lock screen | C. Shared prompt in the lock screen | KDE adds a slot for a method-state part; Linux Hello's Auth Prompt sits there. | A change in KDE. |
| System Settings | A. One page | Status, PIN, fingerprint, face and a table of where each method works, on one scrolling page; sheets for changing the PIN and setting up the face. | Existing Agent calls, plus new ones for fingerprint and face enrolment, the PIN state and the reset (the calls table on the board). |
| System Settings | B. Overview with subpages | One card per method and a subpage behind each, with three first-run steps when no PIN is set. | The same Agent calls as A, existing and new. |

## Recommendation

- **Login screen: B, reached through A.** Ship the own theme as A first, since the stock Breeze theme (KDE's default look) shows no PAM line at all; add B's live method row once the greeter's bus access and the prompt questions below are settled; offer C to SDDM later. The cost is a copy of Breeze to maintain.
- **Lock screen: A on Plasma 6.6, B on 6.8, C proposed upstream.** This is ADR-0016 as decided, made concrete. The cost is two behaviours by Plasma version, and on 6.8 KDE does not show the info lines of its method rows.
- **System Settings: A, with B's first-run steps.** Everything visible on one page, as on KDE's Users page. The cost is a long, dense page once everything is set up.

## The maintainer's choice

On 2026-11-21 the maintainer chose **login proposal B** (the live method row in Linux Hello's own SDDM theme), **lock proposal C** (the shared Auth Prompt in a slot that KDE adds to its lock screen) and **settings proposal A** (one page).

What follows from the choice:

- **The lock screen differs from ADR-0016.** [ADR-0016](../adr/0016-prompt-hosts.md) chose KDE's stock services on Plasma 6.8 and left a slot in KDE's lock screen as a later proposal to KDE. Choosing C makes that slot the goal, so ADR-0016 needs an amendment.
- **The lock screen needs an answer until KDE ships the slot.** Proposal C cannot ship before KDE accepts and releases the change. Until then something must run on the lock screen; proposal A is the one that works today, on Plasma 6.6 and 6.8.
- **Login B depends on open question 5**: whether SDDM's greeter can reach the system bus, and how it learns and may subscribe to a prompt that SDDM's helper opened.
- **Settings A depends on open question 10**: the new Agent calls for fingerprint and face enrolment, the PIN state and the reset.
- **Not done yet:** the ADR for the `plasma` container that records these choices, and the changes to `workspace.dsl` and section 8 that follow from it.

The recommendation above is kept as written, for the record of what was weighed.

## What was checked, and what was assumed

The following was read in the source on 2026-11-21 (SDDM `develop`; `plasma-desktop` and `kscreenlocker` `master`, version 6.8.80). Nothing was run on a desktop.

- SDDM never shows the module's question: its daemon answers every PAM question itself with the text the person typed (`Display::slotRequestChanged`). PAM starts only when the person presses Enter or the login button.
- SDDM passes PAM info and error lines to the greeter as `informationMessage` during the attempt, and an error line also makes the greeter treat the login as failed at once (`Display::slotAuthError`).
- The stock Breeze SDDM theme does not handle `informationMessage`; it shows only "Login Failed" for 3 seconds.
- The lock screen asks interactively: the module's question and every info and error line are added to one text by the field (`handleMessage` in `LockScreenUi.qml`), cleared 3 seconds after a failure. The field's placeholder is always "Password", and an empty answer can be sent.
- The lock screen runs the fingerprint service in parallel with the password service. The default service names are `kde`, `kde-fingerprint`, `kde-smartcard`, `kde-face` and `kde-u2f`. A method whose service answers "unavailable" within 250 ms is hidden.
- Linux Hello's shipped `login` and `unlock` PAM lines fall through to the account password only when Linux Hello is unavailable; a wrong PIN or a lockout ends the attempt (`default=die`).

Assumed: that the shared `SessionManagementScreen` component draws the message text under the field (its file was not reached); that Plasma 6.6 behaves like 6.8 for the `kde` service; the wording of KDE's face row on 6.8; and that the SDDM greeter can reach the system bus (also unverified in ADR-0016).

## Open questions

1. **The PIN expiry after sign-in is not seen.** The module tells it after success, and both screens close at that moment. Should a small part in the session show it as a Plasma notification, calling `GetStatus`? Nothing like it is planned.
2. **Severe conditions at SDDM.** The [ADR-0024](../adr/0024-agent-status-interface.md) amendment sends severe conditions as PAM error lines; SDDM then reports a failed login while the finger and face still run. Should the module send them as info lines at the login screen?
3. **A silent fall-through.** When the Agent is down the module returns without a word, and at SDDM the typed PIN goes to the password module. Should the module first say "Linux Hello is not available. Use your account password."?
4. **The fingerprint line.** With the sensor and the camera both running the module says only "Touch the fingerprint sensor." Should it name both?
5. **The greeter and the prompt (login B).** A *prompt* is the Agent's record of one sign-in attempt, named by an id. SDDM's greeter runs as the `sddm` user and cannot work out the prompt id, which contains the process id of SDDM's helper. Who may subscribe to a login prompt, and how is the id shared?
6. **One method per service (lock B).** Should `pam_linuxhello` take an argument such as `methods=fingerprint`? [ADR-0023](../adr/0023-pam-module-and-login-failure.md) has the module run every method its context allows.
7. **KDE's fingerprint service under lock A on 6.8.** Can `kde-fingerprint` be kept off the sensor without rebuilding KDE, so that only the Agent claims it?
8. **Biometrics during a PIN lockout.** Do the fingerprint and face still run while the PIN is locked? The ADRs read do not say.
9. **The days in `pin-expires-soon`.** The number is only inside the English sentence; a translated settings page needs it as data.
10. **Missing Agent calls for the settings page:** whether a PIN is set (and when it was changed); enrolling, listing and deleting fingers, which also needs a wider rule in polkit (the Linux service that decides which program may ask another for what) so that the Agent's user may enrol at fprintd; setting up, testing and deleting the face ([ADR-0015](../adr/0015-face-capture-and-enrolment.md)); and the reset ([ADR-0003](../adr/0003-destructive-reset.md)). The settings page cannot be finished without them, because it may not run a command instead.
11. **The grace window (login C).** Waiting a few seconds for a finger or face before asking for the PIN is left open in the ADR-0023 amendment of 2026-11-21.
12. **Opening System Settings from the expiry notification.** Does opening the settings page through KDE's own launcher count as running a command under the no-command rule?
13. **UX7.** Section 8 says fingerprint setup reuses KDE's window on the Users page. The no-command rule replaces that with Agent calls; UX7 needs rewording when the ADR for the Plasma container is written.
