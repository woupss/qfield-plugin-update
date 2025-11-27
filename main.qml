import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Theme
import org.qfield
import org.qgis
import QtCore

Item {
    id: rootItem
    property var mainWindow: iface.mainWindow()

    // =========================================================================
    // 1. CONFIGURATION
    // =========================================================================
    property var pluginSources: {
        "Filter": "https://github.com/woupss/Qfield-filter-plugin/archive/refs/heads/main.zip",
        "UpdatefromURL": "https://github.com/woupss/Qfield-Update-qgz-Project/archive/refs/heads/main.zip",
        
        // NAME DETECTION FOR AUTO-UPDATE
        "Qfield Plugin Update": "https://github.com/woupss/qfield-plugin-update/archive/refs/heads/main.zip",
        
        "OSRM Routing": "https://github.com/opengisch/qfield-osrm/archive/refs/heads/main.zip",
        "OpenStreetMap Nominatim Search": "https://github.com/opengisch/qfield-nominatim-locator/archive/refs/heads/main.zip",
        "Delete_Via_Dropdown": "https://github.com/TyHol/DeleteViaDropdown/archive/refs/heads/main.zip",
        "Layer loader": "https://github.com/mbernasocchi/qfield-layer-loader/archive/refs/heads/main.zip",
        "My Private Plugin": "https://monsite.com/files/mon_plugin_v2.zip",
        
        // "Qfield Plugin Reloader": "https://github.com/gacarillor/qfield-plugin-reloader/qfield-plugin-reloader/archive/refs/heads/main.zip"
    }

    // =========================================================================
    // 2. STATE
    // =========================================================================
    property string targetUrl: ""
    property string targetUuid: "" 
    property string targetName: "" 
    property string targetFolderDisplay: "..."
    property bool isFinished: false
    property bool isWorking: false 
    property string savedComboText: ""
    property bool isSelfUpdate: false

    // =========================================================================
    // 3. ANALYSIS LOGIC
    // =========================================================================
    
    function extractNameFromUrl(url) {
        if (!url) return "";
        if (url.indexOf("/archive/") !== -1) {
            var parts = url.split("/");
            for (var k = 0; k < parts.length; k++) {
                if (parts[k] === "archive" && k > 0) {
                    return parts[k-1] + "-main"; // The NEW folder
                }
            }
        }
        return "";
    }

    function findUrlCaseInsensitive(name) {
        var keys = Object.keys(pluginSources);
        var searchName = name.toLowerCase().trim();
        for (var i = 0; i < keys.length; i++) {
            if (keys[i].toLowerCase().trim() === searchName) {
                return pluginSources[keys[i]];
            }
        }
        return "";
    }

    function analyzeUrlAndSelection() {
        var customUrl = urlField.text.trim();
        rootItem.isSelfUpdate = false; 
        
        if (customUrl !== "") {
            // --- CASE 1: CUSTOM URL ---
            if (pluginCombo.currentIndex !== -1) {
                pluginCombo.currentIndex = -1;
                rootItem.savedComboText = ""; 
            }

            var repoName = extractNameFromUrl(customUrl);
            if (repoName !== "") {
                targetFolderDisplay = ".../plugins/" + repoName;
                if (!rootItem.isFinished) rootItem.targetName = repoName;
            } else {
                targetFolderDisplay = ".../plugins/[ZIP Name]";
                if (!rootItem.isFinished) rootItem.targetName = "Custom";
            }

        } else {
            // --- CASE 2: COMBOBOX SELECTION ---
            if (pluginCombo.currentIndex === -1) {
                targetFolderDisplay = "...";
                // Reset if nothing is selected
                rootItem.targetName = "";
                rootItem.targetUuid = "";
                return;
            }

            var selectedName = pluginCombo.currentText;
            
            // AUTO-UPDATE DETECTION
            if (selectedName.toLowerCase().indexOf("plugin update") !== -1) {
                rootItem.isSelfUpdate = true;
            }

            var knownUrl = findUrlCaseInsensitive(selectedName);
            var prettyName = extractNameFromUrl(knownUrl);

            // Search for the currently installed UUID
            var foundUuid = "";
            var plugins = pluginManager.availableAppPlugins;
            for (var i = 0; i < plugins.length; i++) {
                if (plugins[i].name === selectedName) {
                    foundUuid = plugins[i].uuid;
                    break;
                }
            }

            if (prettyName !== "") {
                targetFolderDisplay = ".../plugins/" + prettyName;
                rootItem.targetName = prettyName;
            } else {
                if (foundUuid !== "") {
                    targetFolderDisplay = ".../plugins/" + foundUuid;
                } else {
                    targetFolderDisplay = ".../plugins/[Unknown]";
                }
            }
        }
    }

    // =========================================================================
    // 4. BUSINESS LOGIC
    // =========================================================================

    Connections {
        target: pluginManager

        function onInstallProgress(progress) { 
            progressBar.indeterminate = false;
            progressBar.value = progress;
        }

        function onInstallEnded(uuid, error) {
            rootItem.isWorking = false; 
            
            if (error && error !== "") {
                statusText.text = "ERROR: " + error;
                statusText.color = "red";
                progressBar.value = 0;
            } else {
                if (pluginManager.pluginModel) pluginManager.pluginModel.refresh(false);
                
                rootItem.isFinished = true;
                progressBar.value = 1;
                progressBar.indeterminate = false;
                
                if (rootItem.isSelfUpdate) {
                    statusText.text = "Update installed.\nCleaning up old version in 3 seconds...";
                    statusText.color = "#d35400"; // Orange
                } else {
                    statusText.text = "Update completed successfully.";
                    statusText.color = "green";
                }
                
                // Auto close dialogue
                closeTimer.start();
            }
        }
    }

    // Timer to close the dialog
    Timer {
        id: closeTimer
        interval: 3000
        repeat: false
        onTriggered: {
            updateDialog.close();
        }
    }

    // --- THE KILL SWITCH (DANGER) ---
    // Triggered AFTER dialog closure to delete the old folder
    Timer {
        id: finalSelfDestructTimer
        interval: 500 // 0.5 sec after visual closure
        repeat: false
        onTriggered: {
            console.log("AUTO-UPDATE: Starting final destruction of: " + rootItem.targetUuid);
            
            try {
                // 1. Disable cleanly
                if (pluginManager.isAppPluginEnabled(rootItem.targetUuid)) {
                    pluginManager.disableAppPlugin(rootItem.targetUuid);
                }
                // 2. DELETE INITIAL FOLDER (old UUID)
                pluginManager.uninstall(rootItem.targetUuid);
                
                console.log("AUTO-UPDATE: Old version deleted.");
            } catch (e) {
                console.log("AUTO-UPDATE Error: " + e);
            }
        }
    }

    Timer {
        id: transitionTimer
        interval: 800
        repeat: false
        onTriggered: {
            if (rootItem.targetUrl !== "") {
                statusText.text = "Downloading new version...";
                // Installs the "...-main" folder next to the current one
                pluginManager.installFromUrl(rootItem.targetUrl);
            }
        }
    }

    function startUpdateProcess() {
        var customUrl = urlField.text.trim();
        var selectedName = pluginCombo.currentText;

        statusText.color = "black";

        // VERIFICATIONS
        if (customUrl === "" && pluginCombo.currentIndex === -1) {
             statusText.text = "⚠️ Please select a plugin.";
             statusText.color = "red";
             return;
        }

        // SETUP URL
        if (customUrl !== "") {
            rootItem.targetUrl = customUrl;
            rootItem.savedComboText = ""; 
        } else {
            rootItem.savedComboText = selectedName;
            rootItem.targetName = selectedName;
            
            var foundUrl = findUrlCaseInsensitive(selectedName);
            if (foundUrl !== "") {
                rootItem.targetUrl = foundUrl;
            } else {
                statusText.text = "⚠️ Error: Unknown URL.";
                statusText.color = "red";
                return;
            }
        }

        // IDENTIFY OLD VERSION
        rootItem.targetUuid = "";
        var searchName = (customUrl === "" && pluginCombo.currentIndex !== -1) ? pluginCombo.currentText : "";
        var plugins = pluginManager.availableAppPlugins;
        if (searchName !== "") {
            for (var i = 0; i < plugins.length; i++) {
                if (plugins[i].name === searchName) {
                    rootItem.targetUuid = plugins[i].uuid;
                    break;
                }
            }
        }

        // INIT UI
        platformUtilities.requestStoragePermission();
        rootItem.isWorking = true;
        rootItem.isFinished = false;
        statusText.text = "Initializing...";
        progressBar.value = 0;
        progressBar.indeterminate = true; 

        // DELETE LOGIC
        if (rootItem.targetUuid !== "") {
            if (rootItem.isSelfUpdate) {
                // AUTO-UPDATE CASE: DO NOT DELETE NOW
                statusText.text = "Auto-Update Mode: Installing new version...";
                console.log("AUTO-UPDATE: Deletion deferred to end of process.");
            } 
            else {
                // NORMAL CASE: Delete first
                statusText.text = "Deleting old version...";
                try {
                    if (pluginManager.isAppPluginEnabled(rootItem.targetUuid)) {
                        pluginManager.disableAppPlugin(rootItem.targetUuid);
                    }
                    pluginManager.uninstall(rootItem.targetUuid);
                } catch (e) {}
            }
        }

        transitionTimer.start();
    }

    // =========================================================================
    // 5. GRAPHIC INTERFACE
    // =========================================================================

    Component.onCompleted: {
        iface.addItemToPluginsToolbar(toolbarButton);
    }

    QfToolButton {
        id: toolbarButton
        iconSource: "icon.svg"
        iconColor: Theme.mainColor
        bgcolor: Theme.darkGray
        round: true
        onClicked: {
            if (pluginManager.pluginModel) pluginManager.pluginModel.refresh(false);
            
            // RESET
            pluginCombo.currentIndex = -1;
            urlField.text = "";
            rootItem.savedComboText = ""; 
            rootItem.isFinished = false;
            rootItem.isWorking = false;
            rootItem.targetFolderDisplay = "...";
            rootItem.isSelfUpdate = false;
            progressBar.value = 0;
            progressBar.indeterminate = false;
            statusText.text = "";
            statusText.color = "black";
            
            updateDialog.open();
        }
    }

    Dialog {
        id: updateDialog
        parent: mainWindow.contentItem
        modal: true
        
        // Remove default padding
        padding: 0
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0

        width: Math.min(Math.max(300, mainLayout.implicitWidth + 40), mainWindow.width * 0.95)
        height: mainLayout.implicitHeight + 20 
        
        x: (mainWindow.width - width) / 2
        y: (mainWindow.height - height) / 2
        standardButtons: Dialog.NoButton
        
        onClosed: {
            if (rootItem.isFinished && rootItem.isSelfUpdate && rootItem.targetUuid !== "") {
                finalSelfDestructTimer.start();
            }
        }
        
        background: Rectangle { 
            color: "white"; radius: 8; border.width: 2; border.color: Theme.mainColor 
            
            // MouseArea to lose focus when clicking background
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    mainLayout.forceActiveFocus()
                }
            }
        }

        ColumnLayout {
            id: mainLayout
            anchors.fill: parent
            
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            
            spacing: 4 

            Label {
                text: "Plugin Update"
                font.bold: true
                font.pointSize: 16
                Layout.alignment: Qt.AlignHCenter
            }

            // Deselection button via RowLayout
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 5

                ComboBox {
                    id: pluginCombo
                    Layout.fillWidth: true
                    textRole: "name"
                    model: pluginManager.availableAppPlugins
                    displayText: rootItem.savedComboText !== "" ? rootItem.savedComboText : (currentIndex === -1 ? "Select a plugin" : currentText)
                    onActivated: {
                        urlField.text = "";
                        rootItem.savedComboText = "";
                        analyzeUrlAndSelection(); 
                    }
                }

                Button {
                    text: "✖"
                    visible: pluginCombo.currentIndex !== -1
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    background: Rectangle { 
                        color: "#eee" 
                        radius: 4 
                        border.color: "#ccc"
                    }
                    onClicked: {
                        pluginCombo.currentIndex = -1;
                        rootItem.savedComboText = "";
                        analyzeUrlAndSelection(); 
                    }
                }
            }

            Label { text: "OR enter a URL:" ; font.bold: true; font.pixelSize: 12 ; Layout.topMargin: 12 }
            TextField {
                id: urlField
                Layout.fillWidth: true
                Layout.preferredHeight: 40 
                verticalAlignment: Text.AlignVCenter
                
                selectByMouse: true
                placeholderText: "" 
                Label {
                    anchors.left: parent.left; 
                    anchors.leftMargin: 5;
                    anchors.verticalCenter: parent.verticalCenter
                    
                    // Visible only if empty AND no focus
                    visible: !parent.activeFocus && parent.text === ""
                    
                    text: "https://github.com/user/repo/archive/refs/heads/main.zip"
                    color: "#aaa"; font.pixelSize: 10; font.italic: true
                }
                onTextChanged: { analyzeUrlAndSelection(); statusText.text = ""; statusText.color = "black"; }
                
                background: Rectangle { 
                    color: "white" 
                    border.color: parent.activeFocus ? Theme.mainColor : "#ccc"
                    radius: 4 
                }
            }

            Label { text: "Target destination:" ; font.bold: true; font.pixelSize: 12 ; Layout.topMargin: 12 }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 40; color: "#e0e0e0"; radius: 4; border.color: "#999"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 4 
                    Text { text: "📂"; font.pixelSize: 14 }
                    Text {
                        text: rootItem.targetFolderDisplay
                        font.family: "Courier"; font.pixelSize: 11; color: "#333"; elide: Text.ElideMiddle; Layout.fillWidth: true
                    }
                }
            }

            ProgressBar { 
                id: progressBar
                Layout.fillWidth: true; Layout.topMargin: 10
                value: 0
                indeterminate: rootItem.isWorking && value === 0
                visible: rootItem.isWorking || rootItem.isFinished
            }

            Text {
                id: statusText
                Layout.fillWidth: true
                text: "" 
                visible: text !== ""
                horizontalAlignment: Text.AlignHCenter; font.italic: true; wrapMode: Text.Wrap; color: "#555"
            }

            // --- ADAPTIVE AND DYNAMIC BUTTON ---
            Button {
                Layout.alignment: Qt.AlignHCenter 
                Layout.fillWidth: false 
                Layout.topMargin: 10
                
                leftPadding: 20
                rightPadding: 20
                topPadding: 10
                bottomPadding: 10

                enabled: !rootItem.isFinished && !rootItem.isWorking
                background: Rectangle { color: Theme.mainColor; radius: 6 }
                contentItem: Text { 
                    text: {
                        if (rootItem.isFinished) {
                            if (urlField.text.trim() !== "") return "Installation successful";
                            return "Update successful";
                        }
                        
                        if (urlField.text.trim() !== "") return "INSTALL";
                        
                        return "UPDATE";
                    }
                    color: "white"; font.bold: true; font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter 
                }
                onClicked: startUpdateProcess()
            }
        }
    }
}
