import SwiftUI

/// Shared background treatment for the game's "painted plaque" chrome
/// pieces (action buttons, dice chip, bank/dev-card chip): a repeating
/// painted texture fill, clipped to a `RoundedRectangle`, with the gold
/// border drawn natively rather than baked into the texture image, sandwiched
/// between a pair of thin black hairlines (one just outside it, one just
/// inside) rather than the dark-red accent line the reference art originally
/// used on its own painted frames - the black lines read as a crisp
/// engraved edge on the gold itself rather than a second, differently-hued
/// ring next to it.
///
/// The gold+red border used to be part of the image itself - see
/// `UniformActionButton`'s and `GameView.diceChip`'s git history / the
/// "Aug 21 button-border pivot" and "Aug 21 dice-chip border evenness"
/// notes in `design-references/STATUS.md`. A baked-in border only crops
/// evenly when the image's own aspect ratio happens to match the
/// container's real on-screen aspect closely - every single painted-frame
/// chip in this app has needed a second pass once its container's actual
/// proportions were checked for real, so this is now the default way to
/// build one of these instead of something to reach for after the fact.
struct PaintedChromeBackground: View {
    /// Asset name of a *borderless* repeating texture swatch - a plain
    /// crop of the interior of the original painted frame art, well clear
    /// of any border pixels (`dice-fill`, `bank-fill`, `button-fill-*`).
    let textureImageName: String
    let cornerRadius: CGFloat

    private static let gold = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.8, blue: 0.4),
            Color(red: 0.78, green: 0.56, blue: 0.16),
            Color(red: 0.95, green: 0.8, blue: 0.4),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    /// Thin engraved-edge hairline drawn just outside and just inside the
    /// gold/player-color border - internal rather than private since
    /// `playerCardBorder` (below) draws the same pair around the player HUD
    /// cards' borders.
    static let hairline = Color.black
    static let hairlineWidth: CGFloat = 1
    private static let goldWidth: CGFloat = 1.25

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.clear)
            .background(
                Image(textureImageName)
                    .resizable()
                    .scaledToFill()
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Self.hairline, lineWidth: Self.hairlineWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .inset(by: Self.hairlineWidth)
                    .strokeBorder(Self.gold, lineWidth: Self.goldWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .inset(by: Self.hairlineWidth + Self.goldWidth)
                    .strokeBorder(Self.hairline, lineWidth: Self.hairlineWidth)
            )
    }

    /// The same shiny embossed-line look as the `gold` gradient above, just
    /// built from a player's own seat color instead - a light/base/light
    /// vertical ramp rather than a flat fill, so it reads as the same family
    /// of painted-metal border as the buttons/dice/bank chip.
    static func playerGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.75), color, color.opacity(0.75)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The player HUD cards' (`PlayerChip`, `HumanPlayerPanel`) equivalent of a
/// `PaintedChromeBackground` fill - the same repeating wave texture the
/// action buttons use (reused rather than baked into a new asset per
/// civilization: per the "native shapes over baked-in borders" lesson, these
/// cards' aspect isn't fixed - bot chips flex with 1-3 opponents, the human
/// panel flexes with its content - so recoloring one shared texture at
/// render time is the version that can't crop unevenly), laid over a flat
/// `tint` fill in `.overlay` blend mode rather than `colorMultiply` - the
/// source photo is itself a fairly dark navy (its own brightness is most of
/// what makes the trade button read as a deep blue rather than a bright
/// one), so multiplying it straight into another color compounded that
/// darkness into a near-black card. Blending it as texture/contrast on top
/// of the tint instead keeps the tint as the card's actual brightness level
/// and only borrows the photo for its woven pattern.
///
/// Drawn with `Canvas`/`GraphicsContext.Shading.tiledImage` rather than a
/// plain `Image(...).resizable().scaledToFill()` for two reasons: `tiledImage`
/// lets a *crop* of the texture repeat instead of the whole photo, so the
/// wave motif can be packed smaller/denser across a card instead of one
/// `scaledToFill` crop stretching a couple of arcs across the whole thing
/// (the source photo was sized to read right on an action button, not a
/// smaller HUD card); and `Canvas` paints strictly within the size SwiftUI
/// assigns it, with no separate child view that can end up laid out against
/// its own intrinsic image size instead of the frame it was actually given
/// (the earlier `Image`-based version did exactly that once blended - the
/// card's colored fill stopped short of the card's own top edge, leaving the
/// name row sitting on the bare board background above it).
///
/// The crop is a full-height, narrow-width vertical slice of the source
/// photo (`cropWidthFraction`) - not the whole image shrunk down - and its
/// scale is computed per-card so that one slice's height always exactly
/// fills the card's own height. `button-fill-trade` has a real top-to-bottom
/// lighting gradient baked in (it reads as a natural painted highlight when
/// stretched once across a button); tiling the *whole* image at a fixed
/// scale, as an earlier version of this did, repeats that gradient
/// vertically too, and every repeat boundary showed up as a visible seam - a
/// band that suddenly jumps back to the bright top of the next copy partway
/// down the card. A slice that's already exactly one card tall can only ever
/// appear once per column, so the gradient reads as a single smooth light
/// source over the whole card (same as the buttons) while the slice still
/// repeats sideways for the smaller, denser wave pattern.
struct TintedTextureBackground: View {
    let tint: Color
    /// Fraction of the source texture's width each repeating slice crops -
    /// smaller packs more, narrower repeats of the wave motif across the
    /// card.
    var cropWidthFraction: CGFloat = 0.15

    /// `button-fill-trade.png`'s own point size (a "1x"-scale asset, so 1
    /// pixel = 1 point) - needed up front to convert its normalized
    /// `sourceRect` height back into a real scale factor.
    private static let textureSize = CGSize(width: 650, height: 360)

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(tint))
            guard size.height > 0 else { return }
            let scale = size.height / Self.textureSize.height
            context.opacity = 0.6
            context.blendMode = .overlay
            context.fill(
                Path(rect),
                with: .tiledImage(
                    Image("button-fill-trade"),
                    sourceRect: CGRect(x: 0, y: 0, width: cropWidthFraction, height: 1),
                    scale: scale
                )
            )
        }
    }
}

extension View {
    /// The player HUD cards' (`PlayerChip`, `HumanPlayerPanel`) equivalent of
    /// `PaintedChromeBackground`'s gold-between-two-hairlines border: the
    /// seat's own color standing in for gold (still the correct at-a-glance
    /// "whose card is this" signal, so it stands in for gold rather than
    /// being replaced by it), sandwiched between the same pair of thin black
    /// hairlines - one just outside the color, one just inside it - that the
    /// painted plaques use. Kept as a `View` extension rather than folded
    /// into `PaintedChromeBackground` itself since these cards don't use its
    /// textured-fill background - they only want the border half of the
    /// treatment, layered over their own existing solid-color fill.
    func playerCardBorder(color: Color, cornerRadius: CGFloat, lineWidth: CGFloat, hairlineWidth: CGFloat = PaintedChromeBackground.hairlineWidth) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(PaintedChromeBackground.hairline, lineWidth: hairlineWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .inset(by: hairlineWidth)
                    .strokeBorder(PaintedChromeBackground.playerGradient(color), lineWidth: lineWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .inset(by: hairlineWidth + lineWidth)
                    .strokeBorder(PaintedChromeBackground.hairline, lineWidth: hairlineWidth)
            )
    }
}
