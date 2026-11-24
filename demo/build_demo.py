import json,sys
S="/tmp/claude-0/-home-user/b60a969a-8d46-51f0-a94e-7b84d163aff6/scratchpad"
src=open(S+"/demo/index.html").read()
cur=json.load(open(S+"/cars/curated.json"))
import os
for c in cur:
    if c.get("img"):
        png=os.path.basename(c["img"]).replace(".jpg",".png")
        if os.path.exists(S+"/cars/cut/"+png): c["img"]="img/"+png; c["cut"]=True
out=src.replace("__CURATED__",json.dumps(cur,ensure_ascii=False).replace("</","<\\/"))
open(S+"/demo/carvideo-demo.html","w").write(out)
import os; os.makedirs(S+"/demotest",exist_ok=True)
open(S+"/demotest/index.html","w").write(out.replace("https://cdn.jsdelivr.net/npm/three@0.160.0/","/three/"))
