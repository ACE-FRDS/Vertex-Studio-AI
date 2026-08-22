from pathlib import Path
import os,subprocess,shutil
def detect_build_commands(stage):
 stage=Path(stage);cmds=[]
 if (stage/"Cargo.toml").exists() and shutil.which("cargo"):cmds += [["cargo","check","--workspace"],["cargo","test","--workspace"]]
 if (stage/"package.json").exists() and shutil.which("npm"):cmds += [["npm","run","build"]]
 if ((stage/"pyproject.toml").exists() or (stage/"pytest.ini").exists()) and shutil.which("python"):cmds += [["python","-m","pytest","-q"]]
 return cmds
def run_command(cwd,command,timeout=180):
 allow={"cargo":{"check","test","fmt"},"npm":{"run","test"},"python":{"-m"}}
 exe=Path(command[0]).name.lower().removesuffix(".exe")
 if exe not in allow or len(command)<2 or command[1] not in allow[exe]:return {"ok":False,"code":126,"stdout":"","stderr":"not allowlisted"}
 if exe=="python" and command[1:3]!=["-m","pytest"]:return {"ok":False,"code":126,"stdout":"","stderr":"python only pytest"}
 try:
  env=os.environ.copy()
  shared_target=env.get("VERTEX_CARGO_TARGET_DIR")
  if shared_target: env["CARGO_TARGET_DIR"]=shared_target
  p=subprocess.run(command,cwd=cwd,capture_output=True,text=True,timeout=timeout,env=env)
  return {"ok":p.returncode==0,"code":p.returncode,"stdout":p.stdout[-30000:],"stderr":p.stderr[-30000:]}
 except FileNotFoundError as e:return {"ok":False,"code":127,"stdout":"","stderr":str(e)}
 except subprocess.TimeoutExpired:return {"ok":False,"code":124,"stdout":"","stderr":"timeout"}
 except KeyboardInterrupt:return {"ok":False,"code":130,"stdout":"","stderr":"human abort"}
