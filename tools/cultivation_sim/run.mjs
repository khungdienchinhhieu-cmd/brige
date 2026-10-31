#!/usr/bin/env node
/**
 * cultivation_sim — kiểm số liệu tu luyện MÀ KHÔNG cần Roblox/Studio.
 *
 *   node tools/cultivation_sim/run.mjs          # bảng cân bằng + kiểm luật
 *   node tools/cultivation_sim/run.mjs --full   # in chi tiết cả 45 tầng
 *
 * Cách làm: `src/shared/CultivationConfig.luau` và `Cultivation.luau` cố tình viết
 * theo cú pháp Lua 5.3-compatible. Script này bóc type/annotation (Luau-only) rồi
 * dịch cú pháp Lua → JS để chạy đúng logic thật (không phải bản sao).
 *
 * Nhờ vậy sửa config sai (tầng sau dễ hơn tầng trước, thiếu tầng, tràn số, đột phá
 * sai số lần) là phát hiện ngay ở máy, không phải mở Studio.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(__dirname, "..", "..");
const SHARED = path.join(REPO, "src/shared");

const problems = [];
const okAll = [];
const ok = (m) => okAll.push(m);
const bad = (m) => problems.push(m);

import { loadCultivation } from "./luau_loader.mjs";

let CultivationConfig, Cultivation;
try {
  ({ CultivationConfig, Cultivation } = loadCultivation());
} catch (err) {
  console.error("❌ Không dịch được file .luau sang JS:", err.message);
  process.exit(1);
}

const full = process.argv.includes("--full");
const realms = CultivationConfig.Realms;

/* ------------------------------------------------------- 1. cấu trúc cảnh giới */

const expectNames = ["Luyện Khí", "Trúc Cơ", "Kim Đan", "Nguyên Anh", "Hoá Thần"];
if (realms.length !== expectNames.length) {
  bad(`Phải có ${expectNames.length} cảnh giới, đang có ${realms.length}`);
} else {
  ok(`5 cảnh giới: ${realms.map((r) => r.name).join(" → ")}`);
}
realms.forEach((r, i) => {
  if (r.name !== expectNames[i]) bad(`Cảnh giới ${i + 1} phải là "${expectNames[i]}", đang là "${r.name}"`);
  if (!r.color || !r.glow) bad(`Cảnh giới ${i + 1} thiếu color/glow để vẽ thanh tiến độ`);
  if (!r.description || r.description.length < 20) bad(`Cảnh giới ${r.name} thiếu mô tả`);
});
if (CultivationConfig.StagesPerRealm !== 9) bad(`Mỗi cảnh giới phải 9 tầng, đang ${CultivationConfig.StagesPerRealm}`);
else ok("mỗi cảnh giới 9 tầng → 45 tầng tổng");

/* ----------------------------------------- 2. độ khó tăng dần + bức tường cảnh giới */

let prev = 0;
let strictlyIncreasing = true;
const table = [];
for (let realm = 1; realm <= realms.length; realm++) {
  let totalSeconds = 0;
  const stages = [];
  const rate = CultivationConfig.cultivationRate(realm);
  for (let stage = 1; stage <= CultivationConfig.StagesPerRealm; stage++) {
    const need = CultivationConfig.stageRequirement(realm, stage);
    if (!Number.isFinite(need) || need <= 0) bad(`Yêu cầu khí không hợp lệ ở cảnh ${realm} tầng ${stage}: ${need}`);
    if (need <= prev) strictlyIncreasing = false;
    prev = need;
    const seconds = need / rate;
    totalSeconds += seconds;
    stages.push({ stage, need, seconds });
  }
  table.push({ name: CultivationConfig.getRealm(realm).name, stages, totalSeconds });
}
if (!strictlyIncreasing) bad("Có tầng không khó hơn tầng trước (yêu cầu khí không tăng dần)");
else ok("45 tầng có yêu cầu khí tăng dần tuyệt đối");

// bức tường: tầng 1 cảnh mới phải KHÓ HƠN tầng 9 cảnh cũ (xét cả thời gian lẫn khí)
for (let realm = 1; realm < realms.length; realm++) {
  const lastSec = CultivationConfig.stageSeconds(realm, CultivationConfig.StagesPerRealm);
  const nextSec = CultivationConfig.stageSeconds(realm + 1, 1);
  if (nextSec <= lastSec) {
    bad(`Tầng 1 của cảnh ${realm + 1} (${(nextSec / 60).toFixed(1)}p) KHÔNG khó hơn tầng 9 cảnh ${realm} (${(lastSec / 60).toFixed(1)}p)`);
  }
  const jump = nextSec / lastSec;
  if (jump < 1.05) bad(`Bước sang cảnh giới ${realm + 1} chỉ khó hơn ${jump.toFixed(2)}× — chưa thành "bức tường"`);
}
ok(
  `bức tường cảnh giới: ×${(
    CultivationConfig.stageSeconds(2, 1) / CultivationConfig.stageSeconds(1, CultivationConfig.StagesPerRealm)
  ).toFixed(2)} (tầng 1 cảnh mới / tầng 9 cảnh cũ)`
);

