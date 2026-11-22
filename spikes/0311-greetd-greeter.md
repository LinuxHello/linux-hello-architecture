---
type: spike
subject: Can Linux Hello's own login screen be a QML greeter for greetd that starts Plasma and any other desktop?
artifact: spike
status: answered
owner: "@atterdag"
concepts: [greetd, greeter, login-screen, pam, pam-linuxhello, plasma, wayland]
tags: [spike, plasma, ux]
sources: ["../notes/ui-proposals-2026-11.md", "https://github.com/LinuxHello/linux-hello/issues/311", "../adr/0016-prompt-hosts.md", "../adr/0023-pam-module-and-login-failure.md", "../adr/0024-agent-status-interface.md", "https://man.archlinux.org/man/greetd-ipc.7.en"]
date: 2026-11-21
issue: https://github.com/LinuxHello/linux-hello/issues/311
---

# Spike 0311: a Linux Hello greeter for greetd

This spike has not run yet; it is tracked in [linux-hello#311](https://github.com/LinuxHello/linux-hello/issues/311).

## Question

Linux Hello wants a login screen that shows exactly what its PAM module says: the module's own question, its messages, and whether a message is an error or only information. PAM (Pluggable Authentication Modules) is the Linux system through which a login screen asks a module to check a person; `pam_linuxhello` is Linux Hello's module, which hands the checking to the Agent, Linux Hello's system service. SDDM, the login screen Plasma uses today, cannot do this: it answers the module's question itself with the typed text and treats every error line as a failed login ([the UI proposals](../notes/ui-proposals-2026-11.md) explain what was found in its source). The maintainer therefore chose, on 2026-11-21, to build Linux Hello's own login screen (login proposal D).

The plan is not to write a whole login manager but only the screen. greetd is a small login service that runs PAM and starts the chosen desktop; the screen it shows is a separate program, the *greeter*, which talks to greetd over a socket. greetd passes each PAM question to the greeter with its text and its kind (a visible or secret question, an info line or an error line) and waits for the answer, according to its manual page `greetd-ipc(7)`.

The question, to be answered yes or no: **can a QML greeter under greetd, on Ubuntu, sign a person in with `pam_linuxhello` to Plasma on Wayland and to one other desktop, and show every question and message of the module with its kind?**

The answer decides whether the login screen is built this way, or whether Linux Hello falls back to its own SDDM theme (login proposal B).

## Time box

Two working days.

## Method

Steps 1 to 5 were run on 2026-11-22: first the protocol half on a test VM without a desktop, then everything on a second test VM with Plasma (see *Evidence*). Step 5 is run except for the fingerprint and the lockout. Step 6 is answered from what the run showed and from reading, item by item; none of it is built.

1. In the test VM (Ubuntu 26.04, Plasma 6.6), install greetd from the distribution and a small Wayland compositor to show the greeter (for example `cage`, which shows one program full screen). Record the versions.
2. Write a minimal greeter in QML with a small Rust or C++ part that speaks greetd's protocol: `create_session`, `post_auth_message_response`, `start_session`, `cancel_session`. It shows the text of each question above a field, and info and error lines in two colours. It must start no other program and run no command (the maintainer's rule in the UI proposals).
3. Give greetd a PAM file with Linux Hello's shipped `login` lines (`pam_linuxhello.so context=login`, then `pam_unix`).
4. Read the installed desktops from `/usr/share/wayland-sessions` and `/usr/share/xsessions` and start the chosen one's command with `start_session`.
5. Check each of the nine states drawn in login proposal D: the question, a PIN that works, a wrong PIN, an empty Enter with the fingerprint (a virtual or real sensor), a lockout, the Agent stopped (the account password must then work), and a condition such as `tpm-cleared` shown as an error before anything is typed.
6. Check what a login screen must do beyond signing in, and note each one as done, missing or out of scope: choosing the keyboard layout, the on-screen keyboard and screen reader, the user list, shutdown and restart, a second monitor, and starting after a crash.

## What a yes or no changes

- **Yes:** point 1 of the [ADR-0016](../adr/0016-prompt-hosts.md) amendment of 2026-11-21 holds: Linux Hello's login screen is a greetd greeter, in place of decision 3 (the own SDDM theme). `workspace.dsl` already models the `Linux Hello Greeter` under greetd, and the login sequence in section 6 is rewritten.
- **No or partly:** decision 3 of ADR-0016 stands, `workspace.dsl` goes back to an `SDDM Theme` component, with login proposal B, the live method row in an own SDDM theme, and the spike's findings say what greetd would need.

## Evidence

