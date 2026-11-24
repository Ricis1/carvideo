# CarVideo (iPhone)

Video (YouTube nuoroda arba failas) + mažas žemėlapis su tavo vieta ir greičiu + navigacija pačiame app'e (įvedi adresą). Video automatiškai sustoja, kai greitis viršija nustatytą ribą (testavimui numatyta 300 km/h, keičiama nustatymuose kas 5 km/h).

Maršrutas app'e: įvesk tikslą ir spausk **Vesti čia**. Žemėlapyje nupiešiamas kelias (Apple Maps duomenys), viršuje rodoma posūkių juosta (atstumas iki posūkio, nurodymas, likęs kelias ir laikas), nurodymai sakomi balsu, o nuklydus maršrutas perskaičiuojamas. Mygtukas su žemėlapio ikona sukeičia vietomis: didelis žemėlapis ir mažas video, arba atvirkščiai.

## Ką reikia turėti
- Mac kompiuterį su Xcode 16 ar naujesniu (nemokamas, App Store).
- iPhone su iOS 17 ar naujesne.
- Apple ID. Su nemokamu app'as veikia 7 dienas, po to reikia vėl įdiegti iš Xcode. Su mokama Apple Developer paskyra ($99/m.) veikia metus.

## Kaip paleisti ant iPhone
1. Mac'e atsisiųsk šį aplanką `car-video-ios`.
2. Sukurk projektą vienu iš būdų:
   - **Paprasčiau:** Terminale `brew install xcodegen`, tada šiame aplanke `xcodegen`. Atsiras `CarVideo.xcodeproj`.
   - Info.plist ir app'o ikona susikuria automatiškai iš `project.yml`.
3. Xcode: target CarVideo → Signing & Capabilities → Team = tavo Apple ID. Jei rodo klaidą dėl Bundle ID, pakeisk `com.example.carvideo` į ką nors unikalaus.
4. Prijunk iPhone laidu, pasirink jį viršuje ir spausk ▶︎.
5. iPhone: Nustatymai → Bendra → VPN ir įrenginio valdymas → pasitikėk savo Apple ID. Jei prašo, įjunk Developer Mode (Nustatymai → Privatumas ir sauga).

## CarPlay
Pats app'as veikia iPhone ekrane. Kad jis atsirastų **automobilio CarPlay ekrane**, reikia Apple leidimo (CarPlay entitlement), kurio Apple video programoms neduoda. Vienintelis kelias yra jailbreak su CarPlay papildiniu (pvz. CarBridge), kuris leidžia rodyti bet kurį app'ą CarPlay ekrane. Tai priklauso nuo iOS versijos ir ne visada įmanoma.

## Ką moka
- YouTube: įklijuok nuorodą (youtube.com, youtu.be, shorts).
- Failas: pasirink video iš Files.
- Žemėlapis: satelitas 3D (numatyta) — kamera seka automobilį iš galo, pakreipta, su pastatų ir reljefo 3D. Nustatymuose galima rinktis Įprastas / Satelitas / Satelitas 3D. Rodo greitį.
- 3D satelitas veikia ne visur: 3D pastatai ir reljefas rodomi tik ten, kur Apple turi tokius duomenis (dažniausiai didesniuose miestuose); kitur rodomas plokščias satelitas, bet kamera vis tiek pakreipta.
- Įvesk adresą ir spausk „Vesti čia“ (arba klaviatūros „Go“) — maršrutas rodomas pačiame app'e.
- Gulsčiai: žemėlapis ir video šalia. Pilką brūkšnelį tarp jų galima tempti pirštu (dydis įsimenamas), nustatymuose galima perkelti žemėlapį į dešinę. Stačiai: video viršuje, žemėlapis apačioje.
- Greitis, kelio greičio ženklas ir atvykimo laikas. Greičio ribos ir greičio kameros imamos iš OpenStreetMap (nemokamai, be rakto); likus 300 m iki kameros – įspėjimas, garsas ir balsas.
- Naktinis režimas: žemėlapis automatiškai tamsėja po saulėlydžio (arba rinkis Diena / Naktis).
- Kelionės (kelio ikona): automatiškai įrašomi km, laikas, vidutinis ir maksimalus greitis, kuras pagal tavo sąnaudas.
- Mėgstami YouTube (žvaigždutė): įsidėk grojaraščius, kanalus (/channel/UC… nuoroda) ar video ir paleisk vienu paspaudimu.
- Nustatymai (krumpliaratis): greičio riba video stabdymui, balso nurodymai įjungti/išjungti.

