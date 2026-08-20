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

    // "tr" "en" "es" "fr" "de". Anything unrecognised falls back to English.
    property string lang: "en"
    readonly property bool tr: lang === "tr"
    readonly property bool es: lang === "es"
    readonly property bool fr: lang === "fr"
    readonly property bool de: lang === "de"

    // ---------------------------------------------------------------- media
    readonly property string nothingPlaying: tr ? "Bir şey çalmıyor" : es ? "Nada reproduciéndose" : fr ? "Rien en lecture" : de ? "Nichts wird abgespielt" : "Nothing playing"
    readonly property string unknownArtist: tr ? "Bilinmeyen sanatçı" : es ? "Artista desconocido" : fr ? "Artiste inconnu" : de ? "Unbekannter Künstler" : "Unknown artist"
    readonly property string media: tr ? "Medya" : es ? "Multimedia" : fr ? "Média" : de ? "Medien" : "Media"
    // Shown in place of a total duration when the source never reports one
    // (browser tabs, streams). Not the word "live" as in livestream so much as
    // "this has no known end".
    readonly property string liveDuration: tr ? "canlı" : es ? "en vivo" : fr ? "en direct" : de ? "live" : "live"

    // ------------------------------------------------------------ app mixer
    readonly property string appVolumeTitle: tr ? "Uygulama sesleri" : es ? "Volumen de apps" : fr ? "Volume des apps" : de ? "App-Lautstärke" : "App volume"
    readonly property string appVolumeEmpty: tr ? "Ses çalan uygulama yok" : es ? "Ninguna app reproduciendo audio" : fr ? "Aucune app ne lit de l'audio" : de ? "Keine App spielt Audio" : "No app is playing audio"

    // ----------------------------------------------------------- time tools
    readonly property string timeTitle: tr ? "Zaman" : es ? "Tiempo" : fr ? "Temps" : de ? "Zeit" : "Time"
    // Mode names double as the rail chip labels and the stage eyebrow, so they
    // stay short enough to read at 8px in a 150px-wide chip.
    readonly property string tmTimer: tr ? "ZAMANLAYICI" : es ? "TEMPORIZADOR" : fr ? "MINUTERIE" : de ? "TIMER" : "TIMER"
    readonly property string tmStopwatch: tr ? "KRONOMETRE" : es ? "CRONÓMETRO" : fr ? "CHRONO" : de ? "STOPUHR" : "STOPWATCH"
    readonly property string tmFocus: tr ? "ODAK" : es ? "FOCO" : fr ? "FOCUS" : de ? "FOKUS" : "FOCUS"
    readonly property string tmAlarm: tr ? "ALARM" : es ? "ALARM" : fr ? "ALARM" : de ? "ALARM" : "ALARM"

    // Actions are named for what happens when they are used, and keep the same
    // word everywhere they appear — the button that says "Duraklat" is the one
    // that produced the paused state the label above it reports.
    readonly property string tmStart: tr ? "Başlat" : es ? "Iniciar" : fr ? "Démarrer" : de ? "Start" : "Start"
    readonly property string tmPause: tr ? "Duraklat" : es ? "Pausar" : fr ? "Pause" : de ? "Pause" : "Pause"
    readonly property string tmResume: tr ? "Sürdür" : es ? "Reanudar" : fr ? "Reprendre" : de ? "Fortsetzen" : "Resume"
    readonly property string tmArm: tr ? "Kur" : es ? "Configurar" : fr ? "Régler" : de ? "Einstellen" : "Set"
    readonly property string tmDisarm: tr ? "Kapat" : es ? "Apagar" : fr ? "Éteindre" : de ? "Ausschalten" : "Turn off"

    readonly property string tmPhaseFocus: tr ? "ODAK" : es ? "FOCO" : fr ? "FOCUS" : de ? "FOKUS" : "FOCUS"
    readonly property string tmPhaseBreak: tr ? "MOLA" : es ? "PAUSA" : fr ? "PAUSE" : de ? "PAUSE" : "BREAK"
    readonly property string tmRunning: tr ? "Çalışıyor" : es ? "En marcha" : fr ? "En cours" : de ? "Läuft" : "Running"
    readonly property string tmPaused: tr ? "Duraklatıldı" : es ? "Pausado" : fr ? "En pause" : de ? "Pausiert" : "Paused"
    readonly property string tmReady: tr ? "Hazır" : es ? "Listo" : fr ? "Prêt" : de ? "Bereit" : "Ready"
    readonly property string tmAlarmArmed: tr ? "Alarm kurulu" : es ? "Alarma activada" : fr ? "Alarme réglée" : de ? "Alarm gesetzt" : "Alarm set"
    readonly property string tmAlarmOff: tr ? "Alarm kapalı" : es ? "Alarma apagada" : fr ? "Alarme éteinte" : de ? "Alarm aus" : "Alarm off"
    readonly property string tmLapsEmpty: tr ? "Henüz tur yok" : es ? "Sin vueltas aún" : fr ? "Aucun tour pour l'instant" : de ? "Noch keine Runden" : "No laps yet"
    readonly property string tmCycles: tr ? "Tamamlanan" : es ? "Completados" : fr ? "Terminés" : de ? "Abgeschlossen" : "Completed"

    // Completion cards. The title states what happened; the detail says which
    // of the four tools it was, since the card can arrive long after the page
    // that started it was closed.
    readonly property string tmTimerDone: tr ? "Süre doldu" : es ? "Tiempo agotado" : fr ? "Temps écoulé" : de ? "Zeit abgelaufen" : "Time's up"
    readonly property string tmFocusDone: tr ? "Odak tamamlandı" : es ? "Foco completado" : fr ? "Focus terminé" : de ? "Fokus beendet" : "Focus complete"
    readonly property string tmBreakDone: tr ? "Mola bitti" : es ? "Pausa terminada" : fr ? "Pause finie" : de ? "Pause vorbei" : "Break over"
    readonly property string tmAlarmFired: tr ? "Alarm" : es ? "Alarma" : fr ? "Alarme" : de ? "Alarm" : "Alarm"
    function tmTimerDoneDetail(minutes) {
        return tr ? (minutes + " dakikalık zamanlayıcı bitti")
                  : es ? (minutes + " minutos de temporizador terminados")
                  : fr ? (minutes + " minutes de minuteur terminées")
                  : de ? (minutes + " Minuten Timer abgelaufen")
                  : (minutes + " minute timer finished")
    }
    readonly property string tmFocusDoneDetail: tr ? "5 dakika mola vakti" : es ? "Toca 5 min de pausa" : fr ? "Pause de 5 minutes" : de ? "5 Minuten Pause" : "Take a 5 minute break"
    readonly property string tmBreakDoneDetail: tr ? "Odağa geri dön" : es ? "Volver al foco" : fr ? "Retour au focus" : de ? "Zurück zum Fokus" : "Back to focus"
    function tmAlarmFiredDetail(clock) {
        return tr ? (clock + " alarmı çaldı")
                  : es ? (clock + " alarma sonó")
                  : fr ? (clock + " alarme a sonné")
                  : de ? (clock + " Alarm ausgelöst")
                  : (clock + " alarm")
    }
    readonly property string tmDismiss: tr ? "Kapat" : es ? "Cerrar" : fr ? "Fermer" : de ? "Schließen" : "Dismiss"

    // -------------------------------------------------------- quick settings
    readonly property string quickSettingsTitle: tr ? "Hızlı ayarlar" : es ? "Ajustes rápidos" : fr ? "Réglages rapides" : de ? "Schnelleinstellungen" : "Quick settings"
    readonly property string qsDnd: tr ? "Rahatsız Etme" : es ? "No molestar" : fr ? "Ne pas déranger" : de ? "Nicht stören" : "Do Not Disturb"
    readonly property string qsBluetooth: tr ? "Bluetooth" : es ? "Bluetooth" : fr ? "Bluetooth" : de ? "Bluetooth" : "Bluetooth"
    readonly property string qsWifi: tr ? "Wi-Fi" : es ? "Wi-Fi" : fr ? "Wi-Fi" : de ? "Wi-Fi" : "Wi-Fi"
    readonly property string qsLock: tr ? "Kilitle" : es ? "Bloquear" : fr ? "Verrouiller" : de ? "Sperren" : "Lock"
    readonly property string qsLogout: tr ? "Oturumu Kapat" : es ? "Cerrar sesión" : fr ? "Déconnexion" : de ? "Abmelden" : "Log Out"

    // ----------------------------------------------------------------- queue
    readonly property string queueTitle: tr ? "Sırada" : es ? "A continuación" : fr ? "Suivant" : de ? "Als Nächstes" : "Up next"
    // Marks the panel itself, not just the settings row: the feature depends on
    // an optional MPRIS interface most players skip, so the limitation has to be
    // visible where the user meets it.
    readonly property string queueExperimental: tr ? "DENEYSEL" : es ? "EXPERIMENTAL" : fr ? "EXPÉRIMENTAL" : de ? "EXPERIMENTELL" : "EXPERIMENTAL"
    readonly property string queueUnsupported: tr ? "Bu oynatıcı kuyruk bilgisi vermiyor" : es ? "Este reproductor no informa la cola" : fr ? "Ce lecteur ne signale pas de file" : de ? "Dieser Player meldet keine Warteschlange" : "This player doesn't report a queue"
    readonly property string queueEmpty: tr ? "Kuyruk boş" : es ? "Cola vacía" : fr ? "File vide" : de ? "Warteschlange leer" : "The queue is empty"

    // --------------------------------------------------------------- lyrics
    readonly property string lyrics: tr ? "Şarkı sözleri" : es ? "Letra" : fr ? "Paroles" : de ? "Songtext" : "Lyrics"
    readonly property string lyricsSearching: tr ? "Sözler aranıyor…" : es ? "Buscando letra…" : fr ? "Recherche des paroles…" : de ? "Suche Songtext…" : "Searching for lyrics…"
    readonly property string lyricsNotFound: tr ? "Şarkı sözü bulunamadı" : es ? "Letra no encontrada" : fr ? "Paroles non trouvées" : de ? "Songtext nicht gefunden" : "No lyrics found"
    readonly property string lyricsUnsynced: tr ? "Zamanlama bilgisi yok" : es ? "Sin sincronización" : fr ? "Non synchronisé" : de ? "Nicht synchronisiert" : "Not time-synced"

    // ---------------------------------------------------------------- meters
    readonly property string volumeShort: tr ? "SES" : es ? "VOL" : fr ? "VOL" : de ? "LAUT" : "VOL"
    readonly property string brightnessShort: tr ? "IŞIK" : es ? "LUZ" : fr ? "LUM" : de ? "HELL" : "LIGHT"
    readonly property string micShort: tr ? "MİK" : es ? "MIC" : fr ? "MIC" : de ? "MIK" : "MIC"

    // ---------------------------------------------------------------- device
    readonly property string cameraOn: tr ? "Kamera kullanılıyor" : es ? "Cámara en uso" : fr ? "Caméra en cours d'utilisation" : de ? "Kamera in Verwendung" : "Camera in use"
    readonly property string cameraOff: tr ? "Kamera kapatıldı" : es ? "Cámara desactivada" : fr ? "Caméra désactivée" : de ? "Kamera deaktiviert" : "Camera turned off"
    readonly property string cameraOnDetail: tr ? "Bir uygulama görüntü alıyor" : es ? "Una app está capturando video" : fr ? "Une app capture la vidéo" : de ? "Eine App nimmt Video auf" : "An app is capturing video"
    readonly property string cameraOffDetail: tr ? "Görüntü akışı sonlandırıldı" : es ? "Transmisión de video finalizada" : fr ? "Flux vidéo terminé" : de ? "Video-Stream beendet" : "Video stream ended"
    readonly property string micOn: tr ? "Mikrofon etkin" : es ? "Micrófono activo" : fr ? "Micro actif" : de ? "Mikrofon aktiv" : "Microphone active"
    readonly property string micOff: tr ? "Mikrofon sessize alındı" : es ? "Micrófono silenciado" : fr ? "Micro muet" : de ? "Mikrofon stumm" : "Microphone muted"
    readonly property string micOffDetail: tr ? "Ses girişi durduruldu" : es ? "Entrada de audio detenida" : fr ? "Entrée audio arrêtée" : de ? "Audioeingabe gestoppt" : "Audio input stopped"
    function micOnDetail(value) {
        return tr ? "Giriş seviyesi  %" + value
                  : es ? "Nivel de entrada  " + value + "%"
                  : fr ? "Niveau d'entrée  " + value + "%"
                  : de ? "Eingangspegel  " + value + "%"
                  : "Input level  " + value + "%"
    }

    // --------------------------------------------------------------- battery
    function charging(percent) {
        return tr ? "󰂄  Şarj ediliyor  " + percent + "%"
                  : es ? "󰂄  Cargando  " + percent + "%"
                  : fr ? "󰂄  En charge  " + percent + "%"
                  : de ? "󰂄  Lädt  " + percent + "%"
                  : "󰂄  Charging  " + percent + "%"
    }
    readonly property string batteryLow: tr ? "Pil kritik seviyede" : es ? "Batería crítica" : fr ? "Batterie critique" : de ? "Batterie kritisch" : "Battery critically low"
    function batteryLowDetail(percent) {
        return tr ? "Kalan  %" + percent + " — şarj cihazını bağlayın"
                  : es ? "Queda  " + percent + "% — conecta el cargador"
                  : fr ? "Restant  " + percent + "% — branchez le chargeur"
                  : de ? "Noch  " + percent + "% — Ladegerät anschließen"
                  : percent + "% left — plug in the charger"
    }

    // ---------------------------------------------------------- notifications
    readonly property string notification: tr ? "Bildirim" : es ? "Notificación" : fr ? "Notification" : de ? "Benachrichtigung" : "Notification"
    readonly property string newNotification: tr ? "Yeni bildirim" : es ? "Nueva notificación" : fr ? "Nouvelle notification" : de ? "Neue Benachrichtigung" : "New notification"
    readonly property string emptyNotification: tr ? "Bildirim içeriği bulunmuyor." : es ? "Sin contenido de notificación." : fr ? "Aucun contenu de notification." : de ? "Kein Benachrichtigungsinhalt." : "No notification content."
    readonly property string replyPlaceholder: tr ? "Yanıtla…" : es ? "Responder…" : fr ? "Répondre…" : de ? "Antworten…" : "Reply…"

    // ----------------------------------------------------------------- calls
    readonly property string voiceCall: tr ? "Sesli görüşme" : es ? "Llamada de voz" : fr ? "Appel vocal" : de ? "Sprachanruf" : "Voice call"
    readonly property string incomingCall: tr ? "Gelen arama" : es ? "Llamada entrante" : fr ? "Appel entrant" : de ? "Eingehender Anruf" : "Incoming call"
    readonly property string callConnecting: tr ? "Bağlanıyor…" : es ? "Conectando…" : fr ? "Connexion…" : de ? "Verbinde…" : "Connecting…"
    readonly property string callFallbackApp: tr ? "Arama" : es ? "Llamada" : fr ? "Appel" : de ? "Anruf" : "Call"
    readonly property string accept: tr ? "Kabul et" : es ? "Aceptar" : fr ? "Accepter" : de ? "Annehmen" : "Accept"
    readonly property string decline: tr ? "Reddet" : es ? "Rechazar" : fr ? "Refuser" : de ? "Ablehnen" : "Decline"

    // Sidebar sections
    readonly property string secAppearance: tr ? "Görünüm" : es ? "Apariencia" : fr ? "Apparence" : de ? "Erscheinungsbild" : "Appearance"
    readonly property string secClock: tr ? "Saat" : es ? "Reloj" : fr ? "Horloge" : de ? "Uhr" : "Clock"
    readonly property string secTimeTools: tr ? "Zaman Araçları" : es ? "Herramientas de tiempo" : fr ? "Outils de temps" : de ? "Zeitwerkzeuge" : "Time Tools"
    readonly property string secMedia: tr ? "Oynatıcı" : es ? "Reproductor" : fr ? "Lecteur" : de ? "Player" : "Player"
    readonly property string secCalls: tr ? "Aramalar" : es ? "Llamadas" : fr ? "Appels" : de ? "Anrufe" : "Calls"
    readonly property string secNotifications: tr ? "Bildirimler" : es ? "Notificaciones" : fr ? "Notifications" : de ? "Benachrichtigungen" : "Notifications"
    readonly property string secPanels: tr ? "Paneller" : es ? "Paneles" : fr ? "Panneaux" : de ? "Panels" : "Panels"
    readonly property string secGeneral: tr ? "Genel" : es ? "General" : fr ? "Général" : de ? "Allgemein" : "General"

    // Section subtitles
    readonly property string secAppearanceSub: tr ? "Renkler ve yüzeyler" : es ? "Colores y superficies" : fr ? "Couleurs et surfaces" : de ? "Farben und Oberflächen" : "Colours and surfaces"
    readonly property string secClockSub: tr ? "Biçim ve çizim stili" : es ? "Formato y estilo de dibujo" : fr ? "Format et style de dessin" : de ? "Format und Zeichenstil" : "Format and drawing style"
    readonly property string secTimeToolsSub: tr ? "Zamanlayıcı, kronometre, odak ve alarm ayarları" : es ? "Temporizador, cronómetro, foco y ajustes de alarma" : fr ? "Minuterie, chrono, focus et réglages d'alarme" : de ? "Timer, Stoppuhr, Fokus und Alarm-Einstellungen" : "Timer, stopwatch, focus and alarm settings"
    readonly property string secMediaSub: tr ? "Görsel öğeler, spektrum, sözler ve kontroller" : es ? "Elementos visuales, espectro, letras y controles" : fr ? "Éléments visuels, spectre, paroles et contrôles" : de ? "Visuelle Elemente, Spektrum, Songtext und Steuerung" : "Visual elements, spectrum, lyrics and controls"
    readonly property string secCallsSub: tr ? "Gelen arama davranışı" : es ? "Comportamiento de llamadas entrantes" : fr ? "Comportement des appels entrants" : de ? "Verhalten bei eingehenden Anrufen" : "Incoming call behaviour"
    readonly property string secNotificationsSub: tr ? "Kart süresi ve içeriği" : es ? "Duración y contenido de la tarjeta" : fr ? "Durée et contenu de la carte" : de ? "Kartendauer und -inhalt" : "Card duration and content"
    readonly property string secPanelsSub: tr ? "Şeritteki çiplerin açtığı ek paneller" : es ? "Paneles extra que abren los chips de la tira" : fr ? "Panneaux supplémentaires ouverts par les puces de la barre" : de ? "Zusätzliche Panels, die die Chips der Leiste öffnen" : "The extra panels the strip's chips open"
    readonly property string secGeneralSub: tr ? "Dil ve pencere" : es ? "Idioma y ventana" : fr ? "Langue et fenêtre" : de ? "Sprache und Fenster" : "Language and window"

    // Group labels for Time Tools
    readonly property string grpTimePresets: tr ? "Hazır Süreler" : es ? "Preajustes" : fr ? "Préréglages" : de ? "Voreinstellungen" : "Default Presets"
    readonly property string grpTimePresetsNote: tr ? "Zamanlayıcı, odak oturumu ve mola için varsayılan dakikalar" : es ? "Minutos por defecto para temporizador, sesiones de foco y pausas" : fr ? "Minutes par défaut pour minuterie, sessions focus et pauses" : de ? "Standardminuten für Timer, Fokus-Sessions und Pausen" : "Default minutes for timer, focus sessions and breaks"
    readonly property string grpTimeChime: tr ? "Ses ve Uyarılar" : es ? "Sonido y alertas" : fr ? "Son et alertes" : de ? "Ton & Signal" : "Sound & Chime"
    readonly property string grpTimeChimeNote: tr ? "Zaman bitiminde çalacak melodi ve ses yüksekliği tercihleri" : es ? "Melodía y preferencias de volumen al terminar" : fr ? "Mélodie et préférences de volume à la fin" : de ? "Melodie und Lautstärke-Präferenzen beim Ende" : "Chime melody and volume level preferences upon finish"
    readonly property string grpTimeBehaviour: tr ? "Zamanlayıcı Davranışı" : es ? "Comportamiento del temporizador" : fr ? "Comportement de la minuterie" : de ? "Timer-Verhalten" : "Timer Behaviour"
    readonly property string grpTimeBehaviourNote: tr ? "Odak oturumu bittiğinde otomatik mola ve kart yönetimi" : es ? "Pausa automática y gestión de tarjetas al terminar el foco" : fr ? "Pause auto et gestion des cartes à la fin du focus" : de ? "Auto-Pause und Kartenverhalten beim Fokus-Ende" : "Auto-break trigger and completion card behavior"

    // Time Tools settings
    readonly property string setTimerDefault: tr ? "Varsayılan Zamanlayıcı" : es ? "Temporizador por defecto" : fr ? "Minuterie par défaut" : de ? "Standard-Timer" : "Default Timer"
    readonly property string setTimerDefaultDesc: tr ? "Zamanlayıcı açıldığında seçili hazır dakika" : es ? "Minuto predefinido seleccionado al abrir el temporizador" : fr ? "Minute préselectionnée à l'ouverture de la minuterie" : de ? "Vorausgewähltes Minuten-Preset beim Timer-Start" : "Default minute preset when timer starts"
    readonly property string setFocusDefault: tr ? "Odak Oturumu Süresi" : es ? "Duración de sesión de foco" : fr ? "Durée de session focus" : de ? "Fokus-Sitzungsdauer" : "Focus Session Duration"
    readonly property string setFocusDefaultDesc: tr ? "Pomodoro odaklanma oturumu süresi" : es ? "Duración de sesión de foco Pomodoro" : fr ? "Durée de session de focus Pomodoro" : de ? "Dauer der Pomodoro-Fokus-Sitzung" : "Pomodoro focus session duration"
    readonly property string setBreakDefault: tr ? "Mola Süresi" : es ? "Duración de pausa" : fr ? "Durée de pause" : de ? "Pausendauer" : "Break Duration"
    readonly property string setBreakDefaultDesc: tr ? "Odak oturumu sonrasındaki dinlenme molası" : es ? "Pausa de descanso tras la sesión de foco" : fr ? "Pause de repos après le focus" : de ? "Erholungspause nach dem Fokus" : "Rest break duration following focus"
    readonly property string setAutoStartBreak: tr ? "Otomatik Mola Başlat" : es ? "Iniciar pausa automáticamente" : fr ? "Démarrer la pause automatiquement" : de ? "Pause automatisch starten" : "Auto-start Break"
    readonly property string setAutoStartBreakDesc: tr ? "Odak bittiğinde mola sayacını doğrudan çalıştır" : es ? "Iniciar cuenta atrás de pausa directamente al terminar el foco" : fr ? "Lancer le compte à rebours de pause automatiquement à la fin du focus" : de ? "Pause-Countdown automatisch starten, wenn Fokus endet" : "Start break countdown automatically when focus ends"
    readonly property string setChimeVolume: tr ? "Melodi Ses Seviyesi" : es ? "Volumen de la melodía" : fr ? "Volume de la mélodie" : de ? "Signalton-Lautstärke" : "Chime Volume"
    readonly property string setChimeVolumeDesc: tr ? "Uyarı sesinin yükseklik kademesi" : es ? "Nivel de volumen para notificaciones de fin" : fr ? "Niveau de volume pour notifications de fin" : de ? "Lautstärkepegel für End-Benachrichtigungen" : "Volume level for finish notifications"
    readonly property string chimeVolSoft: tr ? "Hafif" : es ? "Suave" : fr ? "Doux" : de ? "Leise" : "Soft"
    readonly property string chimeVolNormal: tr ? "Normal" : es ? "Normal" : fr ? "Normal" : de ? "Normal" : "Normal"
    readonly property string chimeVolLoud: tr ? "Yüksek" : es ? "Alto" : fr ? "Fort" : de ? "Laut" : "Loud"
    readonly property string testChime: tr ? "Melodiyi Test Et" : es ? "Probar melodía" : fr ? "Tester la mélodie" : de ? "Melodie testen" : "Test Chime"

    // Group labels for Player
    readonly property string grpPlayerVisuals: tr ? "Görsel Öğeler" : es ? "Elementos visuales" : fr ? "Éléments visuels" : de ? "Visuelle Elemente" : "Visual Elements"
    readonly property string grpPlayerVisualsNote: tr ? "Albüm kapağı, frekans spektrumu, şarkı sözleri ve ilerleme çubuğu" : es ? "Portada, espectro de frecuencia, letras y barra de progreso" : fr ? "Pochette, spectre de fréquence, paroles et barre de progression" : de ? "Albumcover, Frequenzspektrum, Songtext und Fortschrittsbalken" : "Album art, frequency spectrum, lyrics and progress line"
    readonly property string grpPlayerBehavior: tr ? "Oynatıcı Davranışı" : es ? "Comportamiento del reproductor" : fr ? "Comportement du lecteur" : de ? "Player-Verhalten" : "Player Behaviour"
    readonly property string grpPlayerBehaviorNote: tr ? "Şarkı değişiminde otomatik genişleme ve mini mod" : es ? "Expansión automática al cambiar de canción y modo mini" : fr ? "Expansion auto au changement de piste et mode mini" : de ? "Auto-Expansion bei Titelfeld und Mini-Modus" : "Auto-expand on track changes and mini player controls"
    readonly property string grpPlayerEffects: tr ? "Görsel Efektler & Animasyon" : es ? "Efectos visuales y animación" : fr ? "Effets visuels et animation" : de ? "Visuelle Effekte & Animation" : "Visual Effects & Motion"
    readonly property string grpPlayerEffectsNote: tr ? "Cava spektrumu dalga stili ve renk parlaması" : es ? "Estilo de onda del espectro cava y brillo de color" : fr ? "Style d'onde du spectre cava et lueur de couleur" : de ? "Cava-Spektrum-Wellenstil und Farbglühen" : "Cava spectrum wave style and color glow"

    // Player settings
    readonly property string setAutoExpandTrack: tr ? "Parça Değişiminde Otomatik Aç" : es ? "Expandir auto al cambiar pista" : fr ? "Étendre auto au changement de piste" : de ? "Bei Titelfeld auto erweitern" : "Auto-expand on Track Change"
    readonly property string setAutoExpandTrackDesc: tr ? "Şarkı değiştiğinde adayı kısa süreliğine genişlet" : es ? "Expandir brevemente la isla al cambiar de canción" : fr ? "Étendre brièvement l'île au changement de piste" : de ? "Insel bei Titelfeld kurz erweitern" : "Briefly expand the island when song changes"
    readonly property string setColorGlow: tr ? "Albüm Rengi Parlaması" : es ? "Brillo de color del álbum" : fr ? "Lueur de la couleur de l'album" : de ? "Albumfarben-Glühen" : "Album Color Glow"
    readonly property string setColorGlowDesc: tr ? "Albüm kapağının tonunda yumuşak arka plan efekti" : es ? "Efecto de fondo suave en el tono de la portada" : fr ? "Effet de fond doux dans la teinte de la pochette" : de ? "Weicher Hintergrund-Effekt in Albumfarbe" : "Soft background glow matching album artwork"
    readonly property string setProgressBar: tr ? "İlerleme Zaman Çubuğu" : es ? "Barra de tiempo de progreso" : fr ? "Barre de temps de progression" : de ? "Fortschritts-Zeitleiste" : "Progress Timeline Bar"
    readonly property string setProgressBarDesc: tr ? "Parçanın geçen ve kalan süresini gösteren hat" : es ? "Línea interactiva mostrando posición y duración" : fr ? "Ligne interactive montrant position et durée" : de ? "Interaktive Linie für Position und Dauer" : "Interactive line showing track position and duration"

    // Group labels
    readonly property string grpTheme: tr ? "Tema" : es ? "Tema" : fr ? "Thème" : de ? "Thema" : "Theme"
    // Split from one "Surfaces" group into two: a border toggle isn't the
    // same kind of decision as picking what the media panel sits on, and
    // stacking both under one vague label — with a description sentence
    // wedged between a row and a picker — was the untidiness in this tab.
    readonly property string grpBorders: tr ? "Kenarlıklar" : es ? "Bordes" : fr ? "Bordures" : de ? "Ränder" : "Borders"
    readonly property string grpBordersNote: tr
        ? "Adayı ve panellerini çevreleyen ince hat"
        : es ? "La línea fina alrededor de la isla y sus paneles"
        : fr ? "Le trait fin autour de l'île et ses panneaux"
        : de ? "Der feine Rand um die Insel und ihre Panels"
        : "The hairline around the island and its panels"
    readonly property string grpMediaSurface: tr ? "Medya Paneli" : es ? "Panel multimedia" : fr ? "Panneau média" : de ? "Medien-Panel" : "Media Panel"
    readonly property string grpMediaSurfaceNote: tr
        ? "Medya paneli temayı izlesin, yoksa her zaman koyu mu kalsın"
        : es ? "Si el panel multimedia sigue el tema o se queda siempre oscuro"
        : fr ? "Si le panneau média suit le thème ou reste toujours sombre"
        : de ? "Ob das Medien-Panel dem Thema folgt oder immer dunkel bleibt"
        : "Whether the media panel follows the theme, or always stays dark"
    readonly property string grpStyle: tr ? "Stil" : es ? "Estilo" : fr ? "Style" : de ? "Stil" : "Style"
    readonly property string grpFormat: tr ? "Biçim" : es ? "Formato" : fr ? "Format" : de ? "Format" : "Format"
    readonly property string grpBehaviour: tr ? "Davranış" : es ? "Comportamiento" : fr ? "Comportement" : de ? "Verhalten" : "Behaviour"
    readonly property string grpTiming: tr ? "Zamanlama" : es ? "Temporización" : fr ? "Temporisation" : de ? "Zeitsteuerung" : "Timing"
    readonly property string grpContent: tr ? "İçerik" : es ? "Contenido" : fr ? "Contenu" : de ? "Inhalt" : "Content"
    readonly property string grpLanguage: tr ? "Dil" : es ? "Idioma" : fr ? "Langue" : de ? "Sprache" : "Language"
    readonly property string grpWindow: tr ? "Pencere" : es ? "Ventana" : fr ? "Fenêtre" : de ? "Fenster" : "Window"

    // Theme names
    readonly property string themeBlack: tr ? "Siyah" : es ? "Negro" : fr ? "Noir" : de ? "Schwarz" : "Black"
    readonly property string themeUmbra: tr ? "Umbra" : es ? "Umbra" : fr ? "Umbra" : de ? "Umbra" : "Umbra"
    readonly property string themeGray: tr ? "Gri" : es ? "Gris" : fr ? "Gris" : de ? "Grau" : "Gray"
    readonly property string themeWhite: tr ? "Beyaz" : es ? "Blanco" : fr ? "Blanc" : de ? "Weiß" : "White"
    // The bundled chimes are listed by number; only the default one has a name
    // worth showing, since "timesup" is a filename rather than a label.
    readonly property string chimeDefault: tr ? "Varsayılan" : es ? "Predeterminado" : fr ? "Défaut" : de ? "Standard" : "Default"
    readonly property string themeGold: tr ? "Altın" : es ? "Oro" : fr ? "Or" : de ? "Gold" : "Gold"
    readonly property string themeAmber: tr ? "Kehribar" : es ? "Ámbar" : fr ? "Ambre" : de ? "Bernstein" : "Amber"
    readonly property string themeRed: tr ? "Kırmızı" : es ? "Rojo" : fr ? "Rouge" : de ? "Rot" : "Red"

    // Appearance
    readonly property string setBorders: tr ? "Kenarlıklar" : es ? "Bordes" : fr ? "Bordures" : de ? "Ränder" : "Borders"
    readonly property string setBordersDesc: tr ? "Kartların çevresindeki ince hat" : es ? "La línea fina alrededor de las tarjetas" : fr ? "Le trait fin autour des cartes" : de ? "Der feine Rand um die Karten" : "The hairline around cards"
    readonly property string grpMountStyle: tr ? "Bağlanma stili" : es ? "Estilo de montaje" : fr ? "Style de fixation" : de ? "Befestigungsstil" : "Mount style"
    readonly property string grpMountStyleNote: tr ? "Adanın ekranın üst kenarıyla nasıl birleştiği" : es ? "Cómo se une la isla al borde superior de la pantalla" : fr ? "Comment l'île rejoint le bord supérieur de l'écran" : de ? "Wie die Insel mit der oberen Bildschirmkante verschmilzt" : "How the island meets the top of the screen"
    readonly property string mountStyleCapsule: tr ? "Kapsül" : es ? "Cápsula" : fr ? "Capsule" : de ? "Kapsel" : "Capsule"
    readonly property string mountStyleSoftFused: tr ? "Yumuşak kaynak" : es ? "Fusión suave" : fr ? "Fusion douce" : de ? "Sanft verschmolzen" : "Soft-fused"
    readonly property string mountStyleNotch: tr ? "Çentik" : es ? "Muesca" : fr ? "Encoche" : de ? "Notch" : "Notch"
    readonly property string setMediaSurfaceDesc: tr ? "Oynatıcı temayı izlesin veya koyu kalsın" : es ? "Seguir el tema o mantener el reproductor oscuro" : fr ? "Suivre le thème ou garder le lecteur sombre" : de ? "Dem Thema folgen oder Player dunkel lassen" : "Follow the theme or keep the player dark"
    readonly property string mediaSurfaceTheme: tr ? "Tema" : es ? "Tema" : fr ? "Thème" : de ? "Thema" : "Theme"
    readonly property string mediaSurfaceDark: tr ? "Koyu" : es ? "Oscuro" : fr ? "Sombre" : de ? "Dunkel" : "Dark"

    // Clock
    readonly property string clockStylePixel: tr ? "Piksel" : es ? "Píxel" : fr ? "Pixel" : de ? "Pixel" : "Pixel"
    readonly property string clockStyleSegment: tr ? "Segment" : es ? "Segmento" : fr ? "Segment" : de ? "Segment" : "Segment"
    readonly property string clockStylePlain: tr ? "Sade" : es ? "Simple" : fr ? "Simple" : de ? "Schlicht" : "Plain"
    readonly property string setClock24h: tr ? "24 saat formatı" : es ? "Formato 24 horas" : fr ? "Format 24 heures" : de ? "24-Stunden-Format" : "24-hour clock"
    readonly property string setClock24hDesc: tr ? "Kapalıyken 12 saat ve ÖÖ/ÖS" : es ? "12 horas con AM/PM al desactivar" : fr ? "12 heures avec AM/PM quand désactivé" : de ? "12 Stunden mit AM/PM wenn aus" : "12-hour with AM/PM when off"
    readonly property string setSeconds: tr ? "Saniye göster" : es ? "Mostrar segundos" : fr ? "Afficher les secondes" : de ? "Sekunden anzeigen" : "Show seconds"
    readonly property string setSecondsDesc: tr ? "Büyük saatin yanındaki küçük hane" : es ? "Los dígitos pequeños junto al reloj grande" : fr ? "Les petits chiffres à côté de l'horloge" : de ? "Die kleinen Ziffern neben der großen Uhr" : "The small digits beside the clock"
    readonly property string setDateLine: tr ? "Tarih satırı" : es ? "Línea de fecha" : fr ? "Ligne de date" : de ? "Datumszeile" : "Date line"
    readonly property string setDateLineDesc: tr ? "Saatin altındaki gün ve ay" : es ? "Día y mes bajo el reloj" : fr ? "Jour et mois sous l'horloge" : de ? "Tag und Monat unter der Uhr" : "Day and month under the clock"
    readonly property string setClockGrid: tr ? "Işıksız ızgara" : es ? "Cuadrícula inactiva" : fr ? "Grille inactive" : de ? "Inaktives Gitter" : "Dormant grid"
    readonly property string setClockGridDesc: tr ? "Yalnızca piksel stilinde görünür" : es ? "Solo visible en estilo píxel" : fr ? "Visible uniquement en style pixel" : de ? "Nur im Pixel-Stil sichtbar" : "Only visible in pixel style"

    // Calls
    readonly property string setCallAutoPopup: tr ? "Arama balonu otomatik açılsın" : es ? "Tarjeta de llamada automática" : fr ? "Carte d'appel automatique" : de ? "Anruferkarte automatisch" : "Auto-open call card"
    readonly property string setCallAutoPopupDesc: tr ? "Kapalıyken yalnız durum çubuğunda ikon çıkar" : es ? "Solo un icono en la barra de estado cuando está desactivado" : fr ? "Une icône dans la barre d'état lorsqu'elle est désactivée" : de ? "Nur ein Symbol in der Statusleiste, wenn aus" : "Only a status-strip icon when off"
    readonly property string setRingTimeout: tr ? "Çalma zaman aşımı" : es ? "Tiempo de llamada" : fr ? "Temps d'appel" : de ? "Anrufzeitraum" : "Ring timeout"
    readonly property string setRingTimeoutDesc: tr ? "Cevaplanmayan arama ne kadar ekranda kalsın" : es ? "¿Cuánto tiempo permanece una llamada sin respuesta en la pantalla?" : fr ? "Combien de temps un appel non répondu reste-t-il à l'écran ?" : de ? "Wie lange bleibt ein unbeantworteter Anruf auf dem Schirm?" : "How long an unanswered call stays up"
    readonly property string setCallPulse: tr ? "Yeşil nabız halkası" : es ? "Anillo de pulso verde" : fr ? "Anneau de pulsation vert" : de ? "Grüner Pulsring" : "Green pulse ring"
    readonly property string setCallPulseDesc: tr ? "Çalarken kapsülün etrafındaki animasyon" : es ? "Animación alrededor de la capsula mientras suena" : fr ? "Animation autour de la capsule pendant l'appel" : de ? "Animation um die Kapsel während des Anrufs" : "The animation around the capsule while ringing"

    // Notifications
    readonly property string setNotifDuration: tr ? "Görünme süresi" : es ? "Duración de la notificación" : fr ? "Durée de la notification" : de ? "Dauer der Benachrichtigung" : "Visible for"
    readonly property string setNotifDurationDesc: tr ? "Kart kendiliğinden kapanana kadar" : es ? "Hasta que la tarjeta se cierre ella misma" : fr ? "Jusqu'à ce que la carte se ferme toute seule" : de ? "Bis die Karte sich selbst schließt" : "Until the card closes itself"
    readonly property string setInlineReply: tr ? "Satır içi yanıt" : es ? "Respuesta inline" : fr ? "Réponse inline" : de ? "Inline-Antwort" : "Inline reply"
    readonly property string setInlineReplyDesc: tr ? "Uygulama destekliyorsa yanıt kutusu" : es ? "Caja de respuesta cuando la app lo permite" : fr ? "Une zone de réponse lorsque l'app le permet" : de ? "Antwortfeld, wenn die App es unterstützt" : "A reply box when the app supports it"
    readonly property string setAppIcon: tr ? "Uygulama simgesi" : es ? "Icono de la aplicación" : fr ? "Icône de l'application" : de ? "App-Symbol" : "App icon"
    readonly property string setAppIconDesc: tr ? "Kapalıyken baş harf rozeti gösterilir" : es ? "Mostrar la inicial de la aplicación cuando está desactivado" : fr ? "Afficher la initiale de l'application lorsqu'elle est désactivée" : de ? "Initialbadge anzeigen, wenn aus" : "An initial badge is shown when off"

    // Media
    readonly property string setLyrics: tr ? "Şarkı sözleri" : es ? "Letra" : fr ? "Paroles" : de ? "Songtext" : "Lyrics"
    readonly property string setLyricsDesc: tr ? "LRCLIB'den eşzamanlı sözler" : es ? "Letra sincronizada de LRCLIB" : fr ? "Paroles synchronisées de LRCLIB" : de ? "Zeitsynchroner Songtext von LRCLIB" : "Time-synced lyrics from LRCLIB"
    readonly property string setSpectrum: tr ? "Spektrum çubukları" : es ? "Barras de espectro" : fr ? "Barres de spectre" : de ? "Spektrum-Balken" : "Spectrum bars"
    readonly property string setSpectrumDesc: tr ? "cava ile canlı frekans grafiği" : es ? "Gráfico de frecuencia en vivo vía cava" : fr ? "Graphique de fréquence en direct via cava" : de ? "Live-Frequenzgraph via cava" : "Live frequency graph via cava"
    readonly property string setAlbumArt: tr ? "Albüm kapağı" : es ? "Portada del álbum" : fr ? "Pochette" : de ? "Albumcover" : "Album art"
    readonly property string setAlbumArtDesc: tr ? "Kapalıyken yerine nota simgesi çıkar" : es ? "Muestra un glifo de nota al desactivar" : fr ? "Un glyphe de note s'affiche quand désactivé" : de ? "Noten-Glyphe wird angezeigt, wenn aus" : "A note glyph replaces it when off"
    readonly property string setCompactControls: tr ? "Mini oynatıcı modu" : es ? "Modo mini reproductor" : fr ? "Mode mini lecteur" : de ? "Mini-Player-Modus" : "Mini player mode"
    readonly property string setCompactControlsDesc: tr
        ? "Hover kapalıyken yalnız kapak, parça adı ve kontroller"
        : es ? "Solo portada, título y controles sin hover"
        : fr ? "Seulement pochette, titre et contrôles sans survol"
        : de ? "Nur Cover, Titel und Steuerung ohne Hover"
        : "Only cover, title and controls when hover is off"
    readonly property string setAppVolume: tr ? "Uygulama sesleri" : es ? "Volumen de apps" : fr ? "Volume des apps" : de ? "App-Lautstärke" : "App volume"
    readonly property string setAppVolumeDesc: tr
        ? "Her uygulamanın sesini panelden ayrı ayrı ayarla"
        : es ? "Ajusta el volumen de cada app desde el panel"
        : fr ? "Règle le volume de chaque app depuis le panneau"
        : de ? "Lautstärke jeder App separat im Panel einstellen"
        : "Set each app's volume separately from the panel"
    // Group headings and their one-line explanations. Each says where on the
    // island the group's settings actually show up, so a setting can be found
    // by remembering what it looked like rather than what it was called.

    readonly property string grpThemeNote: tr
        ? "Ada, ayarlar ve bildirimlerin tamamının renk paleti"
        : es ? "Paleta compartida por la isla, esta ventana y notificaciones"
        : fr ? "Palette partagée par l'île, cette fenêtre et les notifications"
        : de ? "Palette für Insel, dieses Fenster und Benachrichtigungen"
        : "The palette shared by the island, this window and notifications"
    readonly property string grpStyleNote: tr
        ? "Ada boştayken veya saat çipine basıldığında görünen saatin çizimi"
        : es ? "Cómo se dibuja el reloj con la isla inactiva o el chip activo"
        : fr ? "Comment l'horloge est dessinée quand l'île est en veille ou le chip horloge actif"
        : de ? "Wie die Uhr gezeichnet wird, wenn die Insel inaktiv ist oder der Uhr-Chip aktiv ist"
        : "How the clock is drawn when the island is idle or the clock chip is on"
    readonly property string grpFormatNote: tr
        ? "Saatin neyi gösterdiği — 24 saat, saniye, tarih, ızgara"
        : es ? "Qué muestra el reloj — 24 horas, segundos, fecha, cuadrícula"
        : fr ? "Ce que montre l'horloge — 24 heures, secondes, date, grille"
        : de ? "Was die Uhr zeigt — 24 Stunden, Sekunden, Datum, Gitter"
        : "What the clock shows — 24-hour, seconds, date, grid"
    readonly property string grpBehaviourNote: tr
        ? "Gelen arama kartının kendiliğinden açılması ve ne kadar çalacağı"
        : es ? "Si la tarjeta de llamada se abre sola y cuánto suena"
        : fr ? "Si la carte d'appel s'ouvre seule et combien de temps elle sonne"
        : de ? "Ob die Anrufkarte automatisch öffnet und wie lange sie klingelt"
        : "Whether an incoming call opens by itself, and how long it rings"
    readonly property string grpTimingNote: tr
        ? "Bir bildirimin ekranda kalma süresi"
        : es ? "Cuánto permanece una notificación en pantalla"
        : fr ? "Combien de temps une notification reste à l'écran"
        : de ? "Wie lange eine Benachrichtigung angezeigt wird"
        : "How long a notification stays on screen"
    readonly property string grpContentNote: tr
        ? "Bildirim kartında neyin görüneceği"
        : es ? "Qué muestra la tarjeta de notificación"
        : fr ? "Ce que porte la carte de notification"
        : de ? "Was die Benachrichtigungskarte enthält"
        : "What a notification card carries"
    readonly property string grpLanguageNote: tr
        ? "Ada ve bu pencerenin dili"
        : es ? "Idioma de la isla y esta ventana"
        : fr ? "Langue de l'île et de cette fenêtre"
        : de ? "Sprache der Insel und dieses Fensters"
        : "The language of the island and this window"
    readonly property string grpWindowNote: tr
        ? "Adanın fareyle mi yoksa yalnızca tıklamayla mı açılacağı"
        : es ? "Si la isla se abre al pasar el cursor o solo al clic"
        : fr ? "Si l'île s'ouvre au survol ou seulement au clic"
        : de ? "Ob die Insel beim Hover oder nur per Klick öffnet"
        : "Whether the island opens on hover or only on click"

    readonly property string grpAppVolume: tr ? "Uygulama sesleri" : es ? "Volumen de apps" : fr ? "Volume des apps" : de ? "App-Lautstärke" : "App volume"
    readonly property string grpAppVolumeNote: tr
        ? "Şeritteki 󰕾 çipi, her uygulamanın sesini ayrı ayrı ayarlayan paneli açar"
        : es ? "El chip 󰕾 en la tira abre un panel con un nivel por app"
        : fr ? "La puce 󰕾 dans la barre ouvre un panneau avec un niveau par app"
        : de ? "Der 󰕾-Chip in der Leiste öffnet ein Panel mit Pegel pro App"
        : "The 󰕾 chip in the strip opens a panel with one level per application"
    readonly property string grpPlayerSwitcher: tr ? "Oynatıcı seçici" : es ? "Selector de reproductor" : fr ? "Sélecteur de lecteur" : de ? "Player-Wechsler" : "Player switcher"
    readonly property string grpPlayerSwitcherNote: tr
        ? "Yalnızca iki veya daha fazla oynatıcı açıkken görünür, kapağın alt köşesinde"
        : es ? "Solo con dos o más reproductores abiertos, en la esquina inferior de la portada"
        : fr ? "Seulement avec deux lecteurs ou plus, en bas de la pochette"
        : de ? "Nur bei zwei oder mehr offenen Playern, unten am Cover"
        : "Only appears with two or more players open, in the cover's bottom corner"
    readonly property string grpQueue: tr ? "Sırada" : es ? "A continuación" : fr ? "Suivant" : de ? "Als Nächstes" : "Up next"
    readonly property string grpQueueNote: tr
        ? "Şeritteki 󰐑 çipi sıradaki parçaları gösterir — çoğu oynatıcı bu bilgiyi vermez"
        : es ? "El chip 󰐑 muestra próximas pistas — la mayoría no informa"
        : fr ? "La puce 󰐑 montre les pistes à venir — la plupart ne les informe pas"
        : de ? "Der 󰐑-Chip zeigt kommende Titel — die meisten melden sie nicht"
        : "The 󰐑 chip shows upcoming tracks — most players don't report them"

    readonly property string switcherChips: tr ? "İsimler" : es ? "Nombres" : fr ? "Noms" : de ? "Namen" : "Names"
    readonly property string switcherLogos: tr ? "Logolar" : es ? "Logos" : fr ? "Logos" : de ? "Logos" : "Logos"
    readonly property string switcherSegment: tr ? "Şeritte" : es ? "En tira" : fr ? "Dans la barre" : de ? "In Leiste" : "In strip"

    readonly property string queueStyleList: tr ? "Liste" : es ? "Lista" : fr ? "Liste" : de ? "Liste" : "List"
    readonly property string queueStyleCovers: tr ? "Kapaklar" : es ? "Portadas" : fr ? "Pochettes" : de ? "Cover" : "Covers"
    readonly property string queueStyleTimeline: tr ? "Zaman" : es ? "Línea" : fr ? "Frise" : de ? "Zeitleiste" : "Timeline"

    readonly property string setQueue: tr ? "Sırada (deneysel)" : es ? "A continuación (experimental)" : fr ? "Suivant (expérimental)" : de ? "Als Nächstes (experimentell)" : "Up next (experimental)"
    readonly property string setQueueDesc: tr
        ? "Yalnızca kuyruk bilgisi veren oynatıcılarda çalışır; tarayıcı sekmelerinde çalışmaz"
        : es ? "Solo en reproductores que informan cola; pestañas de navegador no"
        : fr ? "Seulement sur lecteurs avec file; pas les onglets navigateur"
        : de ? "Nur bei Playern mit Warteschlange; Browser-Tabs nicht"
        : "Only works on players that report a queue; browser tabs don't"
    readonly property string animWave: tr ? "Dalga" : es ? "Onda" : fr ? "Onde" : de ? "Welle" : "Wave"
    readonly property string animLive: tr ? "Canlı" : es ? "En vivo" : fr ? "En direct" : de ? "Live" : "Live"
    readonly property string animCalm: tr ? "Sakin" : es ? "Calmo" : fr ? "Calme" : de ? "Ruhig" : "Calm"
    readonly property string setAnimationIntensityDesc: tr ? "Çubukların arka plandaki kontrastı" : es ? "Contraste de barras tras el contenido" : fr ? "Contraste des barres derrière le contenu" : de ? "Balkenkontrast hinter dem Inhalt" : "Bar contrast behind the content"
    readonly property string intensitySoft: tr ? "Hafif" : es ? "Suave" : fr ? "Doux" : de ? "Leise" : "Soft"
    readonly property string intensityBalanced: tr ? "Dengeli" : es ? "Equilibrado" : fr ? "Équilibré" : de ? "Ausgeglichen" : "Balanced"
    readonly property string intensityBold: tr ? "Belirgin" : es ? "Intenso" : fr ? "Marqué" : de ? "Kräftig" : "Bold"

    // General
    readonly property string setLanguage: tr ? "Arayüz dili" : es ? "Idioma de interfaz" : fr ? "Langue de l'interface" : de ? "Oberflächensprache" : "Interface language"
    readonly property string setLanguageDesc: tr ? "Saatin gün ve ay adlarını da değiştirir" : es ? "También cambia nombres de día y mes del reloj" : fr ? "Change aussi les noms de jour et mois de l'horloge" : de ? "Ändert auch Tages- und Monatsnamen der Uhr" : "Also changes the clock's day and month names"
    readonly property string setPinned: tr ? "Panel sabit kalsın" : es ? "Mantener panel anclado" : fr ? "Garder le panneau épinglé" : de ? "Panel angeheftet lassen" : "Keep panel pinned"
    readonly property string setPinnedDesc: tr ? "Fare ayrılınca kapanmaz" : es ? "Permanece abierto al salir el puntero" : fr ? "Reste ouvert quand le pointeur sort" : de ? "Bleibt offen, wenn der Zeiger weggeht" : "Stays open when the pointer leaves"
    readonly property string setHoverOpen: tr ? "Üzerine gelince aç" : es ? "Abrir al pasar cursor" : fr ? "Ouvrir au survol" : de ? "Beim Hover öffnen" : "Open on hover"
    readonly property string setHoverOpenDesc: tr
        ? "Kapalıyken mini kontroller ve tıklayarak açma kullanılır"
        : es ? "Sin hover, usa controles compactos y clic para abrir"
        : fr ? "Sans survol, contrôles compacts et clic pour ouvrir"
        : de ? "Ohne Hover kompakte Steuerung und Klick zum Öffnen"
        : "When off, use compact controls and click to open"
    readonly property string setChime: tr ? "Bitiş sesi çal" : es ? "Reproducir sonido al terminar" : fr ? "Jouer un son à la fin" : de ? "Endton abspielen" : "Play finish sound"
    readonly property string setChimeDesc: tr ? "Zamanlayıcı, alarm veya odak bittiğinde ses çal" : es ? "Reproducir sonido al terminar temporizador, alarma o foco" : fr ? "Jouer un son à la fin de la minuterie, de l'alarme ou du focus" : de ? "Ton abspielen, wenn Timer, Alarm oder Fokus endet" : "Play a sound when timer, alarm or focus ends"
    readonly property string setChimeSound: tr ? "Bitiş sesi" : es ? "Sonido final" : fr ? "Son de fin" : de ? "Endton" : "Finish sound"
    readonly property string setChimeSoundDesc: tr ? "Zamanlayıcı/alarm bittiğinde çalacak ses dosyası" : es ? "Archivo de sonido para fin de temporizador/alarma" : fr ? "Fichier son pour fin de minuterie/alarme" : de ? "Sounddatei für Timer-/Alarm-Ende" : "Sound file to play when timer/alarm finishes"

    // Durations, written out rather than templated so a language that puts the
    // unit first (or drops the space) isn't forced into the Turkish shape.
    function seconds(value) { return tr ? value + " sn" : es ? value + " s" : fr ? value + " s" : de ? value + " s" : value + " s" }
}
