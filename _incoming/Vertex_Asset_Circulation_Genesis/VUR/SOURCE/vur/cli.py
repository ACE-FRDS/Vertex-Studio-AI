import argparse, json
from pathlib import Path
from .service import VURService

def main():
    p=argparse.ArgumentParser(prog="vur")
    p.add_argument("--root",required=True)
    sub=p.add_subparsers(dest="cmd",required=True)
    sub.add_parser("status")
    i=sub.add_parser("ingest-file")
    i.add_argument("source"); i.add_argument("--namespace",required=True); i.add_argument("--project",required=True)
    i.add_argument("--repository"); i.add_argument("--commit")
    a=p.parse_args(); service=VURService.open(a.root)
    if a.cmd=="status":
        r=service.registry.load()
        print(json.dumps({k:len(r.get(k,[])) for k in ["vcells","units","packs","templates","relations","sources","projects"]},ensure_ascii=False,indent=2))
    elif a.cmd=="ingest-file":
        print(json.dumps(service.ingest.ingest_external_file(Path(a.source),a.namespace,a.project,a.repository,a.commit),ensure_ascii=False,indent=2))
if __name__=="__main__": main()
