revoke truncate on all tables in schema public from authenticated;
revoke truncate on all tables in schema public from anon;
revoke references, trigger on all tables in schema public from authenticated;
revoke references, trigger on all tables in schema public from anon;
