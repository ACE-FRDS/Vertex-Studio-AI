from .envelope import VXNEnvelope
class System:
 def __init__(self,name,bus):self.name=name;self.bus=bus;bus.register(name,self.receive);self.events=[]
 def receive(self,e):self.events.append(e);return {'system':self.name,'accepted':True,'type':e.semantic_type}
 def send(self,target,semantic_type,payload,**kw):return self.bus.send(VXNEnvelope(self.name,target,semantic_type,payload,**kw))
class HyperAgent(System):
 def ingress(self,intent):
  mission={'intent':intent,'goals':[intent],'preserve_scale':True,'contracts':['authority','evidence','continuity']}
  return self.send('VXNRuntime','Mission.Compiled',mission)
class VXNRuntime(System):
 def receive(self,e):
  self.events.append(e)
  if e.semantic_type=='Mission.Compiled':
   return self.send('Aegis','Authority.Verify',{'mission':e.payload,'origin':e.id})
  if e.semantic_type=='Authority.Passed':
   return self.send('Observatory','Execution.Trace',{'mission':e.payload,'state':'EXECUTING'})
  return {'system':self.name,'accepted':True}
class Aegis(System):
 def receive(self,e):
  self.events.append(e)
  m=e.payload.get('mission',{})
  if m.get('irreversible') and e.authority!='HUMAN':return {'decision':'HUMAN_GATE'}
  return self.send('VXNRuntime','Authority.Passed',m,evidence=['aegis-pass'])
