import AppKit
import SwiftUI

/// Two native tables share one vertical position. Only visible channels create
/// SwiftUI programme cells, regardless of the playlist's channel count.
struct MacGuideTable: NSViewRepresentable {
  @Environment(\.layoutDirection) var direction
  @Environment(\.locale) var locale
  var layoutVersion: Int = 0
  var headerHours: [Date]? = nil
  let items: [EPGGuideItem]
  let channelWidth: CGFloat
  let timelineWidth: CGFloat
  let horizontalPosition: CGFloat
  let positionRequest: UUID
  let header: AnyView
  let channel: (EPGGuideItem) -> AnyView
  let timeline: (EPGGuideItem) -> AnyView

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSView {
    context.coordinator.container
  }

  func updateNSView(_ view: NSView, context: Context) {
    context.coordinator.update(self)
  }

  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: MacGuideTable
    final class Container: NSView {
      var didLayout: (() -> Void)?
      override func layout() { super.layout(); didLayout?() }
    }
    let container = Container()
    private let labels = NSScrollView()
    private let programmes = NSScrollView()
    private let hours = NSScrollView()
    private let labelTable = NSTableView()
    private let programmeTable = NSTableView()
    private let headerHost: NSHostingView<AnyView>
    private var observers: [NSObjectProtocol] = []
    private var requestedPosition: UUID?
    private var horizontalConstraints: [NSLayoutConstraint] = []
    private let title = NSTextField(labelWithString: "")
    private var appliedDirection: LayoutDirection?
    private var synchronizing = false
    private var channelWidthConstraint: NSLayoutConstraint!

    init(_ parent: MacGuideTable) {
      self.parent = parent
      headerHost = NSHostingView(rootView: parent.header)
      headerHost.sizingOptions = []
      super.init()
      for (scroll, table) in [(labels, labelTable), (programmes, programmeTable)] {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        column.resizingMask = []
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 50
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.selectionHighlightStyle = .none
        table.style = .plain
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.delegate = self
        table.dataSource = self
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
      }
      programmes.hasVerticalScroller = true
      programmes.hasHorizontalScroller = true
      programmes.autohidesScrollers = true
      labels.hasVerticalScroller = false
      labels.hasHorizontalScroller = false
      hours.documentView = headerHost
      hours.drawsBackground = false
      hours.contentView.postsBoundsChangedNotifications = true
      hours.horizontalScrollElasticity = .none
      hours.verticalScrollElasticity = .none
      title.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
      for view in [labels, programmes, hours, title] {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
      }
      channelWidthConstraint = labels.widthAnchor.constraint(equalToConstant: parent.channelWidth)
      NSLayoutConstraint.activate([
        labels.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
        labels.bottomAnchor.constraint(equalTo: programmes.contentView.bottomAnchor),
        channelWidthConstraint,
        programmes.topAnchor.constraint(equalTo: labels.topAnchor),
        programmes.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        hours.topAnchor.constraint(equalTo: container.topAnchor),
        hours.heightAnchor.constraint(equalToConstant: 28),
        hours.leftAnchor.constraint(equalTo: programmes.contentView.leftAnchor),
        hours.rightAnchor.constraint(equalTo: programmes.contentView.rightAnchor),
        title.centerYAnchor.constraint(equalTo: hours.centerYAnchor),
      ])
      container.didLayout = { [weak self] in self?.applyPositionRequest() }
      for scroll in [labels, programmes, hours] {
        observers.append(
          NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
          ) { [weak self, weak scroll] _ in
            guard let self, let scroll else { return }
            self.synchronize(from: scroll)
          })
      }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func setDirection(_ direction: LayoutDirection) {
      guard appliedDirection != direction else { return }
      appliedDirection = direction
      requestedPosition = nil
      NSLayoutConstraint.deactivate(horizontalConstraints)
      if direction == .rightToLeft {
        horizontalConstraints = [
          labels.rightAnchor.constraint(equalTo: container.rightAnchor),
          programmes.rightAnchor.constraint(equalTo: labels.leftAnchor, constant: -1),
          programmes.leftAnchor.constraint(equalTo: container.leftAnchor),
          title.rightAnchor.constraint(equalTo: labels.rightAnchor, constant: -10)
        ]
      } else {
        horizontalConstraints = [
          labels.leftAnchor.constraint(equalTo: container.leftAnchor),
          programmes.leftAnchor.constraint(equalTo: labels.rightAnchor, constant: 1),
          programmes.rightAnchor.constraint(equalTo: container.rightAnchor),
          title.leftAnchor.constraint(equalTo: labels.leftAnchor, constant: 10)
        ]
      }
      NSLayoutConstraint.activate(horizontalConstraints)
    }

