import Foundation

/// An async sequence whose work begins when iteration begins, not when the
/// value is created.
///
/// `AsyncThrowingStream`'s closure runs at construction. That surprises in two
/// ways that matter here:
///
/// - **#46**: merely building a pull stream would start a multi-gigabyte
///   download, so declining the confirmation could not prevent it. The decline
///   has to be the absence of a call, and with an eager stream even holding one
///   in a variable is a call.
/// - **NFR-P1**: a chat request carries the user's selected text. Constructing
///   a value should not transmit it. Something built and then dropped -- during
///   a UI rebuild, in an error path, in a test -- must send nothing.
///
/// Wrapping the construction in a closure moves both to `makeAsyncIterator`,
/// which runs only when a `for await` actually starts.
public struct LazyStream<Element: Sendable>: AsyncSequence, Sendable {

    public typealias AsyncIterator = AsyncThrowingStream<Element, any Error>.Iterator

    private let start: @Sendable () -> AsyncThrowingStream<Element, any Error>

    init(_ start: @escaping @Sendable () -> AsyncThrowingStream<Element, any Error>) {
        self.start = start
    }

    public func makeAsyncIterator() -> AsyncIterator {
        start().makeAsyncIterator()
    }
}
