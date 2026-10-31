#!/usr/bin/env node
/**
 * publish.mjs — đóng gói src/ thành studio-sync.json, commit, push, in lệnh Command Bar.
 *
 *   node bridge/publish.mjs "feat: thêm HUD"
 *   node bridge/publish.mjs --dry-run "test"     # KHÔNG ghi file, KHÔNG commit, KHÔNG push
 *   node bridge/publish.mjs --no-action "chore: chỉ sync script"
 *   node bridge/publish.mjs --action-file bridge/rebuild_world_action.luau --action-desc "Dựng thế giới"
 *
 * An toàn:
 *   • --dry-run chỉ đọc, in ra số file + lệnh Command Bar (dùng để nghiệm thu).
 *   • Trước khi commit: kiểm tra HEAD khớp origin/<nhánh> (không đè việc người khác).
 *   • Không bao giờ `git reset --hard`, không ghi token vào repo.
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import {
	REPO_ROOT,
	SYNC_BUNDLE_FILE,
	GITHUB_BRANCH,
	GITHUB_OWNER,
	GITHUB_REPO,
	compileSyncBundle,
	makeActionFromFile,
	makeActionFromCode,
	buildGitHubCommandBarOneLiner,
} from "./compiler.mjs";

// Tác vụ mặc định: CHỈ preview UI trong edit mode.
// Không dựng map nữa (yêu cầu: "không cần xây gì hết") → publish nhanh, không đụng Workspace.
// Nếu sau này cần dựng thế giới: --action-file bridge/rebuild_world_action.luau
const makeActionIdFor = (code) =>
	`act-${crypto.createHash("sha256").update(code).digest("hex").slice(0, 12)}`;

const PREVIEW_ACTION_FILE = "bridge/preview_cultivation_action.luau";

function parseArgs(argv) {
	let message = "chore: cập nhật đồng bộ Roblox Studio (Rojo + Bridge)";
	let actionDesc = null;
	let actionCode = null;
	let actionFile = null;
	let noAction = false;
	let dryRun = false;
	let noPreview = false;
	let previewRealm = 1;
	let previewStage = 1;
	let previewQi = 55;

	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (arg === "--dry-run") dryRun = true;
		else if (arg === "--no-action") noAction = true;
		else if (arg === "--no-preview") noPreview = true;
		else if (arg === "--realm" && argv[i + 1]) previewRealm = Number(argv[++i]) || 1;
		else if (arg === "--stage" && argv[i + 1]) previewStage = Number(argv[++i]) || 1;
		else if (arg === "--qi" && argv[i + 1]) previewQi = Math.max(1, Math.min(99, Number(argv[++i]) || 55));
		else if (arg === "--action-desc" && argv[i + 1]) actionDesc = argv[++i];
		else if (arg === "--action-code" && argv[i + 1]) actionCode = argv[++i];
		else if (arg === "--action-file" && argv[i + 1]) actionFile = argv[++i];
		else if (arg === "--help" || arg === "-h") {
			console.log(fs.readFileSync(new URL(import.meta.url), "utf8").split("*/")[0]);
			process.exit(0);
		} else if (!arg.startsWith("--")) message = arg;
	}

	const usingDefaults = !actionFile && !actionCode && !noAction;

	const actions = [];
	if (actionCode) actions.push(makeActionFromCode(actionCode, actionDesc));
	else if (actionFile) actions.push(makeActionFromFile(actionFile, actionDesc));

	// Preview UI: tác vụ mặc định duy nhất (trừ khi --no-preview / action tự nhập).
	if (usingDefaults && !noPreview) {
		actions.push(
			makeActionFromFile(PREVIEW_ACTION_FILE, "Preview thanh tu luyện trong edit mode")
		);
	}

	return { message, actions, dryRun, previewRealm, previewStage, previewQi };
}

