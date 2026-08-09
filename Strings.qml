import QtQuick

// Every user-visible string in the island, in one place.
//
// Deliberately a plain object rather than Qt's .ts/qsTr machinery: that would
// need lrelease at build time and a QTranslator installed at startup, which is
// a lot of moving parts for a shell config that ships as loose QML files. These
// are ordinary properties, so switching `lang` re-evaluates every binding that
// reads them and the whole UI relabels itself with no reload.
//
// Adding a language means adding one more branch to each line below; adding a
// string means adding it here rather than inline, so nothing silently stays
// untranslated.
QtObject {
    id: root

    // "tr" or "en". Anything unrecognised falls back to English.
    property string lang: "en"
    readonly property bool tr: lang === "tr"

    // ---------------------------------------------------------------- media
    readonly property string nothingPlaying: tr ? "Bir şey çalmıyor" : "Nothing playing"
    readonly property string unknownArtist: tr ? "Bilinmeyen sanatçı" : "Unknown artist"
    readonly property string media: tr ? "Medya" : "Media"
    // Shown in place of a total duration when the source never reports one
    // (browser tabs, streams). Not the word "live" as in livestream so much as
    // "this has no known end".
    readonly property string liveDuration: tr ? "canlı" : "live"

    // --------------------------------------------------------------- lyrics
    readonly property string lyrics: tr ? "Şarkı sözleri" : "Lyrics"
    readonly property string lyricsSearching: tr ? "Sözler aranıyor…" : "Searching for lyrics…"
    readonly property string lyricsNotFound: tr ? "Şarkı sözü bulunamadı" : "No lyrics found"
    readonly property string lyricsUnsynced: tr ? "Zamanlama bilgisi yok" : "Not time-synced"

    // ---------------------------------------------------------------- meters
    readonly property string volumeShort: tr ? "SES" : "VOL"
    readonly property string brightnessShort: tr ? "IŞIK" : "LIGHT"
    readonly property string micShort: tr ? "MİK" : "MIC"

    // ---------------------------------------------------------------- device
    readonly property string cameraOn: tr ? "Kamera kullanılıyor" : "Camera in use"
    readonly property string cameraOff: tr ? "Kamera kapatıldı" : "Camera turned off"
    readonly property string cameraOnDetail: tr ? "Bir uygulama görüntü alıyor" : "An app is capturing video"
    readonly property string cameraOffDetail: tr ? "Görüntü akışı sonlandırıldı" : "Video stream ended"
    readonly property string micOn: tr ? "Mikrofon etkin" : "Microphone active"
    readonly property string micOff: tr ? "Mikrofon sessize alındı" : "Microphone muted"
    readonly property string micOffDetail: tr ? "Ses girişi durduruldu" : "Audio input stopped"
    function micOnDetail(value) {
        return tr ? "Giriş seviyesi  %" + value : "Input level  " + value + "%"
    }

    // --------------------------------------------------------------- battery
    function charging(percent) {
        return tr ? "󰂄  Şarj ediliyor  " + percent + "%"
                  : "󰂄  Charging  " + percent + "%"
    }

    // ---------------------------------------------------------- notifications
    readonly property string notification: tr ? "Bildirim" : "Notification"
    readonly property string newNotification: tr ? "Yeni bildirim" : "New notification"
    readonly property string emptyNotification: tr ? "Bildirim içeriği bulunmuyor." : "No notification content."
    readonly property string replyPlaceholder: tr ? "Yanıtla…" : "Reply…"

    // ----------------------------------------------------------------- calls
    readonly property string voiceCall: tr ? "Sesli görüşme" : "Voice call"
    readonly property string incomingCall: tr ? "Gelen arama" : "Incoming call"
    readonly property string callConnecting: tr ? "Bağlanıyor…" : "Connecting…"
    readonly property string callFallbackApp: tr ? "Arama" : "Call"
    readonly property string accept: tr ? "Kabul et" : "Accept"
    readonly property string decline: tr ? "Reddet" : "Decline"

    // -------------------------------------------------------------- settings
    readonly property string settingsTitle: tr ? "Ayarlar" : "Settings"
    readonly property string settingsOn: tr ? "AÇIK" : "ON"
    readonly property string settingsOff: tr ? "KAPALI" : "OFF"

    // Sidebar sections
    readonly property string secAppearance: tr ? "Görünüm" : "Appearance"
    readonly property string secClock: tr ? "Saat" : "Clock"
    readonly property string secCalls: tr ? "Aramalar" : "Calls"
    readonly property string secNotifications: tr ? "Bildirimler" : "Notifications"
    readonly property string secMedia: tr ? "Medya" : "Media"
    readonly property string secGeneral: tr ? "Genel" : "General"

    // Section subtitles
    readonly property string secAppearanceSub: tr ? "Renkler ve yüzeyler" : "Colours and surfaces"
    readonly property string secClockSub: tr ? "Biçim ve çizim stili" : "Format and drawing style"
    readonly property string secCallsSub: tr ? "Gelen arama davranışı" : "Incoming call behaviour"
    readonly property string secNotificationsSub: tr ? "Kart süresi ve içeriği" : "Card duration and content"
    readonly property string secMediaSub: tr ? "Oynatıcı paneli" : "Player panel"
    readonly property string secGeneralSub: tr ? "Dil ve pencere" : "Language and window"

    // Group labels
    readonly property string grpTheme: tr ? "Tema" : "Theme"
    readonly property string grpSurfaces: tr ? "Yüzeyler" : "Surfaces"
    readonly property string grpStyle: tr ? "Stil" : "Style"
    readonly property string grpFormat: tr ? "Biçim" : "Format"
    readonly property string grpBehaviour: tr ? "Davranış" : "Behaviour"
    readonly property string grpTiming: tr ? "Zamanlama" : "Timing"
    readonly property string grpContent: tr ? "İçerik" : "Content"
    readonly property string grpPanel: tr ? "Panel" : "Panel"
    readonly property string grpMotion: tr ? "Hareket" : "Motion"
    readonly property string grpLanguage: tr ? "Dil" : "Language"
    readonly property string grpWindow: tr ? "Pencere" : "Window"

    // Theme names
    readonly property string themeBlack: tr ? "Siyah" : "Black"
    readonly property string themeUmbra: tr ? "Umbra" : "Umbra"
    readonly property string themeGray: tr ? "Gri" : "Gray"
    readonly property string themeWhite: tr ? "Beyaz" : "White"

    // Appearance
    readonly property string setBorders: tr ? "Kenarlıklar" : "Borders"
    readonly property string setBordersDesc: tr ? "Kartların çevresindeki ince hat" : "The hairline around cards"
    readonly property string setMediaSurface: tr ? "Medya yüzeyi" : "Media surface"
    readonly property string setMediaSurfaceDesc: tr ? "Oynatıcı temayı izlesin veya koyu kalsın" : "Follow the theme or keep the player dark"
    readonly property string mediaSurfaceTheme: tr ? "Tema" : "Theme"
    readonly property string mediaSurfaceDark: tr ? "Koyu" : "Dark"

    // Clock
    readonly property string clockStylePixel: tr ? "Piksel" : "Pixel"
    readonly property string clockStyleSegment: tr ? "Segment" : "Segment"
    readonly property string clockStylePlain: tr ? "Sade" : "Plain"
    readonly property string setClock24h: tr ? "24 saat formatı" : "24-hour clock"
    readonly property string setClock24hDesc: tr ? "Kapalıyken 12 saat ve ÖÖ/ÖS" : "12-hour with AM/PM when off"
    readonly property string setSeconds: tr ? "Saniye göster" : "Show seconds"
    readonly property string setSecondsDesc: tr ? "Büyük saatin yanındaki küçük hane" : "The small digits beside the clock"
    readonly property string setDateLine: tr ? "Tarih satırı" : "Date line"
    readonly property string setDateLineDesc: tr ? "Saatin altındaki gün ve ay" : "Day and month under the clock"
    readonly property string setClockGrid: tr ? "Işıksız ızgara" : "Dormant grid"
    readonly property string setClockGridDesc: tr ? "Yalnızca piksel stilinde görünür" : "Only visible in pixel style"

    // Calls
    readonly property string setCallAutoPopup: tr ? "Arama balonu otomatik açılsın" : "Auto-open call card"
    readonly property string setCallAutoPopupDesc: tr ? "Kapalıyken yalnız durum çubuğunda ikon çıkar" : "Only a status-strip icon when off"
    readonly property string setRingTimeout: tr ? "Çalma zaman aşımı" : "Ring timeout"
    readonly property string setRingTimeoutDesc: tr ? "Cevaplanmayan arama ne kadar ekranda kalsın" : "How long an unanswered call stays up"
    readonly property string setCallPulse: tr ? "Yeşil nabız halkası" : "Green pulse ring"
    readonly property string setCallPulseDesc: tr ? "Çalarken kapsülün etrafındaki animasyon" : "The animation around the capsule while ringing"

    // Notifications
    readonly property string setNotifDuration: tr ? "Görünme süresi" : "Visible for"
    readonly property string setNotifDurationDesc: tr ? "Kart kendiliğinden kapanana kadar" : "Until the card closes itself"
    readonly property string setInlineReply: tr ? "Satır içi yanıt" : "Inline reply"
    readonly property string setInlineReplyDesc: tr ? "Uygulama destekliyorsa yanıt kutusu" : "A reply box when the app supports it"
    readonly property string setAppIcon: tr ? "Uygulama simgesi" : "App icon"
    readonly property string setAppIconDesc: tr ? "Kapalıyken baş harf rozeti gösterilir" : "An initial badge is shown when off"

    // Media
    readonly property string setLyrics: tr ? "Şarkı sözleri" : "Lyrics"
    readonly property string setLyricsDesc: tr ? "LRCLIB'den eşzamanlı sözler" : "Time-synced lyrics from LRCLIB"
    readonly property string setSpectrum: tr ? "Spektrum çubukları" : "Spectrum bars"
    readonly property string setSpectrumDesc: tr ? "cava ile canlı frekans grafiği" : "Live frequency graph via cava"
    readonly property string setAlbumArt: tr ? "Albüm kapağı" : "Album art"
    readonly property string setAlbumArtDesc: tr ? "Kapalıyken yerine nota simgesi çıkar" : "A note glyph replaces it when off"
    readonly property string setCompactControls: tr ? "Mini oynatıcı modu" : "Mini player mode"
    readonly property string setCompactControlsDesc: tr
        ? "Hover kapalıyken yalnız kapak, parça adı ve kontroller"
        : "Only cover, title and controls when hover is off"
    readonly property string animWave: tr ? "Dalga" : "Wave"
    readonly property string animLive: tr ? "Canlı" : "Live"
    readonly property string animCalm: tr ? "Sakin" : "Calm"
    readonly property string setAnimationIntensity: tr ? "Animasyon belirginliği" : "Animation visibility"
    readonly property string setAnimationIntensityDesc: tr ? "Çubukların arka plandaki kontrastı" : "Bar contrast behind the content"
    readonly property string intensitySoft: tr ? "Hafif" : "Soft"
    readonly property string intensityBalanced: tr ? "Dengeli" : "Balanced"
    readonly property string intensityBold: tr ? "Belirgin" : "Bold"

    // General
    readonly property string setLanguage: tr ? "Arayüz dili" : "Interface language"
    readonly property string setLanguageDesc: tr ? "Saatin gün ve ay adlarını da değiştirir" : "Also changes the clock's day and month names"
    readonly property string setPinned: tr ? "Panel sabit kalsın" : "Keep panel pinned"
    readonly property string setPinnedDesc: tr ? "Fare ayrılınca kapanmaz" : "Stays open when the pointer leaves"
    readonly property string setHoverOpen: tr ? "Üzerine gelince aç" : "Open on hover"
    readonly property string setHoverOpenDesc: tr
        ? "Kapalıyken mini kontroller ve tıklayarak açma kullanılır"
        : "When off, use compact controls and click to open"

    // Durations, written out rather than templated so a language that puts the
    // unit first (or drops the space) isn't forced into the Turkish shape.
    function seconds(value) { return tr ? value + " sn" : value + " s" }
}
