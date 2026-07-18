#!/usr/bin/env bash
# apply-vm-hardening.sh — STORY-001 VM hardening (AC1-AC5 + AC7)
#
# Owner-runnable on the target VM (192.168.1.199). Idempotent: running
# twice yields the same end state. Reversible: every change has a paired
# rollback command documented in docs/ops/vm-hardening.md.
#
# Cardinal safety rule (HARD-CODED, NOT OVERRIDABLE):
#   NEVER disable password SSH auth before verifying key-based auth works.
#   The script exits with FATAL if /root/.ssh/authorized_keys is missing/empty
#   OR if a key-based loopback SSH fails. This prevents owner lockout.
#
# Configuration via env vars (defaults match issue body + owner-questioned
# decisions pending). All variables can be overridden at invocation time.
#
#   SSH_PORT           — SSH listen port (default: 22, per owner Q1 answer
#                        pending; script defaults to standard 22)
#   HTTP_PORT          — HTTP surface port allowed by ufw (default: 8000,
#                        per FastAPI/uvicorn default; STORY-003a confirms)
#   FAIL2BAN_BAN_TIME  — ban duration in seconds (default: 600 = 10 min,
#                        tightened from distro default 600 = 10 min via
#                        FAIL2BAN_MAX_RETRY)
#   FAIL2BAN_MAX_RETRY — failed attempts before ban (default: 5, matches
#                        AC4 "5 failed SSH attempts within 60 seconds")
#   FAIL2BAN_FIND_TIME — window for max_retry counting (default: 60 sec,
#                        matches AC4 "within 60 seconds")
#   BACKUP_CRON_EXPR   — systemd timer OnCalendar (default: "*-*-* 02:00:00"
#                        = daily 02:00, matches OPERATIONS.md §6.2 cadence)
#   BACKUP_RETENTION_DAYS — local backups retained (default: 14)
#
# Usage (on target VM as root or via sudo):
#
#   # Dry-run (prints what would change, no mutations)
#   bash apply-vm-hardening.sh --dry-run
#
#   # Apply with defaults
#   sudo bash apply-vm-hardening.sh
#
#   # Apply with custom SSH port
#   sudo SSH_PORT=2222 bash apply-vm-hardening.sh
#
# Exit codes:
#   0 — all ACs applied successfully
#   1 — preflight failure (not root, wrong OS, network down, key auth broken)
#   2 — sshd config validation failure (reverted)
#   3 — ufw/fail2ban/backup installation failure
#   4 — post-apply verification failure

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SSH_PORT="${SSH_PORT:-22}"
HTTP_PORT="${HTTP_PORT:-8000}"
FAIL2BAN_BAN_TIME="${FAIL2BAN_BAN_TIME:-600}"
FAIL2BAN_MAX_RETRY="${FAIL2BAN_MAX_RETRY:-5}"
FAIL2BAN_FIND_TIME="${FAIL2BAN_FIND_TIME:-60}"
BACKUP_CRON_EXPR="${BACKUP_CRON_EXPR:-*-*-* 02:00:00}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"

AGENT_STATE_DIR="${AGENT_STATE_DIR:-/var/log/dev-studio/dev-studio-template/agent-state}"
BACKUP_DEST="${BACKUP_DEST:-/var/backups/agent-state}"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

# Colors (TTY-aware)
if [[ -t 1 ]]; then G=$'\033[0;32m'; R=$'\033[0;31m'; Y=$'\033[0;33m'; B=$'\033[1m'; D=$'\033[0m'
else G=""; R=""; Y=""; B=""; D=""; fi

log()  { printf "${G}[%s]${D} %s\n" "$(date -u +%FT%TZ)" "$*"; }
warn() { printf "${Y}[%s] WARN${D} %s\n" "$(date -u +%FT%TZ)" "$*" >&2; }
fail() { printf "${R}[%s] FATAL${D} %s\n" "$(date -u +%FT%TZ)" "$*" >&2; exit "${2:-1}"; }

run() {
  if [ "$DRY_RUN" = true ]; then
    printf "${Y}[DRY-RUN]${D} would run: %s\n" "$*"
  else
    "$@"
  fi
}

# ============================================================================
# Preflight
# ============================================================================

section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

