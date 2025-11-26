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

       "Qfield Plugin Update": "https://github.com/woupss/qfield-plugin-update/archive/refs/heads/main.zip",


     //   "Qfield Plugin Reloader": "https://github.com/gacarillor/qfield-plugin-reloader/archive/refs/heads/main.zip",

        "OSRM Routing": "https://github.com/opengisch/qfield-osrm/archive/refs/heads/main.zip",

         "OpenStreetMap Nominatim Search": "https://github.com/opengisch/qfield-nominatim-locator/archive/refs/heads/main.zip",

        "Delete_Via_Dropdown": "https://github.com/TyHol/DeleteViaDropdown/archive/refs/heads/main.zip",

        "Layer loader": "https://github.com/mbernasocchi/qfield-layer-loader/archive/refs/heads/main.zip",

        "Mon Plugin Privé": "https://monsite.com/files/mon_plugin_v2.zip"
    }

    // =========================================================================
    // 2. ETAT
    // =========================================================================
    property string targetUrl: ""
    property string targetUuid: ""
    property string targetName: "" 
    property string targetFolderDisplay: "..."
    property bool isFinished: false
    property bool isWorking: false // Pour gérer l'animation de la barre
    
    // Propriété pour figer le nom du plugin pendant le traitement
    property string savedComboText: ""

    // =========================================================================
    // 3. LOGIQUE D'ANALYSE
    // =========================================================================
    function analyzeUrlAndSelection() {
        var customUrl = urlField.text.trim();
        
        if (customUrl !== "") {
            // --- CAS 1 : URL PERSONNALISÉE ---
            // Si une URL est saisie, on désélectionne le combo (visuellement)
            if (pluginCombo.currentIndex !== -1) {
                pluginCombo.currentIndex = -1;
                rootItem.savedComboText = ""; 
            }

            var repoName = "Inconnu";
            var detected = false;

            if (customUrl.indexOf("/archive/") !== -1) {
                var parts = customUrl.split("/");
                for (var k = 0; k < parts.length; k++) {
                    if (parts[k] === "archive" && k > 0) {
                        repoName = parts[k-1];
                        detected = true;
                        break;
                    }
                }
            }

            if (detected) {
                targetFolderDisplay = ".../plugins/" + repoName + "-main";
                if (!rootItem.isFinished) rootItem.targetName = repoName;
            } else {
                targetFolderDisplay = ".../plugins/[Nom du ZIP]";
                if (!rootItem.isFinished) rootItem.targetName = "Personnalisé";
            }

        } else {
            // --- CAS 2 : SÉLECTION COMBOBOX ---
            if (pluginCombo.currentIndex === -1) {
                targetFolderDisplay = "...";
                return;
            }

            var selectedName = pluginCombo.currentText;
            var foundUuid = "";
            var plugins = pluginManager.availableAppPlugins;
            
            for (var i = 0; i < plugins.length; i++) {
                if (plugins[i].name === selectedName) {
                    foundUuid = plugins[i].uuid;
                    break;
                }
            }
            
            if (foundUuid !== "") {
                targetFolderDisplay = ".../plugins/" + foundUuid;
            } else {
                targetFolderDisplay = ".../plugins/[Inconnu]";
            }
        }
    }

    // =========================================================================
    // 4. LOGIQUE MÉTIER
    // =========================================================================

    Connections {
        target: pluginManager

        function onInstallProgress(progress) { 
            // Si on reçoit une progression, on n'est plus en "indéterminé"
            progressBar.indeterminate = false;
            progressBar.value = progress;
        }

        function onInstallEnded(uuid, error) {
            rootItem.isWorking = false; // Arrêt de l'animation
            
            if (error && error !== "") {
                // Remplacement du Toast par le texte rouge
                statusText.text = "ERREUR : " + error;
                statusText.color = "red";
                progressBar.value = 0;
            } else {
                // SUCCÈS
                if (pluginManager.pluginModel) pluginManager.pluginModel.refresh(false);
                
                rootItem.isFinished = true;
                progressBar.value = 1;
                progressBar.indeterminate = false;
                
                statusText.text = "Opération terminée.";
                statusText.color = "green";
                
                closeTimer.start();
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 3000
        repeat: false
        onTriggered: updateDialog.close()
    }

    Timer {
        id: transitionTimer
        interval: 800
        repeat: false
        onTriggered: {
            if (rootItem.targetUrl !== "") {
                statusText.text = "Téléchargement en cours...";
                // On laisse la barre indéterminée jusqu'au premier retour de progression
                pluginManager.installFromUrl(rootItem.targetUrl);
            }
        }
    }

    function startUpdateProcess() {
        var customUrl = urlField.text.trim();
        var selectedName = pluginCombo.currentText;

        // Reset visuel erreur
        statusText.color = "black";

        // 1. DÉTERMINATION
        if (customUrl !== "") {
            rootItem.targetUrl = customUrl;
            rootItem.savedComboText = ""; 
        } else {
            if (pluginCombo.currentIndex === -1) {
                // Remplacement du Toast erreur
                statusText.text = "⚠️ Veuillez sélectionner un plugin ou saisir une URL.";
                statusText.color = "red";
                return;
            }

            rootItem.savedComboText = selectedName;
            rootItem.targetName = selectedName;
            
            if (pluginSources[selectedName]) {
                rootItem.targetUrl = pluginSources[selectedName];
            } else {
                // Remplacement du Toast erreur
                statusText.text = "⚠️ Erreur : Pas d'URL connue pour ce plugin.";
                statusText.color = "red";
                return;
            }
        }

        // 2. INIT
        platformUtilities.requestStoragePermission();
        
        rootItem.isWorking = true; // Active l'animation barre
        rootItem.isFinished = false;
        
        statusText.text = "Traitement en cours..."; // Texte générique de début
        statusText.color = "black";
        
        progressBar.value = 0;
        progressBar.indeterminate = true; // Barre qui bouge (Chenillard)

        // 3. IDENTIFICATION CIBLE
        rootItem.targetUuid = "";
        if (pluginCombo.currentIndex !== -1) {
            var plugins = pluginManager.availableAppPlugins;
            for (var i = 0; i < plugins.length; i++) {
                if (plugins[i].name === pluginCombo.currentText) {
                    rootItem.targetUuid = plugins[i].uuid;
                    break;
                }
            }
        }

        // 4. NETTOYAGE
        if (rootItem.targetUuid !== "") {
            statusText.text = "Nettoyage ancienne version...";
            try {
                if (pluginManager.isAppPluginEnabled(rootItem.targetUuid)) {
                    pluginManager.disableAppPlugin(rootItem.targetUuid);
                }
            } catch (e) {}

            try {
                pluginManager.uninstall(rootItem.targetUuid);
            } catch (e) {
                console.log("Uninstall logic error: " + e);
            }
        }

        // 5. INSTALLATION
        transitionTimer.start();
    }

    // =========================================================================
    // 5. INTERFACE GRAPHIQUE
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
            
            // RESET COMPLET A L'OUVERTURE
            pluginCombo.currentIndex = -1;
            urlField.text = "";
            rootItem.savedComboText = ""; 
            rootItem.isFinished = false;
            rootItem.isWorking = false;
            rootItem.targetFolderDisplay = "...";
            progressBar.value = 0;
            progressBar.indeterminate = false;
            statusText.text = ""; // Pas de texte initial
            statusText.color = "black";
            
            updateDialog.open();
        }
    }

    Dialog {
        id: updateDialog
        parent: mainWindow.contentItem
        modal: true
        width: Math.min(500, mainWindow.width * 0.95)
        x: (mainWindow.width - width) / 2
        y: (mainWindow.height - height) / 2
        standardButtons: Dialog.NoButton
        
        background: Rectangle { 
            color: "white"; radius: 8; border.width: 2; border.color: Theme.mainColor 
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Label {
                text: "Mise à jour Plugin"
                font.bold: true
                font.pointSize: 16
                Layout.alignment: Qt.AlignHCenter
            }

            // --- ZONE 1 : LISTE ---
            Label { 
                text: "Sélectionner le plugin (Cible) :" 
                font.bold: true; font.pixelSize: 12 
            }
            
            ComboBox {
                id: pluginCombo
                Layout.fillWidth: true
                textRole: "name"
                model: pluginManager.availableAppPlugins
                
                // Affichage persistant du nom pendant le traitement
                displayText: rootItem.savedComboText !== "" ? rootItem.savedComboText : (currentIndex === -1 ? "Sélectionnez un plugin" : currentText)
                
                onActivated: {
                    urlField.text = "";
                    rootItem.savedComboText = "";
                    analyzeUrlAndSelection();
                    statusText.text = ""; // Reset message erreur si on change
                    statusText.color = "black";
                }
            }

            // --- ZONE 2 : URL PERSO ---
            Label { 
                text: "OU saisir une URL :" 
                font.bold: true; font.pixelSize: 12 
                Layout.topMargin: 5
            }

            TextField {
                id: urlField
                Layout.fillWidth: true
                selectByMouse: true
                
                // On n'utilise pas le placeholderText standard pour contrôler la police
                placeholderText: "" 
                
                // CUSTOM PLACEHOLDER (Petite police)
                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 10 // Marge interne standard TextField
                    anchors.verticalCenter: parent.verticalCenter
                    // Visible si champ vide
                    visible: parent.text === "" && !parent.activeFocus
                    
                    text: "https://github.com/user/repo/archive/refs/heads/main.zip"
                    color: "#aaa"
                    font.pixelSize: 10 // POLICE REDUITE POUR TOUT AFFICHER
                    font.italic: true
                    elide: Text.ElideRight
                    width: parent.width - 20
                }
                
                onTextChanged: {
                    analyzeUrlAndSelection();
                    statusText.text = ""; // Reset message erreur
                    statusText.color = "black";
                }
                
                background: Rectangle {
                    color: "#f9f9f9"
                    border.color: parent.activeFocus ? Theme.mainColor : "#ccc"
                    radius: 4
                }
            }

            // --- ZONE 3 : CHEMIN ---
            Label { 
                text: "Destination prévue :" 
                font.bold: true; font.pixelSize: 12
                Layout.topMargin: 5
            }
            
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                color: "#e0e0e0"
                radius: 4
                border.color: "#999"
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    Text { text: "📂"; font.pixelSize: 14 }
                    Text {
                        text: rootItem.targetFolderDisplay
                        font.family: "Courier"; font.pixelSize: 11
                        color: "#333"; elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
            }

            // --- ZONE 4 : BARRE DE CHARGEMENT + STATUS ---
            
            // Barre de chargement (Progress ou Indeterminate)
            ProgressBar { 
                id: progressBar
                Layout.fillWidth: true
                Layout.topMargin: 10
                
                value: 0
                // Indéterminée (va-et-vient) si on travaille mais pas encore de % reçu
                indeterminate: rootItem.isWorking && value === 0
                
                // Visible si on travaille ou si on a fini (100%)
                visible: rootItem.isWorking || rootItem.isFinished
            }

            // Texte de Status (Erreur ou Info)
            Text {
                id: statusText
                Layout.fillWidth: true
                text: "" 
                horizontalAlignment: Text.AlignHCenter
                font.italic: true
                wrapMode: Text.Wrap // Pour les longs messages d'erreur
                color: "#555" // Changera en rouge si erreur
            }

            // --- BOUTON DYNAMIQUE ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                Layout.topMargin: 10
                
                Button {
                    anchors.centerIn: parent
                    width: parent.width * 0.9
                    height: 45
                    
                    enabled: !rootItem.isFinished && !rootItem.isWorking
                    
                    background: Rectangle { 
                        color: Theme.mainColor
                        radius: 6 
                    }
                    
                    contentItem: Text { 
                        text: rootItem.isFinished ? "Plugin " + rootItem.targetName + " mis à jour" : "METTRE À JOUR"
                        
                        color: "white"
                        font.bold: true
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter 
                        elide: Text.ElideRight
                    }
                    
                    onClicked: startUpdateProcess()
                }
            }
        }
    }
}
