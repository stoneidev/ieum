// Lists the windows of a running app with their window ids, so one window can be captured on its own:
//   swiftc -O Scripts/window-info.swift -o /tmp/window-info && /tmp/window-info [OwnerName]
//   screencapture -x -o -l <id> /tmp/shot.png
// Never capture the whole screen: the user's other windows (terminals, chats) would be in the picture.
import CoreGraphics
import Foundation
let l = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in l where (w["kCGWindowOwnerName"] as? String) == (CommandLine.arguments.dropFirst().first ?? "Ieum") {
    print(w["kCGWindowNumber"]!, w["kCGWindowName"] ?? "-", w["kCGWindowBounds"]!, w["kCGWindowIsOnscreen"] ?? 0)
}
