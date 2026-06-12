# P2 Faz 2 — Placeholder Enjeksiyonu (DONE)

## Kararlar (kullanıcı onayı: 12 Jun 2026, 16:08)
- Soru 1-A: Tüm hedef dosyalar `.tmpl` uzantısı alacak, init script render edecek
- Soru 2-A: `{{...}}` Jinja-style sözdizimi (systemd ile tutarlı)
- Soru 3-A: Tek atışta 5 dosya, tek PR

## Değiştirilen 5 dosya

| # | Eski | Yeni | Placeholder'lar |
|---|---|---|---|
| 1 | `CODEOWNERS` | `CODEOWNERS.tmpl` | `{{GITHUB_OWNER}}` (4 satır) |
| 2 | `ISSUE_TEMPLATE/config.yml` | `ISSUE_TEMPLATE/config.yml.tmpl` | `{{GITHUB_OWNER}}`, `{{GITHUB_REPO}}` |
| 3 | `agents/orchestrator.md` | `agents/orchestrator.md.tmpl` | `{{HUMAN_OWNER_NAME}}`, `{{GITHUB_OWNER}}` |
| 4 | `commands/standup.md` | `commands/standup.md.tmpl` | `{{GITHUB_OWNER}}` (2 satır) |
| 5 | `commands/sprint-start.md` | `commands/sprint-start.md.tmpl` | `{{GITHUB_OWNER}}` |

## Yeni placeholder (Faz 1'de yoktu)
- **`{{HUMAN_OWNER_NAME}}`** — kullanıcının insan ismi (örn. "atil can")
  - Init script kaynağı: `git config user.name`

## Render edilecek placeholder'ların tam listesi (Faz 3 için)
| Placeholder | Kaynak komut |
|---|---|
| `{{REPO_ROOT}}` | `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` |
| `{{GITHUB_OWNER}}` | `gh api user --jq .login` |
| `{{GITHUB_REPO}}` | `gh repo view --json name --jq .name` |
| `{{HUMAN_OWNER_NAME}}` | `git config user.name` |

## Render edilecek .tmpl dosyalarının tam listesi (Faz 3 için)

### systemd (Faz 1'den)
- `scripts/install/systemd/dev-studio-watcher@.service.tmpl`
- `scripts/install/systemd/dev-studio-watcher-reload.service.tmpl`
- `scripts/install/systemd/dev-studio-watcher-reload.path.tmpl`
- `systemd/dev-studio-health.service.tmpl`

### Username/URL (Faz 2)
- `CODEOWNERS.tmpl`
- `ISSUE_TEMPLATE/config.yml.tmpl`
- `agents/orchestrator.md.tmpl`
- `commands/standup.md.tmpl`
- `commands/sprint-start.md.tmpl`

**TOPLAM: 9 .tmpl dosyası**

## Doğrulamalar (self-review)
- ✅ Hardcoded `atilcan65` referansı (5 dosya skopu): **0**
- ✅ Tüm placeholder'lar doğru satırlarda
- ✅ Dosya isimleri `.tmpl` uzantısı aldı

## Faz 1'den taşınan + Faz 2'de güncellenen gitignore notu
Render output dosyaları (`.tmpl` olmadan) gitignore'a Faz 3'te eklenmeli.
Önerilen gitignore pattern (Faz 3 için):
```
# Render edilmiş template çıktıları
CODEOWNERS
.github/ISSUE_TEMPLATE/config.yml
.claude/agents/orchestrator.md
.claude/commands/standup.md
.claude/commands/sprint-start.md
scripts/install/systemd/*.service
scripts/install/systemd/*.path
systemd/dev-studio-health.service
# (ama .tmpl'leri commit ediyoruz)
!*.tmpl
```

**DİKKAT:** `.gitignore` Faz 5 testinde dikkatli olunmalı — çünkü mevcut dosyalar (Faz 2 öncesi commit'li) silinmeli ki gitignore çalışsın. Init script'in idempotency'si önemli.
