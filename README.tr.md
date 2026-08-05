<div align="center">

# Quickshell için Dynamic Island

Hyprland için monokrom, çentik tarzı bir katman — medya, canlı cihaz
göstergeleri ve pixel-art bir saat; imlecin altında büyüyen tek bir yüzeyde.

[![Quickshell](https://img.shields.io/badge/Quickshell-0.3%2B-111111?style=flat-square)](https://quickshell.outfoxxed.me/)
[![Hyprland](https://img.shields.io/badge/Hyprland-wlroots-111111?style=flat-square)](https://hyprland.org/)
[![Lisans](https://img.shields.io/badge/Lisans-MIT-111111?style=flat-square)](LICENSE)

**[Web sitesi](https://lunanoir21.github.io/quickshell-dynamic-island/)** · [English README](README.md)

<img src="docs/screenshots/clock.png" width="720" alt="Pixel-art saati gösteren açık panel">

</div>

---

## Nedir

Ekranın üst kenarına sabitlenmiş, her zaman üstte duran tek bir yüzey. Kapalıyken
kompakt bir pill; imleci üzerine getirdiğinizde aktarım kontrolleri, spektrum
analizörü ve ses/parlaklık/mikrofon için dikey ölçerler içeren tam bir panele
dönüşür. Bildirimler ile mikrofon/kamera etkinliği yüzeyi kendiliğinden devralır
ve işleri bitince geri verir.

Her şey gri tonlamada çizilir. Hiçbir yerde vurgu rengi yoktur.

<table>
<tr>
<td width="50%"><img src="docs/screenshots/pill.png" alt="Kapalı pill"><br><sub><b>Kapalı</b> — kapak, başlık, pixel saat, pil, mikrofon/kamera göstergeleri, spektrum şeridi</sub></td>
<td width="50%"><img src="docs/screenshots/notification.png" alt="Bildirim kartı"><br><sub><b>Bildirim</b> — çözümlenmiş uygulama simgesi ve kapanma geri sayımı</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/media.png" alt="Medya paneli"><br><sub><b>Medya</b> — kapak, seek, aktarım, aynalanmış spektrum, ölçerler</sub></td>
<td><img src="docs/screenshots/device.png" alt="Mikrofon gizlilik kartı"><br><sub><b>Gizlilik</b> — mikrofon veya kamera her açılıp kapandığında belirir</sub></td>
</tr>
</table>

## Özellikler

- **MPRIS medya** — kapak görseli, başlık/sanatçı, seek, shuffle ve repeat,
  önceki/oynat/sonraki. Aktarım düğmeleri iyimser davranır: bir sonraki poll'ü
  beklemek yerine tıklama anında tepki verir.
- **Gerçek spektrum analizörü** — [`cava`](https://github.com/karlstav/cava) ile
  beslenir, bas bantlar ortada buluşacak şekilde aynalanır. cava yoksa veya panel
  kapalıysa sentetik bir eğriye düşer.
- **Pixel-art saat** — dormant bir LED ızgarası üzerine canvas ile çizilen 5×7
  bitmap yazı tipi. Rakamlar değişince satır satır dikey olarak yuvarlanır.
  Türkçe Ç/Ğ/İ/Ö/Ş/Ü dahildir.
- **Canlı cihaz göstergeleri** — PipeWire mikrofonu ve V4L2 kamerası her
  başladığında/durduğunda bir kart yükseltir. Bunlar gizlilik göstergeleri
  olduğu için ada kapalıyken bile makul bir hızda yoklanır.
- **Bildirimler** — bir uygulama IPC üzerinden kart gönderebilir; kendi simgesiyle
  ya da freedesktop simge adı çözümlemesiyle.
- **Ölçerler** — ses, parlaklık ve mikrofon kazancı sürüklenebilir segment
  çubukları olarak (`wpctl` / `brightnessctl`).
- **Hava durumu ve pil** — IP konumuyla Open-Meteo, 15 dakika önbelleklenir;
  pil seviyesi, şarj durumu ve kalan süre sysfs ile UPower'dan.
- **Yoldan çekilir** — odaktaki pencere tam ekrana geçince tamamen gizlenir,
  çıkınca geri gelir.

## Gereksinimler

| | |
| --- | --- |
| **Zorunlu** | [Quickshell](https://quickshell.outfoxxed.me/) 0.3+, Hyprland (veya layer-shell destekleyen başka bir wlroots bileşik yöneticisi), `jq`, bir Nerd Font |
| **İsteğe bağlı** | `playerctl` (medya), `wpctl` + `pactl` (ses, mikrofon algılama), `brightnessctl`, `cava` (spektrum), `bluetoothctl`, `upower`, `curl` (hava durumu), `fuser` (kamera algılama) |

Eksik olan her şey ilgili bölümü boş bırakır ya da yedeğe düşer — hiçbiri
projeyi çökertmez.

Arayüz simgeler için varsayılan olarak **Iosevka Nerd Font** kullanır.
`DynamicIsland.qml` içindeki `iconFont` değerini kurulu olan yamalı fontunuza
yöneltin. Metin yazı tipi (Bricolage Grotesque) projeye dahildir.

## Kurulum

```bash
git clone https://github.com/lunanoir21/quickshell-dynamic-island.git
cd quickshell-dynamic-island
chmod +x backend.sh
quickshell -p ./Main.qml
```

Bu, projeyi tek başına çalıştırır. Mevcut bir Quickshell yapılandırmasına
katmak için dizini shell kökünüzün yanına koyun ve host'u örnekleyin:

```qml
// Shell.qml
import "dynamic-island" as DynamicIslandModule

ShellRoot {
    DynamicIslandModule.DynamicIslandHost {}
}
```

`DynamicIslandHost`, `Quickshell.screens` üzerinde bir `Variants` olduğu için
her monitöre bir ada yerleştirir.

`hyprland.conf` içine geçiş tuşunu bağlayın:

```ini
bind = SUPER, Super_L, exec, qs -p ~/.config/quickshell/Shell.qml ipc call dynamicIsland toggle
```

## Kullanım

### İmleç

| Eylem | Sonuç |
| --- | --- |
| Üzerine gelme | Açılır |
| Ayrılma | 90 ms içinde kapanır |
| Sağ tık | Kapatır |
| Raptiye düğmesi | Açık kilitler |

Sol tık bilerek işlevsizdir. Adadan ayrılmak onu kapatmak demektir; boş panel
alanına yanlışlıkla atılan bir tık onu asla açık bırakamamalı.

### Klavye

Ada raptiyeliyken çalışır.

| Tuş | Sonuç |
| --- | --- |
| <kbd>Boşluk</kbd> | Oynat / duraklat |
| <kbd>←</kbd> <kbd>→</kbd> | Önceki / sonraki parça |
| <kbd>Esc</kbd> | Kapat |

Yüzey klavye odağını **yalnızca raptiyeliyken** alır. Münhasır bir layer-shell
grab'i, asıl yazdığınız uygulamaya giden her tuşu yutar; bunu hover'a bağlamak
imleç ekranın üstünde durduğu her an girdinizi yer.

### IPC

```bash
qs -p <shell.qml> ipc call dynamicIsland toggle
qs -p <shell.qml> ipc call dynamicIsland open
qs -p <shell.qml> ipc call dynamicIsland close
qs -p <shell.qml> ipc call dynamicIsland activity "herhangi bir metin"
qs -p <shell.qml> ipc call dynamicIsland notify <uygulama> <başlık> <gövde> <simge>
qs -p <shell.qml> ipc call dynamicIsland deviceEvent <microphone|camera> <true|false> <değer>
```

Bildirimleri adaya yönlendirmek için `notify`'ı bildirim sunucunuza bağlayın.

## Nasıl çalışır

```
Main.qml                 ShellRoot giriş noktası
└── DynamicIslandHost    Quickshell.screens üzerinde Variants — monitör başına bir ada
    └── DynamicIsland    Yüzey: durum makinesi, yerleşim, tüm animasyonlar
        ├── BarMeter     Sürüklenebilir segment ölçer (ses / parlaklık / mikrofon)
        ├── PixelClock   Pixel saati, saniyeleri ve tarih satırını birleştirir
        │   └── PixelText  Dikey rakam yuvarlamalı canvas bitmap metin motoru
        │       └── pixelfont.js  5×7 glif tablosu + Türkçe gün/ay adları
        └── backend.sh   Poll başına tek bir JSON anlık görüntüsü
```

`backend.sh snapshot` tüm arayüz durumunu tek bir JSON nesnesi olarak yayar.
Pahalı işler (hava durumu, bluetooth, UPower, kamera algılama) kilitli bir arka
plan işinde tazelenir ve önbellekten okunur; böylece bir poll asla onları
beklemez. Oynatma konumu poll'ler arasında yerel olarak enterpole edilir ve
kaydığında yeniden senkronlanır, böylece ilerleme çubuğu sıçramak yerine akar.

### Düzenlemeden önce bilinmesi gereken iki kural

**Döngüsel animasyonlar asla doğrudan görsel bir özelliğe bağlanmaz.** Her biri
sıfırlanabilir bir sayı sürer (`playGlow`, `ringPulse`, `visualPhase`,
`edgeGlow`) ve durduğunda onu bilinen bir dinlenme değerine döndürür.
`SequentialAnimation on opacity { loops: Infinite }` yazmak, koşul yanlışa
döndüğünde özelliği döngünün ortasında dondurur; ekranda yarım sönmüş halkalar
ve donmuş çubuklar bırakır.

**`Behavior` yalnızca ayrık girdiyi yumuşatmak içindir.** cava'nın 30 Hz
örneklerini yumuşatır. Zaten her karede değişen bir değere `Behavior` koymak,
animasyonu ilerleyemeden yeniden hedefler ve spektrumu hareketsiz bir çubuk
sırasına düzler.

## Yerelleştirme

Arayüz metinleri Türkçedir ve `DynamicIsland.qml` içinde satır içi durur.
`pixelfont.js` içindeki pixel font Türkçe gün ve ay adlarını taşır. İkisi de
kolayca değiştirilebilir.

## Teşekkürler

- outfoxxed tarafından [Quickshell](https://quickshell.outfoxxed.me/)
- Davranışlar [`boring.notch`](https://github.com/TheBoredTeam/boring.notch)'tan uyarlandı
- [Bricolage Grotesque](https://github.com/ateliertriay/bricolage) (OFL 1.1, dahil)
- Spektrum verisi için [cava](https://github.com/karlstav/cava)

## Lisans

MIT — [LICENSE](LICENSE) dosyasına bakın. Dahil edilen yazı tipi OFL 1.1'dir.
