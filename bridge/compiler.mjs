import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
export const REPO_ROOT = path.resolve(__dirname, "..");
export const PROJECT_FILE = path.join(REPO_ROOT, "default.project.json");
export const SYNC_BUNDLE_FILE = path.join(REPO_ROOT, "studio-sync.json");

// Repo này chạy ĐỘC LẬP với repo tham khảo: mọi thông tin GitHub lấy từ chính
// remote origin của checkout, nên không có chỗ nào hard-code owner/repo/nhánh.
export function readRepoCoordinates() {
	let owner = "OWNER";
	let repo = "REPO";
	let branch = "main";
	try {
		const url = execFileSync("git", ["remote", "get-url", "origin"], {
			cwd: REPO_ROOT,
			encoding: "utf8",
		}).trim();
		const m = url.match(/github\.com[:/]+([^/]+)\/([^/\s]+?)(?:\.git)?$/);
		if (m) {
			owner = m[1];
			repo = m[2];
		}
	} catch {
		/* không có origin → giữ mặc định, publish sẽ báo lỗi */
	}
	try {
		const b = execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
			cwd: REPO_ROOT,
			encoding: "utf8",
		}).trim();
		if (b && b !== "HEAD") branch = b;
	} catch {
		/* detached HEAD → giữ main */
	}
	return { owner, repo, branch };
}

const COORDS = readRepoCoordinates();
export const GITHUB_OWNER = COORDS.owner;
export const GITHUB_REPO = COORDS.repo;
// Lấy tại thời điểm gọi, để publish luôn đẩy đúng nhánh đang đứng.
export const GITHUB_BRANCH = COORDS.branch;

const KNOWN_CONTAINER_CLASSES = {
	StarterPlayerScripts: "StarterPlayerScripts",
	StarterCharacterScripts: "StarterCharacterScripts",
};

export function classifyScriptFile(fileName) {
	if (/^init\.server\.luau?$/i.test(fileName)) {
		return { isInit: true, className: "Script", baseName: "init" };
	}
	if (/^init\.client\.luau?$/i.test(fileName)) {
		return { isInit: true, className: "LocalScript", baseName: "init" };
	}
	if (/^init\.luau?$/i.test(fileName)) {
		return { isInit: true, className: "ModuleScript", baseName: "init" };
	}
	let m = fileName.match(/^(.+?)\.server\.luau?$/i);
	if (m) {
		return { isInit: false, className: "Script", baseName: m[1] };
	}
	m = fileName.match(/^(.+?)\.client\.luau?$/i);
	if (m) {
		return { isInit: false, className: "LocalScript", baseName: m[1] };
	}
	m = fileName.match(/^(.+?)\.luau?$/i);
	if (m) {
		return { isInit: false, className: "ModuleScript", baseName: m[1] };
	}
	return null;
}

function compileFsDirectory(absDir, relDir, fileManifest) {
	if (!fs.existsSync(absDir)) {
		return { className: "Folder", managed: true, children: {} };
	}

	const entries = fs
		.readdirSync(absDir, { withFileTypes: true })
		.sort((a, b) => a.name.localeCompare(b.name));

	let nodeClassName = "Folder";
	let nodeSource = undefined;
	let nodeRepoPath = undefined;
	const children = {};

	for (const entry of entries) {
		if (entry.name.startsWith(".")) continue;
		const fullPath = path.join(absDir, entry.name);
		const relPath = path.posix.join(relDir, entry.name);

		if (entry.isDirectory()) {
			children[entry.name] = compileFsDirectory(fullPath, relPath, fileManifest);
		} else if (entry.isFile()) {
			const info = classifyScriptFile(entry.name);
			if (!info) continue;

			const source = fs.readFileSync(fullPath, "utf8");
			fileManifest.push({
				repoPath: relPath,
				className: info.className,
				bytes: Buffer.byteLength(source, "utf8"),
			});

			if (info.isInit) {
				nodeClassName = info.className;
				nodeSource = source;
				nodeRepoPath = relPath;
			} else {
				children[info.baseName] = {
					className: info.className,
					managed: true,
					repoPath: relPath,
					source,
					children: {},
				};
			}
		}
	}

	const result = { className: nodeClassName, managed: true, children };
	if (nodeSource !== undefined) {
		result.source = nodeSource;
		result.repoPath = nodeRepoPath;
	}
	return result;
}

