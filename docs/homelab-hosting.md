# Homelab deployment

Public backend health URL: **https://poki.irrssue.com/v1/health**.

Poki is a native iOS app: install and run it using Xcode as described in the
README. There is no browser version or downloadable signed app at this URL.
The installed app already connects over the internet to the existing hosted
Supabase project for accounts, friendships, and in-app pokes. This deployment
hosts the current Fastify service, whose only endpoint is process health.
It does not migrate Supabase, enable APNs, or change email delivery restrictions.
See [account testing and remaining prerequisites](accounts-setup.md).

## Deploy and roll back

From a machine with the existing `ssh irrssue@homelab` access, commit and push
the intended changes, then run:

```sh
bash deploy/homelab.sh
```

The script uploads only the selected Git commit, builds with Node 24.21.0,
runs type checking and all backend/database tests inside the build, and starts
Docker Compose project `poki`. Build/test failures leave the live containers
unchanged. Runtime failures require rolling back; this is a single-server test
deployment with a brief interruption during replacement.

Releases are retained at `/home/irrssue/apps/poki/releases/<commit>`;
`/home/irrssue/apps/poki/current` points to the latest locally healthy release.
To redeploy a known-good release, pass its commit to the same script:

```sh
bash deploy/homelab.sh <known-good-commit>
```

Pushes alone do not deploy. No GitHub SSH credentials were added.

## Runtime

- API: loopback port `3014`, non-root container, read-only filesystem,
  256 MB memory limit, bounded logs, and a health check every 30 seconds.
- Dedicated Cloudflare tunnel `poki`: routes only `poki.irrssue.com` to the API.
  HTTPS is served at Cloudflare; no router port forwarding is required.
- Both containers restart after process failures or server reboot through
  Docker's `unless-stopped` policy. A failed health check alone does not restart
  a still-running process.
- Tunnel credentials remain exclusively on the server, mounted read-only.
  No Supabase administrative credentials or user data are stored by this API.
- The server's existing tunnel configuration and other services are separate.

Inspect or restart the deployed release on the server:

```sh
cd /home/irrssue/apps/poki/current
export POKI_RELEASE=$(basename "$(readlink -f .)")
docker compose -f deploy/compose.yml ps
docker compose -f deploy/compose.yml logs --tail 100
docker compose -f deploy/compose.yml restart
curl --fail http://127.0.0.1:3014/v1/health
```

The root URL intentionally returns 404. A successful health response only proves
the Fastify process is available; test account and friend flows on two iPhones.
The previously documented missing Supabase safety/mute migrations, restricted
default signup mailer, and missing lock-screen push remain separate work.

Tunnel setup reference: [Cloudflare locally managed tunnels](https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/create-local-tunnel/).
