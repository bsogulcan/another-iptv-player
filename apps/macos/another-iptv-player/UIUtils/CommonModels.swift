import Foundation

struct IdentifiableURL: Identifiable {
    var id: String { url.absoluteString }
    let url: URL
}

struct TupleWrapper<T: Identifiable, E>: Identifiable {
    var id: T.ID { item.id }
    let item: T
    let extra: E?
}

