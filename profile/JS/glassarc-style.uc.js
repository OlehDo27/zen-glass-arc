// Glass Arc: a surface style switch in the Edit Theme panel
// (right click on the sidebar -> Edit Theme). Same setting as the
// "Стиль поверхности" dropdown in Settings -> Zen Mods -> Glass Arc.
(() => {
  const PREF = "mod.glassarc.style";
  const STYLES = [
    ["glass", "Матовое"],
    ["smoked", "Тёмное"],
    ["solid", "Сплошное"],
    ["zen", "Zen"],
  ];

  const current = () => Services.prefs.getStringPref(PREF, "glass");

  // Zen Mods copies dropdown values onto #theme-Glass-Arc only when it
  // rebuilds the mods, so the attribute is kept in sync here.
  function apply() {
    const style = current();
    document.getElementById("theme-Glass-Arc")?.setAttribute("mod-glassarc-style", style);
    for (const button of document.querySelectorAll("#glassarc-style-picker > button")) {
      button.setAttribute("aria-pressed", button.value === style);
    }
  }

  function addPicker(view) {
    if (view.querySelector("#glassarc-style-picker")) {
      return;
    }
    const picker = document.createElement("div");
    picker.id = "glassarc-style-picker";
    for (const [value, label] of STYLES) {
      const button = document.createElement("button");
      button.value = value;
      button.title = label;
      const swatch = document.createElement("span");
      swatch.className = "glassarc-swatch";
      button.append(swatch, label);
      button.addEventListener("click", () => Services.prefs.setStringPref(PREF, value));
      picker.append(button);
    }
    const controls = view.querySelector("#PanelUI-zen-gradient-generator-controls");
    if (controls) {
      controls.after(picker);
    } else {
      view.append(picker);
    }
    apply();
  }

  document.addEventListener("popupshowing", event => {
    if (event.target.id === "PanelUI-zen-gradient-generator") {
      const view = document.getElementById("PanelUI-zen-gradient-generator-view");
      if (view) {
        addPicker(view);
      }
    }
  }, true);

  // Downloads takes Library's place at the bottom of the sidebar, once per
  // profile (the installer already did it if Zen had been started before).
  const MOVED = "mod.glassarc.downloads-moved";
  if (!Services.prefs.getBoolPref(MOVED, false)) {
    window.addEventListener("load", () => setTimeout(() => {
      if (Services.prefs.getBoolPref(MOVED, false)) {
        return;
      }
      try {
        CustomizableUI.addWidgetToArea("downloads-button", "zen-sidebar-foot-buttons");
        CustomizableUI.addWidgetToArea("zen-library-button", CustomizableUI.AREA_FIXED_OVERFLOW_PANEL);
        Services.prefs.setBoolPref(MOVED, true);
      } catch (e) {
        console.error("[Glass Arc]", e);
      }
    }, 1500), { once: true });
  }

  Services.prefs.addObserver(PREF, apply);
  window.addEventListener("unload", () => Services.prefs.removeObserver(PREF, apply), { once: true });
  window.addEventListener("load", apply, { once: true });
})();
