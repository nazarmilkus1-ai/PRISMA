import { PARTICIPANT_READ_RPC, PARTICIPANT_RPC, PUBLIC_RPC, PARTICIPANT_SERVER_ROLE_RPC } from "@prisma-eco/contracts";
import { createSupabasePublicClient } from "@/lib/supabase/public";
import { createSupabaseServerClient } from "@/lib/supabase/server";


export async function getPublicServerStatus(){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.serverStatus);
  const node=(data&&typeof data==="object")?data as any:null;
  if(error||!node)return{online:false,players:0,maxPlayers:0,version:null,name:"PRISMA"};
  const last=node.last_heartbeat_at?new Date(node.last_heartbeat_at).getTime():0;
  return{online:String(node.status||"").toUpperCase()==="ONLINE"&&Date.now()-last<120000,players:node.online_players??0,maxPlayers:node.max_players??0,version:node.version??null,name:node.display_name??"PRISMA"};
}

export async function getPublicMarket(kind?:string,query=""){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.market,{p_kind:kind||null,p_query:query.trim(),p_limit:100});
  if(error||!Array.isArray(data))return[];
  return data;
}

export async function getPublicNews(limit=12){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.news,{p_limit:Math.min(Math.max(limit,1),100)});
  return error||!Array.isArray(data)?[]:data;
}

export async function getPublicClans(limit=50){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.clans,{p_limit:Math.min(Math.max(limit,1),100)});
  return error||!Array.isArray(data)?[]:data;
}

export async function getPublicPolls(limit=20){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.polls,{p_limit:Math.min(Math.max(limit,1),100)});
  if(error||!Array.isArray(data))return[];
  return data;
}
export async function getServerRole(){
  const db=await createSupabaseServerClient();
  const {data,error}=await db.rpc(PARTICIPANT_SERVER_ROLE_RPC.get);
  if(error||!data||typeof data!=="object") return {role:"participant",rank:0,priority:0};
  const payload=data as any;
  return {
    role:String(payload.role||"participant"),
    rank:Number(payload.rank||0),
    priority:Number(payload.priority||0),
  };
}

export async function getDashboardData(){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_RPC.dashboard);
  if(error||!data||typeof data!=="object"){
    return{
      user:null,
      application:null,
      reports:[],
      notifications:[],
      preferences:null,
      clan:null,
      membership:null,
      invitations:[],
      clanInvites:{incoming:[],outgoing:[]},
      stats:null,
      achievements:[],
      polls:[],
    };
  }
  const payload=data as any;
  return{
    user:payload.user??null,
    application:payload.application??null,
    reports:Array.isArray(payload.reports)?payload.reports:[],
    notifications:Array.isArray(payload.notifications)?payload.notifications:[],
    preferences:payload.preferences??null,
    clan:payload.clan??null,
    membership:payload.membership??null,
    invitations:Array.isArray(payload.invitations)?payload.invitations:[],
    clanInvites:payload.clanInvites&&typeof payload.clanInvites==="object"
      ?payload.clanInvites
      :{incoming:[],outgoing:[]},
    stats:payload.stats??null,
    achievements:Array.isArray(payload.achievements)?payload.achievements:[],
    polls:Array.isArray(payload.polls)?payload.polls:[],
  };
}

export async function getParticipantClans(limit=100){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.listClans);
  if(error||!Array.isArray(data))return[];
  return data.slice(0,Math.min(Math.max(limit,1),100));
}

