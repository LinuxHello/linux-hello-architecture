---
type: adr
subject: One shared prompt module; the lock screen uses the stock Face and Fingerprint services, SDDM gets an own theme
artifact: adr
status: accepted
owner: "@atterdag"
concepts: [plasma, sddm, kscreenlocker, qml, prompt]
tags: [adr, plasma, ux]
sources: ["../spikes/0009-plasma-prompt-component.md", "../spikes/0007-pam-dbus-method-state.md", "0014-agent-bus.md", "../arc42/08-crosscutting-concepts.md"]
date: 2026-11-08
---

# ADR-0016: Where the authentication prompt is shown

## Status

Accepted, 2026-11-08, on the maintainer's decision the same day (proposed 2026-11-08). Amendment accepted 2026-11-21, on the maintainer's decision the same day (proposed 2026-11-21): Linux Hello's own login screen as a greeter for greetd, subject to [spike 0311](../spikes/0311-greetd-greeter.md), and Linux Hello's prompt in a slot of KDE's lock screen as the goal (see *Amendment 2026-11-21*).

## Context

UX1 to UX5 want the login manager, the lock screen and in-session prompts to look the same and to show the active method. [Spike 0009](../spikes/0009-plasma-prompt-component.md), read at Plasma 6.8.2 and SDDM `develop`, found that neither login manager nor lock screen has a slot for a third-party prompt:

- **SDDM** loads a whole theme directory and has no theme inheritance; a theme can import any QML module on the greeter's path.
- **The Plasma Login Manager** (new in 6.8, a fork of SDDM) compiles its greeter QML in and has no theme hook.
- **The lock screen** in 6.8.2 is `lockscreen/LockScreen.qml` in the shell package named by `ShellPackage`, which also selects plasmashell's shell. From 6.8 it lists Password, Smartcard, Fingerprint, Face and Universal 2 Factor as PAM services `kde`, `kde-smartcard`, `kde-fingerprint`, `kde-face`, `kde-u2f` and shows their PAM info and error text. Plasma 6.6.x, which Ubuntu 26.04 ships, has only `kde`, `kde-fingerprint` and `kde-smartcard`.
- **One QML module** in the system QML directory can be imported by all hosts, as `org.kde.breeze.components` already is. The page around it differs per host.
- A prompt can only see method state over the **system bus** ([ADR-0014](0014-agent-bus.md)).

| Option for the lock screen | Pros | Cons |
| :-- | :-- | :-- |
| **A. Stock services**: configure the `kde-face` and `kde-fingerprint` services (Plasma 6.8 and later) and show their PAM text | No QML of ours, no fork; works with what KDE ships | Text only, no live camera state; one method per service, not the parallel face, fingerprint and PIN of UX3; not on 6.6 |
| B. Fork of `org.kde.plasma.desktop` limited to `lockscreen/` | Our component on the lock screen | Replaces what plasmashell loads when the same key is used; tracks Plasma releases |
| C. Propose a method-state slot in `LockScreenUi.qml` upstream | The clean end state | Needs KDE's agreement and a release; nothing to ship until then |

| Option for the login manager | Pros | Cons |
| :-- | :-- | :-- |
| **D. Own SDDM theme package** (a Breeze fork) importing the shared module | Works today in SDDM | We own a theme and follow Breeze |
| E. An upstream patch to SDDM or the Plasma Login Manager | No fork | The Plasma Login Manager has no theme hook, so only this works there; needs upstream |

## Decision

1. **One shared QML module**, `Auth Prompt QML Component`, installed in the system QML directory with its URI under the ADR-0012 prefix. Every host imports it; it reads state from the Agent on the system bus ([ADR-0014](0014-agent-bus.md)).
2. **Lock screen: option A on Plasma 6.8 and later**, with C proposed upstream once the first release shows what is missing. On Plasma 6.6.x the lock screen runs the face, fingerprint and PIN methods inside the `kde` service through `pam_linuxhello`, text only. Option B is not adopted.
3. **SDDM: option D.** The Plasma Login Manager is supported only after an upstream change (option E) and is not part of 1.0.
4. **In-session Prompt UI:** the shared module in a Linux Hello window outside the calling app.