/**
 * Nhúng state tu luyện thật vào action preview: publish.mjs đọc Cultivation.luau +
 * CultivationConfig.luau (cùng bộ dịch với tools/cultivation_sim) rồi thay 2 dòng marker
 * trong bridge/preview_cultivation_action.luau.
 * Nhờ vậy bấm "Tầng sau 20 lần" không cần làm, chỉ cần publish là xem đúng cảnh giới.
 */
async function withPreviewSnapshot(action, realm, stage, qiPercent) {
	if (!action || !String(action.code).includes("PREVIEW_SNAPSHOT")) return action;
	try {
		const { loadCultivation } = await import("../tools/cultivation_sim/luau_loader.mjs");
		const { Cultivation, CultivationConfig } = loadCultivation();
		const state = Cultivation.newState(realm, stage);
		state.qi = Cultivation.requirement(state) * (qiPercent / 100);
		const snapshot = Cultivation.snapshot(state);
		// PHẢI là cú pháp bảng Lua (key = value), không phải JSON: code này được
		// loadstring() trong Studio nên {"realm":1} sẽ là lỗi cú pháp.
		const fields = [
			["realm", snapshot.realm],
			["stage", snapshot.stage],
			["qi", snapshot.qi],
			["required", snapshot.required],
			["progress", Number(snapshot.progress.toFixed(4))],
		];
		const literal = `{ ${fields.map(([k, v]) => `${k} = ${v}`).join(", ")} }`;
		const code = String(action.code)
			.replace('local PREVIEW_MODEL = "loop"', 'local PREVIEW_MODEL = "snap"')
			.replace("local PREVIEW_SNAPSHOT = nil", `local PREVIEW_SNAPSHOT = ${literal}`);
		return { ...action, code, id: makeActionIdFor(code) };
	} catch (err) {
		console.warn(`⚠️  Không nhúng được state preview: ${err.message}`);
		return action;
	}
}

function git(args) {
	return execFileSync("git", args, { cwd: REPO_ROOT, encoding: "utf8" }).trim();
}

/** Remote SHA của nhánh (null nếu nhánh chưa có trên origin). */
function remoteBranchSha(branch) {
	const out = git(["ls-remote", "--heads", "origin", branch]);
	const line = out.split("\n").find((l) => l.trim().endsWith(`refs/heads/${branch}`));
	return line ? line.split("\t")[0].trim() : null;
}

/** HEAD phải khớp origin/<nhánh> trước khi commit (chặn push đè việc người khác). */
function assertHeadMatchesOrigin() {
	const branch = GITHUB_BRANCH;
	const head = git(["rev-parse", "HEAD"]);

	let remote = null;
	try {
		remote = remoteBranchSha(branch);
	} catch {
		console.warn(`⚠️  Không hỏi được origin (mạng/quyền) — bỏ qua kiểm tra HEAD.`);
		return;
	}

	if (remote === null) {
		console.log(`ℹ️  Nhánh ${branch} chưa có trên origin — lần push này sẽ tạo nhánh mới.`);
		return;
	}
	if (head !== remote) {
		throw new Error(
			`HEAD (${head.slice(0, 7)}) KHÁC origin/${branch} (${remote.slice(0, 7)}). ` +
				`Đồng bộ lại nhánh trước khi publish (git fetch && git status). Không dùng git reset --hard.`
		);
	}
	console.log(`✔ HEAD khớp origin/${branch} (${head.slice(0, 7)})`);
}

