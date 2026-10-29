// Widget Studio — make your own desktop widgets: a mini media player, a clock, a launcher bar…
//
//   qs -c MacShell ipc call widgetstudio open | close | toggle
//
// Build a widget from blocks (text with live {tokens}, buttons with premade actions, album art,
// progress bars, images, shapes), then "Show on Desktop": it sits on the desktop below your
// windows and can be dragged there. Everything is saved to ~/.config/macshell/custom-widgets.json.
// Rendering: WidgetView.qml, live data + actions: WidgetContext.qml.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "I18n.js" as I18n

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string home: Quickshell.env("HOME") || Quickshell.env("USERPROFILE")

    property var widgets: []          // saved widgets
    property int current: -1          // the one being edited
    property int sel: -1              // its selected item
    property bool loaded: false
    readonly property var cw: current >= 0 && current < widgets.length ? widgets[current] : null
    readonly property var ci: cw && sel >= 0 && sel < cw.items.length ? cw.items[sel] : null

    WidgetContext { id: wctx; hub: root.hub }

    function open() { if (!win.visible) placeWindow(); if (win.visibility === Window.Minimized) win.showNormal(); win.visible = true; win.raise(); win.requestActivate(); if (widgets.length === 0) addFromTemplate(0); else if (current < 0) current = 0; listShared(); }
    // open fully on screen, below the menu bar and above the Dock (smaller screens get a smaller window)
    function placeWindow() {
        var s = Quickshell.screens.length ? Quickshell.screens[0] : null; if (!s) return;
        var top = 34, bottom = 90;
        win.width = Math.min(win.width, s.width - 40);
        win.height = Math.min(win.height, s.height - top - bottom);
        win.x = Math.round((s.width - win.width) / 2);
        win.y = Math.round(top + (s.height - top - bottom - win.height) / 2);
    }
    function close() { win.visible = false; }
    function toggle() { if (win.visible) close(); else open(); }

    // ── templates ──
    readonly property var templates: [
        { name: "Mini Player", w: 344, h: 164, bg: { color: "#1C1C1E", opacity: 0.86, radius: 26, border: true }, items: [
            { type: "art", x: 18, y: 18, w: 128, h: 128, radius: 16 },
            { type: "text", x: 162, y: 22, w: 166, h: 22, text: "{title}", size: 16, bold: true, color: "#FFFFFF" },
            { type: "text", x: 162, y: 46, w: 166, h: 18, text: "{artist}", size: 13, color: "#B0B0B5" },
            { type: "progress", x: 172, y: 82, w: 152, h: 6, source: "media", color: "#FFFFFF", seek: true },
            { type: "button", x: 172, y: 104, w: 36, h: 36, action: "media.previous", icon: "auto", color: "#FFFFFF" },
            { type: "button", x: 228, y: 102, w: 40, h: 40, action: "media.toggle", icon: "auto", color: "#FFFFFF" },
            { type: "button", x: 288, y: 104, w: 36, h: 36, action: "media.next", icon: "auto", color: "#FFFFFF" } ] },
        { name: "Clock", w: 344, h: 164, bg: { color: "#1C1C1E", opacity: 0.8, radius: 26, border: true }, items: [
            { type: "text", x: 22, y: 18, w: 300, h: 24, text: "{day}", size: 18, bold: true, color: "#FF453A" },
            { type: "text", x: 22, y: 44, w: 300, h: 66, text: "{time}", size: 56, bold: true, color: "#FFFFFF" },
            { type: "text", x: 22, y: 118, w: 300, h: 24, text: "{date}", size: 16, color: "#B0B0B5" } ] },
        { name: "Battery & Volume", w: 260, h: 100, bg: { color: "#1C1C1E", opacity: 0.8, radius: 22, border: true }, items: [
            { type: "text", x: 18, y: 12, w: 140, h: 20, text: "Battery {battery}", size: 13, bold: true, color: "#FFFFFF" },
            { type: "progress", x: 18, y: 34, w: 224, h: 8, source: "battery", color: "#30D158" },
            { type: "text", x: 18, y: 52, w: 140, h: 20, text: "Volume {volume}", size: 13, bold: true, color: "#FFFFFF" },
            { type: "progress", x: 18, y: 74, w: 160, h: 8, source: "volume", color: "#0A84FF" },
            { type: "button", x: 190, y: 62, w: 28, h: 28, action: "volume.down", icon: "auto", color: "#FFFFFF" },
            { type: "button", x: 218, y: 62, w: 28, h: 28, action: "volume.up", icon: "auto", color: "#FFFFFF" } ] },
        { name: "Now Playing (large)", w: 360, h: 150, bg: { color: "#1C1C1E", opacity: 0.86, radius: 26, border: true }, items: [
            { type: "art", x: 16, y: 16, w: 118, h: 118, radius: 16 },
            { type: "text", x: 148, y: 18, w: 198, h: 22, text: "{title}", size: 16, bold: true, color: "#FFFFFF" },
            { type: "text", x: 148, y: 40, w: 198, h: 18, text: "{artist}", size: 13, color: "#B0B0B5" },
            { type: "progress", x: 148, y: 72, w: 196, h: 6, source: "media", color: "#FFFFFF", seek: true },
            { type: "text", x: 148, y: 80, w: 80, h: 16, text: "{elapsed}", size: 11, color: "#B0B0B5" },
            { type: "text", x: 264, y: 80, w: 80, h: 16, text: "{remaining}", size: 11, color: "#B0B0B5", align: "right" },
            { type: "button", x: 164, y: 102, w: 34, h: 34, action: "media.previous", icon: "auto", color: "#FFFFFF" },
            { type: "button", x: 226, y: 100, w: 38, h: 38, action: "media.toggle", icon: "auto", color: "#FFFFFF" },
            { type: "button", x: 292, y: 102, w: 34, h: 34, action: "media.next", icon: "auto", color: "#FFFFFF" } ] },
        { name: "Analog Clock", w: 150, h: 150, bg: { color: "#1C1C1E", opacity: 0.85, radius: 34, border: true }, items: [
            { type: "clock", x: 12, y: 12, w: 126, h: 126, color: "#1C1C1E", hand: "#FF9F0A", face: "#FFFFFF" } ] },
        { name: "App Shortcuts", w: 300, h: 110, bg: { color: "#1C1C1E", opacity: 0.6, radius: 24, border: true }, items: [
            { type: "app", x: 14, y: 12, w: 64, h: 86, name: "Firefox", command: "firefox", icon: "firefox", color: "#FFFFFF" },
            { type: "app", x: 84, y: 12, w: 64, h: 86, name: "Spotify", command: "spotify", icon: "spotify", color: "#FFFFFF" },
            { type: "app", x: 154, y: 12, w: 64, h: 86, name: "Discord", command: "discord", icon: "discord", color: "#FFFFFF" },
            { type: "app", x: 224, y: 12, w: 64, h: 86, name: "Steam", command: "steam", icon: "steam", color: "#FFFFFF" } ] },
        { name: "Weather", w: 170, h: 170, bg: { color: "#2D6CDF", opacity: 0.92, radius: 30, border: true }, items: [
            { type: "weather", x: 16, y: 14, w: 140, h: 142, city: "London", unit: "C", color: "#FFFFFF" } ] },
        { name: "Calendar", w: 344, h: 344, bg: { color: "#1C1C1E", opacity: 0.85, radius: 30, border: true }, items: [
            { type: "calendar", x: 20, y: 20, w: 304, h: 304, color: "#FFFFFF", accent: "#FF453A" } ] },
        { name: "System Monitor", w: 260, h: 150, bg: { color: "#1C1C1E", opacity: 0.85, radius: 24, border: true }, items: [
            { type: "text", x: 18, y: 12, w: 224, h: 18, text: "CPU {cpu}", size: 13, bold: true, color: "#FFFFFF" },
            { type: "progress", x: 18, y: 32, w: 224, h: 8, source: "cpu", color: "#0A84FF" },
            { type: "text", x: 18, y: 52, w: 224, h: 18, text: "Memory {ramused}", size: 13, bold: true, color: "#FFFFFF" },
            { type: "progress", x: 18, y: 72, w: 224, h: 8, source: "ram", color: "#30D158" },
            { type: "text", x: 18, y: 92, w: 224, h: 18, text: "GPU {gpu}", size: 13, bold: true, color: "#FFFFFF" },
            { type: "progress", x: 18, y: 112, w: 224, h: 8, source: "gpu", color: "#FF9F0A" } ] },
        { name: "Sticky Note", w: 220, h: 200, bg: { color: "#FFD60A", opacity: 0.95, radius: 18, border: false }, items: [
            { type: "note", x: 16, y: 14, w: 188, h: 172, text: "", size: 15, color: "#1C1C1E" } ] },
        { name: "Blank", w: 260, h: 140, bg: { color: "#1C1C1E", opacity: 0.85, radius: 22, border: true }, items: [] }
    ]

    function clone(o) { return JSON.parse(JSON.stringify(o)); }
    // every change goes through commit(): it is saved, and can be undone / redone
    property var undoStack: []
    property var redoStack: []
    function commit(list) {
        undoStack = undoStack.concat([JSON.stringify(widgets)]).slice(-100);
        redoStack = [];
        widgets = list; saveTimer.restart();
    }
    function undo() {
        if (!undoStack.length) return;
        redoStack = redoStack.concat([JSON.stringify(widgets)]);
        widgets = JSON.parse(undoStack[undoStack.length - 1]); undoStack = undoStack.slice(0, -1);
        sel = -1; current = Math.min(current, widgets.length - 1); saveTimer.restart();
    }
    function redo() {
        if (!redoStack.length) return;
        undoStack = undoStack.concat([JSON.stringify(widgets)]);
        widgets = JSON.parse(redoStack[redoStack.length - 1]); redoStack = redoStack.slice(0, -1);
        sel = -1; current = Math.min(current, widgets.length - 1); saveTimer.restart();
    }

    // ── the desktop grid: squares of about 112 px, 12 px apart, filling the screen edge to edge (5 px from each
    // side), between the menu bar and the Dock; the square size is stretched a little so the columns fit exactly.
    // A widget is 1x1, 2x1, 2x2 or 4x2 squares.
    readonly property int gridGap: 12
    readonly property int gridEdge: 5
    readonly property real scrW: Quickshell.screens.length ? Quickshell.screens[0].width : 1920
    readonly property real scrH: Quickshell.screens.length ? Quickshell.screens[0].height : 1080
    readonly property int barH: root.hub && root.hub.bar ? root.hub.bar.barHeight : 28
    readonly property int dockRoom: 78                                   // the Dock's height plus its margin
    readonly property int gridCols: Math.max(4, Math.round((scrW - 2 * gridEdge + gridGap) / (112 + gridGap)))
    readonly property int gridUnit: Math.floor((scrW - 2 * gridEdge - (gridCols - 1) * gridGap) / gridCols)
    readonly property int gridLeft: gridEdge + Math.floor((scrW - 2 * gridEdge - (gridCols * gridUnit + (gridCols - 1) * gridGap)) / 2)
    readonly property int gridTop: barH + gridEdge
    readonly property int gridRows: Math.max(2, Math.floor((scrH - gridTop - dockRoom - gridEdge + gridGap) / (gridUnit + gridGap)))
    function gridX(col) { return gridLeft + col * (gridUnit + gridGap); }
    function gridY(row) { return gridTop + row * (gridUnit + gridGap); }
    function gridSpan(n) { return n * gridUnit + (n - 1) * gridGap; }
    function snapX(x) { return gridX(Math.max(0, Math.min(gridCols - 1, Math.round((x - gridLeft) / (gridUnit + gridGap))))); }
    function snapY(y) { return gridY(Math.max(0, Math.min(gridRows - 1, Math.round((y - gridTop) / (gridUnit + gridGap))))); }
    // how many squares a widget of this many pixels covers on the current grid
    function cellsOf(px) { return Math.max(1, Math.round((px + gridGap) / (gridUnit + gridGap))); }
    // a widget object resized to cols x rows squares, what's inside scaled with it (templates are drawn at 164 px squares)
    function scaledTo(w0, cols, rows) {
        var w = clone(w0), nw = gridSpan(cols), nh = gridSpan(rows), fx = nw / (w.w || nw), fy = nh / (w.h || nh), f = Math.min(fx, fy);
        for (var i = 0; i < (w.items || []).length; i++) {
            var it = w.items[i];
            it.x = Math.round((it.x || 0) * fx); it.y = Math.round((it.y || 0) * fy);
            it.w = Math.round((it.w || 40) * fx); it.h = Math.round((it.h || 20) * fy);
            if (it.size) it.size = Math.max(6, Math.round(it.size * f));
        }
        if (w.bg && w.bg.radius) w.bg.radius = Math.max(8, Math.round(w.bg.radius * f));
        w.w = nw; w.h = nh;
        return w;
    }
    // how many squares a widget drawn for the old 164 px grid covers
    function oldCells(px) { return Math.max(1, Math.round((px + 16) / 180)); }
    // resize the current widget to cols x rows squares, scaling what's inside with it
    function setGridSize(cols, rows) {
        if (!cw) return;
        var w = clone(cw), nw = gridSpan(cols), nh = gridSpan(rows), fx = nw / (w.w || nw), fy = nh / (w.h || nh), f = Math.min(fx, fy);
        for (var i = 0; i < w.items.length; i++) {
            var it = w.items[i];
            it.x = Math.round((it.x || 0) * fx); it.y = Math.round((it.y || 0) * fy);
            it.w = Math.round((it.w || 40) * fx); it.h = Math.round((it.h || 20) * fy);
            if (it.size) it.size = Math.max(6, Math.round(it.size * f));
        }
        w.w = nw; w.h = nh;
        var l = widgets.slice(); l[current] = w; commit(l);
    }
    // styling single words ("w") or letters ("c") of a text block
    property string spanMode: "w"
    property int spanPick: -1
    onSelChanged: spanPick = -1
    function setSpan(style) {
        if (!ci || spanPick < 0) return;
        var sp = clone(ci.spans || {}), key = spanMode + spanPick;
        // one kind at a time: styling letters clears word styles and the other way round
        for (var k in sp) if (k.charAt(0) !== spanMode) delete sp[k];
        if (style === null) delete sp[key];
        else { var cur = sp[key] || {}; for (var f in style) cur[f] = f === "color" ? style[f] : !cur[f]; sp[key] = cur; }
        updateItem({ spans: sp });
    }
    property int movingIndex: -1            // the desktop widget in Move mode (snaps to the grid)

    // ── Match the desktop theme: every widget is drawn in the current theme's colours (its own colours are kept
    // and come back when this is off). Background = the theme's card colour, text = its text colour,
    // progress bars / today on the calendar = its accent. Saved with the widgets.
    property bool matchTheme: false
    readonly property var theme: {
        var d = root.dock;
        if (!d) return { card: "#2A2A2C", fg: "#F5F5F7", accent: "#0A84FF" };
        var t = null, l = d.themePresets || [];
        for (var i = 0; i < l.length; i++) if (l[i].id === d.themePreset) t = l[i];
        if (!t || t.id === "default") return d.darkMode ? { card: "#2A2A2C", fg: "#F5F5F7", accent: d.accent || "#0A84FF" }
                                                        : { card: "#F2F2F7", fg: "#1D1D1F", accent: d.accent || "#0A84FF" };
        return { card: t.card || "#2A2A2C", fg: t.fg || "#FFFFFF", accent: t.accent || "#0A84FF" };
    }
    function themed(w) {
        if (!matchTheme || !w) return w;
        var o = clone(w), th = theme;
        o.bg = o.bg || {}; o.bg.color = th.card;
        for (var i = 0; i < (o.items || []).length; i++) {
            var it = o.items[i];
            if (it.type === "progress") it.color = th.accent;
            else if (it.type === "calendar") { it.color = th.fg; it.accent = th.accent; }
            else if (it.type === "shape" || it.type === "image" || it.type === "art") continue;      // pictures and shapes keep their look
            else if (it.type === "clock") { it.color = th.card; it.face = th.fg; it.hand = th.accent; }
            else it.color = th.fg;
            if (it.spans) delete it.spans;                                                              // one theme colour for the whole text
        }
        return o;
    }
    // first start (no saved widgets yet): a clock, a calendar and a music player on the desktop
    function addDefaults() {
        var pick = function (name) { for (var i = 0; i < templates.length; i++) if (templates[i].name === name) return clone(templates[i]); return null; };
        var spots = [["Clock", gridX(0), gridY(0)], ["Mini Player", gridX(0), gridY(1)], ["Calendar", gridX(2), gridY(0)]], l = [];
        for (var k = 0; k < spots.length; k++) {
            var w = pick(spots[k][0]);
            if (!w) continue;
            w = scaledTo(w, oldCells(w.w), oldCells(w.h));
            w.id = "default-" + k; w.onDesktop = true; w.x = spots[k][1]; w.y = spots[k][2];
            l.push(w);
        }
        commit(l);
        current = 0;
    }
    function removeFromDesktop(index) { var l = widgets.slice(), w = clone(l[index]); w.onDesktop = false; l[index] = w; commit(l); }
    function deleteAt(index) { var l = widgets.slice(); l.splice(index, 1); commit(l); current = Math.min(current, l.length - 1); sel = -1; }

    // once: widgets made for the old, bigger grid shrink to the new one; an empty desktop gets the clock,
    // calendar and music player
    FileView { id: gridV2; path: root.home + "/.config/macshell/ff-widgets-grid-v2"; printErrors: false; blockLoading: true }
    FileView { id: gridV3; path: root.home + "/.config/macshell/ff-widgets-grid-v3"; printErrors: false; blockLoading: true }
    function migrateGrid() {
        if (gridV2.text() !== "") { snapAllToGrid(); return; }
        var l = [];
        for (var i = 0; i < widgets.length; i++) {
            var w = widgets[i];
            if (w.w >= 160) { w = scaledTo(w, oldCells(w.w), oldCells(w.h)); w.x = snapX(w.x || 0); w.y = snapY(w.y || 0); }
            l.push(w);
        }
        gridV2.setText("1"); gridV3.setText("1");
        if (!l.some(function (w) { return w.onDesktop; })) { widgets = l; addDefaultsKeeping(l); }
        else commit(l);
    }
    function snapAllToGrid() {
        if (gridV3.text() !== "") return;
        var l = [];
        for (var i = 0; i < widgets.length; i++) {
            var w = widgets[i];
            w = scaledTo(w, cellsOf(w.w), cellsOf(w.h));
            w.x = snapX(w.x || 0); w.y = snapY(w.y || 0);
            l.push(w);
        }
        gridV3.setText("1");
        commit(l);
    }
    function addDefaultsKeeping(existing) {
        var keep = existing.slice();
        addDefaults();
        var l = widgets.concat(keep.filter(function (w) { return String(w.id).indexOf("default-") !== 0; }));
        commit(l);
    }
    function addFromTemplate(i) {
        var w = scaledTo(templates[i], oldCells(templates[i].w), oldCells(templates[i].h));
        w.id = Date.now().toString(36); w.onDesktop = false; w.x = 80 + widgets.length * 30; w.y = 120 + widgets.length * 30;
        var l = widgets.slice(); l.push(w); commit(l); current = l.length - 1; sel = -1;
    }
    function updateWidget(fields) {
        if (!cw) return;
        var l = widgets.slice(), w = clone(cw);
        for (var k in fields) w[k] = fields[k];
        l[current] = w; commit(l);
    }
    function updateItem(fields) {
        if (!ci) return;
        var w = clone(cw);
        for (var k in fields) w.items[sel][k] = fields[k];
        var l = widgets.slice(); l[current] = w; commit(l);
    }
    function addItem(type) {
        if (!cw) return;
        var base = { text: { type: "text", w: 160, h: 24, text: "{title}", size: 15, color: "#FFFFFF" },
                     button: { type: "button", w: 36, h: 36, action: "media.toggle", icon: "auto", color: "#FFFFFF" },
                     art: { type: "art", w: 72, h: 72, radius: 12 },
                     progress: { type: "progress", w: 160, h: 8, source: "media", color: "#FFFFFF" },
                     image: { type: "image", w: 80, h: 80, src: "", radius: 12 },
                     shape: { type: "shape", w: 80, h: 40, color: "#0A84FF", radius: 10, opacity: 1 },
                     clock: { type: "clock", w: 100, h: 100, color: "#1C1C1E", hand: "#FF9F0A", face: "#FFFFFF" },
                     app: { type: "app", w: 64, h: 84, name: "Firefox", command: "firefox", icon: "firefox", color: "#FFFFFF", size: 12 },
                     weather: { type: "weather", w: 140, h: 140, city: "London", unit: "C", color: "#FFFFFF" },
                     calendar: { type: "calendar", w: 146, h: 146, color: "#FFFFFF", accent: "#FF453A" },
                     note: { type: "note", w: 180, h: 120, text: "", size: 15, color: "#FFFFFF" } }[type];
        var w = clone(cw); var it = clone(base); it.x = 16; it.y = 16;
        w.items.push(it); var l = widgets.slice(); l[current] = w; commit(l); sel = w.items.length - 1;
    }
    // a copy of the selected block, a little offset so it's visible
    function duplicateItem() {
        if (!ci) return;
        var w = clone(cw), it = clone(ci); it.x = (it.x || 0) + 12; it.y = (it.y || 0) + 12;
        w.items.push(it); var l = widgets.slice(); l[current] = w; commit(l); sel = w.items.length - 1;
    }
    // a copy of the whole widget (not on the desktop until you add it)
    function duplicateWidget(index) {
        var src = widgets[index === undefined ? current : index]; if (!src) return;
        var w = clone(src); w.id = Date.now().toString(36); w.name = (w.name || "Widget") + " " + I18n.tr("copy");
        w.onDesktop = false; w.x = (w.x || 80) + 30; w.y = (w.y || 120) + 30;
        var l = widgets.slice(); l.push(w); commit(l); current = l.length - 1; sel = -1;
    }
    // arrow keys: move the selected block 1 px (10 px with Shift), kept inside the widget
    function nudge(dx, dy) {
        if (!ci) return;
        updateItem({ x: Math.max(0, Math.min(cw.w - (ci.w || 0), (ci.x || 0) + dx)), y: Math.max(0, Math.min(cw.h - (ci.h || 0), (ci.y || 0) + dy)) });
    }
    function sendBackward() {
        if (!ci || sel <= 0) return;
        var w = clone(cw), it = w.items.splice(sel, 1)[0]; w.items.splice(sel - 1, 0, it);
        var l = widgets.slice(); l[current] = w; commit(l); sel = sel - 1;
    }
    function deleteItem() {
        if (!ci) return;
        var w = clone(cw); w.items.splice(sel, 1); var l = widgets.slice(); l[current] = w; commit(l); sel = -1;
    }
    function deleteWidget() {
        if (!cw) return;
        var l = widgets.slice(); l.splice(current, 1); commit(l); current = Math.min(current, l.length - 1); sel = -1;
    }
    function setItemField(index, itemIndex, key, value) {
        var l = widgets.slice(), w = clone(l[index]);
        if (!w.items[itemIndex]) return;
        w.items[itemIndex][key] = value; l[index] = w; commit(l);
    }
    // share a widget: export it as a .ffwidget file, import one (Documents\FreeForm Widgets)
    readonly property string shareDir: home + "/Documents/FreeForm Widgets"
    property var shared: []                  // [{ name, path }]
    function winPath(p) { return String(p).split("/").join(String.fromCharCode(92)); }
    property string pendingExport: ""
    property string pendingName: ""
    function exportWidget() {
        if (!cw) return;
        var w = clone(cw); delete w.onDesktop; delete w.x; delete w.y; delete w.id;
        pendingName = String(w.name || "Widget").replace(/[^A-Za-z0-9 _-]/g, "").trim() || "Widget";
        pendingExport = JSON.stringify(w, null, 1);
        mkdirProc.command = Qt.platform.os === "windows" ? ["cmd.exe", "/c", "if not exist \"" + winPath(shareDir) + "\" mkdir \"" + winPath(shareDir) + "\""]
                                                         : ["mkdir", "-p", shareDir];
        mkdirProc.running = true;
    }
    Process {
        id: mkdirProc
        onExited: {
            exportFile.path = root.shareDir + "/" + root.pendingName + ".ffwidget";
            exportFile.setText(root.pendingExport);
            Qt.openUrlExternally("file:///" + root.shareDir.replace(/^\/+/, ""));
            root.listShared();
        }
    }
    FileView { id: exportFile; printErrors: false }
    function listShared() { listProc.running = false; listProc.running = true; }
    Process {
        id: listProc
        command: Qt.platform.os === "windows"
            ? ["cmd.exe", "/c", "dir", "/b", root.winPath(root.shareDir) + String.fromCharCode(92) + "*.ffwidget"]
            : ["sh", "-c", 'cd "$1" 2>/dev/null && ls -1 *.ffwidget 2>/dev/null', "sh", root.shareDir]
        stdout: StdioCollector {
            onStreamFinished: root.shared = text.split(/\r?\n/).filter(function (l) { return /\.ffwidget$/i.test(l); }).map(function (f) {
                return { path: root.shareDir + "/" + f, name: f.replace(/\.ffwidget$/i, "") };
            })
        }
    }
    FileView { id: importFile; printErrors: false; blockLoading: true }
    function importWidget(path) {
        importFile.path = path;
        var w = null;
        try { w = JSON.parse(importFile.text()); } catch (e) { return; }
        if (!w || !Array.isArray(w.items)) return;
        w.id = Date.now().toString(36); w.onDesktop = false; w.x = 80 + widgets.length * 30; w.y = 120 + widgets.length * 30;
        var l = widgets.slice(); l.push(w); commit(l); current = l.length - 1; sel = -1;
    }

    function moveDesktop(index, x, y) {
        var l = widgets.slice(), w = clone(l[index]); w.x = snapX(x); w.y = snapY(y); l[index] = w; commit(l);
    }

    // ── saving ──
    FileView {
        id: store
        path: root.home + "/.config/macshell/custom-widgets.json"
        printErrors: false
        onLoaded: { try { var o = JSON.parse(text()); root.widgets = o.widgets || []; root.matchTheme = !!o.matchTheme; } catch (e) {} root.loaded = true; root.migrateGrid(); }
        onLoadFailed: { root.addDefaults(); root.undoStack = []; root.loaded = true; }
    }
    Timer { id: saveTimer; interval: 400; onTriggered: store.setText(JSON.stringify({ widgets: root.widgets, matchTheme: root.matchTheme }, null, 1)) }
    onMatchThemeChanged: if (loaded) saveTimer.restart()

    // ═════════════ ON THE DESKTOP ═════════════
    // the grid, shown on the desktop while a widget is being moved
    Variants {
        model: root.movingIndex >= 0 ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region { }
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "freeform-widget-grid"
            Repeater {
                model: root.gridCols * root.gridRows
                delegate: Rectangle {
                    required property int index
                    readonly property int cols: root.gridCols
                    x: root.gridX(index % cols); y: root.gridY(Math.floor(index / cols))
                    width: root.gridUnit; height: root.gridUnit; radius: 22
                    color: Qt.rgba(1, 1, 1, 0.06); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.28)
                }
            }
        }
    }

    Variants {
        model: root.widgets.map(function (w, i) { return { w: w, i: i }; }).filter(function (e) { return e.w.onDesktop; })
        PanelWindow {
            id: dw
            required property var modelData
            readonly property var w: modelData.w
            property real dragX: 0
            property real dragY: 0
            // the screen it was put on (by name), else the first one (e.g. that monitor is unplugged)
            screen: {
                var ss = Quickshell.screens;
                for (var k = 0; k < ss.length; k++) if (ss[k].name === dw.w.screen) return ss[k];
                return ss.length > 0 ? ss[0] : null;
            }
            anchors { top: true; left: true }
            margins { left: Math.max(0, (dw.w.x || 0) + dragX); top: Math.max(0, (dw.w.y || 0) + dragY) }
            property bool menuOpen: false
            // room for the right-click menu under the widget while it's open
            implicitWidth: Math.max(dw.w.w, menuOpen ? 210 : 0); implicitHeight: dw.w.h + (menuOpen ? menuBox.height + 8 : 0) + (moving ? 44 : 0)
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "freeform-widget"
            // a widget with a sticky note takes the keyboard when clicked
            WlrLayershell.keyboardFocus: (dw.w.items || []).some(function (x) { return x.type === "note"; }) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            WidgetView { widget: root.themed(dw.w); ctx: wctx; fam: root.fam; onItemEdited: (index, key, value) => root.setItemField(dw.modelData.i, index, key, value) }
            // drag anywhere that isn't a control to move it; saved when let go
            readonly property bool moving: root.movingIndex === dw.modelData.i
            // Move mode: highlighted outline and a Done button; dragging snaps to the grid
            Rectangle {
                visible: dw.moving
                width: dw.w.w; height: dw.w.h; radius: dw.w.bg && dw.w.bg.radius !== undefined ? dw.w.bg.radius : 22
                color: "transparent"; border.width: 3; border.color: root.accent
                Rectangle {
                    anchors.right: parent.right; anchors.top: parent.bottom; anchors.topMargin: 8
                    width: doneT.implicitWidth + 28; height: 30; radius: 15; color: root.accent
                    Text { id: doneT; anchors.centerIn: parent; text: I18n.tr("Done"); color: "white"; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; onClicked: root.movingIndex = -1 }
                }
            }
            // right-click: a menu with Move / Edit / Remove from Desktop / Delete
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: { dw.menuOpen = !dw.menuOpen; menuClose.restart(); } }
            TapHandler { acceptedButtons: Qt.LeftButton; onTapped: dw.menuOpen = false }
            Timer { id: menuClose; interval: 6000; onTriggered: dw.menuOpen = false }
            Rectangle {
                id: menuBox
                visible: dw.menuOpen
                y: dw.w.h + 6; width: 200; height: menuCol.height + 10; radius: 10
                color: root.darkMode ? "#2C2C2E" : "#FFFFFF"
                border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)
                Column {
                    id: menuCol
                    x: 5; y: 5; width: parent.width - 10
                    Repeater {
                        model: [{ t: "Move", a: "move" }, { t: "Edit Widget\u2026", a: "edit" }, { t: "Remove from Desktop", a: "hide" }, { t: "Delete Widget", a: "delete", warn: true }]
                        delegate: Rectangle {
                            required property var modelData
                            width: menuCol.width; height: 28; radius: 6
                            color: mItem.containsMouse ? root.accent : "transparent"
                            Text {
                                x: 10; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(parent.modelData.t)
                                color: mItem.containsMouse ? "white" : (parent.modelData.warn ? "#FF453A" : (root.darkMode ? "#F5F5F7" : "#1D1D1F"))
                                font.family: root.fam; font.pixelSize: 13
                            }
                            MouseArea {
                                id: mItem; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    var i = dw.modelData.i, a = parent.modelData.a;
                                    dw.menuOpen = false;
                                    if (a === "move") root.movingIndex = i;
                                    else if (a === "edit") { root.current = i; root.sel = -1; root.open(); }
                                    else if (a === "hide") root.removeFromDesktop(i);
                                    else root.deleteAt(i);
                                }
                            }
                        }
                    }
                }
            }
            DragHandler {
                target: null
                enabled: dw.moving                      // only in Move mode, so a click on a widget never moves it
                acceptedButtons: Qt.LeftButton
                onTranslationChanged: { dw.dragX = translation.x; dw.dragY = translation.y; }
                onActiveChanged: if (!active) { root.moveDesktop(dw.modelData.i, (dw.w.x || 0) + dw.dragX, (dw.w.y || 0) + dw.dragY); dw.dragX = 0; dw.dragY = 0; }
            }
        }
    }

    // ═════════════ THE EDITOR ═════════════
    Window {
        id: win
        title: "Widget Studio"
        width: 1120; height: 700
        minimumWidth: 900; minimumHeight: 560
        visible: false
        // Windows: glass (Windows 11 acrylic blur behind, corners rounded by Windows); elsewhere the rounded frame below
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        property int ffBackdrop: 3
        property bool ffDarkGlass: pal.dark
        // glass while it's a window; solid when maximized or fullscreen, so the desktop doesn't show through
        readonly property bool solid: visibility === Window.Maximized || visibility === Window.FullScreen

        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            // a FreeForm theme preset (Settings > Appearance > Theme) recolours the window
            readonly property var preset: root.dock && root.dock.themePreset && root.dock.themePreset !== "default"
                                          ? root.dock.themePresets.filter(function (t) { return t.id === root.dock.themePreset; })[0] : null
            readonly property color bg: preset ? preset.bg : (dark ? "#1E1E1E" : "#FFFFFF")
            readonly property color side: preset ? preset.card : (dark ? "#2A2A2C" : "#F0F0F2")
            readonly property color canvas: dark ? "#141416" : "#E5E5EA"
            readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color sel: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
            readonly property color text: dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
            readonly property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)
            readonly property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.15)
        }

        // small building blocks of the inspector
        component Label: Text { color: pal.text2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
        component Field: Rectangle {
            id: fld
            property alias text: ti.text
            signal edited(string text)
            width: parent ? parent.width : 200; height: 28; radius: 7; color: pal.field
            TextInput {
                id: ti
                x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                color: pal.text; font.family: root.fam; font.pixelSize: 13; clip: true; selectByMouse: true
                onTextEdited: fld.edited(text)
            }
        }
        component Chip: Rectangle {
            id: ch
            property string label: ""
            property bool on: false
            signal clicked()
            width: cht.implicitWidth + 18; height: 26; radius: 13
            color: on ? root.accent : pal.field
            Text { id: cht; anchors.centerIn: parent; text: ch.label; color: ch.on ? "white" : pal.text; font.family: root.fam; font.pixelSize: 12 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
        }
        component Stepper: Row {
            id: st
            property string label: ""
            property int value: 0
            property int step: 1
            signal changed(int v)
            spacing: 6
            Text { width: 26; anchors.verticalCenter: parent.verticalCenter; text: st.label; color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
            Rectangle {
                width: 26; height: 26; radius: 7; color: pal.field
                Text { anchors.centerIn: parent; text: "−"; color: pal.text }
                MouseArea { anchors.fill: parent; onClicked: st.changed(st.value - st.step) }
            }
            Text { width: 34; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter; text: st.value; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
            Rectangle {
                width: 26; height: 26; radius: 7; color: pal.field
                Text { anchors.centerIn: parent; text: "+"; color: pal.text }
                MouseArea { anchors.fill: parent; onClicked: st.changed(st.value + st.step) }
            }
        }
        readonly property var swatches: ["#FFFFFF", "#B0B0B5", "#1C1C1E", "#000000", "#0A84FF", "#30D158", "#FFD60A", "#FF9F0A", "#FF453A", "#FF375F", "#BF5AF2", "#64D2FF"]
        component Swatches: Flow {
            id: sw
            property string value: ""
            signal changed(string c)
            width: parent ? parent.width : 200; spacing: 6
            Repeater {
                model: win.swatches
                delegate: Rectangle {
                    required property string modelData
                    width: 22; height: 22; radius: 11; color: modelData
                    border.width: sw.value.toUpperCase() === modelData ? 3 : 1
                    border.color: sw.value.toUpperCase() === modelData ? root.accent : pal.border
                    MouseArea { anchors.fill: parent; onClicked: sw.changed(parent.modelData) }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12; color: Qt.rgba(Qt.color(pal.bg).r, Qt.color(pal.bg).g, Qt.color(pal.bg).b, win.solid ? 1 : 0.55)
            border.width: 1; border.color: pal.border
            clip: true
            // Windows caption buttons, top right
            WinCaption { z: 100; window: win; dark: pal.dark; anchors.top: parent.top; anchors.right: parent.right; anchors.rightMargin: 1 }

            MouseArea { x: parent.width - 8; y: parent.height - 8; width: 8; height: 8; z: 100; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            // ── left: my widgets + templates ──
            Rectangle {
                id: side
                width: 220; height: parent.height; color: Qt.rgba(Qt.color(pal.side).r, Qt.color(pal.side).g, Qt.color(pal.side).b, win.solid ? 1 : 0.45)
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                Column {
                    x: 10; y: 52; width: parent.width - 20; spacing: 2
                    Label { leftPadding: 8; text: I18n.tr("MY WIDGETS") }
                    Repeater {
                        model: root.widgets
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width; height: 32; radius: 7
                            color: root.current === index ? pal.sel : "transparent"
                            id: wrow
                            Text { x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 80; elide: Text.ElideRight; text: wrow.modelData.name; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; id: wrowMa; onClicked: { root.current = wrow.index; root.sel = -1; } }
                            // on the desktop (green) or not: click to toggle
                            Rectangle {
                                anchors.right: dupBtn.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                width: 10; height: 10; radius: 5
                                color: wrow.modelData.onDesktop ? "#30D158" : "transparent"; border.width: 1; border.color: wrow.modelData.onDesktop ? "#30D158" : pal.text2
                                MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: { root.current = wrow.index; root.updateWidget({ onDesktop: !wrow.modelData.onDesktop }); } }
                            }
                            // duplicate this widget
                            Text {
                                id: dupBtn
                                anchors.right: delBtn.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                text: "\u29C9"; color: pal.text2; font.pixelSize: 13
                                opacity: wrowMa.containsMouse || dupMa.containsMouse ? 1 : 0
                                MouseArea { id: dupMa; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; onClicked: root.duplicateWidget(wrow.index) }
                            }
                            // delete this widget
                            Text {
                                id: delBtn
                                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                text: "\u00D7"; color: pal.text2; font.pixelSize: 17
                                opacity: wrowMa.containsMouse || delMa.containsMouse ? 1 : 0.35
                                MouseArea { id: delMa; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; onClicked: { root.current = wrow.index; root.deleteWidget(); } }
                            }
                        }
                    }
                    Item { width: 1; height: 12 }
                    Label { leftPadding: 8; text: I18n.tr("NEW FROM TEMPLATE") }
                    Repeater {
                        model: root.templates
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width; height: 30; radius: 7
                            color: tma.containsMouse ? pal.sel : "transparent"
                            Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "+  " + parent.modelData.name; color: root.accent; font.family: root.fam; font.pixelSize: 13 }
                            MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; onClicked: root.addFromTemplate(parent.index) }
                        }
                    }
                }
            }

            // ── centre: toolbar + canvas ──
            Item {
                id: centre
                x: side.width; width: parent.width - side.width - inspector.width; height: parent.height
                Rectangle {
                    id: toolbar
                    width: parent.width; height: Math.max(52, addFlow.height + 18); color: "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.sep }
                    DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                    Flow {
                        id: addFlow
                        x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        width: parent.width - 32 - toolRight.width - 12      // wraps to a 2nd line on narrow windows
                        // back / forward one change (greyed out when there's nothing to undo / redo)
                        Repeater {
                            model: [{ g: "\u21B6", tip: "Undo", can: function () { return root.undoStack.length > 0; }, f: function () { root.undo(); } },
                                    { g: "\u21B7", tip: "Redo", can: function () { return root.redoStack.length > 0; }, f: function () { root.redo(); } }]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool can: (root.undoStack, root.redoStack, modelData.can())
                                width: 30; height: 26; radius: 13; color: pal.field
                                opacity: can ? 1 : 0.35
                                Text { anchors.centerIn: parent; text: parent.modelData.g; color: pal.text; font.pixelSize: 16 }
                                MouseArea { anchors.fill: parent; enabled: parent.can; cursorShape: Qt.PointingHandCursor; onClicked: parent.modelData.f() }
                            }
                        }
                        Item { width: 6; height: 1 }
                        Repeater {
                            model: [{ t: "text", l: "Text" }, { t: "button", l: "Button" }, { t: "art", l: "Album Art" }, { t: "progress", l: "Progress" }, { t: "image", l: "Image" }, { t: "shape", l: "Shape" }, { t: "clock", l: "Clock" }, { t: "app", l: "App Shortcut" }, { t: "weather", l: "Weather" }, { t: "calendar", l: "Calendar" }, { t: "note", l: "Note" }]
                            delegate: Chip { required property var modelData; label: "+ " + I18n.tr(modelData.l); onClicked: root.addItem(modelData.t) }
                        }
                    }
                    Row {
                        id: toolRight
                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        // multi-monitor: which screen the widget lives on (click to cycle)
                        Chip {
                            visible: !!root.cw && Quickshell.screens.length > 1
                            label: I18n.tr("Screen: ") + (root.cw && root.cw.screen ? root.cw.screen : (Quickshell.screens.length ? Quickshell.screens[0].name : ""))
                            onClicked: {
                                var ss = Quickshell.screens, cur = root.cw.screen || ss[0].name, i = 0;
                                for (var k = 0; k < ss.length; k++) if (ss[k].name === cur) i = k;
                                root.updateWidget({ screen: ss[(i + 1) % ss.length].name, x: 80, y: 120 });
                            }
                        }
                        Chip {
                            visible: !!root.cw
                            label: root.cw && root.cw.onDesktop ? I18n.tr("Remove from Desktop") : I18n.tr("Add to Desktop")
                            on: !!(root.cw && root.cw.onDesktop)
                            onClicked: root.updateWidget({ onDesktop: !root.cw.onDesktop })
                        }
                        Chip { visible: !!root.cw; label: I18n.tr("Duplicate"); onClicked: root.duplicateWidget() }
                        // all widgets in the desktop theme's colours
                        Chip { label: I18n.tr("Match Theme"); on: root.matchTheme; onClicked: root.matchTheme = !root.matchTheme }
                    }
                }
                Rectangle {
                    id: canvas
                    y: toolbar.height; width: parent.width; height: parent.height - toolbar.height
                    color: Qt.rgba(Qt.color(pal.canvas).r, Qt.color(pal.canvas).g, Qt.color(pal.canvas).b, 0.35)
                    // Delete / Backspace removes the selected block (click a block, then press it)
                    focus: true
                    Keys.onDeletePressed: root.deleteItem()
                    Shortcut { sequences: [StandardKey.Undo]; onActivated: root.undo() }
                    Shortcut { sequences: [StandardKey.Redo]; onActivated: root.redo() }
                    Shortcut { sequence: "Ctrl+D"; onActivated: root.sel >= 0 ? root.duplicateItem() : root.duplicateWidget() }
                    Keys.onPressed: event => {
                        var step = (event.modifiers & Qt.ShiftModifier) ? 10 : 1;
                        if (event.key === Qt.Key_Backspace && root.sel >= 0) root.deleteItem();
                        else if (event.key === Qt.Key_Left) root.nudge(-step, 0);
                        else if (event.key === Qt.Key_Right) root.nudge(step, 0);
                        else if (event.key === Qt.Key_Up) root.nudge(0, -step);
                        else if (event.key === Qt.Key_Down) root.nudge(0, step);
                        else return;
                        event.accepted = true;
                    }
                    // dotted grid
                    Canvas {
                        anchors.fill: parent
                        onPaint: { var c = getContext("2d"); c.fillStyle = pal.dark ? "rgba(255,255,255,0.07)" : "rgba(0,0,0,0.08)"; for (var x = 10; x < width; x += 20) for (var y = 10; y < height; y += 20) c.fillRect(x, y, 2, 2); }
                    }
                    MouseArea { anchors.fill: parent; onPressed: { root.sel = -1; canvas.forceActiveFocus(); } }
                    Text {
                        visible: !root.cw
                        anchors.centerIn: parent
                        text: I18n.tr("Pick a template on the left to start")
                        color: pal.text2; font.family: root.fam; font.pixelSize: 15
                    }
                    Item {
                        id: stage
                        visible: !!root.cw
                        readonly property real sc: root.cw ? Math.min(2, (canvas.width - 80) / root.cw.w, (canvas.height - 80) / root.cw.h) : 1
                        width: root.cw ? root.cw.w : 0; height: root.cw ? root.cw.h : 0
                        anchors.centerIn: parent
                        scale: sc
                        WidgetView {
                            id: preview
                            widget: root.themed(root.cw) || ({ w: 10, h: 10, items: [] })
                            ctx: wctx; fam: root.fam
                            editing: true; selected: root.sel
                            onPicked: i => root.sel = i
                        }
                        // drag the selected item; corner handle resizes it
                        Item {
                            visible: !!root.ci
                            x: root.ci ? root.ci.x : 0; y: root.ci ? root.ci.y : 0
                            width: root.ci ? root.ci.w : 0; height: root.ci ? root.ci.h : 0
                            property real ox: 0
                            property real oy: 0
                            DragHandler {
                                target: null
                                onActiveChanged: if (active) { parent.ox = root.ci.x; parent.oy = root.ci.y; }
                                onTranslationChanged: if (active && root.ci) root.updateItem({ x: Math.round(parent.ox + translation.x / stage.sc), y: Math.round(parent.oy + translation.y / stage.sc) })
                            }
                            Rectangle {
                                x: parent.width - 6; y: parent.height - 6; width: 12; height: 12; radius: 6
                                color: "white"; border.width: 2; border.color: root.accent
                                property real ow: 0
                                property real oh: 0
                                DragHandler {
                                    target: null
                                    onActiveChanged: if (active) { parent.ow = root.ci.w; parent.oh = root.ci.h; }
                                    onTranslationChanged: if (active && root.ci) root.updateItem({ w: Math.max(8, Math.round(parent.ow + translation.x / stage.sc)), h: Math.max(4, Math.round(parent.oh + translation.y / stage.sc)) })
                                }
                            }
                        }
                    }
                }
            }

            // ── right: inspector ──
            Rectangle {
                id: inspector
                anchors.right: parent.right
                width: 280; height: parent.height; color: Qt.rgba(Qt.color(pal.side).r, Qt.color(pal.side).g, Qt.color(pal.side).b, win.solid ? 1 : 0.45)
                Rectangle { width: 1; height: parent.height; color: pal.sep }
                Flickable {
                    anchors.fill: parent; anchors.margins: 16; anchors.topMargin: 40      // room for the caption buttons
                    contentHeight: insp.height; clip: true
                    Column {
                        id: insp
                        width: parent.width; spacing: 8
                        visible: !!root.cw

                        // the selected item
                        Column {
                            visible: !!root.ci
                            width: parent.width; spacing: 8
                            Text { text: root.ci ? I18n.tr({ text: "Text", button: "Button", art: "Album Art", progress: "Progress Bar", image: "Image", shape: "Shape", clock: "Clock", app: "App Shortcut" }[root.ci.type]) : ""; color: pal.text; font.family: root.fam; font.pixelSize: 17; font.weight: Font.Bold }
                            Grid {
                                columns: 2; spacing: 6
                                Stepper { label: "X"; value: root.ci ? root.ci.x : 0; onChanged: v => root.updateItem({ x: v }) }
                                Stepper { label: "Y"; value: root.ci ? root.ci.y : 0; onChanged: v => root.updateItem({ y: v }) }
                                Stepper { label: "W"; value: root.ci ? root.ci.w : 0; onChanged: v => root.updateItem({ w: Math.max(4, v) }) }
                                Stepper { label: "H"; value: root.ci ? root.ci.h : 0; onChanged: v => root.updateItem({ h: Math.max(4, v) }) }
                            }
                            // text
                            Label { visible: root.ci && (root.ci.type === "text" || root.ci.type === "button"); text: root.ci && root.ci.type === "button" ? I18n.tr("LABEL (optional)") : I18n.tr("TEXT") }
                            Field {
                                visible: root.ci && (root.ci.type === "text" || root.ci.type === "button")
                                text: root.ci ? (root.ci.type === "button" ? root.ci.label || "" : root.ci.text || "") : ""
                                onEdited: t => root.updateItem(root.ci.type === "button" ? { label: t } : { text: t })
                            }
                            Flow {
                                visible: root.ci && root.ci.type === "text"
                                width: parent.width; spacing: 4
                                Repeater {
                                    model: wctx.tokens
                                    delegate: Chip { required property string modelData; label: "{" + modelData + "}"; onClicked: root.updateItem({ text: (root.ci.text || "") + "{" + modelData + "}" }) }
                                }
                            }
                            Row {
                                visible: root.ci && (root.ci.type === "text" || root.ci.type === "button")
                                spacing: 6
                                Stepper { label: I18n.tr("Size"); value: root.ci ? root.ci.size || 14 : 14; onChanged: v => root.updateItem({ size: Math.max(6, v) }) }
                                Chip { visible: root.ci && root.ci.type === "text"; label: "B"; on: !!(root.ci && root.ci.bold); onClicked: root.updateItem({ bold: !root.ci.bold }) }
                                Chip { visible: root.ci && root.ci.type === "text"; label: "I"; on: !!(root.ci && root.ci.italic); onClicked: root.updateItem({ italic: !root.ci.italic }) }
                                Chip { visible: root.ci && root.ci.type === "text"; label: "U"; on: !!(root.ci && root.ci.underline); onClicked: root.updateItem({ underline: !root.ci.underline }) }
                            }
                            Row {
                                visible: root.ci && root.ci.type === "text"
                                spacing: 4
                                Repeater {
                                    model: ["left", "center", "right"]
                                    delegate: Chip { required property string modelData; label: I18n.tr(modelData); on: root.ci && (root.ci.align || "left") === modelData; onClicked: root.updateItem({ align: modelData }) }
                                }
                            }
                            // ── text: outline, spacing, font ──
                            Label { visible: root.ci && root.ci.type === "text"; text: I18n.tr("OUTLINE") }
                            Swatches { visible: root.ci && root.ci.type === "text"; value: root.ci ? root.ci.outline || "" : ""; onChanged: c => root.updateItem({ outline: root.ci.outline === c ? "" : c }) }
                            Stepper { visible: root.ci && root.ci.type === "text"; label: I18n.tr("Gap"); value: root.ci ? root.ci.spacing || 0 : 0; onChanged: v => root.updateItem({ spacing: v }) }
                            Flow {
                                visible: root.ci && root.ci.type === "text"
                                width: parent.width; spacing: 4
                                Repeater {
                                    model: ["", "Segoe UI", "Arial", "Georgia", "Consolas", "Impact", "Comic Sans MS"]
                                    delegate: Chip { required property string modelData; label: modelData || "Open Runde"; on: root.ci && (root.ci.font || "") === modelData; onClicked: root.updateItem({ font: modelData }) }
                                }
                            }
                            // ── text: style single words or letters ──
                            Label { visible: root.ci && root.ci.type === "text"; text: I18n.tr("CLICK A WORD OR LETTER TO STYLE IT") }
                            Row {
                                visible: root.ci && root.ci.type === "text"
                                spacing: 4
                                Chip { label: I18n.tr("Words"); on: root.spanMode === "w"; onClicked: { root.spanMode = "w"; root.spanPick = -1; } }
                                Chip { label: I18n.tr("Letters"); on: root.spanMode === "c"; onClicked: { root.spanMode = "c"; root.spanPick = -1; } }
                                Chip { label: I18n.tr("Clear styles"); onClicked: { root.updateItem({ spans: {} }); root.spanPick = -1; } }
                            }
                            Flow {
                                visible: root.ci && root.ci.type === "text"
                                width: parent.width; spacing: 3
                                Repeater {
                                    model: root.ci && root.ci.type === "text" ? (root.spanMode === "w" ? String(root.ci.text || "").split(" ") : String(root.ci.text || "").split("")) : []
                                    delegate: Rectangle {
                                        required property string modelData
                                        required property int index
                                        readonly property var st: root.ci && root.ci.spans ? root.ci.spans[root.spanMode + index] : null
                                        width: Math.max(16, pt.implicitWidth + 10); height: 24; radius: 6
                                        color: root.spanPick === index ? root.accent : pal.field
                                        Text { id: pt; anchors.centerIn: parent; text: parent.modelData === " " ? "\u2423" : parent.modelData; color: parent.st && parent.st.color ? parent.st.color : pal.text; font.bold: !!(parent.st && parent.st.bold); font.family: root.fam; font.pixelSize: 12 }
                                        MouseArea { anchors.fill: parent; onClicked: root.spanPick = parent.index }
                                    }
                                }
                            }
                            Swatches {
                                visible: root.ci && root.ci.type === "text" && root.spanPick >= 0
                                value: ""
                                onChanged: c => root.setSpan({ color: c })
                            }
                            Row {
                                visible: root.ci && root.ci.type === "text" && root.spanPick >= 0
                                spacing: 4
                                Chip { label: "B"; onClicked: root.setSpan({ bold: true }) }
                                Chip { label: "I"; onClicked: root.setSpan({ italic: true }) }
                                Chip { label: "U"; onClicked: root.setSpan({ underline: true }) }
                                Chip { label: I18n.tr("Reset"); onClicked: root.setSpan(null) }
                            }
                            // button action
                            Label { visible: root.ci && root.ci.type === "button"; text: I18n.tr("WHEN CLICKED") }
                            Flow {
                                visible: root.ci && root.ci.type === "button"
                                width: parent.width; spacing: 4
                                Repeater {
                                    model: wctx.actions
                                    delegate: Chip { required property var modelData; label: I18n.tr(modelData.label); on: root.ci && root.ci.action === modelData.id; onClicked: root.updateItem({ action: modelData.id }) }
                                }
                            }
                            Label { visible: root.ci && (root.ci.action === "open.app" || root.ci.action === "open.url"); text: root.ci && root.ci.action === "open.url" ? I18n.tr("WEBSITE") : I18n.tr("APP OR COMMAND") }
                            Field {
                                visible: root.ci && (root.ci.action === "open.app" || root.ci.action === "open.url")
                                text: root.ci ? root.ci.param || "" : ""
                                onEdited: t => root.updateItem({ param: t })
                            }
                            Label { visible: root.ci && root.ci.type === "button"; text: I18n.tr("ICON") }
                            Flow {
                                visible: root.ci && root.ci.type === "button"
                                width: parent.width; spacing: 4
                                Repeater {
                                    model: ["auto", "play", "pause", "next", "prev", "shuffle", "repeat", "volume", "speaker", "note", "appstore", "gear", "search", "folder", "link", "power", "moon", "sun", "none"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: 30; height: 30; radius: 7
                                        color: root.ci && (root.ci.icon || "auto") === modelData ? root.accent : pal.field
                                        WGlyph { visible: parent.modelData !== "auto" && parent.modelData !== "none"; anchors.centerIn: parent; width: 15; height: 15; kind: parent.modelData; color: pal.text }
                                        Text { visible: parent.modelData === "auto" || parent.modelData === "none"; anchors.centerIn: parent; text: parent.modelData === "auto" ? "A" : "—"; color: pal.text; font.pixelSize: 11 }
                                        MouseArea { anchors.fill: parent; onClicked: root.updateItem({ icon: parent.modelData }) }
                                    }
                                }
                            }
                            // progress source
                            Label { visible: root.ci && root.ci.type === "progress"; text: I18n.tr("SHOWS") }
                            Row {
                                visible: root.ci && root.ci.type === "progress"
                                spacing: 4
                                Repeater {
                                    model: [{ v: "media", l: "Song" }, { v: "volume", l: "Volume" }, { v: "battery", l: "Battery" }, { v: "cpu", l: "CPU" }, { v: "ram", l: "Memory" }, { v: "gpu", l: "GPU" }]
                                    delegate: Chip { required property var modelData; label: I18n.tr(modelData.l); on: root.ci && (root.ci.source || "media") === modelData.v; onClicked: root.updateItem({ source: modelData.v }) }
                                }
                            }
                            Label { visible: root.ci && root.ci.type === "progress"; text: I18n.tr("TRACK (behind the bar)") }
                            Swatches { visible: root.ci && root.ci.type === "progress"; value: root.ci ? root.ci.track || "" : ""; onChanged: c => root.updateItem({ track: c }) }
                            Stepper { visible: root.ci && root.ci.type === "progress"; label: I18n.tr("Thick"); value: root.ci ? root.ci.thick || 6 : 6; onChanged: v => root.updateItem({ thick: Math.max(1, v), h: Math.max(root.ci.h || 6, v) }) }
                            // app shortcut
                            Label { visible: root.ci && root.ci.type === "app"; text: I18n.tr("NAME") }
                            Field { visible: root.ci && root.ci.type === "app"; text: root.ci ? root.ci.name || "" : ""; onEdited: t => root.updateItem({ name: t }) }
                            Label { visible: root.ci && root.ci.type === "app"; text: I18n.tr("OPENS (app, path or command)") }
                            Field { visible: root.ci && root.ci.type === "app"; text: root.ci ? root.ci.command || "" : ""; onEdited: t => root.updateItem({ command: t }) }
                            Label { visible: root.ci && root.ci.type === "app"; text: I18n.tr("ICON (icon name or image file)") }
                            Field { visible: root.ci && root.ci.type === "app"; text: root.ci ? root.ci.icon || "" : ""; onEdited: t => root.updateItem({ icon: t }) }
                            // weather
                            Label { visible: root.ci && root.ci.type === "weather"; text: I18n.tr("CITY") }
                            Field { visible: root.ci && root.ci.type === "weather"; text: root.ci ? root.ci.city || "" : ""; onEdited: t => root.updateItem({ city: t }) }
                            Row {
                                visible: root.ci && root.ci.type === "weather"
                                spacing: 4
                                Repeater {
                                    model: ["C", "F"]
                                    delegate: Chip { required property string modelData; label: "\u00B0" + modelData; on: root.ci && (root.ci.unit || "C") === modelData; onClicked: root.updateItem({ unit: modelData }) }
                                }
                            }
                            Text { visible: root.ci && root.ci.type === "weather"; width: parent.width; wrapMode: Text.WordWrap; text: I18n.tr("Weather data: MET Norway. Place search: OpenStreetMap."); color: pal.text2; font.family: root.fam; font.pixelSize: 10 }
                            // calendar
                            Label { visible: root.ci && root.ci.type === "calendar"; text: I18n.tr("TODAY") }
                            Swatches { visible: root.ci && root.ci.type === "calendar"; value: root.ci ? root.ci.accent || "" : ""; onChanged: c => root.updateItem({ accent: c }) }
                            // note
                            Stepper { visible: root.ci && root.ci.type === "note"; label: I18n.tr("Size"); value: root.ci ? root.ci.size || 15 : 15; onChanged: v => root.updateItem({ size: Math.max(8, v) }) }
                            Text { visible: root.ci && root.ci.type === "note"; width: parent.width; wrapMode: Text.WordWrap; text: I18n.tr("Type into the note on the desktop; it's saved by itself."); color: pal.text2; font.family: root.fam; font.pixelSize: 11 }
                            // clock
                            Label { visible: root.ci && root.ci.type === "clock"; text: I18n.tr("DIAL") }
                            Swatches { visible: root.ci && root.ci.type === "clock"; value: root.ci ? root.ci.face || "" : ""; onChanged: c => root.updateItem({ face: c }) }
                            Label { visible: root.ci && root.ci.type === "clock"; text: I18n.tr("SECOND HAND") }
                            Swatches { visible: root.ci && root.ci.type === "clock"; value: root.ci ? root.ci.hand || "" : ""; onChanged: c => root.updateItem({ hand: c }) }
                            // image
                            Label { visible: root.ci && root.ci.type === "image"; text: I18n.tr("IMAGE FILE OR LINK") }
                            Field { visible: root.ci && root.ci.type === "image"; text: root.ci ? root.ci.src || "" : ""; onEdited: t => root.updateItem({ src: t }) }
                            // radius
                            Stepper {
                                visible: root.ci && (root.ci.type === "art" || root.ci.type === "image" || root.ci.type === "shape")
                                label: I18n.tr("Round"); value: root.ci ? root.ci.radius || 0 : 0
                                onChanged: v => root.updateItem({ radius: Math.max(0, v) })
                            }
                            // colour
                            Label { visible: root.ci && root.ci.type !== "art" && root.ci.type !== "image"; text: I18n.tr("COLOUR") }
                            Swatches { visible: root.ci && root.ci.type !== "art" && root.ci.type !== "image"; value: root.ci ? root.ci.color || "#FFFFFF" : ""; onChanged: c => root.updateItem({ color: c }) }
                            // ── any block: turn, see-through, animation ──
                            Stepper { label: I18n.tr("Turn"); step: 15; value: root.ci ? root.ci.rotation || 0 : 0; onChanged: v => root.updateItem({ rotation: ((v % 360) + 360) % 360 }) }
                            Stepper { label: I18n.tr("Show"); step: 10; value: root.ci ? Math.round((root.ci.opacity !== undefined ? root.ci.opacity : 1) * 100) : 100; onChanged: v => root.updateItem({ opacity: Math.max(0.1, Math.min(1, v / 100)) }) }
                            Label { text: I18n.tr("ANIMATION") }
                            Flow {
                                width: parent.width; spacing: 4
                                Repeater {
                                    model: [{ v: "none", l: "None" }, { v: "pulse", l: "Pulse" }, { v: "float", l: "Float" }, { v: "spin", l: "Spin" }, { v: "glow", l: "Glow" }]
                                    delegate: Chip { required property var modelData; label: I18n.tr(modelData.l); on: root.ci && (root.ci.anim || "none") === modelData.v; onClicked: root.updateItem({ anim: modelData.v }) }
                                }
                            }
                            Row {
                                spacing: 6
                                Chip { label: I18n.tr("Bring Forward"); onClicked: { var w = root.clone(root.cw), it = w.items.splice(root.sel, 1)[0]; w.items.push(it); var l = root.widgets.slice(); l[root.current] = w; root.commit(l); root.sel = w.items.length - 1; } }
                                Chip { label: I18n.tr("Send Backward"); onClicked: root.sendBackward() }
                            }
                            Row {
                                spacing: 6
                                Chip { label: I18n.tr("Duplicate"); onClicked: root.duplicateItem() }
                                Chip { label: I18n.tr("Delete"); onClicked: root.deleteItem() }
                            }
                            Text { width: parent.width; wrapMode: Text.WordWrap; color: pal.text2; font.family: root.fam; font.pixelSize: 11
                                   text: I18n.tr("Arrow keys move it (Shift: 10 px). Ctrl+D duplicates.") }
                            Rectangle { width: parent.width; height: 1; color: pal.sep }
                        }

                        // the widget itself
                        Text { text: I18n.tr("Widget"); color: pal.text; font.family: root.fam; font.pixelSize: 17; font.weight: Font.Bold }
                        Label { text: I18n.tr("NAME") }
                        Field { text: root.cw ? root.cw.name : ""; onEdited: t => root.updateWidget({ name: t }) }
                        Grid {
                            columns: 2; spacing: 6
                            Stepper { label: "W"; step: 10; value: root.cw ? root.cw.w : 0; onChanged: v => root.updateWidget({ w: Math.max(60, v) }) }
                            Stepper { label: "H"; step: 10; value: root.cw ? root.cw.h : 0; onChanged: v => root.updateWidget({ h: Math.max(30, v) }) }
                        }
                        Label { text: I18n.tr("BACKGROUND") }
                        Swatches {
                            value: root.cw && root.cw.bg ? root.cw.bg.color : ""
                            onChanged: c => { var b = root.clone(root.cw.bg || {}); b.color = c; root.updateWidget({ bg: b }); }
                        }
                        Row {
                            spacing: 6
                            Stepper { label: I18n.tr("Clear"); step: 10; value: root.cw && root.cw.bg ? Math.round((1 - root.cw.bg.opacity) * 100) : 0
                                onChanged: v => { var b = root.clone(root.cw.bg || {}); b.opacity = Math.max(0, Math.min(1, 1 - v / 100)); root.updateWidget({ bg: b }); } }
                        }
                        Stepper { label: I18n.tr("Round"); step: 2; value: root.cw && root.cw.bg ? root.cw.bg.radius : 0
                            onChanged: v => { var b = root.clone(root.cw.bg || {}); b.radius = Math.max(0, v); root.updateWidget({ bg: b }); } }
                        Label { text: I18n.tr("SIZE ON THE DESKTOP GRID") }
                        Flow {
                            width: parent.width; spacing: 4
                            Repeater {
                                model: [[1, 1], [2, 1], [2, 2], [4, 2]]
                                delegate: Chip {
                                    required property var modelData
                                    label: modelData[0] + "\u00D7" + modelData[1]
                                    on: root.cw && root.cw.w === root.gridSpan(modelData[0]) && root.cw.h === root.gridSpan(modelData[1])
                                    onClicked: root.setGridSize(modelData[0], modelData[1])
                                }
                            }
                        }
                        Label { text: I18n.tr("DYNAMIC (album cover colours)") }
                        Flow {
                            width: parent.width; spacing: 4
                            Chip { label: I18n.tr("This widget"); on: !!(root.cw && root.cw.dynamic); onClicked: root.updateWidget({ dynamic: !root.cw.dynamic }) }
                            Chip { label: I18n.tr("Whole theme"); on: !!(root.cw && root.cw.dynamicTheme); onClicked: root.updateWidget({ dynamicTheme: !root.cw.dynamicTheme, dynamic: true }) }
                        }
                        Item { width: 1; height: 6 }
                        Row {
                            spacing: 6
                            Chip { label: I18n.tr("Export\u2026"); onClicked: root.exportWidget() }
                            Chip { label: I18n.tr("Delete Widget"); onClicked: root.deleteWidget() }
                        }
                        // widgets shared with you: .ffwidget files in Documents/FreeForm Widgets
                        Label { text: I18n.tr("IMPORT (Documents/FreeForm Widgets)") }
                        Flow {
                            width: parent.width; spacing: 4
                            Repeater {
                                model: root.shared
                                delegate: Chip { required property var modelData; label: "+ " + modelData.name; onClicked: root.importWidget(modelData.path) }
                            }
                            Chip { label: I18n.tr("Refresh"); onClicked: root.listShared() }
                        }
                    }
                }
            }
        }
    }
}
