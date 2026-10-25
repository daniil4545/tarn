import AppKit

/// A leaf of the layout of one tab: the terminal block or one viewer. It is a placeholder view for
/// `SplitTree`, which wants `NSView & Codable & Identifiable` leaves (`Features/Splits/SplitTree.swift:5`);
/// it is never put into a window. The block is one leaf: its terminals stay in Ghostty's own
/// `SplitTree<Ghostty.SurfaceView>` (`docs/plans/s3-windows.md` section 1).
final class AreaLeaf: NSView, Codable, Identifiable {
    enum Kind: String, Codable {
        case block, viewer
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        super.init(frame: .zero)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
    }
}

/// The layout of a tab: viewers around the terminal block.
typealias AreaTree = SplitTree<AreaLeaf>

extension SplitTree where ViewType == AreaLeaf {
    /// Where a viewer sat before it left the tree: beside which leaf, on which side.
    struct Slot {
        let anchor: AreaLeaf
        let direction: NewDirection
    }

    /// A layout of the block alone.
    static func block(_ leaf: AreaLeaf) -> Self {
        .init(view: leaf)
    }

    var block: AreaLeaf? { first { $0.kind == .block } }

    var viewers: [AreaLeaf] { filter { $0.kind == .viewer } }

    func leaf(id: UUID) -> AreaLeaf? { first { $0.id == id } }

    /// Puts a viewer beside `anchor`; `share` is the part of the room that `anchor` keeps.
    func opening(_ viewer: AreaLeaf, beside anchor: AreaLeaf, direction: NewDirection, share: Double = 0.5) -> Self {
        guard let root, let node = root.node(view: anchor) else { return self }
        let side = AreaEdge(direction)
        let ratio = side.isFirst ? 1 - share : share
        let split = Node.split(.init(
            direction: side.isHorizontal ? .horizontal : .vertical, ratio: ratio,
            left: side.isFirst ? .leaf(view: viewer) : node,
            right: side.isFirst ? node : .leaf(view: viewer)))
        return (try? replacing(node: node, with: split)) ?? self
    }

    func removing(_ leaf: AreaLeaf) -> Self {
        guard let node = root?.node(view: leaf) else { return self }
        return removing(node)
    }

    /// The leaf that takes focus when the user moves in `direction` from `leaf`.
    func neighbor(of leaf: AreaLeaf, _ direction: FocusDirection) -> AreaLeaf? {
        guard let node = root?.node(view: leaf) else { return nil }
        return focusTarget(for: direction, from: node)
    }

    /// The place of `leaf`, for putting it back after a close.
    func slot(of leaf: AreaLeaf) -> Slot? {
        guard let root, let node = root.node(view: leaf), let path = root.path(to: node),
              let last = path.path.last,
              case let .split(parent)? = root.node(at: Path(path: Array(path.path.dropLast())))
        else { return nil }
        let horizontal = parent.direction == .horizontal
        switch last {
        case .left: return Slot(anchor: parent.right.leftmostLeaf(), direction: horizontal ? .left : .up)
        case .right: return Slot(anchor: parent.left.rightmostLeaf(), direction: horizontal ? .right : .down)
        }
    }
}