async function main() {
	const { message, actions, dryRun, previewRealm, previewStage, previewQi } = parseArgs(
		process.argv.slice(2)
	);

	// Nhúng state tu luyện thật vào action preview (để xem đúng cảnh giới muốn chỉnh)
	for (let i = 0; i < actions.length; i++) {
		actions[i] = await withPreviewSnapshot(actions[i], previewRealm, previewStage, previewQi);
	}

	const bundle = compileSyncBundle(actions);

	console.log(`📦 Repo: ${GITHUB_OWNER}/${GITHUB_REPO} · nhánh ${GITHUB_BRANCH}`);
	console.log(`📁 Số file Rojo: ${bundle.files.length} | Tác vụ: ${bundle.actions.length} | sync v${bundle.version}`);
	for (const f of bundle.files) {
		console.log(`   · ${f.repoPath} [${f.className}] ${f.bytes}B`);
	}
	if (bundle.files.length === 0) {
		throw new Error("Gói sync rỗng — kiểm tra default.project.json và src/.");
	}

	if (actions.length > 0) {
		for (const action of actions) {
			const lines = action.code.split("\n").length;
			console.log(`🏗  Tác vụ: ${action.id} — "${action.description}" (${lines} dòng)`);
		}
	} else {
		console.warn("⚠️  Gói sync KHÔNG có tác vụ nào (--no-action) → Studio chỉ nhận script.");
	}

	if (dryRun) {
		const fakeSha = "DRYRUN";
		console.log("🧪 --dry-run: không ghi studio-sync.json, không commit, không push.");
		console.log(`🔗 Lệnh Command Bar (SHA thật sẽ được in sau khi push):`);
		console.log(buildGitHubCommandBarOneLiner(fakeSha));
		return;
	}

	assertHeadMatchesOrigin();

	const nextBody = JSON.stringify(bundle, null, 2) + "\n";
	const prevBody = fs.existsSync(SYNC_BUNDLE_FILE) ? fs.readFileSync(SYNC_BUNDLE_FILE, "utf8") : null;

	// Chỉ đổi updatedAt khi nội dung đổi → publish lại y nguyên không sinh commit rỗng.
	if (prevBody !== null && JSON.parse(prevBody).hash === bundle.hash) {
		const prev = JSON.parse(prevBody);
		bundle.version = prev.version;
		bundle.updatedAt = prev.updatedAt;
		fs.writeFileSync(SYNC_BUNDLE_FILE, JSON.stringify(bundle, null, 2) + "\n", "utf8");
		console.log(`ℹ️  Gói sync không đổi (hash ${bundle.hash.slice(0, 12)}…, v${bundle.version}).`);

		// Gói không đổi nhưng vẫn có thể có thay đổi ngoài src/ (docs, tools, bridge):
		// commit chúng để repo không bị bẩn, nhưng KHÔNG tăng version.
		git(["add", "-A"]);
		if (git(["status", "--porcelain"])) {
			assertHeadMatchesOrigin();
			git(["commit", "-m", message]);
			git(["push", "-u", "origin", GITHUB_BRANCH]);
			console.log(`✅ Đã commit thay đổi ngoài src/ (${GITHUB_BRANCH} @ ${git(["rev-parse", "HEAD"]).slice(0, 7)})`);
		} else {
			console.log("ℹ️  Không có gì để commit.");
		}
		console.log(`🔗 Lệnh Command Bar:\n${buildGitHubCommandBarOneLiner(git(["rev-parse", "HEAD"]))}`);
		return;
	}

	fs.writeFileSync(SYNC_BUNDLE_FILE, nextBody, "utf8");

	// add -A: mã nguồn, tài liệu và gói sync đi cùng 1 commit → nội dung repo luôn
	// khớp đúng gói mà Studio tải về. File rác đã bị .gitignore chặn.
	git(["add", "-A"]);
	const status = git(["status", "--porcelain"]);
	if (!status) {
		console.log("ℹ️  Không có thay đổi nội dung — studio-sync.json y hệt bản đã commit.");
	} else {
		git(["commit", "-m", message]);
	}
	git(["push", "-u", "origin", GITHUB_BRANCH]);

	const fullSha = git(["rev-parse", "HEAD"]);
	console.log(`✅ Đã đẩy lên GitHub (${GITHUB_BRANCH} @ ${fullSha.slice(0, 7)}) — Sync v${bundle.version}`);
	console.log(`🔗 Lệnh Command Bar:\n${buildGitHubCommandBarOneLiner(fullSha)}`);
}

main().catch((err) => {
	console.error("[Publish Error]", err.message);
	process.exit(1);
});