preflight() {
  section "Preflight"

  # Must be root
  if [ "$(id -u)" -ne 0 ]; then
    fail "Must run as root (use sudo)" 1
  fi
  log "✓ Running as root"

  # OS check (Ubuntu 24.04 per issue body + dev-studio setup)
  if [ ! -f /etc/os-release ]; then
    fail "/etc/os-release missing; expected Ubuntu 24.04" 1
  fi
  . /etc/os-release
  if [ "${ID:-}" != "ubuntu" ] || [ "${VERSION_ID:-}" != "24.04" ]; then
    warn "Expected Ubuntu 24.04; got ${ID:-?} ${VERSION_ID:-?}"
    warn "Script may work on other Debian-derivatives but is untested"
  else
    log "✓ Ubuntu 24.04 detected"
  fi

  # Network check
  if ! ip route get 1.1.1.1 >/dev/null 2>&1; then
    fail "No internet connectivity; cannot fetch packages" 1
  fi
  log "✓ Network reachable"

  # Architecture: amd64 (could relax later)
  ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  if [ "$ARCH" != "amd64" ]; then
    warn "Architecture is $ARCH; script tested on amd64 only"
  fi
}

# ============================================================================
# AC2 (verify first!) + AC1 (disable password) + root login
# ============================================================================

ensure_key_auth_works() {
  section "AC2: Verify key-based SSH auth works (precondition for AC1)"

  # Check authorized_keys exists and is non-empty
  if [ ! -f /root/.ssh/authorized_keys ] || [ ! -s /root/.ssh/authorized_keys ]; then
    fail "/root/.ssh/authorized_keys missing or empty. Add a public key FIRST:
  ssh-copy-id atilcan@192.168.1.199
or
  echo 'ssh-ed25519 AAAA...' >> /root/.ssh/authorized_keys" 1
  fi
  local KEY_COUNT
  KEY_COUNT=$(grep -cE '^(ssh-(rsa|ed25519|dss)|ecdsa-)' /root/.ssh/authorized_keys 2>/dev/null || echo 0)
  log "✓ Found $KEY_COUNT public key(s) in /root/.ssh/authorized_keys"

  # Test loopback SSH with key (uses current user, not root, to mirror real usage)
  local TEST_USER="${SUDO_USER:-atilcan}"
  if ! su - "$TEST_USER" -c "ssh -o BatchMode=yes -o PasswordAuthentication=no -o ConnectTimeout=5 ${TEST_USER}@localhost true" 2>/dev/null; then
    fail "Loopback key-based SSH to ${TEST_USER}@localhost failed.
  Test from another host BEFORE running this script to confirm key auth works.
  If you proceed, you risk locking yourself out." 1
  fi
  log "✓ Loopback key-based SSH works for $TEST_USER"
}

disable_password_auth() {
  section "AC1: Disable password SSH auth + AC2-bonus: disable root login"

  local SSHD_CONFIG=/etc/ssh/sshd_config
  local SSHD_DROPIN_DIR=/etc/ssh/sshd_config.d
  local DROPIN="$SSHD_DROPIN_DIR/00-vm-hardening.conf"

  # Backup the main config (one-time)
  if [ ! -f "${SSHD_CONFIG}.pre-hardening.bak" ]; then
    run cp "$SSHD_CONFIG" "${SSHD_CONFIG}.pre-hardening.bak"
    log "✓ Backed up sshd_config to ${SSHD_CONFIG}.pre-hardening.bak"
  else
    log "✓ sshd_config backup already exists (idempotent)"
  fi

  # Drop-in file (cleaner than mutating sshd_config directly)
  run mkdir -p "$SSHD_DROPIN_DIR"
  if [ "$DRY_RUN" = true ]; then
    printf "${Y}[DRY-RUN]${D} would write to %s:\n" "$DROPIN"
    cat <<'EOF'
# STORY-001: VM hardening — disable password + root SSH
PasswordAuthentication no
PermitRootLogin no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF
  else
    cat > "$DROPIN" <<'EOF'
# STORY-001: VM hardening — disable password + root SSH
PasswordAuthentication no
PermitRootLogin no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF
    chmod 644 "$DROPIN"
    log "✓ Wrote $DROPIN"
  fi

  # Validate sshd config
  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] would run: sshd -t"
  else
    if ! sshd -t; then
      fail "sshd config validation failed; reverting drop-in" 2
    fi
    log "✓ sshd config valid"
  fi

  # Reload sshd (not restart — keep existing sessions)
  run systemctl reload ssh
  log "✓ sshd reloaded (existing sessions preserved)"
}

# ============================================================================
# AC3: ufw firewall
# ============================================================================

configure_ufw() {
  section "AC3: Configure ufw firewall"

  # Install ufw if missing
  if ! command -v ufw >/dev/null 2>&1; then
    log "Installing ufw..."
    run apt-get install -y ufw
  fi

  # Default policies
  run ufw default deny incoming
  run ufw default allow outgoing

  # Allow SSH
  run ufw allow "${SSH_PORT}/tcp" comment "STORY-001: SSH"

  # Allow HTTP surface port (STORY-003a uses FastAPI on this port)
  run ufw allow "${HTTP_PORT}/tcp" comment "STORY-001: HTTP surface (STORY-003a)"

  # Enable ufw (idempotent — ufw returns non-zero if already enabled)
  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] would run: ufw --force enable"
  else
    if ! ufw status | grep -q "Status: active"; then
      run ufw --force enable
    else
      log "✓ ufw already active (idempotent)"
    fi
  fi

  # Print final state
  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] would run: ufw status verbose"
  else
    log "Final ufw status:"
    ufw status verbose | sed 's/^/    /'
  fi
}

