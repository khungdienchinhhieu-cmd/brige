# brige — Tu Tiên (Roblox)

Repo game Roblox **thể loại tu tiên**, chạy độc lập, dùng đường ống đồng bộ
`src/ → studio-sync.json → Studio` (cùng cơ chế với repo tham khảo
`khungdienchinhhieu-cmd/RobloxStudio-connecting`, nhưng không phụ thuộc vào nó).

- Repo: `khungdienchinhhieu-cmd/brige` · **public** (bắt buộc để raw CDN phục vụ `studio-sync.json`)
- Nhánh mặc định `main` · nhánh làm việc `arena/caf04b02-brige`
- **Không cần Rojo / Rokit / CLI Roblox nào.** `default.project.json` chỉ là bản đồ đường dẫn
  → service, do `bridge/compiler.mjs` đọc trực tiếp; Studio chỉ cần `HttpEnabled = true`.

---

## 1. Cơ chế tu luyện (đã làm)

**5 cảnh giới × 9 tầng = 45 tầng**, thanh tiến độ chạy như thanh kinh nghiệm.

| # | Cảnh giới | Tầng | Thời gian mỗi tầng | Cả cảnh giới | Màu thanh |
| --- | --- | --- | --- | --- | --- |
| 1 | Luyện Khí | 1 → 9 | 1.5 → 3.7 phút | 0.4 giờ | xanh lam |
| 2 | Trúc Cơ | 1 → 9 | 4.2 → 10.4 phút | 1.0 giờ | xanh ngọc |
| 3 | Kim Đan | 1 → 9 | 11.8 → 29.1 phút | 2.9 giờ | vàng kim |
| 4 | Nguyên Anh | 1 → 9 | 32.9 → 81.5 phút | 8.1 giờ | tím |
| 5 | Hoá Thần | 1 → 9 | 92.2 → 228.3 phút | 22.7 giờ | đỏ |

Tổng **≈ 31 giờ** tu luyện liên tục (bế quan ×2 → ≈ 16 giờ).

**Độ khó tăng gấp bội — thiết kế theo thời gian, không theo con số khí:**

```
thời gian 1 tầng = 90s × 1.12^(tầng-1) × 2.8^(cảnh-1)
khí cần         = thời gian × tốc độ hấp thụ (15 khí/s, ×2 mỗi cảnh giới)
```

- Trong một cảnh giới: tầng 9 lâu hơn tầng 1 **×2.48** (mỗi tầng ×1.12).
- Chuyển cảnh giới: chậm hơn **×2.8**, và tầng 1 cảnh mới **vẫn khó hơn** tầng 9 cảnh cũ
  (×1.13 — đây là "bức tường"; điều kiện bắt buộc: `2.8 > 1.12⁸ = 2.48`).
- Số khí vì thế vừa tăng theo thời gian vừa tăng theo tốc độ → luôn tăng dần tuyệt đối
  qua cả 45 tầng (đã kiểm tự động).

**Luật chơi hiện tại:** mỗi giây tự hấp thụ linh khí → đầy thanh thì **tự đột phá** lên tầng
kế → hết tầng 9 thì sang cảnh giới mới (thanh reset). Nút **Bế quan** bật ×2 tốc độ.
Hoá Thần tầng 9 = đỉnh, thanh đứng ở 100% và hiện "ĐỈNH PHONG".

Số liệu nằm **toàn bộ** ở `src/shared/CultivationConfig.luau` — sửa 4 hằng số là đổi cân bằng:

| Hằng số | Giá trị | Ý nghĩa |
| --- | --- | --- |
| `StageSeconds` | 90 | giây cho tầng 1 của Luyện Khí |
| `GrowthPerStage` | 1.12 | mỗi tầng chậm hơn 12% |
| `RealmTimeMultiplier` | 2.8 | mỗi cảnh giới chậm hơn ×2.8 (phải > `1.12⁸`) |
| `BaseRate` / `RealmRateMultiplier` | 15 / 2.0 | khí/giây, và tốc độ tăng mỗi cảnh giới |

---

## 2. Cấu trúc

```text
default.project.json            # bản đồ src/ → ReplicatedStorage, ServerScriptService, StarterPlayer
src/
  shared/
    Config.luau                 # tên game, version, màu, tên folder thế giới
    Net.luau                    # tạo/lấy RemoteEvent
    CultivationConfig.luau      # ★ toàn bộ số liệu tu luyện (5 cảnh giới × 9 tầng)
    Cultivation.luau            # ★ logic thuần: tick, đột phá, snapshot (không đụng Instance)
    World/
      BuildKit.luau             # hàm dựng hình dùng chung
      Modules/SectGrounds.luau  # dựng sân tông môn + 5 trụ cảnh giới
  server/
    Main.server.luau            # điểm vào, khởi động hệ tu luyện
    CultivationServer.luau      # giữ state từng người chơi, vòng tick 1s, phát snapshot
  client/
    Init.client.luau            # điểm vào client
    UI/Hud.luau                 # bảng nhỏ tên game / version
    UI/CultivationBar.luau      # ★ thanh tiến độ tu luyện
bridge/
  compiler.mjs                  # đóng gói src/ thành studio-sync.json (hash, version, actions)
  publish.mjs                   # publish: ghi gói, commit, push, in lệnh Command Bar (có --dry-run)
  rebuild_world_action.luau     # tác vụ dựng lại Workspace.BrigeWorld
plugin/StudioLiveBridge.server.luau   # plugin Studio: tải gói theo commit SHA
tools/
  sync_sim/check_bundle.cjs     # kiểm gói sync so với repo (PASS/FAIL)
  cultivation_sim/run.mjs       # ★ mô phỏng & kiểm cân bằng tu luyện, KHÔNG cần Studio
  watch/file_watch.mjs          # theo dõi GitHub bằng gh api
agents/notes/                   # kiến trúc + tiến độ
agents/prompts/                 # prompt cho agent khác
studio-sync.json                # SINH RA bởi publish.mjs (không sửa tay)
.gitignore · .luaurc (strict)
```

