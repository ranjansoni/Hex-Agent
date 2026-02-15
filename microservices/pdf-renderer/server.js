/**
 * PDF Renderer — POST /render-pdf with { url } → returns PDF binary.
 * Used by n8n to convert hex.inc/proposal/{slug} pages to PDF.
 */
const express = require('express');
const puppeteer = require('puppeteer');

const app = express();
app.use(express.json());

const PORT = parseInt(process.env.PORT || '3100', 10);
const RENDER_TIMEOUT_MS = parseInt(process.env.RENDER_TIMEOUT_MS || '30000', 10);

// Basic URL validation (allow http/https)
function isValidUrl(s) {
  if (typeof s !== 'string' || !s.trim()) return false;
  try {
    const u = new URL(s);
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch {
    return false;
  }
}

app.post('/render-pdf', async (req, res) => {
  const { url } = req.body || {};
  if (!isValidUrl(url)) {
    return res.status(400).json({ error: 'url is required and must be a valid http(s) URL' });
  }

  let browser;
  try {
    browser = await puppeteer.launch({
      headless: 'new',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
      ],
    });
    const page = await browser.newPage();
    await page.goto(url, {
      waitUntil: 'networkidle0',
      timeout: RENDER_TIMEOUT_MS,
    });
    const pdf = await page.pdf({
      format: 'Letter',
      printBackground: true,
      margin: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' },
    });
    await browser.close();
    browser = null;

    res.set({
      'Content-Type': 'application/pdf',
      'Content-Disposition': 'inline; filename="rendered.pdf"',
    });
    res.send(pdf);
  } catch (err) {
    if (browser) await browser.close().catch(() => {});
    if (err.name === 'TimeoutError') {
      return res.status(504).json({ error: 'Render timeout', details: err.message });
    }
    console.error('Render error:', err);
    res.status(500).json({ error: 'Failed to render PDF', details: err.message });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'pdf-renderer' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`PDF renderer listening on port ${PORT}`);
});
