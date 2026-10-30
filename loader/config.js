// Glass Arc loader (the first line of this file is skipped by Firefox).
// Runs the profile's chrome/JS/*.uc.js scripts in every browser window.
// Firefox reads this file because of defaults/pref/config-prefs.js.
try {
  const obs = Cc["@mozilla.org/observer-service;1"].getService(Ci.nsIObserverService);
  const loader = Cc["@mozilla.org/moz/jssubscript-loader;1"].getService(Ci.mozIJSSubScriptLoader);
  const dirs = Cc["@mozilla.org/file/directory_service;1"].getService(Ci.nsIProperties);
  const io = Cc["@mozilla.org/network/io-service;1"].getService(Ci.nsIIOService);
  // file: URLs are refused for chrome scripts, so the folder is mapped to
  // resource://glassarc-js/
  const res = io.getProtocolHandler("resource").QueryInterface(Ci.nsIResProtocolHandler);

  obs.addObserver(win => {
    win.addEventListener("DOMContentLoaded", () => {
      if (win.location.href !== "chrome://browser/content/browser.xhtml") {
        return;
      }
      const dir = dirs.get("UChrm", Ci.nsIFile);
      dir.append("JS");
      if (!dir.exists()) {
        return;
      }
      res.setSubstitution("glassarc-js", io.newFileURI(dir));
      for (const file of dir.directoryEntries) {
        if (file.leafName.endsWith(".uc.js")) {
          try {
            loader.loadSubScript(`resource://glassarc-js/${file.leafName}?${file.lastModifiedTime}`, win);
          } catch (e) {
            Cu.reportError(e);
          }
        }
      }
    }, { once: true });
  }, "chrome-document-global-created");
} catch (e) {
  Cu.reportError(e);
}