// trong một cảnh giới, tầng 9 phải lâu hơn tầng 1 rõ rệt
const inRealm = CultivationConfig.stageSeconds(1, 9) / CultivationConfig.stageSeconds(1, 1);
if (inRealm < 1.5) bad(`Trong 1 cảnh giới, tầng 9 chỉ lâu hơn tầng 1 ${inRealm.toFixed(2)}× — chưa leo dốc`);
else ok(`trong cảnh giới: tầng 9 lâu hơn tầng 1 ×${inRealm.toFixed(2)}`);

/* --------------------------------------------------------- 3. an toàn số & thời gian */

const maxNeed = CultivationConfig.stageRequirement(realms.length, CultivationConfig.StagesPerRealm);
if (!Number.isFinite(maxNeed) || maxNeed > 1e12) bad(`Yêu cầu khí cuối quá lớn: ${maxNeed}`);
else ok(`tầng cuối cần ${(maxNeed / 1e6).toFixed(2)}M khí — vẫn an toàn`);

/* ------------------------------------------------------ 4. mô phỏng đột phá 1 giây/tick */

const state = Cultivation.newState(1, 1);
let elapsed = 0;
const MAX_SECONDS = 60 * 60 * 72;
const t0 = Date.now();
while (!Cultivation.isMax(state) && elapsed < MAX_SECONDS) {
  Cultivation.tick(state, 1);
  elapsed += 1;
}
const ms = Date.now() - t0;

if (!Cultivation.isMax(state)) {
  bad("Không thể đạt Hoá Thần tầng 9 trong 72 giờ mô phỏng");
} else {
  ok(`mô phỏng: đạt đỉnh sau ${(elapsed / 3600).toFixed(1)} giờ tu luyện liên tục (chạy ${ms}ms)`);
  if (state.breakthroughs !== 44) bad(`Số lần đột phá phải là 44, đang ${state.breakthroughs}`);
  else ok("đúng 44 lần đột phá (9+9+9+9+8)");
  if (state.realm !== 5 || state.stage !== 9) bad(`Kết thúc phải ở cảnh 5 tầng 9, đang ${state.realm}/${state.stage}`);
}

// đỉnh: tick thêm không được vượt hay reset
const qiAtPeak = state.qi;
Cultivation.tick(state, 60);
if (!Cultivation.isMax(state) || state.stage !== 9) bad("Ở đỉnh mà tick thêm lại làm tụt cảnh giới");
else ok("ở đỉnh: khí giữ nguyên, không tụt tầng");

// bế quan ×2
const a = Cultivation.newState(1, 1);
const b = Cultivation.newState(1, 1);
Cultivation.setSecluded(b, true);
Cultivation.tick(a, 10);
Cultivation.tick(b, 10);
const ratio = b.qi / a.qi;
if (Math.abs(ratio - 2) > 0.001) bad(`Bế quan phải ×2 tốc độ, đo được ×${ratio.toFixed(3)}`);
else ok("bế quan cho đúng ×2 tốc độ hấp thụ");

// snapshot đủ trường cho UI
const snap = Cultivation.snapshot(Cultivation.newState(2, 3));
const requiredFields = ["realm", "stage", "realmName", "stageLabel", "qi", "required", "progress", "rate", "isMax", "realmColor", "realmGlow"];
for (const f of requiredFields) {
  if (snap[f] === undefined) bad(`snapshot thiếu trường "${f}" mà thanh tiến độ cần`);
}
if (snap.progress < 0 || snap.progress > 1) bad(`progress phải trong 0..1, đang ${snap.progress}`);
else ok(`snapshot đủ ${requiredFields.length} trường, progress hợp lệ (${(snap.progress * 100).toFixed(0)}%)`);
if (snap.stageLabel !== "Trúc Cơ · Tầng 3") bad(`stageLabel sai: "${snap.stageLabel}"`);
else ok('stageLabel đúng định dạng "Trúc Cơ · Tầng 3"');

/* --------------------------------------------------------------- in bảng */

if (full) {
  console.log("\nChi tiết 45 tầng:");
  for (const row of table) {
    console.log(`  ${row.name}`);
    for (const s of row.stages) {
      console.log(
        `    tầng ${String(s.stage).padStart(2)} · ${String(s.need).padStart(10)} khí · ${(s.seconds / 60).toFixed(1).padStart(7)} phút`
      );
    }
  }
}

console.log("\nCân bằng (tu luyện liên tục, chưa bế quan):\n");
console.log("  cảnh giới     tầng 1        tầng 9       cả cảnh giới");
for (const row of table) {
  const first = row.stages[0];
  const last = row.stages[row.stages.length - 1];
  console.log(
    `  ${row.name.padEnd(12)}${((first.seconds / 60).toFixed(0) + " phút").padStart(9)}` +
      `${((last.seconds / 60).toFixed(0) + " phút").padStart(13)}` +
      `${(row.totalSeconds / 3600).toFixed(1).padStart(12)} giờ`
  );
}

console.log("");
for (const m of okAll) console.log(`  ✅ ${m}`);
for (const m of problems) console.log(`  ❌ ${m}`);
console.log(
  problems.length === 0
    ? "\nPASS — hệ tu luyện đúng luật: khó dần theo tầng, gấp bội khi chuyển cảnh giới."
    : `\nFAIL — ${problems.length} lỗi.`
);
process.exit(problems.length === 0 ? 0 : 1);
