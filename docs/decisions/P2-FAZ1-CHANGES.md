# P2 Faz 1 — Path Refactor (DONE)

## Kararlar (kullanıcı onayı: 12 Jun 2026)
- Karar 1-B: Env override + auto-detect fallback (`DEV_STUDIO_REPO_ROOT`)
- Karar 2-A: `.tmux-bootstrap/` gitignore + 6 generated dosyayı sil
- Karar 3-C: systemd dosyaları `.tmpl` placeholder → Faz 3'te render
- Karar 4: `agent-doctor.sh` hardcoded mesajı `$SCRIPT_DIR`'a bağla

## Değiştirilen dosyalar (5 edit)

| # | Dosya | Değişiklik |
|---|---|---|
| 1 | `scripts/dev-studio-start.sh` | Satır 24-27: `REPO_ROOT` env override + auto-detect; `HEARTBEAT_DIR` da env override |
| 2 | `scripts/agent-doctor.sh` | Satır 226: hardcoded path → `${SCRIPT_DIR}` |
| 3 | `scripts/install/dev-studio-install-systemd.sh` | Satır 22-23: `REPO_ROOT` auto-detect; satır 45-50: `.tmpl` un-rendered detection + anlamlı hata |
| 4 | `.gitignore.faz1-fragment` | YENİ — Faz 5 testinde mevcut .gitignore'a merge edilecek |
| 5 | `scripts/.tmux-bootstrap/` | **SİLİNDİ** (6 dosya — runtime'da üretiliyor) |

## .tmpl'e dönüştürülen dosyalar (4 dosya, Faz 3'te render edilecek)

| Orjinal | Yeni isim | Placeholder'lar |
|---|---|---|
| `scripts/install/systemd/dev-studio-watcher@.service` | `.tmpl` | `{{REPO_ROOT}}`, `{{GITHUB_OWNER}}`, `{{GITHUB_REPO}}` |
| `scripts/install/systemd/dev-studio-watcher-reload.service` | `.tmpl` | `{{GITHUB_OWNER}}`, `{{GITHUB_REPO}}` |
| `scripts/install/systemd/dev-studio-watcher-reload.path` | `.tmpl` | `{{REPO_ROOT}}`, `{{GITHUB_OWNER}}`, `{{GITHUB_REPO}}` |
| `systemd/dev-studio-health.service` | `.tmpl` | `{{REPO_ROOT}}` |

## Doğrulamalar (self-review)
- ✅ Hardcoded `atilcan65` / `/opt/dev-studio/atilprojects` referansı: **0 (Faz 1 skopu)**
- ✅ Bash syntax: `dev-studio-start.sh`, `agent-doctor.sh`, `install-systemd.sh` → OK
- ✅ Auto-detect: REPO_ROOT script konumundan doğru tespit edildi
- ✅ Env override: `DEV_STUDIO_REPO_ROOT` set edildiğinde override çalıştı
- ✅ Generated `.tmux-bootstrap/` silindi

## Faz 1'de DOKUNULMAYAN dosyalar (Faz 2 skopu)
- `CODEOWNERS`
- `ISSUE_TEMPLATE/config.yml`
- `agents/orchestrator.md`
- `commands/standup.md`
- `commands/sprint-start.md`

## Faz 3'e devredilen iş
Bakınız `FAZ3-TODO-systemd-render.md`:
- `dev-studio-init.sh` 4 `.tmpl` dosyasını render edecek
- Render output `.gitignore`'a eklenecek
- Init script idempotent olmalı

## Faz 1'in TEST EDİLMEMİŞ kısmı
**Faz 5'te test edilecek:**
- `dev-studio-start.sh` farklı bir konumda gerçek tmux session açabiliyor mu?
- `install-systemd.sh` un-rendered durumda anlamlı hata verip duruyor mu?
- `.tmux-bootstrap/` runtime'da hala doğru üretiliyor mu?
