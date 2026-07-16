# Setting up Telegram for a fresh dev-studio project

This guide walks you through wiring up the Telegram notification channel for a brand-new project cloned from this template. It takes about 5 minutes once you have a Telegram account.

> **Sister-pattern**: this doc supersedes the legacy Turkish `docs/TELEGRAM-SETUP.md` (kept for historical reference). Sprint 30+ consolidation TD candidate — both docs coexist until the legacy file is deprecated.

---

## §1 Overview

`dev-studio` agents wake each other through **dual-channel notifications** (per **ADR-0033**): every cross-agent ping tries (a) a Telegram message first, then (b) a tmux pane wake as fallback. The Telegram channel is the "out-of-band" path — it works even when no agent tmux pane is open (laptop asleep, CI runner, fresh SSH session). The tmux channel is the "in-band" path — instant injection into the running agent's terminal. Together they ensure no peer agent ever misses a handoff. This doc explains how to provision the Telegram side; the tmux side is wired automatically by `scripts/dev-studio-start.sh` on first run.

---

## §2 Prerequisites

Before you start, make sure you have:

1. **A Telegram account** — sign up at https://telegram.org if you don't already have one.
2. **A target chat (group or DM)** — where you want agent notifications to land. Can be a solo DM to yourself, or a shared group with your team. The chat must exist BEFORE you create the bot, otherwise you won't have a `chat_id` to point the bot at.
3. **BotFather access** — open https://t.me/BotFather in Telegram. This is Telegram's official bot for creating new bots. You'll send `/newbot` to it.
4. **~5 minutes** — the whole flow is 4 steps.

You do NOT need a server, a phone number, or any paid service. Telegram's Bot API is free for low-volume use (well above what `dev-studio` agents generate).

---

## §3 Quickstart

Four steps, ~5 minutes total:

### Step 1 — Create your bot

1. Open https://t.me/BotFather in Telegram.
2. Send `/newbot`.
3. BotFather asks for a **display name** (e.g., `Dev Studio Notifier`). This shows up in chat headers.
4. BotFather asks for a **username** (e.g., `mydevstudio_bot`). Must end in `bot` and be globally unique.
5. BotFather replies with an HTTP API token like `1234567890:ABCdefGHIjklMNOpqrSTUvwxYZ`. **Treat this token as a secret** — anyone with it can send messages as your bot.

### Step 2 — Get your chat_id

The bot needs to know which chat to post in. To find your chat_id:

1. Open the chat you want notifications in (your DM with the bot, or the group you added the bot to).
2. Send any message — `/start` works fine.
3. In a browser, open:
   ```
   https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
   ```
   (replace `<YOUR_TOKEN>` with the token from Step 1).
4. The JSON response has `"chat":{"id":12345678,...}` (positive number for users/DMs) or `"chat":{"id":-1001234567890,...}` (negative number for groups). Copy that `id` value.

### Step 3 — Run the install-env helper

From the project root (after `git clone` + `scripts/dev-studio-init.sh`):

```bash
bash scripts/install/dev-studio-install-env.sh \
    --telegram-bot-token "1234567890:ABCdefGHIjklMNOpqrSTUvwxYZ" \
    --telegram-chat-id "12345678"
```

The helper writes `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` to `~/.dev-studio-env` AND to all 5 instance env files (`~/.config/dev-studio/instances/<project>--{orchestrator,product-manager,architect,developer,tester}.env`). All files are chmod 600 (owner-read-only). The helper is idempotent — re-running with the same values is a no-op.

> **Why the helper, not manual edit?** Manual `.env` editing requires touching 6 files in lockstep, gets the systemd `EnvironmentFile=` KEY=VALUE form wrong (no `export` prefix in instance files), and forgets the chmod. The helper does all of this atomically. Sister: see **Issue #100** for the helper's design rationale.

### Step 4 — Verify

```bash
bash scripts/notify.sh -l info "verify"
```

You should see a Telegram message land in your target chat within ~1 second, and the command should exit 0.

---

## §4 Verification

The end-to-end check after Step 3:

```bash
bash scripts/notify.sh -l info "verify"
```

**Expected output** (stdout + stderr):

```
[info] Telegram OK: chat_id=12345678 message_id=42
[info] tmux-wake: skipped (no -w flag)
```

**Exit code**: `0` (success).

**Telegram side**: a message in your target chat containing the literal text `verify`.

If Telegram fails but the script exits 0, your token is invalid (see §5 row 1). If the script exits 2 and prints `WARN`, Telegram was skipped but the in-band tmux channel fired (acceptable, but means Telegram itself isn't healthy).

**Optional follow-up**: peer-wake a specific agent to verify the dual-channel end-to-end:

```bash
bash scripts/peer-poke.sh developer "[manual test] hi from Telegram setup"
```

You should see the message land in Telegram AND get injected into the developer's tmux pane (if open).

---

## §5 Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `notify.sh` exits 2 with `ERROR: Telegram API rejected token` | Token is wrong, revoked, or has a typo | Re-check token with `curl https://api.telegram.org/bot<TOKEN>/getMe` — should return JSON with `ok:true`. If `ok:false`, regenerate via `/revoke` in BotFather and re-run Step 3. |
| `notify.sh` exits 2 with `ERROR: chat not found` | `chat_id` is wrong, or bot was never added to the group | For DMs: send `/start` to the bot FIRST, then re-fetch chat_id via `getUpdates`. For groups: add the bot to the group, send any message in the group, then re-fetch chat_id. Negative `chat_id` for groups is normal. |
| `notify.sh` exits 1 with `TELEGRAM_BOT_TOKEN not set` | Helper didn't run, or `~/.dev-studio-env` wasn't sourced | Re-run Step 3. Verify `cat ~/.dev-studio-env` shows both vars. If using a non-interactive tmux session, ensure it sources `~/.dev-studio-env` in `.bashrc`/`.zshrc`. |
| Telegram works but peer tmux pane never wakes | tmux session missing or pane title doesn't match role | Check `tmux ls` — look for a session with panes named `ORCHESTRATOR`, `DEVELOPER`, etc. (uppercase). If using a custom tmux layout, ensure pane titles match `dev-studio-start.sh`'s expected naming. |
| `notify.sh` exits 0 but no Telegram message arrives | Bot was kicked from the group, or chat was archived | Open the chat, send `/start` to the bot to re-add it, then re-run Step 4. For groups: confirm the bot is still a member (group admin can check via group settings → members). |
| Token leaked / compromised | Anyone with the token can send messages as your bot | In BotFather, send `/revoke` and select the bot. Copy the NEW token. Re-run Step 3 with the new token. Old token stops working instantly. |

---

## §6 Cross-references

- **ADR-0033** — dual-channel doctrine (the doctrine this recipe implements)
- **ADR-0014** — project-token-auth (env management reference; explains why we chmod 600)
- **Issue #100** (sister cluster, tmpl side) — `scripts/install/dev-studio-install-env.sh` impl that this recipe invokes
- **Issue #5** (sister cluster, launcher side) — `new-project.sh` arg pass-through; downstream consumer that bakes the env values into freshly-created projects
- **atilcan65/AtilCalculator#1058** — cluster coordination (cross-repo sister per RETRO-023)
- **docs/TELEGRAM-SETUP.md** — legacy Turkish recipe (manual `.env` hand-edit); kept for historical reference, superseded by this doc
- **scripts/notify.sh** — the actual Telegram sender (called by every agent peer-poke)
- **scripts/peer-poke.sh** — the dual-channel wrapper (Telegram first, tmux fallback)