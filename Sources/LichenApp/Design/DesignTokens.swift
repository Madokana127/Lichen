import SwiftUI

/// Lichen 设计系统 token（对应 `Preview/DESIGN.md` v0.3）。
///
/// 颜色按 `ColorScheme` 集中在 ``ColorPalette`` 中，视图只取 palette，
/// 不在业务视图里散落 `colorScheme == .dark` 判断。
public enum DesignTokens {
    // MARK: 尺寸

    /// 圆角基础值 12pt。
    public static let radius: CGFloat = 12
    /// 小圆角 6pt。
    public static let radiusSmall: CGFloat = 6
    /// 卡片圆角 16pt。
    public static let radiusLarge: CGFloat = 16
    /// 输入框圆角 22pt。
    public static let radiusXLarge: CGFloat = 22
    /// 胶囊圆角。
    public static let radiusPill: CGFloat = 999

    /// 间距基础值 4pt。
    public static let spacing: CGFloat = 4
    public static let spacing1: CGFloat = 4
    public static let spacing2: CGFloat = 8
    public static let spacing3: CGFloat = 12
    public static let spacing4: CGFloat = 16
    public static let spacing5: CGFloat = 20
    public static let spacing6: CGFloat = 24
    public static let spacing8: CGFloat = 32
    public static let spacing10: CGFloat = 40
    public static let spacing12: CGFloat = 48
    public static let spacing16: CGFloat = 64

    /// 最小可点击尺寸 44pt。
    public static let tapTarget: CGFloat = 44
    /// 原型基准手机宽度。
    public static let phoneWidth: CGFloat = 390

    // MARK: 动效

    /// 200ms `cubic-bezier(0.4, 0, 0.2, 1)`。
    public static let standard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)
    /// 140ms 微交互。
    public static let quick = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.14)
    /// 300ms 面板滑动。
    public static let panel = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)
    /// 560ms 圆形扩散转场。
    public static let reveal = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.56)
    /// 液态浮框轻微回弹。
    public static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    // MARK: 字体

    public static let fontTitle = Font.system(size: 28, weight: .semibold)
    public static let fontGreeting = Font.system(size: 28, weight: .semibold)
    public static let fontHeadline = Font.system(size: 15, weight: .semibold)
    public static let fontBody = Font.system(size: 13.5, weight: .regular)
    public static let fontCallout = Font.system(size: 12, weight: .medium)
    public static let fontCaption = Font.system(size: 11, weight: .regular)
    public static let fontMicro = Font.system(size: 9.5, weight: .regular)
    public static let fontMono = Font.system(size: 10.5, design: .monospaced)

    /// 指定字号的等宽字体。
    public static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }

    // MARK: 配色

    /// 按当前外观返回完整调色板；未知外观回退到明亮。
    public static func colors(for scheme: ColorScheme) -> ColorPalette {
        switch scheme {
        case .dark:
            return .night
        default:
            return .daylight
        }
    }

    /// 控件描边 / 状态 bar 共用的颜色。
    public static func composerLine(for scheme: ColorScheme) -> Color {
        colors(for: scheme).composerLine
    }
}

// MARK: - 调色板

/// 一套完整的 Lichen 配色。
public struct ColorPalette {
    public let bgCanvas: Color
    public let bg: Color
    public let bgDeep: Color
    public let surface: Color
    public let surfaceWarm: Color
    public let surfaceSunken: Color
    public let surfaceHover: Color

    public let ink: Color
    public let ink2: Color
    public let ink3: Color
    public let ink4: Color

    public let line: Color
    public let lineStrong: Color
    public let lineSoft: Color

    public let accent: Color
    public let accentStrong: Color
    public let accentSoft: Color
    public let accentSoft2: Color
    public let accentInk: Color

    public let composerLine: Color
    public let solid: Color
    public let onSolid: Color
    public let danger: Color
    public let warn: Color
    public let codeBackground: Color

    public let scrim: Color
    public let glass: Color
    public let glassFaint: Color
    public let barGlass: Color
    public let shadow: Color

    /// Lichen daylight。
    public static let daylight = ColorPalette(
        bgCanvas: Color(lichenHex: 0xE7E8E2),
        bg: Color(lichenHex: 0xF7F7F3),
        bgDeep: Color(lichenHex: 0xF1F2EC),
        surface: Color(lichenHex: 0xFFFFFF),
        surfaceWarm: Color(lichenHex: 0xFBFBF7),
        surfaceSunken: Color(lichenHex: 0xEFEFE9),
        surfaceHover: Color(lichenHex: 0xF3F4EE),
        ink: Color(lichenHex: 0x1A1E19),
        ink2: Color(lichenHex: 0x3E453C),
        ink3: Color(lichenHex: 0x5F675C),
        ink4: Color(lichenHex: 0x969C91),
        line: Color(lichenHex: 0xE3E4DC),
        lineStrong: Color(lichenHex: 0xCFD2C8),
        lineSoft: Color(lichenHex: 0x1A1E19, opacity: 0.08),
        accent: Color(lichenHex: 0x35614B),
        accentStrong: Color(lichenHex: 0x274B39),
        accentSoft: Color(lichenHex: 0xE7EFE8),
        accentSoft2: Color(lichenHex: 0xD7E4D9),
        accentInk: Color(lichenHex: 0xF7FBF6),
        composerLine: Color(lichenHex: 0x1A1E19, opacity: 0.12),
        solid: Color(lichenHex: 0x1D211C),
        onSolid: Color(lichenHex: 0xF3F4EE),
        danger: Color(lichenHex: 0x9C3B32),
        warn: Color(lichenHex: 0x8A5A12),
        codeBackground: Color(lichenHex: 0xECEEE6),
        scrim: Color(lichenHex: 0x121611, opacity: 0.34),
        glass: Color(lichenHex: 0xFFFFFF, opacity: 0.52),
        glassFaint: Color(lichenHex: 0xFFFFFF, opacity: 0.35),
        barGlass: Color(lichenHex: 0xF7F7F3, opacity: 0.92),
        shadow: Color(lichenHex: 0x141A15, opacity: 0.12)
    )

