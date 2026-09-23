# Değişiklik Günlüğü

Dynamic Island'a yapılan tüm önemli değişiklikler burada, en yenisinden
başlanarak listelenir. Sürümler işlerin tamamlandığı tarihtir (`YYYY.AA.GG`),
çünkü bu proje öyle sürüm verir — semver değil.

Bu dosya ile [CHANGELOG.md](CHANGELOG.md), sürüm notlarının yazıldığı tek
yerdir. `python3 scripts/changelog.py`, en son sürümü iki README'ye ("Neler
değişti" bölümüne) ve web sitesinin okuduğu `docs/changelog.json` dosyasına
kopyalar. Türkçe değişiklik günlüğü, İngilizcesiyle aynı sürümleri listeliyor
olmalıdır.

Her sürüm, düz biçimin karşılığı olmayan üç şey taşır: `**başlık**` satırı,
kısa bir `özet` paragrafı ve bir `### Shots` bölümü:

    ## [2026.08.17] - 2026-08-17

    **Kısa bir cümle, sürüm yükseltmesi değil**

    Ne değiştiğini ve neden yapmaya değer olduğunu anlatan iki-üç cümle.

    ### Added
    - Madde başına bir değişiklik; kırılan satırlar iki boşlukla girintilenir.

    ### Shots
    - ![görselin ne gösterdiği](screenshots/ad.png "wide") — **altyazı** —
      altındaki cümle. Görselin markdown başlığı `"wide"`, kartın ızgaranın
      tamamını kaplamasını sağlar.

## [2026.09.23] - 2026-09-23

**Omarchy marketplace gönderimi öncesi proaktif güvenlik geçişi**

Omarchy marketplace'e gönderilmeden önce, ada dışarıdan aldığı her şeye bir
güvenilirlik ve güvenlik taraması yapıldı: bildirimlerden ve medya
oynatıcılardan gelen metinler, dışarıya açılan komutlar, arka plan
süreçleri ve ayar dosyası. Tüm bulgular bir inceleyicinin üstüne gelmesini
beklemeden önceden düzeltildi — görsel bir değişiklik yok; aynı ada, daha
zor donan, şaşırtılan veya metin enjekte edilemeyen hâli.

### Fixed

- Bildirimlerden, medya oynatıcılardan, ses mikserinden ve IPC komutlarından
  gelen metin artık her zaman düz metin olarak ve adaya girerken uzunluk
  sınırıyla gösteriliyor; düşmanca ya da bozuk bir uygulama artık arayüze
  stilili markup sıvayamıyor veya etiketi sınırsız büyütemiyor.
- Daha önce süresiz çalışan dış komutlar (ses seviyesi değişimleri,
  bluetooth/wifi/pil okumaları, medya oynatıcı eylemleri) artık süre
  sınırına bağlı; bunları koruyan arka plan kilitleri de takılı kalırsa
  kendiliğinden toparlanıyor — tek bir asılı komut artık yeniden yükleyene
  kadar yoklamayı veya düğmeleri donduramıyor.
- Zamanlanmış bir alarmı kapartmak, uyarının aldığı klavye kilidini artık
  gerçekten bırakıyor; ekranda açıklama yokken ada kilitli ve klavye
  manipülasyonu elinde kalıyor.
- Şarkı sözü araması ve durum anlık görüntüsü süreci artık takılma
  süre sınırına sahip — bir parça değişimi söz penceresini sonsuza kadar
  "aranıyor" bırakamıyor, asılı bir anlık görüntü ada da gösterdiği her
  değeri yeniden yükleyene kadar donduramıyor.
- Parça kuyruğu paneli boyut bakımından sınırlandırıldı ve her satırın
  konum farkı artık her tikte baştan hesaplanmıyor; dev bir kuyruk
  bildiren bir oynatıcı paneli sınırsız büyütemiyor veya O(N²) maliyet
  yükleyemiyor.
- Ses mikseri ve oynatıcı değiştirici satırları, içerikleri gerçekten
  değiştiğinde yeniden kuruluyor; her yenilemede her satırı söküp
  yeniden oluşturmuyor.
- Bir ekranda ayar kaydetmek artık disktekiyle birleşiyor ve yalnızca o
  ekranın gerçekten değiştirdiği anahtarları yazıyor; iki monitor neredeyse
  aynı anda kaydettiğinde birbirinin seçimini artık ezmeyor (son yazan
  kazanır).
