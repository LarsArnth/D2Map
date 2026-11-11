#!/usr/bin/env python3
"""Uploader den pakkede addon til CurseForge.

    ./scripts/pak.sh                       # lav dist/D2Map-<version>.zip først
    ./scripts/udgiv.py --toer              # vis hvad der ville ske, upload intet
    ./scripts/udgiv.py                     # upload som «release»
    ./scripts/udgiv.py --type beta --aendringer "Rettet: …"

Projektet skal findes i forvejen (det kan API'et ikke oprette). Scriptet skal
bruge to ting:

  Projekt-id   `## X-Curse-Project-ID: <id>` i D2Map/D2Map.toc, eller --projekt <id>.
               Id'et står på projektets side på CurseForge.
  Token        CURSEFORGE_API_TOKEN i miljøet, eller i filen
               ~/.config/d2map/curseforge.env som  CURSEFORGE_API_TOKEN=…
               (chmod 600). Tokenet laves på authors.curseforge.com under
               API Tokens. Det skrives aldrig ud og hører ikke hjemme i git.

Spilversionen findes ved at spørge CurseForge om dens liste og vælge den, der
passer til interface-nummeret i toc-filen (16001 = WoW: Forever 1.60.x).
Rammer det forkert, så brug --spilversion <id> (listen vises med --versioner).
"""
import argparse
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request
import uuid

ROD = pathlib.Path(__file__).resolve().parent.parent
TOC = ROD / "D2Map" / "D2Map.toc"
TOKENFIL = pathlib.Path.home() / ".config" / "d2map" / "curseforge.env"
API = "https://wow.curseforge.com/api"
# Addons, D2Map kan bruge, men ikke kræver (CurseForges korte navne). Factoruide
# er ikke med: dens toc-fil har intet CurseForge-id, så den ligger ikke dér.
VALGFRIE = ["questie"]


def toc_felt(navn: str) -> str | None:
    m = re.search(rf"^## {re.escape(navn)}:\s*(.+?)\s*$", TOC.read_text(), re.M)
    return m.group(1) if m else None


def token() -> str:
    værdi = os.environ.get("CURSEFORGE_API_TOKEN")
    if not værdi and TOKENFIL.exists():
        if TOKENFIL.stat().st_mode & 0o077:
            sys.exit(f"{TOKENFIL} kan læses af andre. Kør: chmod 600 {TOKENFIL}")
        for linje in TOKENFIL.read_text().splitlines():
            if linje.startswith("CURSEFORGE_API_TOKEN="):
                værdi = linje.split("=", 1)[1].strip().strip("'\"")
    if not værdi:
        sys.exit(f"Mangler token: sæt CURSEFORGE_API_TOKEN eller læg det i {TOKENFIL}")
    return værdi


def kald(sti: str, tok: str, data: bytes | None = None, indholdstype: str | None = None):
    hoveder = {"X-Api-Token": tok, "User-Agent": "D2Map-udgiv/1"}
    if indholdstype:
        hoveder["Content-Type"] = indholdstype
    anmodning = urllib.request.Request(API + sti, data=data, headers=hoveder)
    try:
        with urllib.request.urlopen(anmodning, timeout=120) as svar:
            return json.loads(svar.read().decode())
    except urllib.error.HTTPError as fejl:
        # CurseForges fejltekst siger som regel præcist, hvad der er galt.
        sys.exit(f"CurseForge svarede {fejl.code} på {sti}: {fejl.read().decode(errors='replace')[:500]}")
    except urllib.error.URLError as fejl:
        sys.exit(f"Kunne ikke nå CurseForge: {fejl.reason}")


def find_spilversion(versioner: list[dict], interface: str) -> dict | None:
    """16001 → den nyeste version, der hedder 1.60.x."""
    stor, lille = int(interface) // 10000, int(interface) // 100 % 100
    forstavelse = f"{stor}.{lille}."
    passer = [v for v in versioner if str(v.get("name", "")).startswith(forstavelse)]

    def nøgle(v):
        return [int(t) if t.isdigit() else 0 for t in re.split(r"[.\-]", v["name"])]

    return max(passer, key=nøgle) if passer else None