function compileProjectNode(nodeName, spec, depth, fileManifest) {
	if (spec.$path) {
		const relPath = spec.$path.replace(/\\/g, "/");
		const absPath = path.resolve(REPO_ROOT, relPath);
		if (fs.existsSync(absPath) && fs.statSync(absPath).isFile()) {
			const info = classifyScriptFile(path.basename(absPath)) || { className: "ModuleScript" };
			const source = fs.readFileSync(absPath, "utf8");
			fileManifest.push({
				repoPath: relPath,
				className: info.className,
				bytes: Buffer.byteLength(source, "utf8"),
			});
			return {
				className: spec.$className || info.className,
				managed: true,
				repoPath: relPath,
				source,
				properties: spec.$properties || undefined,
				children: {},
			};
		}
		const compiled = compileFsDirectory(absPath, relPath, fileManifest);
		if (spec.$className) compiled.className = spec.$className;
		if (spec.$properties) compiled.properties = spec.$properties;
		return compiled;
	}

	const isService = depth === 1;
	const className =
		spec.$className ||
		(isService ? nodeName : KNOWN_CONTAINER_CLASSES[nodeName] || "Folder");

	const children = {};
	for (const [key, childSpec] of Object.entries(spec)) {
		if (key.startsWith("$")) continue;
		if (childSpec && typeof childSpec === "object") {
			children[key] = compileProjectNode(key, childSpec, depth + 1, fileManifest);
		}
	}

	return {
		className,
		isService,
		managed: false,
		properties: spec.$properties || undefined,
		children,
	};
}

export function loadExistingBundle() {
	if (!fs.existsSync(SYNC_BUNDLE_FILE)) {
		return { version: 0, hash: "", actions: [] };
	}
	try {
		return JSON.parse(fs.readFileSync(SYNC_BUNDLE_FILE, "utf8"));
	} catch {
		return { version: 0, hash: "", actions: [] };
	}
}

/** Tác vụ chỉ được chạy 1 lần trong Studio (plugin nhớ id đã chạy), nên id phải
 *  gắn với nội dung: publish lại cùng action file KHÔNG tạo id mới. */
function makeActionId(code) {
	const digest = crypto.createHash("sha256").update(code).digest("hex").slice(0, 12);
	return `act-${digest}`;
}

export function compileSyncBundle(extraActions = null, options = {}) {
	const keepHistory = options.keepHistory === true;
	const rawProject = JSON.parse(fs.readFileSync(PROJECT_FILE, "utf8"));
	const tree = rawProject.tree || {};
	const fileManifest = [];
	const services = {};

	for (const [key, spec] of Object.entries(tree)) {
		if (key.startsWith("$")) continue;
		if (spec && typeof spec === "object") {
			services[key] = compileProjectNode(key, spec, 1, fileManifest);
		}
	}

	const prev = loadExistingBundle();
	// Mặc định: gói chỉ mang ĐÚNG các tác vụ của lần publish này (replace).
	// Trước đây cộng dồn lịch sử → tác vụ dựng thế giới cũ còn nằm mãi trong gói
	// dù đã bỏ (và chạy lại mỗi khi hash đổi). `keepHistory` để dành khi cần.
	const actions = keepHistory && Array.isArray(prev.actions) ? [...prev.actions] : [];
	const incoming = Array.isArray(extraActions) ? extraActions : extraActions ? [extraActions] : [];
	for (const action of incoming) {
		// id băm từ nội dung: nếu đã có action y hệt thì GIỮ bản cũ (createdAt ổn định),
		// nhờ vậy publish lặp lại không làm đổi hash/version.
		const previous = actions.find((a) => a.id === action.id);
		const deduped = actions.filter((a) => a.id !== action.id);
		deduped.push(previous || action);
		actions.length = 0;
		actions.push(...deduped);
	}
	if (actions.length > 50) {
		actions.splice(0, actions.length - 50);
	}

	const contentHash = crypto
		.createHash("sha256")
		.update(JSON.stringify({ projectName: rawProject.name, services, actions }))
		.digest("hex")
		.slice(0, 16);

	const nextVersion = contentHash === prev.hash ? prev.version || 1 : (prev.version || 0) + 1;

	return {
		version: nextVersion,
		hash: contentHash,
		projectName: rawProject.name || GITHUB_REPO,
		repo: `${GITHUB_OWNER}/${GITHUB_REPO}`,
		branch: GITHUB_BRANCH,
		updatedAt: new Date().toISOString(),
		files: fileManifest,
		services,
		actions,
	};
}

export function makeActionFromFile(actionFile, description) {
	const abs = path.isAbsolute(actionFile) ? actionFile : path.resolve(REPO_ROOT, actionFile);
	if (!fs.existsSync(abs)) {
		throw new Error(`Không tìm thấy action file: ${actionFile}`);
	}
	const code = fs.readFileSync(abs, "utf8");
	return {
		id: makeActionId(code),
		description: description || `Tác vụ từ ${path.relative(REPO_ROOT, abs)}`,
		code,
		createdAt: new Date().toISOString(),
	};
}

export function makeActionFromCode(code, description) {
	return {
		id: makeActionId(code),
		description: description || "Tác vụ trực tiếp",
		code,
		createdAt: new Date().toISOString(),
	};
}

export function buildGitHubCommandBarOneLiner(commitSha = null) {
	if (!commitSha) {
		throw new Error(
			"buildGitHubCommandBarOneLiner cần commit SHA — plugin tải theo SHA để tránh cache CDN cũ."
		);
	}
	const rawUrl = `https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/${commitSha}/plugin/StudioLiveBridge.server.luau`;
	return `local h=game:GetService("HttpService") h.HttpEnabled=true loadstring(h:GetAsync("${rawUrl}",true))()`;
}
