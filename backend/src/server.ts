import { buildApp } from './app.ts';
import { loadConfig } from './config.ts';

async function main() {
  const config = loadConfig();
  const app = buildApp(config);
  let closing = false;
  const shutdown = async () => {
    if (closing) return;
    closing = true;
    try {
      await app.close();
    } catch {
      process.stderr.write('Poki API shutdown failed\n');
      process.exitCode = 1;
    }
  };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
  try {
    await app.listen({ host: config.host, port: config.port });
  } catch {
    await shutdown();
    throw new Error('Listen failed');
  }
}

main().catch(() => {
  // Configuration and socket errors may contain credentials: keep startup logs generic.
  process.stderr.write('Poki API startup failed; check configuration and port availability\n');
  process.exitCode = 1;
});
