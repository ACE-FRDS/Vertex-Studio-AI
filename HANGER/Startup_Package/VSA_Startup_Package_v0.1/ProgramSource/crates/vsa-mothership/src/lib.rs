use vsa_foundation::Id;
#[derive(Debug,Clone,Copy,PartialEq,Eq)]
pub enum FacilityKind {
    CommandBridge, Base, Dock, Warehouse, Hangar, Catapult, Observatory,
    Arsenal, ControlTower, SupplyDepot, Library, ProvingGround, Quarantine
}
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct Facility { pub id:Id,pub name:String,pub kind:FacilityKind,pub capabilities:Vec<String> }
pub fn default_mothership()->Vec<Facility>{
    use FacilityKind::*;
    [
        ("Command Bridge",CommandBridge,vec!["ARD","Party","Human Gate"]),
        ("Dock",Dock,vec!["Build","Repair","Migration","Validation"]),
        ("Warehouse",Warehouse,vec!["Models","Assets","Packages","RCC"]),
        ("Hangar",Hangar,vec!["Agents","Drones","Portable Units"]),
        ("Catapult",Catapult,vec!["Mission Dispatch"]),
        ("Observatory",Observatory,vec!["Telemetry","Benchmark","Failure Analysis"]),
        ("Arsenal",Arsenal,vec!["Code","VXN","UI","Package Build"]),
        ("Control Tower",ControlTower,vec!["Provider","Runtime","Jobs","Ports"]),
        ("Supply Depot",SupplyDepot,vec!["Capability on Demand","Hot Reinforcement"]),
        ("Library",Library,vec!["VCC","Knowledge","Genesis"]),
        ("Proving Ground",ProvingGround,vec!["LLM Benchmark","RCC A/B Test"]),
        ("Quarantine",Quarantine,vec!["Sandbox","Untrusted Cartridge"]),
    ].into_iter().map(|(n,k,c)|Facility{id:Id::new("facility"),name:n.into(),kind:k,capabilities:c.into_iter().map(str::to_string).collect()}).collect()
}
