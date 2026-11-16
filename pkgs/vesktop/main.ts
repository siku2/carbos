import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { app, net, protocol } from "electron";

// Discord loads this pinned build instead of the one it currently serves.
const page = readFileSync(new URL("discord.html", import.meta.url));
const version = readFileSync(new URL("version.json", import.meta.url));

function isPage(request: Request, url: URL): boolean {
  return (
    request.method === "GET" &&
    (request.headers.get("accept") ?? "").includes("text/html") &&
    !/^\/(api|assets|cdn-cgi)\//.test(url.pathname)
  );
}

app.whenReady().then(() => {
  protocol.handle("https", (request) => {
    const url = new URL(request.url);
    if (url.hostname === "discord.com") {
      if (url.pathname === "/assets/version.stable.json") {
        return new Response(version, {
          headers: { "content-type": "application/json" },
        });
      }
      if (isPage(request, url)) {
        return new Response(page, {
          headers: { "content-type": "text/html; charset=utf-8" },
        });
      }
    }
    return net.fetch(request, { bypassCustomProtocolHandlers: true });
  });
});

createRequire(import.meta.url)("../app.asar/dist/js/main.js");
