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

## Mốc 2 — bỏ Rojo, chỉ dùng studio-sync CDN

- [x] **Quyết định**: không dùng Rojo. `default.project.json` chỉ là bản đồ đường dẫn → service,
      `bridge/compiler.mjs` tự đọc và plugin tự dựng Instance. Không cần Rokit/rojo binary.
- [x] Đã xoá `rokit.toml`, `tools/rojo/serve.mjs`, `tools/rojo/setup.sh`.
- [x] `.luaurc` giữ alias `shared` → `src/shared` cho Luau LSP (không liên quan Rojo).
- [ ] Đổi repo sang public: **bị chặn** — token hiện tại là GitHub App integration, API trả
      `403 Resource not accessible by integration`. Cần người dùng chạy `gh repo edit --visibility public`
      trên máy có quyền, hoặc Settings → General → Danger Zone → Change visibility.

## Mốc 3 — cơ chế tu luyện (thể loại tu tiên)

- [x] **5 cảnh giới × 9 tầng** = 45 tầng: Luyện Khí → Trúc Cơ → Kim Đan → Nguyên Anh → Hoá Thần.
- [x] Thiết kế **theo thời gian**: `90s × 1.12^(tầng-1) × 2.8^(cảnh-1)` → tổng ≈ 31 giờ
      (bế quan ×2 ≈ 16 giờ). Điều kiện bức tường: `RealmTimeMultiplier > GrowthPerStage^8`.
- [x] `CultivationConfig.luau` (số liệu) + `Cultivation.luau` (logic thuần, test được ngoài Roblox).
- [x] `CultivationServer.luau`: state theo người chơi, tick 1s, tự đột phá, remote
      `CultivationState` (S→C) và `CultivationAction` (C→S: `secluded` / `request`).
- [x] `UI/CultivationBar.luau`: thanh kiểu EXP, đổi màu theo cảnh giới, vệt sáng chạy,
      hiệu ứng đột phá, nút Bế quan ×2, hiện "ĐỈNH PHONG" ở mốc cuối.
- [x] `World/Modules/SectGrounds.luau`: đài tròn + đại trận + 5 trụ cảnh giới (cao/màu dần) + cổng.
- [x] `tools/cultivation_sim/run.mjs`: dịch 2 file .luau sang JS, mô phỏng đột phá thật → 12 mục PASS.
- [x] Đã xoá `SyncYard.luau` (sân thử cũ).

### Lỗi thiết kế đã bắt được nhờ sim (đáng ghi nhớ)

Bản đầu dùng "mỗi cảnh giới khó ×8" nhưng trong cảnh giới mỗi tầng ×1.35 → `1.35^8 = 11.06 > 8`,
nên **tầng 1 cảnh giới mới lại DỄ hơn tầng 9 cảnh cũ**. Sim phát hiện ngay (2 mục FAIL).
Đã sửa sang thiết kế theo thời gian và thêm kiểm tra ràng buộc này.

### Việc tiếp theo (gợi ý thứ tự)

1. Đột phá cảnh giới có **tỉ lệ thất bại** + vật phẩm hỗ trợ (đan dược) → tạo căng thẳng.
2. Linh thạch / điểm cống hiến: nguồn tăng tốc độ tu luyện.
3. DataStore để giữ tiến độ giữa các phiên.
4. Công pháp (chọn hệ: kiếm / lôi / hoả) đổi `GrowthPerStage` hoặc `BaseRate`.

## Mốc 4 — sửa lỗi "cập nhật không được" + preview edit mode

### Nguyên nhân gốc (quan trọng)

Plugin chống chạy trùng bằng `action.id`. Id tác vụ dựng lại = băm nội dung **file action**
(hiếm khi đổi) → id cố định → **chỉ chạy 1 lần duy nhất**. Các lần publish sau: script mới
được ghi nhưng `Workspace.BrigeWorld` không dựng lại ⇒ nhìn như "sync không ăn".

Sửa: khoá = `<action.id>@<bundle.hash>`; `action.once = true` để ghim chạy-1-lần khi cần.

### Chế độ xem ngay (không cần Start Client)

- [x] Tách thanh UI ra `src/shared/UI/CultivationBarView.luau` → **dùng chung** cho client và preview.
- [x] `bridge/preview_cultivation_action.luau`: dựng thanh trong `CoreGui.BrigeCultivationPreview`,
      tua ×2400, chạy hết 45 tầng trong ~30 giây, có nút tạm dừng / về tầng 1, tự nhường khi Play.
- [x] `publish.mjs` đính kèm 2 tác vụ mặc định (dựng thế giới + preview), có `--no-preview`.
- [x] `check_bundle.cjs` thêm 2 kiểm tra: plugin phải dedupe theo hash gói; gói phải có action preview.

### Bài học

Test cũ chỉ kiểm *nội dung gói*, không kiểm *plugin có chạy tác vụ hay không*. Đã bổ sung.
Lần sau thêm cơ chế mới thì luôn thêm một mục kiểm tra tương ứng vào `check_bundle.cjs`.

## Mốc 5 — UI v2 mượt + bỏ dựng map

### Vì sao thanh "giật tăng liên tục"

Preview bản trước tua **×2400** rồi cộng thêm tween 0.35s tạo mới mỗi frame ⇒ thanh vừa
nhảy liên tục vừa tranh nhau với tween cũ. Sửa:

- Preview chạy **tốc độ thật** (1s = 1s); muốn xem cảnh giới cao thì bấm nút chuyển tầng.
- Thanh cập nhật theo `RunService.Heartbeat` + **nội suy** thay vì tween mỗi lần có dữ liệu.

### Theo yêu cầu "không cần xây gì hết"

- `publish.mjs` mặc định **chỉ** đính kèm tác vụ preview UI; bỏ hẳn tác vụ dựng thế giới.
- `compiler.mjs` đổi sang **replace** semantics: gói chỉ mang tác vụ của lần publish này
  (trước đó cộng dồn lịch sử nên tác vụ dựng map cũ nằm mãi trong gói).
- `SectGrounds.luau` + `rebuild_world_action.luau` giữ lại nhưng không tự chạy.

### Nâng cấp UI v2

- Vạch chia 9 tầng trong thanh · màu theo cảnh giới cho cả viền/nút/chữ.
- Flash + chữ phóng to khi đột phá (mạnh hơn khi sang cảnh giới mới).
- Tự mờ khi không thao tác, rê chuột sáng lại.
- `publish.mjs --realm N --stage M --qi P` → nhúng state thật để xem đúng cảnh giới cần chỉnh.
- `tools/cultivation_sim/luau_loader.mjs` dùng chung cho `run.mjs` và `publish.mjs`.
