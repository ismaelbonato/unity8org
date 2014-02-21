/*
 * Copyright (C) 2013 Canonical, Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.0
import Ubuntu.Components 0.1
import Utils 0.1
import Unity 0.2
import "../Components"
import "../Components/ListItems" as ListItems

FocusScope {
    id: scopeView

    property Scope scope
    property SortFilterProxyModel categories: categoryFilter
    property bool isCurrent
    property alias moving: categoryView.moving
    property int tabBarHeight: 0
    property PageHeader pageHeader: null
    property Item previewListView: null

    signal endReached
    signal movementStarted
    signal positionedAtBeginning

    property bool enableHeightBehaviorOnNextCreation: false
    property var categoryView: categoryView

    // FIXME delay the search so that daemons have time to settle, note that
    // removing this will break ScopeView::test_changeScope
    onScopeChanged: {
        if (scope) {
            timer.restart();
            scope.activateApplication.connect(activateApp);
        }
    }

    function activateApp(appId) {
        shell.activateApplication(appId);
    }

    Binding {
        target: scope
        property: "isActive"
        value: isCurrent && !previewListView.open
    }

    Timer {
        id: timer
        interval: 2000
        onTriggered: scope.searchQuery = ""
    }

    SortFilterProxyModel {
        id: categoryFilter
        model: scope ? scope.categories : null
        dynamicSortFilter: true
        filterRole: Categories.RoleCount
        filterRegExp: /^0$/
        invertMatch: true
    }

    onIsCurrentChanged: {
        pageHeader.resetSearch();
        previewListView.open = false;
    }

    onMovementStarted: categoryView.showHeader()

    onPositionedAtBeginning: categoryView.positionAtBeginning()

    Binding {
        target: scopeView.scope
        property: "searchQuery"
        value: pageHeader.searchQuery
        when: isCurrent
    }

    Binding {
        target: pageHeader
        property: "searchQuery"
        value: scopeView.scope.searchQuery
        when: isCurrent
    }

    Connections {
        target: panel
        onSearchClicked: if (isCurrent) {
            pageHeader.triggerSearch()
            categoryView.showHeader()
        }
    }

    Connections {
        target: scopeView.scope
        onShowDash: previewListView.open = false;
        onHideDash: previewListView.open = false;
    }

    ScopeListView {
        id: categoryView
        objectName: "categoryListView"
        anchors.fill: parent
        model: scopeView.categories
        forceNoClip: previewListView.open

        onAtYEndChanged: if (atYEnd) endReached()
        onMovingChanged: if (moving && atYEnd) endReached()

        property string expandedCategoryId: ""

        onContentYChanged: pageHeader.positionRealHeader();
        onOriginYChanged: pageHeader.positionRealHeader();
        onContentHeightChanged: pageHeader.positionRealHeader();

        Behavior on contentY {
            enabled: previewListView.open
            UbuntuNumberAnimation {}
        }

        delegate: ListItems.Base {
            id: baseItem
            objectName: "dashCategory" + category
            highlightWhenPressed: false
            showDivider: false

            readonly property bool expandable: rendererLoader.item ? rendererLoader.item.expandable : false
            readonly property bool filtered: rendererLoader.item ? rendererLoader.item.filter : true
            readonly property string category: categoryId
            readonly property var item: rendererLoader.item

            Image { 
                id: bottomGradient
                anchors {
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                }
                fillMode: Image.Stretch
                verticalAlignment: Image.AlignBottom
                source: "graphics/dash_divider_top_darkgrad.png"
                z: -1
            }

            Loader {
                id: rendererLoader
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }

                source: getRenderer(model.renderer, results)

                onLoaded: {
                    if (item.enableHeightBehavior !== undefined && item.enableHeightBehaviorOnNextCreation !== undefined) {
                        item.enableHeightBehavior = scopeView.enableHeightBehaviorOnNextCreation;
                        scopeView.enableHeightBehaviorOnNextCreation = false;
                    }
                    if (source.toString().indexOf("Apps/RunningApplicationsGrid.qml") != -1) {
                        // TODO: this is still a kludge :D Ideally add some kind of hook so that we
                        // can do this from DashApps.qml or think a better way that needs no special casing
                        item.firstModel = Qt.binding(function() { return mainStageApplicationsModel })
                        item.secondModel = Qt.binding(function() { return sideStageApplicationModel })
                        item.canEnableTerminationMode = Qt.binding(function() { return scopeView.isCurrent })
                    } else {
                        item.model = Qt.binding(function() { return results })
                    }
                    item.objectName = Qt.binding(function() { return categoryId })
                    if (item.expandable) {
                        var shouldFilter = categoryId != categoryView.expandedCategoryId;
                        if (shouldFilter != item.filter) {
                            item.filter = shouldFilter;
                        }
                    }
                    updateDelegateCreationRange();
                    // FIXME: should be "template", not "renderer"
                    item.template = Qt.binding(function() { return model.renderer });
                    item.components = Qt.binding(function() { return model.components });
                }

                Component.onDestruction: {
                    if (item.enableHeightBehavior !== undefined && item.enableHeightBehaviorOnNextCreation !== undefined) {
                        scopeView.enableHeightBehaviorOnNextCreation = item.enableHeightBehaviorOnNextCreation;
                    }
                }

                Connections {
                    target: rendererLoader.item
                    onClicked: {
                        // Prepare the preview in case activate() triggers a preview only
                        previewListView.model = target.model;
                        previewListView.currentIndex = -1
                        previewListView.currentIndex = index;

                        var item = target.model.get(index);

                        if (scopeView.scope.id === "scopes" || (scopeView.scope.id == "clickscope" && categoryId == "local")) {
                            scopeView.scope.activate(item.result)
                        } else {
                            previewListView.open = true
                        }
                    }
                    onPressAndHold: {
                        previewListView.model = target.model;
                        previewListView.currentIndex = -1
                        previewListView.currentIndex = index;
                        previewListView.open = true
                    }
                }
                Connections {
                    target: categoryView
                    onExpandedCategoryIdChanged: {
                        collapseAllButExpandedCategory();
                    }
                    function collapseAllButExpandedCategory() {
                        var item = rendererLoader.item;
                        if (item.expandable) {
                            var shouldFilter = categoryId != categoryView.expandedCategoryId;
                            if (shouldFilter != item.filter) {
                                // If the filter animation will be seen start it, otherwise, just flip the switch
                                var shrinkingVisible = shouldFilter && y + item.collapsedHeight < categoryView.height;
                                var growingVisible = !shouldFilter && y + height < categoryView.height;
                                if (!previewListView.open || !shouldFilter) {
                                    if (shrinkingVisible || growingVisible) {
                                        item.startFilterAnimation(shouldFilter)
                                    } else {
                                        item.filter = shouldFilter;
                                    }
                                    if (!shouldFilter && !previewListView.open) {
                                        categoryView.maximizeVisibleArea(index, item.uncollapsedHeight);
                                    }
                                }
                            }
                        }
                    }
                    onOriginYChanged: rendererLoader.updateDelegateCreationRange();
                    onContentYChanged: rendererLoader.updateDelegateCreationRange();
                    onHeightChanged: rendererLoader.updateDelegateCreationRange();
                    onContentHeightChanged: rendererLoader.updateDelegateCreationRange();
                }

                function updateDelegateCreationRange() {
                    // Do not update the range if we are overshooting up or down, since we'll come back
                    // to the stable position and delete/create items without any reason
                    if (categoryView.contentY < categoryView.originY) {
                        return;
                    } else if (categoryView.contentY + categoryView.height > categoryView.contentHeight) {
                        return;
                    }

                    if (item && item.hasOwnProperty("delegateCreationBegin")) {
                        if (baseItem.y + baseItem.height <= 0) {
                            // Not visible (item at top of the list)
                            item.delegateCreationBegin = baseItem.height
                            item.delegateCreationEnd = baseItem.height
                        } else if (baseItem.y >= categoryView.height) {
                            // Not visible (item at bottom of the list)
                            item.delegateCreationBegin = 0
                            item.delegateCreationEnd = 0
                        } else {
                            item.delegateCreationBegin = Math.max(-baseItem.y, 0)
                            item.delegateCreationEnd = Math.min(categoryView.height + item.delegateCreationBegin, baseItem.height)
                        }
                    }
                }
            }

            onHeightChanged: rendererLoader.updateDelegateCreationRange();
            onYChanged: rendererLoader.updateDelegateCreationRange();
        }

        sectionProperty: "name"
        sectionDelegate: ListItems.Header {
            objectName: "dashSectionHeader" + delegate.category
            property var delegate: categoryView.item(delegateIndex)
            width: categoryView.width
            text: section
            image: {
                if (delegate && delegate.expandable)
                    return delegate.filtered ? "graphics/header_handlearrow.png" : "graphics/header_handlearrow2.png"
                return "";
            }
            onClicked: {
                if (categoryView.expandedCategoryId != delegate.category)
                    categoryView.expandedCategoryId = delegate.category;
                else
                    categoryView.expandedCategoryId = "";
            }

            Image {
                id: topGradient
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                fillMode: Image.Stretch
                verticalAlignment: Image.AlignTop
                source: "graphics/dash_divider_top_lightgrad.png"
                z: -1
            }
        }
        pageHeader: Item {
            implicitHeight: scopeView.tabBarHeight
            onHeightChanged: {
                if (scopeView.pageHeader && scopeView.isCurrent) {
                    scopeView.pageHeader.height = height;
                }
            }
            onYChanged: positionRealHeader();

            function positionRealHeader() {
                if (scopeView.pageHeader && scopeView.isCurrent) {
                    scopeView.pageHeader.y = y + parent.y;
                }
            }
        }
    }

    function getRenderer(template, results) {
        var layout = template["category-layout"];

        if (layout == "running-apps") {
            return "Apps/RunningApplicationsGrid.qml";
        }

        if (layout === "carousel") {
            // TODO: Selectively disable carousel, 4 is fixed for now, should change depending on form factor
            if (results.count <= 4) layout = "grid";
        }
        switch (layout) {
            case "carousel": return "CardCarousel.qml";
            case "grid":
            default: return "CardFilterGrid.qml";
        }
    }
}
