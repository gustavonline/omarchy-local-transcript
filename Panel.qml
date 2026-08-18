import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.gustavonline.local-meeting"
  ipcTarget: moduleName

  property bool configured: false
  property string meetingStatus: "idle"
  property string meetingTitle: "Local Meeting"
  property int elapsedSeconds: 0
  property int chunks: 0
  property var recentNotes: []
  property string statusMessage: ""
  property bool statusIsError: false
  property bool busy: false
  property bool setupMode: false
  property bool setupLoaded: false
  property bool downloadBusy: false
  property string downloadKind: ""
  property string selectedStt: "small"
  property string selectedSummary: "qwen3.5:2b"
  property string selectedLanguage: "auto"
  property bool selectedSaveAudio: false
  property bool selectedAutoSummary: true
  property bool selectedDetection: true
  property var selectedApps: ["zoom", "teams", "slack", "meet", "discord", "buzz", "webex", "jitsi", "browser"]
  property bool sttReady: false
  property bool summaryReady: false
  property var requirements: ({})

  readonly property var sttChoices: ["base", "small", "large-v3-turbo"]
  readonly property var summaryChoices: ["disabled", "gemma3:1b", "qwen3.5:2b", "qwen3.5:4b"]
  readonly property var languageChoices: ["auto", "da", "en"]
  readonly property string helperPath: Qt.resolvedUrl("local-meeting").toString().replace(/^file:\/\//, "")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function formatDuration(total) {
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var seconds = total % 60
    var result = (minutes < 10 && hours > 0 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    return hours > 0 ? hours + ":" + result : result
  }

  function cycle(values, current) {
    var index = values.indexOf(current)
    return values[(index + 1) % values.length]
  }

  function sttLabel(value) {
    if (value === "base") return "Base · 142 MB"
    if (value === "large-v3-turbo") return "Large Turbo · 1.6 GB"
    return "Small · 466 MB · recommended"
  }

  function summaryLabel(value) {
    if (value === "disabled") return "No AI summary"
    if (value === "gemma3:1b") return "Gemma 3 1B · 815 MB"
    if (value === "qwen3.5:4b") return "Qwen 3.5 4B · 3.4 GB"
    return "Qwen 3.5 2B · 2.7 GB · recommended"
  }

  function languageLabel(value) {
    if (value === "da") return "Danish"
    if (value === "en") return "English"
    return "Automatic language detection"
  }

  function appEnabled(value) {
    return selectedApps.indexOf(value) >= 0
  }

  function toggleApp(value) {
    var next = []
    var found = false
    for (var i = 0; i < selectedApps.length; i++) {
      if (selectedApps[i] === value) found = true
      else next.push(selectedApps[i])
    }
    if (!found) next.push(value)
    selectedApps = next
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function refreshSetup() {
    if (!setupProc.running) setupProc.running = true
  }

  function parseState(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      configured = Boolean(data.configured)
      meetingStatus = String(data.meeting_status || "idle")
      meetingTitle = String(data.title || "Local Meeting")
      elapsedSeconds = Number(data.elapsed_seconds || 0)
      chunks = Number(data.chunks || 0)
      recentNotes = Array.isArray(data.recent_notes) ? data.recent_notes : []
      if (data.audio_warning && statusMessage === "") {
        statusMessage = String(data.audio_warning)
        statusIsError = true
      }
      if (!configured) setupMode = true
    } catch (error) {
      statusMessage = "Could not read meeting state"
      statusIsError = true
    }
  }

  function parseSetup(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      var config = data.config || {}
      outputField.text = String(config.outputDirectory || "~/Documents/Meeting Notes")
      selectedStt = String(config.sttModel || "small")
      selectedSummary = String(config.summaryModel || "qwen3.5:2b")
      selectedLanguage = String(config.language || "auto")
      selectedSaveAudio = Boolean(config.saveAudio)
      selectedAutoSummary = Boolean(config.autoSummarize)
      selectedDetection = config.detectMeetings === undefined ? true : Boolean(config.detectMeetings)
      selectedApps = Array.isArray(config.detectionApps) ? config.detectionApps : root.selectedApps
      customAppsField.text = String(config.customMeetingApps || "")
      sttReady = Boolean(data.stt_ready)
      summaryReady = Boolean(data.summary_ready)
      requirements = data.requirements || {}
      setupLoaded = true
    } catch (error) {
      statusMessage = "Could not read local setup"
      statusIsError = true
    }
  }

  function runAction(action, args) {
    if (busy) return
    busy = true
    statusMessage = ""
    actionProc.action = action
    actionProc.command = [helperPath, action].concat(args || [])
    actionProc.running = true
  }

  function saveSetup() {
    var folder = outputField.text.trim()
    if (folder === "") {
      statusMessage = "Choose a meeting folder"
      statusIsError = true
      outputField.forceActiveFocus()
      return
    }
    runAction("configure", [
      folder,
      selectedStt,
      selectedSummary,
      selectedLanguage,
      selectedSaveAudio ? "true" : "false",
      selectedAutoSummary ? "true" : "false",
      selectedDetection ? "true" : "false",
      JSON.stringify(selectedApps),
      customAppsField.text.trim()
    ])
  }

  function downloadModel(kind) {
    if (downloadBusy) return
    downloadBusy = true
    downloadKind = kind
    statusMessage = kind === "stt" ? "Downloading speech model…" : "Downloading local summary model…"
    statusIsError = false
    downloadProc.command = kind === "stt"
      ? [helperPath, "download-stt", selectedStt]
      : [helperPath, "download-summary", selectedSummary]
    downloadProc.running = true
  }

  function saveNote() {
    var note = noteField.text.trim()
    if (note === "") {
      statusMessage = "Write a note first"
      statusIsError = true
      noteField.forceActiveFocus()
      return
    }
    runAction("add-note", [authorField.text.trim(), note])
  }

  onOpenedChanged: if (opened) {
    refresh()
    if (setupMode || !configured) refreshSetup()
    Qt.callLater(function() {
      if (setupMode || !configured) outputField.forceActiveFocus()
      else if (meetingStatus === "idle") titleField.forceActiveFocus()
      else noteField.forceActiveFocus()
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Timer {
    interval: 2000
    repeat: true
    running: root.opened || root.meetingStatus !== "idle"
    onTriggered: root.refresh()
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.configured
    triggeredOnStart: false
    onTriggered: if (!detectProc.running) detectProc.running = true
  }

  Process {
    id: stateProc
    command: [root.helperPath, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseState(text)
    }
  }

  Process {
    id: detectProc
    command: [root.helperPath, "detect"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: setupProc
    command: [root.helperPath, "setup-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSetup(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") {
        root.statusMessage = String(text).trim()
        root.statusIsError = true
      }
    }
  }

  Process {
    id: actionProc
    property string action: ""
    stdout: StdioCollector { id: actionOutput; waitForEnd: true }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) {
        if (action === "start") root.statusMessage = "Recording started locally"
        else if (action === "pause") root.statusMessage = "Recording paused"
        else if (action === "resume") root.statusMessage = "Recording resumed"
        else if (action === "stop") root.statusMessage = "Meeting saved as Markdown"
        else if (action === "add-note") {
          root.statusMessage = "Note saved"
          noteField.text = ""
          noteField.forceActiveFocus()
        } else if (action === "configure") {
          root.statusMessage = "Local setup saved"
          root.configured = true
          root.setupMode = false
        }
        root.statusIsError = false
        root.refresh()
        if (action === "configure") root.refreshSetup()
      } else {
        root.statusMessage = String(actionError.text || "The action failed").trim()
        root.statusIsError = true
      }
    }
  }

  Process {
    id: downloadProc
    stdout: StdioCollector { id: downloadOutput; waitForEnd: true }
    stderr: StdioCollector { id: downloadError; waitForEnd: true }
    onExited: function(exitCode) {
      root.downloadBusy = false
      if (exitCode === 0) {
        root.statusMessage = root.downloadKind === "stt" ? "Speech model is ready" : "Summary model is ready"
        root.statusIsError = false
        root.refreshSetup()
      } else {
        root.statusMessage = String(downloadError.text || "Model download failed").trim()
        root.statusIsError = true
      }
      root.downloadKind = ""
    }
  }

  Process {
    id: openProc
    command: [root.helperPath, "open"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: openError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.statusMessage = String(openError.text || "Could not open meeting files").trim()
        root.statusIsError = true
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.meetingStatus === "recording" ? "󰑊" : root.meetingStatus === "paused" ? "󰏤" : "󰍬"
    foreground: root.meetingStatus === "recording" ? root.urgent : root.foreground
    active: root.meetingStatus !== "idle"
    tooltipText: root.meetingStatus === "recording"
      ? "Recording · " + root.formatDuration(root.elapsedSeconds)
      : root.meetingStatus === "paused" ? "Meeting paused" : "Local Meeting"
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (!openProc.running) openProc.running = true
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.setupMode ? outputField : (root.meetingStatus === "idle" ? titleField : noteField)
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: outputField.activeFocus || customAppsField.activeFocus || titleField.activeFocus || authorField.activeFocus || noteField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: content
        anchors.fill: parent
        implicitHeight: Math.min(contentColumn.implicitHeight, Style.space(760))
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: contentColumn
          width: content.width
          spacing: Style.space(12)

        Item {
          width: parent.width
          implicitHeight: Math.max(headerText.implicitHeight, setupButton.implicitHeight)

          Column {
            id: headerText
            anchors.left: parent.left
            anchors.right: setupButton.left
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.setupMode ? "Local setup" : root.meetingTitle
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              text: root.setupMode ? "NO CLOUD · MODELS RUN ON THIS COMPUTER"
                : root.meetingStatus === "idle" ? "READY"
                : root.meetingStatus.toUpperCase() + " · " + root.formatDuration(root.elapsedSeconds) + " · " + root.chunks + " CHUNKS"
              color: root.meetingStatus === "recording" && !root.setupMode ? root.urgent : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: Style.space(0.5)
            }
          }

          Button {
            id: setupButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.setupMode ? "Done" : "Setup"
            iconText: root.setupMode ? "✓" : "󰒓"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            enabled: root.configured || !root.setupMode
            onClicked: {
              root.setupMode = !root.setupMode
              if (root.setupMode) root.refreshSetup()
              else root.refresh()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          visible: root.setupMode
          width: parent.width
          spacing: Style.space(9)

          PanelSectionHeader {
            text: "MEETING FOLDER"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: outputField
            width: parent.width
            placeholderText: "~/Documents/Meeting Notes"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
          }

          PanelSectionHeader {
            text: "SPEECH TO TEXT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing) * 0.64
              text: root.sttLabel(root.selectedStt)
              iconText: "󰍬"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              leftAlign: true
              onClicked: {
                root.selectedStt = root.cycle(root.sttChoices, root.selectedStt)
                root.sttReady = false
              }
            }

            Button {
              width: parent.width - parent.spacing - parent.children[0].width
              text: root.languageLabel(root.selectedLanguage)
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.selectedLanguage = root.cycle(root.languageChoices, root.selectedLanguage)
            }
          }

          Button {
            width: parent.width
            text: root.downloadBusy && root.downloadKind === "stt" ? "Downloading speech model…"
              : root.sttReady ? "Speech model installed" : "Download selected speech model"
            iconText: root.downloadBusy && root.downloadKind === "stt" ? "󰦖" : root.sttReady ? "✓" : "󰇚"
            iconSpinning: root.downloadBusy && root.downloadKind === "stt"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            enabled: !root.downloadBusy && !root.sttReady
            onClicked: root.downloadModel("stt")
          }

          PanelSectionHeader {
            text: "LOCAL AI SUMMARY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Button {
            width: parent.width
            text: root.summaryLabel(root.selectedSummary)
            iconText: "󰧑"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            leftAlign: true
            onClicked: {
              root.selectedSummary = root.cycle(root.summaryChoices, root.selectedSummary)
              root.selectedAutoSummary = root.selectedSummary !== "disabled"
              root.summaryReady = root.selectedSummary === "disabled"
            }
          }

          Button {
            visible: root.selectedSummary !== "disabled"
            width: parent.width
            text: root.downloadBusy && root.downloadKind === "summary" ? "Downloading summary model…"
              : root.summaryReady ? "Summary model installed" : "Download selected summary model"
            iconText: root.downloadBusy && root.downloadKind === "summary" ? "󰦖" : root.summaryReady ? "✓" : "󰇚"
            iconSpinning: root.downloadBusy && root.downloadKind === "summary"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            enabled: !root.downloadBusy && !root.summaryReady
            onClicked: root.downloadModel("summary")
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: root.selectedSaveAudio ? "Save audio: yes" : "Save audio: no"
              iconText: root.selectedSaveAudio ? "󰑊" : "󰕾"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              selected: root.selectedSaveAudio
              onClicked: root.selectedSaveAudio = !root.selectedSaveAudio
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: root.selectedAutoSummary ? "Auto summary: yes" : "Auto summary: no"
              iconText: root.selectedAutoSummary ? "󰄬" : "󰅖"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              selected: root.selectedAutoSummary
              enabled: root.selectedSummary !== "disabled"
              onClicked: root.selectedAutoSummary = !root.selectedAutoSummary
            }
          }

          Button {
            width: parent.width
            text: root.selectedDetection ? "Meeting detection: on" : "Meeting detection: off"
            iconText: root.selectedDetection ? "󰍬" : "󰍭"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            selected: root.selectedDetection
            onClicked: root.selectedDetection = !root.selectedDetection
          }

          Column {
            visible: root.selectedDetection
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "APPS THAT MAY TRIGGER A REMINDER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [{ id: "zoom", label: "Zoom" }, { id: "teams", label: "Teams" }, { id: "slack", label: "Slack" }]
                Button {
                  required property var modelData
                  width: (parent.width - parent.spacing * 2) / 3
                  text: String(modelData.label)
                  iconText: root.appEnabled(String(modelData.id)) ? "✓" : ""
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  bordered: true
                  selected: root.appEnabled(String(modelData.id))
                  onClicked: root.toggleApp(String(modelData.id))
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [{ id: "meet", label: "Google Meet" }, { id: "discord", label: "Discord" }, { id: "browser", label: "Other browser" }]
                Button {
                  required property var modelData
                  width: (parent.width - parent.spacing * 2) / 3
                  text: String(modelData.label)
                  iconText: root.appEnabled(String(modelData.id)) ? "✓" : ""
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  bordered: true
                  selected: root.appEnabled(String(modelData.id))
                  onClicked: root.toggleApp(String(modelData.id))
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [{ id: "buzz", label: "Buzz" }, { id: "webex", label: "Webex" }, { id: "jitsi", label: "Jitsi" }]
                Button {
                  required property var modelData
                  width: (parent.width - parent.spacing * 2) / 3
                  text: String(modelData.label)
                  iconText: root.appEnabled(String(modelData.id)) ? "✓" : ""
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  bordered: true
                  selected: root.appEnabled(String(modelData.id))
                  onClicked: root.toggleApp(String(modelData.id))
                }
              }
            }

            TextField {
              id: customAppsField
              width: parent.width
              placeholderText: "Extra app/process names, comma separated"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
            }

            Text {
              width: parent.width
              text: "Turn Discord off here if you use it while gaming. Custom names are matched only while that app is using the microphone."
              color: Qt.darker(root.foreground, 1.45)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Text {
            width: parent.width
            text: "Model downloads use the internet once. Audio, transcripts, notes and AI processing remain local afterwards."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Button {
            width: parent.width
            text: root.busy && actionProc.action === "configure" ? "Saving setup…" : "Save local setup"
            iconText: root.busy && actionProc.action === "configure" ? "󰦖" : "✓"
            iconSpinning: root.busy && actionProc.action === "configure"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            enabled: !root.busy && !root.downloadBusy
            onClicked: root.saveSetup()
          }
        }

        Column {
          visible: !root.setupMode && root.meetingStatus === "idle"
          width: parent.width
          spacing: Style.space(9)

          PanelSectionHeader {
            text: "NEW MEETING"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: titleField
            width: parent.width
            placeholderText: "Meeting title"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            Keys.onReturnPressed: root.runAction("start", [titleField.text.trim()])
          }

          Button {
            width: parent.width
            text: root.busy && actionProc.action === "start" ? "Starting…" : "Start local recording"
            iconText: root.busy && actionProc.action === "start" ? "󰦖" : "󰑊"
            iconSpinning: root.busy && actionProc.action === "start"
            foreground: root.urgent
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            enabled: root.configured && !root.busy
            onClicked: root.runAction("start", [titleField.text.trim()])
          }

          Text {
            width: parent.width
            text: "Captures microphone + desktop audio and labels them You / Remote. Make sure everyone has agreed to the recording."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Column {
          visible: !root.setupMode && root.meetingStatus !== "idle"
          width: parent.width
          spacing: Style.space(9)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: root.meetingStatus === "paused" ? "Resume" : "Pause"
              iconText: root.meetingStatus === "paused" ? "󰐊" : "󰏤"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.busy
              onClicked: root.runAction(root.meetingStatus === "paused" ? "resume" : "pause", [])
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: root.busy && actionProc.action === "stop" ? "Finishing…" : "Stop and save"
              iconText: root.busy && actionProc.action === "stop" ? "󰦖" : "󰓛"
              iconSpinning: root.busy && actionProc.action === "stop"
              foreground: root.urgent
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.busy
              onClicked: root.runAction("stop", [])
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "MANUAL NOTE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: authorField
            width: parent.width
            placeholderText: "Author (optional)"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            Keys.onReturnPressed: noteField.forceActiveFocus()
          }

          TextField {
            id: noteField
            width: parent.width
            placeholderText: "Important point, decision or action"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            Keys.onReturnPressed: root.saveNote()
          }

          Button {
            width: parent.width
            text: root.busy && actionProc.action === "add-note" ? "Saving…" : "Save timestamped note"
            iconText: root.busy && actionProc.action === "add-note" ? "󰦖" : "✓"
            iconSpinning: root.busy && actionProc.action === "add-note"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            enabled: !root.busy
            onClicked: root.saveNote()
          }
        }

        Text {
          visible: root.statusMessage !== ""
          width: parent.width
          text: root.statusMessage
          color: root.statusIsError ? root.urgent : root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          visible: !root.setupMode && root.recentNotes.length > 0
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "RECENT MANUAL NOTES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.recentNotes

            Text {
              required property var modelData
              width: parent.width
              text: "<b>" + String(modelData.time || "") + " · "
                + String(modelData.author || "Me").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                + ":</b> " + String(modelData.note || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
              textFormat: Text.RichText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }
        }

          Button {
            visible: !root.setupMode
            width: parent.width
            text: root.meetingStatus === "idle" ? "Open latest meeting" : "Open meeting folder"
            iconText: "↗"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            enabled: !openProc.running
            onClicked: if (!openProc.running) openProc.running = true
          }
        }
      }
    }
  }
}