    /// Lichen night。
    public static let night = ColorPalette(
        bgCanvas: Color(lichenHex: 0x080A08),
        bg: Color(lichenHex: 0x0E100E),
        bgDeep: Color(lichenHex: 0x121512),
        surface: Color(lichenHex: 0x161A16),
        surfaceWarm: Color(lichenHex: 0x141814),
        surfaceSunken: Color(lichenHex: 0x1C211C),
        surfaceHover: Color(lichenHex: 0x20261F),
        ink: Color(lichenHex: 0xF3F4EE),
        ink2: Color(lichenHex: 0xD2D7CB),
        ink3: Color(lichenHex: 0xA2A99B),
        ink4: Color(lichenHex: 0x767E71),
        line: Color(lichenHex: 0x262C26),
        lineStrong: Color(lichenHex: 0x363D34),
        lineSoft: Color(lichenHex: 0xF3F4EE, opacity: 0.10),
        accent: Color(lichenHex: 0x8FC3A0),
        accentStrong: Color(lichenHex: 0xA9D4B7),
        accentSoft: Color(lichenHex: 0x1D2A22),
        accentSoft2: Color(lichenHex: 0x26362B),
        accentInk: Color(lichenHex: 0x0B130D),
        composerLine: Color(lichenHex: 0xF3F4EE, opacity: 0.12),
        solid: Color(lichenHex: 0x1C211C),
        onSolid: Color(lichenHex: 0xF3F4EE),
        danger: Color(lichenHex: 0xE7A79D),
        warn: Color(lichenHex: 0xE4BB74),
        codeBackground: Color(lichenHex: 0x20261F),
        scrim: Color(lichenHex: 0x000000, opacity: 0.56),
        glass: Color(lichenHex: 0xFFFFFF, opacity: 0.06),
        glassFaint: Color(lichenHex: 0xFFFFFF, opacity: 0.04),
        barGlass: Color(lichenHex: 0x0E100E, opacity: 0.90),
        shadow: Color(lichenHex: 0x000000, opacity: 0.55)
    )
}

extension Color {
    /// 从 `0xRRGGBB` 生成 sRGB 颜色。
    init(lichenHex hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - 复用修饰符

/// 卡片：表面色 + 16pt 圆角 + 细描边 + 轻阴影。
public struct LichenCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        let palette = DesignTokens.colors(for: colorScheme)
        content
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.radiusLarge, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            }
            .shadow(color: palette.shadow, radius: 8, x: 0, y: 4)
    }
}

/// 下沉表面：用于思考块、搜索胶囊等。
public struct LichenSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        let palette = DesignTokens.colors(for: colorScheme)
        content
            .background(palette.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous))
    }
}

/// 描边方框：用户提示词与独立卡片的边界。
public struct LichenBorderModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        let palette = DesignTokens.colors(for: colorScheme)
        content.overlay {
            RoundedRectangle(cornerRadius: DesignTokens.radius, style: .continuous)
                .stroke(palette.lineStrong, lineWidth: 1)
        }
    }
}

public extension View {
    /// 统一卡片外观。
    func lichenCard() -> some View {
        modifier(LichenCardModifier())
    }

    /// 统一下沉表面外观。
    func lichenSurface() -> some View {
        modifier(LichenSurfaceModifier())
    }

    /// 统一描边方框外观。
    func lichenBorder() -> some View {
        modifier(LichenBorderModifier())
    }

    /// 把视图中心点写入绑定，供圆形扩散转场使用。
    ///
    /// 坐标取自根坐标空间 `"root"`（由 `RootView` 定义）。
    func revealAnchor(_ anchor: Binding<CGPoint>) -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("root"))
                Color.clear.preference(
                    key: RevealAnchorPreferenceKey.self,
                    value: CGPoint(x: frame.midX, y: frame.midY)
                )
            }
        }
        .onPreferenceChange(RevealAnchorPreferenceKey.self) { value in
            anchor.wrappedValue = value
        }
    }
}

/// 记录触发按钮中心的偏好键。
public struct RevealAnchorPreferenceKey: PreferenceKey {
    public static var defaultValue: CGPoint = .zero

    public static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}
