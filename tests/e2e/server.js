// Local end-to-end test harness (not deployed). Serves the static site and emulates the
// Supabase REST endpoint /rest/v1/rpc/<fn> on top of a local Postgres, calling each
// function as the low-privilege "anon" role exactly as PostgREST would.
const http = require("http");
const fs = require("fs");
const path = require("path");
const { Pool } = require("pg");

const ROOT = path.resolve(__dirname, "..", "..");
const pool = new Pool({ host: "/tmp", port: 55432, user: "postgres", database: "postgres" });
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };
const ARGS = {
  quiz_config: [], quiz_register: ["p_name", "p_email"], quiz_status: ["p_token"], quiz_start: ["p_token"],
  quiz_submit: ["p_token", "p_answers"], quiz_result: ["p_token"], quiz_leaderboard: ["p_limit"], quiz_stats: []
};

http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  if (url.pathname.startsWith("/rest/v1/rpc/")) {
    const fn = url.pathname.split("/").pop();
    if (!ARGS[fn]) { res.writeHead(404); return res.end("{}"); }
    let body = "";
    for await (const c of req) body += c;
    const args = JSON.parse(body || "{}");
    const vals = ARGS[fn].map((k) => (typeof args[k] === "object" && args[k] !== null ? JSON.stringify(args[k]) : args[k]));
    const ph = vals.map((_, i) => `$${i + 1}`).join(",");
    const client = await pool.connect();
    try {
      await client.query("set role anon");
      const r = await client.query(`select public.${fn}(${ph}) as v`, vals);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(r.rows[0].v));
    } catch (e) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ message: e.message }));
    } finally {
      await client.query("reset role").catch(() => {});
      client.release();
    }
    return;
  }
  let p = url.pathname === "/" ? "/index.html" : url.pathname;
  if (p === "/config.js") {
    res.writeHead(200, { "Content-Type": "text/javascript" });
    return res.end('window.BOB_QUIZ_CONFIG={SUPABASE_URL:"http://127.0.0.1:8099",SUPABASE_ANON_KEY:"test-anon-key"};');
  }
  const file = path.join(ROOT, path.normalize(p));
  if (!file.startsWith(ROOT) || !fs.existsSync(file)) { res.writeHead(404); return res.end("nf"); }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
  res.end(fs.readFileSync(file));
}).listen(8099, "127.0.0.1", () => console.log("test server on 8099"));
