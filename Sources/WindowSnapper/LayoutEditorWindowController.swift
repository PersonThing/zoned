import AppKit

/// NSTableView subclass that forwards Delete/Backspace to a callback.
private class DeletableTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // Backspace or Delete
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}

class LayoutEditorWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {

    private var layoutTable: NSTableView!
    private var addLayoutBtn: NSButton!
    private var removeLayoutBtn: NSButton!

    private var nameField: NSTextField!
    private var aspectRatioPopup: NSPopUpButton!
    private var zoneEditorView: ZoneEditorView!

    private var zoneTable: NSTableView!
    private var addZoneBtn: NSButton!
    private var removeZoneBtn: NSButton!

    private var selectedLayoutIndex: Int = 0

    // MARK: - Init

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zone Layouts"
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        super.init(window: window)
        window.delegate = self
        setupUI()
        loadLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // ── Left sidebar: layout list ──────────────────────────────────────
        let sidebarWidth: CGFloat = 180

        let sidebarBox = NSView()
        sidebarBox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sidebarBox)

        let sidebarLabel = makeLabel("LAYOUTS", bold: true, size: 10, color: .secondaryLabelColor)
        sidebarBox.addSubview(sidebarLabel)

        layoutTable = NSTableView()
        layoutTable.headerView = nil
        layoutTable.rowHeight = 28
        layoutTable.dataSource = self
        layoutTable.delegate = self
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.width = sidebarWidth - 20
        layoutTable.addTableColumn(col)
        layoutTable.target = self
        layoutTable.action = #selector(layoutTableClicked)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = layoutTable
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        sidebarBox.addSubview(scrollView)

        addLayoutBtn = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")!, target: self, action: #selector(addLayout))
        addLayoutBtn.bezelStyle = .smallSquare
        addLayoutBtn.translatesAutoresizingMaskIntoConstraints = false
        sidebarBox.addSubview(addLayoutBtn)

        removeLayoutBtn = NSButton(image: NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!, target: self, action: #selector(removeLayout))
        removeLayoutBtn.bezelStyle = .smallSquare
        removeLayoutBtn.translatesAutoresizingMaskIntoConstraints = false
        sidebarBox.addSubview(removeLayoutBtn)

        NSLayoutConstraint.activate([
            sidebarBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            sidebarBox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            sidebarBox.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            sidebarBox.widthAnchor.constraint(equalToConstant: sidebarWidth),

            sidebarLabel.leadingAnchor.constraint(equalTo: sidebarBox.leadingAnchor, constant: 2),
            sidebarLabel.topAnchor.constraint(equalTo: sidebarBox.topAnchor),

            scrollView.leadingAnchor.constraint(equalTo: sidebarBox.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sidebarBox.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: sidebarLabel.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: addLayoutBtn.topAnchor, constant: -4),

            addLayoutBtn.leadingAnchor.constraint(equalTo: sidebarBox.leadingAnchor),
            addLayoutBtn.bottomAnchor.constraint(equalTo: sidebarBox.bottomAnchor),
            addLayoutBtn.widthAnchor.constraint(equalToConstant: 24),
            addLayoutBtn.heightAnchor.constraint(equalToConstant: 24),

            removeLayoutBtn.leadingAnchor.constraint(equalTo: addLayoutBtn.trailingAnchor, constant: 2),
            removeLayoutBtn.bottomAnchor.constraint(equalTo: sidebarBox.bottomAnchor),
            removeLayoutBtn.widthAnchor.constraint(equalToConstant: 24),
            removeLayoutBtn.heightAnchor.constraint(equalToConstant: 24),
        ])

        // ── Right content area ─────────────────────────────────────────────
        let rightBox = NSView()
        rightBox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rightBox)

        NSLayoutConstraint.activate([
            rightBox.leadingAnchor.constraint(equalTo: sidebarBox.trailingAnchor, constant: 12),
            rightBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            rightBox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            rightBox.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        // Name + Aspect Ratio row
        let nameLabel = makeLabel("Name:", bold: false, size: 12, color: .labelColor)
        rightBox.addSubview(nameLabel)

        nameField = NSTextField()
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.target = self
        nameField.action = #selector(nameFieldChanged)
        rightBox.addSubview(nameField)

        let arLabel = makeLabel("Aspect Ratio:", bold: false, size: 12, color: .labelColor)
        rightBox.addSubview(arLabel)

        aspectRatioPopup = NSPopUpButton()
        aspectRatioPopup.translatesAutoresizingMaskIntoConstraints = false
        aspectRatioPopup.target = self
        aspectRatioPopup.action = #selector(aspectRatioChanged)
        rightBox.addSubview(aspectRatioPopup)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor),
            nameLabel.topAnchor.constraint(equalTo: rightBox.topAnchor, constant: 2),

            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.widthAnchor.constraint(equalToConstant: 120),

            arLabel.leadingAnchor.constraint(equalTo: nameField.trailingAnchor, constant: 16),
            arLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            aspectRatioPopup.leadingAnchor.constraint(equalTo: arLabel.trailingAnchor, constant: 6),
            aspectRatioPopup.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
        ])

        // Zone editor grid
        zoneEditorView = ZoneEditorView()
        zoneEditorView.translatesAutoresizingMaskIntoConstraints = false
        zoneEditorView.onLayoutChanged = { [weak self] layout in
            self?.handleLayoutEdited(layout)
        }
        zoneEditorView.onSelectionChanged = { [weak self] in
            guard let self else { return }
            self.zoneTable.reloadData()
            self.reselectZoneTableRow()
            self.updateRemoveButtonState()
        }
        rightBox.addSubview(zoneEditorView)

        // Zone list label
        let zoneListLabel = makeLabel("ZONES", bold: true, size: 10, color: .secondaryLabelColor)
        rightBox.addSubview(zoneListLabel)

        // Zone list table
        let deletableZoneTable = DeletableTableView()
        deletableZoneTable.onDelete = { [weak self] in self?.removeSelectedZone() }
        zoneTable = deletableZoneTable
        zoneTable.headerView = nil
        zoneTable.rowHeight = 22
        zoneTable.dataSource = self
        zoneTable.delegate = self
        let zoneCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("zone"))
        zoneCol.width = 200
        zoneTable.addTableColumn(zoneCol)
        zoneTable.target = self
        zoneTable.action = #selector(zoneTableClicked)

        let zoneScroll = NSScrollView()
        zoneScroll.translatesAutoresizingMaskIntoConstraints = false
        zoneScroll.documentView = zoneTable
        zoneScroll.hasVerticalScroller = true
        zoneScroll.borderType = .bezelBorder
        rightBox.addSubview(zoneScroll)

        // Add/Remove zone buttons
        addZoneBtn = NSButton(title: "+ Zone", target: self, action: #selector(addZone))
        addZoneBtn.bezelStyle = .smallSquare
        addZoneBtn.translatesAutoresizingMaskIntoConstraints = false
        addZoneBtn.controlSize = .small
        addZoneBtn.font = NSFont.systemFont(ofSize: 10)
        rightBox.addSubview(addZoneBtn)

        removeZoneBtn = NSButton(title: "Delete", target: self, action: #selector(removeSelectedZone))
        removeZoneBtn.bezelStyle = .smallSquare
        removeZoneBtn.translatesAutoresizingMaskIntoConstraints = false
        removeZoneBtn.controlSize = .small
        removeZoneBtn.font = NSFont.systemFont(ofSize: 10)
        rightBox.addSubview(removeZoneBtn)

        NSLayoutConstraint.activate([
            zoneEditorView.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor),
            zoneEditorView.trailingAnchor.constraint(equalTo: rightBox.trailingAnchor),
            zoneEditorView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 10),
            zoneEditorView.heightAnchor.constraint(equalTo: zoneEditorView.widthAnchor, multiplier: CGFloat(GRID_ROWS) / CGFloat(GRID_COLS)),

            zoneListLabel.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor, constant: 2),
            zoneListLabel.topAnchor.constraint(equalTo: zoneEditorView.bottomAnchor, constant: 10),

            zoneScroll.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor),
            zoneScroll.trailingAnchor.constraint(equalTo: rightBox.trailingAnchor),
            zoneScroll.topAnchor.constraint(equalTo: zoneListLabel.bottomAnchor, constant: 4),
            zoneScroll.bottomAnchor.constraint(equalTo: addZoneBtn.topAnchor, constant: -4),

            addZoneBtn.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor),
            addZoneBtn.bottomAnchor.constraint(equalTo: rightBox.bottomAnchor),

            removeZoneBtn.leadingAnchor.constraint(equalTo: addZoneBtn.trailingAnchor, constant: 4),
            removeZoneBtn.bottomAnchor.constraint(equalTo: rightBox.bottomAnchor),
        ])

        populateAspectRatioPopup()
    }

    // MARK: - Data Loading

    private func loadLayout() {
        let layouts = LayoutStore.shared.layouts
        guard !layouts.isEmpty else { return }
        selectedLayoutIndex = min(selectedLayoutIndex, layouts.count - 1)
        layoutTable.reloadData()
        layoutTable.selectRowIndexes(IndexSet(integer: selectedLayoutIndex), byExtendingSelection: false)
        loadSelectedLayout()
    }

    private func loadSelectedLayout() {
        let layouts = LayoutStore.shared.layouts
        guard selectedLayoutIndex < layouts.count else { return }
        let layout = layouts[selectedLayoutIndex]
        nameField.stringValue = layout.name
        selectAspectRatioInPopup(layout.aspectRatio)
        zoneEditorView.layout = layout
        zoneEditorView.selectedZoneID = nil
        zoneTable.reloadData()
        updateRemoveButtonState()
    }

    // MARK: - Aspect Ratio Popup

    private func populateAspectRatioPopup() {
        aspectRatioPopup.removeAllItems()
        aspectRatioPopup.addItem(withTitle: "Any (Default)")
        aspectRatioPopup.menu?.items.last?.tag = 0

        var seen = Set<String>()
        for (i, screen) in NSScreen.screens.enumerated() {
            let ar = AspectRatio.fromScreen(screen)
            let key = ar.displayString
            if seen.contains(key) { continue }
            seen.insert(key)
            aspectRatioPopup.addItem(withTitle: "\(ar.displayString) (Screen \(i + 1))")
            aspectRatioPopup.menu?.items.last?.tag = i + 1
            aspectRatioPopup.menu?.items.last?.representedObject = ar
        }
    }

    private func selectAspectRatioInPopup(_ aspectRatio: AspectRatio?) {
        guard let ar = aspectRatio else {
            aspectRatioPopup.selectItem(at: 0)
            return
        }
        for item in aspectRatioPopup.itemArray {
            if let itemAR = item.representedObject as? AspectRatio, itemAR == ar {
                aspectRatioPopup.select(item)
                return
            }
        }
        aspectRatioPopup.addItem(withTitle: ar.displayString)
        aspectRatioPopup.menu?.items.last?.representedObject = ar
        aspectRatioPopup.selectItem(at: aspectRatioPopup.numberOfItems - 1)
    }

    // MARK: - Actions

    @objc private func layoutTableClicked() {
        let row = layoutTable.selectedRow
        guard row >= 0 else { return }
        selectedLayoutIndex = row
        loadSelectedLayout()
    }

    @objc private func nameFieldChanged() {
        var layout = currentLayout()
        layout.name = nameField.stringValue
        saveLayout(layout)
        layoutTable.reloadData()
    }

    @objc private func aspectRatioChanged() {
        var layout = currentLayout()
        if let item = aspectRatioPopup.selectedItem, let ar = item.representedObject as? AspectRatio {
            layout.aspectRatio = ar
        } else {
            layout.aspectRatio = nil
        }
        saveLayout(layout)
    }

    @objc private func addLayout() {
        let newLayout = ZoneLayout(
            name: "New Layout",
            zones: [
                Zone(name: "Full", col: 0, colSpan: GRID_COLS)
            ]
        )
        LayoutStore.shared.addLayout(newLayout)
        selectedLayoutIndex = LayoutStore.shared.layouts.count - 1
        loadLayout()
    }

    @objc private func removeLayout() {
        let layouts = LayoutStore.shared.layouts
        guard layouts.count > 1 else { return }
        let layout = layouts[selectedLayoutIndex]
        LayoutStore.shared.deleteLayout(id: layout.id)
        selectedLayoutIndex = max(0, selectedLayoutIndex - 1)
        loadLayout()
    }

    @objc private func addZone() {
        var layout = currentLayout()
        let newZone = Zone(name: "Full", col: 0, colSpan: GRID_COLS)
        layout.zones.append(newZone)
        saveLayout(layout)
        zoneEditorView.layout = layout
        zoneEditorView.selectedZoneID = newZone.id
        zoneTable.reloadData()
        reselectZoneTableRow()
        updateRemoveButtonState()
    }

    @objc private func removeSelectedZone() {
        zoneEditorView.deleteSelected()
    }

    @objc private func zoneTableClicked() {
        let row = zoneTable.selectedRow
        guard row >= 0 else { return }
        let zones = currentLayout().sortedZones
        guard row < zones.count else { return }
        zoneEditorView.selectedZoneID = zones[row].id
        zoneEditorView.needsDisplay = true
        updateRemoveButtonState()
    }

    // MARK: - Helpers

    private func currentLayout() -> ZoneLayout {
        let layouts = LayoutStore.shared.layouts
        return layouts[selectedLayoutIndex]
    }

    private func saveLayout(_ layout: ZoneLayout) {
        LayoutStore.shared.updateLayout(layout)
        let saved = LayoutStore.shared.layouts[selectedLayoutIndex]
        zoneEditorView.layout = saved
    }

    private func handleLayoutEdited(_ layout: ZoneLayout) {
        saveLayout(layout)
        zoneTable.reloadData()
        reselectZoneTableRow()
    }

    private func reselectZoneTableRow() {
        guard let selectedID = zoneEditorView.selectedZoneID else {
            zoneTable.deselectAll(nil)
            return
        }
        let zones = currentLayout().sortedZones
        if let row = zones.firstIndex(where: { $0.id == selectedID }) {
            zoneTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            zoneTable.deselectAll(nil)
        }
    }

    private func updateRemoveButtonState() {
        removeZoneBtn.isEnabled = (zoneEditorView.selectedZoneID != nil)
        removeLayoutBtn.isEnabled = (LayoutStore.shared.layouts.count > 1)
    }

    private func makeLabel(_ text: String, bold: Bool, size: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.textColor = color
        return label
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == layoutTable {
            return LayoutStore.shared.layouts.count
        }
        return currentLayout().sortedZones.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == layoutTable {
            let layouts = LayoutStore.shared.layouts
            guard row < layouts.count else { return nil }
            let layout = layouts[row]
            let cell = NSTextField(labelWithString: layout.name)
            cell.font = NSFont.systemFont(ofSize: 12)
            return cell
        }

        // Zone table
        let zones = currentLayout().sortedZones
        guard row < zones.count else { return nil }
        let zone = zones[row]
        let color = GridView.zoneColors[row % GridView.zoneColors.count]
        let desc = "\(zone.colSpan)×\(zone.rowSpan)"
        let cell = NSTextField(labelWithString: "● \(zone.name)  (\(desc))")
        cell.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        cell.textColor = color
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        if tv == layoutTable {
            layoutTableClicked()
        }
    }
}
