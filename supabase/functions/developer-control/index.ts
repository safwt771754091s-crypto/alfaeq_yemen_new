import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const OH_KEY = Deno.env.get("OPENHANDS_CLOUD_API_KEY") ?? Deno.env.get("OPENHANDS_API_KEY") ?? "";
const OH_BASE = (Deno.env.get("OPENHANDS_BASE_URL") ?? "https://app.all-hands.dev").replace(/\/$/, "");
const WORKER_SECRET = Deno.env.get("ALFAEQ_AUTOMATION_WORKER_SECRET") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{
  status,
  headers:{"content-type":"application/json",...corsHeaders},
});
async function auth(req:Request,admin:any){
  const h=req.headers.get("authorization")??"";
  const token=h.replace(/^Bearer\s+/i,"").trim();
  if(!token)throw new Error("authentication_required");
  const {data,error}=await admin.auth.getUser(token);
  if(error||!data.user)throw new Error("invalid_session");
  const {data:profile}=await admin.from("users").select("uid,role,owner,admin,developer").eq("uid",data.user.id).maybeSingle();
  if(!profile)throw new Error("profile_not_found");
  const allowed=profile.owner===true||profile.admin===true||profile.developer===true||["owner","admin","developer"].includes(String(profile.role??""));
  if(!allowed)throw new Error("forbidden");
  return {user:data.user,profile};
}
async function oh(path:string,method:"GET"|"POST",body?:unknown){
  if(!OH_KEY)throw new Error("openhands_provider_not_configured");
  const r=await fetch(OH_BASE+path,{method,headers:{authorization:"Bearer "+OH_KEY,"content-type":"application/json"},body:body===undefined?undefined:JSON.stringify(body)});
  const text=await r.text(); let data:any={}; try{data=JSON.parse(text)}catch{data={raw:text.slice(0,2000)}}
  if(!r.ok)throw new Error("OpenHands HTTP "+r.status+": "+JSON.stringify(data).slice(0,1500));
  return data;
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{status:200,headers:corsHeaders});
 if(req.method!=="POST")return json({ok:false,error:"method_not_allowed"},405);
 if(!URL||!SERVICE)return json({ok:false,error:"server_configuration_missing"},500);
 const admin=createClient(URL,SERVICE,{auth:{autoRefreshToken:false,persistSession:false}});
 try{
  const {user}=await auth(req,admin);
  const body=await req.json().catch(()=>({}));
  const action=String(body.action??"status");
  if(action==="automation_status"){
    const {data:inbox}=await admin.from("automation_event_inbox").select("id,status,event_type,attempts,received_at,processed_at,last_error").order("received_at",{ascending:false}).limit(20);
    const {data:legacy}=await admin.from("automation_events").select("id,status,event_type,attempts,created_at,last_error").order("id",{ascending:false}).limit(20);
    return json({ok:true,inbox:inbox??[],legacy:legacy??[]});
  }
  if(action==="run_automation_worker"){
    if(!WORKER_SECRET)throw new Error("automation_worker_not_configured");
    const r=await fetch(URL+"/functions/v1/automation-worker",{method:"POST",headers:{"content-type":"application/json","x-alfaeq-worker-secret":WORKER_SECRET},body:JSON.stringify({limit:10})});
    const text=await r.text(); let data:any={}; try{data=JSON.parse(text)}catch{data={raw:text}};
    return json({ok:r.ok,status:r.status,worker:data},r.ok?202:500);
  }
  if(action==="status"){
    const {data:runs,error}=await admin.from("ai_agent_runs").select("id,task_id,agent_id,provider,status,repository,branch,conversation_id,error,result,created_at,updated_at").order("created_at",{ascending:false}).limit(20);
    if(error)throw error;
    return json({ok:true,runs:runs??[]});
  }
  if(action!=="execute_task")return json({ok:false,error:"unknown_action"},400);
  const title=String(body.title??"").trim();
  const description=String(body.description??"").trim();
  const branch=String(body.branch??"main").trim()||"main";
  if(!title||!description)return json({ok:false,error:"title_and_description_required"},400);
  const repository="safwt771754091s-crypto/alfaeq_yemen_new";
  const {data:task,error:taskError}=await admin.from("ai_tasks").insert({
    title,description,status:"in_progress",priority:"high",project_key:"alfaeq-commercial",
    goal_key:"owner_development",metadata:{requested_by:user.id,source:"developer_center"}
  }).select("id,title,status").single();
  if(taskError)throw taskError;
  const {data:agents,error:agentError}=await admin.from("ai_agents").select("id,status,budget_monthly_cents,spend_monthly_cents").in("status",["idle","active"]).order("created_at").limit(10);
  if(agentError)throw agentError;
  const agent=(agents??[]).find((a:any)=>Number(a.budget_monthly_cents??0)<=0||Number(a.spend_monthly_cents??0)<Number(a.budget_monthly_cents??0));
  if(!agent){
    await admin.from("ai_tasks").update({status:"backlog",metadata:{requested_by:user.id,source:"developer_center",blocked:"no_available_agent"}}).eq("id",task.id);
    return json({ok:false,error:"no_available_agent",task_id:task.id},503);
  }
  const prompt=`You are the protected engineering agent for Alfaeq Yemen commercial platform.
Repository: ${repository}
Branch: ${branch}
Task: ${title}
Description:
${description}

Execution contract:
- Supabase is the production source of truth.
- Preserve Auth, RLS, transactional order/inventory/payment behavior and auditability.
- Never expose or commit secrets.
- Inspect existing implementation before changing it.
- Run formatting, analysis, tests and relevant builds.
- Do not claim success without evidence.
- Prepare focused changes and leave clear verification evidence.`;
  const {data:run,error:runError}=await admin.from("ai_agent_runs").insert({
    task_id:task.id,agent_id:agent.id,provider:"openhands",status:"running",attempt:1,
    repository,branch,prompt,result:{source:"developer_center",requested_by:user.id},started_at:new Date().toISOString()
  }).select("id").single();
  if(runError)throw runError;
  try{
    const start=await oh("/api/v1/app-conversations","POST",{initial_message:{content:[{type:"text",text:prompt}]},selected_repository:repository,selected_branch:branch,title:title});
    let conversationId=String(start.app_conversation_id??"");
    let startTaskId=String(start.id??"");
    if(!conversationId&&startTaskId){
      const ready=await oh("/api/v1/app-conversations/start-tasks?ids="+encodeURIComponent(startTaskId),"GET");
      conversationId=String(ready.app_conversation_id??ready.id??"");
    }
    await admin.from("ai_agent_runs").update({conversation_id:conversationId||null,external_run_id:startTaskId||conversationId||null,result:{provider:"openhands",start,requested_by:user.id},updated_at:new Date().toISOString()}).eq("id",run.id);
    return json({ok:true,task_id:task.id,run_id:run.id,conversation_id:conversationId||null,start_task_id:startTaskId||null,provider:"openhands"},202);
  }catch(e){
    await admin.from("ai_agent_runs").update({status:"failed",error:String(e).slice(0,2000),completed_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq("id",run.id);
    await admin.from("ai_tasks").update({status:"backlog",metadata:{requested_by:user.id,source:"developer_center",last_error:String(e).slice(0,1000)}}).eq("id",task.id);
    throw e;
  }
 }catch(e){
  const m=String(e); const status=m.includes("authentication")||m.includes("session")?401:m.includes("forbidden")?403:m.includes("not_configured")?503:500;
  return json({ok:false,error:m.slice(0,2000)},status);
 }
});