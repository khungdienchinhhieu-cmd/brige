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

// Tác vụ dựng lại thế giới (mặc định kèm mỗi lần publish, giống repo gốc).
const REBUILD_ACTION_FILE = "bridge/rebuild_world_action.luau";

function parseArgs(argv) {
	let message = "chore: cập nhật đồng bộ Roblox Studio (Rojo + Bridge)";
	let actionDesc = null;
	let actionCode = null;
	let actionFile = null;
	let noAction = false;
	let dryRun = false;

	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (arg === "--dry-run") dryRun = true;
		else if (arg === "--no-action") noAction = true;
		else if (arg === "--action-desc" && argv[i + 1]) actionDesc = argv[++i];
		else if (arg === "--action-code" && argv[i + 1]) actionCode = argv[++i];
		else if (arg === "--action-file" && argv[i + 1]) actionFile = argv[++i];
		else if (arg === "--help" || arg === "-h") {
			console.log(fs.readFileSync(new URL(import.meta.url), "utf8").split("*/")[0]);
			process.exit(0);
		} else if (!arg.startsWith("--")) message = arg;
	}

	// MẶC ĐỊNH: luôn kèm tác vụ dựng lại thế giới, trừ khi người dùng chỉ định
	// action khác hoặc --no-action.
	if (!actionFile && !actionCode && !noAction) {
		actionFile = REBUILD_ACTION_FILE;
		actionDesc = actionDesc || "Dựng lại thế giới brige (tăng dần theo mã băm từng module)";
	}

	let extraAction = null;
	if (actionCode) extraAction = makeActionFromCode(actionCode, actionDesc);
	else if (actionFile) extraAction = makeActionFromFile(actionFile, actionDesc);

	return { message, extraAction, dryRun };
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
	const { message, extraAction, dryRun } = parseArgs(process.argv.slice(2));
	const bundle = compileSyncBundle(extraAction);

	console.log(`📦 Repo: ${GITHUB_OWNER}/${GITHUB_REPO} · nhánh ${GITHUB_BRANCH}`);
	console.log(`📁 Số file Rojo: ${bundle.files.length} | Tác vụ: ${bundle.actions.length} | sync v${bundle.version}`);
	for (const f of bundle.files) {
		console.log(`   · ${f.repoPath} [${f.className}] ${f.bytes}B`);
	}
	if (bundle.files.length === 0) {
		throw new Error("Gói sync rỗng — kiểm tra default.project.json và src/.");
	}

	if (extraAction) {
		const lines = extraAction.code.split("\n").length;
		console.log(`🏗  Tác vụ: ${extraAction.id} — "${extraAction.description}" (${lines} dòng)`);
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
		const committedSha = git(["rev-parse", "HEAD"]);
		bundle.version = JSON.parse(prevBody).version;
		bundle.updatedAt = JSON.parse(prevBody).updatedAt;
		fs.writeFileSync(SYNC_BUNDLE_FILE, JSON.stringify(bundle, null, 2) + "\n", "utf8");
		console.log(
			`ℹ️  Nội dung không đổi (hash ${bundle.hash.slice(0, 12)}…) — không tạo commit mới.`
		);
		console.log(`🔗 Lệnh Command Bar (commit hiện tại):\n${buildGitHubCommandBarOneLiner(committedSha)}`);
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
