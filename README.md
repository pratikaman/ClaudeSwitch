<p align="center">
  <img src="docs/icon.png" width="112" alt="ClaudeSwitch">
</p>

<h1 align="center">ClaudeSwitch</h1>

<p align="center">
  <b>One Mac. Several Claude Code accounts. No idea which one still has juice.</b>
</p>

<p align="center">
  A macOS menu bar app that answers the only question that actually matters at 2am:<br>
  <i>which of my accounts can I still use?</i>
</p>

---

## The problem

You have a personal Claude account. And a work one. And that third one you made
"just to test something" four months ago. They live in different config folders,
and you switch between them with hand-rolled shell aliases you named while
sleep-deprived.

Six months later nobody remembers which is which, and nobody finds out an
account is out of weekly limit until Claude announces it mid-thought.

## What it does

- Lists every account, who it's signed in as, and what plan it's on
- Shows **how much rate limit is left** on each one
- Puts the account with the most headroom at the top, with one big button
- Launches it in a terminal — or just hit ⌘1, ⌘2, ⌘3
- Quietly tells you when two "different" accounts are actually the same account
  sharing one allowance, which is a thing that happens

## What it deliberately does *not* do

This is the important part.

ClaudeSwitch **never edits `~/.claude`** and **never moves keychain entries
around**. Picking an account only sets `CLAUDE_CONFIG_DIR` for the single
terminal window it opens. Delete the app right now and every account still works
exactly as before.

There is no "switching", only "opening a terminal with the right environment
variable" — same outcome, dramatically harder to get catastrophically wrong.

## Install

```sh
git clone https://github.com/pratikaman/ClaudeSwitch.git
cd ClaudeSwitch
./build.sh --install     # builds, then copies to ~/Applications
```

macOS 14+. No Xcode project, no dependencies, no package manager — just `swiftc`
over a dozen Swift files. It's ad-hoc signed, so macOS will be suspicious the
first time: right-click the app → **Open** → Open.

### Or make an agent do it

You already have one open. Paste this into Claude Code, Codex, Cursor, Gemini
CLI, Copilot CLI, Aider — whichever is nearest:

> Clone https://github.com/pratikaman/ClaudeSwitch somewhere sensible, run
> `./build.sh --install`, and open `~/Applications/ClaudeSwitch.app`.
> It's a macOS menu bar app: no Dock icon, no window on launch — look in the
> menu bar for a small pixel creature. Building needs Swift from Xcode or the
> Command Line Tools (`xcode-select --install`). It's ad-hoc signed, so if
> Gatekeeper refuses, right-click the app in Finder and choose Open. When it's
> running, tell me which Claude accounts it found and how much limit each has
> left.

Pleasingly recursive: you can spend one Claude account's quota installing the
thing that tells you which Claude account still has quota.

## Where things live

| Path | What |
|---|---|
| `~/Library/Application Support/ClaudeSwitch/config.json` | preferences and per-account overrides |
| `~/Library/Application Support/ClaudeSwitch/usage-cache.json` | last known rate-limit numbers |
| `~/Library/Application Support/ClaudeSwitch/launch/*.command` | generated launch scripts, rewritten each launch |

Access tokens are read from the keychain only to make a single usage request.
They're never cached, written to disk, or logged. The app has no logging at all.

---

MIT. Built on a Mac, for a Mac, by someone with too many Claude accounts.