def multipart(felter: dict[str, str], filnavn: str, indhold: bytes) -> tuple[bytes, str]:
    grænse = "----d2map" + uuid.uuid4().hex
    dele = []
    for navn, værdi in felter.items():
        dele.append(f'--{grænse}\r\nContent-Disposition: form-data; name="{navn}"\r\n\r\n{værdi}\r\n'.encode())
    dele.append(
        f'--{grænse}\r\nContent-Disposition: form-data; name="file"; filename="{filnavn}"\r\n'
        f"Content-Type: application/zip\r\n\r\n".encode() + indhold + b"\r\n"
    )
    dele.append(f"--{grænse}--\r\n".encode())
    return b"".join(dele), f"multipart/form-data; boundary={grænse}"


def main() -> None:
    p = argparse.ArgumentParser(description="Upload D2Map til CurseForge.")
    p.add_argument("--toer", action="store_true", help="vis hvad der ville ske, upload intet")
    p.add_argument("--versioner", action="store_true", help="vis CurseForges spilversioner og stop")
    p.add_argument("--projekt", help="projektets id (ellers X-Curse-Project-ID i toc-filen)")
    p.add_argument("--spilversion", type=int, help="CurseForges id for spilversionen (ellers gættes den)")
    p.add_argument("--type", choices=["release", "beta", "alpha"], default="release")
    p.add_argument("--aendringer", help="ændringslog (Markdown)")
    a = p.parse_args()

    version = toc_felt("Version")
    interface = (toc_felt("Interface") or "").split(",")[0].strip()
    zipfil = ROD / "dist" / f"D2Map-{version}.zip"
    projekt = a.projekt or toc_felt("X-Curse-Project-ID")
    ændringer = a.aendringer or f"D2Map {version}. Changes: https://github.com/LarsArnth/D2Map/commits/main"

    print(f"Version {version}, interface {interface}, fil {zipfil.relative_to(ROD)}")
    if not zipfil.exists():
        sys.exit("Zip-filen findes ikke. Kør ./scripts/pak.sh først.")

    if a.toer and not (os.environ.get("CURSEFORGE_API_TOKEN") or TOKENFIL.exists()):
        print(f"Tørløb uden token: ville uploade {zipfil.stat().st_size} bytes som «{a.type}» "
              f"til projekt {projekt or '(mangler id)'}.")
        print("Spilversionen kan først findes, når der er et token.")
        return

    tok = token()
    versioner = kald("/game/versions", tok)
    if a.versioner:
        for v in sorted(versioner, key=lambda v: str(v.get("name"))):
            print(f"{v['id']:>8}  {v.get('name')}")
        return

    if a.spilversion:
        spil = next((v for v in versioner if v["id"] == a.spilversion), None)
        if not spil:
            sys.exit(f"CurseForge kender ikke spilversion {a.spilversion}. Se listen med --versioner.")
    else:
        spil = find_spilversion(versioner, interface)
        if not spil:
            sys.exit(f"Fandt ingen spilversion til interface {interface}. Se listen med --versioner "
                     "og vælg med --spilversion <id>.")
    print(f"Spilversion: {spil['name']} (id {spil['id']})")

    if not projekt:
        sys.exit("Mangler projekt-id: skriv '## X-Curse-Project-ID: <id>' i D2Map.toc, eller brug --projekt <id>.")

    metadata = {
        "changelog": ændringer,
        "changelogType": "markdown",
        "displayName": f"D2Map {version}",
        "gameVersions": [spil["id"]],
        "releaseType": a.type,
        "relations": {"projects": [{"slug": slug, "type": "optionalDependency"} for slug in VALGFRIE]},
    }
    print(f"Projekt {projekt}, type «{a.type}», valgfrie afhængigheder: {', '.join(VALGFRIE)}")
    if a.toer:
        print("Tørløb: intet uploadet. Metadata:")
        print(json.dumps(metadata, indent=2, ensure_ascii=False))
        return

    krop, indholdstype = multipart({"metadata": json.dumps(metadata)}, zipfil.name, zipfil.read_bytes())
    svar = kald(f"/projects/{projekt}/upload-file", tok, krop, indholdstype)
    print(f"Uploadet. CurseForges fil-id: {svar.get('id')}")


if __name__ == "__main__":
    main()
