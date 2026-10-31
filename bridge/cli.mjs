#!/usr/bin/env node
import { loadExistingBundle, buildGitHubCommandBarOneLiner, GITHUB_OWNER, GITHUB_REPO, GITHUB_BRANCH } from "./compiler.mjs";

const bundle = loadExistingBundle();
let commandBarOneLiner = null;
try {
	commandBarOneLiner = buildGitHubCommandBarOneLiner(process.argv[2] || null);
} catch {
	commandBarOneLiner = "(cần commit SHA — chạy sau khi publish)";
}
console.log(
	JSON.stringify(
		{
			repo: `${GITHUB_OWNER}/${GITHUB_REPO}`,
			branch: GITHUB_BRANCH,
			syncVersion: bundle.version,
			hash: bundle.hash,
			files: bundle.files || [],
			actionsCount: (bundle.actions || []).length,
			commandBarOneLiner,
		},
		null,
		2
	)
);
