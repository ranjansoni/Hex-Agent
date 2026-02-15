/**
 * Contract Generator — POST /generate-contract with deal JSON → returns contract PDF.
 * Uses Handlebars template + Puppeteer. Replace templates/contract.hbs with your real contract.
 */
const express = require('express');
const puppeteer = require('puppeteer');
const Handlebars = require('handlebars');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.json({ limit: '1mb' }));

const PORT = parseInt(process.env.PORT || '3200', 10);
const TEMPLATE_PATH = path.join(__dirname, 'templates', 'contract.hbs');

Handlebars.registerHelper('formatNumber', (n) => {
  if (n == null) return '';
  const num = Number(n);
  return Number.isFinite(num) ? num.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 }) : String(n);
});

let templateCompiled;
function getTemplate() {
  if (!templateCompiled) {
    const html = fs.readFileSync(TEMPLATE_PATH, 'utf8');
    templateCompiled = Handlebars.compile(html);
  }
  return templateCompiled;
}

// Normalize deal payload for template (defaults, formatting)
function normalizeDeal(body) {
  const deal = { ...body };
  deal.client_name = deal.client_name || 'Client';
  deal.contact_name = deal.contact_name || '';
  deal.contact_email = deal.contact_email || '';
  deal.plan_name = deal.plan_name || '';
  deal.total_amount = deal.total_amount != null ? Number(deal.total_amount) : 0;
  deal.project_term_weeks = deal.project_term_weeks != null ? deal.project_term_weeks : null;
  deal.kickoff_date = deal.kickoff_date || null;
  deal.installments = Array.isArray(deal.installments) ? deal.installments : [];
  // Format currency for display
  deal.total_amount_formatted = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(deal.total_amount);
  deal.project_term_display = deal.project_term_weeks != null
    ? `${deal.project_term_weeks} weeks`
    : 'TBD';
  deal.kickoff_display = deal.kickoff_date || 'TBD';
  return deal;
}

app.post('/generate-contract', async (req, res) => {
  const body = req.body || {};
  const deal = normalizeDeal(body);

  let browser;
  try {
    const html = getTemplate()(deal);
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
    await page.setContent(html, {
      waitUntil: 'networkidle0',
      timeout: 10000,
    });
    const pdf = await page.pdf({
      format: 'Letter',
      printBackground: true,
      margin: { top: '0.75in', right: '0.75in', bottom: '0.75in', left: '0.75in' },
    });
    await browser.close();
    browser = null;

    res.set({
      'Content-Type': 'application/pdf',
      'Content-Disposition': `inline; filename="contract-${(deal.client_name || 'client').replace(/[^a-z0-9]/gi, '-')}.pdf"`,
    });
    res.send(pdf);
  } catch (err) {
    if (browser) await browser.close().catch(() => {});
    console.error('Contract generation error:', err);
    res.status(500).json({
      error: 'Failed to generate contract PDF',
      details: err.message,
    });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'contract-generator' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Contract generator listening on port ${PORT}`);
});
