import argparse
from pathlib import Path
from .server import serve

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--root",required=True)
    a=p.parse_args()
    serve(Path(a.root))

if __name__=="__main__":
    main()
