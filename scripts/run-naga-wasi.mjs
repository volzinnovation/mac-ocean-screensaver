// Run the pinned build-time compiler with access only to its shader working directory.
import { WASI } from 'node:wasi';
import { readFile } from 'node:fs/promises';

const wasmPath = process.argv[2];
if (!wasmPath) throw new Error('Usage: node run-naga-wasi.mjs /path/naga.wasm [naga arguments]');
const wasi = new WASI({
  version: 'preview1',
  args: ['naga', ...process.argv.slice(3)],
  env: {},
  preopens: { '.': process.cwd() },
  returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(wasmPath));
const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport });
process.exitCode = wasi.start(instance) ?? 0;
