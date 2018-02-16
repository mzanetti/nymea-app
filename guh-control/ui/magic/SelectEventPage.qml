import QtQuick 2.4
import QtQuick.Controls 2.1
import "../components"
import Guh 1.0

Page {
    id: root
    property alias text: header.text

    // an eventDescriptor object needs to be set and prefilled with either deviceId or interfaceName
    property var eventDescriptor: null

    readonly property var device: eventDescriptor && eventDescriptor.deviceId ? Engine.deviceManager.devices.getDevice(eventDescriptor.deviceId) : null
    readonly property var deviceClass: device ? Engine.deviceManager.deviceClasses.getDeviceClass(device.deviceClassId) : null

    signal backPressed();
    signal done();

    onEventDescriptorChanged: buildInterface()
    Component.onCompleted: buildInterface()

    header: GuhHeader {
        id: header
        onBackPressed: root.backPressed();

        property bool interfacesMode: true
        onInterfacesModeChanged: root.buildInterface()

        HeaderButton {
            imageSource: header.interfacesMode ? "../images/view-expand.svg" : "../images/view-collapse.svg"
            onClicked: header.interfacesMode = !header.interfacesMode
        }
    }

    ListModel {
        id: eventTemplateModel
        ListElement { interfaceName: "temperaturesensor"; text: "When it's freezing..."; event: "freeze"}
        ListElement { interfaceName: "battery"; text: "When the device runs out of battery..."; event: "lowBattery"}
        ListElement { interfaceName: "weather"; text: "When it starts raining..."; event: "rain" }
    }

    function buildInterface() {
        actualModel.clear()

        if (header.interfacesMode) {
            if (root.device) {
                print("device supports interfaces", deviceClass.interfaces)
                for (var i = 0; i < eventTemplateModel.count; i++) {
                    print("event is for interface", eventTemplateModel.get(i).interfaceName)
                    if (deviceClass.interfaces.indexOf(eventTemplateModel.get(i).interfaceName) >= 0) {
                        actualModel.append(eventTemplateModel.get(i))
                    }
                }
            } else if (root.eventDescriptor.interfaceName !== "") {
                for (var i = 0; i < eventTemplateModel.count; i++) {
                    if (eventTemplateModel.get(i).interfaceName === root.eventDescriptor.interfaceName) {
                        actualModel.append(eventTemplateModel.get(i))
                    }
                }
            } else {
                console.warn("You need to set device or interfaceName");
            }
        } else {
            if (root.device) {
                print("fdsfasdfdsafdas", deviceClass.eventTypes.count)
                for (var i = 0; i < deviceClass.eventTypes.count; i++) {
                    print("bla", deviceClass.eventTypes.get(i).name, deviceClass.eventTypes.get(i).displayName)
                    actualModel.append({text: deviceClass.eventTypes.get(i).displayName})
                }
            }
        }
    }

    ListModel {
        id: actualModel
    }

    ListView {
        anchors.fill: parent
        model: actualModel

        delegate: ItemDelegate {
            text: model.text
            onClicked: {
                if (header.interfacesMode) {
                    if (root.device) {
                        print("selected:", model.event)
                        switch (model.event) {
                        case "lowBattery":
                            var eventType = root.deviceClass.eventTypes.findByName("batteryCritical")
                            root.eventDescriptor.eventTypeId = eventType.id;
//                            root.eventDescriptor.paramDescriptors.setParamDescriptor(eventType.paramTypes.get(0).paramTypeId, 0, ParamDescriptors.ValueOperatorLessOrEqual)
                            root.done();
                            break;
                        default:
                            console.warn("FIXME: Unhandled interface event");
                        }
                    }
                } else {
                    console.warn("FIXME: not implemented yet")
                }
            }
        }
    }
}
