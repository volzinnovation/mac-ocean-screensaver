// Evaluate the upstream's shader templates without a browser, retaining the exact WGSL.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.resolve(process.argv[2] || path.join(root, 'build/wgsl'));
const names = [
  'SIM_INIT', 'SIM_EVOLVE', 'FFT_ROWS', 'FFT_COLS', 'SIM_MIPS', 'FOAM_TEX',
  'RGBA8_MIPS', 'FOAM_UPDATE', 'ARRAY16_MIPS', 'TRANS_LUT', 'MS_LUT',
  'SKYVIEW_LUT', 'ENV_CUBE', 'CUBE_MIPS', 'SUN_VIS', 'HEIGHT_PROBE',
  'OCEAN', 'SKY_BG', 'BLOOM_DOWN', 'BLOOM_UP', 'COMPOSITE',
];
const modules = ['common', 'sim', 'sky', 'ocean', 'post'];
const code = modules.map(name => fs.readFileSync(path.join(root, 'Resources/Web/js/wgsl', name + '.js'), 'utf8')
  .replace(/^import[\s\S]*?from\s+['"][^'"]+['"];\s*$/gm, '')
  .replace(/^export\s+(const|function|async function|let|class)\s/gm, '$1 '))
  .join('\n');
const shaders = vm.runInNewContext(code + '\n;({' + names.join(',') + '})', {}, { timeout: 1000 });
fs.mkdirSync(output, { recursive: true });
const manifest = {};
for (const [name, source] of Object.entries(shaders)) {
  fs.writeFileSync(path.join(output, name + '.wgsl'), source);
  const bindings = [...source.matchAll(/@group\((\d+)\)\s*@binding\((\d+)\)\s*var(?:<([^>]+)>)?\s+(\w+)\s*:\s*([^;]+);/g)]
    .map(([, group, binding, addressSpace, variable, type]) => ({
      group: Number(group), binding: Number(binding), name: variable,
      addressSpace: addressSpace || null, type,
    }));
  manifest[name] = { bindings };
}
fs.writeFileSync(path.join(output, 'bindings.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Exported ${names.length} upstream WGSL shaders to ${output}`);
