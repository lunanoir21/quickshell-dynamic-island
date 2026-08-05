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
}
