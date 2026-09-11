/// What the renderer has done since it was last reset, for the contracts that leave
/// no other evidence outside the actor.
///
/// A cache that has stopped caching and a Plan rebuilt once per Tile are both
/// invisible from the pixels: the render is correct either way and only the clock
/// says otherwise, which is exactly what a test cannot assert. These counters are the
/// deliberate exception to asserting external behaviour — they exist so a regression
/// in either is caught by a test rather than by a user with a warm phone.
public struct RenderCounters: Sendable, Equatable {
    /// Render Plans resolved from a Profile and settings. One per Preview frame, and
    /// one per Export however many Tiles the Export divides into.
    public var plansBuilt = 0
    /// Times a set of Tile-sized scratch textures was allocated: the Preview's
    /// ping-pong pair, the Scattering Pyramid, or the MTF Pass's three. A warm
    /// Renderer rendering the same dimensions allocates none.
    public var tileTextureAllocations = 0
    public init() {}
}
