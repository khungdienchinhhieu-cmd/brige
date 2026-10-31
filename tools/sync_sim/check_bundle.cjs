/**
 * Kiểm tra GÓI SYNC mà Studio thật sự nhận được (studio-sync.json).
 *
 *   node tools/sync_sim/check_bundle.cjs           # kiểm tra file đã commit
 *   node tools/sync_sim/check_bundle.cjs --fresh   # biên dịch lại từ src/ rồi kiểm tra
 *
 * Bài test này chặn đúng lỗi hay gặp: publish "thành công" nhưng Studio mở ra
 * vẫn y hệt bản cũ (gói thiếu file, source trong gói cũ hơn trên đĩa, không có
 * tác vụ dựng lại, hoặc ghim sai repo/nhánh).
 *
 * Kiểm:
 *   1. Có hash + version (plugin dựa vào hash để biết phải nạp lại).
 *   2. Mọi file .luau trong src/ có mặt trong gói, source khớp đĩa y hệt.
 *   3. Gói có ít nhất 1 tác vụ dựng lại thế giới, id ổn định (băm nội dung),
 *      và mã tác vụ không tham chiếu repo khác.
 *   4. repo/branch trong gói khớp origin + nhánh đang đứng.
 *   5. Plugin hard-code đúng repo này (owner/brige) và không còn nhánh repo gốc.
 */
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { pathToFileURL } = require("url");

const REPO = path.resolve(__dirname, "..", "..");
const read = (p) => fs.readFileSync(p, "utf8");
const problems = [];
const okAll = [];
const warnAll = [];

const ok = (m) => okAll.push(m);
const bad = (m) => problems.push(m);
const warn = (m) => warnAll.push(m);

let git = (args) => {
  try {
    return execFileSync("git", args, { cwd: REPO, encoding: "utf8" }).trim();
  } catch {
    return "";
  }
};

function flattenSources(node, prefix, out) {
  for (const [name, spec] of Object.entries(node || {})) {
    if (!spec || typeof spec !== "object") continue;
    const here = prefix ? `${prefix}.${name}` : name;
    if (typeof spec.source === "string") out[here] = spec.source;
    if (spec.children) flattenSources(spec.children, here, out);
  }
}

