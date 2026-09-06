qt_add_executable(totm
    main.cpp
)

set_source_files_properties(
    qml/theme/AppTheme.qml
    qml/stores/TabStore.qml
    qml/stores/ToolStore.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(totm
    URI Totm
    VERSION 1.0
    SOURCES
        backend/library/LibraryStore.h
        backend/library/LibraryStore.cpp
    QML_FILES
        # Shell
        qml/Main.qml
        # Theme + stores (singletons)
        qml/theme/AppTheme.qml
        qml/stores/TabStore.qml
        qml/stores/ToolStore.qml
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
        # Canvas + snapping
        qml/components/editor/SnapEngine.qml
        qml/components/editor/snap/SnapTargets.qml
        qml/components/editor/snap/SnapEdge.qml
        qml/components/editor/snap/SnapSpacing.qml
        qml/components/editor/snap/SnapCombinators.qml
        qml/components/editor/canvas/CanvasCamera.qml
        qml/components/editor/canvas/CanvasSelectPolicy.qml
        qml/components/editor/canvas/CanvasResizePolicy.qml
        qml/components/editor/canvas/ShapeLayer.qml
        qml/components/editor/canvas/CanvasOverlays.qml
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
        qml/components/editor/properties/GeometrySection.qml
        qml/components/editor/properties/FillSection.qml
        qml/components/editor/properties/StrokeSection.qml
        qml/components/editor/properties/StyleSection.qml
        # Titlebar + window
        qml/components/titlebar/TitleBar.qml
        qml/components/titlebar/TitleBarTabBar.qml
        qml/components/titlebar/TitleBarTab.qml
        qml/components/titlebar/TitleBarHomeTab.qml
        qml/components/titlebar/TitleBarButton.qml
        qml/components/titlebar/TitleBarControls.qml
        qml/components/titlebar/TitleBarDragArea.qml
        qml/components/titlebar/TitleBarIcon.qml
        qml/components/window/WindowResizeHandles.qml
        # Selection
        qml/components/selection/DragSelectionBox.qml
        qml/components/selection/DragSelection.qml
        # Editor shell
        qml/components/editor/EditorLeftPanel.qml
        qml/components/editor/EditorRightPanel.qml
        qml/components/editor/EditorModeSwitcher.qml
        qml/components/editor/EditorBottomPanel.qml
        qml/components/editor/EditorCanvas.qml
        qml/components/editor/properties/DesignPanel.qml
        # Fields
        qml/components/fields/NumberField.qml
        qml/components/fields/HexField.qml
        qml/components/fields/RenameField.qml
        qml/components/editor/shapes/ShapeItem.qml
        qml/components/editor/SelectionHandles.qml
        # Layers (view + context)
        qml/components/editor/layers/LayersView.qml
        qml/components/editor/layers/LayersRow.qml
        qml/components/editor/layers/ContextMenuItem.qml
        qml/components/editor/layers/LayersContextMenu.qml
        # Toolbar
        qml/components/toolbar/CanvasToolbar.qml
        qml/components/toolbar/ToolbarButton.qml
        qml/components/toolbar/ToolbarMenuItem.qml
        # Views
        qml/views/home/HomeView.qml
        qml/views/home/HomeSideBar.qml
        qml/views/home/WorkspaceRow.qml
        qml/views/home/DesignCard.qml
        qml/views/home/DesignCardPreview.qml
        qml/views/home/DesignContextMenu.qml
        qml/views/editor/EditorView.qml
)

target_link_libraries(totm PRIVATE Qt6::Quick)

# Backend headers register QML types by basename (see the generated
# qmltyperegistrations.cpp), so backend/library/ must be on the include path.
target_include_directories(totm PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/backend/library)

# Cross-platform desktop bundle settings.
# Linux: plain executable. Windows: no console window. macOS: .app bundle.
set_target_properties(totm PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}"
)
