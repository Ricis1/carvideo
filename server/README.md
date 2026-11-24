# Bendras serveris (pranešimai ir draugai)

Kad vairuotojų pranešimus ir draugų vietą matytų visi CarVideo naudotojai, reikia vieno serverio.

**Siūlymas: Supabase** (supabase.com)
- Nemokamas planas: 500 MB duombazė, 50 000 aktyvių naudotojų per mėnesį. To užtenka pradžiai.
- Mokamas „Pro“: 25 $ per mėnesį, kai naudotojų bus daugiau.
- Serveris pasaulinis: projektą galima kurti Europoje (Frankfurtas), o naudotojai gali būti bet kur.

**Paleidimas (apie 10 min):**
1. Susikurti paskyrą supabase.com → New project.
2. SQL Editor → įklijuoti `supabase.sql` → Run.
3. Project Settings → API: nukopijuoti „Project URL“ ir „anon public“ raktą.
4. CarVideo → Nustatymai → Serveris: įklijuoti abu. Programėlė iškart pradeda naudoti bendrą serverį vietoj vietinio.

Privatumas: pranešimuose nėra vardų ir paskyrų – tik vieta, tipas ir laikas. Draugų kelionė matoma tik turintiems kodą ir tik iki atvykimo.

## v14: kuro kainos
`supabase.sql` gale yra lentelė `fuel_prices` ir funkcija `fuel_prices_nearby`. Jei duomenų bazė jau sukurta, SQL redaktoriuje paleisk tik šią dalį.
