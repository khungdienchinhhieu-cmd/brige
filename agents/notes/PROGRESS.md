# Tiến độ brige

Cập nhật: 2026-10-31 · nhánh `arena/caf04b02-brige`

## Đã xong

- [x] Repo `khungdienchinhhieu-cmd/brige` (private), nhánh mặc định `main`.
- [x] Dựng khung thư mục: `src/`, `bridge/`, `plugin/`, `tools/`, `agents/`.
- [x] `default.project.json` map `src/shared → ReplicatedStorage.Shared`, `src/server → ServerScriptService.Server`, `src/client → StarterPlayer.StarterPlayerScripts.Client`.
- [x] `bridge/compiler.mjs` (đóng gói, hash, version, action idempotent) + `bridge/publish.mjs` (`--dry-run`, kiểm tra HEAD==origin).
- [x] `plugin/StudioLiveBridge.server.luau` trỏ repo `brige`, mặc định nhánh làm việc.
- [x] `bridge/rebuild_world_action.luau` dựng lại `Workspace.BrigeWorld` theo băm module.
- [x] `tools/sync_sim/check_bundle.cjs` + `tools/watch/file_watch.mjs`.
- [x] Bản mẫu chạy được: Config, Net, BuildKit, SyncYard, server Main, client Init + Hud.

## Việc tiếp theo

- [ ] Chốt thể loại game → thay "Sync Yard" bằng thế giới thật (thêm module vào `src/shared/World/Modules/`).
- [ ] Chốt gameplay loop đầu tiên + chỉ số cân bằng.
- [ ] (tuỳ chọn) Bật Rojo serve trên máy local để xem thay đổi không cần publish.

## Nhật ký

- 2026-10-31 — Khung repo + đường ống sync hoàn chỉnh, `check_bundle` PASS.

## Nghiệm thu (2026-10-31)

| Hạng mục | Lệnh | Kết quả |
| --- | --- | --- |
| Dry-run in đúng số file + lệnh Command Bar | `node bridge/publish.mjs --dry-run "test"` | ✅ 7 file, 1 tác vụ, lệnh gắn SHA |
| Publish thật | `node bridge/publish.mjs "feat: …"` | ✅ Sync v1 @ `6780e89` |
| Kiểm gói | `node tools/sync_sim/check_bundle.cjs` | ✅ PASS (6 mục ok, 0 lỗi) |
| Parse/compile toàn bộ `.luau` | `luau-compile --binary` (Luau chính thức) | ✅ 9/9 file OK |
| Raw URL trong lệnh Command Bar | `curl -sI <raw url>` | ⚠️ 404 vì repo **private** → xem mục 6 README |

Lưu ý private repo: `raw.githubusercontent.com` không phục vụ repo private, nên dòng
Command Bar chỉ chạy khi repo được đổi sang public. Đường ống không có lỗi gì khác.
