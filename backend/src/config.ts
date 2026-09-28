import { isIP } from 'node:net';

const environments = ['development', 'test', 'production'] as const;
const levels = ['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'] as const;

export interface Config {
  nodeEnv: typeof environments[number];
  host: string;
  port: number;
  logLevel: typeof levels[number];
}

function option<T extends string>(name: string, value: string, choices: readonly T[]): T {
  const match = choices.find(choice => choice === value);
  if (!match) throw new Error(`Invalid ${name}: expected ${choices.join(', ')}`);
  return match;
}

// Report variable names, never their values (which may contain secrets).
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const host = env.HOST ?? '127.0.0.1';
  if (host !== 'localhost' && !isIP(host)) {
    throw new Error('Invalid HOST: expected localhost or an IP address');
  }
  const port = env.PORT ?? '3000';
  if (!/^\d+$/.test(port) || Number(port) < 1 || Number(port) > 65535) {
    throw new Error('Invalid PORT: expected an integer from 1 to 65535');
  }
  return {
    nodeEnv: option('NODE_ENV', env.NODE_ENV ?? 'development', environments),
    host,
    port: Number(port),
    logLevel: option('LOG_LEVEL', env.LOG_LEVEL ?? 'info', levels),
  };
}
