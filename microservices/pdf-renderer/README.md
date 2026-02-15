# PDF Renderer

Renders a given URL to a PDF using Puppeteer. Used by n8n to convert `https://hex.inc/proposal/{slug}` pages to PDF.

## Endpoint

- **POST /render-pdf**  
  Body: `{ "url": "https://hex.inc/proposal/acme-corp" }`  
  Response: PDF binary (`application/pdf`).

## Run locally

```bash
npm install
npm start
# Default port 3100; override with PORT=3100
```

## Run with Docker

```bash
docker build -t hex-pdf-renderer .
docker run -p 3100:3100 hex-pdf-renderer
```

From project root you can use `docker-compose up pdf-renderer`.

## Env

- `PORT` — default 3100
- `RENDER_TIMEOUT_MS` — default 30000 (30s)

## Health

- **GET /health** — returns `{ "status": "ok", "service": "pdf-renderer" }`
