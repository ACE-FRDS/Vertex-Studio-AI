from pathlib import Path
import argparse,json
from .world import VertexWorld
from .httpui import serve
def main():
 p=argparse.ArgumentParser();p.add_argument("--root",default=str(Path(__file__).resolve().parents[2]));s=p.add_subparsers(dest="cmd",required=True);s.add_parser("status");s.add_parser("providers")
 m=s.add_parser("mission");m.add_argument("intent");m.add_argument("--workspace");m.add_argument("--inject-failure",action="store_true");m.add_argument("--materialize",action="store_true")
 f=s.add_parser("flight");f.add_argument("--workspace",required=True);f.add_argument("--intent",default="Inspect workspace. Make one safe improvement. Build and test. Preserve evidence.");f.add_argument("--materialize",action="store_true")
 u=s.add_parser("ui");u.add_argument("--port",type=int,default=8765);a=p.parse_args();vw=VertexWorld(Path(a.root))
 if a.cmd=="status":print(json.dumps(vw.status(),indent=2,ensure_ascii=False))
 elif a.cmd=="providers":print(json.dumps(vw.discover_providers(),indent=2,ensure_ascii=False))
 elif a.cmd=="mission":print(json.dumps(vw.execute_mission(a.intent,workspace=a.workspace,inject_failure=a.inject_failure,materialize=a.materialize),indent=2,ensure_ascii=False))
 elif a.cmd=="flight":print(json.dumps(vw.execute_mission(a.intent,workspace=a.workspace,materialize=a.materialize),indent=2,ensure_ascii=False))
 else:serve(a.root,a.port)
if __name__=="__main__":main()
