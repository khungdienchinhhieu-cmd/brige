/**
 * luau_check.cjs — biên dịch mọi .luau trong gói sync bằng trình biên dịch Luau THẬT.
 *
 *   node tools/sync_sim/luau_check.cjs
 *
 * Vì sao cần: code action được loadstring() trong Studio. Nếu chỉ là "chuỗi JSON"
 * thay vì bảng Lua, hoặc thiếu `end`, Studio sẽ báo lỗi biên dịch và KHÔNG chạy gì cả
 * — mà trước đây không bài test nào bắt được (đã xảy ra với `{"realm":1}`).
 *
 * Tìm trình biên dịch theo thứ tự: $LUAU_COMPILE → PATH → /home/user/.tools/luau/build.
 * Không tìm thấy thì in SKIP (không tính là lỗi) để CI/máy thiếu tool vẫn chạy được.
 */
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const REPO = path.resolve(__dirname, "..", "..");
const problems = [];
const okAll = [];

function findLuauCompile() {
  const candidates = [
    process.env.LUAU_COMPILE,
    path.join(process.env.HOME || "/root", ".tools/luau/build/luau-compile"),
    "/usr/local/bin/luau-compile",
    "/usr/bin/luau-compile",
  ].filter(Boolean);
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  try {
    return execFileSync("which", ["luau-compile"], { encoding: "utf8" }).trim();
  } catch {
    return null;
  }
}

function check(code, label, compiler, tmpFile) {
  fs.writeFileSync(tmpFile, code, "utf8");
  try {
    execFileSync(compiler, ["--binary", tmpFile], { stdio: "pipe" });
    return true;
  } catch (err) {
    const out = String(err.stderr || err.stdout || err.message).split("\n").slice(0, 3).join("\n     ");
    problems.push(`${label}: lỗi biên dịch Luau\n     ${out}`);
    return false;
  }
}

const compiler = findLuauCompile();
if (!compiler) {
  console.log("⚠️  SKIP — không tìm thấy luau-compile (đặt biến LUAU_COMPILE để chỉ đường dẫn).");
  process.exit(0);
}
console.log(`· dùng ${compiler}`);

const tmpFile = path.join(require("os").tmpdir(), `brige_luau_check_${process.pid}.luau`);

// 1. mọi file nguồn
const sources = [];
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith(".luau")) sources.push(p);
  }
})(path.join(REPO, "src"));
for (const extra of ["bridge/preview_cultivation_action.luau", "bridge/rebuild_world_action.luau", "plugin/StudioLiveBridge.server.luau"]) {
  const p = path.join(REPO, extra);
  if (fs.existsSync(p)) sources.push(p);
}

let okCount = 0;
for (const file of sources) {
  if (check(fs.readFileSync(file, "utf8"), path.relative(REPO, file), compiler, tmpFile)) okCount++;
}
if (okCount === sources.length) okAll.push(`${sources.length} file .luau nguồn biên dịch OK`);

// 2. code của MỌI action trong gói (đây là thứ Studio loadstring)
const bundlePath = path.join(REPO, "studio-sync.json");
if (fs.existsSync(bundlePath)) {
  const bundle = JSON.parse(fs.readFileSync(bundlePath, "utf8"));
  const actions = Array.isArray(bundle.actions) ? bundle.actions : [];
  let actionOk = 0;
  for (const a of actions) {
    if (typeof a.code !== "string") continue;
    if (check(a.code, `action ${a.id}`, compiler, tmpFile)) actionOk++;
    else if (/^\s*local \w+ = \{ *"/.test(a.code) || /"\s*:\s*/.test(a.code.split("\n").find((l) => l.includes("PREVIEW_SNAPSHOT")) || "")) {
      problems.push(`action ${a.id}: snapshot nhúng bằng JSON ("key":value) — phải là bảng Lua (key = value).`);
    }
  }
  if (actionOk === actions.length) okAll.push(`${actions.length} action trong studio-sync.json biên dịch OK`);
} else {
  problems.push("Chưa có studio-sync.json — chạy publish trước.");
}

try {
  fs.unlinkSync(tmpFile);
} catch {}

console.log("");
for (const m of okAll) console.log(`  ✅ ${m}`);
for (const m of problems) console.log(`  ❌ ${m}`);
console.log(problems.length === 0 ? "\nPASS — mọi thứ Studio sẽ loadstring đều biên dịch được." : `\nFAIL — ${problems.length} lỗi.`);
process.exit(problems.length === 0 ? 0 : 1);
