// Minimal fetch-to-file helper for plugin download/update.
// Prints detailed errors to stderr so the host application can log them.

const url = Deno.args[0];
const out = Deno.args[1];

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

  const res = await fetch(url, { redirect: "follow" });
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
  await Deno.writeFile(out, buf);
} catch (e) {
  const msg = e instanceof Error ? e.message : String(e);
  console.error(`FETCH_ERROR ${msg}`);
  if (e instanceof Error && e.stack) console.error(e.stack);
  Deno.exit(1);
}

