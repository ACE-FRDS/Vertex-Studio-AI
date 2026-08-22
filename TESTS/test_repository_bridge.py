from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"REPOSITORY_BRIDGE"))

def test_placeholder():
    assert (ROOT/"REPOSITORY_BRIDGE"/"README.md").exists()
