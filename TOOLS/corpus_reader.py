from pathlib import Path
import struct,json,sys
MAGIC=b'VXREC001'
def read_one(path,index=0):
 p=Path(path)
 with p.open('rb') as f:
  f.seek(index*65536);hdr=f.read(16)
  if hdr[:8]!=MAGIC:raise ValueError('bad magic')
  n=struct.unpack('<I',hdr[8:12])[0];meta=json.loads(f.read(n));return meta
if __name__=='__main__':print(json.dumps(read_one(sys.argv[1],int(sys.argv[2]) if len(sys.argv)>2 else 0),indent=2))
