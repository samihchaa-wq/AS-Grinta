revoke execute on function public.is_exact_live_controller(uuid,text)
from public;
revoke execute on function public.is_exact_live_controller(uuid,text)
from anon;
revoke execute on function public.is_exact_live_controller(uuid,text)
from authenticated;

revoke execute on function public.set_live_formation(uuid,text,text)
from public;
revoke execute on function public.set_live_formation(uuid,text,text)
from anon;
revoke execute on function public.add_live_goal(uuid,text,text,integer,text,uuid,text,uuid)
from public;
revoke execute on function public.add_live_goal(uuid,text,text,integer,text,uuid,text,uuid)
from anon;
revoke execute on function public.update_live_goal(uuid,text,text,integer,text,uuid,text,uuid)
from public;
revoke execute on function public.update_live_goal(uuid,text,text,integer,text,uuid,text,uuid)
from anon;
revoke execute on function public.delete_live_goal(uuid,text)
from public;
revoke execute on function public.delete_live_goal(uuid,text)
from anon;

grant execute on function public.set_live_formation(uuid,text,text)
to authenticated;
grant execute on function public.add_live_goal(uuid,text,text,integer,text,uuid,text,uuid)
to authenticated;
grant execute on function public.update_live_goal(uuid,text,text,integer,text,uuid,text,uuid)
to authenticated;
grant execute on function public.delete_live_goal(uuid,text)
to authenticated;
