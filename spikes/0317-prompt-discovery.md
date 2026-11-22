---
type: spike
subject: How a login screen or lock-screen part learns which sign-in attempt the PAM module started, and may follow it without another program disturbing it
artifact: spike
status: open
owner: "@atterdag"
concepts: [prompt, prompt-host, greetd, greeter, lock-screen, pam-linuxhello, dbus, subscribe]
tags: [spike, plasma, security]
sources: ["../adr/0014-agent-bus.md", "../adr/0016-prompt-hosts.md", "../adr/0023-pam-module-and-login-failure.md", "0311-greetd-greeter.md", "https://github.com/LinuxHello/linux-hello/issues/317"]
date: 2026-11-22
issue: https://github.com/LinuxHello/linux-hello/issues/317
---

# Spike: how a screen part finds and follows the PAM module's prompt

This note answers a question that the login screen and the lock screen of Linux Hello both depend on. When a person signs in, the PAM module (`pam_linuxhello`, the piece that the login service and the lock screen load to check a person) asks the Linux Hello Agent to run the fingerprint, the face and the PIN. The screen wants to show which of them is running ("Touch the sensor", "Looking for your face…"), live. To do that it must listen to the same sign-in attempt that the PAM module started. This note says how the screen learns which attempt that is, and what stops another program from listening in or getting in the way. After reading it you know the answer, what was checked, and what is still to be tested.

## Question

Can a screen part, that is the greeter of the login screen or Linux Hello's part in KDE's lock screen, learn the id of the prompt that `pam_linuxhello` opened and subscribe to its signals, without letting another program of the same user follow it or change it? Yes or no.

Two words first. A **prompt** is the Agent's word for one sign-in attempt; it has an id, a user it is for (the *subject*), and the connection on the bus that opened it (the *opener*). To **subscribe** to a prompt is to ask the Agent to send this connection the prompt's signals: which methods run (`ActiveMethods`) and how it ended (`Result`). The bus is D-Bus, the message service that programs on a Linux desktop use to call each other ([ADR-0014](../adr/0014-agent-bus.md)).

## Why it matters

The screens of [ADR-0016](../adr/0016-prompt-hosts.md) (amendment of 2026-11-21) show live method tiles. They cannot do it without this. Two facts make it hard:

1. **The id cannot be guessed.** The PAM module derives the id from the PAM service name (`greetd`, `kde`), the terminal or display, and a value of its own made from its process id and the time (`crates/pam-linuxhello/src/client.rs`, `authenticate_at`). The screen knows the first two but not the third.
2. **The screen is not the opener, and on the login screen not even the same user.** greetd, the login service, runs PAM as root, so root opens the prompt. The greeter runs as greetd's own unprivileged user (on Debian and Ubuntu assumed to be `_greetd`, which the VM run checks). On the lock screen, KDE's locker runs PAM as the person, and Linux Hello's part in the lock screen runs as the same person.

## Time box

Half a day for the analysis below; one day for the run in the test VM, which is still to do.

## Method

1. Read the Agent's access rules for prompts in `crates/linuxhello-agent/src/state.rs` and `api.rs` on `main` at the time of writing (tested code, not a plan).
2. Read how the PAM module opens a prompt (`crates/pam-linuxhello/src/client.rs`).
3. Work out, for the greeter and the lock-screen part, what each can do today and what is missing.
4. **Not done yet:** check the answer in the test VM with greetd and with KDE's lock screen (point 5 of the answer). That needs greetd installed in the VM, which this night's run did not do.

## Evidence

What the Agent allows today, read from the code:

| Who | Open a prompt | Read it and subscribe | Report state on it, or close it |
| :-- | :-- | :-- | :-- |
| Root | for any user | its own prompts | its own prompts |
| The prompt's user | for itself | its own prompts, and a prompt root opened for it | its own prompts, from **any** of its connections |
| A *prompt host* (a uid in the Agent's `prompt_hosts` setting, meant for a greeter's user) | for itself | **any** prompt root opened | no |
| Anyone else | for itself | no | no |

So the permission half of the question is already answered for the login screen: if the greeter's user is a prompt host, it may subscribe to the prompt that root opened. The Agent's `main.rs` sets no prompt host yet (`Config::new(Vec::new())`).

Three things are missing or wrong:

1. **No way to learn the id.** No call lists prompts or says that one was opened.
2. **A prompt host sees too much.** It may read any prompt that root opened. `sudo` also runs as root, so a greeter that could find ids would learn when any user runs `sudo`, which it has no need to know.
3. **Another program of the same user can disturb a prompt.** Reporting state and closing a prompt are tied to the uid, not to the connection that opened it ([ADR-0014](../adr/0014-agent-bus.md), amendment of 2026-11-16). A program running as the person can therefore close the lock screen's prompt, or report a false state on it. ADR-0014 accepted this because the state "carries no authority", and that still holds: the Agent decides the sign-in itself. But a screen that shows live tiles makes a false state more visible, and closing the prompt ends the attempt.

## Answer

**Yes, with three changes to the Agent's interface, which need an ADR amendment before they are built.** In plain words: the Agent tells a screen when a sign-in starts that the screen is allowed to show, and only the program that started an attempt may change or end it.

1. **A new call and signal.** `WatchPrompts()` registers the calling connection; the Agent then sends it `PromptStarted(s prompt_id, s context)` when `Authenticate` starts a prompt that the caller may read, unicast like every signal. The screen then calls `Subscribe(prompt_id)` as today. Nothing is guessed, and no list of prompts exists to be read.
2. **What a watcher is told.** A prompt host is told only about prompts that root opened with the context `login`, which is the login screen's. It is never told about `sudo`, `unlock` or a text console. The person is told about their own prompts, which covers Linux Hello's part in the lock screen. Nobody else is told anything.
3. **Only the opener may change a prompt.** `ReportState` and `ClosePrompt` are refused (`Denied`) from any connection but the one that opened the prompt. Reading and subscribing stay as they are, so a program of the same user can still follow the person's own prompt, which shows them nothing they could not see on their own screen.
4. **The greeter's user becomes a prompt host** through the Agent's configuration, read from the admin policy directory or the unit; which of the two is left to the ADR amendment.
5. **To be tested in the VM** before the amendment is accepted: under greetd (from Ubuntu 26.04's archive) a greeter running as `_greetd` receives `PromptStarted` for a login and can subscribe; it receives nothing for a `sudo` in another terminal; and on KDE's lock screen a second process of the person cannot close the lock screen's prompt.

What this changes: an amendment to ADR-0014 (the access rules) and to the interface of `io.github.LinuxHello.Agent1`; the Auth Prompt QML module ([#318](https://github.com/LinuxHello/linux-hello/issues/318)) and the greeter ([#319](https://github.com/LinuxHello/linux-hello/issues/319)) use `WatchPrompts`. The PAM module does not change.
