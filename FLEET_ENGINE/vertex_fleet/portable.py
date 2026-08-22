import uuid,hashlib,json
class PortableBay:
 def launch_package(self,mission_id,loadout):
  carrier=str(uuid.uuid4())
  body={"carrier_link":carrier,"mission_id":mission_id,"loadout":loadout,"state":"DOCKED"}
  body["integrity"]=hashlib.sha256(json.dumps(body,sort_keys=True).encode()).hexdigest()
  body["state"]="DEPLOYED";return body
 def return_merge(self,pkg,evidence):
  return {"carrier_link":pkg["carrier_link"],"state":"RETURNED","evidence":evidence,"merge":"VERIFY_REQUIRED"}
 def salvage(self,pkg):
  return {"carrier_link":pkg.get("carrier_link"),"state":"SALVAGE","recoverable":["mission_id","loadout","integrity"]}
