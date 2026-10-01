import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.antoniowav.elpris"
  ipcTarget: "io.github.antoniowav.elpris"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
  }

  function close() {
    root.editingSettings = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // In-panel settings editor, persisted through the shell's inline entry
  // update — the same write path `omarchy bar set` uses.
  property bool editingSettings: false
  property string editZone: "SE3"
  property string editUnit: "kr"
  property int editDecimals: 0

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function startEditingSettings() {
    editZone = root.zone
    editUnit = root.ore ? "öre" : "kr"
    editDecimals = root.decimals
    editingSettings = true
  }

  function cancelEditingSettings() {
    editingSettings = false
  }

  function saveSettings() {
    persistSettings({ zone: editZone, unit: editUnit, decimals: editDecimals })
    editingSettings = false
  }

  // Raw quarter-hour entries per day. Kept on failure so stale prices stay
  // visible; tomorrow is empty until Nord Pool publishes around 13:00.
  property var todayEntries: []
  property var tomorrowEntries: []
  property int todayRetries: 0
  property double nowMs: Date.now()

  readonly property string zone: Model.normalizedZone(setting("zone", "SE3"))
  readonly property bool ore: Model.useOre(setting("unit", "kr"))
  readonly property int decimals: Model.normalizedDecimals(setting("decimals", 0))

  onZoneChanged: {
    todayEntries = []
    tomorrowEntries = []
    Qt.callLater(refresh)
  }

  readonly property var current: Model.currentEntry(todayEntries, nowMs)
  readonly property var todayStats: Model.stats(todayEntries)
  readonly property var todayHours: Model.hourly(todayEntries)
  readonly property var tomorrowHours: Model.hourly(tomorrowEntries)
  readonly property var tomorrowStats: Model.stats(tomorrowEntries)
  readonly property int currentLevel: current && todayStats ? Model.levelFor(current.sek, todayStats) : 1

  // Shared scale across both charts so today and tomorrow are comparable.
  readonly property double chartMax: Math.max(todayStats ? todayStats.max : 0, tomorrowStats ? tomorrowStats.max : 0, 0.0001)

  readonly property string barLabel: current ? ("⌁ " + Model.fmtShort(current.sek, ore, decimals)) : ""

  readonly property color cheapColor: "#69b076"
  readonly property color expensiveColor: "#d0764f"

  function levelColor(level) {
    if (level === 0) return cheapColor
    if (level === 2) return expensiveColor
    return root.bar ? root.bar.foreground : Color.foreground
  }

  function fmt(sek) {
    return Model.fmt(sek, ore, decimals)
  }

  // Static curl pipeline: the URL enters via Process.environment and head -c
  // caps how much of a hostile response StdioCollector will buffer.
  readonly property string curlGet:
    "curl -fsS --max-time 10 --proto =https" +
    " --variable %REQ_URL --expand-url \"{{REQ_URL}}\"" +
    " | head -c 524288"

  function refresh() {
    todayRetries = 0
    nowMs = Date.now()
    if (!todayProc.running) {
      todayProc.environment = { REQ_URL: Model.apiUrl(zone, new Date()) }
      todayProc.command = ["bash", "-c", curlGet]
      todayProc.running = true
    }
    if (!tomorrowProc.running) {
      tomorrowProc.environment = { REQ_URL: Model.apiUrl(zone, new Date(Date.now() + 86400000)) }
      tomorrowProc.command = ["bash", "-c", curlGet]
      tomorrowProc.running = true
    }
  }

  function scheduleTodayRetry() {
    if (todayRetries >= 3) return
    todayRetries++
    retryTimer.restart()
  }

  Process {
    id: todayProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseDay(text)
        if (parsed.length > 0) {
          root.todayEntries = parsed
          root.todayRetries = 0
        } else {
          root.scheduleTodayRetry()
        }
      }
    }
  }

  // Tomorrow 404s until publication; that's normal, never retried here. The
  // half-hour refresh timer picks it up once it exists.
  Process {
    id: tomorrowProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.tomorrowEntries = Model.parseDay(text)
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 2500
    onTriggered: if (!todayProc.running) todayProc.running = true
  }

  // Prices are static once published; refetching half-hourly is only for
  // picking up tomorrow's publication and the midnight rollover.
  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // The active quarter changes without any fetch: track the clock.
  Timer {
    interval: 30 * 1000
    running: true
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      // Past midnight yesterday's "today" is stale: roll over.
      if (root.todayEntries.length > 0 && root.todayEntries[root.todayEntries.length - 1].endMs < root.nowMs)
        root.refresh()
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  component PriceChart: Item {
    id: chart
    property var hours: []
    property var dayStats: null
    property bool markNow: false

    property int hoveredIndex: -1
    readonly property var hovered: hoveredIndex >= 0 && hoveredIndex < hours.length ? hours[hoveredIndex] : null

    width: parent.width
    height: Style.space(96)

    Row {
      id: barsRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(18)
      spacing: Style.space(2)

      Repeater {
        model: chart.hours

        Item {
          required property var modelData
          required property int index
          width: (barsRow.width - (chart.hours.length - 1) * barsRow.spacing) / Math.max(1, chart.hours.length)
          height: barsRow.parent.height - Style.space(18)

          readonly property bool isNow: chart.markNow && root.nowMs >= modelData.startMs && root.nowMs < modelData.endMs
          readonly property int level: Model.levelFor(modelData.sek, chart.dayStats)

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(Style.space(3), parent.height * (modelData.sek / root.chartMax))
            radius: Style.space(1)
            color: root.levelColor(parent.level)
            opacity: parent.isNow || chart.hoveredIndex === parent.index ? 1.0 : (parent.level === 1 ? 0.45 : 0.8)

            Rectangle {
              visible: parent.parent.isNow
              anchors.top: parent.top
              anchors.topMargin: -Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(4)
              height: Style.space(4)
              radius: Style.space(2)
              color: Color.accent
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: chart.hoveredIndex = index
            onExited: if (chart.hoveredIndex === index) chart.hoveredIndex = -1
          }
        }
      }
    }

    Text {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      text: chart.hovered
        ? (String(chart.hovered.hour).length < 2 ? "0" : "") + chart.hovered.hour + ":00  " + root.fmt(chart.hovered.sek)
        : "00                    06                    12                    18                    23"
      color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(priceColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: priceColumn
        width: parent.width
        spacing: Style.space(14)

        // ---- Hero: current price + zone, day stats on the right.
        Item {
          width: parent.width
          height: Math.max(heroLeft.height, heroRight.height)

          Column {
            id: heroLeft
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.current ? root.fmt(root.current.sek) : "—"
              color: root.levelColor(root.currentLevel)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: 36
              font.bold: true
            }
            Text {
              text: root.zone + " · SPOT / kWh"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }
          }

          Rectangle {
            width: Style.space(24)
            height: Style.space(24)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.top: parent.top
            radius: Math.min(4, Style.cornerRadius)
            color: gearArea.containsMouse ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent) : "transparent"
            z: 2

            Text {
              anchors.centerIn: parent
              text: root.editingSettings ? "✕" : "\uf013"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: gearArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.editingSettings ? root.cancelEditingSettings() : root.startEditingSettings()
            }
          }

          Row {
            id: heroRight
            visible: !root.editingSettings
            anchors.right: parent.right
            anchors.rightMargin: Style.space(20)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(24)

            Column {
              spacing: Style.space(5)
              Text {
                text: "LOW"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.todayStats ? root.fmt(root.todayStats.min) : "—"
                color: root.cheapColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Column {
              spacing: Style.space(5)
              Text {
                text: "AVG"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.todayStats ? root.fmt(root.todayStats.avg) : "—"
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Column {
              spacing: Style.space(5)
              Text {
                text: "HIGH"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.todayStats ? root.fmt(root.todayStats.max) : "—"
                color: root.expensiveColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        // ---- Settings editor: zone and unit pills.
        Column {
          visible: root.editingSettings
          width: parent.width - Style.space(32)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "PRICE ZONE"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: ["SE1", "SE2", "SE3", "SE4"]

                Rectangle {
                  required property var modelData
                  readonly property bool active: root.editZone === modelData
                  width: (parent.width - 3 * Style.space(8)) / 4
                  height: Style.space(26)
                  radius: Style.cornerRadius
                  color: active ? Color.accent : "transparent"
                  border.width: active ? 0 : 1
                  border.color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.8)

                  Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: parent.active ? Color.background : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.3)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.editZone = parent.modelData
                  }
                }
              }
            }

            Text {
              text: "SE1 Luleå · SE2 Sundsvall · SE3 Stockholm/Göteborg · SE4 Malmö"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.7)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "UNIT"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: [{ key: "kr", title: "KR / KWH" }, { key: "öre", title: "ÖRE / KWH" }]

                Rectangle {
                  required property var modelData
                  readonly property bool active: root.editUnit === modelData.key
                  width: (parent.width - Style.space(8)) / 2
                  height: Style.space(26)
                  radius: Style.cornerRadius
                  color: active ? Color.accent : "transparent"
                  border.width: active ? 0 : 1
                  border.color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.8)

                  Text {
                    anchors.centerIn: parent
                    text: parent.modelData.title
                    color: parent.active ? Color.background : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.3)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.editUnit = parent.modelData.key
                  }
                }
              }
            }
          }

          // Only meaningful in öre: kr already carries two decimals.
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.editUnit !== "kr"

            Text {
              text: "ÖRE DECIMALS"
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: [{ value: 0, title: "14" }, { value: 1, title: "14,1" }, { value: 2, title: "14,08" }]

                Rectangle {
                  required property var modelData
                  readonly property bool active: root.editDecimals === modelData.value
                  width: (parent.width - 2 * Style.space(8)) / 3
                  height: Style.space(26)
                  radius: Style.cornerRadius
                  color: active ? Color.accent : "transparent"
                  border.width: active ? 0 : 1
                  border.color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.8)

                  Text {
                    anchors.centerIn: parent
                    text: parent.modelData.title
                    color: parent.active ? Color.background : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.3)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.editDecimals = parent.modelData.value
                  }
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(28)
            radius: Style.cornerRadius
            color: saveArea.containsMouse ? Qt.darker(Color.accent, 1.15) : Color.accent

            Text {
              anchors.centerIn: parent
              text: "SAVE"
              color: Color.background
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: 1
            }

            MouseArea {
              id: saveArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.saveSettings()
            }
          }
        }

        Text {
          visible: !root.editingSettings && root.todayEntries.length === 0
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Fetching prices…"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        // ---- Today's chart.
        Column {
          visible: !root.editingSettings && root.todayHours.length > 0
          width: parent.width - Style.space(32)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Text {
            text: "TODAY"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          PriceChart {
            hours: root.todayHours
            dayStats: root.todayStats
            markNow: true
          }
        }

        // ---- Tomorrow, once Nord Pool has published (~13:00).
        Column {
          visible: !root.editingSettings && root.tomorrowHours.length > 0
          width: parent.width - Style.space(32)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Text {
            text: "TOMORROW"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          PriceChart {
            hours: root.tomorrowHours
            dayStats: root.tomorrowStats
          }
        }

        Text {
          visible: !root.editingSettings && root.todayHours.length > 0 && root.tomorrowHours.length === 0
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Tomorrow's prices are published around 13:00"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.italic: true
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Elpriser tillhandahålls av elprisetjustnu.se"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.8)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
