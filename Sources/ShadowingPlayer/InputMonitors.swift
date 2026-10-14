import AppKit
import SwiftUI

struct KeyboardRouter: NSViewRepresentable {
    let controller: PlayerController
    func makeNSView(context: Context) -> EventSurface {
        let view = EventSurface()
        view.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view, weak controller] event in
            guard let view, event.window === view.window, let controller,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(event.window?.firstResponder is NSTextView),
                  !(event.window?.firstResponder is NSTextField) else { return event }
            switch event.keyCode {
            case 49: controller.togglePlayback()
            case 123: controller.seekRelative(-5)
            case 124: controller.seekRelative(5)
            case 126: controller.navigateSubtitle(-1)
            case 125: controller.navigateSubtitle(1)
            case 53: controller.clearPractice()
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "r": controller.playSelected(repeating: true)
                case "a": controller.markA()
                case "b": controller.markB()
                case "l": controller.toggleAB()
                default: return event
                }
            }
            return nil
        }
        return view
    }
    func updateNSView(_ view: EventSurface, context: Context) {}
    static func dismantleNSView(_ view: EventSurface, coordinator: ()) { view.removeMonitor() }
}

struct TranscriptScrollMonitor: NSViewRepresentable {
    let onManualScroll: () -> Void
    func makeNSView(context: Context) -> EventSurface {
        let view = EventSurface()
        view.monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { [weak view] event in
            guard let view, event.window === view.window else { return event }
            let point = view.convert(event.locationInWindow, from: nil)
            if view.bounds.contains(point), event.type == .scrollWheel || point.x > view.bounds.width - 18 {
                onManualScroll()
            }
            return event
        }
        return view
    }
    func updateNSView(_ view: EventSurface, context: Context) {}
    static func dismantleNSView(_ view: EventSurface, coordinator: ()) { view.removeMonitor() }
}

final class EventSurface: NSView {
    var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    isolated deinit { removeMonitor() }
}
