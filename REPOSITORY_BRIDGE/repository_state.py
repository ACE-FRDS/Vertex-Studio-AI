from typing import Optional
from dataclasses import dataclass
from pathlib import Path
import subprocess

@dataclass
class RepositoryState:
    root:str
    branch:Optional[str]
    commit:Optional[str]
    clean:bool

def inspect_git(root:Path)->RepositoryState:
    def run(*args):
        p=subprocess.run(["git","-C",str(root),*args],capture_output=True,text=True)
        return p.stdout.strip() if p.returncode==0 else None
    branch=run("branch","--show-current")
    commit=run("rev-parse","HEAD")
    clean=(run("status","--porcelain")=="")
    return RepositoryState(str(root),branch,commit,clean)
