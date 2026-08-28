<img src="docs/icon.png" width="96" align="right" alt="ClaudeSwitch">

# ClaudeSwitch

**One Mac. Several Claude Code accounts. No idea which one still has juice.**

A macOS menu bar app that answers the only question that actually matters at
2am: *which of my accounts can I still use?*

## The problem

You have a personal Claude account. And a work one. And that third one you made
"just to test something" four months ago. They live in different config folders,
and you switch between them using shell aliases you named while sleep-deprived:

```zsh
alias bitch='claude --dangerously-skip-permissions'
alias octopussy='CLAUDE_CONFIG_DIR=~/.claude-side-chick command claude'
alias sidekick='CLAUDE_CONFIG_DIR=~/.claude-sidekick command claude'
```

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

## Four things I learned the hard way

### 1. Your keychain has a secret naming scheme

Claude Code stores each config folder's login under:

```
Claude Code-credentials-<first 8 hex chars of sha256(absolute folder path)>
```

The default `~/.claude` uses the plain, unsuffixed `Claude Code-credentials`.

Which means `CLAUDE_CONFIG_DIR=~/.claude claude` is **not** the same as plain
`claude` — they read different keychain entries. Set that variable "helpfully"
for every profile and you'll cheerfully log someone into a fourth, empty
account. ClaudeSwitch launches the default profile with it explicitly *unset*.

It also means deleting a config folder leaves its login behind forever, still
holding a working refresh token. ClaudeSwitch maps every credential entry back
to its folder and flags the ones with nothing left to belong to. I was quietly
sitting on six of them.

### 2. The rate-limit endpoint will rate limit you for asking about rate limits

`GET https://api.anthropic.com/api/oauth/usage` limits **per account**, and a 429
sticks around for minutes. Two back-to-back refreshes is enough to trip it. So
calls are spaced, results cache to disk, and a throttled account gets a
15-minute timeout instead of being hammered and showing you a blank card.

### 3. `open` hands your entire environment to the child process

If the app is launched from inside a Claude Code session, it inherits that
session's markers and passes them to every terminal it spawns. Not cosmetic:

| Variable | What it quietly breaks |
|---|---|
| `CLAUDE_CODE_CHILD_SESSION` | new session thinks it's a child → **transcript saving turns off** |
| `CLAUDE_CODE_MESSAGING_SOCKET` / `_TOKEN` | points it at the *parent's* IPC socket |
| `CLAUDE_CODE_EXECPATH` | pins it to the parent's CLI version |

The generated launch script unsets all of them before setting anything.
(Bonus: Ghostty on macOS ignores `--working-directory` via `open --args`, so the
script `cd`s for itself.)

### 4. `scope` is an object, not a string

A limit's `scope` field looks like `{"model": {"display_name": "Fable"}}`. Read
it as a string and your beautiful UI proudly displays **"Weekly_Scoped"**.

Worth getting right, because a model-scoped weekly cap can sit *far* above the
overall weekly number — 63% vs 39% on my account. ClaudeSwitch leads with
whichever limit is closest to biting, not the friendliest one.

## Design

Terracotta `rgb(202, 124, 94)` on near-black `#0E1116`. One warm scale, no green
anywhere: brand colour while you're fine, then amber → ember → red as a limit
closes in. Colour only escalates when something deserves your attention.

Flat, not boxy — rows separated by hairlines, surfaces only on hover.

The app icon, menu bar glyph and in-app mark all generate from a single pixel
grid in `tools/mascot.py`. Run it to regenerate every size at once.

## Where things live

| Path | What |
|---|---|
| `~/Library/Application Support/ClaudeSwitch/config.json` | preferences and per-account overrides |
| `~/Library/Application Support/ClaudeSwitch/usage-cache.json` | last known rate-limit numbers |
| `~/Library/Application Support/ClaudeSwitch/launch/*.command` | generated launch scripts, rewritten each launch |

Access tokens are read from the keychain only to make a single usage request.
They're never cached, written to disk, or logged. The app has no logging at all.

## The mascot

He wears glasses. He has three legs. He is doing his best.

---

MIT. Built on a Mac, for a Mac, by someone with too many Claude accounts.
