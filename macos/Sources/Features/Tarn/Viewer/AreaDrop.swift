import AppKit

/// A side of a rectangle.
enum AreaEdge: Equatable {
    case left, right, top, bottom

    init(_ direction: AreaTree.NewDirection) {
        switch direction {
        case .left: self = .left
        case .right: self = .right
        case .up: self = .top
        case .down: self = .bottom
        }
    }

    /// Ghostty's own drop zone (`TerminalSplitDropZone`, `Features/Splits/TerminalSplitTreeView.swift`),
    /// which gives the nearest edge by the corner-to-corner diagonals.
    init(_ zone: TerminalSplitDropZone) {
        switch zone {
        case .left: self = .left
        case .right: self = .right
        case .top: self = .top
        case .bottom: self = .bottom
        }
    }

    var direction: AreaTree.NewDirection {
        switch self {
        case .left: .left
        case .right: .right
        case .top: .up
        case .bottom: .down
        }
    }

    var isHorizontal: Bool { self == .left || self == .right }
    var isFirst: Bool { self == .left || self == .top }
}

/// A file dragged out of a viewer page: a tab of the viewer, or a row of its files tree.
struct FileDrag: Equatable {
    let path: String
    /// The viewer whose page started the drag.
    let viewer: UUID
    /// A tab moves with its edits; a tree row only opens the file.
    let moves: Bool
    /// The tab is the only one of its viewer, so a drop on that viewer changes nothing.
    let sole: Bool
}

/// What is being dragged. A terminal is the surface that Ghostty's grab handle drags.
enum AreaPayload: Equatable {
    case viewer(UUID)
    case terminal(UUID)
    case file(FileDrag)
}

/// What a drop does to the layout.
enum AreaPlan: Equatable {
    /// The pane takes that half of the whole area.
    case half(AreaEdge)
    /// The area is split in two across the corner: the pane takes `edge` of the first or the second
    /// part. The pane halves that part, so a quarter needs an area that is already split.
    case quarter(first: Bool, edge: AreaEdge)
    /// The pane takes the half of one pane that lies on `edge`.
    case beside(UUID, AreaEdge)
    /// The files of the viewer go into that viewer.
    case into(UUID)
}

/// The answer for the pointer: the frame to show and the plan, or a refusal.
struct AreaDropTarget: Equatable {
    let plan: AreaPlan?
    /// In points of the area, origin at the top left.
    let frame: CGRect
    let refusal: String?
}

/// The drop zones of `docs/specs/windows-workspaces.md` section 3a, checked first to last: corner, strip,
/// the middle of a viewer, elsewhere in a pane, the pane itself. Pure math; the overlay draws it.
enum AreaDrop {
    static let corner: CGFloat = 48
    static let strip: CGFloat = 24
    static let tabBar: CGFloat = 32
    static let middle: CGFloat = 0.15
    static let selfRefusal = "Drop on another pane"
    static let splitRefusal = "Split terminals stay together: drag the viewer to the block edge"

    /// Nil means "not ours": the pointer is in the terminal block, where Ghostty's own drop zones work.
    static func target(
        at point: CGPoint, in size: CGSize, tree: AreaTree, payload: AreaPayload, loneTerminal: Bool
    ) -> AreaDropTarget? {
        guard let root = tree.root, let block = tree.block else { return nil }
        let moving: AreaLeaf?
        var refusal: String?
        switch payload {
        case let .viewer(id):
            guard let leaf = tree.leaf(id: id) else { return nil }
            moving = leaf
        case .terminal:
            // Without viewers the block is the whole area: Ghostty's zones are the only ones.
            guard !tree.viewers.isEmpty else { return nil }
            moving = block
            if !loneTerminal { refusal = splitRefusal }
        case .file:
            // A file opens a new viewer or joins one; nothing leaves the layout yet.
            moving = nil
        }
        let rest = (moving.map { tree.removing($0) } ?? tree).root
        if let found = areaZone(at: point, in: size, rest: rest) {
            return AreaDropTarget(plan: refusal == nil ? found.plan : nil, frame: found.frame, refusal: refusal)
        }
        guard let (leaf, rect) = frames(of: root, in: CGRect(origin: .zero, size: size))
            .first(where: { $0.1.contains(point) })
        else { return nil }
        if leaf === moving {
            // A lone terminal over its own block is Ghostty's business.
            return payload == .viewer(leaf.id) ? AreaDropTarget(plan: nil, frame: rect, refusal: selfRefusal) : nil
        }
        let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        let edge = AreaEdge(TerminalSplitDropZone.calculate(at: local, in: rect.size))
        if leaf.kind == .viewer, case .viewer = payload, isMiddle(local, in: rect.size) {
            return AreaDropTarget(plan: .into(leaf.id), frame: rect, refusal: nil)
        }
        if leaf.kind == .viewer, case let .file(drag) = payload {
            // Onto its own viewer a file changes nothing, unless a tab splits off by an edge.
            let own = leaf.id == drag.viewer
            if own, drag.moves ? drag.sole || isMiddle(local, in: rect.size) : isMiddle(local, in: rect.size) {
                return AreaDropTarget(plan: nil, frame: rect, refusal: selfRefusal)
            }
            if !own, isMiddle(local, in: rect.size) {
                return AreaDropTarget(plan: .into(leaf.id), frame: rect, refusal: nil)
            }
        }
        return AreaDropTarget(
            plan: refusal == nil ? .beside(leaf.id, edge) : nil, frame: half(edge, of: rect), refusal: refusal)
    }

