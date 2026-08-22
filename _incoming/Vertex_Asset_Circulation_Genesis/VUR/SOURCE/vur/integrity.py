from hashlib import sha256
from pathlib import Path

def sha256_file(path:Path, chunk_size:int=1024*1024)->str:
    digest=sha256()
    with path.open("rb") as f:
        while True:
            chunk=f.read(chunk_size)
            if not chunk: break
            digest.update(chunk)
    return digest.hexdigest()
