"""Snapshot current design for isolated TD synthesis/routing (no bitgen)."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--flow-template', type=Path,
                        help='Prior isolated build supplying flow files when GUI run settings are absent')
    args = parser.parse_args()
    root = args.output.resolve()
    repo = Path(__file__).resolve().parents[1]
    manifest = root / 'source_manifest.json'
    if args.verify:
        entries = json.loads(manifest.read_text(encoding='utf-8'))
        for relative, expected in entries.items():
            for base in (root, repo):
                if digest(base / relative) != expected:
                    raise ValueError(f'Source changed: {base / relative}')
        print(f'PASS: {len(entries)} snapshot/current source hashes match')
        return
    root.mkdir(parents=True, exist_ok=False)
    original = repo / 'reference_edge_project'
    board = root / 'reference_edge_project'
    shutil.copytree(original / 'user_source', board / 'user_source')
    (board / 'td_project').mkdir()
    for name in ('camera_to_dsi_display.al', 'camera_to_dsi_display.sdc'):
        shutil.copyfile(original / 'td_project' / name, board / 'td_project' / name)
    entries = {p.relative_to(root).as_posix(): digest(p)
               for p in board.rglob('*') if p.is_file()}
    manifest.write_text(json.dumps(entries, indent=2), encoding='utf-8')
    al = original / 'td_project/camera_to_dsi_display.al'
    raw = re.sub(r'<Runs>.*?</Runs>', '', al.read_text(encoding='utf-8'), flags=re.S)
    project = ET.fromstring(re.sub(r'&(?!amp;|lt;|gt;|quot;|apos;|#)', '&amp;', raw))
    project.attrib.pop('Path', None)
    for element in project.findall('.//File'):
        source = (al.parent / element.attrib['Path']).resolve()
        mapped = board / source.relative_to(original)
        if not mapped.exists():
            raise FileNotFoundError(mapped)
        element.set('Path', mapped.as_posix())
    for run in ('syn_1', 'phy_1'):
        target = root / run
        target.mkdir()
        ET.ElementTree(project).write(target / 'camera_to_dsi_display.prj', encoding='utf-8', xml_declaration=True)
        baseline = (args.flow_template.resolve() / run if args.flow_template else
                    original / 'td_project/camera_to_dsi_display_Runs' / run)
        settings = (baseline / 'settings.cfg').read_text(encoding='utf-8')
        if args.flow_template:
            settings = settings.replace((args.flow_template.resolve() / 'reference_edge_project').as_posix(), board.as_posix())
        settings = settings.replace('../../../user_source/', (board / 'user_source').as_posix() + '/')
        settings = settings.replace('../../camera_to_dsi_display.sdc', (board / 'td_project/camera_to_dsi_display.sdc').as_posix())
        if run == 'phy_1':
            settings = settings.replace('set end_step bitgen', 'set end_step opt_route')
        (target / 'settings.cfg').write_text(settings, encoding='utf-8')
        flow_file = baseline / ('verify.tcl' if args.flow_template else 'camera_to_dsi_display.tcl')
        flow = flow_file.read_text(encoding='utf-8')
        (target / 'verify.tcl').write_text(flow, encoding='utf-8')
    print(f'Prepared {root}; {len(entries)} files fingerprinted; routing only, no bitgen')


if __name__ == '__main__':
    main()