The parallel-methods rule of UX3 therefore holds at SDDM, `sudo` and the console, where one PAM conversation runs all methods, and not on the 6.8 lock screen, where KDE already runs separate PAM services. [Spike 0007](../spikes/0007-pam-dbus-method-state.md) noted the clash; this ADR resolves it in favour of KDE's services at the lock screen.

### Amendment 2026-11-21 (accepted): Linux Hello's own login screen under greetd, and Linux Hello's prompt inside KDE's lock screen

The decision above gave the login screen an SDDM theme of Linux Hello's own (option D) and the Plasma 6.8 lock screen KDE's own face and fingerprint services (option A). The [UI proposals of November 2026](../notes/ui-proposals-2026-11.md) drew both, state by state, and reading SDDM's and KDE's source for them showed what each can and cannot show. On that basis the maintainer chose differently for both places.

In plain words: Linux Hello writes its own login screen, a small program that sits on top of greetd, a minimal login service, and can start any desktop installed on the machine. On the lock screen it stays inside KDE's own lock screen and asks KDE for a place where Linux Hello's prompt can sit. It does not write a lock screen of its own.

**Why the login screen changes.** A PAM module talks to the screen only through the *PAM conversation*: questions, and lines of text marked as information or error. SDDM, the login screen Plasma uses, handles that conversation in a way no theme can repair:

- SDDM's daemon answers every PAM question itself, with the text typed into the greeter, so the module's own question ("PIN (or use the fingerprint sensor or the camera, then press Enter):") never appears (`Display::slotRequestChanged` in SDDM's `develop` branch).
- Every PAM error line makes the greeter treat the login as failed at once, while the fingerprint and the face may still be running (`Display::slotAuthError`). The [ADR-0024](0024-agent-status-interface.md) amendment sends severe conditions, such as "The TPM no longer holds the key that your PIN opens…", as error lines.
- PAM starts only when the person presses Enter, so nothing about the attempt can be shown before that.

greetd is a small login service that runs PAM and starts the chosen desktop as the person; the screen is a separate program, the *greeter*, that talks to greetd over a socket. greetd passes each PAM question to the greeter with its text and its kind (a visible or secret question, an information line or an error line) and waits for the answer (manual page `greetd-ipc(7)`, read on the Arch Linux mirror of version 0.10.3). The greeter can then show what the module says, with the right severity, as soon as an account is chosen. It reads the installed desktops from `/usr/share/wayland-sessions` and `/usr/share/xsessions`, as GDM and SDDM do, so the same login screen starts Plasma, GNOME or any other desktop.

**Why the lock screen changes.** On Plasma 6.8, KDE runs one PAM service per method (`kde` for the password, `kde-fingerprint`, `kde-face`) and draws a row for each. Filling those services with Linux Hello (option A) splits one sign-in into a separate prompt at the Agent for each method, needs a new module argument that limits a service to one method, and shows no information line from the fingerprint and face rows (no handler was found in `LockScreenUi.qml` or `MainBlock.qml`). A slot in KDE's lock screen for Linux Hello's prompt (option C) shows the same method tiles as the login screen and the live state of every method.

| Option | Pros | Cons |
| :-- | :-- | :-- |
| **F. Login: a greeter of Linux Hello's own for greetd** | Shows every PAM question and line with its kind; starts any desktop; needs nobody else's change | Linux Hello owns the login screen: its look, keyboard layouts, accessibility and translations; people move from SDDM, GDM or the Plasma Login Manager to greetd |
| D. Login: an own SDDM theme (the earlier decision) | Works inside SDDM, which Plasma installs | Cannot show the module's question; an error line ends the attempt in the greeter |
| E. Login: a change to SDDM upstream | No screen of Linux Hello's own | Nothing ships until SDDM releases it; the Plasma Login Manager needs the same |
| **C. Lock: a slot in KDE's lock screen** | One look with the login screen; live state of every method | Needs KDE's agreement and a release |
| A. Lock: KDE's stock services (the earlier decision for 6.8) | No QML of Linux Hello's own | Separate prompts per method; no information lines from the method rows |
| G. Lock: a lock screen of Linux Hello's own | Full control | On Wayland only the locker the compositor trusts can lock safely; KWin, KDE's compositor, starts KDE's own, and is listed as not supporting `ext-session-lock-v1`, the standard protocol that lets another program lock the screen |

**Decision: option F for the login screen and option C for the lock screen.**

1. **The login screen is a greeter of Linux Hello's own for greetd,** written in QML around the shared Auth Prompt (decision 1). It lists every installed desktop and starts the chosen one through greetd. This replaces decision 3. It holds only if [spike 0311](../spikes/0311-greetd-greeter.md) answers yes: a QML greeter under greetd signs a person in with `pam_linuxhello` to Plasma on Wayland and to one other desktop, and shows every question and line with its kind. If the spike answers no, decision 3 stands, with the live method row of the UI proposals (login proposal B).
2. **SDDM and the Plasma Login Manager are not given a Linux Hello theme.** `pam_linuxhello` still works in them through the shipped `login` PAM lines; the person types the PIN and sees what SDDM's own theme shows, which for the stock Breeze theme is "Login Failed" and no line of the module.
3. **The lock screen's goal is option C.** Linux Hello proposes to KDE a slot in the lock screen for a part that shows method state, can answer the PAM conversation and can set the field's placeholder. The proposal is made now, not after the first release as decision 2 said. In the slot sits the shared Auth Prompt, and `pam_linuxhello` runs every method in the `kde` service.
4. **Linux Hello writes no lock screen of its own** (option G), for the reason in the table: an unlocker that the compositor does not trust can be drawn over or bypassed, which is the worst kind of bug a lock screen can have. The wayland.app table is a secondary source; KWin's own code was not checked.
5. **No screen part runs a program.** The greeter talks only to greetd's socket and to the Agent over its D-Bus interface `io.github.LinuxHello.Agent1`; the part in the lock screen talks only to the Agent. Neither starts `linuxhello-ctl`, `busctl` or any other command (the maintainer's rule in the UI proposals: starting a program is slower, adds code an attacker can use, and a program found by name through `PATH` can be swapped for a fake one).
6. **Decisions 1 and 4 are unchanged.** The shared QML module is now imported by the greeter and by the part in the lock screen's slot.

