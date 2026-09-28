import Fastify, { LogController } from 'fastify';
import type { Config } from './config.ts';

// Composition is separate from listen so tests never need an open port.
export function buildApp(config: Config) {
  const app = Fastify({
    logger: { level: config.logLevel },
    // Default request logs contain URLs; lookup queries can contain usernames.
    logController: new LogController({ disableRequestLogging: true }),
    requestIdHeader: false,
    bodyLimit: 16 * 1024,
    requestTimeout: 10_000,
    connectionTimeout: 10_000,
    forceCloseConnections: true,
    exposeHeadRoutes: false,
  });

  app.get('/v1/health', {
    schema: {
      response: {
        200: {
          type: 'object',
          additionalProperties: false,
          required: ['status'],
          properties: { status: { type: 'string', const: 'ok' } },
        },
      },
    },
  }, async (_request, reply) => {
    reply.header('Cache-Control', 'no-store');
    return { status: 'ok' };
  });

  app.setNotFoundHandler(async (_request, reply) => {
    return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Route not found' } });
  });

  app.setErrorHandler((error, request, reply) => {
    const errorStatus = error instanceof Error && 'statusCode' in error ? error.statusCode : undefined;
    const clientError = typeof errorStatus === 'number' && Number.isInteger(errorStatus) && errorStatus >= 400 && errorStatus < 500;
    const status = clientError ? errorStatus : 500;
    // Never log raw errors, bodies, headers, URLs, tokens, or message payloads.
    request.log.error({ requestId: request.id, statusCode: status }, 'Request failed');
    return reply.code(status).send({
      error: {
        code: clientError ? 'INVALID_REQUEST' : 'INTERNAL_ERROR',
        message: clientError ? 'Invalid request' : 'Something went wrong',
      },
    });
  });

  return app;
}
