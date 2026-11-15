export const dynamic = 'force-dynamic';
export function GET() {
  const url = process.env.SUPABASE_URL || '';
  const key = process.env.SUPABASE_ANON_KEY || '';
  // This endpoint is public. Never return a privileged Supabase key.
  let privileged = key.startsWith('sb_secret_');
  try { privileged ||= JSON.parse(Buffer.from(key.split('.')[1] || '', 'base64url').toString()).role === 'service_role'; } catch {}
  if (privileged) return Response.json({ configured: false, url: '', key: '' }, { status: 503, headers: { 'Cache-Control': 'no-store' } });
  return Response.json({ configured: Boolean(url && key), url, key }, { headers: { 'Cache-Control': 'no-store' } });
}