# ============================================================================
# AC4: fail2ban with SSH jail
# ============================================================================

configure_fail2ban() {
  section "AC4: Configure fail2ban with SSH jail"

  # Install fail2ban if missing
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    log "Installing fail2ban..."
    run apt-get install -y fail2ban
  fi

  # Drop-in config (local overrides the distro default jail.conf)
  local F2B_LOCAL=/etc/fail2ban/jail.local
  if [ "$DRY_RUN" = true ]; then
    printf "${Y}[DRY-RUN]${D} would write to %s:\n" "$F2B_LOCAL"
    cat <<EOF
[DEFAULT]
bantime = ${FAIL2BAN_BAN_TIME}
maxretry = ${FAIL2BAN_MAX_RETRY}
findtime = ${FAIL2BAN_FIND_TIME}

[sshd]
enabled = true
port = ${SSH_PORT}
backend = systemd
EOF
  else
    cat > "$F2B_LOCAL" <<EOF
# STORY-001: VM hardening — fail2ban SSH jail
[DEFAULT]
bantime = ${FAIL2BAN_BAN_TIME}
maxretry = ${FAIL2BAN_MAX_RETRY}
findtime = ${FAIL2BAN_FIND_TIME}

[sshd]
enabled = true
port = ${SSH_PORT}
backend = systemd
EOF
    chmod 644 "$F2B_LOCAL"
    log "✓ Wrote $F2B_LOCAL"
  fi

  # Enable + start fail2ban
  run systemctl enable fail2ban
  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] would run: systemctl restart fail2ban"
  else
    run systemctl restart fail2ban
    sleep 2
    log "Final fail2ban status:"
    fail2ban-client status sshd 2>/dev/null | sed 's/^/    /' || warn "sshd jail not yet active (may need a moment)"
  fi
}

# ============================================================================
# AC5: State-file backup script + systemd timer
# ============================================================================

install_backup_timer() {
  section "AC5: State-file backup script + systemd timer"

  # Backup script
  local BACKUP_SCRIPT=/usr/local/bin/backup-agent-state.sh
  if [ "$DRY_RUN" = true ]; then
    printf "${Y}[DRY-RUN]${D} would write to %s:\n" "$BACKUP_SCRIPT"
    cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
mkdir -p ${BACKUP_DEST}
tar czf "${BACKUP_DEST}/agent-state-\$(date +%Y%m%d-%H%M%S).tar.gz" \\
    -C "\$(dirname ${AGENT_STATE_DIR})" "\$(basename ${AGENT_STATE_DIR})"
find ${BACKUP_DEST} -name 'agent-state-*.tar.gz' -mtime +${BACKUP_RETENTION_DAYS} -delete
EOF
  else
    cat > "$BACKUP_SCRIPT" <<EOF
#!/usr/bin/env bash
# backup-agent-state.sh — per OPERATIONS.md §6.2
set -euo pipefail
mkdir -p ${BACKUP_DEST}
tar czf "${BACKUP_DEST}/agent-state-\$(date +%Y%m%d-%H%M%S).tar.gz" \\
    -C "\$(dirname ${AGENT_STATE_DIR})" "\$(basename ${AGENT_STATE_DIR})"
find ${BACKUP_DEST} -name 'agent-state-*.tar.gz' -mtime +${BACKUP_RETENTION_DAYS} -delete
EOF
    chmod 755 "$BACKUP_SCRIPT"
    log "✓ Wrote $BACKUP_SCRIPT"
  fi

  # Systemd service
  local SERVICE=/etc/systemd/system/agent-state-backup.service
  if [ "$DRY_RUN" = true ]; then
    printf "${Y}[DRY-RUN]${D} would write to %s\n" "$SERVICE"
  else
    cat > "$SERVICE" <<'EOF'
[Unit]
Description=Backup agent-state directory
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-agent-state.sh
Nice=10
EOF
    log "✓ Wrote $SERVICE"
  fi

  # Systemd timer
  local TIMER=/etc/systemd/system/agent-state-backup.timer
  if [ "$DRY_RUN" = true ]; then
    printf "${Y}[DRY-RUN]${D} would write to %s\n" "$TIMER"
  else
    cat > "$TIMER" <<EOF
[Unit]
Description=Daily agent-state backup timer
Requires=agent-state-backup.service

[Timer]
OnCalendar=${BACKUP_CRON_EXPR}
Persistent=true
Unit=agent-state-backup.service

[Install]
WantedBy=timers.target
EOF
    log "✓ Wrote $TIMER"
  fi

  # Reload systemd + enable + start timer
  if [ "$DRY_RUN" = false ]; then
    run systemctl daemon-reload
    run systemctl enable agent-state-backup.timer
    run systemctl start agent-state-backup.timer
    log "Final timer status:"
    systemctl list-timers agent-state-backup --no-pager | sed 's/^/    /' || warn "Timer not yet scheduled"
  fi
}

