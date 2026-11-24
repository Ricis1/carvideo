# Bendras pranešimų serveris – nustatymas (v17, ~10 min, nemokamai)

Tai daroma **vieną kartą**. Po to visi, kurie įsidiegs CarVideo, automatiškai matys vieni kitų pranešimus (policija, duobės, avarijos). Naudotojams nieko vesti nereikia.

1. Atidaryk **supabase.com** → „Start your project“ → prisijunk su GitHub.
2. „New project“: pavadinimas `carvideo`, slaptažodį sugalvok bet kokį, regionas **Frankfurt (eu-central-1)** → „Create“.
3. Kairėje **SQL Editor** → „New query“ → įklijuok visą `supabase.sql` turinį → **Run**.
4. Kairėje **Project Settings → API** (arba „Data API“). Nukopijuok:
   - **Project URL** (pvz. `https://abcd1234.supabase.co`)
   - **anon public** raktą (ilgas tekstas, prasideda `eyJ...`)
5. GitHub'e: `Ricis1/carvideo` → **Settings → Secrets and variables → Actions → New repository secret**:
   - `SUPABASE_URL` = Project URL
   - `SUPABASE_KEY` = anon public raktas
6. **Actions → Build IPA → Run workflow**. Naujas `CarVideo.ipa` jau turės serverį viduje.

Kas dar:
- Nemokamas planas: 500 MB, 50 000 naudotojų per mėnesį – užtenka.
- Nemokamas projektas užmiega po 7 dienų be veiklos. Darbas `Supabase keepalive` jį pažadina kas 3 dienas automatiškai.
- „anon public“ raktas nėra slaptas (jis būna programėlėje), bet duomenų bazės slaptažodžio niekam nesiųsk.
- Seni pranešimai (> 2 val.) išsivalo patys, pasikartojantys sujungiami.
