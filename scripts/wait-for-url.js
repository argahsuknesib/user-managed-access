#!/usr/bin/env node

const url = process.argv[2];
const timeoutMs = Number(process.argv[3] ?? 30000);

if (!url) {
  console.error('Usage: node scripts/wait-for-url.js <url> [timeoutMs]');
  process.exit(1);
}

const startedAt = Date.now();
const pollMs = 500;

async function waitForUrl() {
  while (Date.now() - startedAt < timeoutMs) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        return;
      }
    } catch {
      // Keep polling until timeout.
    }
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
  throw new Error(`Timed out waiting for ${url} after ${timeoutMs}ms`);
}

waitForUrl().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