**Run of 2026-11-22, the protocol half** (`make vm-test-greetd` in the maintainer's workstation repository). The test VM runs Ubuntu 26.04 as a server image, with no display and no Plasma, so it answers only whether greetd passes the PAM module's conversation to a greeter. It does not answer whether a QML greeter can show it or start a desktop.

What was set up: greetd 0.10.3-5 from Ubuntu's archive, whose package runs the greeter as the user `_greetd`. Its PAM file `/etc/pam.d/greetd` includes `login`, and the prototype installer had put Linux Hello's line at the top of `login`: `auth [success=done authinfo_unavail=ignore default=die] pam_linuxhello.so context=login`. In place of a real greeter, greetd started a stand-in that only wrote down the path of greetd's socket. A small Python program then played the greeter on that socket. It sent `create_session` for a test user with a PIN, printed every `auth_message` with its kind, and answered each question. The Linux Hello build was the prototype of 2026-11-21, without the fingerprint and the face (the VM has neither).

| What the person does | What the greeter received, in order | Outcome | Check |
| :-- | :-- | :-- | :-- |
| Types a wrong PIN | `secret` "PIN: ", then `error` "Wrong PIN." | `auth_error`, and no question for the password | PASS |
| Presses Enter on an empty PIN | `secret` "PIN: ", then `secret` "Password: " | the account password signs in | PASS |
| Signs in while the Agent is stopped | `secret` "Password: " | the account password signs in | PASS |
| Types the right PIN | `secret` "PIN: " | `success`; `start_session` accepted | PASS |

Three findings:

1. **greetd passes the module's own question and the kind of each line.** The question reached the greeter word for word as a secret question, and "Wrong PIN." as an error line. SDDM, the login screen Plasma uses today, answers the question itself and treats every error line as a failed login ([ADR-0016](../adr/0016-prompt-hosts.md), amendment of 2026-11-21). An error line did not end the attempt on greetd's side: greetd reported the failure only once PAM returned it.
2. **The fall-through to the password works under greetd** for an empty answer and for a stopped Agent, as ADR-0023 decides. The installer's line in `login` is enough; greetd's file needs no line of its own. A first run that added one ran the module twice and asked for the PIN twice.
3. **Not shown:** whether `start_session` then starts the session. greetd starts it only once the greeter has exited; in this run no session of the test user appeared after the stand-in was ended, because greetd started the greeter again. This needs a real greeter and a desktop.

### Run of 2026-11-22 on a VM with Plasma (`make vm-test-greeter`)

A second test VM got Plasma 6.6.7 on Wayland from Ubuntu 26.04's archive, without SDDM, and greetd 0.10.3 with cage 0.2.1. cage is a Wayland compositor that shows one program full screen, the greeter. Linux Hello was installed from `main` with its prototype installer, including the line in `login`. The greeter is spike code, never shipped: a QML window with a small Python part (PySide6 6.10) that speaks greetd's socket protocol. It starts no program itself; greetd starts the chosen desktop. The window shows the question above a field, information lines in blue and error lines in red. It reads the desktops from `/usr/share/wayland-sessions`, the same files GDM and SDDM read. For a run without a person, the Python part types the answers itself after a pause, so that a screenshot of the VM's screen shows each state.

| State | What the greeter showed | Check |
| :-- | :-- | :-- |
| The person is chosen | the module's own question, "PIN:", above a hidden field | PASS |
| The right PIN, Plasma chosen | signed in; greetd started Plasma, and `kwin_wayland` and `plasmashell` ran as the person | PASS |
| A wrong PIN | the error line "Wrong PIN." in red, then the failure | PASS |
| The Agent stopped | the information line "Linux Hello is not available. Use your account password." in blue, then "Password:" | PASS |
| The right PIN, Weston chosen | greetd started Weston, a second desktop, from the same greeter | PASS |
| The TPM cleared | the error line "The TPM no longer holds the key that your PIN opens…" in red, above the PIN question, before anything was typed | PASS |
| An empty Enter with the fingerprint | not run: the VM has no fingerprint reader | — |
| A lockout | not run | — |

Findings of this run:

1. **cage 0.2.1 crashes if the window asks for full screen before its first frame** (an assertion in cage's `schedule_configure`). Dropping the request was enough, because cage shows its one window full screen anyway.
2. **When the TPM was cleared, the module still asks for the PIN.** The error line says the PIN cannot be used, and the question asks for it anyway. Not asking for the PIN in that case is a change to the PAM module, not to the greeter.
3. **The installer adds Linux Hello to `login` only with `--console`.** greetd's PAM file includes `login`, so the greeter gets the module only after `install.sh --console`. The greeter's installer needs its own step.
4. **greetd restarts the greeter when it exits without starting a session** ("greeter exited without creating a session" in greetd's journal), so a crashed greeter comes back by itself.

What a login screen must do besides signing in (step 6). None of these is built in the spike greeter; this is what the run and the reading say about each:

| Need | Status |
| :-- | :-- |
| Restart after a crash | Done by greetd itself (finding 4) |
| The list of desktops | Done: read from `/usr/share/wayland-sessions`; X11 sessions in `/usr/share/xsessions` are not tried |
| The list of users | Missing: AccountsService (`org.freedesktop.Accounts` on the bus) lists them, as other greeters do |
| Shutdown and restart | Missing: logind's `PowerOff` and `Reboot` on the bus; whether polkit allows them to the greeter's session is not checked |
| Keyboard layout | Missing: cage takes the layout from `XKB_DEFAULT_LAYOUT`; choosing one in the greeter is not tried |
| On-screen keyboard and screen reader | Open: not tried under cage |
| A second monitor | Open: not tried; cage has its own rules for more than one output |

## Answer

**Yes.** A QML greeter under greetd signs a person in with `pam_linuxhello` and starts Plasma on Wayland and another desktop (Weston). It shows the module's question word for word, its information lines and its error lines with their kind, including a condition before anything is typed. This holds point 1 of the ADR-0016 amendment of 2026-11-21: Linux Hello's login screen is its own greeter for greetd. What a real login screen needs besides that (the users, shutdown, keyboard layout, accessibility, monitors) is listed above as work for the greeter ([#319](https://github.com/LinuxHello/linux-hello/issues/319)), not as a reason against it.