- Uzaktaki kapak ve şarkı sözü indirmeleri boyut bakımından sınırlandırılıyor,
  eski önbellek dosyaları temizleniyor; davranış bozuk bir uç nokta diski
  dolduramıyor.
- Geçici durum artık `/tmp` altında öngörülebilir, paylaşılan bir yolda
  durmuyor: betik oturumun özel çalışma zamanı dizinini tercih ediyor, yoksa
  kullanıcının kendi önbelleğine düşüyor; her çalıştırmada sahip, tür ve izin
  doğrulanıp sembolik bağlantılar reddediliyor. Bitiş zili PID'i de yalnızca bu
  örneğin başlattığı bir sürece aitse sinyalleniyor.
- YouTube ve şarkı sözü yanıtları artık tümüyle kabuğun belleğine
  alınmıyor: alırken zorla uygulanan bir bayt tavanıyla sınırlandırılmış geçici
  bir dosyaya akıtılıyor (chunked ya da uzunluksuz dev bir yanıt emilmek yerine
  kesiliyor) ve arayüzde gösterilen kapak görseli sınırlandırılmış yerel önbellek
  dosyası — asla uzak bir küçük resim URL'si değil.
- YouTube kapak doğrulaması artık boyutu hiç doğrulanamayan bir görseli
  bayt büyüklüğüne bakarak kabul etmek yerine tamamen reddediyor — küçük bir
  dosya yine de devasa bir çözülmüş boyut bildirebilir; sabit bir üst sınır
  (kenar başına 4096, toplamda 16 megapiksel) artık zaten var olan
  "çok küçük" (yer tutucu) kontrolünün yanında bunu da engelliyor.

## [2026.08.17] - 2026-08-17

**YouTube kapakları, İngilizce olmayan yerellerde düzeltildi**

tr_TR.UTF-8 gibi yerellerde glibc'nin regex motoru [A-Za-z]'yi düz bir bayt
aralığı değil, sıralamaya duyarlı bir aralık olarak ele alır. Bu, backend.sh
içindeki video-id eşleştirmesini, Türkçe sıralamanın algılanan A-Z/a-z
aralığının dışına yerleştirdiği harf içeren her id'de sessizce bozdu; ada da
tek video için kapak çekmek yerine boş bir kapağa düşüyordu.

### Fixed

