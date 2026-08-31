import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

pragma ComponentBehavior: Bound

// kvn-tui bar widget.
//
// Icon states: dim shield = disconnected, full-color shield = connected,
// pulsing = connecting, urgent = last error.
//
// Left click: open the control panel (profiles + settings).
// Right click: quick toggle VPN (last profile) / disconnect.
// Middle click: open the full TUI.
BarWidget {
  id: root
  moduleName: "yarikov.omakvn"

  KvnService {
    id: kvn
    onDaemonUpChanged: if (!daemonUp) root.close()
  }

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property bool popoutSwitchClosing: false
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }
  function toggle() { popupOpen = !popupOpen }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root, direction)
    return false
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int rowHorizontalPadding: Style.space(10)
  readonly property int rowContentSpacing: Style.space(8)

  // All keyboard-selectable panel rows in order: hero toggle, profiles,
  // settings, then the footer button.
  readonly property int profileCount: kvn.profiles.length
  readonly property int rowVpnToggle: 0
  readonly property int rowProfileStart: 1
  readonly property int rowRouting: rowProfileStart + profileCount
  readonly property int rowRegion: rowRouting + 1
  readonly property int rowKillSwitch: rowRegion + 1
  readonly property int rowAutoConnect: rowKillSwitch + 1
  readonly property int rowTui: rowAutoConnect + 1
  readonly property int rowCount: rowTui + 1
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool gPending: false

  function activeProfile() {
    for (var i = 0; i < kvn.profiles.length; i++)
      if (kvn.profiles[i].id === kvn.activeProfileId) return kvn.profiles[i]
    return null
  }

  function pendingProfile() {
    for (var i = 0; i < kvn.profiles.length; i++)
      if (kvn.profiles[i].id === kvn.pendingProfileId) return kvn.profiles[i]
    return null
  }

  function lastProfile() {
    for (var i = 0; i < kvn.profiles.length; i++)
      if (kvn.profiles[i].id === kvn.lastProfileId) return kvn.profiles[i]
    return null
  }

  function heroProfile() {
    return pendingProfile() || activeProfile() || lastProfile()
      || (kvn.profiles.length > 0 ? kvn.profiles[0] : null)
  }

  function startDaemon() {
    if (!daemonStarter.running) daemonStarter.running = true
  }

  Process {
    id: daemonStarter
    command: ["systemctl", "--user", "start", "kvn-tui.service"]
    onExited: kvn.reconnectSocket()
  }

  function openTui() {
    var command = "omarchy-launch-or-focus-tui --app-id=org.omarchy.kvn-tui kvn-tui"
    if (root.bar) root.bar.run(command)
    else Quickshell.execDetached([
      "omarchy-launch-or-focus-tui",
      "--app-id=org.omarchy.kvn-tui",
      "kvn-tui"
    ])
    root.close()
  }

  function toggleVpn() {
    if (!kvn.daemonUp) {
      startDaemon()
      return
    }
    if (kvn.connected) {
      kvn.disconnectVpn()
    } else {
      var profile = lastProfile() || (kvn.profiles.length > 0 ? kvn.profiles[0] : null)
      if (profile) kvn.connectProfile(profile.id)
      else root.toggle()
    }
  }

  // Geo region cycle order mirrors GeoRegion::ALL in the Rust model.
  readonly property var regionCycle: ["ru", "cn", "ir", "global"]

  function availableModes(region) {
    if (region !== "" && region !== "global")
      return ["global", "bypass_" + region, "only_" + region]
    return ["global"]
  }

  function modeLabel(mode) {
    if (mode === "global") return "Global"
    var parts = mode.split("_")
    var code = { "ru": "RU", "cn": "CN", "ir": "IR", "global": "Global" }[parts[1]] || parts[1].toUpperCase()
    return (parts[0] === "bypass" ? "Bypass " : "Only ") + code
  }

  function regionLabel(region) {
    if (region === "") return "Not set"
    return { "ru": "RU", "cn": "CN", "ir": "IR", "global": "Global" }[region] || region.toUpperCase()
  }

  function cycleMode(forward) {
    var modes = availableModes(kvn.geoRegion)
    var idx = modes.indexOf(kvn.routingMode)
    if (idx === -1) idx = 0
    var next = modes[(idx + (forward ? 1 : modes.length - 1)) % modes.length]
    if (next !== kvn.routingMode) kvn.setRoutingMode(next)
  }

  function cycleRegion(forward) {
    var idx = regionCycle.indexOf(kvn.geoRegion)
    if (idx === -1) idx = regionCycle.length - 1
    var next = regionCycle[(idx + (forward ? 1 : regionCycle.length - 1)) % regionCycle.length]
    if (next !== kvn.geoRegion) kvn.setGeoRegion(next)
  }

  function formatBytes(bytes) {
    var n = Number(bytes)
    if (!isFinite(n) || n < 0) n = 0
    if (n < 1024) return Math.round(n) + " B"
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB"
    return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB"
  }

  function formatRate(bytesPerSec) {
    return formatBytes(bytesPerSec) + "/s"
  }

  onPopupOpenChanged: {
    gPending = false
    if (popupOpen) {
      cursorActive = false
      cursorIndex = rowVpnToggle
      Qt.callLater(function() { if (root.popupOpen) keyCatcher.forceActiveFocus() })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: kvn.daemonUp && kvn.connected ? "󰦝" : "󰦜"
    fontFamily: root.fontFamily
    tooltipText: {
      if (!kvn.daemonUp) return "kvn-tui — daemon not running (click to start)"
      if (kvn.connected) {
        var p = root.activeProfile()
        return "kvn-tui — connected to " + (p ? p.name : "profile")
      }
      if (kvn.busy) return "kvn-tui — connecting…"
      return "kvn-tui — disconnected"
    }
    foreground: root.foreground
    activeColor: root.foreground
    useActiveColor: false
    active: kvn.connected
    dimmed: !kvn.connected && !kvn.busy
    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        root.toggle()
      } else if (b === Qt.MiddleButton) {
        root.openTui()
      } else {
        root.toggleVpn()
      }
    }

    // Connecting: gentle opacity pulse.
    opacity: 1
    SequentialAnimation on opacity {
      running: kvn.busy
      loops: Animation.Infinite
      NumberAnimation { to: 0.35; duration: 550; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutQuad }
      onRunningChanged: if (!running) button.opacity = 1
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(380))
    contentHeight: fittedContentHeight(mainColumn.implicitHeight)

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      spacing: Style.space(12)

      // --- daemon offline ---
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)
        visible: !kvn.daemonUp

        Text {
          Layout.fillWidth: true
          text: "The kvn-tui daemon is not running. Start it to control the VPN from the bar."
          color: root.dim
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Button {
          Layout.fillWidth: true
          text: "Start daemon"
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.heading
          bordered: true
          onClicked: root.startDaemon()
        }
      }

      // --- main panel ---
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.space(12)
        visible: kvn.daemonUp

        // Hero: VPN icon, current/last profile and connection toggle. Mirrors
        // the Omarchy network panel's Wi-Fi header.
        Item {
          Layout.fillWidth: true
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, vpnSwitch.implicitHeight)

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: kvn.daemonUp && kvn.connected ? "󰦝" : "󰦜"
            color: kvn.statusIsError ? root.urgent : (kvn.connected ? root.foreground : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          ToggleSwitch {
            id: vpnSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: kvn.connected
            busy: kvn.busy
            enabled: kvn.connected || root.profileCount > 0
            opacity: enabled ? 1 : 0.4
            hasCursor: root.cursorActive && root.cursorIndex === root.rowVpnToggle
            foreground: root.foreground
            accent: Color.accent
            onHovered: function(isHovered) {
              if (isHovered) {
                root.cursorActive = true
                root.cursorIndex = root.rowVpnToggle
              }
            }
            onToggled: root.toggleVpn()

            PanelToolTip {
              visible: vpnSwitch.containsMouse
              text: kvn.connected ? "Disconnect VPN" : "Connect VPN"
              fontFamily: root.fontFamily
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: vpnSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: {
                var profile = root.heroProfile()
                return profile ? profile.name : "No profiles"
              }
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: kvn.busy ? "CONNECTING…" : (kvn.connected ? "CONNECTED" : "DISCONNECTED")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }
        }

        // Connection details grid — same shape as the Omarchy network panel.
        GridLayout {
          Layout.fillWidth: true
          columns: 4
          columnSpacing: Style.space(20)
          rowSpacing: Style.spacing.labelGap

          InfoLabel { text: "Receiving" }
          DetailValue { text: root.formatRate(kvn.connected ? kvn.traffic.down : 0) }
          InfoLabel { text: "Sending" }
          DetailValue { text: root.formatRate(kvn.connected ? kvn.traffic.up : 0) }

          InfoLabel { text: "Downloaded" }
          DetailValue { text: root.formatBytes(kvn.connected ? kvn.traffic.downTotal : 0) }
          InfoLabel { text: "Uploaded" }
          DetailValue { text: root.formatBytes(kvn.connected ? kvn.traffic.upTotal : 0) }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "PROFILES"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // profile list
        ListView {
          id: profileList
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, Style.space(190))
          Layout.maximumHeight: Style.space(190)
          implicitHeight: Math.min(contentHeight, Style.space(190))
          visible: root.profileCount > 0
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          spacing: Style.space(4)
          model: kvn.profiles

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: CursorSurface {
            id: profileRow
            required property int index
            required property var modelData
            readonly property bool isRequested: modelData.id === kvn.pendingProfileId
            readonly property bool isPending: kvn.busy && isRequested
            readonly property bool isActive: kvn.pendingProfileId !== ""
              ? isRequested : modelData.id === kvn.activeProfileId
            readonly property int logicalIndex: root.rowProfileStart + index
            readonly property bool isCursor: root.cursorActive && root.cursorIndex === logicalIndex
            width: profileList.width
            implicitHeight: profileContent.implicitHeight + Style.spacing.rowPaddingX
            height: implicitHeight
            hasCursor: isCursor
            current: isActive
            foreground: root.foreground
            accent: Color.accent
            fill: Style.hoverFillFor(root.foreground, Color.accent)
            currentFill: Style.selectedFillFor(root.foreground, Color.accent)

            MouseArea {
              id: rowHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) {
                root.cursorActive = true
                root.cursorIndex = profileRow.logicalIndex
              }
              onClicked: {
                if (!profileRow.isActive) kvn.connectProfile(profileRow.modelData.id)
              }
            }

            RowLayout {
              id: profileContent
              anchors.fill: parent
              anchors.leftMargin: root.rowHorizontalPadding
              anchors.rightMargin: root.rowHorizontalPadding
              spacing: root.rowContentSpacing

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(1)

                Text {
                  Layout.fillWidth: true
                  text: profileRow.modelData.name
                  color: root.foreground
                  elide: Text.ElideMiddle
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  Layout.fillWidth: true
                  visible: profileRow.isActive
                  text: profileRow.isPending ? "Connecting…"
                    : profileRow.isRequested ? "Disconnected" : "Connected"
                  color: root.foreground
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                text: profileRow.modelData.protocol
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                visible: text !== ""
              }

              Text {
                text: profileRow.modelData.testing ? "…"
                  : profileRow.modelData.latencyMs === undefined ? ""
                  : profileRow.modelData.latencyMs === null ? "unreachable"
                  : profileRow.modelData.latencyMs + " ms"
                color: profileRow.modelData.latencyMs === null && !profileRow.modelData.testing ? Color.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            visible: root.profileCount === 0
            text: "No profiles. Add them with `kvn-tui` (p to paste a link)."
            color: root.dim
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "SETTINGS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(4)

          PanelRow {
            Layout.fillWidth: true
            glyph: ""
            label: "Routing"
            valueText: "‹ " + root.modeLabel(kvn.routingMode) + " ›"
            rowIndex: root.rowRouting
            onActivated: root.cycleMode(true)
            onStep: function(forward) { root.cycleMode(forward) }
          }

          PanelRow {
            Layout.fillWidth: true
            glyph: ""
            label: "Region"
            valueText: "‹ " + root.regionLabel(kvn.geoRegion) + " ›"
            rowIndex: root.rowRegion
            onActivated: root.cycleRegion(true)
            onStep: function(forward) { root.cycleRegion(forward) }
          }

          PanelRow {
            Layout.fillWidth: true
            glyph: ""
            label: "Kill switch"
            showToggle: true
            toggleChecked: kvn.killSwitch
            toggleBusy: ksPending
            rowIndex: root.rowKillSwitch
            onActivated: {
              ksRequested = !kvn.killSwitch
              kvn.setKillSwitch(ksRequested)
              ksTimeout.restart()
            }
          }

          PanelRow {
            Layout.fillWidth: true
            glyph: ""
            label: "Auto-connect"
            showToggle: true
            toggleChecked: kvn.autoConnect
            rowIndex: root.rowAutoConnect
            onActivated: kvn.setAutoConnect(!kvn.autoConnect)
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        // Footer: open the full TUI
        Button {
          Layout.fillWidth: true
          text: "Open TUI"
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.body
          bordered: true
          hasCursor: root.cursorActive && root.cursorIndex === root.rowTui
          onHovered: function(isHovered) {
            if (isHovered) {
              root.cursorActive = true
              root.cursorIndex = root.rowTui
            }
          }
          onClicked: root.openTui()

          // Hidden focus catcher for keyboard navigation. Keeping it inside
          // the button prevents it from adding another ColumnLayout gap.
          Item {
            id: keyCatcher
            width: 0
            height: 0
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              var direction = (event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1
              root.switchPanel(direction)
              event.accepted = true
              return
            }
            if (!kvn.daemonUp) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.startDaemon()
                event.accepted = true
              }
              return
            }
            var isLowerG = event.key === Qt.Key_G
              && !(event.modifiers & Qt.ShiftModifier)
            if (!isLowerG && root.gPending) {
              root.gPending = false
            }
            if (event.key === Qt.Key_K && (event.modifiers & Qt.ShiftModifier)) {
              root.activateRow(root.rowKillSwitch)
              event.accepted = true
            } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
              root.moveCursor(1)
              event.accepted = true
            } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
              root.moveCursor(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
              root.activateRow(root.cursorIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
              root.stepRow(root.cursorIndex, true)
              event.accepted = true
            } else if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
              root.stepRow(root.cursorIndex, false)
              event.accepted = true
            } else if (event.text === "G") {
              root.cursorActive = true
              root.cursorIndex = root.rowCount - 1
              root.syncCursorView()
              event.accepted = true
            } else if (isLowerG) {
              if (root.gPending) {
                root.gPending = false
                root.cursorActive = true
                root.cursorIndex = 0
                root.syncCursorView()
              } else {
                root.gPending = true
              }
              event.accepted = true
            } else if (event.text === "s") {
              if (kvn.connected) kvn.disconnectVpn()
              event.accepted = true
            } else if (event.text === "r") {
              if (kvn.connected) kvn.reconnect()
              event.accepted = true
            } else if (event.text === "a") {
              kvn.setAutoConnect(!kvn.autoConnect)
              event.accepted = true
            } else if (event.text === "t") {
              root.openTui()
              event.accepted = true
            }
            }
          }
        }
      }
    }
  }

  // Kill-switch toggle feedback: `busy` until the daemon confirms the new
  // state (or the request times out — a failed toggle never flips).
  property bool ksRequested: false
  property bool ksPending: kvn.killSwitch !== ksRequested && ksTimeout.running
  Timer {
    id: ksTimeout
    interval: 6000
    onTriggered: root.ksRequested = kvn.killSwitch
  }

  function moveCursor(delta) {
    if (rowCount === 0) return
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = delta < 0 ? rowCount - 1 : 0
    } else {
      cursorIndex = (cursorIndex + delta + rowCount) % rowCount
    }
    syncCursorView()
  }

  function syncCursorView() {
    if (cursorIndex >= rowProfileStart && cursorIndex < rowRouting)
      profileList.positionViewAtIndex(cursorIndex - rowProfileStart, ListView.Contain)
  }

  function activateRow(index) {
    if (index === rowVpnToggle) {
      if (!kvn.busy && (kvn.connected || profileCount > 0)) toggleVpn()
    } else if (index >= rowProfileStart && index < rowRouting) {
      var profileIndex = index - rowProfileStart
      if (kvn.profiles[profileIndex] && kvn.profiles[profileIndex].id !== kvn.activeProfileId)
        kvn.connectProfile(kvn.profiles[profileIndex].id)
    } else if (index === rowRouting) {
      cycleMode(true)
    } else if (index === rowRegion) {
      cycleRegion(true)
    } else if (index === rowKillSwitch) {
      ksRequested = !kvn.killSwitch
      kvn.setKillSwitch(ksRequested)
      ksTimeout.restart()
    } else if (index === rowAutoConnect) {
      kvn.setAutoConnect(!kvn.autoConnect)
    } else if (index === rowTui) {
      openTui()
    }
  }

  function stepRow(index, forward) {
    if (index === rowRouting) cycleMode(forward)
    else if (index === rowRegion) cycleRegion(forward)
  }

  // Dim label / right-aligned value pair, styled like the Omarchy network
  // panel's connection-details grid.
  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component DetailValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    Layout.fillWidth: true
    horizontalAlignment: Text.AlignRight
  }

  // Selectable settings row: cycler or toggle.
  component PanelRow: CursorSurface {
    id: row
    signal activated()
    signal step(bool forward)
    property string glyph: ""
    property string label: ""
    property string valueText: ""
    property bool rowEnabled: true
    property bool showToggle: false
    property bool toggleChecked: false
    property bool toggleBusy: false
    property int rowIndex: -1
    readonly property bool isCursor: root.cursorActive && root.cursorIndex === rowIndex

    Layout.fillWidth: true
    implicitHeight: panelRowContent.implicitHeight + Style.spacing.rowPaddingX
    Layout.preferredHeight: implicitHeight
    hasCursor: isCursor
    foreground: root.foreground
    accent: Color.accent
    fill: Style.hoverFillFor(root.foreground, Color.accent)
    opacity: rowEnabled ? 1 : 0.4

    MouseArea {
      id: rowArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: row.rowEnabled
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.cursorIndex = row.rowIndex
      }
      onClicked: row.activated()
    }

    RowLayout {
      id: panelRowContent
      anchors.fill: parent
      anchors.leftMargin: root.rowHorizontalPadding
      anchors.rightMargin: root.rowHorizontalPadding
      spacing: root.rowContentSpacing

      Text {
        text: row.glyph
        visible: row.glyph !== ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        Layout.fillWidth: true
        text: row.label
        color: root.foreground
        elide: Text.ElideMiddle
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: !row.showToggle && row.valueText !== ""
        text: row.valueText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      ToggleSwitch {
        visible: row.showToggle
        checked: row.toggleChecked
        busy: row.toggleBusy
        interactive: false
        foreground: root.foreground
        accent: Color.accent
        onToggled: row.activated()
      }
    }
  }
}