export async function getPlayers(query="",limit=100){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.searchPlayers,{p_query:query.trim(),p_limit:Math.min(Math.max(limit,1),300)});
  if(error) return [];
  return Array.isArray(data)?data:[];
}
export async function getPlayerProfile(nickname:string){
  const db=await createSupabaseServerClient();
  const[{data,error},{data:socialData}]=await Promise.all([
    db.rpc(PARTICIPANT_READ_RPC.playerProfile,{p_nickname:nickname}),
    db.rpc(PARTICIPANT_READ_RPC.publicSocial,{p_nickname:nickname}),
  ]);
  if(error||!data||typeof data!=="object")return null;
  const payload=data as any;
  return{
    user:payload.user??null,
    stats:payload.stats??null,
    achievements:Array.isArray(payload.achievements)?payload.achievements:[],
    activity:Array.isArray(payload.activity)?payload.activity:[],
    clan:payload.clan??null,
    membership:payload.membership??null,
    rating_history:Array.isArray(payload.rating_history)?payload.rating_history:[],
    server_role:payload.server_role??"Участник",
    social:socialData&&typeof socialData==="object"?socialData:{visibility:"PRIVATE"},
  };
}
export async function getGlobalSearch(query:string){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.globalSearch,{p_query:query.trim()});
  if(error||!data||typeof data!=="object")return{players:[],clans:[],news:[],wiki:[],market:[]};
  const payload=data as any;
  return{
    players:Array.isArray(payload.players)?payload.players:[],
    clans:Array.isArray(payload.clans)?payload.clans:[],
    news:Array.isArray(payload.news)?payload.news:[],
    wiki:Array.isArray(payload.wiki)?payload.wiki:[],
    market:Array.isArray(payload.market)?payload.market:[],
  };
}
export async function getSocialData(){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.social);
  if(error||!data||typeof data!=="object")return{marriage:null,relationship:null,marriage_history:[],relationship_history:[],marriage_requests_in:[],relationship_requests_in:[],marriage_requests_out:[],relationship_requests_out:[]};
  const payload=data as any;
  return{
    marriage:payload.marriage??null,
    relationship:payload.relationship??null,
    marriage_history:Array.isArray(payload.marriage_history)?payload.marriage_history:[],
    relationship_history:Array.isArray(payload.relationship_history)?payload.relationship_history:[],
    marriage_requests_in:Array.isArray(payload.marriage_requests_in)?payload.marriage_requests_in:[],
    relationship_requests_in:Array.isArray(payload.relationship_requests_in)?payload.relationship_requests_in:[],
    marriage_requests_out:Array.isArray(payload.marriage_requests_out)?payload.marriage_requests_out:[],
    relationship_requests_out:Array.isArray(payload.relationship_requests_out)?payload.relationship_requests_out:[],
  };
}
export async function getClanPage(id:string){
  const db=await createSupabaseServerClient();
  const[{data,error},{data:activityData}]=await Promise.all([
    db.rpc(PARTICIPANT_READ_RPC.clan,{p_clan_id:id}),
    db.rpc(PARTICIPANT_READ_RPC.clanActivity,{p_clan_id:id}),
  ]);
  if(error||!data||typeof data!=="object")return null;
  const payload=data as any;
  return{
    clan:payload.clan??null,
    members:Array.isArray(payload.members)?payload.members:[],
    wars:Array.isArray(payload.wars)?payload.wars:[],
    activity:Array.isArray(activityData)?activityData:(Array.isArray(payload.activity)?payload.activity:[]),
    villages:Array.isArray(payload.villages)?payload.villages:[],
    achievements:Array.isArray(payload.achievements)?payload.achievements:[],
    announcements:Array.isArray(payload.announcements)?payload.announcements:[],
  };
}
export async function getAnalyticsData(period:"24h"|"7d"|"30d"|"all"="30d"){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.analytics,{p_period:period});
  if(error||!data||typeof data!=="object")return null;
  const payload=data as any;
  return{
    period:payload.period??period,
    from:payload.from??null,
    to:payload.to??null,
    server:payload.server??{},
    community:payload.community??{},
    stats:payload.stats??{},
    telemetry:Array.isArray(payload.telemetry)?payload.telemetry:[],
    chatActivity:Array.isArray(payload.chat_activity)?payload.chat_activity:[],
    myChat:Array.isArray(payload.my_chat)?payload.my_chat:[],
    achievements:Number(payload.achievements??0),
    ratingTop:Array.isArray(payload.rating_top)?payload.rating_top:[],
    killsTop:Array.isArray(payload.kills_top)?payload.kills_top:[],
    myRating:payload.my_rating??null,
    myKills:payload.my_kills??null,
  };
}

