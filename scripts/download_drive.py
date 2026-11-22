#!/usr/bin/env python3
"""
Downloads a file from Google Drive via gdown.
Handles both full URLs and raw file IDs, and auto-detects archive/package types.
"""
import os
import re
import sys

def main():
    if len(sys.argv) < 3:
        print("Usage: download_drive.py <url_or_id> <output_path>", file=sys.stderr)
        sys.exit(1)

    url_or_id = sys.argv[1].strip()
    out = sys.argv[2].strip()

    import gdown

    m = re.search(r'/d/([a-zA-Z0-9_-]+)', url_or_id) or re.search(r'id=([a-zA-Z0-9_-]+)', url_or_id)
    file_id = m.group(1) if m else url_or_id

    cookies_file = os.environ.get('GDRIVE_COOKIES_PATH') or ('cookies.txt' if os.path.exists('cookies.txt') else None)
    kwargs = {'quiet': False}
    if cookies_file and os.path.exists(cookies_file):
        print(f"Using Google Drive cookies: {cookies_file} ({os.path.getsize(cookies_file)} bytes)", flush=True)
        kwargs['use_cookies'] = True
        kwargs['cookies_file'] = cookies_file

    print(f"Downloading from Google Drive: {file_id} -> {out}", flush=True)
    res = gdown.download(id=file_id, output=out, resume=True, **kwargs)

    if not res or not os.path.exists(out) or os.path.getsize(out) == 0:
        print(f"Direct ID download failed, retrying with raw URL...", flush=True)
        res = gdown.download(url=url_or_id, output=out, resume=True, **kwargs)

    if not os.path.exists(out) or os.path.getsize(out) == 0:
        print(f"ERROR: Downloaded file '{out}' is missing or empty!", file=sys.stderr)
        sys.exit(1)

    print(f"Download successful: {out} ({os.path.getsize(out)} bytes)", flush=True)

    # Magic inspection and renaming
    with open(out, 'rb') as f:
        hdr = f.read(65536)

    out_dir = os.path.dirname(out) or '.'
    base_name = os.path.basename(out)
    prefix = base_name.replace('_dl', '')

    if hdr.startswith(b'PK\x03\x04'):
        print(f"Detected ZIP archive, extracting into {out_dir}...", flush=True)
        os.system(f'unzip -q "{out}" -d "{out_dir}" && rm -f "{out}"')
    elif len(hdr) >= 0x104 and hdr[0x100:0x104] == b'HEAD':
        ext = 'xcz' if b'.ncz' in hdr else 'xci'
        target = os.path.join(out_dir, f"{prefix}.{ext}")
        print(f"Detected {ext.upper()} file, renaming to {target}...", flush=True)
        os.rename(out, target)
    elif hdr.startswith(b'PFS0') or hdr.startswith(b'NSZ'):
        ext = 'nsz' if (b'.ncz' in hdr or hdr.startswith(b'NSZ')) else 'nsp'
        target = os.path.join(out_dir, f"{prefix}.{ext}")
        print(f"Detected {ext.upper()} file, renaming to {target}...", flush=True)
        os.rename(out, target)
    else:
        target = os.path.join(out_dir, f"{prefix}.nsp")
        print(f"Detected standard NSP file, renaming to {target}...", flush=True)
        os.rename(out, target)

if __name__ == '__main__':
    main()
