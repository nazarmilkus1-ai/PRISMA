"use client";

import {useMemo,useState} from "react";

type Marker={id:string;kind:string;title:string;description?:string|null;x:number;y?:number;z:number;color?:string|null;world:string};
type Village={id:string;name:string;center_x:number;center_y:number;center_z:number;radius:number;world:string;clans?:any};
type MapObject=Marker|Village;

function objectTitle(item:MapObject){return "title" in item?item.title:item.name;}
function objectDescription(item:MapObject){return "description" in item?item.description||"Описание не добавлено.":"Описание не добавлено.";}
function objectX(item:MapObject){return "x" in item?item.x:item.center_x;}
function objectY(item:MapObject){return "center_y" in item?item.center_y:item.y;}
function objectZ(item:MapObject){return "z" in item?item.z:item.center_z;}

const KIND_LABEL:Record<string,string>={SPAWN:"Спавн",CITY:"Город",IMPORTANT:"Важное",EVENT:"Событие",CLAN:"Клан"};

export function WorldMap({markers,villages}:{markers:Marker[];villages:Village[]}){
  const [zoom,setZoom]=useState(1),[world,setWorld]=useState("world"),[query,setQuery]=useState(""),[kind,setKind]=useState("ALL"),[selected,setSelected]=useState<{type:"marker";item:Marker}|{type:"village";item:Village}|null>(null);
  const filteredM=useMemo(()=>markers.filter(m=>m.world===world&&(kind==="ALL"||m.kind===kind)&&(!query.trim()||m.title.toLowerCase().includes(query.trim().toLowerCase())||String(m.description||"").toLowerCase().includes(query.trim().toLowerCase()))),[markers,world,kind,query]);
  const filteredV=useMemo(()=>villages.filter(v=>v.world===world&&(!query.trim()||v.name.toLowerCase().includes(query.trim().toLowerCase()))),[villages,world,query]);
  const X=(x:number)=>50+(x/12500)*44*zoom; const Y=(z:number)=>50+(z/12500)*44*zoom;
  const kinds=useMemo(()=>Array.from(new Set(markers.filter(m=>m.world===world).map(m=>m.kind))),[markers,world]);

  return <div className="overflow-hidden rounded-3xl border bg-[#eef2ef] dark:bg-[#17201b]">
    <div className="prisma-glass-surface border-b px-4 py-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div><p className="text-sm font-semibold">PRISMA World Map</p><p className="text-xs text-[var(--muted-foreground)]">Лёгкая координатная карта без Dynmap</p></div>
        <div className="flex items-center gap-2"><select value={world} onChange={e=>{setWorld(e.target.value);setSelected(null)}} className="rounded-lg border bg-[var(--card)] px-2 py-1.5 text-xs"><option value="world">Обычный мир</option><option value="world_nether">Незер</option><option value="world_the_end">Край</option></select><button type="button" onClick={()=>setZoom(z=>Math.min(2,z+0.2))} className="rounded-lg border px-2.5 py-1.5 text-sm">+</button><button type="button" onClick={()=>setZoom(z=>Math.max(.6,z-.2))} className="rounded-lg border px-2.5 py-1.5 text-sm">−</button></div>
      </div>
      <div className="mt-3 grid gap-2 sm:grid-cols-[1fr_180px_auto]">
        <input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Поиск точки или города" className="prisma-glass-control h-9 w-full rounded-lg border px-3 py-2 text-xs"/>
        <select value={kind} onChange={e=>setKind(e.target.value)} className="prisma-glass-control h-9 w-full rounded-lg border px-3 py-2 text-xs"><option value="ALL">Все точки</option>{kinds.map(k=><option key={k} value={k}>{KIND_LABEL[k]||k}</option>)}</select>
        <span className="rounded-lg border px-3 py-2 text-center text-xs text-[var(--muted-foreground)]">{filteredM.length+filteredV.length} объектов</span>
      </div>
    </div>

    {selected?<div className="prisma-glass-surface border-b px-4 py-3">
      <div className="flex items-start justify-between gap-4">
        <div><p className="text-[10px] font-semibold uppercase tracking-[.18em] text-[var(--primary)]">{selected.type==="marker"?(KIND_LABEL[selected.item.kind]||selected.item.kind):"Территория клана"}</p><h3 className="mt-1 font-semibold">{objectTitle(selected.item)}</h3><p className="mt-1 text-xs text-[var(--muted-foreground)]">{objectDescription(selected.item)}</p><p className="mt-2 font-mono text-[11px] text-[var(--muted-foreground)]">X {Math.round(objectX(selected.item))} · Y {Math.round(objectY(selected.item)??64)} · Z {Math.round(objectZ(selected.item))}</p></div>
        <button type="button" onClick={()=>setSelected(null)} className="rounded-lg border px-2.5 py-1.5 text-xs">Закрыть</button>
      </div>
    </div>:null}

    <div className="relative">
      <svg viewBox="0 0 100 100" className="block aspect-square w-full">
        <rect x="0" y="0" width="100" height="100" fill="currentColor" opacity=".025"/>
        {Array.from({length:11}).map((_,i)=><g key={i}><line x1={i*10} y1="0" x2={i*10} y2="100" stroke="currentColor" opacity=".08"/><line x1="0" y1={i*10} x2="100" y2={i*10} stroke="currentColor" opacity=".08"/></g>)}
        <line x1="50" y1="2" x2="50" y2="98" stroke="currentColor" opacity=".18"/><line x1="2" y1="50" x2="98" y2="50" stroke="currentColor" opacity=".18"/>
        {filteredV.map(v=><g key={v.id} onClick={()=>setSelected({type:"village",item:v})} className="cursor-pointer">
          <circle cx={X(v.center_x)} cy={Y(v.center_z)} r={Math.max(1.2,Math.min(12,v.radius/160))} fill={v.clans?.color||"var(--primary)"} opacity=".16" stroke={v.clans?.color||"var(--primary)"} strokeWidth=".35"/>
          <text x={X(v.center_x)} y={Y(v.center_z)-2} textAnchor="middle" fontSize="2.2" fill="currentColor">{v.name}</text>
        </g>)}
        {filteredM.map(m=><g key={m.id} onClick={()=>setSelected({type:"marker",item:m})} className="cursor-pointer">
          <circle cx={X(m.x)} cy={Y(m.z)} r="1.3" fill={m.color||"var(--primary)"} stroke="white" strokeWidth=".35"/>
          <title>{m.title}</title>
        </g>)}
        <text x="4" y="96" fontSize="2.3" fill="currentColor" opacity=".65">−12 500</text><text x="84" y="96" fontSize="2.3" fill="currentColor" opacity=".65">+12 500</text>
      </svg>
    </div>
    {!filteredM.length&&!filteredV.length?<p className="prisma-glass-surface border-t px-4 py-6 text-center text-xs text-[var(--muted-foreground)]">По этому фильтру ничего не найдено.</p>:null}
    {(filteredM.length||filteredV.length)?<div className="prisma-glass-surface border-t p-4">
      <div className="mb-3 flex items-center justify-between gap-3"><p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">Объекты</p><span className="text-[10px] text-[var(--muted-foreground)]">Показано до 24</span></div>
      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {[...filteredV.map(v=>({type:"village" as const,item:v,key:"v:"+v.id})),...filteredM.map(m=>({type:"marker" as const,item:m,key:"m:"+m.id}))].slice(0,24).map(entry=><button key={entry.key} type="button" onClick={()=>setSelected(entry)} className="prisma-glass-surface rounded-xl border p-3 text-left transition-colors hover:border-[var(--primary)]/40 hover:bg-white/[0.055]">
          <div className="flex items-start justify-between gap-2"><span className="truncate text-xs font-semibold">{objectTitle(entry.item)}</span><span className="shrink-0 text-[9px] text-[var(--muted-foreground)]">{entry.type==="marker"?(KIND_LABEL[entry.item.kind]||entry.item.kind):"Территория"}</span></div>
          <p className="mt-1 font-mono text-[10px] text-[var(--muted-foreground)]">X {Math.round(objectX(entry.item))} · Z {Math.round(objectZ(entry.item))}</p>
        </button>)}
      </div>
    </div>:null}
  </div>
}