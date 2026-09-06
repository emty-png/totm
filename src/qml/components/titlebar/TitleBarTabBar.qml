import QtQuick
import QtQuick.Layouts
import Totm

// Left tab cluster: pinned home tab, document tabs, add (+) button.
// Fixed widths (home 46, docs 138) so the active blend cover in TitleBar
// can be positioned arithmetically.
RowLayout {
    id: tabBar

    // Active tab geometry for the bottom-border cover (TitleBar draws it).
    // Doc tabs are 4x the 46px home tab = 184px.
    readonly property bool homeActive: TabStore.currentIndex === 0
    readonly property real activeX: homeActive ? 0 : 46 + (TabStore.currentIndex - 1) * 184
    readonly property real activeWidth: homeActive ? 46 : 184

    spacing: 0
    Layout.fillHeight: true

    TitleBarHomeTab {
        active: tabBar.homeActive
        onClicked: TabStore.select(0)
    }

    Repeater {
        model: TabStore.docCount
        TitleBarTab {
            // NOTE: plain injected `index` (qmllint suggests a required
            // declaration, but that silently breaks sibling bindings at
            // runtime — verified headlessly). Warnings below are advisory.
            title: TabStore.titleAt(index + 1)
            active: TabStore.currentIndex === index + 1
            onClicked: TabStore.select(index + 1)
            onCloseRequested: TabStore.closeTab(index + 1)
        }
    }

    // New-tab button, same 46px width as window controls.
    TitleBarButton {
        iconKind: "plus"
        onClicked: TabStore.addUntitled()
    }
}
