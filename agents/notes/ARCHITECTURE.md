# Kiến trúc brige — sổ ghi chú

## 1. Ba lớp

| Lớp | Vai trò | Ai ghi |
| --- | --- | --- |
| `src/` | mã Luau thật của game (layout kiểu Rojo, nhưng KHÔNG cần Rojo) | agent / người |
| `bridge/` | đóng gói + publish + tác vụ dựng thế giới | agent |
| `plugin/` | cầu nối trong Studio: tải gói theo SHA, áp vào DataModel | hiếm khi sửa |

## 2. Luồng đồng bộ (một chiều, không có server trung gian)

```
sửa src/
   ↓  node bridge/publish.mjs "msg"
bridge/compiler.mjs  ── đọc default.project.json + src/*.luau
   ↓
studio-sync.json  { version, hash, files[], services{source…}, actions[] }
   ↓  git commit + push (nhánh làm việc)
GitHub raw (theo commit SHA)
   ↓  Command Bar loadstring(plugin)
plugin/StudioLiveBridge.server.luau
   ↓  reconcileNode() ghi Source vào Script/LuaSourceContainer
Studio DataModel
   ↓  runQueuedActions()
bridge/rebuild_world_action.luau → dựng lại folder Workspace.BrigeWorld
```

## 3. Vì sao phải có "actions"

Plugin chỉ **ghi Source**. Nếu module dựng map đã chạy ở lần sync trước, script mới
được nạp nhưng map vẫn y cũ. Vì vậy mỗi lần publish đều đính kèm một action dựng lại
thế giới; plugin nhớ `id` đã chạy (ServerStorage attribute) nên mỗi action chỉ chạy 1 lần.

`id = act-<sha256(code)[0..12]>` → **idempotent**: cùng nội dung ⇒ cùng id ⇒ không dựng lại
vô ích; nội dung đổi ⇒ id đổi ⇒ dựng lại.

## 4. Quy ước tên file → class Roblox (compiler.mjs tự làm, không cần Rojo)

| Tên file | Kết quả |
| --- | --- |
| `Foo.luau` | `ModuleScript` "Foo" |
| `Foo.server.luau` | `Script` "Foo" |
| `Foo.client.luau` | `LocalScript` "Foo" |
| `init.luau` / `init.server.luau` / `init.client.luau` | chính folder đó thành script |

## 5. Bản đồ dịch vụ (từ `default.project.json`)

| Đường dẫn repo | Roblox |
| --- | --- |
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |

## 6. Khác biệt so với repo tham khảo

- owner/repo/nhánh đọc từ `git remote` + `git branch` thay vì hard-code.
- `publish.mjs` có `--dry-run`, kiểm tra `HEAD == origin/<nhánh>` trước khi commit.
- Action id băm nội dung (repo gốc dùng `Date.now()` → mỗi lần publish chạy lại vô ích).
- `check_bundle.cjs` kiểm tra thêm repo/nhánh trong gói + plugin trỏ đúng repo.
- Không copy `studio-sync.json`, `.rbxl`, ảnh review hay dữ liệu lớn từ repo gốc.
- **Không dùng Rojo/Rokit**: `default.project.json` được `compiler.mjs` đọc trực tiếp, plugin tự dựng Instance.
