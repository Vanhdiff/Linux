# Trading Desk License Ops

## Create a customer license

1. Open Supabase -> Authentication -> Users.
2. Create the customer's email/password account.
3. Open SQL Editor and run `supabase/seeds/create_customer_license.sql`.
4. Replace:
   - `CUSTOMER_USER_UID`
   - `TD-PRO-002`
   - `Customer Name`
5. Run the verification query at the bottom.

Files:
- `supabase/seeds/create_customer_license.sql`
- `supabase/seeds/reset_customer_license_activations.sql`

## Reset activation when the customer changes machine

Run `supabase/seeds/reset_customer_license_activations.sql` and replace the license key.

## Build the Windows setup

Prerequisites:
- Flutter release already built
- Inno Setup 6 installed

Command:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_setup.ps1
```

Installer output:

```text
installer\trading-desk-setup-1.0.0.exe
```
