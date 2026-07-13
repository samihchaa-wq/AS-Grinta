-- P0 hardening: new functions created by postgres in public must not become
-- executable through the Data API unless a migration grants access explicitly.

alter default privileges for role postgres in schema public
  revoke execute on functions from public;

alter default privileges for role postgres in schema public
  revoke execute on functions from anon;

alter default privileges for role postgres in schema public
  revoke execute on functions from authenticated;
