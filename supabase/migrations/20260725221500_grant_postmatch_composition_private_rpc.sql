-- Keep the public wrapper SECURITY INVOKER, like the existing composition RPCs,
-- while allowing it to invoke the private implementation. Authorization is
-- still enforced inside private.create_postmatch_composition().

revoke all on function private.create_postmatch_composition(
  uuid, text, jsonb, boolean, text
) from public, anon;

grant execute on function private.create_postmatch_composition(
  uuid, text, jsonb, boolean, text
) to authenticated;
