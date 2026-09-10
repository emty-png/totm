qt_add_executable(totm
    main.cpp
)

set_source_files_properties(
    qml/theme/AppTheme.qml
    qml/stores/TabState.qml
    qml/stores/ToolState.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(totm
    URI Totm
    VERSION 1.0
    SOURCES
        backend/library/LibraryStore.h
        backend/library/LibraryStore.cpp
        backend/settings/SettingsStore.h
        backend/settings/SettingsStore.cpp
        backend/video/VideoExporter.h
        backend/video/VideoExporter.cpp
        backend/video/AnimSampler.h
        backend/video/AnimSampler.cpp
    QML_FILES
        # Shell
        qml/Main.qml
        # Theme + stores (singletons)
        qml/theme/AppTheme.qml
        qml/stores/TabState.qml
        qml/stores/ToolState.qml
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
        # Canvas + snapping
        qml/components/editor/snap/SnapEngine.qml
        qml/components/editor/snap/SnapTargets.qml
        qml/components/editor/snap/SnapEdge.qml
        qml/components/editor/snap/SnapSpacing.qml
        qml/components/editor/snap/SnapCombinators.qml
        qml/components/editor/canvas/BezierMath.qml
        qml/components/editor/canvas/ShapeDrawTool.qml
        qml/components/editor/canvas/TextEditor.qml
        qml/components/editor/canvas/CanvasCamera.qml
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
        qml/components/editor/properties/PresetCard.qml
        qml/components/editor/properties/PresetGallery.qml
        qml/components/editor/properties/CustomGallery.qml
        qml/components/editor/properties/ClipCustomTransformOptions.qml
        qml/components/editor/properties/ClipCustomStyleOptions.qml
        qml/components/editor/properties/ClipCustomOtherOptions.qml
        qml/components/editor/properties/ClipPathOptions.qml
        qml/components/editor/properties/ShapeAnimationsPanel.qml
        qml/components/editor/properties/ClipEditor.qml
        qml/components/editor/properties/SegmentedOption.qml
        qml/components/editor/properties/ClipSlideOptions.qml
        qml/components/editor/properties/ClipSpinOptions.qml
        qml/components/editor/properties/ClipTimingOptions.qml
        qml/components/editor/properties/EasingGraph.qml
        qml/components/editor/properties/GraphEditorPopup.qml
        qml/components/editor/properties/PanelSection.qml
        qml/components/editor/properties/PanelIconButton.qml
        qml/components/editor/properties/PositionSection.qml
        qml/components/editor/properties/LayoutSection.qml
        qml/components/editor/properties/AppearanceSection.qml
        qml/components/editor/properties/FillSection.qml
        qml/components/editor/properties/StrokeSection.qml
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
        # Selection
        qml/components/selection/DragSelection.qml
        # Editor shell
        qml/components/editor/EditorLeftPanel.qml
        qml/components/editor/EditorRightPanel.qml
        qml/components/editor/EditorModeSwitcher.qml
        qml/components/editor/AnimateModeSwitcher.qml
        qml/components/editor/timeline/TimelineView.qml
        qml/components/editor/timeline/TimelineLane.qml
        qml/components/editor/timeline/TimelineRuler.qml
        qml/components/editor/timeline/TimelineTransport.qml
        qml/components/editor/EditorBottomPanel.qml
        qml/components/editor/EditorCanvas.qml
        qml/components/editor/properties/DesignPanel.qml
        # Fields
        qml/components/fields/NumberField.qml
        qml/components/fields/HexField.qml
        qml/components/fields/RenameField.qml
        qml/components/editor/shapes/ShapeItem.qml
        qml/components/editor/shapes/ShapeGeometry.qml
        qml/components/editor/shapes/TextGlyphs.qml
        qml/components/editor/SelectionHandles.qml
        # Layers (view + context)
        qml/components/editor/layers/LayersView.qml
        qml/components/editor/layers/LayersRow.qml
        qml/components/editor/layers/LayersContextMenu.qml
        # Menu (shared rows)
        qml/components/menu/MenuItem.qml
        qml/components/menu/ToolbarMenuItem.qml
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
        # Views (screen roots only)
        qml/views/home/HomeView.qml
        qml/views/editor/EditorView.qml
)

target_link_libraries(totm PRIVATE Qt6::Quick)

# Backend headers register QML types by basename (see the generated
# qmltyperegistrations.cpp), so each backend dir must be on the include path.
target_include_directories(totm PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/library
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/settings
    ${CMAKE_CURRENT_SOURCE_DIR}/backend/video
)

# Cross-platform desktop bundle settings.
# Linux: plain executable. Windows: no console window. macOS: .app bundle.
set_target_properties(totm PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}"
)
