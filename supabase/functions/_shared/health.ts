export function healthResponse(functionName: string): Response {
  return new Response(
    JSON.stringify({
      ok: true,
      function: functionName,
    }),
    {
      headers: { 'content-type': 'application/json' },
      status: 200,
    },
  );
}
