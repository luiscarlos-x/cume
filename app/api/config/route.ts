import {env} from 'cloudflare:workers';
export const dynamic='force-dynamic';
export function GET(){const e=env as unknown as Record<string,string>;const url=e.SUPABASE_URL||'',key=e.SUPABASE_ANON_KEY||'';return Response.json({configured:!!(url&&key),url,key},{headers:{'Cache-Control':'no-store'}})}
