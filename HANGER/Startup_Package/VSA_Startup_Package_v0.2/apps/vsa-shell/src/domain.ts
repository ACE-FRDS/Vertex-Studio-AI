export type WorkspaceId="ai"|"developer"|"studio"|"web"|"designer"|"portfolio"|"mothership";
export interface Panel { id:string; title:string; facility?:string }
export const workspaces:{id:WorkspaceId;label:string;description:string}[]=[
 {id:"ai",label:"AI",description:"Provider / Model / ARD / Memory"},
 {id:"developer",label:"Developer",description:"Source Explorer / Editor / Build"},
 {id:"studio",label:"Studio",description:"Data / Layout / Script / Runtime"},
 {id:"web",label:"Web",description:"Static / Dynamic / Web App"},
 {id:"designer",label:"Designer",description:"Figma/XD/Fireworks-like visual surface"},
 {id:"portfolio",label:"Portfolio",description:"Developer ID / Projects / Quests"},
 {id:"mothership",label:"Mothership",description:"Facilities / Hangar / Dock / Observatory"}
];
