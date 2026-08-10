DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM net.http_request_queue LIMIT 1) THEN
    RAISE EXCEPTION 'Cannot relocate pg_net while HTTP requests are pending';
  END IF;
END;
$$;

DROP EXTENSION IF EXISTS pg_net;
CREATE EXTENSION pg_net WITH SCHEMA extensions;;