Not decided here: what runs on the lock screen until KDE ships the slot (the UI proposals recommend option A of this ADR's first table, `pam_linuxhello` in the `kde` service on Plasma 6.6 and 6.8, if KDE's own fingerprint service can be kept off the sensor, which was not verified); which small compositor shows the greeter; how the greeter and the lock screen's part learn the id of the prompt that the PAM module opened, and may subscribe to it; and the full list of what a login screen must do besides signing in (keyboard layout, screen reader, shutdown, more than one monitor), which spike 0311 collects.

**Consequences of the amendment.** Linux Hello owns a login screen and its accessibility and translations, and is supported only for people who switch to greetd. `workspace.dsl` and [section 5](../arc42/05-building-block-view.md) replace the `SDDM Theme` component with the `Linux Hello Greeter` and the SDDM login manager with greetd; if spike 0311 answers no, they go back. The runtime view of a login in [section 6](../arc42/06-runtime-view.md) changes from SDDM to greetd once spike 0311 has answered. Until KDE ships the slot, the lock screen shows only PAM text.

## Consequences

**Easier:** no shell-package fork; a small shared component; the lock screen follows KDE's own method list.

**Harder:**

- UX2 and UX4 text at the lock screen is whatever the PAM services print; there is no live camera state there.
- Face on the lock screen needs Plasma 6.8; on 6.6.x it is text inside the password service.
- We own an SDDM theme and follow Breeze changes.
- Not verified (spike 0009): whether the `sddm` greeter has a session bus, how the Plasma Login Manager sets up its bus and PAM, and addressed signal delivery to one peer.
- [Section 5](../arc42/05-building-block-view.md) and [workspace.dsl](../workspace.dsl) name `SDDM Theme` and `Lock Screen Shell Package`; once this is accepted the second becomes "stock services, no package" and the component is removed.
