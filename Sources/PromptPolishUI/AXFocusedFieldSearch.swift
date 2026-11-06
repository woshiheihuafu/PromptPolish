import AppKit
import ApplicationServices

/// Used only when the application/system does not expose AXFocusedUIElement.
enum AXFocusedFieldSearch {
    static func find(in window: AXUIElement, maxNodes: Int = 2_048, maxDepth: Int = 64,
                     read: (String, AXUIElement) throws -> CFTypeRef?) -> AXUIElement? {
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        var pending: [(AXUIElement, Int)] = [(window, 0)]
        var visited = Set<Identity>()
        var index = 0
        var candidate: AXUIElement?
        do {
            while index < pending.count {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                let (node, depth) = pending[index]; index += 1
                guard visited.insert(Identity(element: node)).inserted else { continue }
                guard visited.count <= maxNodes, depth <= maxDepth,
                      let role = try read(kAXRoleAttribute, node) as? String else { return nil }
                if [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role),
                   try read(kAXFocusedAttribute, node) as? Bool == true {
                    guard candidate == nil,
                          try read(kAXSubroleAttribute, node) as? String != kAXSecureTextFieldSubrole,
                          let value = try read(kAXWindowAttribute, node),
                          CFGetTypeID(value) == AXUIElementGetTypeID(),
                          CFEqual(value, window) else { return nil }
                    candidate = node
                }
                let children = try read(kAXChildrenAttribute, node) as? [AXUIElement] ?? []
                // Never accept a candidate from a truncated/partly unreadable tree.
                guard children.count <= maxNodes, pending.count + children.count <= maxNodes * 2 else { return nil }
                pending.append(contentsOf: children.map { ($0, depth + 1) })
            }
            return ProcessInfo.processInfo.systemUptime < deadline ? candidate : nil
        } catch { return nil }
    }

    private struct Identity: Hashable {
        let element: AXUIElement
        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }
}
