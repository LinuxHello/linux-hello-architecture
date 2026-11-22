---
type: adr
subject: Every Linux Hello client talks to the Agent over its own bus connection and the PIN socket, and starts no program and no shell
artifact: adr
status: accepted
owner: "@atterdag"
concepts: [dbus, attack-surface, subprocess, cli, plasma, pam, kcm, sddm, lock-screen]
tags: [adr, security, architecture]
sources: ["0014-agent-bus.md", "0021-pin-transport.md", "0023-pam-module-and-login-failure.md", "0024-agent-status-interface.md", "https://github.com/LinuxHello/linux-hello/issues/213"]
date: 2026-11-21
---

# ADR-0026: Clients reach the Agent directly, never through a command

## Status

Accepted, 2026-11-21. The maintainer set the requirement on 2026-11-21; the lead wrote it down, and it was accepted on the maintainer's standing approval of the lead's recommendations. It applies to the login screen, the lock screen, the System Settings page, `linuxhello-ctl` and the PAM module, and to every Linux Hello client that comes later. Amendment accepted 2026-11-22 on the same standing approval: how a part opens the settings page for the person (see *Amendment 2026-11-22*).

## Context

Linux Hello has one service that decides: the Agent. The Agent is a system service, a program that runs for the whole machine, under its own user and confined by an AppArmor profile (kernel rules that limit what a program may touch). Everything a person sees talks to it. Some clients exist today: `linuxhello-ctl` (the command-line tool) and `pam_linuxhello`. The PAM module is the piece that `sudo`, the console login and the lock screen load to check a person; PAM, Pluggable Authentication Modules, is the Linux system that lets those programs ask a module instead of checking passwords themselves. Others are planned: the login screen (SDDM, the display manager KDE uses), the Plasma lock screen, and a page in KDE's System Settings.

The Agent offers two ways in:

- **D-Bus**, the message service that programs on a Linux desktop use to call each other. The Agent's interface is `io.github.LinuxHello.Agent1` on the system bus ([ADR-0014](0014-agent-bus.md)).
- **The PIN socket**, `/run/linuxhello/pin.sock`, which carries the PIN itself, so that a PIN is never a bus message ([ADR-0021](0021-pin-transport.md)).

