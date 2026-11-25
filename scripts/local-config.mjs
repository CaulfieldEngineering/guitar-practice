// This machine's own settings, kept out of git: config.local.json at the repo root (config.example.json shows its
// shape). The drill server's address, and the App Store Connect key ids, its .p8 path and the Apple team id for the
// signing scripts. An environment variable, where one is named, wins over the file.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export function localConfig() {
  try {
    return JSON.parse(fs.readFileSync(path.join(ROOT, 'config.local.json'), 'utf8'));
  } catch {
    return {};
  }
}

// One value: the environment variable `env`, else `pick(config)`; `what` names it when neither has it.
export function need(env, pick, what) {
  const v = process.env[env] || pick(localConfig());
  if (!v) throw new Error(`${what} is not set: ${env}, or config.local.json (see config.example.json)`);
  return String(v);
}

export const apple = () => ({
  keyId: need('ASC_KEY_ID', (c) => c.apple?.keyId, 'The App Store Connect API key id'),
  issuerId: need('ASC_ISSUER_ID', (c) => c.apple?.issuerId, 'The App Store Connect issuer id'),
  keyPath: need('ASC_KEY_PATH', (c) => c.apple?.keyPath, 'The App Store Connect .p8 path'),
  teamId: need('IOS_TEAM_ID', (c) => c.apple?.teamId, 'The Apple team id'),
});
