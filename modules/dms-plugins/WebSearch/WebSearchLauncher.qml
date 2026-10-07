import QtQuick
import Quickshell

Item {
    id: root

    property var pluginService: null
    property string trigger: "!"

    signal itemsChanged()

    Component.onCompleted: {
        if (pluginService)
            trigger = pluginService.loadPluginData("webSearch", "trigger", "!");
    }

    onTriggerChanged: {
        if (pluginService)
            pluginService.savePluginData("webSearch", "trigger", trigger);
    }

    function looksLikeUrl(text) {
        if (/\s/.test(text))
            return false;
        return /^https?:\/\//i.test(text) || /^localhost(:\d+)?(\/|$)/i.test(text) || /^[\w-]+(\.[\w-]+)+(:\d+)?(\/|$)/.test(text);
    }

    // The launcher drops items whose name does not match the query, so the
    // query itself is the name.
    function getItems(query) {
        const text = (query || "").trim();
        if (text === "")
            return [{
                name: "Search the web",
                icon: "firefox",
                comment: "Type a query or a URL",
                action: "",
                categories: ["Web"]
            }];

        const search = {
            name: text,
            icon: "firefox",
            comment: "Search with Firefox",
            action: "search:" + text,
            categories: ["Web"]
        };
        if (!looksLikeUrl(text))
            return [search];

        search.name = "Search for " + text;
        return [{
            name: text,
            icon: "firefox",
            comment: "Open in a new window",
            action: "open:" + text,
            categories: ["Web"]
        }, search];
    }

    function executeItem(item) {
        const action = item?.action || "";
        const sep = action.indexOf(":");
        if (sep < 0)
            return;
        const type = action.slice(0, sep);
        const data = action.slice(sep + 1);
        if (type === "open") {
            const url = /^https?:\/\//i.test(data) ? data : "https://" + data;
            Quickshell.execDetached(["firefox", "--new-window", url]);
        } else {
            Quickshell.execDetached(["firefox", "--search", data]);
        }
    }
}
