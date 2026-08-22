from pathlib import Path
from .domain import VirtualFile

class OverlayExplorer:
    def __init__(self,real_root:Path,overlay_root:Path):
        self.real_root=real_root
        self.overlay_root=overlay_root
    def project_file(self,relative:str,state:str="REAL_CONFIRMED")->VirtualFile:
        real=self.real_root/relative
        overlay=self.overlay_root/relative
        return VirtualFile(
            path=relative,
            state=state,
            real_path=str(real) if real.exists() else None,
            overlay_path=str(overlay) if overlay.exists() else None
        )
