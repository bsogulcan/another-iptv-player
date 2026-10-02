/// A view of a collection whose elements are paired with their position, for a
/// `ForEach` that needs the index of each item (look-ahead prefetch, end-of-page
/// trigger).
///
/// `Array(items.enumerated())` gives the same pairs but copies the whole collection
/// into a new array every time the enclosing body runs, which is every keystroke of a
/// search field for a group of tens of thousands of channels. This wrapper only keeps
/// the base and builds a pair when it is asked for one.
///
///     ForEach(Indexed(items.prefix(visibleCount)), id: \.element.id) { index, channel in ... }
///
/// `offset` counts from zero like `enumerated()`, also for a slice whose indices do
/// not start at zero.
nonisolated struct Indexed<Base: RandomAccessCollection>: RandomAccessCollection where Base.Index == Int {
    typealias Index = Int
    typealias Indices = Range<Int>
    typealias Element = (offset: Int, element: Base.Element)

    let base: Base

    init(base: Base) {
        self.base = base
    }

    init(_ base: Base) {
        self.base = base
    }

    var startIndex: Int { base.startIndex }
    var endIndex: Int { base.endIndex }

    subscript(position: Int) -> Element {
        (offset: position - base.startIndex, element: base[position])
    }
}

extension Indexed: Sendable where Base: Sendable {}
