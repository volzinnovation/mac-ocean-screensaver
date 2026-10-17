#!/usr/bin/env python3
"""Bundle the original shader modules without introducing a JS dependency."""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
web = root / "Resources" / "Web"
order = ["wgsl/common.js", "wgsl/sim.js", "wgsl/sky.js", "wgsl/ocean.js", "wgsl/post.js", "main.js"]
chunks = []
for name in order:
    source = (web / "js" / name).read_text()
    source = re.sub(r"^import[\s\S]*?from\s+['\"][^'\"]+['\"];\s*$", "", source, flags=re.M)
    source = re.sub(r"^export\s+(const|function|async function|let|class)\s", r"\1 ", source, flags=re.M)
    chunks.append(f"// {name}\n{source}")
page = (web / "index.html").read_text()
page = page.replace('<script type="module" src="js/main.js"></script>', '<script type="module">\n' + '\n'.join(chunks) + '\n</script>')
output = pathlib.Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(page)
print(f"Bundled renderer: {output} ({len(page):,} bytes)")
