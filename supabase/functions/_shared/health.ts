export function healthResponse(functionName: string): Response {
  const requestId = crypto.randomUUID();
  return new Response(
    JSON.stringify({
      ok: true,
      function: functionName,
    }),
    {
      headers: { 'content-type': 'application/json', 'x-request-id': requestId },
      status: 200,
    },
  );
}
