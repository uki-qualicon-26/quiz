// Drives the real UI in headless Chromium. Run after tests/e2e/server.js is up.
const { chromium } = require("playwright");
const assert = require("assert");
const BASE = "http://127.0.0.1:8099";

(async () => {
  const browser = await chromium.launch();
  const errors = [];
  const newPage = async () => {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
    // 400s from intentionally rejected requests (bad/duplicate email) are expected.
    page.on("console", (m) => {
      if (m.type() === "error" && !/status of 400/.test(m.text())) errors.push("console: " + m.text());
    });
    return page;
  };

  // --- Player 1: validation, single/multi behaviour, scoring, review ---
  const p = await newPage();
  await p.goto(BASE);
  await p.fill("#name", "Alice Tester");
  await p.fill("#email", "alice@gmail.com");
  await p.click("#reg-btn");
  assert(/ibm\.com/.test(await p.textContent("#error")), "non-IBM email rejected");

  await p.fill("#email", "alice@uk.ibm.com");
  await p.click("#reg-btn");
  await p.waitForSelector("#view-ready:not(.hidden)");
  await p.click("#start-btn");
  await p.waitForSelector("#view-quiz:not(.hidden)");
  assert.strictEqual(await p.locator(".qcard").count(), 10, "10 questions");

  // single-choice: radio, picking a second option replaces the first
  const q1 = p.locator(".qcard").nth(0);
  assert.strictEqual(await q1.locator("input[type=radio]").count(), 4, "Q1 radios");
  await q1.locator("input[value=a]").check();
  await q1.locator("input[value=b]").check();
  assert.strictEqual(await q1.locator("input:checked").count(), 1, "single allows one only");
  // multi-choice: checkboxes, several allowed
  const q2 = p.locator(".qcard").nth(1);
  assert.strictEqual(await q2.locator("input[type=checkbox]").count(), 4, "Q2 checkboxes");
  await q2.locator("input[value=a]").check(); await q2.locator("input[value=b]").check(); await q2.locator("input[value=c]").check();
  assert.strictEqual(await q2.locator("input:checked").count(), 3, "multi allows several");

  // Answer key: Q1 b, Q3 c, Q4 c, Q5 a, Q6 d, Q7 a+b, Q8 d, Q9 b, Q10 a+b+c. Deliberately get Q9 wrong (pick a).
  const pick = async (n, keys) => { for (const k of keys) await p.locator(".qcard").nth(n - 1).locator(`input[value=${k}]`).check(); };
  await pick(3, ["c"]); await pick(4, ["c"]); await pick(5, ["a"]); await pick(6, ["d"]);
  await pick(7, ["a", "b"]); await pick(8, ["d"]); await pick(9, ["a"]); await pick(10, ["a", "b", "c"]);
  assert(/10 of 10 answered/.test(await p.textContent("#progress")), "progress counter");
  assert(!(await p.content()).includes('"correct"'), "no answer key leaked in DOM");
  await p.click("#submit-btn");
  await p.waitForSelector("#view-result:not(.hidden)");
  assert.strictEqual((await p.textContent("#res-score")).trim(), "9", "9/10 expected");
  assert.strictEqual((await p.textContent("#res-rank")).trim(), "#1");
  assert.strictEqual(await p.locator("#review .opt.wrong").count(), 1, "exactly one wrong option highlighted");
  assert((await p.locator("#review .verdict.bad").count()) === 1, "one incorrect verdict");
  await p.waitForSelector("#lb-wrap table.lb tbody tr");
  assert((await p.textContent("#lb-wrap")).includes("Alice Tester"), "leaderboard shows name");
  assert(!(await p.textContent("#lb-wrap")).includes("@"), "leaderboard hides emails");

  // refresh keeps result, and re-registering same email is blocked
  await p.reload();
  await p.waitForSelector("#view-result:not(.hidden)");
  const p1b = await newPage();
  await p1b.goto(BASE);
  await p1b.fill("#name", "Alice Again"); await p1b.fill("#email", "ALICE@uk.ibm.com");
  await p1b.click("#reg-btn");
  await p1b.waitForSelector("#error:not(.hidden)");
  assert(/already completed/.test(await p1b.textContent("#error")), "duplicate blocked");

  // --- Player 2: timer expiry auto-submits what was answered; refresh mid-quiz keeps the clock ---
  const t = await newPage();
  await t.goto(BASE);
  await t.fill("#name", "Slow Sam"); await t.fill("#email", "sam@ibm.com");
  await t.click("#reg-btn"); await t.waitForSelector("#view-ready:not(.hidden)");
  await t.click("#start-btn"); await t.waitForSelector("#view-quiz:not(.hidden)");
  await t.locator(".qcard").nth(0).locator("input[value=b]").check();
  t.on("dialog", (d) => d.accept());
  await t.waitForTimeout(3000);
  await t.evaluate(() => { window.onbeforeunload = null; });
  await t.reload({ waitUntil: "load" }).catch(() => {});
  await t.waitForSelector("#view-quiz:not(.hidden)");
  const clock = await t.textContent("#clock");
  assert(/^0:(0\d|1\d|2\d)$/.test(clock.trim()), "clock resumed after refresh, got " + clock);
  await t.waitForSelector("#view-result:not(.hidden)", { timeout: 40000 });
  assert.strictEqual((await t.textContent("#res-score")).trim(), "1", "auto-submit scored the one answer");
  assert((await t.textContent("#res-rank")).trim() === "#2", "ranked below Alice");

  // --- Presenter: counters and ceremony ---
  const pr = await newPage();
  await pr.goto(BASE + "/presenter.html");
  await pr.waitForSelector("#lb-wrap table.lb tbody tr");
  assert.strictEqual((await pr.textContent("#c-done")).trim(), "2", "2 finished");
  await pr.click("#btn-ceremony");
  await pr.waitForSelector(".podium-step.is-winner", { timeout: 15000 });
  assert(/Alice Tester/.test(await pr.textContent("#banner")), "winner announced");
  await pr.waitForSelector(".confetti");

  assert.deepStrictEqual(errors, [], "no browser errors: " + errors.join(" | "));
  await browser.close();
  console.log("E2E PASSED");
})().catch((e) => { console.error("E2E FAILED:", e.message); process.exit(1); });