export async function getRankings(category="rating",limit=100){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.rankings,{p_category:category,p_limit:Math.min(Math.max(limit,1),300)});
  if(error||!Array.isArray(data))return[];
  return data;
}
export async function getSeasons(){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.seasons,{p_limit:30});
  return error||!Array.isArray(data)?[]:data;
}
export async function getSeasonLeaderboard(id:string){const db=await createSupabaseServerClient();const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.seasonLeaderboard,{p_season_id:id});if(error||!data||typeof data!=="object")return{players:[],clans:[]};const payload=data as any;return{players:Array.isArray(payload.players)?payload.players:[],clans:Array.isArray(payload.clans)?payload.clans:[]};}
export async function getMapData(){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.mapData);
  if(error||!data||typeof data!=="object")return{markers:[],villages:[]};
  const payload=data as any;
  return{markers:Array.isArray(payload.markers)?payload.markers:[],villages:Array.isArray(payload.villages)?payload.villages:[]};
}
export async function getTimeline(limit=60){const db=await createSupabaseServerClient();const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.timeline,{p_limit:Math.min(Math.max(limit,1),200)});if(error||!Array.isArray(data))return[];return data;}
export async function getMarket(kind?:string,query=""){const db=await createSupabaseServerClient();const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.market,{p_kind:kind||null,p_query:query.trim(),p_limit:100});if(error||!Array.isArray(data))return[];return data.map((x:any)=>({...x,users:{minecraft_nickname:x.minecraft_nickname}}));}
export async function getMarketInquiries(){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.marketInquiries);
  if(error||!Array.isArray(data))return[];
  return data;
}
export async function getMarketOffers(){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.marketOffers);
  if(error||!Array.isArray(data))return[];
  return data;
}
export async function getParticipantVoting(){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.voting);
  if(error||!Array.isArray(data))return[];
  return data;
}
export async function getParticipantCalendar(){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.calendar);
  if(error||!Array.isArray(data))return[];
  return data;
}
export async function getEvents(limit=50){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.events,{p_limit:Math.min(Math.max(limit,1),100)});
  return error||!Array.isArray(data)?[]:data;
}
export async function getPublicWiki(query=""){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.wiki,{p_query:query.trim().slice(0,100),p_limit:100});
  return error||!Array.isArray(data)?[]:data;
}

export async function getWiki(query=""){
  const db=await createSupabaseServerClient();
  const{data:{user}}=await db.auth.getUser();
  if(!user) return getPublicWiki(query);
  const{data:wikiData,error}=await db.rpc(PARTICIPANT_READ_RPC.wiki,{p_query:query.trim().slice(0,100),p_limit:100});
  return error||!Array.isArray(wikiData)?[]:wikiData;
}
export async function getMedia(limit=60){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.media,{p_limit:Math.min(Math.max(limit,1),100)});
  return error||!Array.isArray(data)?[]:data;
}
export async function getAwards(){
  const db=createSupabasePublicClient();
  const{data,error}=await db.rpc(PUBLIC_RPC.awards,{p_limit:100});
  return error||!Array.isArray(data)?[]:data;
}


export async function getRankingEntry(_userId:string,category="rating"){
  const db=await createSupabaseServerClient();
  const{data,error}=await db.rpc(PARTICIPANT_READ_RPC.rankingEntry,{p_category:category});
  if(error||!data||typeof data!=="object")return null;
  return data;
}

export type CommunityStatus={
  checkedAt:string;
  website:{ok:true};
  database:{ok:boolean;latencyMs:number|null};
  minecraft:{online:boolean;lastSeenSeconds:number|null};
};

/** Public, availability-only status: no addresses, versions or player lists (those stay members-only). */
export async function getCommunityStatus():Promise<CommunityStatus>{
  const db=createSupabasePublicClient();
  const started=Date.now();
  const{data,error}=await db.rpc(PUBLIC_RPC.serverStatus);
  const latency=Date.now()-started;
  const node=(!error&&data&&typeof data==="object")?data as any:null;
  const last=node?.last_heartbeat_at?new Date(node.last_heartbeat_at).getTime():0;
  const age=last?Math.max(0,Math.round((Date.now()-last)/1000)):null;
  return{
    checkedAt:new Date().toISOString(),
    website:{ok:true},
    database:{ok:!error,latencyMs:error?null:latency},
    minecraft:{online:Boolean(node)&&String(node.status||"").toUpperCase()==="ONLINE"&&age!==null&&age<120,lastSeenSeconds:age},
  };
}
