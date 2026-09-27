import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
type Body={orderId?:string};
function jwtRole(auth:string):string|null{try{const token=auth.replace(/^Bearer\s+/i,"");const p=token.split(".")[1];if(!p)return null;const pad=p.replace(/-/g,"+").replace(/_/g,"/")+"===".slice((p.length+3)%4);const d=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(pad),c=>c.charCodeAt(0)));return typeof d.role==="string"?d.role:null;}catch{return null;}}
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return new Response(JSON.stringify({ok:false,error:"method_not_allowed"}),{status:405,headers:{"content-type":"application/json"}});
 const auth=req.headers.get("authorization")??"";
 if(!auth.toLowerCase().startsWith("bearer ")||jwtRole(auth)!=="service_role")return new Response(JSON.stringify({ok:false,error:"service_role_required"}),{status:403,headers:{"content-type":"application/json"}});
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key)return new Response(JSON.stringify({ok:false,error:"server_configuration_error"}),{status:500,headers:{"content-type":"application/json"}});
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
  const body=await req.json() as Body; const orderId=String(body.orderId??"").trim();
  if(!orderId||orderId.length>128)return new Response(JSON.stringify({ok:false,error:"invalid_order_id"}),{status:400,headers:{"content-type":"application/json"}});
  const {data:before}=await db.from("orders").select("id,status,metadata").eq("id",orderId).maybeSingle();
  if(!before)return new Response(JSON.stringify({ok:false,orderId,error:"order_not_found"}),{status:404,headers:{"content-type":"application/json"}});
  const {data:rows,error}=await db.rpc("reserve_order_inventory",{p_order_id:orderId});
  if(error){
   const metadata={...(before.metadata??{}),inventory_status:"reservation_failed",inventory_error:error.message,inventory_updated_at:new Date().toISOString()};
   await db.from("orders").update({metadata,updated_at:new Date().toISOString()}).eq("id",orderId);
   return new Response(JSON.stringify({ok:false,orderId,error:error.message}),{status:409,headers:{"content-type":"application/json"}});
  }
  const metadata={...(before.metadata??{}),inventory_status:"reserved",inventory_reserved_at:new Date().toISOString()};
  const {error:updateError}=await db.from("orders").update({metadata,updated_at:new Date().toISOString()}).eq("id",orderId);
  if(updateError)return new Response(JSON.stringify({ok:false,orderId,error:updateError.message}),{status:500,headers:{"content-type":"application/json"}});
  return new Response(JSON.stringify({ok:true,orderId,status:before.status,inventoryStatus:"reserved",reservations:rows??[]}),{status:200,headers:{"content-type":"application/json"}});
 }catch(e){return new Response(JSON.stringify({ok:false,error:e instanceof Error?e.message:"invalid_request"}),{status:400,headers:{"content-type":"application/json"}});}
});