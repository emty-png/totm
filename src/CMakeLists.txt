qt_add_executable(totm
    main.cpp
    "${PROJECT_SOURCE_DIR}/packaging/icons.qrc"
    "${PROJECT_SOURCE_DIR}/packaging/official-plugins.qrc"
)

# Platform icons: macOS bundle icon, Windows exe icon. The Linux
# hicolor set + desktop entry install below instead of embedding.
if(APPLE)
    set_source_files_properties(
        "${PROJECT_SOURCE_DIR}/packaging/icons/totm.icns"
        PROPERTIES MACOSX_PACKAGE_LOCATION "Resources"
    )
    target_sources(totm PRIVATE "${PROJECT_SOURCE_DIR}/packaging/icons/totm.icns")
elseif(WIN32)
    target_sources(totm PRIVATE "${PROJECT_SOURCE_DIR}/packaging/icons/totm.rc")
endif()

set_source_files_properties(
    qml/theme/AppTheme.qml
    qml/stores/TabState.qml
    qml/stores/ToolState.qml
    qml/stores/ShortcutState.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(totm
    URI Totm
    VERSION 1.0
    SOURCES
        backend/effects/EffectSpec.h
        backend/effects/EffectPainter.h
        backend/effects/EffectPainter.cpp
        backend/effects/EffectItem.h
        backend/effects/EffectItem.cpp
        backend/library/LibraryStore.h
        backend/library/LibraryStore.cpp
        backend/library/AudioPeaks.h
        backend/library/AudioPeaks.cpp
        backend/svg/SvgImport.h
        backend/svg/SvgImport.cpp
        backend/settings/SettingsStore.h
        backend/settings/SettingsStore.cpp
        backend/video/VideoExporter.h
        backend/video/VideoExporter.cpp
        backend/video/AnimSampler.h
        backend/video/AnimSampler.cpp
        backend/video/FramePaint.h
        backend/video/FramePaint.cpp
        backend/export/ComponentExporter.h
        backend/export/ComponentExporter.cpp
        backend/export/SvgPaint.h
        backend/export/SvgPaint.cpp
        backend/plugins/PluginStore.h
        backend/plugins/PluginStore.cpp
        backend/plugins/PluginNetworkGuard.h
        backend/crash/CrashReporter.h
        backend/crash/CrashReporter.cpp
        backend/crash/CrashHandler.h
        backend/crash/CrashHandler.cpp
        backend/files/FileBrowser.h
        backend/files/FileBrowser.cpp
    QML_FILES
        # Shell
        qml/Main.qml
        qml/CrashWindow.qml
        # Theme + stores (singletons)
        qml/theme/AppTheme.qml
        qml/stores/TabState.qml
        qml/stores/ToolState.qml
        qml/stores/ShortcutState.qml
        # Document + helpers
        qml/models/Document.qml
        qml/models/DocNode.qml
        qml/models/document/DocTree.qml
        qml/models/document/DocEffective.qml
        qml/models/document/DocLayersModel.qml
        qml/models/document/DocDrill.qml
        qml/models/document/DocClipboard.qml
        qml/models/document/DocFactory.qml
        qml/models/document/DocSelection.qml
        qml/models/document/DocRename.qml
        qml/models/document/DocGroup.qml
        qml/models/document/DocReorder.qml
        qml/models/document/DocBounds.qml
        qml/models/document/DocEdits.qml
        qml/models/document/DocPen.qml
        qml/models/document/DocCorners.qml
        qml/models/document/DocHistory.qml
        qml/models/document/DocAnimSample.qml
        qml/models/document/DocAnimPresets.qml
        qml/models/document/DocCustomDefaults.qml
        qml/models/document/DocTransport.qml
        qml/models/document/DocEasing.qml
        qml/models/document/DocPathSample.qml
        qml/models/document/DocAnim.qml
        qml/models/document/DocAudio.qml
        # Canvas + snapping
        qml/components/editor/snap/SnapEngine.qml
        qml/components/editor/snap/SnapTargets.qml
        qml/components/editor/snap/SnapEdge.qml
        qml/components/editor/snap/SnapSpacing.qml
        qml/components/editor/snap/SnapCombinators.qml
        qml/components/editor/canvas/BezierMath.qml
        qml/components/editor/canvas/ShapeDrawTool.qml
        qml/components/editor/canvas/ImageTool.qml
        qml/components/editor/canvas/TextEditor.qml
        qml/components/editor/canvas/CanvasCamera.qml
        qml/components/editor/canvas/CanvasGuides.qml
        qml/components/editor/canvas/CanvasSelectPolicy.qml
        qml/components/editor/canvas/CanvasResizePolicy.qml
        qml/components/editor/canvas/PenTool.qml
        qml/components/editor/canvas/PenOverlay.qml
        qml/components/editor/canvas/PathTool.qml
        qml/components/editor/canvas/PathOverlay.qml
        qml/components/editor/canvas/PenEdit.qml
        qml/components/editor/canvas/PenEditOverlay.qml
        qml/components/editor/canvas/ShapeLayer.qml
        qml/components/editor/canvas/CanvasOverlays.qml
        qml/components/editor/canvas/MeasurePill.qml
        qml/components/editor/canvas/DrillBreadcrumb.qml
        # Layers
        qml/components/editor/layers/LayerHighlight.qml
        qml/components/editor/layers/LayerLeading.qml
        qml/components/editor/layers/LayerRenameField.qml
        qml/components/editor/layers/LayerToggles.qml
        qml/components/editor/layers/LayersHeader.qml
        qml/components/editor/layers/LayersReorder.qml
        # Design panel
        qml/components/editor/properties/SelectionSnapshot.qml
        qml/components/editor/properties/PanelDropdown.qml
        qml/components/editor/properties/AlignOption.qml
        qml/components/editor/properties/TypographySection.qml
        qml/components/editor/properties/ColorSVPad.qml
        qml/components/editor/properties/ColorHueSlider.qml
        qml/components/editor/properties/ColorPickerPopup.qml
        qml/components/editor/properties/GradientEditor.qml
        qml/components/editor/properties/EffectsSection.qml
        qml/components/editor/properties/EffectsPopup.qml
        qml/components/editor/properties/EffectBlurFields.qml
        qml/components/editor/properties/EffectGlowFields.qml
        qml/components/editor/properties/EffectShadowCard.qml
        qml/components/editor/properties/EffectGlowCard.qml
        qml/components/editor/properties/PresetCard.qml
        qml/components/editor/properties/PresetGallery.qml
        qml/components/editor/properties/CustomGallery.qml
        qml/components/editor/properties/ClipCustomTransformOptions.qml
        qml/components/editor/properties/ClipCustomStyleOptions.qml
        qml/components/editor/properties/ClipCustomGradientOptions.qml
        qml/components/editor/properties/ClipCustomShadowOptions.qml
        qml/components/editor/properties/ClipCustomBlurOptions.qml
        qml/components/editor/properties/ClipCustomGlowOptions.qml
        qml/components/editor/properties/ClipCustomGrainOptions.qml
        qml/components/editor/properties/ClipCustomOtherOptions.qml
        qml/components/editor/properties/ClipEntryDropdown.qml
        qml/components/editor/properties/ClipAlphaWell.qml
        qml/components/editor/properties/ClipDashPair.qml
        qml/components/editor/properties/ClipPositionSwitch.qml
        qml/components/editor/properties/ClipPathOptions.qml
        qml/components/editor/properties/ShapeAnimationsPanel.qml
        qml/components/editor/properties/ClipEditor.qml
        qml/components/editor/properties/SegmentedOption.qml
        qml/components/editor/properties/ClipSlideOptions.qml
        qml/components/editor/properties/ClipSpinOptions.qml
        qml/components/editor/properties/ClipTextOptions.qml
        qml/components/editor/properties/ClipTimingOptions.qml
        qml/components/editor/properties/EasingGraph.qml
        qml/components/editor/properties/GraphEditorPopup.qml
        qml/components/editor/properties/PanelSection.qml
        qml/components/editor/properties/PanelIconButton.qml
        qml/components/editor/properties/PositionSection.qml
        qml/components/editor/properties/LayoutSection.qml
        qml/components/editor/properties/AppearanceSection.qml
        qml/components/editor/properties/AudioSection.qml
        qml/components/editor/properties/ImageSection.qml
        qml/components/editor/properties/FillSection.qml
        qml/components/editor/properties/FillEntryCard.qml
        qml/components/editor/properties/StrokeSection.qml
        qml/components/editor/properties/StrokeEntryCard.qml
        qml/components/editor/properties/PenSection.qml
        # Titlebar + window
        qml/components/titlebar/TitleBar.qml
        qml/components/titlebar/MacTrafficLights.qml
        qml/components/titlebar/TitleBarTabBar.qml
        qml/components/titlebar/TitleBarTab.qml
        qml/components/titlebar/TitleBarHomeTab.qml
        qml/components/titlebar/TitleBarButton.qml
        qml/components/titlebar/TitleBarControls.qml
        qml/components/titlebar/TitleBarDragArea.qml
        qml/components/window/WindowResizeHandles.qml
        # Icons (global glyph set)
        qml/components/icons/AppIcon.qml
        qml/components/icons/PickerIcons.qml
        # Selection
        qml/components/selection/DragSelection.qml
        # Editor shell
        qml/components/editor/PanelResizeHandle.qml
        qml/components/editor/AudioPreview.qml
        qml/components/editor/EditorLeftPanel.qml
        qml/components/editor/EditorRightPanel.qml
        qml/components/editor/EditorShortcuts.qml
        qml/components/editor/ExternalDropArea.qml
        qml/components/editor/EditorModeSwitcher.qml
        qml/components/editor/AnimateModeSwitcher.qml
        qml/components/editor/timeline/TimelineView.qml
        qml/components/editor/timeline/TimelineLane.qml
        qml/components/editor/timeline/TimelineAudioLane.qml
        qml/components/editor/timeline/TimelineRuler.qml
        qml/components/editor/timeline/TimelineTransport.qml
        qml/components/editor/EditorBottomPanel.qml
        qml/components/editor/EditorCanvas.qml
        qml/components/editor/properties/DesignPanel.qml
        qml/components/editor/properties/ExportSection.qml
        # Fields
        qml/components/fields/NumberField.qml
        qml/components/fields/HexField.qml
        qml/components/fields/RenameField.qml
        qml/components/editor/shapes/ShapeItem.qml
        qml/components/editor/shapes/ShapeGeometry.qml
        qml/components/editor/shapes/GrainOverlay.qml
        qml/components/editor/shapes/TextGlyphs.qml
        qml/components/editor/SelectionHandles.qml
        # Layers (view + context)
        qml/components/editor/layers/LayersView.qml
        qml/components/editor/layers/LayersRow.qml
        qml/components/editor/layers/LayersContextMenu.qml
        # Menu (shared rows)
        qml/components/menu/MenuItem.qml
        qml/components/menu/ToolbarMenuItem.qml
        # Dialogs (shared modals)
        qml/components/dialogs/ConfirmPopup.qml
        qml/components/dialogs/FilePicker.qml
        # Toolbar
        qml/components/toolbar/CanvasToolbar.qml
        qml/components/toolbar/ToolbarButton.qml
        # Export (video render)
        qml/components/editor/export/ExportButton.qml
        qml/components/editor/export/ExportQualityPopup.qml
        qml/components/editor/export/ExportProgressPopup.qml
        # Home feature components (screens live under views/)
        qml/components/home/HomeSelection.qml
        qml/components/home/WorkspacePanel.qml
        qml/components/home/WorkspaceRow.qml
        qml/components/home/DesignCard.qml
        qml/components/home/DesignCardPreview.qml
        qml/components/home/DesignContextMenu.qml
        qml/components/home/TemplateLibrary.qml
        qml/components/home/TemplateCard.qml
        qml/components/home/TemplateMenu.qml
        # Plugins (permission-gated QML extensions)
        qml/components/plugins/PluginPermissionPopup.qml
        qml/components/plugins/PluginPermissionRow.qml
        qml/components/plugins/OfficialBadge.qml
        qml/components/plugins/PluginManagerRow.qml
        qml/components/plugins/PluginFilePicker.qml
        qml/components/plugins/PluginSlot.qml
        # Views (screen roots only)
        qml/views/home/HomeView.qml
        qml/views/settings/SettingsView.qml
        qml/views/settings/SettingsTabBar.qml
        qml/views/settings/SettingsTab.qml
        qml/views/settings/GeneralSettingsView.qml
        qml/views/settings/PluginSettingsView.qml
        qml/views/settings/ShortcutSettingsView.qml
        qml/views/settings/AppearanceSettingsView.qml
        qml/views/editor/EditorView.qml
        # Settings rows
        qml/components/settings/ShortcutRow.qml
        qml/components/settings/GeneralNewDesignSection.qml
        qml/components/settings/GeneralExportSection.qml
        qml/components/settings/GeneralStorageSection.qml
        qml/components/settings/AppearanceThemeSection.qml
        qml/components/settings/AppearanceCanvasSection.qml
        qml/components/settings/AppearanceWindowSection.qml
        qml/components/settings/AppearanceColorRow.qml
        qml/components/settings/AppearanceColorsSection.qml
        qml/components/settings/AppearanceRadiusSection.qml
        qml/components/settings/AppearanceFontSection.qml
        qml/components/settings/AppearanceFontRow.qml
)

# Grain shaders precompiled with qsb (Qt6 ShaderEffect takes .qsb URLs,
# never inline source). Lands beside GrainOverlay.qml in the module.
qt_add_shaders(totm "totm_grain_shaders"
    PREFIX "/Totm"
    FILES
        qml/components/editor/shapes/grain.vert
        qml/components/editor/shapes/grain.frag
)

target_link_libraries(totm PRIVATE Qt6::Quick Qt6::Svg Qt6::Multimedia Qt6::Network)

# Backend headers register QML types by basename (see the generated
# qmltyperegistrations.cpp), so each backend dir must be on the include path.
target_include_directories(totm PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/effects
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/files
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/library
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/settings
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/video
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/export
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/svg
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/plugins
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/crash
)

# Cross-platform desktop bundle settings.
# Linux: plain executable. Windows: no console window. macOS: .app bundle.
set_target_properties(totm PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_ICON_FILE totm.icns
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}"
)

