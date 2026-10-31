/**
 * luau_loader.mjs — dịch 2 file .luau thuần dữ liệu sang JS để chạy ngoài Roblox.
 *
 * Dùng bởi:
 *   • tools/cultivation_sim/run.mjs   → kiểm cân bằng
 *   • bridge/publish.mjs              → lấy snapshot thật nhúng vào action preview
 *
 * `src/shared/CultivationConfig.luau` và `src/shared/Cultivation.luau` cố tình viết theo
 * cú pháp Lua 5.3-compatible (không if-then-else biểu thức, không continue) để bộ dịch
 * đơn giản này xử lý được. Thêm logic vào 2 file đó thì giữ đúng luật ấy.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const REPO = path.resolve(__dirname, "..", "..");
export const SHARED = path.join(REPO, "src/shared");

const fmt = (template, ...args) => {
  let i = 0;
  return String(template).replace(/%[sdq%.0-9-]*[a-z]/g, (token) => {
    const value = args[i++];
    if (token.endsWith("d")) return String(Math.floor(Number(value)));
    if (token.endsWith("q")) return JSON.stringify(String(value));
    return String(value);
  });
};

const L = { clamp: (v, lo, hi) => Math.min(Math.max(v, lo), hi) };

class Color3 {
  constructor(r, g, b) {
    this.R = r;
    this.G = g;
    this.B = b;
  }
  static fromRGB(r, g, b) {
    return new Color3(r / 255, g / 255, b / 255);
  }
}

/** Bóc type annotation + cú pháp Luau không có trong Lua 5.3. */
function stripLuau(src) {
  let out = src;
  out = out.replace(/--\[\[[\s\S]*?\]\]/g, "");
  out = out.replace(/^export type[\s\S]*?^}/gm, "");
  out = out.replace(/^export type.*$/gm, "");
  out = out.replace(/--(?!\[\[)[^\n]*/g, "");

  // function A.b(x: T): R  →  A.b = function (x) {
  out = out.replace(
    /^(\s*)(?:local\s+)?function\s+([\w.]+)\s*\(([^)]*)\)\s*(?::[^{\n]*)?$/gm,
    (m, indent, name, params) => {
      const clean = params
        .split(",")
        .map((p) => p.split(":")[0].trim())
        .filter(Boolean)
        .join(", ");
      return `${indent}${name} = function (${clean}) {`;
    }
  );
  out = out.replace(/^(\s*local\s+)(\w+)\s*:\s*[^=\n]+=/gm, "$1$2 =");
  out = out.replace(/:\s*\{[^{}]*\}\s*(?=\=)/g, " ");
  return out;
}

/** Dịch cú pháp Lua 5.3 → JS (chỉ phần 2 file này dùng). */
function luaToJs(src) {
  let out = src;

  out = out.replace(/\blocal\s+function\b/g, "function");
  out = out.replace(/\blocal\s+(\w+)\s*=/g, "const $1 =");
  out = out.replace(/\blocal\s+(\w+)\b/g, "const $1");

  out = out.replace(/\bif\s+(.+?)\s+then\b/g, "if ($1) {");
  out = out.replace(/\belseif\s+(.+?)\s+then\b/g, "} else if ($1) {");
  out = out.replace(/\belse\b/g, "} else {");
  out = out.replace(/\bend\b/g, "}");
  out = out.replace(/\bwhile\s+(.+?)\s+do\b/g, "while ($1) {");
  out = out.replace(
    /\bfor\s+(\w+)\s*=\s*(.+?),\s*(.+?),\s*(.+?)\s+do\b/g,
    "for (let $1 = $2; $1 <= $3; $1 += $4) {"
  );
  out = out.replace(/\bfor\s+(\w+)\s*=\s*(.+?),\s*(.+?)\s+do\b/g, "for (let $1 = $2; $1 <= $3; $1 += 1) {");

  out = out.replace(/~=/g, "!==");
  out = out.replace(/\bnot\b/g, "!");
  out = out.replace(/\bnil\b/g, "null");
  out = out.replace(/\band\b/g, "&&");
  out = out.replace(/\bor\b/g, "||");
  out = out.replace(/#([\w.]+)/g, "$1.length");
  out = out.replace(/\^/g, "**");
  out = out.replace(/::\s*[\w.{}| ]+/g, "");

  // Lua cho phép xuống dòng trong biểu thức: gộp dòng bắt đầu bằng toán tử
  out = out.replace(/\n[ \t]*(\*|\/|\+|-(?=\s)|and\b|or\b|\*\*)\s*/g, " $1 ");

  // field bảng Lua `  name = "x",`  →  `  name: "x",`
  out = out.replace(/^(\s*)([A-Za-z_]\w*)\s*=\s*/gm, "$1$2: ");

  // nối chuỗi
  out = out.replace(/([^\s.])\.\.([^\s])/g, "$1 + $2");

  // thư viện
  out = out.replace(/math\.clamp\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)/g, "L.clamp($1)");
  out = out.replace(/math\.floor/g, "Math.floor");
  out = out.replace(/math\.max/g, "Math.max");
  out = out.replace(/math\.min/g, "Math.min");
  out = out.replace(/string\.format/g, "fmt");

  // bảng thuần dãy `X = { {...} }` → mảng JS thật
  out = out.replace(
    /(CultivationConfig\.Realms) = \{([\s\S]*?)\n\}(?=\s*\n(?:CultivationConfig\.|[a-z]))/,
    (m, name, body) => `${name} = [${body}\n]`
  );
  // Lua 1-based → JS 0-based cho truy cập trực tiếp
  out = out.replace(/(CultivationConfig\.Realms)\[([\w.]+)\]/g, "$1[($2) - 1]");

  out = out.replace(/^(\s*)return\b(.*)$/gm, (m, ind, rest) => `${ind}return${rest};`);
  return out;
}

let cache = null;

/** Nạp CultivationConfig + Cultivation (có cache trong 1 lần chạy). */
export function loadCultivation() {
  if (cache) return cache;

  let configSrc = stripLuau(fs.readFileSync(path.join(SHARED, "CultivationConfig.luau"), "utf8"));
  configSrc = configSrc.replace(/^local CultivationConfig = \{\}$/m, "const CultivationConfig = {};");
  configSrc = luaToJs(configSrc);
  const configFn = new Function("Color3", "L", "Math", "fmt", `"use strict";\n${configSrc}`);
  const CultivationConfig = configFn(Color3, L, Math, fmt);
  if (!CultivationConfig || !CultivationConfig.Realms) {
    throw new Error("Không nạp được CultivationConfig (kiểm tra cú pháp file .luau)");
  }

  let cultSrc = stripLuau(fs.readFileSync(path.join(SHARED, "Cultivation.luau"), "utf8"));
  cultSrc = cultSrc.replace(/^local CultivationConfig = require\(.*\)$/m, "");
  cultSrc = cultSrc.replace(/^local Cultivation = \{\}$/m, "const Cultivation = {};");
  cultSrc = luaToJs(cultSrc);
  const cultFn = new Function("CultivationConfig", "L", "Math", "fmt", `"use strict";\n${cultSrc}`);
  const Cultivation = cultFn(CultivationConfig, L, Math, fmt);
  if (!Cultivation || typeof Cultivation.tick !== "function") {
    throw new Error("Không nạp được Cultivation (kiểm tra cú pháp file .luau)");
  }

  cache = { Cultivation, CultivationConfig };
  return cache;
}

export { fmt, L, Color3 };
