import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(() => {
  return Response.json(
    {
      error: "Cette fonction de maintenance a été désactivée.",
      code: "FUNCTION_RETIRED",
    },
    {
      status: 410,
      headers: {
        "Cache-Control": "no-store",
      },
    },
  );
});
