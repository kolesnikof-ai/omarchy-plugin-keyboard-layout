import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "KeyboardLayoutModel.js" as KeyboardLayoutModel

BarWidget {
  id: root
  moduleName: "omarchy.keyboard-layout"


  property string layoutFull: ""
  // xkb layout id of the keymap above ("us", "ru"), from the layout list rather
  // than the description. Empty when the seat has not named one.
  property string layoutId: ""
  // The keyboard the last reading spoke for, which is the one a click switches,
  // and separately the one activelayout named as being typed on. A reading
  // confirms the first is really there, so the click has a keyboard to reach
  // from the first reading onwards rather than only after a switch, and stops
  // naming one that has been unplugged.
  property string keyboardName: ""
  property string typedKeyboardName: ""
  // Keyboards on the seat, buttons and virtual ones excluded, and whether the
  // last reading left that shape in doubt.
  property int keyboardCount: 0
  property bool keyboardUnresolved: false
  // Nothing to read or switch on the single-layout install most people run, so
  // the widget ships on the bar and stays out of the way until there are two.
  // An older Hyprland that doesn't report the list keeps showing the label.
  property bool multipleLayouts: true
  // Short language code per layout description ("English (US)": "en"), read from
  // xkb's own table rather than maintained by hand.
  property var layoutBriefs: ({})
  readonly property string layoutLabel: KeyboardLayoutModel.shortLabel(layoutFull, layoutBriefs)

  // A query already in flight was started before this event, so it may read the
  // layout the switch replaced. Remember the request and re-run once it lands
  // rather than dropping it; nothing else would correct the label afterwards.
  property bool refreshPending: false

  function refresh() {
    if (queryProc.running) {
      refreshPending = true
      return
    }

    refreshPending = false
    queryProc.running = true
  }

  // Keyboards someone can actually type on, which is not everything Hyprland
  // calls a keyboard.
  function typedKeyboards(keyboards) {
    return keyboards.filter(k => KeyboardLayoutModel.isTypedKeyboard(k.name))
  }

  // The main flag names no keyboard for long: fcitx5 takes it with the virtual
  // keyboard it binds to inject, which leaves no typed keyboard holding it and
  // nothing to read at all, and once that unbinds it lands on whichever device
  // Hyprland saw last, a power button included. Go by layout progress instead,
  // and by the keyboard activelayout named.
  function selectKeyboard(typed) {
    return KeyboardLayoutModel.selectKeyboard(typed, root.typedKeyboardName)
  }

  // switchxkblayout is a hyprctl command rather than a dispatcher, so it has to
  // be run rather than sent over the dispatch socket. It switches the keyboard
  // the last reading spoke for, so a click always advances the device the label
  // is describing. Switching the seat together would reach the typed keyboard
  // without having to name it, but it would also carry the buttons along, and
  // the whole read depends on those staying where they started: once a button
  // has been advanced too, a toggle that wraps the keyboard back to the first
  // layout leaves the button reading as the furthest along, and the label
  // follows the button.
  function cycleLayout() {
    if (!root.keyboardName || !root.bar) return
    root.bar.run("hyprctl switchxkblayout " + Util.shellQuote(root.keyboardName) + " next")
    refreshTimer.restart()
  }

  Component.onCompleted: {
    briefsProc.running = true
    refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      // The event names the keyboard that switched ahead of the layout it moved
      // to, and that is the keyboard being typed on whatever holds the main flag.
      if (name === "activelayout") {
        const named = KeyboardLayoutModel.eventKeyboardName(event)
        if (named) root.typedKeyboardName = named
      }

      // A reload that adds a layout to kb_layout decides whether the widget
      // shows at all, and leaves every keyboard on the layout it was already
      // reading, so it raises no activelayout to notice it by.
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.refresh()
    }
  }

  Process {
    id: queryProc
    command: ["hyprctl", "-j", "devices"]
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }

      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let listed
        try {
          listed = JSON.parse(text || "{}").keyboards
        } catch (e) {
          return
        }

        // A query the watchdog killed reports nothing at all, and an empty
        // string parses into the same shape a seat with no keyboards would.
        // Tell them apart by the list itself, so only a reading that reached
        // hyprctl gets to speak for the seat.
        if (!Array.isArray(listed)) return

        const typed = root.typedKeyboards(listed)
        const kb = root.selectKeyboard(typed)
        if (!kb || !kb.active_keymap) {
          // Either the last keyboard has been unplugged, which the label has to
          // stop describing and the click has to stop naming, or keyboards are
          // there and none of them reports a keymap. Both leave the shape in
          // doubt, so keep asking rather than letting a count from before it
          // changed settle the poll.
          root.keyboardUnresolved = true
          if (typed.length === 0) {
            root.layoutFull = ""
            root.layoutId = ""
            root.keyboardName = ""
          }
          return
        }

        root.keyboardUnresolved = false
        root.keyboardCount = typed.length
        root.keyboardName = String(kb.name || "")
        root.multipleLayouts = kb.layout === undefined || String(kb.layout).indexOf(",") !== -1
        root.layoutFull = kb.active_keymap
        root.layoutId = KeyboardLayoutModel.activeLayoutId(kb)
      }
    }
  }

  // The table only changes when xkb data is upgraded, so read it at startup and
  // leave it alone. The bar is built per monitor, so this runs once per widget.
  // The exotic rulesets cover layouts like trans (IPA) that ship in the same xkb
  // package and set just as well, so load them or those labels lose their code.
  Process {
    id: briefsProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.layoutBriefs = KeyboardLayoutModel.layoutBriefs(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: root.refresh()
  }

  // A query that never returns would freeze the label until the shell restarts,
  // since a Process that is already running can't be re-run. Give up on one that
  // overstays so the next refresh gets through, and ask again: the reading it
  // never delivered may have been the only one due on a settled seat, and
  // nothing else would come back for it.
  Timer {
    id: stallTimer
    interval: 5000
    onTriggered: {
      queryProc.running = false
      refreshTimer.restart()
    }
  }

  // Which keyboard on a crowded seat the label is describing can change without
  // Hyprland announcing it, since a device arriving or leaving raises no event
  // of its own, and that can only be learned by asking. Poll while there is that
  // ambiguity, until a first reading lands so a query that failed at login still
  // recovers, and while a reading has left the seat's shape in doubt. The
  // one-keyboard install has none of those, and is left alone rather than
  // spawning hyprctl forever for an answer that cannot change.
  Timer {
    interval: 10000
    running: !root.keyboardName || root.keyboardUnresolved || root.keyboardCount > 1
    repeat: true
    onTriggered: root.refresh()
  }

  visible: layoutLabel !== "" && multipleLayouts

  // Unscaled pixels. One number pads both sides. Two numbers set the left and
  // the right inset on their own, as a list ([16, 0]) or a string ("16 0").
  // The live values come from this widget's entry in shell.json.
  // Named apart from WidgetButton.horizontalMargin: that property is a single
  // real, and sharing the name lets its 0 binding overwrite this list.
  property var marginValue: setting("horizontalMargin", [6, 6])

  // The value has to be an argument. Reading it only inside the function does
  // not subscribe the binding, so the insets stay 0 after shell.json arrives.
  function marginNumber(value, side) {
    let parts = []
    if (Array.isArray(value)) parts = value
    else if (typeof value === "string") parts = value.trim().split(/\s+/)
    else if (value && typeof value.length === "number") {
      for (let i = 0; i < value.length; i++) parts.push(value[i])
    } else parts = [value]

    if (parts.length < 1 || parts[0] === "") return 0
    const raw = side === 0 || parts.length < 2 ? parts[0] : parts[1]
    const n = Number(raw)
    return isFinite(n) ? n : 0
  }

  readonly property real marginLeft: Style.spaceReal(marginNumber(marginValue, 0))
  readonly property real marginRight: Style.spaceReal(marginNumber(marginValue, 1))
  // The button can only pad both sides by one number and then centers its
  // label. On a horizontal bar the caption and the flag are placed explicitly,
  // so equal insets such as [6, 6] stay on their own sides.

  // "flag" draws the country mark. "text" keeps the short language label.
  property string layoutDisplay: setting("layoutDisplay", "flag")
  readonly property bool displayFlag: layoutDisplay !== "text"
  // "rect", "rounded", or "circle". Any other value is a plain rectangle.
  property string flagShape: setting("flagShape", "circle")
  // A shell font step: caption, body-small, body, subtitle, title, heading,
  // display, display-large. The size follows the shell base. The flag matches it.
  function fontTokenSize(name) {
    switch (String(name || "")) {
      case "caption": return Style.font.caption
      case "body-small": return Style.font.bodySmall
      case "body": return Style.font.body
      case "subtitle": return Style.font.subtitle
      case "title": return Style.font.title
      case "heading": return Style.font.heading
      case "display": return Style.font.display
      case "display-large": return Style.font.displayLarge
      default: return Style.font.title
    }
  }
  property real fontSize: fontTokenSize(setting("fontSize", "title"))
  readonly property string resolvedFlagShape: flagShape === "rounded" || flagShape === "circle" ? flagShape : "rect"
  readonly property string flagFile: KeyboardLayoutModel.flagName(layoutId)
  readonly property bool flagCircle: resolvedFlagShape === "circle"
  readonly property bool flagRounded: resolvedFlagShape === "rounded"
  readonly property real flagHeight: fontSize
  readonly property real flagWidth: flagCircle ? flagHeight : flagHeight * 4 / 3
  readonly property url flagSource: displayFlag && flagFile !== "" ? Qt.resolvedUrl("flags/" + (flagCircle ? "circle" : "rect") + "/" + flagFile + ".svg") : ""
  // A missing file reports Error and the text label takes the slot back. A
  // vertical bar keeps the button's own label; the flag is a horizontal mark.
  readonly property bool showFlag: displayFlag && flagFile !== "" && !(bar && bar.vertical) && flagImage.status !== Image.Error
  readonly property bool customSlot: !(bar && bar.vertical)

  implicitWidth: customSlot ? Math.max(12, (showFlag ? flagWidth : caption.implicitWidth) + marginLeft + marginRight) : button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.layoutLabel
    fontSize: root.fontSize
    horizontalMargin: root.customSlot ? 0 : root.marginNumber(root.marginValue, 0)
    labelVisible: !root.customSlot
    tooltipText: root.layoutFull
    onPressed: function() { root.cycleLayout() }

    Text {
      id: caption
      visible: root.customSlot && !root.showFlag
      x: root.marginLeft
      anchors.verticalCenter: parent.verticalCenter
      text: button.text
      textFormat: Text.PlainText
      color: button.active && button.useActiveColor ? button.activeColor : button.foreground
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      renderType: Text.NativeRendering

      Behavior on color {
        enabled: !button.bar || button.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: flagSlot
      visible: root.showFlag
      x: root.marginLeft
      anchors.verticalCenter: parent.verticalCenter
      width: root.flagWidth
      height: root.flagHeight

      // The mask has to stay visible: a hidden item never fills its layer, and
      // the effect then has nothing to sample. The picture is the same size and
      // covers this rectangle, so only the rounded-off corners show the bar.
      Rectangle {
        id: flagMask
        anchors.fill: parent
        radius: Math.min(Style.spaceReal(3), width / 2, height / 2)
        visible: root.flagRounded
        layer.enabled: root.flagRounded
        color: "white"
      }

      Item {
        anchors.fill: parent
        layer.enabled: root.flagRounded
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: root.flagRounded
          maskSource: flagMask
          maskThresholdMin: 0.3
          maskSpreadAtMin: 0.3
        }

        Image {
          id: flagImage
          anchors.fill: parent
          source: root.flagSource
          fillMode: Image.PreserveAspectFit
          smooth: true
          cache: true
          sourceSize.width: Math.round(width * Screen.devicePixelRatio)
          sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        }
      }
    }
  }
}