    /// The tab bar of a viewer and a box in its middle mean "into this viewer".
    static func isMiddle(_ local: CGPoint, in size: CGSize) -> Bool {
        local.y < tabBar
            || (abs(local.x / size.width - 0.5) < middle && abs(local.y / size.height - 0.5) < middle)
    }

    /// Corners and strips of the whole area. `rest` is the layout without the pane that moves.
    static func areaZone(at point: CGPoint, in size: CGSize, rest: AreaTree.Node?) -> (plan: AreaPlan, frame: CGRect)? {
        let (x, y, w, h) = (point.x, point.y, size.width, size.height)
        guard x >= 0, y >= 0, x <= w, y <= h else { return nil }
        let vertical: AreaEdge? = y < corner ? .top : y > h - corner ? .bottom : nil
        let horizontal: AreaEdge? = x < corner ? .left : x > w - corner ? .right : nil
        let inCorner = vertical != nil && horizontal != nil
        var edge: AreaEdge?
        if !inCorner {
            edge = x < strip ? .left : x > w - strip ? .right : y < strip ? .top : y > h - strip ? .bottom : nil
        }
        guard inCorner || edge != nil else { return nil }
        if let vertical, let horizontal, case let .split(split)? = rest {
            let row = split.direction == .horizontal
            let first = row ? horizontal == .left : vertical == .top
            let start = first ? 0 : split.ratio
            let share = first ? split.ratio : 1 - split.ratio
            let frame = row
                ? CGRect(x: start * w, y: vertical == .top ? 0 : h / 2, width: share * w, height: h / 2)
                : CGRect(x: horizontal == .left ? 0 : w / 2, y: start * h, width: w / 2, height: share * h)
            return (.quarter(first: first, edge: row ? vertical : horizontal), frame)
        }
        let nearest: AreaEdge = min(x, w - x) < min(y, h - y)
            ? (horizontal ?? (x < w / 2 ? .left : .right))
            : (vertical ?? (y < h / 2 ? .top : .bottom))
        let chosen = edge ?? nearest
        return (.half(chosen), half(chosen, of: CGRect(origin: .zero, size: size)))
    }

    static func half(_ edge: AreaEdge, of rect: CGRect) -> CGRect {
        switch edge {
        case .left: CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .right: CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .top: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
        case .bottom: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
        }
    }

    /// Where each leaf sits in `rect`, origin at the top left; the first child of a vertical split is the top.
    static func frames(of node: AreaTree.Node, in rect: CGRect) -> [(AreaLeaf, CGRect)] {
        switch node {
        case let .leaf(view):
            return [(view, rect)]
        case let .split(split):
            let (first, second): (CGRect, CGRect)
            if split.direction == .horizontal {
                let width = rect.width * split.ratio
                first = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
                second = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
            } else {
                let height = rect.height * split.ratio
                first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
                second = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
            }
            return frames(of: split.left, in: first) + frames(of: split.right, in: second)
        }
    }
}

extension SplitTree where ViewType == AreaLeaf {
    /// The layout after `leaf` is dropped by `plan`. An `.into` plan only removes the leaf: the
    /// caller moves its files.
    func placing(_ leaf: AreaLeaf, _ plan: AreaPlan) -> Self {
        let rest = removing(leaf)
        guard let root = rest.root else { return self }
        func join(_ edge: AreaEdge, _ other: Node) -> Node {
            .split(.init(
                direction: edge.isHorizontal ? .horizontal : .vertical, ratio: 0.5,
                left: edge.isFirst ? .leaf(view: leaf) : other,
                right: edge.isFirst ? other : .leaf(view: leaf)))
        }
        switch plan {
        case let .half(edge):
            return .init(root: join(edge, root), zoomed: nil)
        case let .quarter(first, edge):
            guard case let .split(split) = root else { return placing(leaf, .half(edge)) }
            let part = join(edge, first ? split.left : split.right)
            return .init(root: .split(.init(
                direction: split.direction, ratio: split.ratio,
                left: first ? part : split.left, right: first ? split.right : part)), zoomed: nil)
        case let .beside(id, edge):
            guard let destination = rest.leaf(id: id) else { return self }
            return (try? rest.inserting(view: leaf, at: destination, direction: edge.direction)) ?? self
        case .into:
            return rest
        }
    }
}
