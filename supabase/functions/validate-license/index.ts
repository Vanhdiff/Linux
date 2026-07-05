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
      return json({ valid: false, licensed: false, message: "License not found" }, 404);
    }
    if (license.status !== "active") {
      return json(
        { valid: false, licensed: false, message: `License is ${license.status}` },
        403,
      );
    }
    if (license.expires_at && new Date(license.expires_at).getTime() <= Date.now()) {
      return json({ valid: false, licensed: false, message: "License expired" }, 403);
    }

    const { data: activation, error: activationError } = await adminClient
      .from("license_activations")
      .select("*")
      .eq("license_id", license.id)
      .eq("device_id", deviceId)
      .maybeSingle();

    if (activationError) {
      return json({ valid: false, message: activationError.message }, 500);
    }
    if (!activation) {
      return json(
        { valid: false, licensed: false, message: "This device is not activated" },
        403,
      );
    }

    const { error: updateError } = await adminClient
      .from("license_activations")
      .update({
        device_name: deviceName || activation.device_name,
        last_seen_at: new Date().toISOString(),
      })
      .eq("id", activation.id);

    if (updateError) {
      return json({ valid: false, message: updateError.message }, 500);
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
