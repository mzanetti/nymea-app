import QtQuick 2.4
import QtQuick.Controls 2.1
import QtQuick.Layouts 1.1
import "qrc:/ui/components"
import Nymea 1.0

Page {
    id: root

    header: NymeaHeader {
        text: qsTr("ZigBee network topology")
        backButtonVisible: true
        onBackPressed: pageStack.pop()
        HeaderButton {
            imageSource: "/ui/images/help.svg"
            text: qsTr("Help")
            onClicked: {
                var popup = zigbeeHelpDialog.createObject(app)
                popup.open()
            }
        }
    }

    property ZigbeeManager zigbeeManager: null
    property ZigbeeNetwork network: null

    readonly property int nodeDistance: Style.iconSize * 2
    readonly property int nodeSize: Style.iconSize + Style.margins
    readonly property double scale: 1


    Component.onCompleted: {
        zigbeeManager.refreshNeighborTables(network.networkUuid)

        reload();
        for (var i = 0; i < network.nodes.count; i++) {
            network.nodes.get(i).neighborsChanged.connect(root.reload)
        }
    }
    Component.onDestruction: {
        for (var i = 0; i < network.nodes.count; i++) {
            network.nodes.get(i).neighborsChanged.disconnect(root.reload)
        }
    }

    Connections {
        target: root.network.nodes
        onNodeAdded: {
            root.reload()
            node.neighborsChanged.connect(root.reload);
        }
    }

    function generateNodeList() {
        var nodeItems = []
        var coordinator = {}
        var routers = []
        var endDevices = []
        for (var i = 0; i < root.network.nodes.count; i++) {
            var node = root.network.nodes.get(i);
            switch (node.type) {
            case ZigbeeNode.ZigbeeNodeTypeRouter:
                routers.push(node)
                break;
            case ZigbeeNode.ZigbeeNodeTypeEndDevice:
                endDevices.push(node);
                break;
            case ZigbeeNode.ZigbeeNodeTypeCoordinator:
                coordinator = node;
                break;
            }
        }

        var startAngle = -90

        var routersCircumference = Math.max(5, routers.length) * (root.nodeSize + root.nodeDistance) * root.scale
        var distanceFromCenter = routersCircumference / 2 / Math.PI

        routers.unshift(coordinator)

        var handledEndDevices = []

        var angle = 360 / routers.length;
        for (var i = 0; i < routers.length; i++) {
            var router = routers[i]
            var nodeAngle = startAngle + angle * i;
            var x = distanceFromCenter * Math.cos(nodeAngle * Math.PI / 180)
            var y = distanceFromCenter * Math.sin(nodeAngle * Math.PI / 180)
            nodeItems.push(createNodeItem(routers[i], x, y, nodeAngle));


            var neighborCounter = 0;
            for (var j = 0; j < router.neighbors.length; j++) {
                var neighborNode = root.network.nodes.getNodeByNetworkAddress(router.neighbors[j].networkAddress)
                if (!neighborNode) {
                    continue
                }

                if (neighborNode.type == ZigbeeNode.ZigbeeNodeTypeEndDevice) {
                    if (handledEndDevices.indexOf(neighborNode.networkAddress) >= 0) {
                        continue;
                    }
                    handledEndDevices.push(neighborNode.networkAddress)

                    var neighborAngle  = nodeAngle + neighborCounter * 8
                    var neighborDistance = (distanceFromCenter + root.nodeDistance + root.nodeSize) * root.scale + neighborCounter * root.nodeDistance * .5 * root.scale

                    x = neighborDistance * Math.cos(neighborAngle * Math.PI / 180)
                    y = neighborDistance * Math.sin(neighborAngle * Math.PI / 180)
                    nodeItems.push(createNodeItem(neighborNode, x, y, angle))

                    neighborCounter++
                }
            }
        }

        var unconnectedNodes = []
        for (var i = 0; i < network.nodes.count; i++) {
            var node = network.nodes.get(i)
            if (node.type == ZigbeeNode.ZigbeeNodeTypeEndDevice && handledEndDevices.indexOf(node.networkAddress) < 0) {
                print("Adding unconnected node:","0x" + node.networkAddress.toString(16))
                unconnectedNodes.push(node)
            }
        }
        var cellWidth = root.nodeSize * 2
        var cellHeight = root.nodeSize * 2
        var maxColumns = (root.width - Style.bigMargins * 2) / cellWidth
        var columns = Math.min(unconnectedNodes.length, maxColumns)
        var rowWidth = columns * cellWidth
        print("columns:", columns, "maxCols", maxColumns)
        for (var i = 0; i < unconnectedNodes.length; i++) {
            var node = unconnectedNodes[i]
            var column = i % columns;
            var row = Math.floor(i / columns)
            var x = cellWidth * column + cellWidth / 2 - rowWidth / 2
            var y = Style.margins + cellHeight * row + root.nodeSize - canvas.height / 2
            nodeItems.push(createNodeItem(node, x, y, 0))
        }
        d.nodeItems = nodeItems
    }


    function createNodeItem(node, x, y, angle) {
        d.adjustSize(x, y)

        for (var i = 0; i < d.nodeItems.length; i++) {
            if (d.nodeItems[i].node == node) {
                d.nodeItems[i].x = x;
                d.nodeItems[i].y = y;
                d.nodeItems[i].angle = angle;
                return d.nodeItems[i]
            }
        }

        var icon = "/ui/images/zigbee.svg"
        var thing = null
        if (node.networkAddress == 0) {
            icon = "qrc:/styles/%1/logo.svg".arg(styleController.currentStyle)
        } else {
            for (var i = 0; i < engine.thingManager.things.count; i++) {
                var t = engine.thingManager.things.get(i)
                //                print("checking thing", t.name)
                var param = t.paramByName("ieeeAddress")
                if (param && param.value == node.ieeeAddress) {
                    thing = t;
                    break;
                }
            }
        }

        if (thing) {
            icon = app.interfacesToIcon(thing.thingClass.interfaces)
        }

        var nodeItem = {
            node: node,
            x: x,
            y: y,
            edges: [],
            image: imageComponent.createObject(canvas, {
                                                   x: Qt.binding(function() { return x + (canvas.width - Style.iconSize) / 2}),
                                                   y: Qt.binding(function() { return y + (canvas.height - Style.iconSize) / 2}),
                                                   name: icon,
                                                   color: Style.accentColor
                                               }),
            thing: thing

        }
        //        print("creared node", thing ? thing.name : "", " at", x, y)
        return nodeItem
    }

    function reload() {
        print("Reloading network map")
        while (d.nodeItems.length > 0) {
            var nodeItem = d.nodeItems.shift()
            nodeItem.image.destroy();
        }
        generateNodeList();
        canvas.requestPaint()
        print("repainting", flickable.contentX, flickable.contentY)
        if (flickable.contentX == 0 && flickable.contentY == 0) {
            flickable.contentX = (flickable.contentWidth - flickable.width) / 2
            flickable.contentY = (flickable.contentHeight - flickable.height) / 2
        }
    }

    QtObject {
        id: d
        property var nodeItems: []

        property int selectedNodeAddress: -1
        readonly property var selectedNodeItem: {
            for (var i = 0; i < nodeItems.length; i++) {
                if (nodeItems[i].node.networkAddress === selectedNodeAddress) {
                    return nodeItems[i]
                }
            }
            return null
        }

        readonly property ZigbeeNode selectedNode: selectedNodeAddress >= 0 ? network.nodes.getNodeByNetworkAddress(selectedNodeAddress) : null

        property int minX: 0
        property int minY: 0
        property int maxX: 0
        property int maxY: 0
        property int size: 0

        function adjustSize(x, y) {
            minX = Math.min(minX, x)
            minY = Math.min(minY, y)
            maxX = Math.max(maxX, x)
            maxY = Math.max(maxY, y)
            var minWidth = Math.max(-minX, maxX) * 2
            var minHeight = Math.max(-minY, maxY) * 2
            size = Math.max(minWidth, minHeight) + root.nodeSize * 2
        }

    }

    Component {
        id: imageComponent
        ColorIcon {
        }
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        clip: true

        contentWidth: canvas.width
        contentHeight: canvas.height

        Canvas {
            id: canvas
            width: Math.max(d.size, flickable.width)
            height: Math.max(d.size, flickable.height)
            clip: true

            onPaint: {
                //                print("**** height:", canvas.height, "width", canvas.width)
                var ctx = getContext("2d");
                ctx.reset();

                var center = { x: canvas.width / 2, y: canvas.height / 2 };
                ctx.translate(center.x, center.y)

                paintNodeList(ctx);
            }

            function paintNodeList(ctx) {
                for (var i = 0; i < d.nodeItems.length; i++) {
                    paintEdges(ctx, d.nodeItems[i], false)
                }
                for (var i = 0; i < d.nodeItems.length; i++) {
                    paintEdges(ctx, d.nodeItems[i], true)
                }
                if (d.selectedNodeItem) {
                    paintRoute(ctx, d.selectedNodeItem)
                }
                for (var i = 0; i < d.nodeItems.length; i++) {
                    paintNode(ctx, d.nodeItems[i])
                }
            }

            function paintRoute(ctx, nodeItem) {
                var node = nodeItem.node
                var nextHop = -1
                if (node.type === ZigbeeNode.ZigbeeNodeTypeRouter) {
                    for (var i = 0; i < node.routes.length; i++) {
                        if (node.routes[i].destinationAddress === 0) {
                            nextHop = node.routes[i].nextHopAddress
                            break;
                        }
                    }
                } else if (node.type === ZigbeeNode.ZigbeeNodeTypeEndDevice) {
                    for (var i = 0; i < network.nodes.count; i++) {
                        for (var j = 0; j < network.nodes.get(i).neighbors.length; j++) {
                            if (network.nodes.get(i).neighbors[j].networkAddress === node.networkAddress) {
                                nextHop = network.nodes.get(i).networkAddress
                                break;
                            }
                        }
                    }
                }

                print("next hop", nextHop)
                if (nextHop == -1) {
                    return;
                }
                var toNodeItem = null
                for (var i = 0; i < d.nodeItems.length; i++) {
                    if (d.nodeItems[i].node.networkAddress == nextHop) {
                        toNodeItem = d.nodeItems[i]
                        break;
                    }
                }
                if (!toNodeItem) {
                    return;
                }

                ctx.save()

                ctx.lineWidth = 2
                ctx.setLineDash([4, 4])
                ctx.strokeStyle = Style.blue

                ctx.beginPath();
                ctx.moveTo(scale * nodeItem.x, scale * nodeItem.y)
                ctx.lineTo(scale * toNodeItem.x, scale * toNodeItem.y)

                ctx.stroke();
                ctx.closePath()
                ctx.setLineDash([1,0])
                ctx.restore();

                paintRoute(ctx, toNodeItem)

            }

            function paintEdges(ctx, nodeItem, selected) {
                for (var i = 0; i < nodeItem.node.neighbors.length; i++) {
                    var neighbor = nodeItem.node.neighbors[i]
                    //                print("ege from", nodeItem.node.networkAddress, "to", neighbor, "LQI", neighbor.lqi, "depth:", neighbor.depth)
                    for (var k = 0; k < d.nodeItems.length; k++) {
                        if (d.nodeItems[k].node.networkAddress == neighbor.networkAddress) {
                            var toNodeItem = d.nodeItems[k]
                            if (nodeItem.node.networkAddress === d.selectedNodeAddress || toNodeItem.node.networkAddress === d.selectedNodeAddress) {
                                if (selected) {
                                    paintEdge(ctx, nodeItem, d.nodeItems[k], neighbor.lqi, true)
                                }
                            } else {
                                if (!selected) {
                                    paintEdge(ctx, nodeItem, d.nodeItems[k], neighbor.lqi, false)
                                }
                            }
                            continue
                        }
                    }
                }
            }

            function paintNode(ctx, nodeItem) {
                ctx.save()
                ctx.beginPath();
                ctx.fillStyle = nodeItem.node.networkAddress === d.selectedNodeAddress ? Style.tileOverlayColor : Style.tileBackgroundColor
                ctx.strokeStyle = nodeItem.node.networkAddress === d.selectedNodeAddress ? Style.accentColor : Style.tileBackgroundColor
                ctx.arc(root.scale * nodeItem.x, root.scale * nodeItem.y, root.scale * root.nodeSize / 2, 0, 2 * Math.PI);
                ctx.fill();
                //                ctx.stroke();
                ctx.fillStyle = Style.foregroundColor
                ctx.font = "" + Style.extraSmallFont.pixelSize + "px Ubuntu";
                var text = ""
                if (nodeItem.thing) {
                    text = nodeItem.thing.name
                } else {
                    text = nodeItem.node.model
                }
                if (text.length > 10) {
                    text = text.substring(0, 9) + "…"
                }

                var textSize = ctx.measureText(text)
                //            ctx.fillText(text, scale * (nodeItem.x ), scale * (nodeItem.y ))
                ctx.fillText(text, scale * (nodeItem.x - textSize.width / 2), scale * (nodeItem.y + root.nodeSize / 2 + Style.extraSmallFont.pixelSize))

                ctx.closePath();

                ctx.restore();
            }

            function paintEdge(ctx, fromNodeItem, toNodeItem, lqi, selected) {
                ctx.save()
                var percent = lqi / 255;
                var goodColor = Style.green
                var badColor = Style.red
                var resultRed = goodColor.r + percent * (badColor.r - goodColor.r);
                var resultGreen = goodColor.g + percent * (badColor.g - goodColor.g);
                var resultBlue = goodColor.b + percent * (badColor.b - goodColor.b);

                if (selected) {
                    ctx.lineWidth = 2
                    ctx.strokeStyle = Qt.rgba(resultRed, resultGreen, resultBlue, 1)
                } else {
                    ctx.lineWidth = 1
                    var alpha = d.selectedNodeAddress >= 0 ? .2 : 1
                    ctx.strokeStyle = Qt.rgba(resultRed, resultGreen, resultBlue, alpha)
                }
                ctx.beginPath();
                ctx.moveTo(scale * fromNodeItem.x, scale * fromNodeItem.y)
                ctx.lineTo(scale * toNodeItem.x, scale * toNodeItem.y)

                ctx.stroke();

                ctx.closePath()
                ctx.restore();
            }

            MouseArea {
                anchors.fill: parent

                onClicked: {
                    print("clicked:", mouseX, mouseY)
                    var translatedMouseX = mouseX - canvas.width / 2
                    var translatedMouseY = mouseY - canvas.height / 2
                    d.selectedNodeAddress = -1
                    for (var i = 0; i < d.nodeItems.length; i++) {
                        var nodeItem = d.nodeItems[i]
                        //                    print("nodeItem at:", root.scale * nodeItem.x, root.scale * nodeItem.y)
                        if (Math.abs(root.scale * nodeItem.x - translatedMouseX) < (root.scale * root.nodeSize / 2)
                                && Math.abs(root.scale * nodeItem.y - translatedMouseY) < (root.scale * root.nodeSize / 2)) {
                            d.selectedNodeAddress = nodeItem.node.networkAddress;
                            print("selecting", nodeItem.node.networkAddress)
                            for (var j = 0; j < nodeItem.node.routes.length; j++) {
                                var route = nodeItem.node.routes[j]
                                print("route:", route.destinationAddress, "via", route.nextHopAddress)
                            }
                        }
                    }

                    canvas.requestPaint();
                }
            }
        }
    }


    BigTile {
        id: infoTile
        visible: d.selectedNodeAddress >= 0
        anchors {
            top: parent.top
            right: parent.right
            margins: Style.smallMargins
        }

        width: 260
        header: RowLayout {
            width: parent.width - Style.smallMargins
            spacing: Style.smallMargins
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                ThingsProxy {
                    id: selectedThingsProxy
                    engine: _engine
                    paramsFilter: {"ieeeAddress": d.selectedNode ? d.selectedNode.ieeeAddress : "---"}
                }

                text: d.selectedNodeAddress < 0
                      ? ""
                      : d.selectedNodeAddress === 0
                        ? Configuration.systemName
                        : selectedThingsProxy.count > 0
                          ? selectedThingsProxy.get(0).name
                          : network.nodes.getNodeByNetworkAddress(d.selectedNode).model
            }

            ColorIcon {
                size: Style.smallIconSize
                name: {
                    if (!d.selectedNode) {
                        return "";
                    }

                    var signalStrength = 100.0 * d.selectedNode.lqi / 255
                    if (!d.selectedNode.reachable)
                        return "/ui/images/connections/nm-signal-00.svg"
                    if (signalStrength <= 25)
                        return "/ui/images/connections/nm-signal-25.svg"
                    if (signalStrength <= 50)
                        return "/ui/images/connections/nm-signal-50.svg"
                    if (signalStrength <= 75)
                        return "/ui/images/connections/nm-signal-75.svg"
                    if (signalStrength <= 100)
                        return "/ui/images/connections/nm-signal-100.svg"
                }
            }
        }

        contentItem: ColumnLayout {
            width: infoTile.width
            SelectionTabs {
                id: infoSelectionTabs
                Layout.fillWidth: true
                color: Style.tileOverlayColor
                selectionColor: Qt.tint(Style.tileOverlayColor, Qt.rgba(Style.foregroundColor.r, Style.foregroundColor.g, Style.foregroundColor.b, 0.1))
                model: ListModel {
                    ListElement {
                        text: qsTr("Device")
                    }
                    ListElement {
                        text: qsTr("Links")
                    }
                    ListElement {
                        text: qsTr("Routes")
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                visible: infoSelectionTabs.currentIndex == 0
                columns: 2
                columnSpacing: Style.smallMargins

                Label {
                    text: qsTr("Address:")
                    font: Style.smallFont
                    Layout.fillWidth: true
                }
                Label {
                    text: d.selectedNode ? "0x" + d.selectedNode.networkAddress.toString(16) : ""
                    font: Style.smallFont
                    horizontalAlignment: Text.AlignRight
                    Layout.fillWidth: true
                }
                Label {
                    text: qsTr("Model:")
                    font: Style.smallFont
                    Layout.fillWidth: true
                }
                Label {
                    text: d.selectedNode ? d.selectedNode.model : ""
                    font: Style.smallFont
                    horizontalAlignment: Text.AlignRight
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Label {
                    text: qsTr("Manufacturer:")
                    font: Style.smallFont
                    Layout.fillWidth: true
                }
                Label {
                    text: d.selectedNode ? d.selectedNode.manufacturer : ""
                    font: Style.smallFont
                    horizontalAlignment: Text.AlignRight
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Label {
                    text: qsTr("Last seen:")
                    font: Style.smallFont
                    Layout.fillWidth: true
                }
                Label {
                    text: d.selectedNode ? d.selectedNode.lastSeen.toLocaleString(Qt.locale(), Locale.ShortFormat) : ""
                    font: Style.smallFont
                    horizontalAlignment: Text.AlignRight
                    Layout.fillWidth: true
                }
            }

            ColumnLayout {
                visible: infoSelectionTabs.currentIndex == 1
                RowLayout {
                    Label {
                        text: qsTr("Neighbor")
                        font: Style.smallFont
                        Layout.fillWidth: true
                    }
                    ColorIcon {
                        size: Style.smallIconSize
                        name: "connections/nm-signal-50"
                    }
                    ColorIcon {
                        size: Style.smallIconSize
                        name: "zigbee/zigbee-router"
                    }
                    Item {
                        Layout.preferredWidth: Style.smallIconSize + Style.smallMargins
                        Layout.fillHeight: true
                        ColorIcon {
                            anchors.centerIn: parent
                            size: Style.smallIconSize
                            name: "arrow-down"
                        }
                    }

                    ColorIcon {
                        size: Style.smallIconSize
                        name: "add"
                    }
                }
                ThinDivider {
                    color: Style.foregroundColor
                }

                ListView {
                    id: neighborTableListView
                    Layout.fillWidth: true
                    //            spacing: app.margins
                    implicitHeight: Math.min(root.height / 4, count * Style.smallIconSize)
                    clip: true
                    model: d.selectedNode ? d.selectedNode.neighbors.length : 0

                    delegate: RowLayout {
                        id: neighborTableDelegate
                        width: neighborTableListView.width
                        property ZigbeeNodeNeighbor neighbor: d.selectedNode.neighbors[index]
                        property ZigbeeNode neighborNode: root.network.nodes.getNodeByNetworkAddress(neighbor.networkAddress)
                        property Thing neighborNodeThing: {
                            for (var i = 0; i < engine.thingManager.things.count; i++) {
                                var thing = engine.thingManager.things.get(i)
                                var param = thing.paramByName("ieeeAddress")
                                if (param && param.value == neighborNode.ieeeAddress) {
                                    return thing
                                }
                            }
                            return null
                        }

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font: Style.smallFont
                            text: neighborTableDelegate.neighbor.networkAddress === 0
                                  ? Configuration.systemName
                                  : neighborTableDelegate.neighborNodeThing
                                    ? neighborTableDelegate.neighborNodeThing.name
                                    : neighborTableDelegate.neighborNode
                                      ? neighborTableDelegate.neighborNode.model
                                      : "0x" + neighborTableDelegate.neighbor.networkAddress.toString(16)
                            color: neighborTableDelegate.neighborNode ? Style.foregroundColor : Style.red
                        }
                        Label {
                            text: (neighborTableDelegate.neighbor.lqi * 100 / 255).toFixed(0) + "%"
                            font: Style.smallFont
                            horizontalAlignment: Text.AlignRight
                        }
                        ColorIcon {
                            size: Style.smallIconSize
                            name: {
                                switch (neighborTableDelegate.neighbor.relationship) {
                                case ZigbeeNode.ZigbeeNodeRelationshipChild:
                                    return "zigbee/zigbee-child"
                                case ZigbeeNode.ZigbeeNodeRelationshipParent:
                                    return "zigbee/zigbee-parent"
                                case ZigbeeNode.ZigbeeNodeRelationshipSibling:
                                    return "zigbee/zigbee-sibling"
                                case ZigbeeNode.ZigbeeNodeRelationshipPreviousChild:
                                    return "zigbee/zigbee-previous-child"
                                }
                                return ""
                            }
                        }

                        Label {
                            Layout.preferredWidth: Style.smallIconSize + Style.smallMargins
                            font: Style.smallFont
                            text: neighborTableDelegate.neighbor.depth
                            horizontalAlignment: Text.AlignRight
                        }
                        Item {
                            Layout.preferredWidth: Style.smallIconSize
                            Layout.preferredHeight: Style.smallIconSize

                            Led {
                                anchors.fill: parent
                                anchors.margins: Style.smallIconSize / 4
                                state: neighborTableDelegate.neighbor.permitJoining ? "on" : "off"
                            }
                        }

                    }
                }

            }
            ColumnLayout {
                visible: infoSelectionTabs.currentIndex == 2
                RowLayout {
                    Label {
                        id: toLabel
                        text: qsTr("To")
                        font: Style.smallFont
                        Layout.fillWidth: true
                    }
                    Label {
                        id: viaLabel
                        text: qsTr("Via")
                        font: Style.smallFont
                        Layout.fillWidth: true
                    }
                    ColorIcon {
                        size: Style.smallIconSize
                        name: "transfer-progress"
                    }
                }
                ThinDivider {
                    color: Style.foregroundColor
                }
                ListView {
                    id: routesListView
                    Layout.fillWidth: true
                    implicitHeight: Math.min(root.height / 4, count * Style.smallIconSize)
                    clip: true
                    model: d.selectedNode ? d.selectedNode.routes.length : 0

                    delegate: RowLayout {
                        id: routesTableDelegate
                        width: routesListView.width
                        property ZigbeeNodeRoute route: d.selectedNode.routes[index]
                        property ZigbeeNode destinationNode: root.network.nodes.getNodeByNetworkAddress(route.destinationAddress)
                        property Thing destinationNodeThing: {
                            for (var i = 0; i < engine.thingManager.things.count; i++) {
                                var thing = engine.thingManager.things.get(i)
                                var param = thing.paramByName("ieeeAddress")
                                if (param && param.value == destinationNode.ieeeAddress) {
                                    return thing
                                }
                            }
                            return null
                        }
                        property ZigbeeNode nextHopNode: root.network.nodes.getNodeByNetworkAddress(route.nextHopAddress)
                        property Thing nextHopNodeThing: {
                            for (var i = 0; i < engine.thingManager.things.count; i++) {
                                var thing = engine.thingManager.things.get(i)
                                var param = thing.paramByName("ieeeAddress")
                                if (param && param.value == nextHopNode.ieeeAddress) {
                                    return thing
                                }
                            }
                            return null
                        }

                        Label {
                            Layout.preferredWidth: toLabel.width
                            elide: Text.ElideRight
                            font: Style.smallFont
                            text: routesTableDelegate.route.destinationAddress === 0
                                  ? Configuration.systemName
                                  : routesTableDelegate.destinationNodeThing
                                    ? routesTableDelegate.destinationNodeThing.name
                                    : routesTableDelegate.destinationNode
                                      ? routesTableDelegate.destinationNode.model
                                      : "0x" + routesTableDelegate.route.destinationAddress.toString(16)
                        }
                        Label {
                            Layout.preferredWidth: viaLabel.width
                            elide: Text.ElideRight
                            font: Style.smallFont
                            text: routesTableDelegate.route.nextHopAddress === 0
                                  ? Configuration.systemName
                                  : routesTableDelegate.nextHopNodeThing
                                    ? routesTableDelegate.nextHopNodeThing.name
                                    : routesTableDelegate.nextHopNode
                                      ? routesTableDelegate.nextHopNode.model
                                      : "0x" + routesTableDelegate.route.nextHopAddress.toString(16)
                        }
                        ColorIcon {
                            name: {
                                switch (routesTableDelegate.route.status) {
                                case ZigbeeNode.ZigbeeNodeRouteStatusActive:
                                    return "tick"
                                case ZigbeeNode.ZigbeeNodeRouteStatusDiscoveryFailed:
                                    return "dialog-error-symbolic"
                                case ZigbeeNode.ZigbeeNodeRouteStatusDiscoveryUnderway:
                                    return "find"
                                case ZigbeeNode.ZigbeeNodeRouteStatusInactive:
                                    return "dialog-warning-symbolic"
                                case ZigbeeNode.ZigbeeNodeRouteStatusValidationUnderway:
                                    return "system-update"
                                }
                            }
                            size: Style.smallIconSize
                            color: routesTableDelegate.route.memoryConstrained ? Style.orange : Style.foregroundColor
                        }
                    }
                }
            }
        }
    }

    Component {
        id: zigbeeHelpDialog

        MeaDialog {
            id: dialog
            title: qsTr("ZigBee topology help")

            Flickable {
                implicitHeight: helpColumn.implicitHeight
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: helpColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: helpColumn
                    width: parent.width

                    ListSectionHeader {
                        text: qsTr("Map")
                    }
                    RowLayout {
                        ColumnLayout {
                            Layout.preferredWidth: Style.iconSize
                            Rectangle {
                                Layout.fillWidth: true
                                height: 2
                                color: Style.green
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 2
                                color: Style.orange
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 2
                                color: Style.red
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Links between nodes")
                        }
                    }
                    RowLayout {
                        ColumnLayout {
                            Layout.preferredWidth: Style.iconSize
                            Rectangle {
                                Layout.fillWidth: true
                                height: 2
                                color: Style.blue
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Route to coordinator")
                        }
                    }

                    ListSectionHeader {
                        text: qsTr("Links")
                    }


                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            size: Style.iconSize
                            name: "zigbee/zigbee-coordinator"
                        }

                        Label {
                            text: qsTr("Node relationship")
                        }
                    }

                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "zigbee/zigbee-sibling"
                        }

                        Label {
                            text: qsTr("Sibling")
                        }
                    }
                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "zigbee/zigbee-parent"
                        }

                        Label {
                            text: qsTr("Parent")
                        }
                    }
                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "zigbee/zigbee-child"
                        }

                        Label {
                            text: qsTr("Child")
                        }
                    }

                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "zigbee/zigbee-previous-child"
                        }

                        Label {
                            text: qsTr("Previous child")
                        }
                    }

                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "/ui/images/arrow-down.svg"
                        }

                        Label {
                            text: qsTr("Depth in network")
                        }
                    }
                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "add"
                        }

                        Label {
                            text: qsTr("Permit join")
                        }
                    }

                    ListSectionHeader {
                        text: qsTr("Routes")
                    }

                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "transfer-progress"
                        }

                        Label {
                            text: qsTr("Route status")
                        }
                    }

                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "tick"
                        }

                        Label {
                            text: qsTr("Route active")
                        }
                    }
                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "dialog-warning-symbolic"
                        }

                        Label {
                            text: qsTr("Route inactive")
                        }
                    }
                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "dialog-error-symbolic"
                        }

                        Label {
                            text: qsTr("Route failed")
                        }
                    }
                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "find"
                        }

                        Label {
                            text: qsTr("Discovery in progress")
                        }
                    }
                    RowLayout {
                        spacing: Style.margins
                        ColorIcon {
                            Layout.preferredHeight: Style.iconSize
                            Layout.preferredWidth: Style.iconSize
                            name: "system-update"
                        }

                        Label {
                            text: qsTr("Validation in progress")
                        }
                    }
                }
            }
        }
    }
}
