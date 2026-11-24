'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');

async function main() {
  const [inputPath, outputPath] = process.argv.slice(2);
  const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  const { chromium, firefox, webkit } = require(input.playwrightPath);
  const browserName = String(input.browser || 'chrome').toLowerCase();
  const type = browserName === 'firefox' ? firefox : browserName === 'webkit' ? webkit : chromium;
  const profileWasTemporary = !input.profile;
  const userDataDir = input.profile || fs.mkdtempSync(path.join(os.tmpdir(), 'browser-profile-'));
  const launch = { headless: Boolean(input.headless) };
  if (input.executablePath) launch.executablePath = input.executablePath;
  if (input.channel) launch.channel = input.channel;

  let context;
  try {
    context = await type.launchPersistentContext(userDataDir, launch);
    const page = await context.newPage();
    if (input.method === 'POST') {
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
        status: response.status(), title: await page.title(), content_type: headers['content-type'] || null, headers,
        body, body_text: await page.evaluate(() => document.body ? document.body.innerText : ''),
      };
      if (input.script !== undefined) result.script_result = scriptResult === undefined ? null : scriptResult;
      await finish(context, result, input, outputPath, profileWasTemporary, userDataDir);
      return;
    }

    let response;
    try {
      response = await page.goto(input.url, {
        waitUntil: input.waitUntil,
        ...(input.timeout === undefined || input.timeout === null ? {} : { timeout: input.timeout }),
      });
    } catch (error) {
      throw error;
    }
    if (input.interactive) await waitForEnter();
    const scriptResult = await runPageScript(page, input);
    if (input.method === 'PNG' || input.method === 'PDF') {
      if (input.method === 'PNG') {
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
        method: input.method, requested_url: input.url, final_url: page.url(),
        status: response ? response.status() : null,
        title: await page.title(),
        content_type: response ? (response.headers()['content-type'] || null) : null,
        headers: response ? response.headers() : {}, file: input.file,
      };
      if (input.script !== undefined) result.script_result = scriptResult === undefined ? null : scriptResult;
      await finish(context, result, input, outputPath, profileWasTemporary, userDataDir);
      return;
    }

    const body = await page.content();
    const title = await page.title().catch(() => '');
    const result = {
      method: 'GET', requested_url: input.url, final_url: page.url(),
      status: response ? response.status() : null,
      title: title || '',
      content_type: response ? (response.headers()['content-type'] || null) : null,
      headers: response ? response.headers() : {}, body,
      body_text: await page.evaluate(() => document.body ? document.body.innerText : ''),
      is_captcha: isCaptcha(title, body),
    };
    if (input.script !== undefined) result.script_result = scriptResult === undefined ? null : scriptResult;
    await finish(context, result, input, outputPath, profileWasTemporary, userDataDir);
  } catch (error) {
    try { if (context) await context.close(); } catch (_) {}
    if (profileWasTemporary) {
      try { fs.rmSync(userDataDir, { recursive: true, force: true }); } catch (_) {}
    }
    writeResult(outputPath, { ok: false, error: error && error.message ? error.message : String(error) });
    process.exitCode = 1;
  }
}

async function finish(context, result, input, outputPath, profileWasTemporary, userDataDir) {
  writeResult(outputPath, { ok: true, result });
  if (input.keepItOn) {
    await context.waitForEvent('close', { timeout: 0 });
  } else {
    await context.close();
  }
  if (profileWasTemporary) fs.rmSync(userDataDir, { recursive: true, force: true });
}

function writeResult(outputPath, value) {
  const temporaryPath = `${outputPath}.${process.pid}.tmp`;
  fs.writeFileSync(temporaryPath, JSON.stringify(value), 'utf8');
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

function isCaptcha(title, body) {
  const text = `${title || ''}\n${body || ''}`.toLowerCase();
  return /captcha|unusual traffic|verify you are human|checking your browser/.test(text);
}

main().catch(error => {
  const [, outputPath] = process.argv.slice(2);
  try { writeResult(outputPath, { ok: false, error: error.message || String(error) }); } catch (_) {}
  process.exitCode = 1;
});
