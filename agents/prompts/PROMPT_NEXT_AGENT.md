# Prompt cho agent tiếp theo (dán nguyên khối)

Bạn làm việc trong repo `khungdienchinhhieu-cmd/brige` (nhánh `arena/caf04b02-brige`),
một repo Roblox độc lập dùng đường ống đồng bộ Arena → GitHub → Studio.

Trước khi làm bất cứ gì, đọc: `README.md`, `agents/notes/ARCHITECTURE.md`, `agents/notes/PROGRESS.md`.

Quy tắc bắt buộc:

1. Chỉ sửa mã Luau trong `src/` (và tác vụ trong `bridge/rebuild_world_action.luau` khi cần dựng hình).
   Không sửa `plugin/StudioLiveBridge.server.luau` trừ khi được yêu cầu rõ.
2. Sau khi sửa: `node bridge/publish.mjs --dry-run "test"` để xem số file, rồi
   `node bridge/publish.mjs "<thông điệp tiếng Việt>"`, rồi `node tools/sync_sim/check_bundle.cjs`
   — phải in PASS.
3. Không đưa token/mật khẩu/cookie vào repo. Không `git reset --hard`. Không merge/đóng PR khi chưa được yêu cầu.
4. Mỗi lần publish phải kèm tác vụ dựng lại thế giới (mặc định đã có) — nếu không, Studio nhận
   script mới nhưng map không đổi.
5. Cập nhật `agents/notes/PROGRESS.md` sau mỗi mốc.
6. Viết code Luau theo `.luaurc` (strict), dùng `Config`/`Net`/`BuildKit` sẵn có thay vì tạo trùng.
7. Khi thêm module thế giới: đặt ở `src/shared/World/Modules/<Tên>.luau`, export `build(root, kit)`
   (và `FOUNDATION = true` nếu là nền tảng) — `rebuild_world_action.luau` sẽ tự gọi.
