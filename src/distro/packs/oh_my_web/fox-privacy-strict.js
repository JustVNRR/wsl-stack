// The oh_my_web pack's STRICT privacy profile - what `pfox` (and gmake
// fox_tweak_on) puts in place: the light profile, plus anti-fingerprinting
// (English pages, UTC hours, letterboxing) and WebRTC off. `fox` puts the
// light one back. Defaults: about:config wins. What each line does:
// docs/fox.md.

// --- Tracking protection: the Strict preset, named pref by pref ---
// (the category line is what the Settings page shows; the engines read the
// prefs, so both are set)
pref("browser.contentblocking.category", "strict");
pref("privacy.trackingprotection.enabled", true);
pref("privacy.trackingprotection.fingerprinting.enabled", true);
pref("privacy.trackingprotection.cryptomining.enabled", true);
pref("privacy.trackingprotection.socialtracking.enabled", true);
pref("privacy.trackingprotection.emailtracking.enabled", true);

// --- Tracking parameters stripped from URLs, in every window ---
pref("privacy.query_stripping.enabled", true);
pref("privacy.query_stripping.enabled.pbmode", true);

// --- Clicks and pages that would phone home ---
pref("browser.send_pings", false);
pref("beacon.enabled", false);

// --- Connections a page did not ask for ---
pref("network.prefetch-next", false);
pref("network.dns.disablePrefetch", true);

// --- TLS and DNS ---
// HTTPS-only in every window: a site served over plain http gets a warning
// page with a way through. DoH is off on purpose - the DNS of this instance is
// the tunnel's business (docs/vpn.md), and Firefox answering it itself would
// step around the tunnel.
pref("dom.security.https_only_mode", true);
pref("network.trr.mode", 5);

// --- What a page may read of the machine ---
// No camera/microphone enumeration (WSLg serves neither), and geolocation
// denied by default - one site can still be allowed through the padlock.
pref("media.navigator.enabled", false);
pref("permissions.default.geo", 2);

// --- Telemetry, studies, and the do-not-sell signal ---
pref("datareporting.healthreport.uploadEnabled", false);
pref("app.shield.optoutstudies.enabled", false);
pref("privacy.globalprivacycontrol.enabled", true);

// --- Anti-fingerprinting (the big switch: it changes what sites see) ---
// Time zone UTC, language en-US, a generic user-agent, canvas noise - and the
// letterboxing, which standardizes the window's size (grey margins around
// pages until the window matches a standard shape).
pref("privacy.resistFingerprinting", true);
pref("privacy.resistFingerprinting.letterboxing", true);

// --- WebRTC off ---
// No real-time connections from a page: this instance has no camera, and an
// in-browser call is a leak this browser does not need.
pref("media.peerconnection.enabled", false);

// --- A dark interface, whatever the system prefers ---
// The browser's own chrome and the colour scheme announced to sites, both
// dark, whichever theme the machine has.
pref("ui.systemUsesDarkTheme", 1);
pref("layout.css.prefers-color-scheme.content-override", 0);
