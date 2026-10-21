"""Rebuild an untouched Git checkpoint in isolation, preserving the worktree.

No checkout/reset, source parameter overrides, or changes to production outputs.
The current TD runner templates are reused with historical project sources/SDC.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
from zipfile import ZipFile
import xml.etree.ElementTree as ET


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--ref", default="checkpoint-20261016-eram-linebuffers")
    parser.add_argument("--verify", action="store_true", help="Check prepared source hashes without changing any files")
    args = parser.parse_args()
    if args.verify:
        root = args.output.resolve()
        manifest = json.loads((root / "history_manifest.json").read_text(encoding="utf-8"))
        if digest(root / "checkpoint_source.zip") != manifest["archive_sha256"]:
            raise ValueError("Historical archive hash changed")
        for relative, expected in manifest["source_files"].items():
            if digest(root / "source" / relative) != expected:
                raise ValueError("Historical source changed: " + relative)
        print(json.dumps({"commit": manifest["commit"], "verified_files": len(manifest["source_files"]),
                          "source_modified": False}, indent=2))
        return
    repo = Path(__file__).resolve().parents[1]
    commit = subprocess.check_output(
        ["git", "rev-parse", "--verify", args.ref + "^{commit}"], cwd=repo
    ).decode().strip()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    archive_path = root / "checkpoint_source.zip"
    subprocess.run(["git", "archive", "--format=zip", "--output=" + str(archive_path), commit],
                   cwd=repo, check=True)
    source = root / "source"
    with ZipFile(archive_path) as archive:
        for name in archive.namelist():
            parts = PurePosixPath(name)
            if parts.is_absolute() or ".." in parts.parts or "\\" in name:
                raise ValueError("Unsafe archive entry: " + name)
        archive.extractall(source)
    board = source / "reference_edge_project"
    al = board / "td_project/camera_to_dsi_display.al"
    raw = re.sub(r"<Runs>.*?</Runs>", "", al.read_text(encoding="utf-8"), flags=re.S)
    project = ET.fromstring(re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;|#)", "&amp;", raw))
    project.attrib.pop("Path", None)
    for element in project.findall(".//File"):
        path = (al.parent / element.attrib["Path"]).resolve()
        if not path.is_relative_to(source) or not path.exists():
            raise ValueError("Missing or external historical source: " + str(path))
        element.set("Path", path.as_posix())
    production_runs = repo / "reference_edge_project/td_project/camera_to_dsi_display_Runs"
    for run in ("syn_1", "phy_1"):
        run_dir = root / run
        run_dir.mkdir()
        ET.ElementTree(project).write(run_dir / "camera_to_dsi_display.prj",
                                      encoding="utf-8", xml_declaration=True)
        template = production_runs / run
        settings = (template / "settings.cfg").read_text(encoding="utf-8")
        settings = settings.replace("../../../user_source/", (board / "user_source").as_posix() + "/")
        settings = settings.replace("../../camera_to_dsi_display.sdc",
                                    (board / "td_project/camera_to_dsi_display.sdc").as_posix())
        (run_dir / "settings.cfg").write_text(settings, encoding="utf-8")
        flow = (template / "camera_to_dsi_display.tcl").read_text(encoding="utf-8")
        flow = flow.replace("  bitgen -bit $prj_name.bit",
                            "  set_param bitgen compress on\n  bitgen -bit $prj_name.bit")
        (run_dir / "verify.tcl").write_text(flow, encoding="utf-8")
    # Preserve and fingerprint EVERY historical design source before invoking TD.
    fingerprints = {p.relative_to(source).as_posix(): digest(p)
                    for p in sorted((board / "user_source").rglob("*")) if p.is_file()}
    fingerprints[al.relative_to(source).as_posix()] = digest(al)
    sdc = board / "td_project/camera_to_dsi_display.sdc"
    fingerprints[sdc.relative_to(source).as_posix()] = digest(sdc)
    manifest = {"ref": args.ref, "commit": commit, "archive_sha256": digest(archive_path),
                "source_files": fingerprints, "source_modified": False,
                "runner_templates": str(production_runs), "production_outputs_modified": False}
    (root / "history_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({"output": str(root), "ref": args.ref, "commit": commit,
                      "source_files": len(fingerprints), "source_modified": False}, indent=2))


if __name__ == "__main__":
    main()
