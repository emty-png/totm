import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// First-run welcome tour: dimmed modal card in the ConfirmPopup visual
// language (surface + border + radiusLarge + soft shadow). Three pages,
// dots + Back/Next, Skip. Any dismissal pins onboardingCompleted via
// SettingsStore so second launch stays clean; Settings reopens it.
Popup {
    id: tour

    property int currentIndex: 0
    readonly property int pageCount: 3
    readonly property bool isLast: tour.currentIndex === tour.pageCount - 1

    function showTour() {
        tour.currentIndex = 0;
        tour.open();
    }

    function next() {
        if (tour.isLast) {
            SettingsStore.completeOnboarding();
            tour.close();
        } else {
            tour.currentIndex++;
        }
    }

    function skip() {
        SettingsStore.completeOnboarding();
        tour.close();
    }

    anchors.centerIn: parent
    width: Math.min(520, (parent ? parent.width : 552) - 32)
    padding: 20
    modal: true
    dim: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    // Duller backdrop than the default modal dim, scoped to this tour
    // only (other popups keep the shared dim).
    Overlay.modal: Rectangle {
        color: "#a6000000"
    }

    onClosed: {
        // Escape / outside-press also pins: the tour shows exactly once.
        if (SettingsStore.shouldShowOnboarding())
            SettingsStore.completeOnboarding();
        tour.currentIndex = 0;
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.97
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: 100
            easing.type: Easing.InCubic
        }
    }

    background: Rectangle {
        radius: AppTheme.radiusLarge
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border
    }

    contentItem: ColumnLayout {
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("%1 of %2").arg(tour.currentIndex + 1).arg(tour.pageCount)
                font.pixelSize: 12
                elide: Text.ElideRight
                color: AppTheme.muted
            }

            Text {
                text: qsTr("Skip")
                font.pixelSize: 12
                color: skipMouse.containsMouse ? AppTheme.foreground : AppTheme.muted

                MouseArea {
                    id: skipMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tour.skip()
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            currentIndex: tour.currentIndex

            OnboardingPage {
                iconKind: "sparkle"
                title: qsTr("Welcome to totm")
                body: qsTr("An offline motion-graphics editor. Draw vectors, arrange layers, then bring them to life on the timeline.")
            }
            OnboardingPage {
                iconKind: "plus"
                title: qsTr("Start something")
                body: qsTr("Create a new design, start from a template, or import a shared .totm bundle from the home library.")
            }
            OnboardingPage {
                iconKind: "play"
                title: qsTr("Design, then animate")
                body: qsTr("Shape the canvas with tools and the design panel, then add presets or custom clips and press play.")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 6

            Repeater {
                model: tour.pageCount

                Rectangle {
                    required property int index

                    Layout.preferredWidth: tour.currentIndex === index ? 20 : 8
                    Layout.preferredHeight: 8
                    Layout.alignment: Qt.AlignVCenter
                    radius: 4
                    color: tour.currentIndex === index ? AppTheme.selection : AppTheme.fieldBorder

                    Behavior on Layout.preferredWidth {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tour.currentIndex = index
                    }
                }
            }

            // Spacer: pins Back / Next to the right edge on every page.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
            }

            Rectangle {
                Layout.preferredWidth: backText.implicitWidth + 24
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: backMouse.pressed ? AppTheme.pressed : backMouse.containsMouse ? AppTheme.hover : AppTheme.surface
                visible: tour.currentIndex > 0
                enabled: tour.currentIndex > 0

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    id: backText

                    anchors.centerIn: parent
                    text: qsTr("Back")
                    font.pixelSize: 12
                    color: backMouse.containsMouse || backMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: backMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tour.currentIndex--
                }
            }

            Rectangle {
                Layout.preferredWidth: nextText.implicitWidth + 32
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.foreground
                color: AppTheme.foreground

                Text {
                    id: nextText

                    anchors.centerIn: parent
                    text: tour.isLast ? qsTr("Get started") : qsTr("Next")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: AppTheme.background
                }

                MouseArea {
                    id: nextMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tour.next()
                }
            }
        }
    }
}