    private func hosted(_ view: AnyView) -> AnyView {
      AnyView(view.environment(\.layoutDirection, parent.direction).environment(\.locale, parent.locale))
    }

    func update(_ next: MacGuideTable) {
      let rowsChanged = appliedDirection != next.direction || parent.locale != next.locale
        || parent.items != next.items || parent.channelWidth != next.channelWidth
        || parent.timelineWidth != next.timelineWidth
      let headerChanged = next.headerHours == nil || parent.headerHours != next.headerHours
        || appliedDirection != next.direction || parent.locale != next.locale || parent.timelineWidth != next.timelineWidth
      let programmesChanged = rowsChanged || parent.layoutVersion != next.layoutVersion
      if appliedDirection == nil || parent.locale != next.locale {
        title.stringValue = LocalizationManager.resolveLocalizedString(
          for: "dashboard.channels", languageCode: next.locale.language.languageCode?.identifier)
      }
      parent = next
      setDirection(next.direction)
      if channelWidthConstraint.constant != next.channelWidth {
        channelWidthConstraint.constant = next.channelWidth
      }
      if labelTable.tableColumns[0].width != next.channelWidth {
        labelTable.tableColumns[0].width = next.channelWidth
      }
      if programmeTable.tableColumns[0].width != next.timelineWidth {
        programmeTable.tableColumns[0].width = next.timelineWidth
      }
      if headerChanged {
        headerHost.rootView = hosted(next.header)
        headerHost.frame = NSRect(x: 0, y: 0, width: next.timelineWidth, height: 28)
      }
      // Native tables ask for views only for rows intersecting the viewport.
      if rowsChanged { labelTable.reloadData() }
      if programmesChanged { programmeTable.reloadData() }
      container.needsLayout = true
      synchronize(from: programmes)
    }

    private func applyPositionRequest() {
      let viewport = programmes.contentView.bounds.width
      guard viewport > 0, requestedPosition != parent.positionRequest else { return }
      requestedPosition = parent.positionRequest
      let maxX = max(0, parent.timelineWidth - viewport)
      let fromStart = min(maxX, max(0, parent.horizontalPosition))
      let x = parent.direction == .rightToLeft ? maxX - fromStart : fromStart
      programmes.contentView.scroll(to: NSPoint(x: x, y: programmes.contentView.bounds.minY))
      programmes.reflectScrolledClipView(programmes.contentView)
      synchronize(from: programmes)
    }

    private func synchronize(from source: NSScrollView) {
      guard !synchronizing else { return }
      synchronizing = true
      defer { synchronizing = false }
      if source === hours {
        programmes.contentView.scroll(to: NSPoint(x: hours.contentView.bounds.minX,
          y: programmes.contentView.bounds.minY))
        programmes.reflectScrolledClipView(programmes.contentView)
        return
      }
      let other = source === labels ? programmes : labels
      let target = NSPoint(x: other.contentView.bounds.minX, y: source.contentView.bounds.minY)
      if other.contentView.bounds.origin != target {
        other.contentView.scroll(to: target)
        other.reflectScrolledClipView(other.contentView)
      }
      let headerPosition = NSPoint(x: programmes.contentView.bounds.minX, y: 0)
      if hours.contentView.bounds.origin != headerPosition {
        hours.contentView.scroll(to: headerPosition)
        hours.reflectScrolledClipView(hours.contentView)
      }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
      switch parent.items[row] {
      case .header: 30
      case .channel: 50
      }
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      let id = NSUserInterfaceItemIdentifier("guideRow")
      let content =
        tableView === labelTable
        ? parent.channel(parent.items[row]) : parent.timeline(parent.items[row])
      if let view = tableView.makeView(withIdentifier: id, owner: nil) as? NSHostingView<AnyView> {
        view.rootView = hosted(content)
        return view
      }
      let view = NSHostingView(rootView: hosted(content))
      view.sizingOptions = []
      view.identifier = id
      return view
    }
  }
}
