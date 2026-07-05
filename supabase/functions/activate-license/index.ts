import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader) {
      return json({ valid: false, message: "Missing Authorization header" }, 401);
    }

    const body = await request.json();
    const licenseKey = String(body.license_key ?? "").trim();
    const deviceId = String(body.device_id ?? "").trim();
    const deviceName = String(body.device_name ?? "").trim();

    if (!licenseKey || !deviceId) {
      return json({ valid: false, message: "license_key and device_id are required" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    const userClient = createClient(
      supabaseUrl,
      anonKey,
      { global: { headers: { Authorization: authHeader } } },
    );
    const adminClient = createClient(
      supabaseUrl,
      serviceRoleKey,
    );

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ valid: false, message: "User session is invalid" }, 401);
    }

    const user = userData.user;
    const { data: license, error: licenseError } = await adminClient
      .from("licenses")
      .select("*")
      .eq("license_key", licenseKey)
      .eq("user_id", user.id)
      .single();

    if (licenseError || !license) {
      return json({ valid: false, message: "License not found for this user" }, 404);
    }
    if (license.status !== "active") {
      return json({ valid: false, message: `License is ${license.status}` }, 403);
    }
    if (license.expires_at && new Date(license.expires_at).getTime() <= Date.now()) {
      return json({ valid: false, message: "License expired" }, 403);
    }

    const { data: activations, error: activationError } = await adminClient
      .from("license_activations")
      .select("*")
      .eq("license_id", license.id);

    if (activationError) {
      return json({ valid: false, message: activationError.message }, 500);
    }

    const knownActivation = activations.find((item) => item.device_id === deviceId);
    if (!knownActivation && activations.length >= Number(license.max_devices ?? 1)) {
      return json({ valid: false, message: "Maximum devices reached for this license" }, 403);
    }

    const payload = {
      license_id: license.id,
      user_id: user.id,
      device_id: deviceId,
      device_name: deviceName || null,
      last_seen_at: new Date().toISOString(),
      activated_at: knownActivation?.activated_at ?? new Date().toISOString(),
    };

    const { error: upsertError } = await adminClient
      .from("license_activations")
      .upsert(payload, { onConflict: "license_id,device_id" });

    if (upsertError) {
      return json({ valid: false, message: upsertError.message }, 500);
    }

    return json({
      valid: true,
      licensed: true,
      license_key: license.license_key,
      email: user.email,
      plan: license.plan,
      status: license.status,
      expires_at: license.expires_at,
      max_devices: license.max_devices,
    });
  } catch (error) {
    return json(
      {
        valid: false,
        message: error instanceof Error ? error.message : "Unexpected error",
      },
      500,
    );
  }
});

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