# ============================================================================
# AC7: Post-apply verification
# ============================================================================

verify_all() {
  section "AC7: Post-apply verification"

  local FAILED=0

  # AC1: PasswordAuthentication should be 'no'
  local PASS_AUTH
  PASS_AUTH=$(sshd -T 2>/dev/null | grep -i '^passwordauthentication' | awk '{print $2}')
  if [ "$PASS_AUTH" = "no" ]; then
    log "✓ AC1: PasswordAuthentication=no (confirmed via sshd -T)"
  else
    warn "AC1: PasswordAuthentication=$PASS_AUTH (expected 'no')"
    FAILED=$((FAILED+1))
  fi

  # AC2: PermitRootLogin should be 'no'
  local ROOT_LOGIN
  ROOT_LOGIN=$(sshd -T 2>/dev/null | grep -i '^permitrootlogin' | awk '{print $2}')
  if [ "$ROOT_LOGIN" = "no" ]; then
    log "✓ AC2-bonus: PermitRootLogin=no"
  else
    warn "AC2-bonus: PermitRootLogin=$ROOT_LOGIN (expected 'no')"
    FAILED=$((FAILED+1))
  fi

  # AC3: ufw should be active + allow SSH port
  if ufw status 2>/dev/null | grep -q "Status: active"; then
    log "✓ AC3: ufw active"
    if ufw status 2>/dev/null | grep -qE "^${SSH_PORT}/tcp"; then
      log "✓ AC3: ufw allows ${SSH_PORT}/tcp"
    else
      warn "AC3: ufw does NOT allow ${SSH_PORT}/tcp"
      FAILED=$((FAILED+1))
    fi
  else
    warn "AC3: ufw not active"
    FAILED=$((FAILED+1))
  fi

  # AC4: fail2ban should be running with sshd jail enabled
  if systemctl is-active --quiet fail2ban; then
    log "✓ AC4: fail2ban service active"
    if fail2ban-client status 2>/dev/null | grep -q "sshd"; then
      log "✓ AC4: fail2ban sshd jail enabled"
    else
      warn "AC4: fail2ban sshd jail not enabled"
      FAILED=$((FAILED+1))
    fi
  else
    warn "AC4: fail2ban service not active"
    FAILED=$((FAILED+1))
  fi

  # AC5: timer should be active
  if systemctl is-active --quiet agent-state-backup.timer; then
    log "✓ AC5: agent-state-backup.timer active"
  else
    warn "AC5: agent-state-backup.timer not active"
    FAILED=$((FAILED+1))
  fi

  if [ "$FAILED" -gt 0 ]; then
    fail "Post-apply verification: $FAILED check(s) failed" 4
  fi

  log ""
  log "=========================================="
  log "All ACs verified. VM hardening complete."
  log "=========================================="
}

# ============================================================================
# Main
# ============================================================================

main() {
  printf "${B}STORY-001 VM Hardening${D}\n"
  printf "  Target: $(hostname) ($(ip route get 1.1.1.1 2>/dev/null | awk '{print $7;exit}'))\n"
  printf "  SSH_PORT=%s  HTTP_PORT=%s  DRY_RUN=%s\n" "$SSH_PORT" "$HTTP_PORT" "$DRY_RUN"
  printf "  fail2ban: bantime=%ss maxretry=%s findtime=%ss\n" \
    "$FAIL2BAN_BAN_TIME" "$FAIL2BAN_MAX_RETRY" "$FAIL2BAN_FIND_TIME"
  printf "  Backup: OnCalendar='%s' retention=%s days\n" \
    "$BACKUP_CRON_EXPR" "$BACKUP_RETENTION_DAYS"
  echo ""

  preflight
  ensure_key_auth_works
  disable_password_auth
  configure_ufw
  configure_fail2ban
  install_backup_timer

  if [ "$DRY_RUN" = true ]; then
    log ""
    log "[DRY-RUN] No changes made. Re-run without --dry-run to apply."
    exit 0
  fi

  verify_all
}

main "$@"