'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');

async function main() {
  const [inputPath, outputPath] = process.argv.slice(2);
  const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  let session = readSession(input.sessionFile);
  if (session) {
    try {
      const result = await sendToSession(session, input);
      writeResult(outputPath, { ok: true, result });
      return;
    } catch (error) {
      if (!['ECONNREFUSED', 'ECONNRESET', 'EPIPE'].includes(error.code)) throw error;
      removeSessionIfOwned(input.sessionFile, session);
      session = null;
      if (input.current) throw new Error('No active keep-open browser session was found');
    }
  }
  if (input.current) throw new Error('No active keep-open browser session was found');

  const { chromium, firefox, webkit } = require(input.playwrightPath);
  const browserName = String(input.browser || 'chrome').toLowerCase();
  const type = browserName === 'firefox' ? firefox : browserName === 'webkit' ? webkit : chromium;
  const temporaryProfile = !input.profile;
  const userDataDir = input.profile || fs.mkdtempSync(path.join(os.tmpdir(), 'browser-profile-'));
  const launch = { headless: Boolean(input.headless) };
  if (input.executablePath) launch.executablePath = input.executablePath;
  if (input.channel) launch.channel = input.channel;

  let context;
  let server;
  try {
    context = await type.launchPersistentContext(userDataDir, launch);
    const page = await context.newPage();
    if (input.keepItOn) {
      server = await startSessionServer(context, page, input.sessionFile);
    }
    const result = await runRequest(context, page, input);
    writeResult(outputPath, { ok: true, result });
    if (input.keepItOn) {
      await context.waitForEvent('close', { timeout: 0 });
    } else {
      await context.close();
    }
    if (temporaryProfile) fs.rmSync(userDataDir, { recursive: true, force: true });
  } catch (error) {
    try { if (server) server.close(); } catch (_) {}
    try { if (context) await context.close(); } catch (_) {}
    removeSessionIfOwned(input.sessionFile, { pid: process.pid });
    if (temporaryProfile) {
      try { fs.rmSync(userDataDir, { recursive: true, force: true }); } catch (_) {}
    }
    writeResult(outputPath, { ok: false, error: error && error.message ? error.message : String(error) });
    process.exitCode = 1;
  }
}

async function runRequest(context, page, input) {
  const method = String(input.method || 'GET').toUpperCase();
  if (method === 'POST') {
    await page.goto('about:blank');
    const response = await context.request.post(input.url, input.data === undefined ? {} : { data: input.data });
    const body = await response.text();
    const headers = response.headers();
    const responseURL = response.url();
    const html = isHTML(headers['content-type'], body)
      ? body
      : '<!doctype html><html><head><meta charset="utf-8"><title>browser.post</title></head><body><pre id="browser-post-body">' + escapeHTML(body) + '</pre></body></html>';
    await page.setContent(html);
    await page.evaluate(payload => { window.__BROWSER_POST__ = payload; }, {
      method: 'POST', status: response.status(), url: responseURL, body,
    });
    if (input.interactive) await waitForEnter();
    const scriptResult = await runPageScript(page, input);
    const result = {
      method: 'POST', requested_url: input.url,
      final_url: page.url() === 'about:blank' ? responseURL : page.url(),
      status: response.status(), title: await page.title(),
      content_type: headers['content-type'] || null, headers,
      body, body_text: await page.evaluate(() => document.body ? document.body.innerText : ''),
    };
    if (input.script !== undefined) result.script_result = scriptResult === undefined ? null : scriptResult;
    return result;
  }

  let response = null;
  if (!input.current) {
    response = await page.goto(input.url, {
      waitUntil: input.waitUntil,
      ...(input.timeout === undefined || input.timeout === null ? {} : { timeout: input.timeout }),
    });
  }
  if (input.interactive) await waitForEnter();
  const scriptResult = await runPageScript(page, input);
  const requestedURL = input.url || page.url();

  if (method === 'PNG' || method === 'PDF') {
    if (method === 'PNG') {
      await page.screenshot({ path: input.file, type: 'png', fullPage: true });
    } else {
      await page.emulateMedia({ media: 'screen' });
      const dimensions = await page.evaluate(() => ({
        width: document.documentElement.scrollWidth,
        height: document.documentElement.scrollHeight,
      }));
      for (const axis of ['width', 'height']) {
        const value = dimensions && dimensions[axis];
        if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
          throw new Error(`browser.pdf could not measure a usable page ${axis}`);
        }
        if (value > 19200) throw new Error(`browser.pdf refuses to render a page ${axis} of ${value}px - exceeds the 19200 px practical PDF page-size limit`);
      }
      await page.pdf({
        path: input.file,
        width: `${dimensions.width}px`, height: `${dimensions.height}px`,
        printBackground: true,
      });
    }
    const result = {
      method, requested_url: requestedURL, final_url: page.url(),
      status: response ? response.status() : null,
      title: await page.title(),
      content_type: response ? (response.headers()['content-type'] || null) : null,
      headers: response ? response.headers() : {}, file: input.file,
    };
    if (input.script !== undefined) result.script_result = scriptResult === undefined ? null : scriptResult;
    return result;
  }

  const body = await page.content();
  const title = await page.title().catch(() => '');
  const result = {
    method: 'GET', requested_url: requestedURL, final_url: page.url(),
    status: response ? response.status() : null,
    title: title || '',
    content_type: response ? (response.headers()['content-type'] || null) : null,
    headers: response ? response.headers() : {}, body,
    body_text: await page.evaluate(() => document.body ? document.body.innerText : ''),
  };
  if (input.current) result.tabs = await snapshotTabs(context, page);
  if (input.script !== undefined) result.script_result = scriptResult === undefined ? null : scriptResult;
  return result;
}