---

## 3. Chạy & kiểm (không cần Studio)

```bash
node tools/cultivation_sim/run.mjs          # bảng cân bằng + 12 mục kiểm luật (PASS/FAIL)
node tools/cultivation_sim/run.mjs --full   # in chi tiết cả 45 tầng
node bridge/publish.mjs --dry-run "test"    # xem số file + lệnh Command Bar, không ghi/commit
node bridge/publish.mjs "feat: …"           # publish thật (ghi studio-sync.json, commit, push)
node tools/sync_sim/check_bundle.cjs        # phải in PASS
```

`cultivation_sim` **dịch chính 2 file .luau sang JS rồi chạy logic thật** (không phải bản sao),
nên sửa config sai là bắt được ngay: tầng sau dễ hơn tầng trước, bức tường cảnh giới bị phá,
số lần đột phá sai, tràn số, snapshot thiếu trường cho UI. Vì vậy `CultivationConfig.luau` và
`Cultivation.luau` giữ cú pháp Lua 5.3-compatible (không `if-then-else` biểu thức, không `continue`).

---

## 4. Quy trình đồng bộ Arena → Studio

1. Sửa file trong `src/`.
2. `node bridge/publish.mjs "thông điệp"` → in ra lệnh Command Bar đã gắn commit SHA.
3. Studio → **View → Command Bar** → dán → Enter:

   ```lua
   local h=game:GetService("HttpService") h.HttpEnabled=true
   loadstring(h:GetAsync("https://raw.githubusercontent.com/khungdienchinhhieu-cmd/brige/<SHA>/plugin/StudioLiveBridge.server.luau",true))()
   ```

4. Plugin tải `studio-sync.json` **theo đúng SHA** (không dính cache), ghi Source vào
   `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayer…Client`,
   rồi chạy tác vụ dựng lại `Workspace.BrigeWorld`.
5. Output hiện `[brige Bridge] ✅ Đồng bộ thành công Rojo v…` là xong. Bấm **Play** để test.

---

## 5. Bảng toạ độ (Workspace.BrigeWorld)

| Vật thể | Toạ độ (studs) | Ghi chú |
| --- | --- | --- |
| `GroundFloor` | `(0, -1, 0)` | nền đá 200 × 2 × 200 |
| `MainPlatform` | `(0, 1, 0)` | đài tròn bán kính 46 |
| `Rune*` (24 viên) | vòng bán kính 41 | đại trận phát sáng |
| `MeditationSeat` / `SeatGlow` | `(0, 3.5, 0)` / `(0, 5.2, 0)` | chỗ ngồi tu luyện |
| `RealmTower_1..5` | vòng cung bán kính 22, `z + 8` | 5 trụ cảnh giới, cao dần 18 → 34 |
| `RealmCrystal_1..5` | đỉnh mỗi trụ + 3 | phát sáng đúng màu cảnh giới |
| `Stair_*` | 4 hướng, cách tâm 52/58/64 | bậc dẫn lên đài |
| `GatePillar_*` / `GateBeam` | `(±20, 13, 92)` / `(0, 28, 92)` | cổng tông môn |
| `Baseplate` | `(0, -10, 0)` | 512 × 20 × 512 |

---

## 6. Nội quy an toàn

- Không đưa token / mật khẩu / cookie vào repo (`.gitignore` chặn `.env`).
- Lỗi xác thực git/gh → **dừng**, báo người dùng kết nối lại GitHub.
- Không `git reset --hard`. `publish.mjs` kiểm tra `HEAD == origin/<nhánh>` trước khi commit.
- Không merge/đóng PR khi chưa được yêu cầu.
- Không copy `studio-sync.json`, `.rbxl` hay dữ liệu lớn từ repo tham khảo.
- **Không dùng Rojo/Rokit** — đồng bộ chỉ qua `bridge/publish.mjs`.

## 7. Cơ chế then chốt

- **Ghim SHA**: lệnh Command Bar tải plugin theo commit SHA → không bao giờ nhận bản cũ từ cache.
- **hash + version** để plugin biết phải nạp lại hay không.
- **actions**: plugin chỉ ghi Source; mỗi lần publish đính kèm tác vụ `rebuild_world_action.luau`
  (id = `act-<băm nội dung>`) để dựng lại thế giới đúng một lần.
- **Tách logic khỏi Instance**: `Cultivation.luau` thuần dữ liệu → test được ngoài Roblox.

## 8. Nếu repo bị đổi về private

raw.githubusercontent.com không trả file của repo private. Đổi lại public:
`gh repo edit khungdienchinhhieu-cmd/brige --visibility public` (cần quyền admin;
token dạng GitHub App không đổi được visibility).

## 9. Tiến độ

Xem [`agents/notes/PROGRESS.md`](agents/notes/PROGRESS.md).

- [x] Đường ống đồng bộ (compiler / publish / plugin / check_bundle)
- [x] Cơ chế tu luyện 5 cảnh giới × 9 tầng + thanh tiến độ + bế quan ×2
- [ ] Chốt vòng lặp gameplay: đột phá có tỉ lệ thất bại, linh thạch, công pháp, bí cảnh
- [ ] Lưu tiến độ người chơi (DataStore) — hiện state reset khi rời server