## Žinomi apribojimai
- Maršrutas skaičiuojamas Apple Maps, ne Google Maps ar Waze (jų maršrutų paimti neįmanoma). Spūsčių kaip Waze nėra. Greičio kameros ir ribos – iš OpenStreetMap, todėl kai kurių gali trūkti.
- Kai kurie YouTube video neleidžia įterpimo — jie nerodomi jokiame app'e.

---

# Be Mac'o: kompiliavimas internete ir įdiegimas iš Windows

GitHub nemokamai suteikia Mac kompiuterį debesyje. Jis sukompiliuoja app'ą į `CarVideo.ipa` failą, o Windows programa **Sideloadly** jį pasirašo tavo Apple ID ir įdiegia į iPhone.

## 1. Sukompiliuok `.ipa` per GitHub
1. Susikurk paskyrą https://github.com ir naują repozitoriją (pvz. `car-video`). Jei ji vieša (public), kompiliavimas nemokamas be limito.
2. Įkelk į ją visą `car-video-ios` aplanko turinį, **įskaitant** `.github/workflows/build-ipa.yml`.
   (Arba prijunk GitHub prie Claude, ir aš įkelsiu pats.)
3. Repozitorijoje atidaryk skirtuką **Actions** → „Build IPA“ → **Run workflow**. Kompiliavimas trunka apie 5 min.
4. Kai užsidegs žalia varnelė, atidaryk tą paleidimą, apačioje **Artifacts** → atsisiųsk `CarVideo-ipa` (zip, kuriame yra `CarVideo.ipa`).

## 2. Įdiek į iPhone su Sideloadly (Windows)
1. Įdiek **iTunes** ir **iCloud** iš apple.com (ne iš Microsoft Store versijų).
2. Atsisiųsk ir įdiek **Sideloadly**: https://sideloadly.io
3. Prijunk iPhone laidu, telefone paspausk „Pasitikėti šiuo kompiuteriu“.
4. Sideloadly: įtempk `CarVideo.ipa`, įvesk savo Apple ID, spausk **Start**.
5. iPhone: Nustatymai → Bendra → VPN ir įrenginio valdymas → pasitikėk savo Apple ID.
   Jei prašo, įjunk Nustatymai → Privatumas ir sauga → **Developer Mode** ir perkrauk telefoną.

Su nemokamu Apple ID app'as veikia **7 dienas**. Po to tiesiog pakartok 2 dalies 3–4 žingsnius su tuo pačiu `.ipa`. Sideloadly gali tai daryti ir automatiškai per Wi‑Fi, kai kompiuteris įjungtas.

---

# Vėliau: TestFlight (be kompiuterio, $99/m.)
Jei kada norėsi diegti tiesiai iš iPhone, `.github/workflows/testflight.yml` jau paruoštas: reikės Apple Developer paskyros, App Store Connect API rakto ir 5 GitHub Secrets (sąrašas failo viršuje).

---

# v13 naujovės
Eismo juostos (OSM turn:lanes), ramus naktinis ekranas, parkavimo nuotrauka su aukštu ir pastaba, poilsio priminimas, garsumas pagal greitį. Viskas `V13Features.swift`, kiekvieną galima išjungti nustatymuose.

# v14 naujovės
Muzika ir pasaulio radijas šalia žemėlapio (radio-browser.info), kuro ir įkrovimo kainos (FR, AT, DE oficialūs duomenys, kitur vairuotojai), ~200 naujų vertimų. Viskas `V14Features.swift`.

# v15 naujovės
Vaizdo registratorius (ciklinis įrašas, smūgio išsaugojimas) ir žemėlapiai be interneto (MapLibre + OpenFreeMap). Viskas `V15Features.swift`.

# v16 naujovės
Savas 3D automobilis su 5 kėbulais ir 3 ratlankių stiliais, kelionė su sustojimais, elektromobilio kelionės planas. Viskas `V16Features.swift`.
