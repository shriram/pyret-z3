// Drive VS Code web (vscode-test-web on :3100) with the Pyret extension:
// open a .arr file, click Run, and print the Pyret output.
// Usage: node run-in-vscode-web.js <path relative to the repo root> [timeoutSeconds]
const { chromium } = require("playwright");

const target = process.argv[2] || "src/z3-tests.arr";
const timeoutSec = Number(process.argv[3] || "180");

function allFrames(page) {
  return page.frames();
}

async function frameTexts(page) {
  const out = [];
  for (const f of allFrames(page)) {
    try {
      const t = await f.evaluate(() => document.body ? document.body.innerText : "");
      out.push({ url: f.url(), text: t });
    } catch (e) { /* detached or cross-origin */ }
  }
  return out;
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
  page.on("console", m => { if (m.type() === "error") console.log("[console.error]", m.text().slice(0, 300)); });
  await page.goto("http://localhost:3100/", { waitUntil: "load" });

  // Open the file from the explorer tree (expand folders along the path).
  const parts = target.split("/");
  for (const part of parts) {
    const item = page.getByRole("treeitem", { name: part, exact: true }).first();
    await item.waitFor({ timeout: 60000 });
    await item.click();
    await page.waitForTimeout(1500);
  }
  console.log("opened", target);

  // The Pyret editor (code.pyret.org) lives in VS Code's webview (an outer
  // iframe and an inner one). Find the frame that has both Run and Stop and
  // click ITS Run.
  let runFrame = null;
  let run = null;
  const findDeadline = Date.now() + 90000;
  while (Date.now() < findDeadline && runFrame === null) {
    for (const f of page.frames()) {
      try {
        const candidates = f.locator("#runButton, button:has-text('Run'), a:has-text('Run')");
        const n = await candidates.count();
        const stop = await f.locator("button:has-text('Stop'), a:has-text('Stop')").count();
        if (n > 0 && stop > 0) { runFrame = f; run = candidates.first(); break; }
      } catch (e) { /* frame navigating */ }
    }
    if (runFrame === null) { await page.waitForTimeout(2000); }
  }
  if (runFrame === null) {
    console.log("no frame with Run/Stop; frames:", page.frames().map(f => f.url().slice(0, 100)));
    await page.screenshot({ path: "vscode-norun.png" });
    process.exit(3);
  }
  console.log("Run button found in frame", runFrame.url().slice(0, 100));
  await page.waitForTimeout(5000);
  // Drag the editor/REPL splitter left so the interactions pane is visible.
  await page.mouse.move(1238, 500);
  await page.mouse.down();
  await page.mouse.move(700, 500, { steps: 10 });
  await page.mouse.up();
  await page.waitForTimeout(500);
  await run.click();
  console.log("clicked Run (webview)");
  const t0 = Date.now();
  let lastSnap = 0;

  const deadline = Date.now() + timeoutSec * 1000;
  let last = "";
  while (Date.now() < deadline) {
    await page.waitForTimeout(3000);
    const texts = await frameTexts(page);
    const joined = texts.map(t => t.text).join("\n");
    const m = joined.match(/(Looks shipshape[^\n]*|Passed: [^\n]*|all \d+ tests passed[^\n]*|The program didn't define any tests[^\n]*)/);
    if (m) {
      console.log("RESULT:", m[1]);
      const idx = joined.indexOf(m[1]);
      console.log(joined.slice(Math.max(0, idx - 2500), idx + 400));
      await page.screenshot({ path: "vscode-result.png" });
      await browser.close();
      return;
    }
    const errish = joined.match(/(Error loading webview[^\n]*|Could not load Z3[^\n]*|errored[^\n]*|Pyret didn't understand[^\n]*|is unbound[^\n]*)/);
    if (errish && errish[1] !== last) { last = errish[1]; console.log("note:", errish[1].slice(0, 300)); }
    if (Date.now() - lastSnap > 30000) {
      lastSnap = Date.now();
      const wv = texts.filter(t => t.url.includes("webview")).map(t => t.text).join("\n");
      console.log(`[${Math.round((Date.now() - t0) / 1000)}s] webview tail:`, JSON.stringify(wv.slice(-400)));
    }
  }
  console.log("TIMEOUT; frame texts follow");
  for (const t of await frameTexts(page)) {
    console.log("---", t.url.slice(0, 120));
    console.log(t.text.slice(0, 1500));
  }
  await page.screenshot({ path: "vscode-timeout.png" });
  await browser.close();
  process.exit(2);
})().catch(e => { console.error("FAILED", e); process.exit(1); });
