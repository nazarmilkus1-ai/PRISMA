"use client";
import {useState} from "react";
import {useRouter} from "next/navigation";
import {Button,Card,CardContent,CardHeader,CardTitle,Textarea} from "@prisma-eco/ui";

export function ApplicationReview({applicationId,status}:{applicationId:string;status:string}){
 const router=useRouter();const [reason,setReason]=useState("");const [pending,setPending]=useState(false);const [error,setError]=useState("");
 async function act(action:"approve"|"reject"){
  setPending(true);setError("");
  try{
   const r=await fetch("/admin/api/applications/"+applicationId,{method:"PATCH",headers:{"content-type":"application/json"},body:JSON.stringify({action,reason:reason.trim()||undefined})});
   const p=await r.json().catch(()=>({}));if(!r.ok)throw new Error(p.error||"Операция не выполнена.");router.refresh();
  }catch(e){setError(e instanceof Error?e.message:"Операция не выполнена.");}finally{setPending(false);}
 }
 return <Card><CardHeader><CardTitle>Решение</CardTitle></CardHeader><CardContent className="space-y-3">
  {status==="PENDING"?<><Textarea value={reason} onChange={e=>setReason(e.target.value)} placeholder="Причина отклонения — необязательно" maxLength={500}/>{error?<p role="alert" className="text-xs text-destructive">{error}</p>:null}<div className="flex gap-2"><Button type="button" disabled={pending} onClick={()=>act("approve")}>Принять</Button><Button type="button" variant="destructive" disabled={pending} onClick={()=>act("reject")}>Отклонить</Button></div></>:<p className="text-sm text-muted-foreground">Заявка уже имеет статус «{status==="ACCEPTED"?"принята":"отклонена"}».</p>}
 </CardContent></Card>;
}
