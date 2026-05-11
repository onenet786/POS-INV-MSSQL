import { spawn } from 'node:child_process';
import path from 'node:path';

const tsxCli = path.join(process.cwd(), 'node_modules', 'tsx', 'dist', 'cli.mjs');
const child = spawn(process.execPath, [tsxCli, 'watch', 'src/server.ts'], {
  cwd: process.cwd(),
  stdio: 'inherit',
  shell: false,
});

let stopping = false;

function stop() {
  if (stopping) return;
  stopping = true;
  if (!child.killed) child.kill('SIGINT');
  setTimeout(() => process.exit(0), 1000).unref();
}

process.on('SIGINT', stop);
process.on('SIGTERM', stop);

child.on('exit', (code, signal) => {
  if (stopping || signal === 'SIGINT' || signal === 'SIGTERM') {
    process.exit(0);
  }
  process.exit(code ?? 0);
});
