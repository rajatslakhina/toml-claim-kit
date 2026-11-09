/// How strictly claims are held.
public struct TOMLPolicy: Sendable, Hashable {
    /// Whether a block labeled `toml` counts as a claim that its text is TOML.
    public var checksTOMLBlocks: Bool
    /// Whether unquoted floats with a trailing zero and dotted keys of digits are reported.
    public var reportsCaveats: Bool
    /// Whether output that shows the right value another way (spacing, key order, quote style) holds.
    public var acceptsEquivalent: Bool

    public init(checksTOMLBlocks: Bool = true, reportsCaveats: Bool = true, acceptsEquivalent: Bool = true) {
        self.checksTOMLBlocks = checksTOMLBlocks
        self.reportsCaveats = reportsCaveats
        self.acceptsEquivalent = acceptsEquivalent
    }

    /// Blocks labeled `toml` checked and caveats reported.
    public static let standard = TOMLPolicy()

    /// Only what an answer says in words or shows as output; caveats let through.
    public static let lenient = TOMLPolicy(checksTOMLBlocks: false, reportsCaveats: false)

    /// Output must match character for character.
    public static let strict = TOMLPolicy(acceptsEquivalent: false)
}
