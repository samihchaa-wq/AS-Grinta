-- P0: remove pg_net from the exposed public schema.
-- pg_net 0.20.x is not relocatable with ALTER EXTENSION, so recreate it while
-- the request queue is empty. Its API remains under the dedicated `net` schema.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM net.http_request_queue LIMIT 1) THEN
    RAISE EXCEPTION 'Cannot relocate pg_net while HTTP requests are pending';
  END IF;
END;
$$;

DROP EXTENSION IF EXISTS pg_net;
CREATE EXTENSION pg_net WITH SCHEMA extensions;
