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
    // 0. INTERNATIONALISATION (I18N)
    // =========================================================================
    property string currentLang: "en"

    function detectLanguage() {
        // Récupère le code langue (ex: "fr_FR" -> "fr")
        var loc = Qt.locale().name.substring(0, 2);
        if (loc === "fr") rootItem.currentLang = "fr";
        else rootItem.currentLang = "en";
    }

    // Dictionnaire des textes (Mis à jour selon votre demande)
    property var translations: {
        "title": { "en": "PLUGIN UPDATER", "fr": "MISE À JOUR DES PLUGINS" },
        "select_placeholder": { "en": "Select a plugin", "fr": "Sélectionner un plugin" },
        "or_custom": { "en": "OR custom URL:", "fr": "OU une URL personnalisée :" },
        "destination": { "en": "Target destination:", "fr": "Dossier de destination :" },
        "installed_ver": { "en": "Installed version: ", "fr": "Version installée : " },
        "btn_wait": { "en": "WAIT...", "fr": "ATTENTE..." },
        "btn_install": { "en": "INSTALL NOW", "fr": "INSTALLER" },
        "btn_update": { "en": "UPDATE", "fr": "METTRE À JOUR" },
        "status_checking": { "en": "Checking for updates...", "fr": "Recherche de mises à jour..." },
        "status_scanning": { "en": "🔍 Scanning installed plugins...", "fr": "🔍 Scan des plugins..." },
        "status_uptodate": { "en": "✔ All plugins are up to date.", "fr": "✔ Tout est à jour." },
        "status_updates_found": { "en": "🚀 Updates found:\n", "fr": "🚀 Mises à jour trouvées :\n" },
        "search_step": { "en": "Searching", "fr": "Recherche" },
        "source_direct": { "en": "Source: Direct Link", "fr": "Source : Lien direct" },
        "wait_search": { "en": "Please wait for search to finish...", "fr": "Attendez la fin de la recherche..." },
        "select_warn": { "en": "⚠️ Please select a plugin.", "fr": "⚠️ Sélectionnez un plugin." },
        "check_release": { "en": "Checking releases...", "fr": "Vérification des versions..." },
        "json_error": { "en": "JSON Error.", "fr": "Erreur JSON." },
        "api_error": { "en": "API Error", "fr": "Erreur API" },
        "no_repo": { "en": "❌ No relevant repository found.", "fr": "❌ Aucun dépôt trouvé." },
        "available": { "en": "Available: ", "fr": "Disponible : " },
        "found": { "en": "Found: ", "fr": "Trouvé : " },
        "no_zip": { "en": "No zip found. Using Main.", "fr": "Aucun zip trouvé. Utilisation de Main." },
        "downloading": { "en": "Downloading", "fr": "Téléchargement" },
        "extracting": { "en": "Extracting files...", "fr": "Extraction des fichiers..." },
        "error": { "en": "❌ Error: ", "fr": "❌ Erreur : " },
        "installed": { "en": "✔ Installed", "fr": "✔ Installé" },
        "restart": { "en": "\nRestart recommended.", "fr": "\nRedémarrage recommandé." }
    }

    // Fonction de traduction
    function tr(key) {
        if (translations[key]) {
            return translations[key][rootItem.currentLang] || translations[key]["en"];
        }
        return key;
    }

    // =========================================================================
    // 1. ETAT ET VARIABLES
    // =========================================================================
    property string finalDownloadUrl: ""
    property string preparedUrl: ""
    property string targetUuid: ""      
    property string targetName: ""      
    property string targetAuthor: ""    
    
    property string detectedVersion: "" 
    property string installedVersion: "" 
    property string displayUrl: "" 
    property string targetFolderDisplay: "..." 
    
    property bool isWorking: false
    property bool isFinished: false
    property bool isSelfUpdate: false

    property bool updatesChecked: false
    property var pluginsQueue: []
    property string updatesResultText: tr("status_checking")
    property bool isCheckingUpdates: false

    // =========================================================================
    // 2. LOGIQUE METIER
    // =========================================================================

    function cleanVersion(v) {
        if (!v) return "";
        return v.replace(/^[vV]/, "").trim();
    }

    function isNewerVersion(currentVer, onlineVer) {
        var v1 = cleanVersion(currentVer).split('.');
        var v2 = cleanVersion(onlineVer).split('.');
        var len = Math.max(v1.length, v2.length);
        for (var i = 0; i < len; i++) {
            var num1 = (i < v1.length) ? parseInt(v1[i]) : 0;
            var num2 = (i < v2.length) ? parseInt(v2[i]) : 0;
            if (isNaN(num1)) num1 = 0;
            if (isNaN(num2)) num2 = 0;
            if (num2 > num1) return true;
            if (num1 > num2) return false;
        }
        return false;
    }

    function startGlobalUpdateCheck() {
        if (rootItem.updatesChecked) return;
        rootItem.pluginsQueue = [];
        rootItem.updatesResultText = tr("status_scanning");
        rootItem.isCheckingUpdates = true;
        var plugins = pluginManager.availableAppPlugins;
        for (var i = 0; i < plugins.length; i++) {
            rootItem.pluginsQueue.push({ name: plugins[i].name, version: plugins[i].version, uuid: plugins[i].uuid });
        }
        updateQueueTimer.start();
    }

    Timer {
        id: updateQueueTimer
        interval: 1500; repeat: true
        onTriggered: {
            if (rootItem.pluginsQueue.length > 0) {
                var p = rootItem.pluginsQueue.shift();
                checkSinglePluginUpdate(p);
            } else {
                updateQueueTimer.stop();
                rootItem.isCheckingUpdates = false;
                rootItem.updatesChecked = true;
                if (rootItem.updatesResultText === tr("status_scanning")) {
                    rootItem.updatesResultText = tr("status_uptodate");
                }
            }
        }
    }

    function checkSinglePluginUpdate(pluginObj) {
        var query = encodeURIComponent(pluginObj.name + " qfield");
        var apiUrl = "https://api.github.com/search/repositories?q=" + query + "&sort=stars&order=desc&per_page=1";
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    if (response.items && response.items.length > 0) getLatestTag(response.items[0].url, pluginObj);
                } catch (e) {}
            }
        }
        xhr.open("GET", apiUrl); xhr.setRequestHeader("User-Agent", "QField-Plugin-Installer"); xhr.send();
    }

    function getLatestTag(repoUrl, pluginObj) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    var remoteVer = "";
                    if (Array.isArray(response) && response.length > 0) remoteVer = response[0].name;
                    else if (response.tag_name) remoteVer = response.tag_name;
                    if (remoteVer !== "" && isNewerVersion(pluginObj.version, remoteVer)) {
                        appendUpdateMessage(pluginObj.name, pluginObj.version, remoteVer);
                    }
                } catch (e) {}
            }
        }
        xhr.open("GET", repoUrl + "/releases/latest"); xhr.setRequestHeader("User-Agent", "QField-Plugin-Installer"); xhr.send();
    }

    function appendUpdateMessage(name, oldVer, newVer) {
        if (rootItem.updatesResultText.indexOf("Scanning") !== -1 || rootItem.updatesResultText.indexOf("Scan") !== -1) {
            rootItem.updatesResultText = tr("status_updates_found");
        }
        rootItem.updatesResultText += "• " + name + ": " + oldVer + " ➡ " + newVer + "\n";
    }

    function getRepoSlug(url) {
        if (!url || url.indexOf("github.com") === -1) return "";
        var clean = url.replace("https://github.com/", "").replace("http://github.com/", "");
        clean = clean.split("/archive")[0]; clean = clean.split("/releases")[0];
        var parts = clean.split("/");
        if (parts.length >= 2) return parts[0] + "/" + parts[1];
        return "";
    }

    function startSmartSearch() { searchGitHubBroad(rootItem.targetName + " qfield", 1); }

    function searchGitHubBroad(queryTerm, step) {
        statusText.text = tr("search_step") + " (" + step + "): '" + queryTerm + "'..."; 
        statusText.color = "gray";
        var apiUrl = "https://api.github.com/search/repositories?q=" + encodeURIComponent(queryTerm) + "&sort=stars&order=desc&per_page=5";
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        var items = response.items || [];
                        if (items.length > 0) {
                            var bestRepo = findBestMatch(items);
                            if (bestRepo) checkGitHubRelease(bestRepo.full_name, bestRepo.html_url, false);
                            else tryNextSearchStep(step);
                        } else tryNextSearchStep(step);
                    } catch (e) { statusText.text = "❌ " + tr("json_error"); }
                } else statusText.text = "❌ " + tr("api_error") + " (" + xhr.status + ")";
            }
        }
        xhr.open("GET", apiUrl); xhr.setRequestHeader("User-Agent", "QField-Plugin-Installer"); xhr.send();
    }

    function tryNextSearchStep(currentStep) {
        if (currentStep === 1) {
            if (rootItem.targetUuid !== "") searchGitHubBroad(rootItem.targetUuid, 2);
            else handleSearchFailure();
        } else if (currentStep === 2) {
            searchGitHubBroad(rootItem.targetName, 3);
        } else handleSearchFailure();
    }

    function handleSearchFailure() { statusText.text = tr("no_repo"); statusText.color = "red"; }

    function findBestMatch(items) {
        var bestItem = null; var maxScore = 0; var threshold = 15;
        var targetUuidClean = rootItem.targetUuid.toLowerCase().replace(/_/g, "-");
        var targetAuthorClean = rootItem.targetAuthor.toLowerCase(); 
        var authorParts = targetAuthorClean.split(" ");
        var primaryAuthorName = authorParts.length > 0 ? authorParts[0] : targetAuthorClean;

        for (var i = 0; i < items.length; i++) {
            var item = items[i]; var score = 0;
            var repoName = item.name.toLowerCase(); var repoOwner = item.owner.login.toLowerCase();
            var desc = (item.description || "").toLowerCase();

            if (targetAuthorClean !== "" && (repoOwner.indexOf(primaryAuthorName) !== -1 || targetAuthorClean.indexOf(repoOwner) !== -1)) score += 30;
            if (rootItem.targetUuid !== "" && (repoName === targetUuidClean || repoName === rootItem.targetUuid.toLowerCase())) score += 20;
            else if (repoName.indexOf(targetUuidClean) !== -1) score += 10;
            if (desc.indexOf("qfield") !== -1 || repoName.indexOf("qfield") !== -1) score += 10;
            if (item.stargazers_count > 10) score += 5;
            if (score > maxScore) { maxScore = score; bestItem = item; }
        }
        return maxScore >= threshold ? bestItem : null;
    }

    function checkGitHubRelease(repoSlug, fallbackUrl, autoInstall) {
        var apiUrl = "https://api.github.com/repos/" + repoSlug + "/releases/latest?t=" + new Date().getTime();
        if (!autoInstall) statusText.text = tr("check_release");
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) processSingleRelease(xhr.responseText, fallbackUrl, autoInstall);
                else checkGitHubAllReleases(repoSlug, fallbackUrl, autoInstall);
            }
        }
        xhr.open("GET", apiUrl); xhr.setRequestHeader("User-Agent", "QField-Plugin-Installer"); xhr.send();
    }

    function checkGitHubAllReleases(repoSlug, fallbackUrl, autoInstall) {
        var apiUrl = "https://api.github.com/repos/" + repoSlug + "/releases?per_page=1&t=" + new Date().getTime();
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) processListResponse(xhr.responseText, fallbackUrl, autoInstall, "Release");
                else checkGitHubTags(repoSlug, fallbackUrl, autoInstall);
            }
        }
        xhr.open("GET", apiUrl); xhr.setRequestHeader("User-Agent", "QField-Plugin-Installer"); xhr.send();
    }

    function checkGitHubTags(repoSlug, fallbackUrl, autoInstall) {
        var apiUrl = "https://api.github.com/repos/" + repoSlug + "/tags?per_page=1&t=" + new Date().getTime();
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) processListResponse(xhr.responseText, fallbackUrl, autoInstall, "Tag");
                else handleError(fallbackUrl, autoInstall, "API Error " + xhr.status + ". Using Main.");
            }
        }
        xhr.open("GET", apiUrl); xhr.setRequestHeader("User-Agent", "QField-Plugin-Installer"); xhr.send();
    }

    function processSingleRelease(jsonText, fallbackUrl, autoInstall) {
        try { extractAndFinish(JSON.parse(jsonText), fallbackUrl, autoInstall); } 
        catch (e) { handleError(fallbackUrl, autoInstall, tr("json_error")); }
    }

    function processListResponse(jsonText, fallbackUrl, autoInstall, typeLabel) {
        try {
            var response = JSON.parse(jsonText);
            if (Array.isArray(response) && response.length > 0) extractAndFinish(response[0], fallbackUrl, autoInstall);
            else handleError(fallbackUrl, autoInstall, "No " + typeLabel + " found. Using Main.");
        } catch (e) { handleError(fallbackUrl, autoInstall, tr("json_error")); }
    }

    function extractAndFinish(obj, fallbackUrl, autoInstall) {
        var versionTag = obj.tag_name || obj.name || "Unknown"; var foundAsset = "";
        if (obj.assets && obj.assets.length > 0) {
            for (var i = 0; i < obj.assets.length; i++) {
                if (obj.assets[i].name.toLowerCase().endsWith(".zip")) { foundAsset = obj.assets[i].browser_download_url; break; }
            }
        }
        if (foundAsset === "") foundAsset = obj.zipball_url;

        if (foundAsset) {
            rootItem.detectedVersion = versionTag; rootItem.preparedUrl = foundAsset; rootItem.displayUrl = foundAsset; 
            if (!autoInstall) { statusText.text = tr("available") + versionTag; statusText.color = "blue"; } 
            else { statusText.text = tr("found") + versionTag; executeInstallation(foundAsset); }
        } else { handleError(fallbackUrl, autoInstall, tr("no_zip")); }
    }

    function handleError(fallbackUrl, autoInstall, msg) {
        rootItem.detectedVersion = "Main (Dev)"; rootItem.preparedUrl = fallbackUrl; rootItem.displayUrl = fallbackUrl;
        if (!autoInstall) { statusText.text = msg; statusText.color = "#888"; } 
        else { statusText.text = msg; executeInstallation(fallbackUrl); }
    }

    function preCheckVersion() {
        rootItem.detectedVersion = ""; rootItem.preparedUrl = ""; rootItem.displayUrl = ""; statusText.text = "";
        var customUrl = urlField.text.trim();

        if (customUrl !== "") {
            var slug = getRepoSlug(customUrl);
            if (slug !== "") checkGitHubRelease(slug, customUrl, false);
            else { statusText.text = tr("source_direct"); rootItem.preparedUrl = customUrl; rootItem.displayUrl = customUrl; }
            updateTargetDisplay(); return;
        }

        if (pluginCombo.currentIndex !== -1) { startSmartSearch(); updateTargetDisplay(); }
    }

    function updateTargetDisplay() {
        var customUrl = urlField.text.trim();
        if (customUrl !== "") {
            var slug = getRepoSlug(customUrl);
            if (slug !== "") rootItem.targetFolderDisplay = ".../plugins/" + slug.split("/")[1];
            else rootItem.targetFolderDisplay = ".../plugins/CustomPlugin";
        } else if (pluginCombo.currentIndex !== -1) {
            if (rootItem.targetUuid !== "") rootItem.targetFolderDisplay = ".../plugins/" + rootItem.targetUuid;
            else rootItem.targetFolderDisplay = ".../plugins/" + rootItem.targetName.replace(/\s+/g, '');
        } else { rootItem.targetFolderDisplay = "..."; }
    }

    function startProcess() {
        var customUrl = urlField.text.trim();
        statusText.color = "black"; rootItem.isWorking = true; rootItem.isFinished = false;
        progressBar.value = 0; progressBar.indeterminate = true; rootItem.isSelfUpdate = false;

        if (rootItem.installedVersion !== "") rootItem.isSelfUpdate = true;

        if (customUrl !== "") {
             var slug = getRepoSlug(customUrl);
            if (slug !== "") checkGitHubRelease(slug, customUrl, true);
            else executeInstallation(customUrl);
            return;
        } 
        
        if (pluginCombo.currentIndex !== -1) {
            if (rootItem.preparedUrl !== "") executeInstallation(rootItem.preparedUrl);
            else { statusText.text = tr("wait_search"); rootItem.isWorking = false; progressBar.indeterminate = false; }
        } else { statusText.text = tr("select_warn"); statusText.color = "red"; rootItem.isWorking = false; }
    }

    function executeInstallation(finalUrl) {
        rootItem.finalDownloadUrl = finalUrl;
        installTimer.start();
    }

    Timer { id: installTimer; interval: 500; repeat: false; onTriggered: pluginManager.installFromUrl(rootItem.finalDownloadUrl) }

    Connections {
        target: pluginManager
        function onInstallProgress(progress) {
            progressBar.indeterminate = false; progressBar.value = progress; statusText.color = "#333";
            var verInfo = rootItem.detectedVersion !== "" ? "(" + rootItem.detectedVersion + ")" : "";
            if (progress < 1) statusText.text = tr("downloading") + " " + verInfo + ": " + Math.round(progress*100) + "%";
            else statusText.text = tr("extracting");
        }
        function onInstallEnded(uuid, error) {
            rootItem.isWorking = false; progressBar.value = 1.0; progressBar.indeterminate = false;
            if (error && error !== "") { statusText.text = tr("error") + error; statusText.color = "red"; }
            else {
                rootItem.isFinished = true; var successMsg = tr("installed");
                if (rootItem.detectedVersion !== "") successMsg += " " + rootItem.detectedVersion;
                
                // Modification : Suppression du message de redémarrage ici
                statusText.text = successMsg;
                
                statusText.color = "green";
                if (pluginManager.pluginModel) pluginManager.pluginModel.refresh(false);
            }
        }
    }

    Component.onCompleted: {
        detectLanguage();
        iface.addItemToPluginsToolbar(toolbarButton);
    }

    QfToolButton {
        id: toolbarButton
        iconSource: "icon.svg"; iconColor: Theme.mainColor; bgcolor: Theme.darkGray; round: true
        onClicked: {
            pluginCombo.currentIndex = -1; urlField.text = ""; rootItem.isFinished = false;
            rootItem.isWorking = false; progressBar.value = 0; statusText.text = "";
            rootItem.detectedVersion = ""; rootItem.installedVersion = ""; 
            rootItem.displayUrl = ""; rootItem.preparedUrl = ""; rootItem.targetFolderDisplay = "...";
            rootItem.targetUuid = ""; rootItem.targetName = ""; rootItem.targetAuthor = "";
            updateDialog.open(); startGlobalUpdateCheck();
        }
    }

    // =========================================================================
    // INTERFACE GRAPHIQUE
    // =========================================================================

    Dialog {
        id: updateDialog
        parent: mainWindow.contentItem
        modal: true
        padding: 0; topPadding: 0; bottomPadding: 0; leftPadding: 0; rightPadding: 0

        width: Math.min(Math.max(350, mainLayout.implicitWidth + 40), mainWindow.width * 0.90)
        height: mainLayout.implicitHeight + 20 
        anchors.centerIn: parent
        standardButtons: Dialog.NoButton
        
        onClosed: {} 
        
        background: Rectangle { 
            color: "white"; radius: 8; border.width: 2; border.color: Theme.mainColor 
            MouseArea { anchors.fill: parent; onClicked: { mainLayout.forceActiveFocus() } }
        }

        ColumnLayout {
            id: mainLayout
            anchors.fill: parent
            
            // MARGES ET SPACING
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            anchors.leftMargin: 30
            anchors.rightMargin: 30
            spacing: 4 

            // TITRE (Traduit)
            Label { 
                text: tr("title")
                color: "black" 
                font.bold: true; font.pointSize: 16
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 0 
                Layout.bottomMargin: 10 
            }

            RowLayout {
                Layout.fillWidth: true
                ComboBox {
                    id: pluginCombo; Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    font.pixelSize: 14 
                    textRole: "name"; model: pluginManager.availableAppPlugins
                    displayText: currentIndex === -1 ? tr("select_placeholder") : currentText
                    onActivated: { 
                        urlField.text = "";
                        var plugins = pluginManager.availableAppPlugins;
                        if (index >= 0 && index < plugins.length) {
                             var p = plugins[index];
                             rootItem.installedVersion = p.version;
                             rootItem.targetName = p.name;
                             rootItem.targetUuid = p.uuid; 
                             rootItem.targetAuthor = (p.author !== undefined) ? p.author : "";
                        } else {
                             rootItem.installedVersion = ""; rootItem.targetName = ""; rootItem.targetUuid = ""; rootItem.targetAuthor = "";
                        }
                        rootItem.displayUrl = ""; rootItem.preparedUrl = "";
                        preCheckVersion(); 
                    }
                }
                Button {
                    text: "✖"; visible: pluginCombo.currentIndex !== -1; Layout.preferredWidth: 40; 
                    Layout.preferredHeight: 34
                    onClicked: { 
                        pluginCombo.currentIndex = -1; statusText.text = ""; rootItem.detectedVersion = ""; 
                        rootItem.installedVersion = ""; rootItem.displayUrl = ""; updateTargetDisplay(); 
                    }
                }
            }

            TextField {
                visible: rootItem.displayUrl !== ""; Layout.fillWidth: true; text: rootItem.displayUrl; readOnly: true; selectByMouse: true 
                font.pixelSize: 12; color: "#555"; background: Rectangle { color: "#f0f0f0"; radius: 4 }
                
                Layout.preferredHeight: 34
                Layout.minimumHeight: 34
                Layout.maximumHeight: 34
                Layout.preferredWidth: 50 
                verticalAlignment: TextInput.AlignVCenter
            }

            Label { text: tr("or_custom"); font.bold: true; font.pixelSize: 14; Layout.topMargin: 2 }
            
            TextField {
                id: urlField; Layout.fillWidth: true; placeholderText: "https://github.com/user/repo"
                selectByMouse: true; 
                font.pixelSize: 14 
                Layout.preferredHeight: 34
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: { 
                    pluginCombo.currentIndex = -1; rootItem.installedVersion = ""; rootItem.displayUrl = ""; 
                    if(text.length > 10) preCheckVersion(); else updateTargetDisplay();
                }
            }

            Label { text: tr("destination"); font.bold: true; font.pixelSize: 13 ; Layout.topMargin: 2 }
            
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32 
                color: "#e0e0e0"; radius: 4; border.color: "#999"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4
                    Text { text: "📂"; font.pixelSize: 16; verticalAlignment: Text.AlignVCenter }
                    Text { text: rootItem.targetFolderDisplay; font.family: "Courier"; font.pixelSize: 13; color: "#333"; elide: Text.ElideMiddle; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter }
                }
            }

            ProgressBar {
                id: progressBar; Layout.fillWidth: true; Layout.topMargin: 2
                from: 0; to: 1.0; value: 0; indeterminate: rootItem.isWorking && value === 0
                visible: rootItem.isWorking || rootItem.isFinished
                Layout.preferredHeight: 8 
            }

            Text {
                visible: rootItem.installedVersion !== ""
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 14; color: "black"
                text: tr("installed_ver") + rootItem.installedVersion 
            }

            Text {
                id: statusText; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                font.italic: true; color: "#555"; font.weight: rootItem.detectedVersion !== "" ? Font.Bold : Font.Normal
                font.pixelSize: 14
                wrapMode: Text.Wrap; text: ""
            }
            
            TextArea {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.preferredHeight: Math.max(34, contentHeight + 4)
                
                readOnly: true
                text: rootItem.updatesResultText
                color: "#333"
                font.pixelSize: 13
                background: Rectangle { color: "#f9f9f9"; radius: 4; border.color: "#ddd" }
                leftPadding: 4; rightPadding: 4; topPadding: 4; bottomPadding: 4
            }

            Button {
                Layout.alignment: Qt.AlignHCenter; 
                Layout.topMargin: 5
                leftPadding: 20
                rightPadding: 20
                
                enabled: !rootItem.isWorking && (pluginCombo.currentIndex !== -1 || urlField.text !== "")
                background: Rectangle { color: parent.enabled ? Theme.mainColor : "#bdc3c7"; radius: 4 }
                contentItem: Text { 
                    text: rootItem.isWorking ? tr("btn_wait") : (rootItem.preparedUrl !== "" ? tr("btn_install") : tr("btn_update"))
                    color: "white"; font.bold: true; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter 
                }
                onClicked: startProcess()
            }
        }
    }
}