async function snapshotTabs(context, sessionPage) {
  const pages = context.pages();
  return Promise.all(pages.map(async (tab, index) => {
    const text = await tab.evaluate(() => document.body ? document.body.innerText : '').catch(() => '');
    const limit = 4000;
    return {
      index,
      session_page: tab === sessionPage,
      url: tab.url(),
      title: await tab.title().catch(() => ''),
      text: text.slice(0, limit),
      text_truncated: text.length > limit,
    };
  }));
}

async function startSessionServer(context, page, sessionFile) {
  const token = crypto.randomBytes(32).toString('hex');
  let queue = Promise.resolve();
  const server = http.createServer((request, response) => {
    if (request.method !== 'POST' || request.url !== '/run') {
      response.writeHead(404).end();
      return;
    }
    if (request.headers.authorization !== `Bearer ${token}`) {
      response.writeHead(403).end();
      return;
    }
    let body = '';
    request.setEncoding('utf8');
    request.on('data', chunk => {
      body += chunk;
      if (body.length > 5 * 1024 * 1024) request.destroy(new Error('session request too large'));
    });
    request.on('end', () => {
      let input;
      try { input = JSON.parse(body); }
      catch (_) { response.writeHead(400).end(JSON.stringify({ ok: false, error: 'Invalid session request JSON' })); return; }
      const operation = queue.then(() => runRequest(context, page, input));
      queue = operation.then(() => undefined, () => undefined);
      operation.then(
        result => { response.writeHead(200, { 'content-type': 'application/json' }); response.end(JSON.stringify({ ok: true, result })); },
        error => { response.writeHead(500, { 'content-type': 'application/json' }); response.end(JSON.stringify({ ok: false, error: error.message || String(error) })); },
      );
    });
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const record = { host: '127.0.0.1', port: server.address().port, token, pid: process.pid };
  writeResult(sessionFile, record);
  fs.chmodSync(sessionFile, 0o600);
  context.once('close', () => {
    server.close();
    removeSessionIfOwned(sessionFile, record);
  });
  return server;
}

function readSession(sessionFile) {
  try { return JSON.parse(fs.readFileSync(sessionFile, 'utf8')); }
  catch (_) { return null; }
}

function removeSessionIfOwned(sessionFile, record) {
  if (!sessionFile) return;
  try {
    const current = JSON.parse(fs.readFileSync(sessionFile, 'utf8'));
    if (record.pid && current.pid !== record.pid) return;
    fs.unlinkSync(sessionFile);
  } catch (_) {}
}

function sendToSession(session, input) {
  return new Promise((resolve, reject) => {
    const request = http.request({
      host: session.host, port: session.port, path: '/run', method: 'POST',
      headers: { authorization: `Bearer ${session.token}`, 'content-type': 'application/json' },
    }, response => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', chunk => { body += chunk; });
      response.on('end', () => {
        let result;
        try { result = JSON.parse(body); } catch (_) { reject(new Error('Keep-open browser returned invalid JSON')); return; }
        if (!result.ok) { reject(new Error(result.error || 'Keep-open browser request failed')); return; }
        resolve(result.result);
      });
    });
    request.on('error', reject);
    request.end(JSON.stringify(input));
  });
}

function writeResult(outputPath, value) {
  const temporaryPath = `${outputPath}.${process.pid}.tmp`;
  fs.writeFileSync(temporaryPath, JSON.stringify(value), { encoding: 'utf8', mode: 0o600 });
  fs.renameSync(temporaryPath, outputPath);
}

async function waitForEnter() {
  if (!process.stdin.isTTY) throw new Error('--ask/--askme requires an interactive terminal');
  process.stderr.write('Browser is open for interactive work. Complete the captcha or login flow, then press Enter to continue.\n');
  const rl = readline.createInterface({ input: process.stdin, output: process.stderr });
  await new Promise(resolve => rl.once('line', resolve));
  rl.close();
}

async function runPageScript(page, input) {
  if (input.jquery) await page.addScriptTag({ path: input.jqueryPath });
  if (input.script === undefined) return undefined;
  if (input.script === '') throw new Error('--script must not be empty');
  return page.evaluate(script => new Function(script)(), input.script);
}

function isHTML(contentType, body) {
  const mediaType = String(contentType || '').split(';')[0].trim().toLowerCase();
  return mediaType === 'text/html' || mediaType === 'application/xhtml+xml'
    || /^\s*<!doctype\s+html(?:\s|>)/i.test(body)
    || /^\s*<html(?:\s|>)/i.test(body);
}

function escapeHTML(value) {
  return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

if (require.main === module) {
  main().catch(error => {
    const [, outputPath] = process.argv.slice(2);
    try { writeResult(outputPath, { ok: false, error: error.message || String(error) }); } catch (_) {}
    process.exitCode = 1;
  });
}

module.exports = { runRequest };