- YouTube kapak görseli birçok videoda C olmayan yereller altında çekilemedi
  (tr_TR.UTF-8'de doğrulandı) — video-id regex'i artık sistem yerelinden
  bağımsız olarak C yerelinde eşleştiriliyor.

## [2026.08.16] - 2026-08-16

**Kayan ayarlar, ve gri olmayan üç tema**

Ayarlar penceresi okunaklıydı ama durağandı: her kontrol, durum değiştirmek
için kesip geçiyordu. Artık ne yaptığını canlandırıyor — seçim kayıyor,
anahtarlar kayıyor, bölümler belirerek açılıyor — ve sonunda seçmek için
kullanıldığı temayı kendisi de takip ediyor. Gold, Amber ve Red, dört nötr
temaya katılıyor.

### Added

- Gold, Amber ve Red temaları. Her biri başka bir nötr yerine renkli bir koyu
  taban üzerine kurulu; böylece yüzey, vurgu rengi doğrulamadan önce rengin
  ipucunu verir.
- Ayarlarda klavye ile gezinme — Yukarı ve Aşağı, bölümler arasında gezer.

### Changed

- Ayarlar penceresi, Umbra'ya sabit kalmak yerine aktif temayı izler ve
  paletler arasında kesmek yerine geçiş yapar.
- Kenar çubuğundaki aktif bölüm artık öğeler arasında kayan tek bir gösterge;
  her satırın kendi arka planını silip belirtmesi yerine.
- Açık/kapalı kontrolleri ON ve OFF okuyan haplar değil gerçek kayan
  anahtarlar; segmentli seçiciler de seçilen seçeneğe tek bir vurguyu
  kaydırır.
- Tema kartları, her temanın kendi dolgu, ince çizgi ve vurgusuyla çizilmiş
  minyatür adalardır; kademeli girişli bir ızgara olarak dizilir.
- Bölüm değiştirmek, yeni içeriği sert kesim yerine belirip yükselterek
  gösterir.
- Görünüm; her biri tek bir iş yapan Theme, Borders ve Media Panel olmak
  üzere üç gruba ayrıldı; içine sıkışmış başıboş cümleli tek ve muğlak bir
  Surfaces grubunun yerini aldı.

### Fixed

- Çan test düğmesi, bir ses çalarken artık Stop'a dönüşüyor ve onu gerçekten
  durdurabiliyor; her tıklamada sesi sessizce yeniden başlatmak yerine.
- Çan seçici pencerenin sağ kenarından taşıyordu — on bir sesten dördüne hiç
  erişilemiyordu. Artık sarıyor, ve seçmek onu çalıyor.

### Removed

- Hava durumu, tamamen. Her tazelenmede iki ağ çağrısı ve bir konum sorgusu
  gerektiriyordu; adada ise hiçbir şey onu göstermiyordu.
- Arayüzün çoktan çağırmayı bıraktığı dört ölü backend komutu (volume,
  mic-volume, brightness, seek) ve dokuz kullanılmayan arayüz metni.

### Shots

- ![Amber temasında ayarlar penceresinin Görünüm bölümü, ızgara halinde yedi
  tema kartı](screenshots/changelog/themes.png "wide") — **Yedi tema,
  temalarıyla gösteriliyor** — Her kart, o temanın kendi renkleriyle
  küçültülmüş bir ada çiziyor. Aktif olan, vurgu renginde bir parıltı ve bir
  onay rozeti taşıyor — ve çevresindeki pencere de o temayı giyiyor.
- ![Bir satıra sarılmış on bir melodi çipiyle zaman araçları ayarları](screenshots/changelog/chime-test.png)
  — **On bir melodi, hepsine erişilebilir** — Eski seçici yedinci sesten
  sonra pencerenin kenarından taşıyordu. Artık seçince çalıyor — duyamayacağın
  bir sesi seçmek bir seçim değildir.
- ![Kayan anahtarlar ve segmentli süre seçiciyle bildirim ayarları](screenshots/changelog/settings-switches.png)
  — **Kayan anahtarlar** — Konum ve dolgu, 10px'lik bir kelime yerine açık ya
  da kapalı diyor — ve süre seçici, iki segmenti yeniden boyamak yerine tek
  bir vurguyu kaydırıyor.

## [2026.08.15] - 2026-08-15

**Artık zamanı tutuyor — ve sürenin dolduğunu da söylüyor**

Zamanlayıcı, turlu kronometre, odak döngüsü ve alarm; genişliği bölüşen dört
ayrı parça yerine yeniden akort olan tek bir enstrüman olarak yeniden
kuruldu. Bitiş bir olaydır: ada şekil değiştirir, çalar ve cevaplanmayı
bekler. Çalışmaya devam eden bir araç, kapalı pill üzerinde görünür kalır.

### Added

- Zaman araçları: dört modlu tek bir enstrüman olarak zamanlayıcı, turlu
  kronometre, odak döngüsü ve alarm.
- Çalan ve bekleyen bir bitiş kartı — Esc, Boşluk, Enter ya da bir tıkla
  kapatılır, ama belirdiği yerde duran imleçle değil.
- Çalışan bir araç, kapalı pill üzerinde kapsül olarak durur; son bir dakikada
  kehribara döner ve tempoyu ikiye katar.
- Gerçek donanım ya da uygulama durumunu beklemeden her widget'ı denemek için
  IPC kısayollarıyla dolu bir Makefile.

### Shots

- ![Zaman sayfası, çalışan bir zamanlayıcı, kare hücrelerden oluşan bir
  ilerleme şeridi, süre ön ayarları ve dört modlu bir ray](screenshots/time-tools.png "wide")
  — **Tek enstrüman, dört mod** — Okuma, saatle aynı 5×7 matrisi kullanır,
  rakamları aynı şekilde yuvarlanır; ilerleme de altına park edilmiş bir çubuk
  yerine o aynı kare hücrelerden çizilir.
- !["Süre doldu" okuyan ve kapat düğmeli bir bitiş kartı](screenshots/time-alert.png)
  — **Bitiş bir olaydır** — Esc, Boşluk, Enter ya da bir tık — ama belirdiği
  yerde duran imleçle değil, adanın kapanmasıyla da değil.
- ![Kapalı pill üzerinde çalışan bir zamanlayıcı taşıyan yeşil bir
  kapsül](screenshots/time-capsule.png) — **Kapalıyken de sayıyor** — Mod
  simgesi, canlı değer, boşalan bir çizgi ve ilerleyen bir ışık. Son dakikada
  kehribar ve iki kat hız.

## [2026.08.14] - 2026-08-14

**Aramalar, uygulama başına mikser ve sırada bekleyenler**

Gelen aramalar yüzeyi tamamen kendine alır, ses çıkaran her uygulama kendi
fader'ını alır ve oynatıcının bildirdiği sıra, okunabilir bir şeye dönüşür.

### Added

- Gelen arama yönetimi; herhangi bir uygulamanın API'sinden değil, eş zamanlı
  çalma ve kayıt akışlarından çıkarılır — böylece Signal, Telegram ve WhatsApp
  tek bir sezgisel yöntemle kapsanır.
- Uygulama başına ses mikseri; akış yerine uygulamaya göre gruplandığı için
  dört sekmeli bir tarayıcı tek satırdır.
- Sıradaki parça paneli; çoğu oynatıcı hiç bildirmediği için deneysel olarak
  işaretlendi.

### Shots

- ![Kabul ve reddet düğmeleri olan gelen arama kartı](screenshots/call.png) —
  **Projedeki tek renk** — Kabul ve reddet üzerindeki yeşil ve kırmızı —
  yanlış tahminin gerçekten bir şeye mal olduğu iki kontrol.

## [2026.08.09] - 2026-08-09

**Temalar, kompakt bir oynatıcı ve yüzey olan ses**

Seçebileceğin dört palet, tam paneli istemeyenler için yalnızca oynatıcılı bir
pill ve gerçek sesten çizilen bir spektrum.

### Added

- Dört tema — Siyah, Umbra, Gri ve Beyaz — aynı anda adaya, panellerine ve
  bildirimlerine uygulanır.
- Kompakt medya kontrolleri: yoldan çeken yalnızca oynatıcılı bir pill.
- Mini oynatıcıda bir ilerleme şeridi.
- Gerçek cava verisini paylaşan Dalga, Canlı ve Sakin animasyon varyantları;
  Yumuşak, Dengeli veya Cesur yoğunlukta.

### Shots

- ![Canlı ses spektrumlu açılmış Umbra medya paneli](screenshots/changelog/media-animation.png "wide")
  — **Yüzey olan ses** — Dalga, Canlı ve Sakin varyantları gerçek cava
  verisini paylaşır; görünürlük Yumuşak, Dengeli veya Cesur ayarlanabilir.
- ![İlerleme şeritli kompakt yalnızca-oynatıcı pill](screenshots/changelog/mini-player.png)
  — **Yalnızca oynatıcı** — Durağan bir masaüstü için: pill parçayı ve
  ilerlemesini taşır, başka hiçbir şeyi.

## [2026.08.06] - 2026-08-06

**İki dil, senkronize sözler ve ayrılmadan yanıtlama**

Arayüzün tamamı, yeniden yükleme olmadan İngilizce ve Türkçe arasında kendini
yeniden etiketler; bildirimler yerinde yanıtlanabilir ve sözler, parçayla
zamanında gelir.

### Added

- İngilizce ve Türkçe, canlı değiştirilir — her metin sıradan bir özellik,
  bu yüzden dili değiştirmek onu okuyan her bağlamayı yeniden değerlendirir.
- Destekleyen bildirimlerde satır içi yanıt.
- LRCLIB'den, yerel olarak önbelleğe alınmış senkronize sözler.

### Shots

- ![Geçerli satırın vurgulandığı sözler paneli](screenshots/lyrics.png) —
  **Söylenen satır** — Vurgu, senkronize sözlerin tüm anlamıdır; panel de bu
  yüzden onunla açılır.
- ![Satır içi yanıt alanlı bir bildirim](screenshots/reply.png) —
  **Ayrılmadan yanıtlama** — Destekleyen bildirimler için — geri kalanı
  aksiyonlarını korur.

## [2026.08.05] - 2026-08-05

**İlk sürüm**

Üst kenara sabitlenmiş, her zaman üstte duran tek bir yüzey: imlecin altında
medya kontrollerine, canlı ölçerlere ve pixel-art saate büyüyen kompakt bir
pill.

### Added

- Adanın kendisi — hover ile büyür, ayrılışta 90ms'lik lütuf süresi, ya da
  durağan bir masaüstü için tıkla-aç.
- Medya kontrolleri; ses, parlaklık ve mikrofon ölçerleri; mikrofon ve kamera
  için cihaz göstergeleri.
- 5×7 matristen pixel, segment ve düz stillerle çizilen bir pixel-art saat.

### Shots

- ![Kapalı pill](screenshots/pill.png) — **Kapalı** — Ekranda söylenecek bir
  şey yokken duran şey.
- ![Pixel-art saat](screenshots/clock.png) — **Saat** — Yanmış hücrelerin
  arkasında isteğe bağlı bir canlı ızgara ile bir 5×7 matris.