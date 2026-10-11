# Unimax Traders — Invoice Desk v0.1

**Draft prototype • HTML + CSS + JavaScript + Supabase**

For Utshav and Manav, Urlabari (Ullabari), Morang, Nepal.

## What works

- Email/password sign-in restricted to approved staff accounts
- Pharmacy/customer and supplement product catalogue
- Invoice drafts without permanent numbers
- Finalize and register: number `UM-0001`, `UM-0002`, etc, allocated transactionally by PostgreSQL
- View or print registered invoices; Word `.docx` downloads; browser Save as PDF
- Void finalized bills with a reason (admins only) while preserving numbering
- Invoice totals, discounts, configurable tax rate (defaults to zero), amount received and balance due
- A4 print format with signature/stamp spaces; company details can be updated

**Database stores authoritative invoice data and a finalized snapshot.** Word/PDF documents are generated on demand; their binary files are not uploaded to Supabase Storage. That avoids storage costs and duplicate files. To retain exact original output for legal archiving, add a server-side immutable document archive later.

## First setup (approximately 15–30 minutes)

1. Open [supabase.com](https://supabase.com/) and create a free project. Save the database password securely.
2. Open **SQL Editor** → **New query**, paste the entire `schema.sql`, then **Run** once. If tables already exist, do not casually rerun/recreate policies: the script is intended for a new project.
3. Open **Authentication → Providers → Email** and disable public email sign-ups (or use the equivalent current setting). Under **Authentication → Users** use **Add user** to create the founding staff email/password, marking email confirmed through the admin dashboard if needed. Never put actual passwords in GitHub.
4. Copy the new user's UUID from Authentication → Users. Run in SQL Editor (replace UUID):

   ```sql
   insert into public.staff(user_id, display_name, role)
   values ('PASTE_USER_UUID', 'Utshav', 'admin');
   ```

   Add more authorized users through Authentication → Users and then `public.staff`, selecting `'admin'` or `'staff'`.
5. Open **Project Settings → API** (the names may change slightly). Copy the **Project URL** and the **publishable key** (or legacy `anon` key). Copy `config.example.js` to `config.js` and replace both placeholders. **Never paste the secret or `service_role` key.** The public browser key is safe only because Row Level Security policies and membership checks are enabled.
6. Upload `index.html`, `styles.css`, `app.js`, `config.js`, and the `assets/` folder to a normal static web host or GitHub Pages. The app must be served over HTTP(S); don't open `index.html` as a `file://` URL.
7. Visit your URL, sign in and add one test pharmacy and product. Create a draft, preview it, save it, finalize it, export Word, and print.

## GitHub Pages deploy

Create a **private repository** for source control if desired. GitHub Pages availability for private repositories depends on your GitHub plan/settings. The **deployed site is publicly reachable** even if authentication protects the data; do not use it to conceal passwords.

Simplest method: create a new repository, upload the app files including a filled-in `config.js`, then enable **Settings → Pages → Deploy from branch → main / (root)**. Github Pages publishes static assets; `config.js` is public and must contain **only** the publishable/anon key. The `.gitignore` file excludes `config.js` from Git commits by default; if keeping `config.js` out of your Git repo, use a deployment workflow or your normal hosting file manager to upload it separately. Never commit private keys.

## How numbering works

A draft is unnumbered. A finalized invoice obtains the next number inside the `finalize_invoice()` database function. If two staff members finalize simultaneously, the database counter serializes allocations. A void invoice still keeps its original number. This app intentionally has **one global sequence**, without resetting annually. Bill prefixes are visual labels, not a separate per-prefix sequence. Altering the prefix later could change the presentation for drafts, but finalized invoices retain a settings snapshot.

## Business and compliance safeguards

- This is a **functional starter**, not certified Nepal tax/fiscal software. Have a Nepalese accountant verify the invoice fields, numbering, PAN/VAT treatment and legal format before using it as an official tax invoice.
- **Do not set 13% tax automatically** for every supplement; product classification and your company's tax registration determine treatment.
- Registered invoices are immutable in this draft. Recorded payments cannot be edited after finalization, so choose the received amount carefully. A separate payment/receivables ledger is recommended before full production use.
- No automatic stock deductions yet. Add stock lots, expiry, returns and payment receipts in Phase 2.
- Internet required for Supabase, and for Word export libraries loaded via CDN. The app is not offline-first.
- Supabase Free has usage limits and may pause inactive projects. Set calendar reminders for exports and back up the database yourself: free plans do not offer the same managed backups as paid plans.
- User-created finalized invoice records can be voided (admin only); backups and logging should be strengthened before storing material financial records.
- Current accounts all share one Unimax company data set; use only trusted authorized staff.

## Smoke-test checklist

- [ ] Unapproved user cannot access company data
- [ ] Approved staff can log in and save pharmacy/product
- [ ] Draft can be edited without consuming a bill number
- [ ] First finalized invoice becomes `UM-0001`
- [ ] Subsequent finalized invoice becomes `UM-0002`
- [ ] Two concurrent finalizations never have the same bill number
- [ ] Printed totals match invoice line calculations
- [ ] Word file opens correctly in Word/LibreOffice
- [ ] Admin can void a finalized bill, number is retained
- [ ] Staff cannot void a finalized bill
- [ ] Company settings and PAN are still blank until provided

## Next release

Stock/expiry tracking, purchase costs, tiered pricing for 2–3/4–6/7+ units, separate payment receipts, role permissions, CSV exports, batch/lot tracing and deeper reporting.
