-- Supabase-managed migrations may create functions as supabase_admin.
-- Keep those functions private by default as well.

alter default privileges for role supabase_admin in schema public
  revoke execute on functions from public;

alter default privileges for role supabase_admin in schema public
  revoke execute on functions from anon;

alter default privileges for role supabase_admin in schema public
  revoke execute on functions from authenticated;