A client can reach the Agent in two ways. It can open these connections itself, or it can run a program that does, such as `busctl` (systemd's command-line bus tool), and read what that program prints. The second way is easy to write in a script or in QML, the language of Plasma's screens. `linuxhello-ctl status` works that way today: it runs `busctl` to call `GetStatus`, `systemctl` to ask whether the Agent's service runs, and `busctl` again to ask the fingerprint service for a reader.

Running a program for this has three costs:

1. **Speed.** Each call starts a new process, which connects to the bus, authenticates and says hello, and then the client parses text. On a lock screen that happens while the person waits.
2. **Attack surface.** A program is found by its name, through the `PATH` variable and the files on disk. Whoever controls those decides what runs. A program also brings its own code, libraries and environment into a screen that handles a PIN.
3. **A man in the middle.** The answer passes through a second program and through text. A program put in the first one's place can print "nothing is wrong", or a success, and the client believes it. With its own bus connection the client knows whom it talks to: the bus only lets the Agent's user own the Agent's name, and it says which connection sent each message.

| Option | Pros | Cons |
| :-- | :-- | :-- |
| **A. Every client opens its own bus connection and the PIN socket; no client starts a program** | One process; the bus vouches for the peer; no text to parse; nothing found through `PATH` | Each client needs a bus library, or its own small one as the PAM module has ([ADR-0023](0023-pam-module-and-login-failure.md), amendment of 2026-11-21) |
| B. Clients may run `busctl` or `linuxhello-ctl` | Quick to write, above all in QML | All three costs above, on the screens that matter most |
| C. A small helper program that every client runs | One place for the bus code | The same costs as B, plus one more program to confine and keep in step |

## Decision

**Option A.** A Linux Hello client talks to the Agent only over its own connection to the system bus and, for a PIN, over the PIN socket. It starts no program and no shell, and it never reads the Agent's answer from a program's output.

1. **Which programs this covers.** Every client of the Agent: `linuxhello-ctl`, `pam_linuxhello`, the login screen's and the lock screen's Linux Hello parts, the System Settings page, and every one added later. In QML, a call goes through a library that exposes the Agent's interface (Qt's D-Bus classes, or a Rust library made with cxx-qt), never through a process-running element.
2. **No process at all.** A client never starts another program. In Rust, `std::process::Command` does not appear in a client crate outside its tests. In C++, `QProcess` and `system()` do not appear, and the same holds for any other way to start one.
3. **Other services too.** When a client needs a fact from another service, it asks that service over the bus in the same way. For example, `linuxhello-ctl doctor` asks systemd (`org.freedesktop.systemd1`) whether the Agent's unit is active, and fprintd (`net.reactivated.Fprint`, the fingerprint service) whether it has a reader. It reads files where a fact is a file, such as the AppArmor profile list.
4. **A missing capability becomes an Agent call.** When a screen needs something the Agent does not offer, the Agent gets a method for it, decided in its own ADR or amendment. Enrolling a fingerprint or a face from System Settings is the first case: the page must not run `fprintd-enroll` or `howdy add`.
5. **Which bus.** The PAM module uses the fixed system-bus socket, never an address from the environment ([ADR-0023](0023-pam-module-and-login-failure.md), amendment of 2026-11-21, point 1), because `sudo` keeps the invoking user's environment. A client that runs as the person themself, such as `linuxhello-ctl` or a screen in their session, may use the standard system-bus address. Whoever could change that environment is the same person.
6. **What is not covered.** The Agent itself still starts Howdy's compare script, a fixed program with a fixed command line and an empty environment, until Howdy gets a helper service of its own (linux-hello#272). The install and test scripts in `scripts/` are not clients. Tests may start programs, such as a private `dbus-daemon`.
7. **How it is checked.** Each client crate has a test that reads its own sources and fails on a way to start a program outside test code. The tests are `the_cli_starts_no_program` in `linuxhello-ctl` and `the_pam_module_starts_no_program` in `pam_linuxhello`. A Plasma part gets the same test when it is created.

### Amendment 2026-11-22 (accepted): opening the settings page for the person

A small part in the person's session will show a desktop notification such as "Your PIN expires in 5 days", with a button that opens Linux Hello's page in System Settings ([#324](https://github.com/LinuxHello/linux-hello/issues/324)). Opening that page means that a program, System Settings, starts. Point 2 says a client never starts another program, so this amendment says how the button may do it.

In plain words: the part asks the desktop, over the bus, to open the page, and the desktop starts System Settings as it would for a click in the menu. The part itself starts nothing and reads nothing back.

1. **Allowed:** one bus call to a service of the desktop that opens an application or an address for the person. Examples are the desktop portal's `org.freedesktop.portal.OpenURI` (xdg-desktop-portal, the service through which sandboxed apps open links) and the D-Bus activation of System Settings itself (`org.freedesktop.Application.Activate` on its well-known name). Which one works on Plasma 6.6 and 6.8 is checked when the part is built.
2. **Not allowed:** starting `systemsettings`, `kcmshell6` or anything else from the part, also not through a library that runs the program in the part's own process (KDE's `KIO::ApplicationLauncherJob` does that), and not through a shell.
3. **Why the difference.** The three costs of the context come from a program that the client starts and whose output it trusts. Here the desktop starts a program it already knows by its desktop file, the part does not choose a path, and nothing the program prints comes back to the part. The notification carries no secret and decides nothing.
4. **The check of point 7** applies to the part: its sources contain no way to start a program.

## Consequences

**Easier:**

- A screen's answer comes from the Agent and nowhere else. Review is simpler: one connection, typed values, no text to parse.
- Each screen saves a process start per call.
- The fuzz target that read `busctl`'s text output goes away with the parser.

**Harder:**

- Every client carries bus code. QML parts need a small C++ or Rust library to reach the Agent; that library is part of the `plasma` container and is confined and reviewed with it.
- Features that a command already offers must be built as Agent calls first. Enrolment is the first, and it needs its own decision.
- `linuxhello-ctl doctor` must know systemd's and fprintd's bus interfaces instead of their commands. Both are stable interfaces that `systemctl` and `fprintd-list` themselves use.