# macOS .totm association: custom plist carrying CFBundleDocumentTypes
# plus the exported UTI, so Finder opens route to the app (delivered as
# QFileOpenEvent). The stable bundle id matters for Launch Services.
if(APPLE)
    set_target_properties(totm PROPERTIES
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.tot.totm"
        MACOSX_BUNDLE_BUNDLE_NAME "totm"
        MACOSX_BUNDLE_INFO_PLIST "${PROJECT_SOURCE_DIR}/packaging/macos/Info.plist.in"
    )
endif()

# Linux desktop integration (X11 + Wayland): hicolor icons, desktop
# entry. `cmake --install` picks these up; no prebuilt packages ship.
if(UNIX AND NOT APPLE)
    foreach(icon_size IN ITEMS 16 22 24 32 48 64 128 256)
        install(
            FILES "${PROJECT_SOURCE_DIR}/packaging/icons/hicolor/${icon_size}x${icon_size}/apps/totm.png"
            DESTINATION "share/icons/hicolor/${icon_size}x${icon_size}/apps"
        )
    endforeach()
    install(
        FILES "${PROJECT_SOURCE_DIR}/packaging/totm.desktop"
        DESTINATION "share/applications"
    )
    # Shared MIME definition for .totm design bundles, so file managers
    # offer totm in Open With (and it can become the default). Distro
    # hooks refresh the databases on package install; `cmake --install`
    # to ~/.local needs manual update-mime-database/update-desktop-database.
    install(
        FILES "${PROJECT_SOURCE_DIR}/packaging/mime/totm.xml"
        DESTINATION "share/mime/packages"
    )
    # Maker guide for plug-ins, opened from Settings -> Plugin.
    # Credits page, opened from the sidebar Credits row above Settings.
    # Contributors page, linked from the credits page TOC.
    install(
        FILES
            "${PROJECT_SOURCE_DIR}/src/docs/PLUG_IN.html"
            "${PROJECT_SOURCE_DIR}/src/docs/CREDITS.html"
            "${PROJECT_SOURCE_DIR}/src/docs/CONTRIBUTORS.html"
            "${PROJECT_SOURCE_DIR}/src/docs/CHANGELOG.html"
        DESTINATION "share/doc/totm"
    )
endif()
