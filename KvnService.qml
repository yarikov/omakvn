import QtQuick
import Quickshell
import Quickshell.Io

// Single connection to the kvn-tui daemon: NDJSON over a Unix socket.
//
// The daemon pushes a full StateSnapshot after every state change (and about
// once per second with live traffic while connected), so the widget never
// polls. Commands are one-line JSON writes in the other direction. When the
// daemon is down the socket link is retried on a timer until it comes back.
Item {
  id: root

  // --- state mirrored from the latest snapshot -----------------------------
  property bool daemonUp: false
  // Idle | Connecting | ConnectPending | Connected
  property string connection: "Idle"
  property string statusText: ""
  property bool statusIsError: false
  property string activeProfileId: ""
  // Profile requested by the UI but not yet confirmed by the daemon. The
  // daemon keeps reporting the previous active profile while it connects.
  property string pendingProfileId: ""
  property string lastProfileId: ""
  // [{ id, name, protocol, latencyMs (number|null), testing }]
  property var profiles: []
  // Persisted geo routing state; the active mode is derived the same way the
  // Rust model derives it: selected_region_modes[current_region] ?? "global".
  property string geoRegion: "" // "ru" | "cn" | "ir" | "global" | "" (unset)
  property string routingMode: "global"
  property bool killSwitch: false
  property bool autoConnect: false
  property var traffic: ({ up: 0, down: 0, upTotal: 0, downTotal: 0, conns: 0 })

  // The bridge frames raw socket bytes before UTF-8 decoding and emits
  // ASCII-only JSON. QML selects and bounds the fields that enter widget state.
  readonly property int maxSocketLineLength: 16 * 1024 * 1024
  readonly property int maxExternalStringLength: 1024
  readonly property int maxProfiles: 4096
  readonly property string bridgePath: {
    var url = String(Qt.resolvedUrl("ipc_bridge.py"))
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }
  property string _socketBuffer: ""
  property bool _discardingOversizeLine: false

  readonly property bool connected: connection === "Connected"
  readonly property bool busy: connection === "Connecting" || connection === "ConnectPending"

  function markDaemonDown() {
    daemonUp = false
    connection = "Idle"
    statusText = ""
    statusIsError = false
    activeProfileId = ""
    pendingProfileId = ""
    traffic = ({ up: 0, down: 0, upTotal: 0, downTotal: 0, conns: 0 })
    _socketBuffer = ""
    _discardingOversizeLine = false
  }

  // --- socket plumbing ------------------------------------------------------
  property string uid: ""
  readonly property var bridge: bridgeLoader.item

  readonly property string socketPath: {
    var xdg = Quickshell.env("XDG_RUNTIME_DIR") || ""
    if (xdg !== "") return xdg + "/kvn-tui.sock"
    return uid !== "" ? "/tmp/kvn-tui-" + uid + ".sock" : ""
  }

  function send(cmd) {
    if (!bridge || !bridge.running) return false
    bridge.write(JSON.stringify(cmd) + "\n")
    return true
  }

  function connectProfile(id) {
    if (send({ cmd: "ConnectProfile", profile_id: id }))
      pendingProfileId = String(id)
  }
  function disconnectVpn() { send({ cmd: "Disconnect" }) }
  function reconnect() { send({ cmd: "Reconnect" }) }
  function setRoutingMode(mode) { send({ cmd: "SetRoutingMode", mode: mode }) }
  function setGeoRegion(region) { send({ cmd: "SetGeoRegion", region: region }) }
  function setKillSwitch(enabled) { send({ cmd: "SetKillSwitch", enabled: enabled }) }
  function setAutoConnect(enabled) { send({ cmd: "SetAutoConnect", enabled: enabled }) }

  // Destroy and recreate the bridge until the daemon socket is available.
  function reconnectSocket() {
    bridgeLoader.active = false
    reconnectDelay.restart()
  }

  Timer {
    id: reconnectDelay
    interval: 100
    onTriggered: bridgeLoader.active = true
  }

  // Resolving the UID only matters when XDG_RUNTIME_DIR is unset (rare);
  // `id -u` runs once at startup.
  Process {
    command: ["id", "-u"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.uid = String(text || "").trim()
    }
  }

  Loader {
    id: bridgeLoader
    active: root.socketPath !== ""
    sourceComponent: Process {
      command: ["python3", root.bridgePath, root.socketPath]
      running: true
      stdinEnabled: true
      stdout: SplitParser {
        // Bridge output is ASCII, so arbitrary read boundaries are safe.
        splitMarker: ""
        onRead: function(data) { root.handleSocketData(data) }
      }
      onExited: {
        root.markDaemonDown()
      }
    }
  }

  // Flip the link off and on until the daemon answers. A failed connect
  // leaves the Socket dead — it does not retry on its own.
  Timer {
    interval: 1000
    repeat: true
    running: !root.daemonUp && root.socketPath !== ""
    onTriggered: root.reconnectSocket()
  }

  property string _profilesKey: ""

  function boundedString(value) {
    if (value === undefined || value === null) return ""
    var result = String(value)
    return result.length <= maxExternalStringLength
      ? result : result.slice(0, maxExternalStringLength)
  }

  function handleSocketData(data) {
    var chunk = String(data)
    var offset = 0

    while (offset < chunk.length) {
      var newline = chunk.indexOf("\n", offset)
      var end = newline === -1 ? chunk.length : newline
      var fragment = chunk.slice(offset, end)

      if (!_discardingOversizeLine) {
        if (_socketBuffer.length + fragment.length <= maxSocketLineLength) {
          _socketBuffer += fragment
        } else {
          _socketBuffer = ""
          _discardingOversizeLine = true
        }
      }

      if (newline === -1) return

      if (!_discardingOversizeLine) {
        var line = _socketBuffer
        if (line.endsWith("\r")) line = line.slice(0, -1)
        if (line !== "") handleLine(line)
      }

      _socketBuffer = ""
      _discardingOversizeLine = false
      offset = newline + 1
    }
  }

  function handleLine(data) {
    var snap
    try {
      snap = JSON.parse(String(data))
    } catch (e) {
      return
    }
    if (!snap || typeof snap !== "object" || Array.isArray(snap)
        || snap.connection === undefined) return

    // A valid snapshot is definitive proof that the daemon is reachable.
    // The socket can connect during component construction, before QML sees
    // connectionStateChanged, so do not rely on that signal alone.
    daemonUp = true

    connection = boundedString(snap.connection)
    statusText = boundedString(snap.status)
    statusIsError = snap.status_is_error === true
    activeProfileId = boundedString(snap.active_profile_id)
    // Keep the requested profile after a failed attempt so the disconnected
    // UI still reflects the user's latest selection. A successful connection
    // promotes it to activeProfileId, at which point it is safe to clear.
    if (connection === "Connected")
      pendingProfileId = ""

    var settings = snap.settings && typeof snap.settings === "object"
      && !Array.isArray(snap.settings) ? snap.settings : {}
    lastProfileId = boundedString(settings.last_connected_profile)

    // Rebuilding the profiles array on every traffic tick would reset the
    // list view; only rebuild when the roster actually changed.
    var rawRoster = Array.isArray(snap.profiles) ? snap.profiles : []
    if (rawRoster.length > maxProfiles) return
    var roster = rawRoster.map(function(p) {
      p = p && typeof p === "object" && !Array.isArray(p) ? p : {}
      return {
        id: boundedString(p.id),
        name: boundedString(p.name),
        protocol: boundedString(p.protocol),
        address: boundedString(p.address)
      }
    })
    var key = ""
    for (var i = 0; i < roster.length; i++)
      key += roster[i].id + "|" + roster[i].name + "|" + roster[i].address + ";"
    var lat = snap.profile_latencies && typeof snap.profile_latencies === "object"
      && !Array.isArray(snap.profile_latencies) ? snap.profile_latencies : {}
    var testing = Array.isArray(snap.testing_profiles) ? snap.testing_profiles : []
    if (testing.length > maxProfiles) return
    var testingSet = ({})
    for (var k = 0; k < testing.length; k++) {
      var testingId = boundedString(testing[k])
      if (testingId !== "") testingSet["$" + testingId] = true
    }
    for (var j = 0; j < roster.length; j++) {
      var rid = String(roster[j].id)
      var ownsLatency = Object.prototype.hasOwnProperty.call(lat, rid)
      var validLatency = lat[rid] === null
        || (typeof lat[rid] === "number" && isFinite(lat[rid]))
      key += ownsLatency && validLatency
        ? (lat[rid] === null ? "n" : lat[rid]) : "-"
      key += testingSet["$" + rid] === true ? "t" : ""
      key += ";"
    }
    if (key !== _profilesKey) {
      _profilesKey = key
      profiles = roster.map(function(p) {
        var pid = p.id
        var hasLatency = Object.prototype.hasOwnProperty.call(lat, pid)
          && (lat[pid] === null
              || (typeof lat[pid] === "number" && isFinite(lat[pid])))
        return {
          id: pid,
          name: p.name,
          protocol: p.protocol,
          latencyMs: hasLatency ? lat[pid] : undefined,
          testing: testingSet["$" + pid] === true
        }
      })
    }

    var gr = settings.geo_routing && typeof settings.geo_routing === "object"
      && !Array.isArray(settings.geo_routing) ? settings.geo_routing : {}
    var currentRegion = boundedString(gr.current_region)
    var selectedModes = gr.selected_region_modes
      && typeof gr.selected_region_modes === "object"
      && !Array.isArray(gr.selected_region_modes) ? gr.selected_region_modes : null
    geoRegion = currentRegion
    routingMode = currentRegion !== "" && selectedModes
      ? boundedString(selectedModes[currentRegion] || "global")
      : "global"

    killSwitch = settings.kill_switch === true
    autoConnect = settings.auto_connect === true

    var t = snap.traffic && typeof snap.traffic === "object"
      && !Array.isArray(snap.traffic) ? snap.traffic : {}
    traffic = {
      up: typeof t.up_rate_bps === "number" && isFinite(t.up_rate_bps) ? t.up_rate_bps : 0,
      down: typeof t.down_rate_bps === "number" && isFinite(t.down_rate_bps) ? t.down_rate_bps : 0,
      upTotal: typeof t.up_total === "number" && isFinite(t.up_total) ? t.up_total : 0,
      downTotal: typeof t.down_total === "number" && isFinite(t.down_total) ? t.down_total : 0,
      conns: typeof t.conn_count === "number" && isFinite(t.conn_count) ? t.conn_count : 0
    }
  }
}
