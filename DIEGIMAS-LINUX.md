# CarVideo įdiegimas į iPhone per Linux kompiuterį (nemokamai)

Reikia: Linux kompiuterio, iPhone, USB laido ir paprasto (nemokamo) Apple ID.

## 1. Parsisiųsk programą
Atidaryk **github.com/Ricis1/carvideo/releases** → „CarVideo … (naujausias)“ → parsisiųsk **CarVideo.ipa**.
(Failas susikuria pats po kiekvieno pakeitimo, per ~10 min.)

## 2. Paruošk Linux kompiuterį (vieną kartą)
Terminale:
```
sudo apt install usbmuxd libimobiledevice-utils
```
(Fedora: `sudo dnf install usbmuxd libimobiledevice-utils`.)

Parsisiųsk **iloader**: github.com/nab138/iloader → „Releases“ → `.AppImage` (arba `.deb`).
AppImage paleidimas: dešinys pelės mygtukas → Properties → „Allow executing“, tada dukart spustelėk.

## 3. Prijunk iPhone
1. Prijunk laidu, atrakink telefoną, paspausk **„Pasitikėti“ (Trust)** ir įvesk kodą.
2. iPhone: **Nustatymai → Privatumas ir sauga → Kūrėjo režimas (Developer Mode) → įjungti**, telefonas persikraus.
   (Jei šio punkto nėra – jis atsiras po 4 žingsnio.)

## 4. Įdiek SideStore per iloader (vieną kartą)
1. iloader'yje prisijunk su savo Apple ID (geriau atskiru, ne pagrindiniu).
2. Pasirink **SideStore** → „Install“. iloader pats sukurs ir įkels poravimo failą.
3. iPhone: **Nustatymai → Bendrieji → VPN ir įrenginio valdymas** → savo Apple ID → **„Pasitikėti“**.
4. Iš App Store įsidiek **LocalDevVPN** (arba ką paprašys SideStore) – jo reikia, kad SideStore pats atnaujintų programas be kompiuterio.

## 5. Įdiek CarVideo
1. CarVideo.ipa nusiųsk į telefoną (pvz. AirDrop neveikia su Linux – naudok Google Drive, el. paštą ar Telegram ir „Išsaugoti į Failus“).
2. Atidaryk **SideStore → My Apps → „+“** → pasirink CarVideo.ipa → palauk.
3. Pirmą kartą atidarius – leisk vietą ir pranešimus.

## Svarbu
- **Nemokamas Apple ID: programa galioja 7 dienas.** SideStore telefone paspausk „Refresh“ bent kartą per savaitę (arba įjunk automatinį atnaujinimą) – kompiuterio nebereikia.
- Daugiausia **3 programos** vienu metu (SideStore + CarVideo + dar viena).
- CarPlay su nemokamu Apple ID neveiks (Apple leidimas reikalingas tik mokamai paskyrai). Visa kita veikia.
- AltServer-Linux senas ir nebeprižiūrimas – geriau iloader + SideStore.
