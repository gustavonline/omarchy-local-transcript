import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.gustavonline.local-transcript"
  ipcTarget: moduleName

  property bool configured: false
  property bool settingsPage: false
  property string transcriptStatus: "idle"
  property string transcriptTitle: "Local Transcript"
  property int elapsedSeconds: 0
  property int chunks: 0
  property var recentNotes: []
  property string statusMessage: ""
  property bool statusIsError: false
  property bool busy: false
  property bool downloadBusy: false
  property string downloadKind: ""

  property string selectedStt: "small"
  property string selectedSummary: "qwen3:4b-instruct"
  property bool selectedSaveAudio: false
  property bool selectedAutoSummary: true
  property bool selectedDetection: true
  property var selectedSourceApps: []
  property bool sttReady: false
  property bool summaryReady: false
  property var installedSttModels: []
  property var installedSummaryModels: []
  property var requirements: ({})

  readonly property string helperPath: Qt.resolvedUrl("local-transcript").toString().replace(/^file:\/\//, "")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var sttOptions: [
    { value: "base", label: "Whisper Base", description: "142 MB · Fastest" },
    { value: "small", label: "Whisper Small", description: "466 MB · Recommended" },
    { value: "large-v3-turbo", label: "Whisper Large v3 Turbo", description: "1.6 GB · Most accurate" }
  ]
  readonly property var summaryOptions: [
    { value: "disabled", label: "No summary", description: "Transcript only" },
    { value: "qwen3:1.7b", label: "Qwen 3 1.7B", description: "1.4 GB · Faster" },
    { value: "qwen3:4b-instruct", label: "Qwen 3 4B Instruct", description: "2.5 GB · Recommended" }
  ]

  function formatDuration(total) {
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var seconds = total % 60
    var shortValue = (minutes < 10 && hours > 0 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    return hours > 0 ? hours + ":" + shortValue : shortValue
  }

  function sttShortLabel() {
    if (selectedStt === "base") return "Whisper Base"
    if (selectedStt === "large-v3-turbo") return "Whisper Turbo"
    return "Whisper Small"
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
      transcriptStatus = String(data.meeting_status || "idle")
      transcriptTitle = String(data.title || "Local Transcript")
      elapsedSeconds = Number(data.elapsed_seconds || 0)
      chunks = Number(data.chunks || 0)
      recentNotes = Array.isArray(data.recent_notes) ? data.recent_notes : []
      if (data.audio_warning && statusMessage === "") {
        statusMessage = String(data.audio_warning)
        statusIsError = true
      }
      if (!configured) settingsPage = true
    } catch (error) {
      statusMessage = "Could not read transcript state"
      statusIsError = true
    }
  }

  function parseSetup(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      var config = data.config || {}
      outputField.text = String(config.outputDirectory || "~/Documents/Transcripts")
      selectedStt = String(config.sttModel || "small")
      selectedSummary = String(config.summaryModel || "qwen3:4b-instruct")
      selectedSaveAudio = Boolean(config.saveAudio)
      selectedAutoSummary = config.autoSummarize === undefined ? true : Boolean(config.autoSummarize)
      selectedDetection = config.detectSources === undefined ? true : Boolean(config.detectSources)
      selectedSourceApps = Array.isArray(config.sourceApps) ? config.sourceApps : []
      sttReady = Boolean(data.stt_ready)
      summaryReady = Boolean(data.summary_ready)
      installedSttModels = Array.isArray(data.installed_stt_models) ? data.installed_stt_models : []
      installedSummaryModels = Array.isArray(data.ollama_models) ? data.ollama_models : []
      requirements = data.requirements || {}
    } catch (error) {
      statusMessage = "Could not read local settings"
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
      statusMessage = "Choose a transcript folder"
      statusIsError = true
      outputField.forceActiveFocus()
      return
    }
    runAction("configure", [folder, selectedStt, selectedSummary,
      selectedSaveAudio ? "true" : "false",
      selectedAutoSummary ? "true" : "false",
      selectedDetection ? "true" : "false",
      JSON.stringify(selectedSourceApps)])
  }

  function downloadModel(kind) {
    if (downloadBusy || (kind === "summary" && selectedSummary === "disabled")) return
    downloadBusy = true
    downloadKind = kind
    statusMessage = kind === "stt" ? "Downloading transcription model…" : "Downloading summary model…"
    statusIsError = false
    downloadProc.command = kind === "stt"
      ? [helperPath, "download-stt", selectedStt]
      : [helperPath, "download-summary", selectedSummary]
    downloadProc.running = true
  }

  function saveNote() {
    var note = noteField.text.trim()
    if (note === "") return
    runAction("add-note", ["Me", note])
  }

  onOpenedChanged: if (opened) {
    refresh()
    if (settingsPage || !configured) refreshSetup()
    Qt.callLater(function() {
      if (settingsPage) outputField.forceActiveFocus()
      else if (transcriptStatus === "idle") titleField.forceActiveFocus()
      else noteField.forceActiveFocus()
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Timer {
    interval: 2000
    repeat: true
    running: root.opened || root.transcriptStatus !== "idle"
    onTriggered: root.refresh()
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.configured
    onTriggered: if (!detectProc.running) detectProc.running = true
  }

  Process {
    id: stateProc
    command: [root.helperPath, "state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseState(text) }
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
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseSetup(text) }
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
        if (action === "start") root.statusMessage = "Recording started"
        else if (action === "pause") root.statusMessage = "Transcription paused"
        else if (action === "resume") root.statusMessage = "Transcription resumed"
        else if (action === "stop") root.statusMessage = "Transcript saved"
        else if (action === "add-note") {
          root.statusMessage = "Annotation saved"
          noteField.text = ""
          noteField.forceActiveFocus()
        } else if (action === "configure") {
          root.statusMessage = "Settings saved"
          root.configured = true
          root.settingsPage = false
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
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: downloadError; waitForEnd: true }
    onExited: function(exitCode) {
      root.downloadBusy = false
      if (exitCode === 0) {
        root.statusMessage = root.downloadKind === "stt" ? "Transcription model installed" : "Summary model installed"
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
        root.statusMessage = String(openError.text || "Could not open transcript folder").trim()
        root.statusIsError = true
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.transcriptStatus === "recording" ? "󰑊" : root.transcriptStatus === "paused" ? "󰏤" : "󰈙"
    foreground: root.transcriptStatus === "recording" ? root.urgent : root.foreground
    active: root.transcriptStatus !== "idle"
    tooltipText: root.transcriptStatus === "recording" ? "Local Transcript · " + root.formatDuration(root.elapsedSeconds)
      : root.transcriptStatus === "paused" ? "Transcript paused" : "Local Transcript"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (!openProc.running) openProc.running = true
      } else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.settingsPage ? outputField : (root.transcriptStatus === "idle" ? titleField : noteField)
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: outputField.activeFocus || titleField.activeFocus || noteField.activeFocus
        || sttDropdown.popupOpen || summaryDropdown.popupOpen || appPicker.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: content
        anchors.fill: parent
        implicitHeight: Math.min(contentColumn.implicitHeight, root.settingsPage ? Style.space(720) : Style.space(520))
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: Style.space(16)

        Column {
          id: contentColumn
          width: content.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(titleBlock.implicitHeight, settingsButton.implicitHeight)

            Column {
              id: titleBlock
              anchors.left: parent.left
              anchors.right: settingsButton.left
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.settingsPage ? "Settings" : "Local Transcript"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: !root.settingsPage
                text: root.transcriptStatus === "idle" ? "Ready"
                  : (root.transcriptStatus === "recording" ? "Recording" : "Paused") + " · " + root.formatDuration(root.elapsedSeconds)
                color: root.transcriptStatus === "recording" && !root.settingsPage ? root.urgent : root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            PanelActionButton {
              id: settingsButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.settingsPage ? "󰁍" : "󰒓"
              tooltipText: root.settingsPage ? "Back" : "Settings"
              foreground: root.foreground
              hoverColor: root.accent
              fontFamily: root.fontFamily
              bordered: true
              focusable: true
              enabled: root.configured || !root.settingsPage
              onClicked: {
                root.settingsPage = !root.settingsPage
                if (root.settingsPage) root.refreshSetup()
                else root.refresh()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            visible: !root.settingsPage && root.transcriptStatus === "idle"
            width: parent.width
            spacing: Style.space(10)

            TextField {
              id: titleField
              width: parent.width
              placeholderText: "Transcript title (optional)"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              Keys.onReturnPressed: root.runAction("start", [titleField.text.trim()])
            }

            Button {
              width: parent.width
              text: root.busy && actionProc.action === "start" ? "Starting…" : "Start recording"
              iconText: root.busy && actionProc.action === "start" ? "󰦖" : "󰐊"
              iconSpinning: root.busy && actionProc.action === "start"
              foreground: root.accent
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              enabled: root.configured && !root.busy
              onClicked: root.runAction("start", [titleField.text.trim()])
            }

            Text {
              width: parent.width
              text: "Computer + microphone · " + root.sttShortLabel()
              color: Qt.darker(root.foreground, 1.45)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Button {
              width: parent.width
              text: "Open transcripts"
              iconText: "↗"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: false
              enabled: !openProc.running
              onClicked: if (!openProc.running) openProc.running = true
            }
          }

          Column {
            visible: !root.settingsPage && root.transcriptStatus !== "idle"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: root.transcriptTitle
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.formatDuration(root.elapsedSeconds)
              color: root.transcriptStatus === "recording" ? root.urgent : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: root.transcriptStatus === "paused" ? "Resume" : "Pause"
                iconText: root.transcriptStatus === "paused" ? "󰐊" : "󰏤"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                bordered: true
                enabled: !root.busy
                onClicked: root.runAction(root.transcriptStatus === "paused" ? "resume" : "pause", [])
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                text: root.busy && actionProc.action === "stop" ? "Finishing…" : "Stop & save"
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

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: noteField
                width: parent.width - addNoteButton.width - parent.spacing
                placeholderText: "Add a timestamped annotation"
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                Keys.onReturnPressed: root.saveNote()
              }

              PanelActionButton {
                id: addNoteButton
                iconText: "＋"
                tooltipText: "Save annotation"
                foreground: root.foreground
                hoverColor: root.accent
                fontFamily: root.fontFamily
                bordered: true
                focusable: true
                enabled: !root.busy
                onClicked: root.saveNote()
              }
            }

            Column {
              visible: root.recentNotes.length > 0
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: root.recentNotes
                Text {
                  required property var modelData
                  width: parent.width
                  text: String(modelData.time || "") + "  " + String(modelData.note || "")
                  color: Qt.darker(root.foreground, 1.2)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }

          Column {
            visible: root.settingsPage
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "FILES"; foreground: root.foreground; fontFamily: root.fontFamily }

            TextField {
              id: outputField
              width: parent.width
              placeholderText: "~/Documents/Transcripts"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
            }

            PanelSectionHeader { text: "TRANSCRIPTION"; foreground: root.foreground; fontFamily: root.fontFamily }

            Dropdown {
              id: sttDropdown
              width: parent.width
              label: "Model"
              value: root.selectedStt
              options: root.sttOptions
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(value) {
                root.selectedStt = value
                root.sttReady = root.installedSttModels.indexOf(value) >= 0
              }
            }

            Button {
              visible: !root.sttReady || (root.downloadBusy && root.downloadKind === "stt")
              width: parent.width
              text: root.downloadBusy && root.downloadKind === "stt" ? "Downloading model…"
                : root.sttReady ? "Installed" : "Download model"
              iconText: root.downloadBusy && root.downloadKind === "stt" ? "󰦖" : root.sttReady ? "✓" : "󰇚"
              iconSpinning: root.downloadBusy && root.downloadKind === "stt"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.downloadBusy && !root.sttReady
              onClicked: root.downloadModel("stt")
            }

            Text {
              visible: root.sttReady && !(root.downloadBusy && root.downloadKind === "stt")
              width: parent.width
              text: "✓ Installed"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            PanelSectionHeader { text: "SUMMARY"; foreground: root.foreground; fontFamily: root.fontFamily }

            Dropdown {
              id: summaryDropdown
              width: parent.width
              label: "Model"
              value: root.selectedSummary
              options: root.summaryOptions
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(value) {
                root.selectedSummary = value
                root.selectedAutoSummary = value !== "disabled"
                root.summaryReady = value === "disabled"
                  || root.installedSummaryModels.indexOf(value) >= 0
              }
            }

            Button {
              visible: root.selectedSummary !== "disabled"
                && (!root.summaryReady || (root.downloadBusy && root.downloadKind === "summary"))
              width: parent.width
              text: root.downloadBusy && root.downloadKind === "summary" ? "Downloading model…"
                : root.summaryReady ? "Installed" : "Download model"
              iconText: root.downloadBusy && root.downloadKind === "summary" ? "󰦖" : root.summaryReady ? "✓" : "󰇚"
              iconSpinning: root.downloadBusy && root.downloadKind === "summary"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.downloadBusy && !root.summaryReady
              onClicked: root.downloadModel("summary")
            }

            Text {
              visible: root.selectedSummary !== "disabled" && root.summaryReady
                && !(root.downloadBusy && root.downloadKind === "summary")
              width: parent.width
              text: "✓ Installed"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Toggle {
              width: parent.width
              label: "Create summary"
              description: "Written in the transcript language"
              checked: root.selectedAutoSummary && root.selectedSummary !== "disabled"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              enabled: root.selectedSummary !== "disabled"
              onClicked: root.selectedAutoSummary = !root.selectedAutoSummary
            }

            Toggle {
              width: parent.width
              label: "Save audio"
              description: "Keep a compressed audio copy"
              checked: root.selectedSaveAudio
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.selectedSaveAudio = !root.selectedSaveAudio
            }

            PanelSectionHeader { text: "REMINDERS"; foreground: root.foreground; fontFamily: root.fontFamily }

            Toggle {
              width: parent.width
              label: "Recording reminders"
              description: "Prompt when a selected app uses audio"
              checked: root.selectedDetection
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.selectedDetection = !root.selectedDetection
            }

            MultiSelect {
              id: appPicker
              visible: root.selectedDetection
              width: parent.width
              label: "Apps"
              values: root.selectedSourceApps
              optionsCommand: [root.helperPath, "apps"]
              placeholderText: "Search installed apps…"
              noSelectionText: "Choose apps"
              emptyText: "No installed apps found"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(values) { root.selectedSourceApps = values }
            }

            Button {
              width: parent.width
              text: root.busy && actionProc.action === "configure" ? "Saving…" : "Save"
              iconText: root.busy && actionProc.action === "configure" ? "󰦖" : "✓"
              iconSpinning: root.busy && actionProc.action === "configure"
              foreground: root.accent
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.busy && !root.downloadBusy
              onClicked: root.saveSetup()
            }

            Item { width: 1; height: Style.space(8) }
          }

          Text {
            visible: root.statusMessage !== ""
            width: parent.width
            text: root.statusMessage
            color: root.statusIsError ? root.urgent : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
