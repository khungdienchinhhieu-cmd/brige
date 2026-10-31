#!/usr/bin/env node
/**
 * file_watch.mjs — chạy nền, báo ngay khi một FILE TRÊN GITHUB bị thay đổi.
 *
 *   node tools/watch/file_watch.mjs --path studio-sync.json
 *   node tools/watch/file_watch.mjs --path src/shared/Config.luau --interval 30
 *   node tools/watch/file_watch.mjs --path studio-sync.json --once     # kiểm tra 1 lần rồi thoát
 *
 * Cách hoạt động:
 *   • Hỏi GitHub (qua `gh api`) commit MỚI NHẤT chạm vào file đó trên nhánh đang theo dõi.
 *   • Lần đầu chỉ ghi nhận mốc (baseline), KHÔNG báo.
 *   • Lần sau: commit SHA đổi → ghi cảnh báo + in console + (tuỳ chọn) gửi webhook.
 *   • Trạng thái lưu ở tools/watch/.state/ (đã gitignore), cảnh báo ghi vào ALERTS.log.
 *
 * Mặc định owner/repo/nhánh lấy từ chính checkout này (git remote + git branch),
 * nên repo chạy độc lập, không phụ thuộc repo tham khảo.
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const STATE_DIR = path.join(__dirname, ".state");

function git(args) {
	try {
		return execFileSync("git", args, { cwd: REPO_ROOT, encoding: "utf8" }).trim();
	} catch {
		return "";
	}
}

function detectCoords() {
	const url = git(["remote", "get-url", "origin"]);
	const m = url.replace(/\.git$/, "").match(/github\.com[:/]+([^/]+)\/([^/]+)$/);
	const branch = git(["rev-parse", "--abbrev-ref", "HEAD"]);
	return {
		owner: m ? m[1] : "khungdienchinhhieu-cmd",
		repo: m ? m[2] : "brige",
		branch: branch && branch !== "HEAD" ? branch : "main",
	};
}

const COORDS = detectCoords();

const DEFAULTS = {
	owner: COORDS.owner,
	repo: COORDS.repo,
	branch: COORDS.branch,
	path: "studio-sync.json",
	interval: 60,
	once: false,
	webhook: process.env.WATCH_WEBHOOK_URL || "",
};

function parseArgs(argv) {
	const opt = { ...DEFAULTS };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		const v = () => argv[++i];
		if (a === "--path") opt.path = v();
		else if (a === "--branch") opt.branch = v();
		else if (a === "--interval") opt.interval = Math.max(15, Number(v()) || 60);
		else if (a === "--webhook") opt.webhook = v();
		else if (a === "--owner") opt.owner = v();
		else if (a === "--repo") opt.repo = v();
		else if (a === "--once") opt.once = true;
		else if (a === "--help" || a === "-h") {
			console.log(fs.readFileSync(fileURLToPath(import.meta.url), "utf8").split("*/")[0]);
			process.exit(0);
		} else {
			console.error(`Tham số không hiểu: ${a}`);
			process.exit(2);
		}
	}
	return opt;
}

/** Commit mới nhất chạm vào `filePath` trên `branch`. Trả về null nếu không có. */
function latestCommitFor(opt) {
	const endpoint =
		`repos/${opt.owner}/${opt.repo}/commits` +
		`?sha=${encodeURIComponent(opt.branch)}&path=${encodeURIComponent(opt.path)}&per_page=1`;
	const out = execFileSync("gh", ["api", endpoint], { cwd: REPO_ROOT, encoding: "utf8" });
	const list = JSON.parse(out);
	if (!Array.isArray(list) || list.length === 0) return null;
	const c = list[0];
	return {
		sha: c.sha,
		shortSha: c.sha.slice(0, 7),
		message: String(c.commit?.message || "").split("\n")[0],
		author: c.commit?.author?.name || c.author?.login || "?",
		date: c.commit?.committer?.date || "",
		url: c.html_url || "",
	};
}

function stateFileFor(opt) {
	const safe = `${opt.branch}__${opt.path}`.replace(/[^A-Za-z0-9._-]+/g, "_");
	return path.join(STATE_DIR, `${safe}.json`);
}

function readState(file) {
	try {
		return JSON.parse(fs.readFileSync(file, "utf8"));
	} catch {
		return null;
	}
}

function writeState(file, data) {
	fs.mkdirSync(path.dirname(file), { recursive: true });
	fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n", "utf8");
}

async function postWebhook(url, payload) {
	try {
		const res = await fetch(url, {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ content: payload.text, ...payload }),
		});
		return `HTTP ${res.status}`;
	} catch (err) {
		return `lỗi: ${err.message}`;
	}
}

async function alertChange(opt, prev, now) {
	const stamp = new Date().toISOString();
	const text =
		`🔔 ${opt.path} trên ${opt.branch} ĐÃ THAY ĐỔI — ${String(prev.sha).slice(0, 7)} → ${now.shortSha}\n` +
		`   "${now.message}" — ${now.author} lúc ${now.date}\n   ${now.url}`;
	console.log("\x07" + text);
	fs.mkdirSync(STATE_DIR, { recursive: true });
	fs.appendFileSync(path.join(STATE_DIR, "ALERTS.log"), `[${stamp}] ${text}\n`, "utf8");
	if (opt.webhook) {
		const r = await postWebhook(opt.webhook, {
			event: "file_changed",
			path: opt.path,
			branch: opt.branch,
			from: prev.sha,
			to: now.sha,
			message: now.message,
			url: now.url,
			text,
		});
		console.log(`   webhook: ${r}`);
	}
}

async function checkOnce(opt, stateFile) {
	const now = latestCommitFor(opt);
	const stamp = new Date().toLocaleTimeString("vi-VN");
	if (!now) {
		console.log(`[${stamp}] ${opt.path}: chưa có commit nào trên ${opt.branch} (hoặc sai đường dẫn)`);
		return;
	}
	const prev = readState(stateFile);
	if (!prev || !prev.sha) {
		writeState(stateFile, { ...now, watching: opt.path, branch: opt.branch, baselineAt: stamp });
		console.log(`[${stamp}] ✅ Ghi nhận mốc ${now.shortSha} cho ${opt.path} — sẽ báo khi có commit mới.`);
		return;
	}
	if (prev.sha !== now.sha) {
		await alertChange(opt, prev, now);
		writeState(stateFile, { ...now, watching: opt.path, branch: opt.branch, baselineAt: prev.baselineAt });
		return;
	}
	console.log(`[${stamp}] · không đổi (${now.shortSha})`);
}

async function main() {
	const opt = parseArgs(process.argv.slice(2));
	const stateFile = stateFileFor(opt);
	console.log(
		`👀 Theo dõi ${opt.owner}/${opt.repo} · ${opt.branch} · ${opt.path} · mỗi ${opt.interval}s` +
			(opt.webhook ? " · có webhook" : "")
	);

	if (opt.once) {
		await checkOnce(opt, stateFile);
		return;
	}

	let stopping = false;
	const stop = () => {
		stopping = true;
		console.log("⏹  Dừng theo dõi.");
		process.exit(0);
	};
	process.on("SIGINT", stop);
	process.on("SIGTERM", stop);

	while (!stopping) {
		try {
			await checkOnce(opt, stateFile);
		} catch (err) {
			// Lỗi mạng / hết quota: ghi lại rồi thử lại, không để script chết
			console.log(`[${new Date().toLocaleTimeString("vi-VN")}] ⚠ lỗi kiểm tra: ${String(err.message || err).split("\n")[0]}`);
		}
		await new Promise((r) => setTimeout(r, opt.interval * 1000));
	}
}

main();
