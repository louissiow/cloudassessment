// CloudWatch Synthetics API canary: t1dx-canary-cuj-<region>
// Exercises CUJ-01 (login), CUJ-02 (balance) and CUJ-03 (RM 0.01 transfer between
// two flagged synthetic accounts) through the public edge t1dx-cf-edge.
// Credentials come from Secrets Manager (replicated to both Regions) - never hard-coded.
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const { randomUUID } = require('crypto');

const BASE = new URL(process.env.BASE_URL);

async function secret() {
  const sm = new SecretsManagerClient({});
  const out = await sm.send(new GetSecretValueCommand({ SecretId: 't1dx/canary/synthetic-customer' }));
  return JSON.parse(out.SecretString);
}

function req(method, path, headers = {}) {
  return {
    hostname: BASE.hostname,
    method,
    path,
    port: 443,
    protocol: 'https:',
    headers: { 'Content-Type': 'application/json', 'x-synthetic': 'true', ...headers },
  };
}

function expectStatus(allowed) {
  return async (res) => new Promise((resolve, reject) => {
    if (!allowed.includes(res.statusCode)) {
      reject(new Error(`unexpected status ${res.statusCode}`));
      return;
    }
    let body = '';
    res.on('data', (d) => { body += d; });
    res.on('end', () => resolve(body));
  });
}

exports.handler = async () => {
  const s = await secret();
  const cfg = synthetics.getConfiguration();
  cfg.setConfig({ restrictedHeaders: ['authorization'], restrictedUrlParameters: [] });

  // CUJ-01 login (device-bound synthetic customer)
  let token;
  await synthetics.executeHttpStep('CUJ-01-login', req('POST', '/auth/login'), async (res) => {
    const body = await expectStatus([200])(res);
    token = JSON.parse(body).accessToken;
  }, { includeRequestBody: false, includeResponseBody: false });
  const auth = { Authorization: `Bearer ${token}` };

  // CUJ-02 balance
  await synthetics.executeHttpStep('CUJ-02-balance',
    req('GET', `/accounts/${s.fromAccountId}`, auth), expectStatus([200]));

  // CUJ-03 transfer accepted (201/202). Idempotency-Key is unique per run.
  const body = JSON.stringify({ to: s.toAccountId, amount: '0.01', currency: 'MYR', reference: 'synthetic' });
  const r = req('POST', '/transfers', { ...auth, 'Idempotency-Key': randomUUID() });
  r.body = body;
  await synthetics.executeHttpStep('CUJ-03-transfer-accept', r, expectStatus([201, 202]));
  log.info('CUJ canary completed');
};
