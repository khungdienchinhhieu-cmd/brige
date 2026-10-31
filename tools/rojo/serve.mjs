#!/usr/bin/env node
/**
 * serve.mjs — chạy Rojo serve kèm kiểm tra trước khi mở Studio.
 *
 *   node tools/rojo/serve.mjs              # rojo serve (cổng 34872)
 *   node tools/rojo/serve.mjs --port 34873
 *   node tools/rojo/serve.mjs --build      # chỉ build ra brige.rbxl, không serve
 *   node tools/rojo/serve.mjs --check      # chỉ kiểm tra môi trường
 *
 * Vì sao có script này: đường ống studio-sync.json cần repo public + HttpEnabled, còn
 * Rojo serve thì chạy hoàn toàn local. Script kiểm tra: rojo đã cài chưa, default.project.json
 * có hợp lệ không, src/ có script không, rồi mới gọi rojo.
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const PROJECT = path.join(REPO_ROOT, "default.project.json");

const args = process.argv.slice(2);
const onlyCheck = args.includes("--check");
const doBuild = args.includes("--build");
const portIndex = args.indexOf("--port");
const port = portIndex >= 0 ? Number(args[portIndex + 1]) || 34872 : 34872;

function fail(msg, hint) {
	console.error(`❌ ${msg}`);
	if (hint) console.error(`   → ${hint}`);
	process.exit(1);
}

function whichRojo() {
	try {
		const version = execFileSync("rojo", ["--version"], { encoding: "utf8", cwd: REPO_ROOT }).trim();
		return version;
	} catch {
		return null;
	}
}

// 1. môi trường
const rojoVersion = whichRojo();
if (!rojoVersion) {
	fail(
		"Chưa có rojo trong PATH.",
		"Cài: curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash && rokit install"
	);
}
console.log(`✔ rojo ${rojoVersion}`);

// 2. project file
if (!fs.existsSync(PROJECT)) fail("Thiếu default.project.json");
let project;
try {
	project = JSON.parse(fs.readFileSync(PROJECT, "utf8"));
} catch (err) {
	fail(`default.project.json không phải JSON hợp lệ: ${err.message}`);
}
console.log(`✔ project "${project.name}" → ${Object.keys(project.tree).filter((k) => !k.startsWith("$")).join(", ")}`);

// 3. đếm script src/ + kiểm tra $path trỏ đúng thư mục có thật
const srcScripts = [];
(function walk(dir) {
	if (!fs.existsSync(dir)) return;
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) walk(p);
		else if (e.name.endsWith(".luau")) srcScripts.push(path.relative(REPO_ROOT, p));
	}
})(path.join(REPO_ROOT, "src"));
if (srcScripts.length === 0) fail("src/ chưa có file .luau nào");
console.log(`✔ ${srcScripts.length} file .luau trong src/`);

function collectPaths(node, out) {
	for (const [k, v] of Object.entries(node || {})) {
		if (k.startsWith("$")) continue;
		if (!v || typeof v !== "object") continue;
		if (typeof v.$path === "string") out.push(v.$path);
		collectPaths(v, out);
	}
}
const paths = [];
collectPaths(project.tree, paths);
for (const rel of paths) {
	if (!fs.existsSync(path.join(REPO_ROOT, rel))) fail(`$path không tồn tại: ${rel}`);
}
console.log(`✔ tất cả $path tồn tại: ${paths.join(", ")}`);

console.log("");
if (onlyCheck) {
	console.log("✅ Môi trường sẵn sàng cho `rojo serve`.");
	process.exit(0);
}

// 4. chạy
const rojoArgs = doBuild
	? ["build", "default.project.json", "--output", "brige.rbxl"]
	: ["serve", "default.project.json", "--address", "0.0.0.0", "--port", String(port)];

console.log(`▶ rojo ${rojoArgs.join(" ")}`);
if (!doBuild) {
	console.log(`
Bước tiếp trong Roblox Studio:
  1. Home → Plugins → bật "Rojo" (nếu chưa có: Studio → Toolbox → Manage Plugins → Rojo, hoặc cài Rojo.rbxm).
  2. Bấm nút Rojo trên toolbar → Connect (localhost:${port}).
  3. Sửa file trong src/ rồi Ctrl+S → Studio cập nhật ngay, không cần publish.
`);
}

const child = spawn("rojo", rojoArgs, { cwd: REPO_ROOT, stdio: "inherit", env: process.env });
child.on("exit", (code) => process.exit(code ?? 0));
for (const sig of ["SIGINT", "SIGTERM"]) {
	process.on(sig, () => child.kill(sig));
}
