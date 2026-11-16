import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const [file] = process.argv.slice(2);
if (file === undefined) {
  throw new Error("usage: update.ts pkgs/vesktop/default.nix");
}
const target = join(dirname(file), "discord.html");

function buildNumber(html: string): string | undefined {
  return /"BUILD_NUMBER":"(\d+)"/.exec(html)?.[1];
}

// Nonces and the Cloudflare challenge change on every request.
function normalize(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, (script) =>
      script.includes("/cdn-cgi/challenge-platform/") ? "" : script,
    )
    .replace(/ nonce="[^"]*"/g, "");
}

const response = await fetch("https://discord.com/app");
if (!response.ok) {
  throw new Error(`discord.com/app returned ${response.status}`);
}
const html = normalize(await response.text());
const build = buildNumber(html);
if (
  build === undefined ||
  html.includes("/cdn-cgi/") ||
  html.includes("nonce=")
) {
  throw new Error("discord.com/app changed its layout, check normalize()");
}

const current = await readFile(target, "utf8").catch(() => "");
if (html !== current) {
  await writeFile(target, html);
  console.log(`discord: ${buildNumber(current) ?? "none"} -> ${build}`);
}
