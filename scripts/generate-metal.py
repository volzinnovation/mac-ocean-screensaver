#!/usr/bin/env python3
"""Regenerate vendored MSL from the original WGSL. Normal builds need no Node/Naga.

Run with Node >=20 and either --naga-wasm PATH, or --download-compiler to fetch
the integrity-pinned 0.1.0 WASI build into build/tools. Only its WASM is executed.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.1.0"
ARCHIVE_URL = f"https://registry.npmjs.org/naga-wasi-cli/-/naga-wasi-cli-{VERSION}.tgz"
ARCHIVE_SHA512 = "314a947be5eed9e45b45ff140a06d7487a06c773fc3c5e2b8ee0f64351289cd15fbd3e7b8987159db6508b4a48940d86c4703e2b85fc43d08ac63a819c55bb10"


def source_hashes():
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT / "Resources/Web/js/wgsl").glob("*.js"))}


def patch_msl(source, bindings):
    """Replace Naga's fake resource slots with original WebGPU binding indices.

    The standalone CLI has no MSL binding map argument. This mechanical patch
    gives each resource its original WGSL binding within its Metal namespace.
    The generated function body and math are untouched.
    """
    by_name = {item["name"]: item for item in bindings}

    def resource(match):
        line, name = match[0], match[1]
        # Naga's unused robustness-size argument is unnecessary: these shaders
        # have no arrayLength(), and the CLI emits unchecked indexing.
        if name == "_buffer_sizes":
            return ""
        item = by_name.get(name) or by_name.get(name.rstrip("_"))
        if item is None:
            raise ValueError(f"Cannot map generated Metal argument {name}")
        kind = "sampler" if item["type"] == "sampler" else "texture" if item["type"].startswith("texture") else "buffer"
        return line.replace("[[user(fake0)]]", f"[[{kind}({item['binding']})]]")

    source = re.sub(r"^.*?\b(\w+)\s*\[\[user\(fake0\)\]\].*$", resource, source, flags=re.M)
    if re.search(r"\b_buffer_sizes\b", source):
        raise ValueError("Shader actually uses Naga's buffer-size argument; binding support is required")

    def local_threadgroups(match):
        head, arguments = match[1], match[2]
        locals_ = []

        def take(argument):
            locals_.append(f"    threadgroup {argument[1]} {argument[2]};")
            return ""

        # Make fixed-size WGSL workgroup arrays static Metal threadgroup storage,
        # avoiding dynamic threadgroup arguments and native allocation metadata.
        arguments = re.sub(r"^, threadgroup (\w+)& (\w+)\s*$", take, arguments, flags=re.M)
        return head + arguments + "\n) {\n" + "\n".join(locals_)

    source = re.sub(r"(^kernel [^\n]+\(\n)([\s\S]*?)\n\) \{", local_threadgroups, source, flags=re.M)
    if "[[user(fake" in source:
        raise ValueError("Unmapped Metal resource slots remain")
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", default=os.environ.get("NODE", shutil.which("node") or "node"))
    parser.add_argument("--naga-wasm", type=Path, default=os.environ.get("NAGA_WASM"))
    parser.add_argument("--download-compiler", action="store_true")
    parser.add_argument("--check", action="store_true", help="Check vendored MSL source hashes without Node or downloads")
    args = parser.parse_args()
    output = ROOT / "Resources/Metal"
    if args.check:
        metadata = json.loads((output / "Bindings.json").read_text())
        if metadata["sourceSHA256"] != source_hashes():
            raise SystemExit("WGSL changed: regenerate Metal with scripts/generate-metal.py")
        for name, item in metadata["shaders"].items():
            if hashlib.sha256((output / f"{name}.metal").read_bytes()).hexdigest() != item["metalSHA256"]:
                raise SystemExit(f"Generated Metal changed: {name}")
        print("Vendored Metal matches the original WGSL source hashes")
        return
    version = subprocess.check_output([args.node, "--version"], text=True).strip()
    if int(version.removeprefix("v").split(".")[0]) < 20:
        raise SystemExit("Shader regeneration requires Node >=20; pass --node /path/to/node")
    wasm = Path(args.naga_wasm).resolve() if args.naga_wasm else None
    if wasm is None and args.download_compiler:
        compiler_directory = ROOT / "build/tools" / f"naga-wasi-cli-{VERSION}"
        compiler_directory.mkdir(parents=True, exist_ok=True)
        archive = urllib.request.urlopen(ARCHIVE_URL, timeout=30).read()
        if hashlib.sha512(archive).hexdigest() != ARCHIVE_SHA512:
            raise SystemExit("Compiler archive integrity check failed")
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as package:
            for name in ("wasi/naga.wasm", "LICENSE-MIT", "LICENSE-APACHE"):
                data = package.extractfile("package/" + name).read()
                destination = compiler_directory / Path(name).name
                destination.write_bytes(data)
        wasm = compiler_directory / "naga.wasm"
    if wasm is None or not wasm.is_file():
        raise SystemExit("Pass --naga-wasm PATH or --download-compiler (build-time tool only)")
    working_directory = ROOT / "build/generated-wgsl"
    subprocess.run([args.node, str(ROOT / "scripts/export-wgsl.mjs"), str(working_directory)], check=True)
    shaders = json.loads((working_directory / "bindings.json").read_text())
    output.mkdir(parents=True, exist_ok=True)
    for name, item in shaders.items():
        subprocess.run([args.node, "--no-warnings", str(ROOT / "scripts/run-naga-wasi.mjs"), str(wasm),
                        "--metal-version", "2.4", f"{name}.wgsl", f"{name}.metal"], cwd=working_directory, check=True)
        original = (working_directory / f"{name}.metal").read_text()
        generated = ("// Generated from Resources/Web/js/wgsl by scripts/generate-metal.py.\n"
                     "// Original ocean renderer: Noniv/web-ocean, MIT; see THIRD_PARTY_NOTICES.md.\n"
                     "// Edit the WGSL source and regenerate; native builds use this vendored MSL.\n" + patch_msl(original, item["bindings"]))
        (output / f"{name}.metal").write_text(generated)
        item["entryPoints"] = {stage: function for stage, function in re.findall(r"^(kernel|vertex|fragment) \w+ (\w+)\(", generated, re.M)}
        group = re.search(r"@workgroup_size\(([^)]+)\)", (working_directory / f"{name}.wgsl").read_text())
        if group:
            dimensions = [int(value.strip()) for value in group[1].split(",")]
            item["threadsPerThreadgroup"] = dimensions + [1] * (3 - len(dimensions))
        item["metalSHA256"] = hashlib.sha256(generated.encode()).hexdigest()
        for binding in item["bindings"]:
            binding["metalIndex"] = binding["binding"]
            binding["metalNamespace"] = "sampler" if binding["type"] == "sampler" else "texture" if binding["type"].startswith("texture") else "buffer"
    metadata = {
        "generator": f"naga-wasi-cli@{VERSION}", "generatorArchiveSHA512": ARCHIVE_SHA512,
        "sourceSHA256": source_hashes(),
        "notes": "Bindings retain original WGSL indices in separate Metal namespaces. Workgroup arrays are static. Clip space is unchanged.",
        "shaders": shaders,
    }
    (output / "Bindings.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Generated {len(shaders)} native Metal shaders in {output}")


if __name__ == "__main__":
    main()