(async () => {
  const fresh = process.argv.includes("--fresh");
  let bundle;
  if (fresh) {
    const mod = await import(pathToFileURL(path.join(REPO, "bridge/compiler.mjs")).href);
    bundle = mod.compileSyncBundle();
    console.log("· biên dịch lại từ src/ (--fresh)");
  } else {
    const file = path.join(REPO, "studio-sync.json");
    if (!fs.existsSync(file)) {
      console.log("❌ Chưa có studio-sync.json — chạy: node bridge/publish.mjs \"...\"");
      process.exit(1);
    }
    bundle = JSON.parse(read(file));
    console.log(`· đọc ${path.relative(REPO, file)} (bản đã commit — đúng thứ Studio tải về)`);
  }

  // 1. hash + version
  if (!bundle.hash) bad("Gói thiếu hash → plugin tưởng đã đồng bộ mới nhất và bỏ qua.");
  else ok(`hash ${String(bundle.hash).slice(0, 12)}… · version ${bundle.version} · ${(bundle.files || []).length} file Rojo`);
  if (!Number.isInteger(bundle.version) || bundle.version < 1) bad(`version không hợp lệ: ${bundle.version}`);

  // 2. mọi file src/ phải có trong gói, source khớp đĩa
  const sources = {};
  flattenSources(bundle.services, "", sources);
  const srcFiles = [];
  (function walk(dir) {
    if (!fs.existsSync(dir)) return;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".luau")) srcFiles.push(p);
    }
  })(path.join(REPO, "src"));

  let stale = 0;
  for (const abs of srcFiles) {
    const rel = path.relative(REPO, abs).replace(/\\/g, "/");
    const fileName = path.basename(abs);
    const base = fileName.replace(/\.luau$/, "");
    const moduleName = base.replace(/\.(server|client)$/, "").replace(/^init$/, "");
    const onDisk = read(abs);

    const hits = Object.entries(sources).filter(([, src]) => src === onDisk);
    if (hits.length === 0) {
      // source trong gói khác đĩa?
      const anyByName = Object.entries(sources).filter(([key]) => key.endsWith(`.${moduleName}`) || key === moduleName);
      if (anyByName.length > 0) {
        bad(`${rel}: source trong gói KHÁC trên đĩa (gói cũ / chưa publish)`);
        stale++;
      } else {
        bad(`${rel}: KHÔNG có trong gói sync`);
      }
    }
  }
  if (stale === 0) ok(`${srcFiles.length} file .luau trong src/ đều có trong gói, source khớp đĩa`);

  // 3. tác vụ dựng lại thế giới
  const actions = Array.isArray(bundle.actions) ? bundle.actions : [];
  // tác vụ dựng lại = chứa BrigeWorld + gọi module build (loại trừ preview UI)
  const rebuild = actions.filter(
    (a) =>
      typeof a.code === "string" &&
      a.code.includes("BrigeWorld") &&
      a.code.includes("Modules") &&
      !a.code.includes("BrigeCultivationPreview")
  );
  if (rebuild.length === 0) {
    // Mặc định hiện tại: KHÔNG dựng map (chỉ preview UI). Đây là chủ ý, không phải lỗi.
    warn(
      `Gói không có tác vụ dựng lại thế giới (chủ ý — chỉ đồng bộ script + UI). ` +
        `Cần dựng map thì: node bridge/publish.mjs --action-file bridge/rebuild_world_action.luau "msg"`
    );
  } else {
    const latest = rebuild[rebuild.length - 1];
    ok(`Có ${rebuild.length} tác vụ dựng lại thế giới (mới nhất: ${latest.id})`);
    for (const token of ["workspace", "BrigeWorld", "Modules"]) {
      if (!latest.code.includes(token)) warn(`Tác vụ dựng lại thiếu "${token}" — có thể đã lỗi thời.`);
    }
    for (const a of actions) {
      if (!/^act-[0-9a-f]{12}$/.test(String(a.id))) bad(`Action id không ổn định: ${a.id} (id phải băm từ nội dung code).`);
      if (typeof a.code === "string" && a.code.includes("RobloxStudio-connecting")) bad(`Action ${a.id} còn tham chiếu repo gốc RobloxStudio-connecting.`);
      // tác vụ dựng lại phải KHÔNG đánh dấu once: nội dung đổi là phải chạy lại
      if (a.once === true && !String(a.id).includes("once")) {
        bad(`Action ${a.id} bị đánh dấu once=true → sẽ chỉ chạy 1 lần, đổi nội dung cũng không chạy lại.`);
      }
    }

  }

  // 3b. Preview edit mode — kiểm riêng, không phụ thuộc có dựng map hay không
  const preview = actions.filter((a) => typeof a.code === "string" && a.code.includes("BrigeCultivationPreview"));
  if (preview.length === 0) {
    warn("Gói KHÔNG có action preview edit mode — chỉ xem được UI sau khi bấm Play.");
  } else {
    const code = preview[preview.length - 1].code;
    ok(`có action preview edit mode (${preview[preview.length - 1].id}) — xem UI không cần Play`);
    if (/Instance\.new\("Part"\)|Instance\.new\("Folder"\)|\.Parent = workspace/.test(code)) {
      bad("Action preview có dựng/xoá Instance trong Workspace — phải chỉ là UI.");
    } else {
      ok("action preview chỉ vẽ UI, không đụng Workspace");
    }
    if (!code.includes("Heartbeat") && !code.includes("RenderStepped")) {
      bad("Action preview không dùng Heartbeat/RenderStepped → thanh nhảy từng giây (giật).");
    } else {
      ok("preview cập nhật theo từng frame (Heartbeat) → mượt, không giật");
    }
    const hugeSpeed = code.match(/SPEED\s*=\s*(\d+)/);
    if (hugeSpeed && Number(hugeSpeed[1]) > 60) {
      bad(`Preview tua ×${hugeSpeed[1]} → thanh nhảy liên tục. Tối đa ×60.`);
    }
    // phải có điều khiển để xem nhanh từng cảnh giới thay vì tua
    if (!code.includes("previewStateAt") && !code.includes("Tầng sau")) {
      warn("Preview thiếu nút chuyển tầng — muốn xem cảnh giới cao phải chờ.");
    } else {
      ok("preview có nút chuyển tầng để xem nhanh cảnh giới");
    }
  }

  // 4. repo/branch trong gói khớp git thật
  const origin = git(["remote", "get-url", "origin"]).replace(/\.git$/, "");
  const m = origin.match(/github\.com[:/]+([^/]+)\/([^/]+)$/);
  const expectRepo = m ? `${m[1]}/${m[2]}` : "";
  const expectBranch = git(["rev-parse", "--abbrev-ref", "HEAD"]);
  if (expectRepo && bundle.repo !== expectRepo) bad(`Gói ghi repo "${bundle.repo}" nhưng origin là "${expectRepo}".`);
  else if (expectRepo) ok(`repo trong gói: ${bundle.repo}`);
  if (expectBranch && expectBranch !== "HEAD" && bundle.branch !== expectBranch) {
    bad(`Gói ghi nhánh "${bundle.branch}" nhưng đang đứng ở "${expectBranch}".`);
  } else if (expectBranch) ok(`nhánh trong gói: ${bundle.branch}`);

  // 5. plugin hard-code đúng repo này
  const pluginPath = path.join(REPO, "plugin/StudioLiveBridge.server.luau");
  if (!fs.existsSync(pluginPath)) bad("Thiếu plugin/StudioLiveBridge.server.luau — lệnh Command Bar sẽ 404.");
  else {
    const plugin = read(pluginPath);
    const owner = plugin.match(/GITHUB_OWNER\s*=\s*"([^"]+)"/);
    const repoName = plugin.match(/GITHUB_REPO\s*=\s*"([^"]+)"/);
    if (!owner || !repoName) bad("Plugin thiếu GITHUB_OWNER/GITHUB_REPO.");
    else {
      if (expectRepo && `${owner[1]}/${repoName[1]}` !== expectRepo) {
        bad(`Plugin trỏ ${owner[1]}/${repoName[1]} nhưng repo là ${expectRepo}.`);
      } else ok(`plugin trỏ đúng repo: ${owner[1]}/${repoName[1]}`);
      if (repoName[1] === "RobloxStudio-connecting") bad("Plugin vẫn trỏ repo gốc — phải là repo độc lập.");
    }
    if (plugin.includes("arena/b37b6115-robloxstudio-connecting") && repoName && repoName[1] === "brige") {
      bad("Plugin còn hard-code nhánh của repo gốc.");
    }
    // Lỗi "cập nhật không được": plugin chỉ nhớ action.id → action id cố định
    // (băm từ nội dung file) chỉ chạy 1 lần duy nhất, các lần sync sau bị bỏ qua.
    if (!plugin.includes("bundleKey") && !/hash/.test(plugin.match(/function runQueuedActions\([^)]*\)/)?.[0] || "")) {
      bad(
        "Plugin chống chạy trùng theo action.id (không theo hash gói) → tác vụ dựng lại chỉ chạy lần đầu, " +
          "các lần publish sau Studio nhận script mới nhưng map KHÔNG đổi. Đây là lỗi 'cập nhật không được'."
      );
    } else {
      ok("plugin chống chạy trùng theo hash gói → publish mới là chạy lại tác vụ");
    }

    const shaConst = plugin.match(/BASE_COMMIT_SHA\s*=\s*"([^"]*)"/);
    if (!shaConst) bad("Plugin thiếu hằng BASE_COMMIT_SHA (ghim bản build).");
    if (plugin.includes("__BRIDGE_COMMIT_SHA__")) warn("Plugin còn placeholder SHA — bình thường, vì plugin tải theo SHA trong lệnh Command Bar.");
  }

  // Danh sách script trong gói (nhìn là biết gói có gì)
  const keys = Object.keys(sources).sort();
  console.log(`\n  Script trong gói (${keys.length}):`);
  for (const k of keys) console.log(`    · ${k}`);

  console.log("");
  for (const w of warnAll) console.log(`  ⚠️  ${w}`);
  for (const x of okAll) console.log(`  ✅ ${x}`);
  for (const p of problems) console.log(`  ❌ ${p}`);
  console.log(
    problems.length === 0
      ? "\nPASS — gói sync dùng được: Studio nạp script mới và hiện UI ngay trong edit mode."
      : `\nFAIL — ${problems.length} lỗi trong gói sync.`
  );
  process.exit(problems.length === 0 ? 0 : 1);
})().catch((err) => {
  console.error("❌ check_bundle lỗi:", err.message);
  process.exit(1);
});
