import Foundation
import Testing
@testable import another_iptv_player

/// `Indexed`: the pairs `Array(items.enumerated())` would give, without the copy.
@Suite("Indexed collection")
struct IndexedCollectionTests {

    private final class Item {
        let name: String
        init(_ name: String) { self.name = name }
    }

    @Test
    func pairsEveryElementWithItsPosition() {
        let items = ["a", "b", "c", "d"]
        let indexed = Indexed(items)

        #expect(indexed.count == 4)
        #expect(indexed.startIndex == 0)
        #expect(indexed.endIndex == 4)
        #expect(indexed.indices == 0..<4)
        #expect(indexed.map(\.offset) == [0, 1, 2, 3])
        #expect(indexed.map(\.element) == items)
        #expect(indexed[2].offset == 2)
        #expect(indexed[2].element == "c")
    }

    @Test
    func givesTheSamePairsAsEnumerated() {
        let items = (0..<50).map { "item-\($0)" }
        let expected = Array(items.enumerated())
        let indexed = Indexed(base: items)

        #expect(indexed.count == expected.count)
        for (pair, reference) in zip(indexed, expected) {
            #expect(pair.offset == reference.offset)
            #expect(pair.element == reference.element)
        }
    }

    /// A slice keeps the indices of its base. The offset still counts from zero,
    /// as it does for `enumerated()`.
    @Test
    func offsetsOfASliceStartAtZero() {
        let items = ["a", "b", "c", "d", "e"]
        let slice = items[2...]
        let indexed = Indexed(slice)

        #expect(indexed.startIndex == 2)
        #expect(indexed.endIndex == 5)
        #expect(indexed.count == 3)
        #expect(indexed.map(\.offset) == [0, 1, 2])
        #expect(indexed.map(\.element) == ["c", "d", "e"])
        #expect(indexed[3].offset == 1)
        #expect(indexed[3].element == "d")
        #expect(indexed.first?.element == "c")
        #expect(indexed.last?.offset == 2)
    }

    /// The paginated grids iterate a prefix of the full list.
    @Test
    func prefixOfAnArray() {
        let items = Array(0..<1_000)
        let indexed = Indexed(items.prefix(90))

        #expect(indexed.count == 90)
        #expect(indexed.last?.offset == 89)
        #expect(indexed.last?.element == 89)
        #expect(Indexed(items.prefix(0)).isEmpty)
        #expect(Indexed(items.prefix(5_000)).count == 1_000)
    }

    @Test
    func emptyBase() {
        let indexed = Indexed([Int]())

        #expect(indexed.isEmpty)
        #expect(indexed.count == 0)
        #expect(indexed.first == nil)
        #expect(Array(indexed.indices).isEmpty)
    }

    @Test
    func elementsAreTheBaseElementsNotCopies() {
        let items = [Item("one"), Item("two"), Item("three")]
        let indexed = Indexed(items)

        for index in indexed.indices {
            #expect(indexed[index].element === items[index])
        }
        #expect(indexed.base.count == items.count)
    }

    @Test
    func supportsRandomAccess() {
        let indexed = Indexed(Array(10..<20))

        #expect(indexed.index(after: 3) == 4)
        #expect(indexed.index(before: 3) == 2)
        #expect(indexed.index(0, offsetBy: 7) == 7)
        #expect(indexed.distance(from: 2, to: 9) == 7)
        #expect(indexed.reversed().map(\.offset) == Array((0..<10).reversed()))
        #expect(indexed.reversed().first?.element == 19)
        #expect(indexed.dropFirst(8).map(\.element) == [18, 19])
    }

    /// `ForEach` identifies rows through a key path into the pair.
    @Test
    func keyPathIntoThePair() {
        let items = ["x", "y", "z"]
        let ids = Indexed(items).map { $0[keyPath: \.element] }

        #expect(ids == items)
    }
}
