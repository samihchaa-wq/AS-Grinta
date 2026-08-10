-- Same pattern as create_postmatch_composition: the public wrapper stays
-- SECURITY INVOKER, but authenticated needs direct EXECUTE on the private
-- implementation to actually be able to call it.

grant execute on function private.update_postmatch_composition(
  uuid, text, jsonb, boolean, text
) to authenticated;
;
