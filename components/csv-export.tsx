'use client';
import {useState,useRef} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';
import type {Data} from '../lib/finance';
import {today} from '../lib/finance';
import {readData} from '../lib/data';
import {accountBalance} from '../lib/intelligence';
import {financialCsv} from '../lib/csv-export';
import {Download} from 'lucide-react';

export default function CsvExport({data,uid,db,demo,house}:{data:Data;uid:string;db:SupabaseClient|null;demo:boolean;house:string}){
 const [scope,setScope]=useState<'personal'|'household'>('personal'),[selectedHouse,setSelectedHouse]=useState(house),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState('');
 const inFlight=useRef(false);
 const houses=data.households.filter(h=>data.household_members.some(m=>m.household_id===h.id&&m.user_id===uid));
 const houseId=houses.some(h=>h.id===selectedHouse)?selectedHouse:houses[0]?.id||'';
 async function download(){
  if(inFlight.current)return;inFlight.current=true;setBusy(true);setMessage('');setError('');
  try{
   if(!demo&&!db)throw new Error('Entre na sua conta para exportar.');
   const fresh=demo?data:await readData(db!,uid,today().slice(0,7));
   if(!demo){const result=await db!.auth.getUser();if(result.error||result.data.user?.id!==uid)throw new Error('Sua sessão mudou. Entre novamente para exportar.');}
   const csv=financialCsv(fresh,uid,scope,houseId,Object.fromEntries(fresh.accounts.map(a=>[a.id,accountBalance(a,fresh,today())])));
   const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8;'}));
   const link=document.createElement('a');link.href=url;link.download=`cume-${scope==='personal'?'pessoal':'casa-'+houseId}-${today()}.csv`;document.body.appendChild(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
   setMessage('CSV gerado com todo o histórico financeiro disponível.');
  }catch(cause){setError(cause instanceof Error?cause.message:'Não foi possível exportar. Tente novamente.')}finally{inFlight.current=false;setBusy(false)}
 }
 return <section className="panel csv-export" aria-label="Exportação de dados"><div><h2>Exportar CSV</h2><p>Todo o histórico financeiro, incluindo contas ocultas, previstos e cancelados. Cada tipo de registro é identificado; saldos e cotas não são novos gastos.</p></div><div className="csv-export-controls"><label>Dados para exportar<select value={scope} disabled={busy} onChange={e=>setScope(e.target.value as 'personal'|'household')}><option value="personal">Pessoal</option><option value="household">Casa</option></select></label>{scope==='household'&&<label>Casa<select value={houseId} disabled={busy} onChange={e=>setSelectedHouse(e.target.value)}>{!houses.length&&<option value="">Nenhuma casa disponível</option>}{houses.map(h=><option key={h.id} value={h.id}>{h.name}</option>)}</select></label>}<button className="secondary" disabled={busy||(scope==='household'&&!houseId)} onClick={download}><Download size={17}/>{busy?'Gerando CSV…':'Exportar CSV'}</button></div>{message&&<p role="status">{message}</p>}{error&&<div className="error" role="alert">{error}</div>}</section>;
}
