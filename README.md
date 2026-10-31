# brige

**brige** là một repo game Roblox **độc lập**, dùng cùng kiểu đồng bộ với repo tham khảo
`khungdienchinhhieu-cmd/RobloxStudio-connecting` nhưng **không phụ thuộc** vào nó:
mọi thông tin repo/nhánh lấy từ chính checkout này.

- Repo: `khungdienchinhhieu-cmd/brige` · **private**
- Nhánh mặc định: `main` · Nhánh làm việc: `arena/caf04b02-brige`
- Thể loại game: **chưa chốt** → hiện tại repo dựng **Sync Yard**, một sân thử để chứng minh
  toàn bộ đường ống `src/ → studio-sync.json → Studio` chạy đúng trước khi chọn hướng game.

## 1. Cấu trúc

```text
default.project.json            # Rojo: map src/ vào ReplicatedStorage, ServerScriptService, StarterPlayer
src/
  client/                       # LocalScript + ModuleScript phía client
    Init.client.luau            # điểm vào client, dựng HUD
    UI/Hud.luau
  server/                       # Script phía server
    Main.server.luau
  shared/                       # ModuleScript dùng chung
    Config.luau
    Net.luau
    World/
      BuildKit.luau             # hàm dựng hình dùng chung
      Modules/SyncYard.luau     # module dựng thế giới mẫu
bridge/
  compiler.mjs                  # đóng gói src/ thành gói đồng bộ (hash, version, actions)
  publish.mjs                   # tăng version, ghi studio-sync.json, commit, push, in lệnh Command Bar
  cli.mjs                       # xem nhanh trạng thái gói đã commit
  rebuild_world_action.luau     # tác vụ dựng lại Workspace.BrigeWorld
plugin/
  StudioLiveBridge.server.luau  # plugin Studio: tải gói theo commit SHA
tools/
  sync_sim/check_bundle.cjs     # kiểm gói so với repo (PASS/FAIL)
  watch/file_watch.mjs          # theo dõi GitHub bằng gh api, ghi cảnh báo
agents/
  notes/                        # kiến trúc + tiến độ
  prompts/                      # prompt cho agent khác
studio-sync.json                # SINH RA bởi publish.mjs (không sửa tay)
.gitignore                      # chặn .rbxl, .rbxlx, .rbxl.lock, sourcemap.json, Packages/
.luaurc                         # strict mode
```

## 2. Chạy thử (không cần Studio)

```bash
node bridge/publish.mjs --dry-run "test"   # in số file + lệnh Command Bar, KHÔNG ghi/commit/push
node bridge/publish.mjs "feat: mốc đầu"    # publish thật: ghi studio-sync.json, commit, push
node tools/sync_sim/check_bundle.cjs       # phải in PASS
node bridge/cli.mjs                        # xem version/hash/số file của gói đã commit
```

Yêu cầu: Node 18+ (đã test Node 22), `git`, `gh` đã đăng nhập.

## 3. Quy trình đồng bộ Arena → Studio

1. Sửa file trong `src/`.
2. `node bridge/publish.mjs "thông điệp"` → script in ra **lệnh Command Bar** đã gắn commit SHA:

   ```lua
   local h=game:GetService("HttpService")
   h.HttpEnabled=true
   loadstring(h:GetAsync("https://raw.githubusercontent.com/khungdienchinhhieu-cmd/brige/<SHA>/plugin/StudioLiveBridge.server.luau",true))()
   ```

3. Mở Roblox Studio → **View → Command Bar** → dán dòng đó → Enter.
4. Plugin tải `studio-sync.json` **theo đúng SHA** (không dính cache CDN), ghi Source vào
   `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client`,
   rồi chạy tác vụ dựng lại `Workspace.BrigeWorld`.
5. Xem cửa sổ Output: `[brige Bridge] ✅ Đồng bộ thành công Rojo v…` là xong.

> **Bắt buộc**: repo đang **private**, nên `HttpEnabled` + raw CDN chỉ đọc được nếu repo
> **public**. Nếu muốn giữ private, xem mục 6 (Cách B).

### Bảng toạ độ / vị trí quan trọng

| Vật thể | Toạ độ (studs) | Ghi chú |
| --- | --- | --- |
| `Workspace.BrigeWorld` | gốc `(0, 0, 0)` | folder do tác vụ dựng lại tạo, xoá-dựng lại mỗi lần hash đổi |
| `YardFloor` | tâm `(0, 0, 0)`, dày 2 | sàn sân thử 240 × 240 |
| `CenterPlinth` | `(0, 2.5, 0)` | bục giữa, biển tên ở `(0, 16, 0)` |
| `Pylon1..4` | `(±114, 12, ±114)` | cột Neon 4 góc |
| Cổng vào | `z = +116` | `GateLeft (-14, 10, 116)`, `GateRight (14, 10, 116)`, `GateBeam (0, 21.5, 116)` |
| `Baseplate` | `(0, -10, 0)` | 512 × 20 × 512 trong `default.project.json` |

## 4. Nội quy an toàn

- Không đưa token / mật khẩu / cookie vào repo (`.gitignore` đã chặn `.env`).
- Lỗi xác thực git/gh → **dừng**, báo người dùng kết nối lại GitHub.
- Không `git reset --hard`. `publish.mjs` kiểm tra `HEAD == origin/<nhánh>` trước khi commit.
- Không merge/đóng PR khi chưa được yêu cầu.
- Không copy `studio-sync.json`, `.rbxl` hay dữ liệu lớn từ repo gốc.

## 5. Cơ chế then chốt

- **Ghim SHA**: lệnh Command Bar tải plugin theo commit SHA → không bao giờ nhận bản cũ từ cache.
- **hash + version** trong `studio-sync.json` để plugin biết phải nạp lại hay không.
- **actions**: plugin chỉ ghi Source, không dựng hình. Mỗi lần publish đính kèm tác vụ
  `rebuild_world_action.luau` (id = `act-<băm nội dung>`) để dựng lại thế giới đúng một lần.
- **strict mode** trong `.luaurc`; mọi module thế giới export `build(root, kit)`.

## 6. Nếu cần giữ repo private

raw.githubusercontent.com **không** trả file của repo private. Hai cách:

- **Cách A (nhanh nhất)**: đổi repo sang public — `gh repo edit --visibility public`.
- **Cách B (giữ private)**: dùng Rojo ở máy local:
  `rojo serve default.project.json` rồi bật plugin Rojo trong Studio (cần cài Rojo).
  Đường ống `studio-sync.json` vẫn dùng được khi repo public.

## 7. Tiến độ

Xem [`agents/notes/PROGRESS.md`](agents/notes/PROGRESS.md). Hiện tại: khung repo + đường ống
đồng bộ hoàn chỉnh, `check_bundle` PASS; **thể loại game chưa chốt**, thế giới đang là sân thử.
