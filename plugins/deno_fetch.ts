// Minimal fetch-to-file helper for plugin download/update.
// Prints detailed errors to stderr so the host application can log them.
//
// Args:
//   0: url
//   1: outFile
//   2: (optional) ifNoneMatch (ETag value)
//
// Stdout (on success): JSON { not_modified: boolean, etag: string }

const url = Deno.args[0];
const out = Deno.args[1];
const ifNoneMatch = Deno.args[2] ?? "";

function parentDir(p: string): string {
  // Avoid importing std/path to keep this script self-contained.
  const m = p.match(/^(.*)[\\/][^\\/]*$/);
  return m ? m[1] : "";
}

async function ensureParentDir(p: string) {
  const dir = parentDir(p);
  if (!dir || dir === ".") return;
  await Deno.mkdir(dir, { recursive: true });
}

function truncate(s: string, max: number): string {
  const t = (s ?? "").trim();
  if (!t) return "";
  if (t.length <= max) return t;
  return t.slice(0, max) + `...(truncated,len=${t.length})`;
}

try {
  if (!url || !out) {
    console.error("ARGS_ERROR missing url/out");
    Deno.exit(2);
  }

  const headers: Record<string, string> = {};
  if (ifNoneMatch.trim()) headers["if-none-match"] = ifNoneMatch.trim();

  const res = await fetch(url, { redirect: "follow", headers });
  const etag = res.headers.get("etag") ?? "";

  if (res.status === 304) {
    // No need to download body; caller should treat as "already up to date".
    console.log(JSON.stringify({ not_modified: true, etag }));
    Deno.exit(0);
  }
  if (!res.ok) {
    let body = "";
    try {
      body = await res.text();
    } catch {
      body = "";
    }
    console.error(
      `HTTP ${res.status} ${res.statusText} body=${truncate(body, 512)}`
    );
    Deno.exit(2);
  }

  const buf = new Uint8Array(await res.arrayBuffer());
  await ensureParentDir(out);
  await Deno.writeFile(out, buf);
  console.log(JSON.stringify({ not_modified: false, etag }));
} catch (e) {
  const msg = e instanceof Error ? e.message : String(e);
  console.error(`FETCH_ERROR ${msg}`);
  if (e instanceof Error && e.stack) console.error(e.stack);
  Deno.exit(1);
}
